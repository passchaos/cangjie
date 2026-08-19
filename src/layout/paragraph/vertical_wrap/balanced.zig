//! Bounded raggedness optimization for vertical source-order columns.
//!
//! Greedy selection remains the fallback and fixes the number of columns in
//! each hard-break segment. This module searches the same reusable UAX/ranged
//! and emergency boundary graph for a lower squared-slack path, then returns
//! only source/glyph ranges; physical RL/LR placement stays with
//! `vertical_columns.zig`.

const std = @import("std");

const graph = @import("balanced/graph.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const measure = @import("measure.zig");
const paragraph_options = @import("../options.zig");
const policy = @import("policy.zig");
const run_types = @import("../../types/runs.zig");
const shared = @import("shared.zig");
const unicode = @import("../../../unicode.zig");

const cost_epsilon: f64 = 0.000001;
const width_epsilon: f32 = 0.001;
const emergency_penalty: f64 = 4.0;
// Long documents can expose a safe boundary after nearly every grapheme.
// Bounding both dimensions keeps `.balanced` a presentation preference:
// exhausting either budget retains the already valid greedy ranges.
const max_states_per_segment: usize = 16_384;
const max_edges_per_state: usize = 256;

const State = struct {
    boundary_index: usize,
    columns: usize,
    cost: f64,
    previous: ?usize,
};

const RegularFit = enum {
    none,
    found,
    limit_exceeded,
};

/// Replace independently solvable hard-segment ranges transactionally.
pub fn apply(
    output: *std.ArrayList(shared.Range),
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    prefix: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
) !void {
    if (options.line_break_strategy != .balanced or
        output.items.len <= 1 or
        !policy.anyWrappingEnabled(
            output.items[output.items.len - 1].byte_end,
            options,
        ) or
        options.max_lines == 0 or
        options.max_width <= 0 or
        !std.math.isFinite(options.max_width))
    {
        return;
    }

    var resolved = std.ArrayList(shared.Range).empty;
    defer resolved.deinit(allocator);
    try resolved.ensureTotalCapacity(allocator, output.items.len);

    var group_start: usize = 0;
    while (group_start < output.items.len) {
        var group_end = group_start + 1;
        while (group_end < output.items.len and
            !output.items[group_end].starts_segment)
        {
            group_end += 1;
        }
        const greedy = output.items[group_start..group_end];
        if (greedy.len <= 1) {
            resolved.appendSliceAssumeCapacity(greedy);
            group_start = group_end;
            continue;
        }

        var boundaries = std.ArrayList(graph.Boundary).empty;
        defer boundaries.deinit(allocator);
        try graph.enumerate(
            &boundaries,
            allocator,
            text,
            glyphs,
            runs,
            variation_coords,
            graphemes,
            breaks,
            options,
            greedy,
        );
        const selected = try solve(
            allocator,
            glyphs,
            prefix,
            options,
            boundaries.items,
            greedy.len,
            greedy[0].inline_indent,
        );
        if (selected) |path| {
            defer allocator.free(path);
            appendSolution(
                &resolved,
                boundaries.items,
                path,
                greedy,
            );
        } else {
            resolved.appendSliceAssumeCapacity(greedy);
        }
        group_start = group_end;
    }

    output.clearRetainingCapacity();
    try output.appendSlice(allocator, resolved.items);
}

fn solve(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    options: paragraph_options.Options,
    boundaries: []const graph.Boundary,
    column_count: usize,
    first_indent: f32,
) !?[]usize {
    if (boundaries.len < 3 or column_count < 2) return null;
    var states = std.ArrayList(State).empty;
    defer states.deinit(allocator);
    try states.append(allocator, .{
        .boundary_index = 0,
        .columns = 0,
        .cost = 0,
        .previous = null,
    });

    var state_index: usize = 0;
    while (state_index < states.items.len) : (state_index += 1) {
        const state = states.items[state_index];
        if (state.columns >= column_count) continue;
        const start = boundaries[state.boundary_index].next_glyph_start;
        const remaining = column_count - state.columns;
        const indent = if (state.columns == 0) first_indent else 0;
        const limit = @max(0, options.max_width - indent);
        const regular_fit = hasFittingRegular(
            glyphs,
            prefix,
            options,
            boundaries,
            state.boundary_index + 1,
            start,
            remaining,
            limit,
        );
        if (regular_fit == .limit_exceeded) return null;
        var edge_count: usize = 0;
        var end_index = state.boundary_index + 1;
        while (end_index < boundaries.len) : (end_index += 1) {
            const boundary = boundaries[end_index];
            if (!eligible(boundary, remaining)) continue;
            if (boundary.glyph_end <= start) continue;
            edge_count += 1;
            // A truncated edge set can change the selected quality path in an
            // order-dependent way. Abort the whole segment instead so the
            // documented greedy fallback remains deterministic.
            if (edge_count > max_edges_per_state) return null;
            if (regular_fit == .found and boundary.kind == .emergency) {
                continue;
            }
            const width = boundaryInlineSize(
                boundary,
                glyphs,
                prefix,
                start,
                options,
            );
            if (width > limit + width_epsilon) continue;
            const cost = squaredSlack(width, limit) +
                if (boundary.kind == .emergency)
                    emergency_penalty
                else
                    0;
            const accepted = try insertOrImprove(
                &states,
                allocator,
                .{
                    .boundary_index = end_index,
                    .columns = state.columns + 1,
                    .cost = state.cost + cost,
                    .previous = state_index,
                },
            );
            if (!accepted) return null;
        }
    }

    var best: ?usize = null;
    for (states.items, 0..) |state, index| {
        if (state.columns != column_count or
            boundaries[state.boundary_index].kind != .terminal)
        {
            continue;
        }
        if (best == null or state.cost < states.items[best.?].cost) {
            best = index;
        }
    }
    var cursor = best orelse return null;
    const path = try allocator.alloc(usize, column_count);
    var write = path.len;
    while (write > 0) {
        write -= 1;
        path[write] = states.items[cursor].boundary_index;
        cursor = states.items[cursor].previous orelse break;
    }
    if (write != 0) {
        allocator.free(path);
        return null;
    }
    return path;
}

fn hasFittingRegular(
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    options: paragraph_options.Options,
    boundaries: []const graph.Boundary,
    first_index: usize,
    start: usize,
    remaining: usize,
    limit: f32,
) RegularFit {
    var edge_count: usize = 0;
    for (boundaries[first_index..]) |boundary| {
        if (!eligible(boundary, remaining)) continue;
        if (boundary.glyph_end <= start) continue;
        edge_count += 1;
        if (edge_count > max_edges_per_state) return .limit_exceeded;
        if (boundary.kind == .emergency) continue;
        if (boundaryInlineSize(
            boundary,
            glyphs,
            prefix,
            start,
            options,
        ) <= limit + width_epsilon) return .found;
    }
    return .none;
}

fn eligible(boundary: graph.Boundary, remaining: usize) bool {
    if (remaining == 1) return boundary.kind == .terminal;
    return boundary.kind != .terminal and boundary.kind != .start;
}

fn insertOrImprove(
    states: *std.ArrayList(State),
    allocator: std.mem.Allocator,
    candidate: State,
) !bool {
    for (states.items) |*existing| {
        if (existing.boundary_index != candidate.boundary_index or
            existing.columns != candidate.columns)
        {
            continue;
        }
        if (candidate.cost + cost_epsilon < existing.cost) {
            existing.* = candidate;
        }
        return true;
    }
    if (states.items.len >= max_states_per_segment) return false;
    try states.append(allocator, candidate);
    return true;
}

fn appendSolution(
    output: *std.ArrayList(shared.Range),
    boundaries: []const graph.Boundary,
    path: []const usize,
    greedy: []const shared.Range,
) void {
    var previous_index: usize = 0;
    var byte_start = greedy[0].byte_start;
    for (path, 0..) |boundary_index, column_index| {
        const boundary = boundaries[boundary_index];
        output.appendAssumeCapacity(.{
            .glyph_start = boundaries[previous_index].next_glyph_start,
            .glyph_end = boundary.glyph_end,
            .byte_start = byte_start,
            .byte_end = if (column_index + 1 == path.len)
                greedy[greedy.len - 1].byte_end
            else
                boundary.byte_end,
            .inline_indent = if (column_index == 0)
                greedy[0].inline_indent
            else
                0,
            .starts_segment = column_index == 0,
            .hyphen = boundary.hyphen,
        });
        previous_index = boundary_index;
        byte_start = boundary.byte_end;
    }
}

fn boundaryInlineSize(
    boundary: graph.Boundary,
    glyphs: []const GlyphPosition,
    prefix: []const f32,
    start: usize,
    options: paragraph_options.Options,
) f32 {
    return @import("candidates.zig").candidateInlineSize(
        .{
            .glyph_end = boundary.glyph_end,
            .next_glyph_start = boundary.next_glyph_start,
            .byte_end = boundary.byte_end,
            .hyphen = boundary.hyphen,
        },
        glyphs,
        prefix,
        start,
        options,
    );
}

fn squaredSlack(width: f32, limit: f32) f64 {
    if (limit <= 0 or !std.math.isFinite(limit)) return 0;
    const ratio = @as(f64, @floatCast(@max(0, limit - width) / limit));
    return ratio * ratio;
}

test "balanced apply transactionally retains greedy on dense edge fanout" {
    const allocator = std.testing.allocator;
    const internal_count = max_edges_per_state + 1;
    const glyph_count = internal_count + 1;
    const glyphs = try allocator.alloc(GlyphPosition, glyph_count);
    defer allocator.free(glyphs);
    const graphemes = try allocator.alloc(
        unicode.GraphemeCluster,
        glyph_count,
    );
    defer allocator.free(graphemes);
    for (glyphs, 0..) |*glyph, index| {
        glyph.* = .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = index,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 1,
        };
        graphemes[index] = .{
            .byte_start = index,
            .byte_len = 1,
        };
    }
    const prefix = try allocator.alloc(f32, glyph_count + 1);
    defer allocator.free(prefix);
    measure.fillPrefix(prefix, glyphs);

    const midpoint = glyph_count / 2;
    const greedy = [_]shared.Range{
        .{
            .glyph_start = 0,
            .glyph_end = midpoint,
            .byte_start = 0,
            .byte_end = midpoint,
            .starts_segment = true,
        },
        .{
            .glyph_start = midpoint,
            .glyph_end = glyph_count,
            .byte_start = midpoint,
            .byte_end = glyph_count,
        },
    };
    var ranges = std.ArrayList(shared.Range).empty;
    defer ranges.deinit(allocator);
    try ranges.appendSlice(allocator, &greedy);

    try apply(
        &ranges,
        allocator,
        "",
        glyphs,
        &.{},
        &.{},
        prefix,
        graphemes,
        &.{},
        .{
            .max_width = @floatFromInt(midpoint),
            .line_break_strategy = .balanced,
            .word_break = .break_all,
            .writing_mode = .vertical_lr,
        },
    );
    try std.testing.expectEqualSlices(shared.Range, &greedy, ranges.items);
}
