//! GDEF AttachList lookup and allocator-owned point-index reads.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const glyph_mod = @import("../../../../glyph.zig");
const sfnt = @import("../../../sfnt/root.zig");
const coverage = @import("coverage.zig");
const types = @import("types.zig");

pub const Error = sfnt.Error ||
    std.mem.Allocator.Error ||
    error{EndOfStream};

pub fn read(
    allocator: std.mem.Allocator,
    data: []const u8,
    attach_list_offset: usize,
    glyph_id: glyph_mod.GlyphId,
) Error![]types.AttachmentPoint {
    if (attach_list_offset > data.len or
        data.len - attach_list_offset < 4)
    {
        return error.BadSfnt;
    }
    const coverage_relative = try bin.readU16At(data, attach_list_offset);
    const glyph_count = try bin.readU16At(data, attach_list_offset + 2);
    const offsets_start = attach_list_offset + 4;
    if (@as(usize, glyph_count) * 2 > data.len - offsets_start) {
        return error.BadSfnt;
    }
    const children_start = 4 + @as(usize, glyph_count) * 2;
    const coverage_offset = try requiredChildOffset(
        data,
        attach_list_offset,
        coverage_relative,
        children_start,
    );
    const coverage_index = try coverage.coverageIndex(
        data,
        coverage_offset,
        glyph_id,
    ) orelse return allocator.alloc(types.AttachmentPoint, 0);
    if (coverage_index >= glyph_count) return error.BadSfnt;

    const point_relative = try bin.readU16At(
        data,
        offsets_start + coverage_index * 2,
    );
    const point_offset = try requiredChildOffset(
        data,
        attach_list_offset,
        point_relative,
        children_start,
    );
    if (data.len - point_offset < 2) return error.BadSfnt;
    const count = try bin.readU16At(data, point_offset);
    if (@as(usize, count) * 2 > data.len - (point_offset + 2)) {
        return error.BadSfnt;
    }

    const result = try allocator.alloc(types.AttachmentPoint, count);
    errdefer allocator.free(result);
    var previous: ?u16 = null;
    for (result, 0..) |*point, index| {
        point.point_index =
            try bin.readU16At(data, point_offset + 2 + index * 2);
        if (previous) |value| {
            if (point.point_index <= value) return error.BadSfnt;
        }
        previous = point.point_index;
    }
    return result;
}

fn requiredChildOffset(
    data: []const u8,
    base: usize,
    relative: usize,
    minimum_relative: usize,
) Error!usize {
    if (base > data.len or relative < minimum_relative or
        relative > data.len - base)
    {
        return error.BadSfnt;
    }
    return base + relative;
}
