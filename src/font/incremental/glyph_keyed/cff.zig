//! Glyph-keyed reconstruction of terminal CFF/CFF2 CharStrings INDEX data.

const std = @import("std");
const offsets = @import("offsets.zig");

pub const Kind = enum { cff, cff2 };

pub fn apply(
    allocator: std.mem.Allocator,
    table: []const u8,
    charstrings_offset: usize,
    glyph_count: usize,
    replacements: []const ?[]const u8,
    kind: Kind,
    max_output_size: usize,
) ![]u8 {
    if (charstrings_offset > table.len or glyph_count != replacements.len) {
        return error.BadSfnt;
    }
    const count_width: usize = if (kind == .cff) 2 else 4;
    if (count_width > table.len - charstrings_offset) return error.BadSfnt;
    const count: usize = if (kind == .cff)
        readU16(table, charstrings_offset)
    else
        readU32(table, charstrings_offset);
    if (count != glyph_count or count == 0) return error.BadSfnt;
    const off_size_offset = charstrings_offset + count_width;
    if (off_size_offset >= table.len) return error.BadSfnt;
    const encoding = cffEncoding(table[off_size_offset]) orelse return error.BadSfnt;
    const offset_count = count + 1;
    const offset_bytes = std.math.mul(usize, offset_count, encoding.width()) catch
        return error.BadSfnt;
    const offsets_start = off_size_offset + 1;
    if (offset_bytes > table.len - offsets_start) return error.BadSfnt;
    const object_start = offsets_start + offset_bytes;
    const base_offsets = try allocator.alloc(u32, offset_count);
    defer allocator.free(base_offsets);
    for (base_offsets, 0..) |*value, index| {
        const encoded = readSized(table, offsets_start + index * encoding.width(), encoding.width());
        if (encoded == 0) return error.BadSfnt;
        value.* = encoded - 1;
    }
    if (base_offsets[offset_count - 1] > table.len - object_start or
        object_start + base_offsets[offset_count - 1] != table.len)
    {
        // IFT requires CharStrings to be terminal and non-overlapping, which
        // makes replacing its INDEX safe without rewriting Top DICT offsets.
        return error.BadSfnt;
    }
    const rebuilt = try offsets.rebuild(
        allocator,
        table[object_start..],
        base_offsets,
        replacements,
        encoding,
        &.{ .cff_1, .cff_2, .cff_3, .cff_4 },
        max_output_size,
    );
    defer rebuilt.deinit(allocator);
    const new_offset_bytes = rebuilt.offsets.len * rebuilt.encoding.width();
    const new_index_len = std.math.add(
        usize,
        count_width + 1 + new_offset_bytes,
        rebuilt.data.len,
    ) catch return error.BadSfnt;
    const total = std.math.add(usize, charstrings_offset, new_index_len) catch
        return error.BadSfnt;
    if (total > max_output_size) return error.BadSfnt;
    const output = try allocator.alloc(u8, total);
    errdefer allocator.free(output);
    @memcpy(output[0..charstrings_offset], table[0..charstrings_offset]);
    if (kind == .cff) writeU16(output, charstrings_offset, @intCast(count)) else writeU32(output, charstrings_offset, @intCast(count));
    output[off_size_offset] = @intCast(rebuilt.encoding.width());
    try offsets.writeEncodedOffsets(output, offsets_start, rebuilt.offsets, rebuilt.encoding);
    const new_object_start = offsets_start + new_offset_bytes;
    @memcpy(output[new_object_start..], rebuilt.data);
    return output;
}

fn cffEncoding(width: u8) ?offsets.Encoding {
    return switch (width) {
        1 => .cff_1,
        2 => .cff_2,
        3 => .cff_3,
        4 => .cff_4,
        else => null,
    };
}
fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}
fn readU32(data: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}
fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}
fn writeU32(data: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, data[offset..][0..4], value, .big);
}
fn readSized(data: []const u8, offset: usize, width: usize) u32 {
    var value: u32 = 0;
    for (data[offset..][0..width]) |byte| value = (value << 8) | byte;
    return value;
}
