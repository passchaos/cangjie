//! TrueType compound-glyph component stream validation.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const types = @import("types.zig");

pub const Error = error{ InvalidGlyph, EndOfStream } ||
    std.mem.Allocator.Error;

pub fn readLinks(
    allocator: std.mem.Allocator,
    glyph_data: []const u8,
    glyph_count: u16,
) Error!types.Links {
    var components = std.ArrayList(types.Component).empty;
    errdefer components.deinit(allocator);

    var offset: usize = 10;
    while (true) {
        if (offset > glyph_data.len or glyph_data.len - offset < 4) {
            return error.InvalidGlyph;
        }
        const flags = try bin.readU16At(glyph_data, offset);
        try validateFlags(flags);
        const component_glyph = try bin.readU16At(glyph_data, offset + 2);
        if (component_glyph >= glyph_count) return error.InvalidGlyph;
        offset += 4;

        const argument_bytes: usize = if ((flags & 0x0001) != 0) 4 else 2;
        if (argument_bytes > glyph_data.len - offset) {
            return error.InvalidGlyph;
        }
        try components.append(allocator, .{
            .glyph = component_glyph,
            .point_match = try pointMatch(
                glyph_data[offset .. offset + argument_bytes],
                flags,
            ),
        });
        offset += argument_bytes;

        const has_scale = (flags & 0x0008) != 0;
        const has_xy_scale = (flags & 0x0040) != 0;
        const has_two_by_two = (flags & 0x0080) != 0;
        const scale_flag_count = @as(u8, @intFromBool(has_scale)) +
            @as(u8, @intFromBool(has_xy_scale)) +
            @as(u8, @intFromBool(has_two_by_two));
        if (scale_flag_count > 1) return error.InvalidGlyph;
        const scale_bytes: usize = if (has_scale)
            2
        else if (has_xy_scale)
            4
        else if (has_two_by_two)
            8
        else
            0;
        if (scale_bytes > glyph_data.len - offset) {
            return error.InvalidGlyph;
        }
        offset += scale_bytes;

        if ((flags & 0x0020) == 0) {
            if ((flags & 0x0100) != 0) {
                if (offset > glyph_data.len or glyph_data.len - offset < 2) {
                    return error.InvalidGlyph;
                }
                const instruction_len =
                    try bin.readU16At(glyph_data, offset);
                offset += 2;
                if (instruction_len > glyph_data.len - offset) {
                    return error.InvalidGlyph;
                }
            }
            return .{ .components = try components.toOwnedSlice(allocator) };
        }
    }
}

pub fn validateFlags(flags: u16) Error!void {
    const known_flags: u16 = 0x0001 | 0x0002 | 0x0004 | 0x0008 |
        0x0010 | 0x0020 | 0x0040 | 0x0080 | 0x0100 |
        0x0200 | 0x0400 | 0x0800 | 0x1000 |
        0x2000 | 0x4000 | 0x8000;
    if ((flags & ~known_flags) != 0) return error.InvalidGlyph;
    // These bits assign opposite meanings to the same component offset.
    if ((flags & 0x0800) != 0 and (flags & 0x1000) != 0) {
        return error.InvalidGlyph;
    }
}

pub fn pointMatch(
    argument_data: []const u8,
    flags: u16,
) Error!?types.PointMatch {
    if ((flags & 0x0002) != 0) return null;
    if ((flags & 0x0001) != 0) {
        if (argument_data.len < 4) return error.InvalidGlyph;
        return .{
            .parent_point = try bin.readU16At(argument_data, 0),
            .child_point = try bin.readU16At(argument_data, 2),
        };
    }
    if (argument_data.len < 2) return error.InvalidGlyph;
    return .{
        .parent_point = argument_data[0],
        .child_point = argument_data[1],
    };
}
