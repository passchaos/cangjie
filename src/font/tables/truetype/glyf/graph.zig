//! Compound-glyph graph, maxp aggregate, and point-match validation.

const std = @import("std");
const types = @import("types.zig");

pub const Error = error{InvalidGlyph} || std.mem.Allocator.Error;

pub fn validate(
    allocator: std.mem.Allocator,
    adjacency: []const types.Links,
    point_counts: []?usize,
    max_component_elements: u16,
    max_component_depth: u16,
) Error!void {
    const states = try allocator.alloc(VisitState, adjacency.len);
    defer allocator.free(states);
    @memset(states, .unvisited);
    const depths = try allocator.alloc(u16, adjacency.len);
    defer allocator.free(depths);
    @memset(depths, 0);

    for (adjacency, 0..) |links, glyph_index| {
        if (links.components.len > max_component_elements) {
            return error.InvalidGlyph;
        }
        if (states[glyph_index] == .unvisited) {
            _ = try visit(adjacency, states, depths, @intCast(glyph_index));
        }
        if (depths[glyph_index] > max_component_depth) {
            return error.InvalidGlyph;
        }
    }

    // Point-matching constraints require complete, acyclic child point counts,
    // so resolve them only after the graph proof above.
    for (adjacency, 0..) |_, glyph_index| {
        _ = try pointCount(adjacency, point_counts, @intCast(glyph_index));
    }
}

const VisitState = enum {
    unvisited,
    visiting,
    visited,
};

fn visit(
    adjacency: []const types.Links,
    states: []VisitState,
    depths: []u16,
    glyph_id: types.GlyphId,
) Error!u16 {
    const index: usize = glyph_id;
    switch (states[index]) {
        .visited => return depths[index],
        .visiting => return error.InvalidGlyph,
        .unvisited => {},
    }
    states[index] = .visiting;
    var max_depth: u16 = 0;
    for (adjacency[index].components) |component| {
        const child_depth =
            try visit(adjacency, states, depths, component.glyph);
        if (child_depth == std.math.maxInt(u16)) return error.InvalidGlyph;
        max_depth = @max(max_depth, child_depth + 1);
    }
    depths[index] = max_depth;
    states[index] = .visited;
    return max_depth;
}

fn pointCount(
    adjacency: []const types.Links,
    point_counts: []?usize,
    glyph_id: types.GlyphId,
) Error!usize {
    const index: usize = glyph_id;
    if (point_counts[index]) |count| return count;

    var total: usize = 0;
    for (adjacency[index].components) |component| {
        const child_count =
            try pointCount(adjacency, point_counts, component.glyph);
        if (component.point_match) |match| {
            if (@as(usize, match.parent_point) >= total or
                @as(usize, match.child_point) >= child_count)
            {
                return error.InvalidGlyph;
            }
        }
        if (child_count > std.math.maxInt(usize) - total) {
            return error.InvalidGlyph;
        }
        total += child_count;
    }
    point_counts[index] = total;
    return total;
}
