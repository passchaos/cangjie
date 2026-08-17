//! Greedy paragraph reflow over an immutable shaped glyph stream.
//!
//! This module owns line selection and delegates three orthogonal concerns:
//! source opportunity mapping, line geometry/metrics, and truncation.

const std = @import("std");

const analysis = @import("../analysis.zig");
const automatic_hyphens = @import("automatic_hyphens.zig");
const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const geometry = @import("geometry.zig");
const horizontal_justification =
    @import("../../justification/horizontal.zig");
const jstf_shrinkage =
    @import("../../justification/jstf/shrinkage.zig");
const inline_object = @import("../../inline_object/root.zig");
const opportunities = @import("opportunities.zig");
const punctuation_compression = @import("../../punctuation/compression.zig");
const punctuation_hanging = @import("../../punctuation/hanging.zig");
const segmentation = @import("../../../text/segmentation/root.zig");
const shaped_boundary = @import("../shaped_boundary.zig");
const truncation = @import("truncation.zig");
const unicode = @import("../../../unicode.zig");

pub const BaselineMetrics = geometry.BaselineMetrics;
pub const alignedLineX = geometry.alignedLineX;
pub const defaultBaselineMetrics = geometry.defaultBaselineMetrics;
pub const resolvedAlignment = geometry.resolvedAlignment;
pub const runRangeForGlyphs = geometry.runRangeForGlyphs;

pub fn build(
    buffer: anytype,
    text: []const u8,
    options: anytype,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const @import("../opportunity.zig").Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
) !void {
    return buildWithJstfShrinkage(
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
        hyphenation_dictionary,
        NoShrinkageRecipe{},
    );
}

/// Build lines while allowing an OpenType JSTF recipe to shrink an overflowing
/// source prefix before the greedy breaker commits a wrap.
pub fn buildWithJstfShrinkage(
    buffer: anytype,
    text: []const u8,
    options: anytype,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const @import("../opportunity.zig").Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
    recipe: anytype,
) !void {
    buffer.lines.clearRetainingCapacity();
    const max_width = if (options.max_width > 0)
        options.max_width
    else
        std.math.inf(f32);
    const wrap_width = if (options.wrap_mode == .no_wrap)
        std.math.inf(f32)
    else
        max_width;
    const alignment = geometry.resolvedAlignment(options);
    var line_start: usize = 0;
    var line_byte_start: usize = 0;
    var line_width: f32 = 0;
    var last_break = opportunities.Candidate{};
    var y: f32 = 0;
    var index: usize = 0;
    var line_in_paragraph: usize = 0;
    var consecutive_hyphenated_lines: usize = 0;
    var terminal_emergency_line_committed = false;
    const max_lines = options.max_lines orelse std.math.maxInt(usize);
    var selected_automatic_hyphens =
        std.ArrayList(automatic_hyphens.Selected).empty;
    defer selected_automatic_hyphens.deinit(buffer.allocator);
    const space_advance = geometry.defaultSpaceAdvance(buffer.glyphs.items);
    const tab_stop =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) * space_advance;

    // Retained paragraphs carry width-independent grapheme and line-break
    // analysis. One-shot layout allocates only when emergency wrapping or a
    // dictionary tailoring requires those boundaries.
    var owned_graphemes: ?[]unicode.GraphemeCluster = null;
    defer if (owned_graphemes) |clusters| buffer.allocator.free(clusters);
    const grapheme_clusters = analyzed_graphemes orelse clusters: {
        if (options.wrap_mode == .no_wrap) break :clusters &.{};
        owned_graphemes = try unicode.itemizeGraphemeClusters(
            buffer.allocator,
            text,
        );
        break :clusters owned_graphemes.?;
    };
    var owned_line_breaks: ?[]@import("../opportunity.zig").Opportunity = null;
    defer if (owned_line_breaks) |breaks| buffer.allocator.free(breaks);
    const effective_line_breaks = analyzed_line_breaks orelse breaks: {
        if (dictionary == null and hyphenation_dictionary == null) {
            break :breaks null;
        }
        if (options.wrap_mode == .no_wrap) break :breaks null;
        owned_line_breaks = try analysis.itemizeWithHyphenation(
            buffer.allocator,
            text,
            grapheme_clusters,
            dictionary,
            hyphenation_dictionary,
        );
        break :breaks owned_line_breaks.?;
    };
    var line_breaks = opportunities.Cursor.init(text, effective_line_breaks);

    // Greedy wrapping tracks the newest reusable soft opportunity. On
    // overflow it prefers that candidate and otherwise advances to the first
    // safe grapheme boundary, never splitting a shaped source atom.
    glyph_loop: while (index < buffer.glyphs.items.len) : (index += 1) {
        var glyph = &buffer.glyphs.items[index];
        if (glyph.isInlineObject()) {
            const object = inline_object.find(
                options.inline_objects,
                glyph.cluster,
            ) orelse return error.InvalidInlineObjects;
            glyph.x_advance =
                if (object.kind == .in_flow) object.width else 0;
        }
        if (opportunities.isMandatory(glyph.codepoint)) {
            const break_end_index =
                if (glyph.codepoint == '\r' and
                index + 1 < buffer.glyphs.items.len and
                buffer.glyphs.items[index + 1].codepoint == '\n')
                    index + 2
                else
                    index + 1;
            const line_byte_end = shaped_boundary.glyphSourceEnd(
                buffer.glyphs.items[break_end_index - 1],
            );
            const line_info = geometry.lineRunInfo(
                buffer.runs.items,
                buffer.glyphs.items,
                options.inline_objects,
                line_start,
                index,
                default_metrics,
                options.line_height,
            );
            try geometry.appendLine(
                buffer,
                line_start,
                index,
                line_byte_start,
                line_byte_end,
                line_width,
                line_info,
                y,
                alignment,
                max_width,
                geometry.lineIndent(line_in_paragraph, options),
                null,
            );
            if (buffer.lines.items.len >= max_lines) {
                try automatic_hyphens.materialize(
                    buffer,
                    selected_automatic_hyphens.items,
                );
                try truncation.apply(
                    buffer,
                    max_lines,
                    options.ellipsis,
                    max_width,
                    alignment,
                    true,
                );
                return;
            }
            y += line_info.metrics.lineHeight() + options.paragraph_spacing;
            line_breaks.discardThrough(shaped_boundary.glyphSourceEnd(
                buffer.glyphs.items[break_end_index - 1],
            ));
            line_start = break_end_index;
            line_byte_start = line_byte_end;
            line_width = 0;
            last_break.reset();
            consecutive_hyphenated_lines = 0;
            line_in_paragraph = 0;
            index = break_end_index - 1;
            continue :glyph_loop;
        }

        if (glyph.codepoint == '\t') {
            // Tabs depend on the current line pen, not only font metrics.
            glyph.x_advance = geometry.tabAdvance(
                line_width,
                tab_stop,
                space_advance,
            );
        }
        glyph.x_advance += geometry.spacingForGlyph(glyph.codepoint, options);
        line_width += glyph.x_advance;
        const current_line_limit = geometry.lineWidthLimit(
            line_in_paragraph,
            wrap_width,
            options,
        );
        // A hanging punctuation glyph may cross the inline-end measure while
        // remaining on this line. Delay overflow until the occupied portion,
        // rather than the complete glyph advance, exceeds the limit. The
        // opportunity after this source atom is recorded below and becomes the
        // preferred boundary if a following glyph overflows.
        const current_hanging_amount = punctuation_hanging.logicalEndAmount(
            buffer.glyphs.items,
            line_start,
            index + 1,
            options.punctuation.end_hanging_fraction,
        );
        const current_compression_capacity =
            punctuation_compression.effectiveCapacity(
                buffer.glyphs.items,
                line_start,
                index + 1,
                options.punctuation.max_compression_fraction,
                options.punctuation.end_hanging_fraction,
                options.punctuation.convention,
            );
        const overflow_allowance = @max(
            current_compression_capacity,
            current_hanging_amount,
        );
        if (line_width > current_line_limit + overflow_allowance and
            index + 1 > line_start)
        {
            const shrinkage = try jstf_shrinkage.tryFit(
                buffer,
                recipe,
                line_start,
                index + 1,
                current_line_limit + overflow_allowance,
            );
            if (shrinkage.applied) {
                const old_range_end = index + 1;
                const glyph_delta: isize =
                    @as(isize, @intCast(shrinkage.glyph_len)) -
                    @as(isize, @intCast(old_range_end - line_start));
                automatic_hyphens.shiftAfterReplacement(
                    selected_automatic_hyphens.items,
                    old_range_end,
                    glyph_delta,
                    buffer.runs.items,
                );
                line_width = shrinkage.width;
                index = line_start + shrinkage.glyph_len - 1;
                last_break.reset();
                line_breaks = opportunities.Cursor.init(
                    text,
                    effective_line_breaks,
                );
                line_breaks.discardThrough(line_byte_start);
                try rebuildLastBreak(
                    &line_breaks,
                    buffer,
                    options,
                    line_start,
                    index,
                    line_width,
                    &last_break,
                );
                continue :glyph_loop;
            }
            // Discretionary opportunities include visible hyphen width. Reject
            // a candidate that would overflow even after taking the break.
            const automatic_limit_reached =
                if (options.hyphenation.max_consecutive_lines) |limit|
                    consecutive_hyphenated_lines >= limit
                else
                    false;
            const candidate_is_limited_hyphen =
                last_break.hasVisibleHyphen() and
                automatic_limit_reached;
            const fitting_last_break = candidate: {
                const candidate_index =
                    last_break.glyph_index orelse break :candidate null;
                if (candidate_is_limited_hyphen) break :candidate null;
                // A selected discretionary boundary adds a visible hyphen
                // after this prefix. The preceding source glyph is therefore
                // no longer at logical line end and cannot contribute hanging.
                const candidate_hanging_fraction: f32 =
                    if (last_break.hasVisibleHyphen())
                        0
                    else
                        options.punctuation.end_hanging_fraction;
                const candidate_hanging = punctuation_hanging.logicalEndAmount(
                    buffer.glyphs.items,
                    line_start,
                    candidate_index,
                    candidate_hanging_fraction,
                );
                const candidate_compression =
                    punctuation_compression.effectiveCapacity(
                        buffer.glyphs.items,
                        line_start,
                        candidate_index,
                        options.punctuation.max_compression_fraction,
                        candidate_hanging_fraction,
                        options.punctuation.convention,
                    );
                if (@max(0, last_break.width - candidate_hanging) >
                    current_line_limit + candidate_compression)
                {
                    break :candidate null;
                }
                break :candidate candidate_index;
            };
            const overflow_break = shaped_boundary.chooseOverflowBreak(
                buffer.glyphs.items,
                grapheme_clusters,
                index,
                line_start,
                fitting_last_break,
            );
            if (overflow_break.defer_break) continue;
            const break_end = overflow_break.index;
            const uses_last_break = fitting_last_break != null and
                break_end == fitting_last_break.?;
            const break_width = if (overflow_break.uses_current_discardable)
                line_width - glyph.x_advance
            else if (uses_last_break)
                last_break.width
            else
                geometry.lineWidth(
                    buffer.glyphs.items[line_start..break_end],
                );
            var selected_visible_hyphen = false;
            if (uses_last_break) {
                if (last_break.hyphen) |candidate| {
                    discretionary_hyphen.materialize(
                        &buffer.glyphs.items[candidate.glyph_index],
                        candidate.resolved,
                    );
                    selected_visible_hyphen = true;
                } else if (last_break.automatic_hyphen) |candidate| {
                    try automatic_hyphens.appendSelected(
                        &selected_automatic_hyphens,
                        buffer.allocator,
                        buffer.lines.items.len,
                        break_end,
                        candidate,
                    );
                    selected_visible_hyphen = true;
                }
            }
            var next_line_start = break_end;
            geometry.trimLeadingSoftBreaks(
                buffer.glyphs.items,
                &next_line_start,
            );
            // Discarded boundary spaces remain in the preceding logical source
            // range, keeping line ranges contiguous for bidi and caret maps.
            const line_byte_end = shaped_boundary.byteEndForGlyphPrefix(
                buffer.glyphs.items,
                next_line_start,
                line_byte_start,
            );
            const justify_line =
                next_line_start < buffer.glyphs.items.len and
                buffer.lines.items.len + 1 < max_lines;
            const indent = geometry.lineIndent(line_in_paragraph, options);
            const justification_target =
                if (justify_line and alignment == .justify)
                    @max(
                        break_width,
                        geometry.lineWidthLimitForIndent(max_width, indent),
                    )
                else
                    null;
            const line_info = geometry.lineRunInfo(
                buffer.runs.items,
                buffer.glyphs.items,
                options.inline_objects,
                line_start,
                break_end,
                default_metrics,
                options.line_height,
            );
            try geometry.appendLine(
                buffer,
                line_start,
                break_end,
                line_byte_start,
                line_byte_end,
                break_width,
                line_info,
                y,
                alignment,
                max_width,
                indent,
                justification_target,
            );
            if (buffer.lines.items.len >= max_lines) {
                try automatic_hyphens.materialize(
                    buffer,
                    selected_automatic_hyphens.items,
                );
                try truncation.apply(
                    buffer,
                    max_lines,
                    options.ellipsis,
                    max_width,
                    alignment,
                    true,
                );
                // Truncation makes this the terminal visible line. A pending
                // target would otherwise trigger Kashida/space expansion even
                // though terminal and ellipsized lines are never justified.
                if (buffer.lines.items.len != 0) {
                    buffer.lines.items[
                        buffer.lines.items.len - 1
                    ].justification_target = null;
                }
                return;
            }
            y += line_info.metrics.lineHeight();
            line_in_paragraph += 1;
            consecutive_hyphenated_lines =
                if (selected_visible_hyphen)
                    consecutive_hyphenated_lines + 1
                else
                    0;
            line_start = next_line_start;
            line_byte_start = shaped_boundary.byteEndForGlyphPrefix(
                buffer.glyphs.items,
                line_start,
                line_byte_end,
            );
            if (line_start > index + 1) {
                // An emergency break after an over-wide glyph can be followed
                // by one or more spaces that have not reached the glyph loop
                // yet. `trimLeadingSoftBreaks` intentionally assigns those
                // source bytes to the preceding logical line, so skip their
                // glyph slots as well. Recomputing a width over
                // `[line_start..index + 1]` would otherwise form a reversed
                // slice, and merely clamping the slice would count the trimmed
                // spaces again on the following iterations.
                line_width = 0;
                terminal_emergency_line_committed =
                    break_end == buffer.glyphs.items.len;
                last_break.reset();
                index = line_start - 1;
                continue :glyph_loop;
            }
            line_width = geometry.lineWidth(
                buffer.glyphs.items[line_start .. index + 1],
            );
            terminal_emergency_line_committed =
                break_end == buffer.glyphs.items.len;
            last_break.reset();
        }
        const atom_continues =
            index + 1 < buffer.glyphs.items.len and
            shaped_boundary.glyphClusterStart(
                buffer.glyphs.items[index + 1],
            ) == shaped_boundary.glyphClusterStart(glyph.*);
        if (!atom_continues) {
            const glyph_source_end = shaped_boundary.glyphSourceEnd(glyph.*);
            while (line_breaks.nextThrough(glyph_source_end)) |line_break| {
                switch (line_break.kind) {
                    .soft => try opportunities.recordSoft(
                        buffer.glyphs.items,
                        buffer.runs.items,
                        line_break.byte_offset,
                        index,
                        line_start,
                        line_width,
                        &last_break,
                        options.normalized_variation_coords,
                        line_break.automatic_hyphen,
                        options.hyphenation.character,
                    ),
                    .hard => {},
                }
            }
        }
    }

    // A final emergency break may consume the entire last shaped atom. Avoid
    // fabricating an empty line unless the source actually ended in a hard
    // separator.
    if (!terminal_emergency_line_committed) {
        const line_info = geometry.lineRunInfo(
            buffer.runs.items,
            buffer.glyphs.items,
            options.inline_objects,
            line_start,
            buffer.glyphs.items.len,
            default_metrics,
            options.line_height,
        );
        try geometry.appendLine(
            buffer,
            line_start,
            buffer.glyphs.items.len,
            line_byte_start,
            text.len,
            line_width,
            line_info,
            y,
            alignment,
            max_width,
            geometry.lineIndent(line_in_paragraph, options),
            null,
        );
    }
    try truncation.apply(
        buffer,
        max_lines,
        options.ellipsis,
        max_width,
        alignment,
        false,
    );
    try automatic_hyphens.materialize(
        buffer,
        selected_automatic_hyphens.items,
    );
}

const NoShrinkageRecipe = struct {
    pub fn canShrinkSourceRange(_: @This(), _: usize, _: usize) bool {
        return false;
    }

    pub fn jstfTags(
        _: @This(),
        _: usize,
        _: usize,
    ) struct {
        script: unicode.OpenTypeScriptTag,
        language: unicode.OpenTypeLanguageTag,
    } {
        return .{ .script = .dflt, .language = .dflt };
    }

    pub fn shapeRangeWithJstfPriority(
        _: @This(),
        _: anytype,
        _: usize,
        _: usize,
        _: anytype,
        _: usize,
        _: anytype,
        _: []const usize,
    ) !void {
        unreachable;
    }

    pub fn prepareCommit(
        _: @This(),
        _: usize,
        _: usize,
        _: usize,
    ) !void {
        unreachable;
    }

    pub fn commit(_: @This(), _: usize, _: usize, _: usize) void {
        unreachable;
    }
};

fn rebuildLastBreak(
    line_breaks: *opportunities.Cursor,
    buffer: anytype,
    options: anytype,
    line_start: usize,
    index: usize,
    line_width: f32,
    candidate: *opportunities.Candidate,
) !void {
    const glyph_source_end = shaped_boundary.glyphSourceEnd(
        buffer.glyphs.items[index],
    );
    while (line_breaks.nextThrough(glyph_source_end)) |line_break| {
        switch (line_break.kind) {
            .soft => try opportunities.recordSoft(
                buffer.glyphs.items,
                buffer.runs.items,
                line_break.byte_offset,
                index,
                line_start,
                line_width,
                candidate,
                options.normalized_variation_coords,
                line_break.automatic_hyphen,
                options.hyphenation.character,
            ),
            .hard => {},
        }
    }
}

/// Apply generic spacing after any source-level line reshaping has finished.
///
/// Kashida consumes part of a line's target first. Spaces or conservative CJK
/// boundaries receive only the remainder, so the two mechanisms cannot both
/// independently claim the complete measure.
pub fn applyPendingJustification(buffer: anytype) void {
    for (buffer.lines.items) |*line| {
        const target = line.justification_target orelse continue;
        const line_end = line.glyph_start + line.glyph_len;
        const natural_width = geometry.lineWidth(
            buffer.glyphs.items[line.glyph_start..line_end],
        );
        line.width = horizontal_justification.apply(
            buffer.glyphs.items[line.glyph_start..line_end],
            natural_width,
            target,
        );
        line.justification_target = null;
    }
}
