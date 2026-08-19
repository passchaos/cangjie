//! Safe source/output boundary graph for vertical balanced wrapping.
//!
//! Every edge comes from the same authored or emergency policy used by the
//! greedy vertical breaker. In particular, no edge may split a grapheme or a
//! shaping boundary marked unsafe to reuse.

const std = @import("std");

const candidates = @import("../candidates.zig");
const GlyphPosition = @import("../../../glyph_position.zig").GlyphPosition;
const line_break_opportunity = @import("../../../line_break/opportunity.zig");
const line_break_policy = @import("../../line_break_policy.zig");
const paragraph_options = @import("../../options.zig");
const policy = @import("../policy.zig");
const run_types = @import("../../../types/runs.zig");
const shaped_boundary = @import("../../../line_break/shaped_boundary.zig");
const shared = @import("../shared.zig");
const unicode = @import("../../../../unicode.zig");

pub const Kind = enum {
    start,
    soft,
    emergency,
    terminal,
};

pub const Boundary = struct {
    glyph_end: usize,
    next_glyph_start: usize,
    byte_end: usize,
    kind: Kind,
    hyphen: ?@import("../../../discretionary_hyphen.zig").VerticalCandidate = null,
};

pub fn enumerate(
    output: *std.ArrayList(Boundary),
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
    greedy: []const shared.Range,
) !void {
    const segment_start = greedy[0].glyph_start;
    const segment_end = greedy[greedy.len - 1].glyph_end;
    const source_start = greedy[0].byte_start;
    const source_content_end =
        if (segment_end < glyphs.len and isMandatory(glyphs[segment_end].codepoint))
            glyphs[segment_end].cluster
        else
            greedy[greedy.len - 1].byte_end;

    try output.append(allocator, .{
        .glyph_end = segment_start,
        .next_glyph_start = segment_start,
        .byte_end = source_start,
        .kind = .start,
    });

    var ordinary = std.ArrayList(shared.SoftCandidate).empty;
    defer ordinary.deinit(allocator);
    try candidates.collect(
        &ordinary,
        allocator,
        text,
        glyphs,
        runs,
        variation_coords,
        graphemes,
        breaks,
        segment_start,
        segment_end,
        source_start,
        source_content_end,
        options,
    );
    try candidates.appendBreakSpaces(
        &ordinary,
        allocator,
        glyphs,
        graphemes,
        segment_start,
        segment_end,
        source_start,
        source_content_end,
        options,
    );
    for (ordinary.items) |candidate| {
        if (candidate.glyph_end <= segment_start or
            candidate.next_glyph_start >= segment_end)
        {
            continue;
        }
        try appendPreferred(output, allocator, .{
            .glyph_end = candidate.glyph_end,
            .next_glyph_start = candidate.next_glyph_start,
            .byte_end = candidate.byte_end,
            .kind = candidateKind(
                breaks,
                candidate.byte_end,
                options,
            ),
            .hyphen = candidate.hyphen,
        });
    }

    var glyph_index = segment_start + 1;
    while (glyph_index < segment_end) : (glyph_index += 1) {
        if (!shaped_boundary.outputBoundaryIsReusable(
            glyphs,
            graphemes,
            glyph_index,
        )) continue;
        const byte_end = glyphs[glyph_index].cluster;
        if (!policy.emergencyAllowedBefore(options, byte_end)) continue;
        try appendPreferred(output, allocator, .{
            .glyph_end = glyph_index,
            .next_glyph_start = glyph_index,
            .byte_end = byte_end,
            .kind = .emergency,
        });
    }
    try output.append(allocator, .{
        .glyph_end = segment_end,
        .next_glyph_start = segment_end,
        .byte_end = source_content_end,
        .kind = .terminal,
    });
    std.sort.heap(Boundary, output.items, {}, boundaryLessThan);
}

fn appendPreferred(
    output: *std.ArrayList(Boundary),
    allocator: std.mem.Allocator,
    value: Boundary,
) !void {
    for (output.items) |*existing| {
        if (existing.next_glyph_start != value.next_glyph_start) continue;
        if (priority(value.kind) > priority(existing.kind)) {
            existing.* = value;
        }
        return;
    }
    try output.append(allocator, value);
}

fn candidateKind(
    breaks: []const line_break_opportunity.Opportunity,
    byte_end: usize,
    options: paragraph_options.Options,
) Kind {
    for (breaks) |item| {
        if (item.byte_offset < byte_end) continue;
        if (item.byte_offset > byte_end or !item.arbitrary) return .soft;
        const selected = line_break_policy.beforeBoundary(
            paragraph_options.defaultLineBreakPolicy(options),
            options.line_break_policy_ranges,
            byte_end,
        );
        return if (selected.overflow_wrap == .break_word and
            selected.word_break != .break_all)
            .emergency
        else
            .soft;
    }
    // break-spaces candidates are authored soft opportunities and may not
    // have a retained analysis record at the same boundary.
    return .soft;
}

fn boundaryLessThan(_: void, lhs: Boundary, rhs: Boundary) bool {
    if (lhs.next_glyph_start != rhs.next_glyph_start) {
        return lhs.next_glyph_start < rhs.next_glyph_start;
    }
    if (lhs.glyph_end != rhs.glyph_end) return lhs.glyph_end < rhs.glyph_end;
    return priority(lhs.kind) > priority(rhs.kind);
}

fn priority(kind: Kind) u8 {
    return switch (kind) {
        .start, .terminal => 3,
        .soft => 2,
        .emergency => 1,
    };
}

fn isMandatory(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

test "balanced graph never manufactures an unsafe grapheme edge" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 20,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 20,
            .flags = .{ .unsafe_to_break_before = true },
        },
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 2,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 20,
        },
    };
    const graphemes = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = 1 },
        .{ .byte_start = 1, .byte_len = 1 },
        .{ .byte_start = 2, .byte_len = 1 },
    };
    const greedy = [_]shared.Range{
        .{
            .glyph_start = 0,
            .glyph_end = 2,
            .byte_start = 0,
            .byte_end = 2,
            .starts_segment = true,
        },
        .{
            .glyph_start = 2,
            .glyph_end = 3,
            .byte_start = 2,
            .byte_end = 3,
        },
    };
    var boundaries = std.ArrayList(Boundary).empty;
    defer boundaries.deinit(std.testing.allocator);
    try enumerate(
        &boundaries,
        std.testing.allocator,
        "AAA",
        &glyphs,
        &.{},
        &.{},
        &graphemes,
        &.{},
        .{
            .max_width = 40,
            .line_break_strategy = .balanced,
            .word_break = .break_all,
            .writing_mode = .vertical_lr,
        },
        &greedy,
    );
    for (boundaries.items) |boundary| {
        try std.testing.expect(boundary.next_glyph_start != 1);
    }
}
