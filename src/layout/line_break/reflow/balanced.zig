//! Bounded whole-segment optimization over reusable paragraph boundaries.
//!
//! Greedy reflow remains the canonical geometry/materialization pass. This
//! module changes only its soft-boundary policy: it first enumerates the exact
//! safe candidate graph, solves for one line target per hard-break segment,
//! then asks greedy reflow to choose the latest candidate not exceeding that
//! target. Keeping mutation in one pass preserves tabs, JSTF shrinkage,
//! hyphen materialization, styled metadata transactions, and truncation.

const std = @import("std");

const geometry = @import("geometry.zig");
const opportunity = @import("../opportunity.zig");
const opportunities = @import("opportunities.zig");
const paragraph_options = @import("../../paragraph/options.zig");
const punctuation_compression = @import("../../punctuation/compression.zig");
const punctuation_hanging = @import("../../punctuation/hanging.zig");
const regions = @import("regions.zig");
const shaped_boundary = @import("../shaped_boundary.zig");
const tabs = @import("../../paragraph/tabs.zig");
const white_space = @import("../../paragraph/white_space.zig");
const unicode = @import("../../../unicode.zig");

const cost_epsilon: f64 = 0.000001;
const width_epsilon: f32 = 0.001;
const hyphen_penalty: f64 = 0.35;
const consecutive_hyphen_penalty: f64 = 1.0;
const emergency_penalty: f64 = 4.0;
// Paragraphs can expose a boundary after almost every grapheme. Keep the
// quality search deterministic under hostile or document-scale input; failure
// to find a path within these limits falls back to the already valid greedy
// layout rather than turning a presentation preference into an error.
const max_states_per_segment: usize = 16_384;
const max_edges_per_state: usize = 256;

pub const Plan = struct {
    allocator: std.mem.Allocator,
    targets: []Target,

    pub fn deinit(self: *Plan) void {
        self.allocator.free(self.targets);
        self.* = undefined;
    }
};

const Target = struct {
    line_index: usize,
    glyph_index: usize,
};

const Kind = enum {
    start,
    soft,
    emergency,
    mandatory,
    terminal,
};

const Boundary = struct {
    glyph_index: usize,
    next_glyph_index: usize,
    byte_offset: usize,
    kind: Kind,
    candidate: opportunities.Candidate = .{},

    fn hasVisibleHyphen(self: Boundary) bool {
        return self.candidate.hasVisibleHyphen();
    }
};

const State = struct {
    boundary_index: usize,
    lines: usize,
    hyphen_run: usize,
    y: f32,
    cost: f64,
    previous: ?usize,
};

const Segment = struct {
    boundary_start: usize,
    boundary_end: usize,
    line_count: usize,
    line_index_base: usize,
    paragraph_line_base: usize,
    y: f32,
};

const Solution = struct {
    path: []usize,
    next_y: f32,
};

/// Build a target plan only when balancing is semantically active.
pub fn build(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    grapheme_clusters: []const unicode.GraphemeCluster,
    line_breaks: []const opportunity.Opportunity,
    greedy_lines: anytype,
    recipe: anytype,
) !?Plan {
    if (options.line_break_strategy != .balanced or
        options.wrap_mode == .no_wrap or
        !std.math.isFinite(effectiveMaxWidth(options.max_width)) or
        options.max_lines == 0 or
        buffer.glyphs.items.len == 0)
    {
        return null;
    }

    var boundaries = std.ArrayList(Boundary).empty;
    defer boundaries.deinit(buffer.allocator);
    try enumerateBoundaries(
        &boundaries,
        buffer,
        text,
        options,
        grapheme_clusters,
        line_breaks,
    );
    if (boundaries.items.len <= 2) return null;

    if (greedy_lines.len <= 1) return null;

    const segments = try mapGreedySegments(
        buffer.allocator,
        boundaries.items,
        text,
        greedy_lines,
    );
    defer buffer.allocator.free(segments);
    if (segments.len == 0) return null;

    var targets = std.ArrayList(Target).empty;
    errdefer targets.deinit(buffer.allocator);
    var propagated_y: ?f32 = null;
    for (segments, 0..) |segment_template, segment_index| {
        var segment = segment_template;
        if (propagated_y) |exact_y| segment.y = exact_y;
        const solution = try solveSegment(
            buffer,
            options,
            default_metrics,
            boundaries.items,
            segment,
            recipe,
        ) orelse continue;
        defer buffer.allocator.free(solution.path);
        propagated_y = if (segment_index + 1 < segments.len)
            solution.next_y + options.paragraph_spacing
        else
            null;
        // The final boundary is mandatory/terminal and is never selected by
        // the greedy soft-candidate policy.
        if (solution.path.len > 1) {
            for (
                solution.path[0 .. solution.path.len - 1],
                0..,
            ) |glyph_index, line_offset| {
                try targets.append(buffer.allocator, .{
                    .line_index = segment.line_index_base + line_offset,
                    .glyph_index = glyph_index,
                });
            }
        }
    }
    if (targets.items.len == 0) return null;
    std.sort.heap(Target, targets.items, {}, targetLessThan);
    return .{
        .allocator = buffer.allocator,
        .targets = try targets.toOwnedSlice(buffer.allocator),
    };
}

/// Prevent greedy from advancing past the optimal soft boundary for this line.
pub fn shouldBreakAtTarget(
    plan: ?*const Plan,
    line_index: usize,
    current_output_end: usize,
) bool {
    const target = targetForLine(plan, line_index) orelse return false;
    return current_output_end == target;
}

fn targetForLine(
    plan: ?*const Plan,
    line_index: usize,
) ?usize {
    const selected = plan orelse return null;
    for (selected.targets) |target| {
        if (target.line_index == line_index) return target.glyph_index;
        if (target.line_index > line_index) return null;
    }
    return null;
}

fn enumerateBoundaries(
    output: *std.ArrayList(Boundary),
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    graphemes: []const unicode.GraphemeCluster,
    analyzed: []const opportunity.Opportunity,
) !void {
    try output.append(buffer.allocator, .{
        .glyph_index = 0,
        .next_glyph_index = 0,
        .byte_offset = 0,
        .kind = .start,
    });
    var cursor = opportunities.Cursor.init(text, analyzed);
    var hard_break_end: ?usize = null;
    var index: usize = 0;
    while (index < buffer.glyphs.items.len) : (index += 1) {
        const glyph = buffer.glyphs.items[index];
        if (opportunities.isMandatory(glyph.codepoint)) {
            const break_end =
                if (glyph.codepoint == '\r' and
                index + 1 < buffer.glyphs.items.len and
                buffer.glyphs.items[index + 1].codepoint == '\n')
                    index + 2
                else
                    index + 1;
            try appendUnique(output, buffer.allocator, .{
                .glyph_index = index,
                .next_glyph_index = break_end,
                .byte_offset = shaped_boundary.glyphSourceEnd(
                    buffer.glyphs.items[break_end - 1],
                ),
                .kind = .mandatory,
            });
            cursor.discardThrough(shaped_boundary.glyphSourceEnd(
                buffer.glyphs.items[break_end - 1],
            ));
            hard_break_end = break_end;
            index = break_end - 1;
            continue;
        }

        const atom_continues =
            index + 1 < buffer.glyphs.items.len and
            shaped_boundary.glyphClusterStart(
                buffer.glyphs.items[index + 1],
            ) == shaped_boundary.glyphClusterStart(glyph);
        if (atom_continues) continue;
        const source_end = shaped_boundary.glyphSourceEnd(glyph);
        while (cursor.nextThrough(source_end)) |line_break| {
            if (line_break.kind != .soft) continue;
            var candidate = opportunities.Candidate{};
            try opportunities.recordSoft(
                buffer.glyphs.items,
                buffer.runs.items,
                line_break.byte_offset,
                index,
                hard_break_end orelse 0,
                0,
                &candidate,
                options.normalized_variation_coords,
                line_break.automatic_hyphen,
                line_break.arbitrary,
                options.hyphenation.character,
            );
            const break_index = candidate.glyph_index orelse continue;
            var next_start = break_index;
            if (white_space.shouldDiscardAfterSoftWrap(
                options.white_space_collapse,
            )) {
                geometry.trimLeadingSoftBreaks(
                    buffer.glyphs.items,
                    &next_start,
                );
            }
            try appendUnique(output, buffer.allocator, .{
                .glyph_index = break_index,
                .next_glyph_index = next_start,
                .byte_offset = line_break.byte_offset,
                .kind = if (line_break.arbitrary and
                    options.overflow_wrap == .break_word and
                    options.word_break != .break_all)
                    .emergency
                else
                    .soft,
                .candidate = candidate,
            });
        }
        if (options.white_space_collapse == .break_spaces and
            geometry.isDiscardableBreak(glyph.codepoint))
        {
            var after_space = opportunities.Candidate{};
            opportunities.recordBreakSpaces(
                buffer.glyphs.items,
                index,
                hard_break_end orelse 0,
                0,
                &after_space,
            );
            if (after_space.glyph_index) |after_index| {
                try appendUnique(output, buffer.allocator, .{
                    .glyph_index = after_index,
                    .next_glyph_index = after_index,
                    .byte_offset = source_end,
                    .kind = .soft,
                    .candidate = after_space,
                });
            }
        }
    }

    // Policies that permit arbitrary wrapping expose every reusable grapheme
    // boundary. If a UAX #14 edge already exists there, retain its better
    // semantics and lower penalty.
    if (options.overflow_wrap != .normal or
        options.word_break == .break_all)
    {
        var glyph_index: usize = 1;
        while (glyph_index < buffer.glyphs.items.len) : (glyph_index += 1) {
            if (!shaped_boundary.outputBoundaryIsReusable(
                buffer.glyphs.items,
                graphemes,
                glyph_index,
            )) continue;
            try appendUnique(output, buffer.allocator, .{
                .glyph_index = glyph_index,
                .next_glyph_index = glyph_index,
                .byte_offset = shaped_boundary.byteEndForGlyphPrefix(
                    buffer.glyphs.items,
                    glyph_index,
                    0,
                ),
                .kind = .emergency,
            });
        }
    }
    try appendUnique(output, buffer.allocator, .{
        .glyph_index = buffer.glyphs.items.len,
        .next_glyph_index = buffer.glyphs.items.len,
        .byte_offset = text.len,
        .kind = .terminal,
    });
    std.sort.heap(Boundary, output.items, {}, boundaryLessThan);
}

fn appendUnique(
    output: *std.ArrayList(Boundary),
    allocator: std.mem.Allocator,
    value: Boundary,
) !void {
    for (output.items) |*existing| {
        if (existing.glyph_index != value.glyph_index or
            existing.byte_offset != value.byte_offset)
        {
            continue;
        }
        if (boundaryPriority(value.kind) > boundaryPriority(existing.kind)) {
            existing.* = value;
        }
        return;
    }
    try output.append(allocator, value);
}

fn mapGreedySegments(
    allocator: std.mem.Allocator,
    boundaries: []const Boundary,
    text: []const u8,
    lines: anytype,
) ![]Segment {
    var output = std.ArrayList(Segment).empty;
    errdefer output.deinit(allocator);
    var line_start: usize = 0;
    while (line_start < lines.len) {
        var line_end = line_start + 1;
        while (line_end < lines.len and
            !lineEndsHard(text, lines[line_end - 1]))
        {
            line_end += 1;
        }
        const boundary_start = boundaryIndexForByte(
            boundaries,
            lines[line_start].byte_start,
            false,
        );
        const boundary_end = boundaryIndexForByte(
            boundaries,
            lines[line_end - 1].byteEnd(),
            true,
        );
        try output.append(allocator, .{
            .boundary_start = boundary_start,
            .boundary_end = boundary_end,
            .line_count = line_end - line_start,
            .line_index_base = line_start,
            .paragraph_line_base = 0,
            .y = lines[line_start].y,
        });
        line_start = line_end;
    }
    return output.toOwnedSlice(allocator);
}

fn solveSegment(
    buffer: anytype,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    boundaries: []const Boundary,
    segment: Segment,
    recipe: anytype,
) !?Solution {
    if (segment.line_count == 0 or
        segment.boundary_start >= segment.boundary_end)
    {
        return null;
    }
    var states = std.ArrayList(State).empty;
    defer states.deinit(buffer.allocator);
    try states.append(buffer.allocator, .{
        .boundary_index = segment.boundary_start,
        .lines = 0,
        .hyphen_run = 0,
        .y = segment.y,
        .cost = 0,
        .previous = null,
    });

    var state_index: usize = 0;
    while (state_index < states.items.len) : (state_index += 1) {
        const state = states.items[state_index];
        if (state.lines >= segment.line_count) continue;
        const start = boundaries[state.boundary_index].next_glyph_index;
        const remaining_lines = segment.line_count - state.lines;
        const fitting_regular_edge =
            if (options.overflow_wrap == .break_word and
            options.word_break != .break_all)
                try hasFittingRegularEdge(
                    buffer,
                    options,
                    default_metrics,
                    boundaries,
                    segment,
                    recipe,
                    state,
                    start,
                    remaining_lines,
                )
            else
                false;
        const first_end = state.boundary_index + 1;
        var end_index = first_end;
        var evaluated_edges: usize = 0;
        while (end_index <= segment.boundary_end) : (end_index += 1) {
            const end_boundary = boundaries[end_index];
            if (end_boundary.kind == .mandatory and
                end_index != segment.boundary_end) break;
            if (remaining_lines == 1 and end_index != segment.boundary_end) {
                continue;
            }
            if (remaining_lines > 1 and end_index == segment.boundary_end) {
                continue;
            }
            if (fitting_regular_edge and end_boundary.kind == .emergency) {
                continue;
            }
            evaluated_edges += 1;
            if (evaluated_edges > max_edges_per_state) break;
            const evaluated = try evaluateLine(
                buffer,
                options,
                default_metrics,
                recipe,
                start,
                end_boundary,
                segment.paragraph_line_base + state.lines,
                state.y,
            );
            if (!evaluated.fits) {
                // Width is monotone unless a tab field changes alignment.
                // Continue so a later candidate can still be measured exactly.
                continue;
            }
            const next_hyphen_run =
                if (end_boundary.hasVisibleHyphen())
                    state.hyphen_run + 1
                else
                    0;
            if (options.hyphenation.max_consecutive_lines) |limit| {
                if (next_hyphen_run > limit) continue;
            }
            const terminal = end_index == segment.boundary_end;
            // Justified lines run source-level JSTF/font-expansion/Kashida
            // after selection, so their pre-justification slack is not visible
            // raggedness. Keep hyphen/emergency penalties while treating all
            // fitting non-terminal edges as equally filled.
            const visually_filled =
                options.alignment == .justify and !terminal;
            const line_cost = badness(
                evaluated.width,
                evaluated.limit,
                visually_filled,
                end_boundary,
                state.hyphen_run != 0,
            );
            const accepted = try insertOrImprove(
                &states,
                buffer.allocator,
                .{
                    .boundary_index = end_index,
                    .lines = state.lines + 1,
                    .hyphen_run = next_hyphen_run,
                    .y = evaluated.next_y,
                    .cost = state.cost + line_cost,
                    .previous = state_index,
                },
            );
            if (!accepted) return null;
        }
    }

    var best: ?usize = null;
    for (states.items, 0..) |state, index| {
        if (state.boundary_index != segment.boundary_end or
            state.lines != segment.line_count)
        {
            continue;
        }
        if (best == null or state.cost < states.items[best.?].cost) {
            best = index;
        }
    }
    const final_index = best orelse return null;
    const path = try buffer.allocator.alloc(usize, segment.line_count);
    var cursor = final_index;
    var write = path.len;
    while (write > 0) {
        write -= 1;
        path[write] = boundaries[states.items[cursor].boundary_index].glyph_index;
        cursor = states.items[cursor].previous orelse break;
    }
    if (write != 0) {
        buffer.allocator.free(path);
        return null;
    }
    return .{
        .path = path,
        .next_y = states.items[final_index].y,
    };
}

fn hasFittingRegularEdge(
    buffer: anytype,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    boundaries: []const Boundary,
    segment: Segment,
    recipe: anytype,
    state: State,
    start: usize,
    remaining_lines: usize,
) !bool {
    var end_index = state.boundary_index + 1;
    var evaluated_edges: usize = 0;
    while (end_index <= segment.boundary_end) : (end_index += 1) {
        const boundary = boundaries[end_index];
        if (boundary.kind == .mandatory and
            end_index != segment.boundary_end) break;
        if (boundary.kind == .emergency) continue;
        if (remaining_lines == 1 and end_index != segment.boundary_end) {
            continue;
        }
        if (remaining_lines > 1 and end_index == segment.boundary_end) {
            continue;
        }
        evaluated_edges += 1;
        if (evaluated_edges > max_edges_per_state) break;
        const evaluated = try evaluateLine(
            buffer,
            options,
            default_metrics,
            recipe,
            start,
            boundary,
            segment.paragraph_line_base + state.lines,
            state.y,
        );
        if (evaluated.fits) return true;
    }
    return false;
}

const EvaluatedLine = struct {
    fits: bool,
    width: f32,
    limit: f32,
    next_y: f32,
};

fn evaluateLine(
    buffer: anytype,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    recipe: anytype,
    start: usize,
    boundary: Boundary,
    line_index: usize,
    y: f32,
) !EvaluatedLine {
    if (start >= boundary.glyph_index) return .{
        .fits = false,
        .width = 0,
        .limit = 0,
        .next_y = y,
    };
    const metrics = geometry.resolvedLineInfo(
        buffer.runs.items,
        buffer.glyphs.items,
        options.inline_objects,
        start,
        boundary.glyph_index,
        default_metrics,
        options.line_height,
        recipe.minimumLineHeight(start, boundary.glyph_index),
    ).metrics;
    var committed_y = y;
    const region = try regions.resolve(
        buffer.allocator,
        options,
        line_index,
        &committed_y,
        metrics.lineHeight(),
        effectiveMaxWidth(options.max_width),
    );
    const hyphen_advance = visibleHyphenAdvance(boundary.candidate);
    const space_advance = geometry.defaultSpaceAdvance(buffer.glyphs.items);
    const fallback_interval =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) *
        space_advance;
    const range_width = tabs.measureRangeWithTerminal(
        buffer.glyphs.items[start..boundary.glyph_index],
        options.tab_stops,
        fallback_interval,
        space_advance,
        hyphen_advance,
    );
    const width = if (options.white_space_collapse == .collapse and
        !tabs.contains(buffer.glyphs.items[start..boundary.glyph_index]))
        white_space.measureRange(
            buffer.glyphs.items,
            start,
            boundary.glyph_index,
            options.white_space_collapse,
        ) + hyphen_advance
    else
        range_width;
    const hanging_fraction: f32 =
        if (boundary.hasVisibleHyphen())
            0
        else
            options.punctuation.end_hanging_fraction;
    const hanging = punctuation_hanging.logicalEndAmount(
        buffer.glyphs.items,
        start,
        boundary.glyph_index,
        hanging_fraction,
    );
    const compression = punctuation_compression.effectiveCapacity(
        buffer.glyphs.items,
        start,
        boundary.glyph_index,
        options.punctuation.max_compression_fraction,
        hanging_fraction,
        options.punctuation.convention,
    );
    return .{
        .fits = @max(0, width - hanging) <=
            region.width + compression + width_epsilon,
        .width = width,
        .limit = region.width,
        .next_y = committed_y + metrics.lineHeight(),
    };
}

fn badness(
    width: f32,
    limit: f32,
    visually_filled: bool,
    boundary: Boundary,
    previous_hyphen: bool,
) f64 {
    if (!std.math.isFinite(limit) or limit <= 0) return 0;
    const slack = @max(0, limit - width);
    const ratio = @as(f64, @floatCast(slack / limit));
    // Equal treatment of every visual line minimizes total squared slack and
    // therefore pulls words away from an otherwise short terminal runt.
    var result = if (visually_filled) 0 else ratio * ratio;
    if (boundary.hasVisibleHyphen()) {
        result += hyphen_penalty;
        if (previous_hyphen) result += consecutive_hyphen_penalty;
    }
    if (boundary.kind == .emergency) result += emergency_penalty;
    return result;
}

fn insertOrImprove(
    states: *std.ArrayList(State),
    allocator: std.mem.Allocator,
    candidate: State,
) !bool {
    for (states.items) |*existing| {
        if (existing.boundary_index != candidate.boundary_index or
            existing.lines != candidate.lines or
            existing.hyphen_run != candidate.hyphen_run or
            @as(u32, @bitCast(existing.y)) !=
                @as(u32, @bitCast(candidate.y)))
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

fn boundaryIndexForByte(
    boundaries: []const Boundary,
    byte_offset: usize,
    prefer_mandatory: bool,
) usize {
    var fallback: usize = 0;
    for (boundaries, 0..) |boundary, index| {
        if (boundary.byte_offset < byte_offset) {
            fallback = index;
            continue;
        }
        if (boundary.byte_offset > byte_offset) break;
        if (!prefer_mandatory or
            boundary.kind == .mandatory or
            boundary.kind == .terminal)
        {
            return index;
        }
        fallback = index;
    }
    return fallback;
}

fn lineEndsHard(text: []const u8, line: anytype) bool {
    const end = @min(line.byteEnd(), text.len);
    if (end == 0) return false;
    var view = std.unicode.Utf8View.initUnchecked(text[0..end]);
    var iterator = view.iterator();
    var last: ?u21 = null;
    while (iterator.nextCodepoint()) |codepoint| last = codepoint;
    if (last) |codepoint| {
        return opportunities.isMandatory(codepoint);
    }
    return false;
}

fn visibleHyphenAdvance(candidate: opportunities.Candidate) f32 {
    if (candidate.hyphen) |item| return item.resolved.x_advance;
    if (candidate.automatic_hyphen) |item| return item.resolved.x_advance;
    return 0;
}

fn effectiveMaxWidth(value: f32) f32 {
    return if (value > 0) value else std.math.inf(f32);
}

fn boundaryPriority(kind: Kind) u8 {
    return switch (kind) {
        .start => 4,
        .emergency => 0,
        .soft => 1,
        .terminal => 2,
        .mandatory => 3,
    };
}

fn boundaryLessThan(_: void, a: Boundary, b: Boundary) bool {
    if (a.glyph_index != b.glyph_index) {
        return a.glyph_index < b.glyph_index;
    }
    if (a.byte_offset != b.byte_offset) {
        return a.byte_offset < b.byte_offset;
    }
    return boundaryPriority(a.kind) > boundaryPriority(b.kind);
}

fn targetLessThan(_: void, a: Target, b: Target) bool {
    if (a.line_index != b.line_index) return a.line_index < b.line_index;
    return a.glyph_index < b.glyph_index;
}

test "balanced badness penalizes terminal runts" {
    const middle = Boundary{
        .glyph_index = 1,
        .next_glyph_index = 1,
        .byte_offset = 1,
        .kind = .soft,
    };
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.64),
        badness(20, 100, false, middle, false),
        0.000001,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        badness(20, 100, true, middle, false),
    );
}
