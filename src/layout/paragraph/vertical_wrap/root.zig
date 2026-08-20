//! Greedy inline-axis selection for vertical paragraph columns.
//!
//! Physical RL/LR placement and line-box metrics remain in
//! `vertical_columns.zig`; this module selects only safe source/glyph ranges.

const std = @import("std");
const balanced = @import("balanced.zig");
const candidates = @import("candidates.zig");
const emergency = @import("emergency.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const intrinsic = @import("intrinsic.zig");
const line_break_opportunity = @import("../../line_break/opportunity.zig");
const measure = @import("measure.zig");
const paragraph_options = @import("../options.zig");
const policy = @import("policy.zig");
const run_types = @import("../../types/runs.zig");
const shared = @import("shared.zig");
const unicode = @import("../../../unicode.zig");
const vertical_inline_region = @import("../vertical_inline_region.zig");
const vertical_block_metrics = @import("../vertical_block_metrics.zig");
const geometry = @import("../../line_break/reflow/geometry.zig");

pub const Range = shared.Range;
pub const intrinsicWidths = intrinsic.measure;

pub fn build(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    recipe: anytype,
) ![]Range {
    var output = std.ArrayList(Range).empty;
    errdefer output.deinit(allocator);
    var effective_breaks = try policy.resolve(
        allocator,
        text,
        graphemes,
        breaks,
        options,
    );
    defer effective_breaks.deinit();
    const wrapping_enabled = policy.anyWrappingEnabled(text.len, options);
    const prefix = try allocator.alloc(f32, glyphs.len + 1);
    defer allocator.free(prefix);
    measure.fillPrefix(prefix, glyphs);

    var segment_start: usize = 0;
    var segment_byte_start: usize = 0;
    var index: usize = 0;
    while (index < glyphs.len) : (index += 1) {
        if (!isMandatory(glyphs[index].codepoint)) continue;
        const break_end = if (glyphs[index].codepoint == '\r' and
            index + 1 < glyphs.len and
            glyphs[index + 1].codepoint == '\n')
            index + 2
        else
            index + 1;
        const hard_byte_end = glyphs[break_end - 1].sourceByteEnd();
        try appendSegment(
            &output,
            allocator,
            text,
            glyphs,
            runs,
            variation_coords,
            prefix,
            graphemes,
            effective_breaks.items,
            options,
            default_metrics,
            recipe,
            wrapping_enabled,
            output.items.len,
            segment_start,
            index,
            segment_byte_start,
            glyphs[index].cluster,
        );
        output.items[output.items.len - 1].byte_end = hard_byte_end;
        segment_start = break_end;
        segment_byte_start = hard_byte_end;
        index = break_end - 1;
    }
    try appendSegment(
        &output,
        allocator,
        text,
        glyphs,
        runs,
        variation_coords,
        prefix,
        graphemes,
        effective_breaks.items,
        options,
        default_metrics,
        recipe,
        wrapping_enabled,
        output.items.len,
        segment_start,
        glyphs.len,
        segment_byte_start,
        text.len,
    );
    try balanced.apply(
        &output,
        allocator,
        text,
        glyphs,
        runs,
        variation_coords,
        prefix,
        graphemes,
        effective_breaks.items,
        options,
    );
    return output.toOwnedSlice(allocator);
}

fn appendSegment(
    output: *std.ArrayList(Range),
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    prefix: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    recipe: anytype,
    wrapping_enabled: bool,
    visual_base: usize,
    segment_start: usize,
    segment_end: usize,
    segment_byte_start: usize,
    segment_byte_end: usize,
) !void {
    if (segment_start >= segment_end) {
        const natural_indent = @max(0, options.first_line_indent);
        try output.append(allocator, .{
            .glyph_start = segment_start,
            .glyph_end = segment_start,
            .byte_start = segment_byte_start,
            .byte_end = segment_byte_end,
            .inline_indent = vertical_inline_region.indent(
                options,
                visual_base,
                natural_indent,
            ),
            .starts_segment = true,
            .visual_index = visual_base,
        });
        return;
    }

    const first_indent = @max(0, options.first_line_indent);
    var first_column = true;
    const limit = if (wrapping_enabled and
        options.max_width > 0 and
        std.math.isFinite(options.max_width))
        @max(0, options.max_width - first_indent)
    else
        std.math.inf(f32);
    if (!std.math.isFinite(limit) and
        visual_base >= options.line_regions.len and
        options.exclusions.len == 0)
    {
        try output.append(allocator, .{
            .glyph_start = segment_start,
            .glyph_end = segment_end,
            .byte_start = segment_byte_start,
            .byte_end = segment_byte_end,
            .inline_indent = vertical_inline_region.indent(
                options,
                visual_base,
                first_indent,
            ),
            .starts_segment = true,
            .visual_index = visual_base,
        });
        return;
    }

    var items = std.ArrayList(shared.SoftCandidate).empty;
    defer items.deinit(allocator);
    try candidates.collect(
        &items,
        allocator,
        text,
        glyphs,
        runs,
        variation_coords,
        graphemes,
        breaks,
        segment_start,
        segment_end,
        segment_byte_start,
        segment_byte_end,
        options,
    );
    try candidates.appendBreakSpaces(
        &items,
        allocator,
        glyphs,
        graphemes,
        segment_start,
        segment_end,
        segment_byte_start,
        segment_byte_end,
        options,
    );
    var glyph_start = segment_start;
    var byte_start = segment_byte_start;
    var consecutive_hyphenated_columns: usize = 0;
    var natural_block_edge: f32 = if (output.items.len == 0)
        0
    else block_start: {
        const previous = output.items[output.items.len - 1];
        break :block_start if (options.writing_mode == .vertical_lr)
            previous.block_start + previous.block_size + options.paragraph_spacing
        else
            previous.block_start - options.paragraph_spacing;
    };
    while (glyph_start < segment_end) {
        const visual_index = output.items.len;
        const natural_indent = if (first_column) first_indent else 0;
        const candidate_block_metrics = try vertical_block_metrics.resolve(
            runs,
            glyphs,
            options,
            default_metrics,
            glyph_start,
            segment_end,
        );
        const natural_block_start = if (options.writing_mode == .vertical_lr)
            natural_block_edge
        else
            natural_block_edge - candidate_block_metrics.block_size;
        const resolved_region = try vertical_inline_region.resolve(
            allocator,
            options,
            visual_index,
            natural_block_start,
            @max(
                candidate_block_metrics.block_size,
                recipe.minimumLineHeight(glyph_start, segment_end) orelse 0,
            ),
            natural_indent,
            wrapping_enabled,
        );
        const column_indent = resolved_region.indent;
        const column_limit = resolved_region.inline_size;
        if (measure.occupiedInlineSize(
            glyphs,
            prefix,
            glyph_start,
            segment_end,
            options,
        ) <= column_limit) {
            try output.append(allocator, .{
                .glyph_start = glyph_start,
                .glyph_end = segment_end,
                .byte_start = byte_start,
                .byte_end = segment_byte_end,
                .inline_indent = column_indent,
                .starts_segment = first_column,
                .visual_index = visual_index,
                .block_start = resolved_region.block_start,
                .block_size = candidate_block_metrics.block_size,
                .inline_start = resolved_region.inline_start,
                .inline_size = resolved_region.inline_size,
                .hyphen = null,
            });
            return;
        }
        const overflow = measure.firstOverflow(
            glyphs,
            prefix,
            glyph_start,
            segment_end,
            segment_end,
            column_limit,
            options,
        );
        const visible_hyphen_allowed =
            if (options.hyphenation.max_consecutive_lines) |hyphen_limit|
                consecutive_hyphenated_columns < hyphen_limit
            else
                true;
        const selected = candidates.lastFitting(
            items.items,
            glyphs,
            prefix,
            glyph_start,
            overflow,
            column_limit,
            options,
            visible_hyphen_allowed,
        ) orelse if (policy.emergencyAllowedBefore(
            options,
            glyphs[overflow - 1].sourceByteEnd(),
        ))
            emergency.fittingOrNext(
                glyphs,
                prefix,
                graphemes,
                glyph_start,
                segment_end,
                segment_byte_end,
                overflow,
                column_limit,
                options,
            )
        else
            emergency.afterDisabled(
                candidates.firstUsable(
                    items.items,
                    glyph_start,
                    visible_hyphen_allowed,
                ),
                glyphs,
                graphemes,
                segment_end,
                segment_byte_end,
                overflow,
                options,
            );
        const selected_block_metrics = try vertical_block_metrics.resolve(
            runs,
            glyphs,
            options,
            default_metrics,
            glyph_start,
            selected.glyph_end,
        );
        // RL resolution conservatively tested the complete remaining segment's
        // width. Anchor a narrower selected prefix to that same right edge so
        // mixed-width columns do not acquire an artificial horizontal gap.
        const selected_block_start = if (options.writing_mode == .vertical_lr)
            resolved_region.block_start
        else
            resolved_region.block_start + candidate_block_metrics.block_size -
                selected_block_metrics.block_size;
        try output.append(allocator, .{
            .glyph_start = glyph_start,
            .glyph_end = selected.glyph_end,
            .byte_start = byte_start,
            .byte_end = selected.byte_end,
            .inline_indent = column_indent,
            .starts_segment = first_column,
            .visual_index = visual_index,
            .block_start = selected_block_start,
            // Resolving with the complete remaining segment above is
            // conservative for mixed-width fallback/object columns. Persist
            // the selected range's exact block width for placement and for the
            // following column's block cursor.
            .block_size = selected_block_metrics.block_size,
            .inline_start = resolved_region.inline_start,
            .inline_size = resolved_region.inline_size,
            .hyphen = selected.hyphen,
        });
        glyph_start = selected.next_glyph_start;
        byte_start = selected.byte_end;
        consecutive_hyphenated_columns =
            if (selected.hyphen != null)
                consecutive_hyphenated_columns + 1
            else
                0;
        first_column = false;
        natural_block_edge = if (options.writing_mode == .vertical_lr)
            selected_block_start + selected_block_metrics.block_size
        else
            selected_block_start;
    }
}

fn isMandatory(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

const TestRecipe = struct {
    pub fn minimumLineHeight(_: TestRecipe, _: usize, _: usize) ?f32 {
        return null;
    }
};

fn buildTest(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const GlyphPosition,
    runs: []const run_types.CascadeRun,
    variation_coords: []const f32,
    graphemes: []const unicode.GraphemeCluster,
    breaks: []const line_break_opportunity.Opportunity,
    options: paragraph_options.Options,
) ![]Range {
    return build(
        allocator,
        text,
        glyphs,
        runs,
        variation_coords,
        graphemes,
        breaks,
        options,
        .{ .ascent = 16, .descent = 4, .leading = 0 },
        TestRecipe{},
    );
}

test "vertical emergency break defers across unsafe output boundaries" {
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
    };
    const graphemes = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = 1 },
        .{ .byte_start = 1, .byte_len = 1 },
    };
    const ranges = try buildTest(
        std.testing.allocator,
        "AA",
        &glyphs,
        &.{},
        &.{},
        &graphemes,
        &.{},
        .{ .max_width = 20.1, .writing_mode = .vertical_lr },
    );
    defer std.testing.allocator.free(ranges);
    try std.testing.expectEqual(@as(usize, 1), ranges.len);
    try std.testing.expectEqual(@as(usize, 2), ranges[0].glyph_end);

    const break_all = try buildTest(
        std.testing.allocator,
        "AA",
        &glyphs,
        &.{},
        &.{},
        &graphemes,
        &.{},
        .{
            .max_width = 20.1,
            .word_break = .break_all,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_lr,
        },
    );
    defer std.testing.allocator.free(break_all);
    // Policy-generated grapheme candidates remain subordinate to shaping
    // safety; `break-all` cannot split an unsafe positioning relationship.
    try std.testing.expectEqual(@as(usize, 1), break_all.len);
    try std.testing.expectEqual(@as(usize, 2), break_all[0].glyph_end);
}

test "vertical dictionary opportunity respects unsafe shaped boundary" {
    const allocator = std.testing.allocator;
    const text = "กข";
    var dictionary =
        try @import("../../../text/segmentation/root.zig")
            .WordBreakDictionary.init(
            allocator,
            .thai,
            &.{ "ก", "ข" },
        );
    defer dictionary.deinit();
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'ก',
            .cluster = 0,
            .source_byte_len = "ก".len,
            .x_advance = 0,
            .y_advance = 20,
        },
        .{
            .glyph_id = 2,
            .codepoint = 'ข',
            .cluster = "ก".len,
            .source_byte_len = "ข".len,
            .x_advance = 0,
            .y_advance = 20,
            .flags = .{ .unsafe_to_break_before = true },
        },
    };
    const graphemes = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = "ก".len },
        .{ .byte_start = "ก".len, .byte_len = "ข".len },
    };
    const breaks =
        try @import("../../line_break/analysis.zig").itemizeWithHyphenation(
            allocator,
            text,
            &graphemes,
            &dictionary,
            null,
            .{
                .wrap_mode = .word,
                .word_break = .normal,
                .overflow_wrap = .normal,
            },
            &.{},
        );
    defer allocator.free(breaks);
    var saw_dictionary_boundary = false;
    for (breaks) |item| {
        if (item.kind == .soft and item.byte_offset == "ก".len) {
            saw_dictionary_boundary = true;
        }
    }
    try std.testing.expect(saw_dictionary_boundary);

    const ranges = try buildTest(
        allocator,
        text,
        &glyphs,
        &.{},
        &.{},
        &graphemes,
        breaks,
        .{
            .max_width = 20.1,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_lr,
        },
    );
    defer allocator.free(ranges);
    try std.testing.expectEqual(@as(usize, 1), ranges.len);
    try std.testing.expectEqual(@as(usize, glyphs.len), ranges[0].glyph_end);
}

test "vertical automatic hyphen opportunity respects unsafe shaped boundary" {
    const allocator = std.testing.allocator;
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
            .glyph_id = 2,
            .codepoint = 'B',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 0,
            .y_advance = 20,
            .flags = .{ .unsafe_to_break_before = true },
        },
    };
    const graphemes = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = 1 },
        .{ .byte_start = 1, .byte_len = 1 },
    };
    // No run is needed to resolve the visible glyph: the unsafe source edge
    // must reject the automatic opportunity first.
    const ranges = try buildTest(
        allocator,
        "AB",
        &glyphs,
        &.{},
        &.{},
        &graphemes,
        &.{.{
            .byte_offset = 1,
            .kind = .soft,
            .automatic_hyphen = true,
        }},
        .{
            .max_width = 20.1,
            .overflow_wrap = .normal,
            .writing_mode = .vertical_lr,
        },
    );
    defer allocator.free(ranges);
    try std.testing.expectEqual(@as(usize, 1), ranges.len);
    try std.testing.expectEqual(@as(usize, glyphs.len), ranges[0].glyph_end);
}
