//! TrueType glyf structural validation and shared component grammar.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const loca = @import("../loca.zig");
const compound = @import("compound.zig");
const graph = @import("graph.zig");
const simple = @import("simple.zig");
const types = @import("types.zig");

pub const Error = loca.Error || compound.Error || graph.Error;

pub const PointMatch = types.PointMatch;
pub const Limits = types.Limits;

pub const validateSimpleFlag = simple.validateFlag;
pub const validateCompoundFlags = compound.validateFlags;

pub fn validate(
    allocator: std.mem.Allocator,
    data: []const u8,
    loca_record: sfnt.Record,
    glyf_record: sfnt.Record,
    glyph_count: u16,
    index_to_loc_format: i16,
    limits: Limits,
) Error!void {
    if (glyf_record.offset > data.len or
        glyf_record.length > data.len - glyf_record.offset)
    {
        return error.InvalidGlyph;
    }

    const adjacency = try allocator.alloc(types.Links, glyph_count);
    @memset(adjacency, .{});
    defer {
        for (adjacency) |links| allocator.free(links.components);
        allocator.free(adjacency);
    }
    const point_counts = try allocator.alloc(?usize, glyph_count);
    defer allocator.free(point_counts);
    @memset(point_counts, null);

    for (0..glyph_count) |glyph_index| {
        const start = try loca.offset(
            data,
            loca_record,
            index_to_loc_format,
            glyph_index,
        );
        const end = try loca.offset(
            data,
            loca_record,
            index_to_loc_format,
            glyph_index + 1,
        );
        if (end == start) {
            point_counts[glyph_index] = 0;
            continue;
        }
        if (end < start or end > glyf_record.length) {
            return error.InvalidLoca;
        }
        const glyph_data =
            data[glyf_record.offset + start .. glyf_record.offset + end];
        if (glyph_data.len < 10) return error.InvalidGlyph;
        const contour_count = try bin.readI16At(glyph_data, 0);
        if (contour_count >= 0) {
            point_counts[glyph_index] = try simple.validate(
                glyph_data,
                @intCast(contour_count),
                limits.max_points,
                limits.max_contours,
            );
        } else {
            adjacency[glyph_index] =
                try compound.readLinks(allocator, glyph_data, glyph_count);
        }
    }

    try graph.validate(
        allocator,
        adjacency,
        point_counts,
        limits.max_component_elements,
        limits.max_component_depth,
    );
}
