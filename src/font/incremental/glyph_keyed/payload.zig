//! Structural reader for the decompressed IFT `GlyphPatches` payload.
//!
//! Offset32 values in this format are absolute from the beginning of the
//! decompressed payload. The reader authenticates the complete glyph, table,
//! and offset directories before any replacement is exposed to table-specific
//! reconstruction code.

const std = @import("std");

pub const Error = error{BadSfnt};

pub const View = struct {
    data: []const u8,
    glyph_count: usize,
    table_count: usize,
    glyph_id_width: usize,
    glyph_ids_offset: usize,
    tables_offset: usize,
    offsets_offset: usize,

    pub fn glyphId(self: View, index: usize) Error!u32 {
        if (index >= self.glyph_count) return error.BadSfnt;
        const offset = self.glyph_ids_offset + index * self.glyph_id_width;
        return switch (self.glyph_id_width) {
            2 => readU16(self.data, offset),
            3 => readU24(self.data, offset),
            else => unreachable,
        };
    }

    pub fn tableTag(self: View, index: usize) Error![4]u8 {
        if (index >= self.table_count) return error.BadSfnt;
        const offset = self.tables_offset + index * 4;
        return self.data[offset..][0..4].*;
    }

    pub fn glyphData(
        self: View,
        table_index: usize,
        glyph_index: usize,
    ) Error![]const u8 {
        if (table_index >= self.table_count or glyph_index >= self.glyph_count) {
            return error.BadSfnt;
        }
        const index = table_index * self.glyph_count + glyph_index;
        const start: usize = readU32(self.data, self.offsets_offset + index * 4);
        const end: usize = readU32(self.data, self.offsets_offset + (index + 1) * 4);
        if (end < start or end > self.data.len) return error.BadSfnt;
        return self.data[start..end];
    }
};

pub fn parse(data: []const u8, flags: u8) Error!View {
    if ((flags & ~@as(u8, 0x01)) != 0 or data.len < 5) return error.BadSfnt;
    const glyph_count: usize = readU32(data, 0);
    const table_count: usize = data[4];
    const glyph_id_width: usize = if ((flags & 0x01) != 0) 3 else 2;
    const glyph_ids_len = std.math.mul(usize, glyph_count, glyph_id_width) catch
        return error.BadSfnt;
    const tables_offset = std.math.add(usize, 5, glyph_ids_len) catch
        return error.BadSfnt;
    const tables_len = std.math.mul(usize, table_count, 4) catch
        return error.BadSfnt;
    const offsets_offset = std.math.add(usize, tables_offset, tables_len) catch
        return error.BadSfnt;
    const data_offset_count = std.math.add(
        usize,
        std.math.mul(usize, glyph_count, table_count) catch return error.BadSfnt,
        1,
    ) catch return error.BadSfnt;
    const offsets_len = std.math.mul(usize, data_offset_count, 4) catch
        return error.BadSfnt;
    const metadata_end = std.math.add(usize, offsets_offset, offsets_len) catch
        return error.BadSfnt;
    if (metadata_end > data.len) return error.BadSfnt;

    var previous_gid: ?u32 = null;
    for (0..glyph_count) |index| {
        const offset = 5 + index * glyph_id_width;
        const glyph_id = if (glyph_id_width == 2)
            @as(u32, readU16(data, offset))
        else
            readU24(data, offset);
        if (previous_gid) |previous| if (glyph_id <= previous) return error.BadSfnt;
        previous_gid = glyph_id;
    }

    var previous_tag: ?[4]u8 = null;
    for (0..table_count) |index| {
        const offset = tables_offset + index * 4;
        const tag = data[offset..][0..4].*;
        if (previous_tag) |previous| {
            if (std.mem.order(u8, &previous, &tag) != .lt) return error.BadSfnt;
        }
        previous_tag = tag;
    }

    var previous_offset: usize = metadata_end;
    for (0..data_offset_count) |index| {
        const current: usize = readU32(data, offsets_offset + index * 4);
        // Glyph data must not alias the directories that define its meaning.
        if (current < previous_offset or current > data.len) return error.BadSfnt;
        previous_offset = current;
    }

    return .{
        .data = data,
        .glyph_count = glyph_count,
        .table_count = table_count,
        .glyph_id_width = glyph_id_width,
        .glyph_ids_offset = 5,
        .tables_offset = tables_offset,
        .offsets_offset = offsets_offset,
    };
}

fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readU24(data: []const u8, offset: usize) u32 {
    return (@as(u32, data[offset]) << 16) |
        (@as(u32, data[offset + 1]) << 8) | data[offset + 2];
}

fn readU32(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "glyph patch payload reads table-major replacement data" {
    const bytes = [_]u8{
        0, 0, 0, 2, 1, // two glyphs, one table
        0,   2,   0,   7, // glyph ids
        'g', 'l', 'y', 'f',
        0,   0,   0,   25,
        0,   0,   0,   28,
        0,   0,   0,   30,
        'a', 'b', 'c', 'd',
        'e',
    };
    const parsed = try parse(&bytes, 0);
    try std.testing.expectEqual(@as(u32, 2), try parsed.glyphId(0));
    try std.testing.expectEqualStrings("glyf", &(try parsed.tableTag(0)));
    try std.testing.expectEqualStrings("abc", try parsed.glyphData(0, 0));
    try std.testing.expectEqualStrings("de", try parsed.glyphData(0, 1));
}

test "glyph patch payload rejects directory aliases and unordered keys" {
    var bytes = [_]u8{
        0,   0,   0,   2, 1,
        0,   7,   0,   7, 'g',
        'l', 'y', 'f', 0, 0,
        0,   25,  0,   0, 0,
        25,  0,   0,   0, 25,
    };
    try std.testing.expectError(error.BadSfnt, parse(&bytes, 0));
    bytes[8] = 8;
    std.mem.writeInt(u32, bytes[17..21], 0, .big);
    try std.testing.expectError(error.BadSfnt, parse(&bytes, 0));
}
