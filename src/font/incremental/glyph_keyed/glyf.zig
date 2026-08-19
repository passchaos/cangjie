//! Glyph-keyed reconstruction of the coupled `glyf`/`loca` tables.

const std = @import("std");
const offsets = @import("offsets.zig");

pub const Result = struct {
    glyf: []u8,
    loca: []u8,

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        allocator.free(self.glyf);
        allocator.free(self.loca);
    }
};

pub fn apply(
    allocator: std.mem.Allocator,
    glyf_data: []const u8,
    loca_data: []const u8,
    index_to_loc_format: i16,
    replacements: []const ?[]const u8,
    max_output_size: usize,
) !Result {
    const encoding: offsets.Encoding = switch (index_to_loc_format) {
        0 => .short_div_by_two,
        1 => .long,
        else => return error.BadSfnt,
    };
    const base_offsets = try allocator.alloc(u32, replacements.len + 1);
    defer allocator.free(base_offsets);
    for (base_offsets, 0..) |*value, index| {
        const byte_offset = index * encoding.width();
        if (byte_offset > loca_data.len or
            encoding.width() > loca_data.len - byte_offset) return error.BadSfnt;
        value.* = switch (encoding) {
            .short_div_by_two => @as(u32, std.mem.readInt(
                u16,
                loca_data[byte_offset..][0..2],
                .big,
            )) * 2,
            .long => std.mem.readInt(u32, loca_data[byte_offset..][0..4], .big),
            else => unreachable,
        };
    }
    const rebuilt = try offsets.rebuild(
        allocator,
        glyf_data,
        base_offsets,
        replacements,
        encoding,
        &.{encoding},
        max_output_size,
    );
    defer allocator.free(rebuilt.offsets);
    errdefer allocator.free(rebuilt.data);
    const loca = try allocator.alloc(u8, rebuilt.offsets.len * encoding.width());
    errdefer allocator.free(loca);
    try offsets.writeEncodedOffsets(loca, 0, rebuilt.offsets, encoding);
    return .{ .glyf = rebuilt.data, .loca = loca };
}
