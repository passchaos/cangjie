//! Glyph-keyed reconstruction of `gvar`'s offset array and glyph data.

const std = @import("std");
const offsets = @import("offsets.zig");

pub fn apply(
    allocator: std.mem.Allocator,
    table: []const u8,
    glyph_count: usize,
    replacements: []const ?[]const u8,
    max_output_size: usize,
) ![]u8 {
    if (table.len < 20 or glyph_count != replacements.len or
        readU16(table, 0) != 1 or readU16(table, 2) != 0 or
        readU16(table, 12) != glyph_count) return error.BadSfnt;
    const flags = readU16(table, 14);
    if ((flags & ~@as(u16, 1)) != 0) return error.BadSfnt;
    const initial: offsets.Encoding = if ((flags & 1) != 0) .long else .short_div_by_two;
    const offset_count = glyph_count + 1;
    const offsets_len = std.math.mul(usize, offset_count, initial.width()) catch
        return error.BadSfnt;
    if (offsets_len > table.len - 20) return error.BadSfnt;
    const glyph_data_offset: usize = readU32(table, 16);
    if (glyph_data_offset < 20 + offsets_len or glyph_data_offset > table.len) {
        return error.BadSfnt;
    }
    const base_offsets = try allocator.alloc(u32, offset_count);
    defer allocator.free(base_offsets);
    for (base_offsets, 0..) |*value, index| {
        const offset = 20 + index * initial.width();
        value.* = switch (initial) {
            .short_div_by_two => @as(u32, readU16(table, offset)) * 2,
            .long => readU32(table, offset),
            else => unreachable,
        };
    }
    const base_data = table[glyph_data_offset..];
    const rebuilt = try offsets.rebuild(
        allocator,
        base_data,
        base_offsets,
        replacements,
        initial,
        &.{ .short_div_by_two, .long },
        max_output_size,
    );
    defer rebuilt.deinit(allocator);

    const axis_count: usize = readU16(table, 4);
    const shared_tuple_count: usize = readU16(table, 6);
    const shared_tuple_offset: usize = readU32(table, 8);
    const shared_len = std.math.mul(
        usize,
        std.math.mul(usize, axis_count, shared_tuple_count) catch return error.BadSfnt,
        2,
    ) catch return error.BadSfnt;
    if (shared_tuple_count != 0 and
        (shared_tuple_offset < 20 + offsets_len or
            shared_tuple_offset > table.len or
            shared_len > table.len - shared_tuple_offset)) return error.BadSfnt;
    // IFT permits the source shared-tuple and glyph-data regions to overlap or
    // appear out of canonical order. Copy each authenticated region into its
    // own output object below; this deliberately duplicates overlap and emits
    // the canonical header -> offsets -> shared tuples -> glyph data order.
    const shared = if (shared_tuple_count == 0)
        table[0..0]
    else
        table[shared_tuple_offset .. shared_tuple_offset + shared_len];

    const new_offsets_len = rebuilt.offsets.len * rebuilt.encoding.width();
    const new_shared_offset = 20 + new_offsets_len;
    const new_data_offset = std.math.add(usize, new_shared_offset, shared.len) catch
        return error.BadSfnt;
    const total = std.math.add(usize, new_data_offset, rebuilt.data.len) catch
        return error.BadSfnt;
    if (total > max_output_size or total > std.math.maxInt(u32)) return error.BadSfnt;
    const output = try allocator.alloc(u8, total);
    errdefer allocator.free(output);
    @memcpy(output[0..20], table[0..20]);
    writeU32(output, 8, @intCast(new_shared_offset));
    writeU16(output, 14, if (rebuilt.encoding == .long) flags | 1 else flags & ~@as(u16, 1));
    writeU32(output, 16, @intCast(new_data_offset));
    try offsets.writeEncodedOffsets(output, 20, rebuilt.offsets, rebuilt.encoding);
    @memcpy(output[new_shared_offset..][0..shared.len], shared);
    @memcpy(output[new_data_offset..], rebuilt.data);
    return output;
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
