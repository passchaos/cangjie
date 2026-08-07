const std = @import("std");
const bin = @import("../binary.zig");
const glyph_mod = @import("../glyph.zig");

pub const Error = error{
    BadSfnt,
    UnsupportedCmap,
} || error{EndOfStream};

pub const Mapping = struct {
    codepoint: u21,
    glyph_id: glyph_mod.GlyphId,
};

const cmap_format8_is32_offset = 12;
const cmap_format8_is32_len = 8192;
const cmap_format8_groups_offset = cmap_format8_is32_offset + cmap_format8_is32_len + 4;

/// Return the next non-missing scalar-to-glyph mapping after `after`.
///
/// The caller is expected to have validated the cmap table and selected subtable
/// immediately before this call. These readers still keep local bounds checks so
/// the iterator remains safe when used by future parsing code or tests.
pub fn next(data: []const u8, offset: usize, length: usize, format: u16, after: ?u21) Error!?Mapping {
    return switch (format) {
        0 => try nextFormat0(data, offset, length, after),
        2 => try nextScannedBmp(data, offset, length, format, after),
        4 => try nextFormat4(data, offset, length, after),
        6 => try nextFormat6(data, offset, length, after),
        8 => try nextSequentialGroups(data, offset, cmap_format8_groups_offset, length, after),
        10 => try nextFormat10(data, offset, length, after),
        12 => try nextSequentialGroups(data, offset, 16, length, after),
        13 => try nextFormat13(data, offset, length, after),
        else => error.UnsupportedCmap,
    };
}

fn nextFormat0(data: []const u8, offset: usize, length: usize, after: ?u21) Error!?Mapping {
    if (offset > data.len or length > data.len - offset or length != 262) return error.BadSfnt;
    var code: u32 = if (after) |cp| @as(u32, cp) + 1 else 0;
    while (code <= 0xff) : (code += 1) {
        const glyph_id = data[offset + 6 + @as(usize, @intCast(code))];
        if (glyph_id != 0) return .{ .codepoint = @intCast(code), .glyph_id = glyph_id };
    }
    return null;
}

fn nextScannedBmp(data: []const u8, offset: usize, length: usize, format: u16, after: ?u21) Error!?Mapping {
    var code = firstScalarAfter(after) orelse return null;
    while (code <= 0xffff) {
        const glyph_id = switch (format) {
            2 => try glyphIndexFormat2(data, offset, length, code),
            else => unreachable,
        };
        if (glyph_id != 0) return .{ .codepoint = code, .glyph_id = glyph_id };
        code = nextScalarAfter(code) orelse return null;
    }
    return null;
}

fn glyphIndexFormat2(data: []const u8, offset: usize, length: usize, codepoint: u21) Error!glyph_mod.GlyphId {
    if (codepoint > 0xffff) return 0;
    const table_end = try checkedTableEnd(data, offset, length);
    if (length < 526) return error.BadSfnt;

    const high_byte: u8 = @intCast((codepoint >> 8) & 0xff);
    const low_byte: u8 = @intCast(codepoint & 0xff);
    const key = try bin.readU16At(data, offset + 6 + @as(usize, high_byte) * 2);
    if ((key & 7) != 0) return error.BadSfnt;
    const subheader_index = key / 8;
    const subheader_offset = offset + 6 + 512 + @as(usize, subheader_index) * 8;
    if (subheader_offset + 8 > table_end) return error.BadSfnt;

    if (high_byte != 0 and subheader_index == 0) return 0;

    const first_code = try bin.readU16At(data, subheader_offset);
    const entry_count = try bin.readU16At(data, subheader_offset + 2);
    const id_delta = try bin.readI16At(data, subheader_offset + 4);
    const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
    const char_code = @as(u16, low_byte);
    if (char_code < first_code) return 0;
    const entry_index = @as(usize, char_code - first_code);
    if (entry_index >= entry_count) return 0;

    const glyph_offset = subheader_offset + 6 + @as(usize, id_range_offset) + entry_index * 2;
    if (glyph_offset + 2 > table_end) return error.BadSfnt;
    const glyph = try bin.readU16At(data, glyph_offset);
    if (glyph == 0) return 0;
    return addU16Wrapping(glyph, id_delta);
}

fn nextFormat4(data: []const u8, offset: usize, length: usize, after: ?u21) Error!?Mapping {
    const table_end = try checkedTableEnd(data, offset, length);
    if (length < 16) return error.BadSfnt;
    const seg_count_x2 = try bin.readU16At(data, offset + 6);
    if (seg_count_x2 == 0 or (seg_count_x2 & 1) != 0) return error.BadSfnt;
    const seg_count = @as(usize, seg_count_x2 / 2);
    if (length < 16 + seg_count * 8) return error.BadSfnt;

    const end_codes = offset + 14;
    const start_codes = end_codes + seg_count * 2 + 2;
    const id_deltas = start_codes + seg_count * 2;
    const id_range_offsets = id_deltas + seg_count * 2;
    const minimum = if (after) |cp| @as(u32, cp) + 1 else 0;

    for (0..seg_count) |index| {
        const start = try bin.readU16At(data, start_codes + index * 2);
        const end = try bin.readU16At(data, end_codes + index * 2);
        if (end < start) return error.BadSfnt;
        if (end == 0xffff and start == 0xffff) break;
        var code = firstScalarAtLeast(@max(@as(u32, start), minimum)) orelse return null;
        if (code > end) continue;
        const delta = try bin.readI16At(data, id_deltas + index * 2);
        const range_offset = try bin.readU16At(data, id_range_offsets + index * 2);
        while (code <= end) {
            const cp16: u16 = @intCast(code);
            const glyph_id = if (range_offset == 0) blk: {
                break :blk addU16Wrapping(cp16, delta);
            } else blk: {
                const glyph_offset = id_range_offsets + index * 2 + @as(usize, range_offset) + (@as(usize, cp16 - start) * 2);
                if (glyph_offset + 2 > table_end) return error.BadSfnt;
                const raw = try bin.readU16At(data, glyph_offset);
                break :blk if (raw == 0) 0 else addU16Wrapping(raw, delta);
            };
            if (glyph_id != 0) return .{ .codepoint = code, .glyph_id = glyph_id };
            code = nextScalarAfter(code) orelse return null;
        }
    }
    return null;
}

fn nextFormat6(data: []const u8, offset: usize, length: usize, after: ?u21) Error!?Mapping {
    _ = try checkedTableEnd(data, offset, length);
    if (length < 10) return error.BadSfnt;
    const first_code = try bin.readU16At(data, offset + 6);
    const entry_count = try bin.readU16At(data, offset + 8);
    if (@as(usize, entry_count) * 2 != length - 10) return error.BadSfnt;

    const minimum = if (after) |cp| @as(u32, cp) + 1 else 0;
    var code = firstScalarAtLeast(@max(@as(u32, first_code), minimum)) orelse return null;
    const end = @as(u32, first_code) + @as(u32, entry_count);
    while (code < end) {
        const glyph_id = try bin.readU16At(data, offset + 10 + @as(usize, code - first_code) * 2);
        if (glyph_id != 0) return .{ .codepoint = code, .glyph_id = glyph_id };
        code = nextScalarAfter(code) orelse return null;
    }
    return null;
}

fn nextFormat10(data: []const u8, offset: usize, length: usize, after: ?u21) Error!?Mapping {
    _ = try checkedTableEnd(data, offset, length);
    if (length < 20 or (length - 20) % 2 != 0) return error.BadSfnt;
    const first_code = try bin.readU32At(data, offset + 12);
    const entry_count = try bin.readU32At(data, offset + 16);
    if (@as(u64, entry_count) * 2 != @as(u64, length - 20)) return error.BadSfnt;

    const minimum = if (after) |cp| @as(u32, cp) + 1 else 0;
    var code = firstScalarAtLeast(@max(first_code, minimum)) orelse return null;
    const end = @as(u64, first_code) + @as(u64, entry_count);
    while (@as(u64, code) < end) {
        const glyph_id = try bin.readU16At(data, offset + 20 + @as(usize, code - first_code) * 2);
        if (glyph_id != 0) return .{ .codepoint = code, .glyph_id = glyph_id };
        code = nextScalarAfter(code) orelse return null;
    }
    return null;
}

fn nextSequentialGroups(data: []const u8, offset: usize, groups_offset: usize, length: usize, after: ?u21) Error!?Mapping {
    const table_end = try checkedTableEnd(data, offset, length);
    if (groups_offset < 4 or groups_offset > length) return error.BadSfnt;
    const group_count: usize = @intCast(try bin.readU32At(data, offset + groups_offset - 4));
    if (group_count > (table_end - (offset + groups_offset)) / 12) return error.BadSfnt;
    const minimum = if (after) |cp| @as(u32, cp) + 1 else 0;
    for (0..group_count) |index| {
        const group = offset + groups_offset + index * 12;
        const start = try bin.readU32At(data, group);
        const end = try bin.readU32At(data, group + 4);
        if (end < start) return error.BadSfnt;
        const first_glyph = try bin.readU32At(data, group + 8);
        var code = firstScalarAtLeast(@max(start, minimum)) orelse return null;
        if (code > end) continue;
        if (first_glyph == 0 and code == start) {
            code = nextScalarAfter(code) orelse return null;
            if (code > end) continue;
        }
        const glyph_id = first_glyph + (code - start);
        if (glyph_id > std.math.maxInt(glyph_mod.GlyphId)) return error.BadSfnt;
        if (glyph_id != 0) return .{ .codepoint = code, .glyph_id = @intCast(glyph_id) };
    }
    return null;
}

fn nextFormat13(data: []const u8, offset: usize, length: usize, after: ?u21) Error!?Mapping {
    _ = try checkedTableEnd(data, offset, length);
    if (length < 16 or (length - 16) % 12 != 0) return error.BadSfnt;
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    if (@as(u64, group_count) * 12 != @as(u64, length - 16)) return error.BadSfnt;

    const minimum = if (after) |cp| @as(u32, cp) + 1 else 0;
    for (0..group_count) |index| {
        const group = offset + 16 + index * 12;
        const start = try bin.readU32At(data, group);
        const end = try bin.readU32At(data, group + 4);
        if (end < start) return error.BadSfnt;
        const glyph_id = try bin.readU32At(data, group + 8);
        if (glyph_id == 0) continue;
        const code = firstScalarAtLeast(@max(start, minimum)) orelse return null;
        if (code > end) continue;
        if (glyph_id > std.math.maxInt(glyph_mod.GlyphId)) return error.BadSfnt;
        return .{ .codepoint = code, .glyph_id = @intCast(glyph_id) };
    }
    return null;
}

fn checkedTableEnd(data: []const u8, offset: usize, length: usize) Error!usize {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    return offset + length;
}

fn addU16Wrapping(value: u16, delta: i16) u16 {
    return @as(u16, @bitCast(@as(i16, @bitCast(value)) +% delta));
}

fn firstScalarAfter(after: ?u21) ?u21 {
    const start = if (after) |cp| @as(u32, cp) + 1 else 0;
    return firstScalarAtLeast(start);
}

fn nextScalarAfter(codepoint: u21) ?u21 {
    return firstScalarAtLeast(@as(u32, codepoint) + 1);
}

fn firstScalarAtLeast(start: u32) ?u21 {
    var code = start;
    if (code >= 0xd800 and code <= 0xdfff) code = 0xe000;
    if (code > 0x10ffff) return null;
    return @intCast(code);
}
