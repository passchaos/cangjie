//! Greedy paragraph reflow over an immutable shaped glyph stream.
//!
//! This module owns line selection and delegates three orthogonal concerns:
//! source opportunity mapping, line geometry/metrics, and truncation.

const std = @import("std");

const analysis = @import("../analysis.zig");
const automatic_hyphens = @import("automatic_hyphens.zig");
const balanced = @import("balanced.zig");
const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const geometry = @import("geometry.zig");
const horizontal_justification =
    @import("../../justification/horizontal.zig");
const jstf_shrinkage =
    @import("../../justification/jstf/shrinkage.zig");
const inline_object = @import("../../inline_object/root.zig");
const line_break_opportunity = @import("../opportunity.zig");
const opportunities = @import("opportunities.zig");
const paragraph_options = @import("../../paragraph/options.zig");
const punctuation_compression = @import("../../punctuation/compression.zig");
const punctuation_hanging = @import("../../punctuation/hanging.zig");
const regions = @import("regions.zig");
const tabs = @import("../../paragraph/tabs.zig");
const white_space = @import("../../paragraph/white_space.zig");
const segmentation = @import("../../../text/segmentation/root.zig");
const shaped_boundary = @import("../shaped_boundary.zig");
const truncation = @import("truncation.zig");
const unicode = @import("../../../unicode.zig");

pub const BaselineMetrics = geometry.BaselineMetrics;
pub const alignedLineX = geometry.alignedLineX;
pub const defaultBaselineMetrics = geometry.defaultBaselineMetrics;
pub const resolvedAlignment = geometry.resolvedAlignment;
pub const runRangeForGlyphs = geometry.runRangeForGlyphs;

const state_mod = @import("greedy/state.zig");

pub const Advance = state_mod.Advance;
pub const State = state_mod.State;

pub fn buildWithPlan(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
    recipe: anytype,
    balance_plan: ?*const balanced.Plan,
) !void {
    var state = State.init(buffer.allocator);
    defer state.deinit();
    try begin(
        &state,
        buffer,
        text,
        options,
        default_metrics,
        analyzed_graphemes,
        analyzed_line_breaks,
        dictionary,
        hyphenation_dictionary,
    );
    while (try advanceWithPlan(
        &state,
        buffer,
        text,
        options,
        default_metrics,
        recipe,
        balance_plan,
    ) == .line) {}
}

/// Initialize a persistent greedy reflow.
///
/// This performs width-dependent analysis tailoring and mutable advance
/// preparation once. Subsequent `advance` calls commit at most one visual line.
pub fn begin(
    state: *State,
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: BaselineMetrics,
    analyzed_graphemes: ?[]const unicode.GraphemeCluster,
    analyzed_line_breaks: ?[]const line_break_opportunity.Opportunity,
    dictionary: ?*const segmentation.WordBreakDictionary,
    hyphenation_dictionary: ?*const @import("../../../text/hyphenation/root.zig").Dictionary,
) !void {
    if (state.owned_line_breaks) |items| {
        state.allocator.free(items);
        state.owned_line_breaks = null;
    }
    if (state.owned_graphemes) |items| {
        state.allocator.free(items);
        state.owned_graphemes = null;
    }
    state.selected_automatic_hyphens.clearRetainingCapacity();
    buffer.lines.clearRetainingCapacity();
    state.max_width = if (options.max_width > 0)
        options.max_width
    else
        std.math.inf(f32);
    state.alignment = geometry.resolvedAlignment(options);
    state.uses_exclusions =
        options.wrap_mode != .no_wrap and options.exclusions.len != 0;
    state.max_lines = options.max_lines orelse std.math.maxInt(usize);
    state.initialized = true;
    state.complete = state.max_lines == 0;
    if (state.complete) {
        buffer.runs.clearRetainingCapacity();
        buffer.glyphs.clearRetainingCapacity();
        return;
    }
    state.line_start = 0;
    state.line_byte_start = 0;
    state.line_width = 0;
    state.last_break = .{};
    state.y = 0;
    state.index = 0;
    state.line_in_paragraph = 0;
    state.region_height = requestedLineHeight(
        default_metrics,
        options.line_height,
    );
    state.active_region = try regions.preview(
        buffer.allocator,
        options,
        state.line_in_paragraph,
        buffer.lines.items.len,
        state.y,
        state.region_height,
        state.max_width,
    );
    state.consecutive_hyphenated_lines = 0;
    state.terminal_emergency_line_committed = false;
    state.space_advance = geometry.defaultSpaceAdvance(buffer.glyphs.items);
    state.fallback_tab_interval =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) *
        state.space_advance;
    try prepareAdvances(buffer.glyphs.items, options);
    white_space.prepare(
        buffer.glyphs.items,
        options.white_space_collapse,
        state.space_advance,
    );

    // Retained paragraphs carry width-independent grapheme and line-break
    // analysis. One-shot layout allocates only when emergency wrapping or a
    // dictionary tailoring requires those boundaries.
    state.grapheme_clusters = analyzed_graphemes orelse clusters: {
        if (options.wrap_mode == .no_wrap) break :clusters &.{};
        state.owned_graphemes = try unicode.itemizeGraphemeClusters(
            buffer.allocator,
            text,
        );
        break :clusters state.owned_graphemes.?;
    };
    state.effective_line_breaks = breaks: {
        if (analyzed_line_breaks) |base| {
            if (options.word_break == .normal and
                options.overflow_wrap != .anywhere)
            {
                break :breaks base;
            }
            state.owned_line_breaks = try analysis.tailorBreakPolicy(
                buffer.allocator,
                text,
                state.grapheme_clusters,
                base,
                options.word_break,
                options.overflow_wrap,
            );
            break :breaks state.owned_line_breaks.?;
        }
        if (dictionary == null and
            hyphenation_dictionary == null and
            options.word_break == .normal and
            options.overflow_wrap != .anywhere)
        {
            break :breaks null;
        }
        if (options.wrap_mode == .no_wrap) break :breaks null;
        state.owned_line_breaks = try analysis.itemizeWithHyphenation(
            buffer.allocator,
            text,
            state.grapheme_clusters,
            dictionary,
            hyphenation_dictionary,
            options.word_break,
            options.overflow_wrap,
        );
        break :breaks state.owned_line_breaks.?;
    };
    state.line_breaks = opportunities.Cursor.init(
        text,
        state.effective_line_breaks,
    );
}

/// Commit at most one line from a persistent greedy reflow.
pub fn advance(
    state: *State,
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: BaselineMetrics,
    recipe: anytype,
) !Advance {
    return advanceWithPlan(
        state,
        buffer,
        text,
        options,
        default_metrics,
        recipe,
        null,
    );
}

/// Refresh the uncommitted line's prospective geometry.
///
/// Incremental callers may append or replace the explicit region for the next
/// visual line between advances. No source or cursor state changes here.
pub fn refreshRegion(
    state: *State,
    buffer: anytype,
    options: paragraph_options.Options,
) !void {
    if (!state.initialized) return error.ParagraphBreakerNotInitialized;
    if (state.complete) return;
    state.active_region = try regions.preview(
        buffer.allocator,
        options,
        state.line_in_paragraph,
        buffer.lines.items.len,
        state.y,
        state.region_height,
        state.max_width,
    );
}

fn advanceWithPlan(
    state: *State,
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: BaselineMetrics,
    recipe: anytype,
    balance_plan: ?*const balanced.Plan,
) !Advance {
    if (!state.initialized) return error.ParagraphBreakerNotInitialized;
    if (state.complete) return .complete;

    const max_width = state.max_width;
    const alignment = state.alignment;
    const uses_exclusions = state.uses_exclusions;
    const max_lines = state.max_lines;
    var line_start = state.line_start;
    var line_byte_start = state.line_byte_start;
    var line_width = state.line_width;
    var last_break = state.last_break;
    var y = state.y;
    var index = state.index;
    var line_in_paragraph = state.line_in_paragraph;
    var region_height = state.region_height;
    var active_region = state.active_region;
    var consecutive_hyphenated_lines =
        state.consecutive_hyphenated_lines;
    var terminal_emergency_line_committed =
        state.terminal_emergency_line_committed;
    var selected_automatic_hyphens =
        state.selected_automatic_hyphens;
    defer state.selected_automatic_hyphens =
        selected_automatic_hyphens;
    const space_advance = state.space_advance;
    const fallback_tab_interval = state.fallback_tab_interval;
    const grapheme_clusters = state.grapheme_clusters;
    const effective_line_breaks = state.effective_line_breaks;
    var line_breaks = state.line_breaks;

    // Greedy wrapping tracks the newest reusable soft opportunity. On
    // overflow it prefers that candidate and otherwise advances to the first
    // safe grapheme boundary, never splitting a shaped source atom.
    glyph_loop: while (index < buffer.glyphs.items.len) : (index += 1) {
        var glyph = &buffer.glyphs.items[index];
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
            const line_info = geometry.resolvedLineInfo(
                buffer.runs.items,
                buffer.glyphs.items,
                options.inline_objects,
                line_start,
                index,
                default_metrics,
                options.line_height,
                recipe.minimumLineHeight(line_start, index),
            );
            const line_region = try regions.resolve(
                buffer.allocator,
                options,
                line_in_paragraph,
                buffer.lines.items.len,
                &y,
                line_info.metrics.lineHeight(),
                max_width,
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
                lineAlignment(
                    buffer.glyphs.items[line_start..index],
                    alignment,
                    options.direction,
                ),
                line_region,
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
                    options,
                );
                state.complete = true;
                return .line;
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
            region_height = requestedLineHeight(
                default_metrics,
                options.line_height,
            );
            active_region = try regions.preview(
                buffer.allocator,
                options,
                line_in_paragraph,
                buffer.lines.items.len,
                y,
                region_height,
                max_width,
            );
            // The hard separator has been consumed. Resume at the first glyph
            // of the following paragraph segment rather than replaying the
            // already committed line on the next call.
            index = break_end_index;
            state.capture(
                line_start,
                line_byte_start,
                line_width,
                last_break,
                y,
                index,
                line_in_paragraph,
                region_height,
                active_region,
                consecutive_hyphenated_lines,
                terminal_emergency_line_committed,
                line_breaks,
            );
            return .line;
        }

        if (glyph.isActiveTab()) {
            // Tabs depend on the current line pen, not only font metrics.
            const explicit_stop = tabs.nextExplicitStop(
                line_width,
                options.tab_stops,
            );
            glyph.x_advance = tabs.advance(
                line_width,
                options.tab_stops,
                fallback_tab_interval,
                space_advance,
                tabs.measureField(
                    buffer.glyphs.items,
                    index + 1,
                    if (explicit_stop) |stop|
                        stop.decimal_point
                    else
                        '.',
                    0,
                ),
            );
        }
        line_width += glyph.x_advance;
        if (uses_exclusions) {
            const next_region_height = @max(
                region_height,
                glyphLineHeight(
                    buffer.runs.items,
                    buffer.glyphs.items,
                    options.inline_objects,
                    index,
                    default_metrics,
                    options.line_height,
                    recipe.minimumLineHeight(index, index + 1),
                ),
            );
            if (next_region_height > region_height) {
                region_height = next_region_height;
                // The complete prospective line band determines its fragment.
                // Overflow still follows the normal safe-break path below; a
                // tall glyph must not create an ad-hoc break inside a shaped
                // atom or bypass discretionary-hyphen and punctuation policy.
                active_region = try regions.preview(
                    buffer.allocator,
                    options,
                    line_in_paragraph,
                    buffer.lines.items.len,
                    y,
                    region_height,
                    max_width,
                );
            }
        }
        const current_region = active_region;
        const current_line_limit = if (options.wrap_mode == .no_wrap)
            std.math.inf(f32)
        else
            current_region.width;
        const atom_continues =
            index + 1 < buffer.glyphs.items.len and
            shaped_boundary.glyphClusterStart(
                buffer.glyphs.items[index + 1],
            ) == shaped_boundary.glyphClusterStart(glyph.*);
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
        const naturally_overflows =
            line_width > current_line_limit + overflow_allowance;
        // Preserve greedy's look-behind semantics: an opportunity becomes the
        // preferred candidate after its source atom is complete, but only the
        // balanced pass can force an immediate commit at that edge.
        if (!naturally_overflows and !atom_continues) {
            const glyph_source_end = shaped_boundary.glyphSourceEnd(glyph.*);
            while (line_breaks.nextThrough(glyph_source_end)) |line_break| {
                switch (line_break.kind) {
                    .soft => {
                        var candidate = opportunities.Candidate{};
                        try opportunities.recordSoft(
                            buffer.glyphs.items,
                            buffer.runs.items,
                            line_break.byte_offset,
                            index,
                            line_start,
                            line_width,
                            &candidate,
                            options.normalized_variation_coords,
                            line_break.automatic_hyphen,
                            line_break.arbitrary,
                            options.hyphenation.character,
                        );
                        if (candidate.glyph_index != null) {
                            last_break = candidate;
                        }
                    },
                    .hard => {},
                }
            }
            if (options.white_space_collapse == .break_spaces) {
                opportunities.recordBreakSpaces(
                    buffer.glyphs.items,
                    index,
                    line_start,
                    line_width,
                    &last_break,
                );
            }
        }
        // Direct boundary synthesis is both the zero-allocation one-shot fast
        // path and a fallback for retained streams whose policy-neutral base
        // analysis contains no matching arbitrary record.
        if (!naturally_overflows and
            !atom_continues and
            !geometry.isDiscardableBreak(glyph.codepoint) and
            (options.word_break == .break_all or
                options.overflow_wrap == .anywhere) and
            index + 1 < buffer.glyphs.items.len and
            shaped_boundary.outputBoundaryIsReusable(
                buffer.glyphs.items,
                grapheme_clusters,
                index + 1,
            ))
        {
            last_break = .{
                .glyph_index = index + 1,
                .width = line_width,
                .arbitrary = true,
            };
        }
        const forced_balance_break = !naturally_overflows and
            balanced.shouldBreakAtTarget(
                balance_plan,
                buffer.lines.items.len,
                index + 1,
            );
        if ((naturally_overflows or
            forced_balance_break) and
            index + 1 > line_start)
        {
            const shrinkage = if (forced_balance_break)
                jstf_shrinkage.Result{}
            else
                try jstf_shrinkage.tryFit(
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
                if (uses_exclusions) {
                    // Source-level JSTF replacement can change run metrics as
                    // well as glyph count. Refresh the prospective band before
                    // measuring the next source atom against exclusions.
                    region_height = lineHeightForRange(
                        buffer.runs.items,
                        buffer.glyphs.items,
                        options.inline_objects,
                        line_start,
                        index + 1,
                        default_metrics,
                        options.line_height,
                        recipe.minimumLineHeight(line_start, index + 1),
                    );
                    active_region = try regions.preview(
                        buffer.allocator,
                        options,
                        line_in_paragraph,
                        buffer.lines.items.len,
                        y,
                        region_height,
                        max_width,
                    );
                }
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
            var fitting_last_break = candidate: {
                const candidate_index =
                    last_break.glyph_index orelse break :candidate null;
                if (candidate_is_limited_hyphen) break :candidate null;
                const candidate_width_limit = if (!uses_exclusions)
                    current_line_limit
                else candidate_limit: {
                    const candidate_height = lineHeightForRange(
                        buffer.runs.items,
                        buffer.glyphs.items,
                        options.inline_objects,
                        line_start,
                        candidate_index,
                        default_metrics,
                        options.line_height,
                        recipe.minimumLineHeight(line_start, candidate_index),
                    );
                    const candidate_region = try regions.preview(
                        buffer.allocator,
                        options,
                        line_in_paragraph,
                        buffer.lines.items.len,
                        y,
                        candidate_height,
                        max_width,
                    );
                    break :candidate_limit candidate_region.width;
                };
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
                const candidate_hyphen_advance =
                    visibleHyphenAdvance(last_break);
                const candidate_width = tabs.measureRangeWithTerminal(
                    buffer.glyphs.items[line_start..candidate_index],
                    options.tab_stops,
                    fallback_tab_interval,
                    space_advance,
                    candidate_hyphen_advance,
                );
                if (@max(0, candidate_width - candidate_hanging) >
                    candidate_width_limit + candidate_compression)
                {
                    break :candidate null;
                }
                last_break.width = candidate_width;
                break :candidate candidate_index;
            };
            if (options.white_space_collapse == .collapse) {
                white_space.trimLineStart(
                    buffer.glyphs.items,
                    line_start,
                );
                if (fitting_last_break) |candidate_index| {
                    white_space.trimLineEnd(
                        buffer.glyphs.items,
                        line_start,
                        candidate_index,
                    );
                }
            }
            if (forced_balance_break) {
                fitting_last_break = index + 1;
            }
            const overflow_break = shaped_boundary.chooseOverflowBreak(
                buffer.glyphs.items,
                grapheme_clusters,
                index,
                line_start,
                fitting_last_break,
                options.overflow_wrap != .normal or
                    options.word_break == .break_all,
                options.white_space_collapse == .break_spaces,
            );
            if (overflow_break.defer_break) continue;
            const break_end = overflow_break.index;
            const uses_last_break = fitting_last_break != null and
                last_break.glyph_index != null and
                break_end == fitting_last_break.? and
                break_end == last_break.glyph_index.?;
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
            if (options.white_space_collapse == .collapse) {
                white_space.trimLineStart(
                    buffer.glyphs.items,
                    line_start,
                );
                white_space.trimLineEnd(
                    buffer.glyphs.items,
                    line_start,
                    break_end,
                );
            }
            const visible_hyphen_advance = if (uses_last_break)
                visibleHyphenAdvance(last_break)
            else
                0;
            const break_width = if (options.white_space_collapse == .collapse)
                geometry.lineWidth(
                    buffer.glyphs.items[line_start..break_end],
                ) + @max(0, visible_hyphen_advance)
            else if (overflow_break.uses_current_discardable)
                tabs.recomputeRange(
                    buffer.glyphs.items[line_start..break_end],
                    options.tab_stops,
                    fallback_tab_interval,
                    space_advance,
                )
            else
                tabs.recomputeRangeWithTerminal(
                    buffer.glyphs.items[line_start..break_end],
                    options.tab_stops,
                    fallback_tab_interval,
                    space_advance,
                    @max(0, visible_hyphen_advance),
                );
            var next_line_start = break_end;
            if (white_space.shouldDiscardAfterSoftWrap(
                options.white_space_collapse,
            )) {
                geometry.trimLeadingSoftBreaks(
                    buffer.glyphs.items,
                    &next_line_start,
                );
                if (options.white_space_collapse == .collapse) {
                    // These source atoms are omitted from both adjacent visual
                    // line ranges. Zero them before bidi moves the unmatched
                    // suffix so caret/accessibility ownership cannot retain a
                    // stale shaped or tab-ruler advance.
                    white_space.trimLineStart(
                        buffer.glyphs.items,
                        break_end,
                    );
                }
            }
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
            const line_info = geometry.resolvedLineInfo(
                buffer.runs.items,
                buffer.glyphs.items,
                options.inline_objects,
                line_start,
                break_end,
                default_metrics,
                options.line_height,
                recipe.minimumLineHeight(line_start, break_end),
            );
            const committed_region = try regions.resolve(
                buffer.allocator,
                options,
                line_in_paragraph,
                buffer.lines.items.len,
                &y,
                line_info.metrics.lineHeight(),
                max_width,
            );
            // The prospective overflowing prefix can be taller than the
            // selected source prefix. Justification must therefore use the
            // exact region re-resolved for the committed line, not the preview.
            const justification_target =
                if (justify_line and
                alignment == .justify and
                !tabs.contains(
                    buffer.glyphs.items[line_start..break_end],
                ))
                    @max(break_width, committed_region.width)
                else
                    null;
            const committed_alignment = lineAlignment(
                buffer.glyphs.items[line_start..break_end],
                alignment,
                options.direction,
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
                committed_alignment,
                committed_region,
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
                    options,
                );
                // Truncation makes this the terminal visible line. A pending
                // target would otherwise trigger Kashida/space expansion even
                // though terminal and ellipsized lines are never justified.
                if (buffer.lines.items.len != 0) {
                    buffer.lines.items[
                        buffer.lines.items.len - 1
                    ].justification_target = null;
                }
                state.complete = true;
                return .line;
            }
            y += line_info.metrics.lineHeight();
            line_in_paragraph += 1;
            consecutive_hyphenated_lines =
                if (selected_visible_hyphen)
                    consecutive_hyphenated_lines + 1
                else
                    0;
            line_start = next_line_start;
            region_height = lineHeightForRange(
                buffer.runs.items,
                buffer.glyphs.items,
                options.inline_objects,
                line_start,
                index + 1,
                default_metrics,
                options.line_height,
                recipe.minimumLineHeight(line_start, index + 1),
            );
            active_region = try regions.preview(
                buffer.allocator,
                options,
                line_in_paragraph,
                buffer.lines.items.len,
                y,
                region_height,
                max_width,
            );
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
                region_height = requestedLineHeight(
                    default_metrics,
                    options.line_height,
                );
                active_region = try regions.preview(
                    buffer.allocator,
                    options,
                    line_in_paragraph,
                    buffer.lines.items.len,
                    y,
                    region_height,
                    max_width,
                );
                terminal_emergency_line_committed =
                    break_end == buffer.glyphs.items.len;
                last_break.reset();
                index = line_start;
                state.capture(
                    line_start,
                    line_byte_start,
                    line_width,
                    last_break,
                    y,
                    index,
                    line_in_paragraph,
                    region_height,
                    active_region,
                    consecutive_hyphenated_lines,
                    terminal_emergency_line_committed,
                    line_breaks,
                );
                return .line;
            }
            line_width = tabs.recomputePrefix(
                buffer.glyphs.items[line_start..],
                index + 1 - line_start,
                options.tab_stops,
                fallback_tab_interval,
                space_advance,
            );
            terminal_emergency_line_committed =
                break_end == buffer.glyphs.items.len;
            last_break.reset();
            // The glyph at `index` was already measured as the prefix of the
            // next line. Continue with its successor when the caller resumes.
            index += 1;
            state.capture(
                line_start,
                line_byte_start,
                line_width,
                last_break,
                y,
                index,
                line_in_paragraph,
                region_height,
                active_region,
                consecutive_hyphenated_lines,
                terminal_emergency_line_committed,
                line_breaks,
            );
            return .line;
        }
    }

    // A final emergency break may consume the entire last shaped atom. Avoid
    // fabricating an empty line unless the source actually ended in a hard
    // separator.
    if (!terminal_emergency_line_committed) {
        if (options.white_space_collapse == .collapse) {
            white_space.trimLineStart(
                buffer.glyphs.items,
                line_start,
            );
            white_space.trimLineEnd(
                buffer.glyphs.items,
                line_start,
                buffer.glyphs.items.len,
            );
            line_width = geometry.lineWidth(
                buffer.glyphs.items[line_start..],
            );
        }
        const line_info = geometry.resolvedLineInfo(
            buffer.runs.items,
            buffer.glyphs.items,
            options.inline_objects,
            line_start,
            buffer.glyphs.items.len,
            default_metrics,
            options.line_height,
            recipe.minimumLineHeight(line_start, buffer.glyphs.items.len),
        );
        const line_region = try regions.resolve(
            buffer.allocator,
            options,
            line_in_paragraph,
            buffer.lines.items.len,
            &y,
            line_info.metrics.lineHeight(),
            max_width,
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
            lineAlignment(
                buffer.glyphs.items[line_start..],
                alignment,
                options.direction,
            ),
            line_region,
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
        options,
    );
    try automatic_hyphens.materialize(
        buffer,
        selected_automatic_hyphens.items,
    );
    state.complete = true;
    return if (terminal_emergency_line_committed) .complete else .line;
}

fn lineAlignment(
    glyphs: []const @import("../../glyph_position.zig").GlyphPosition,
    paragraph_alignment: anytype,
    direction: anytype,
) @TypeOf(paragraph_alignment) {
    if (tabs.contains(glyphs)) {
        return if (direction == .rtl) .right else .left;
    }
    return paragraph_alignment;
}

fn visibleHyphenAdvance(candidate: opportunities.Candidate) f32 {
    if (candidate.hyphen) |item| return item.resolved.x_advance;
    if (candidate.automatic_hyphen) |item| {
        return item.resolved.x_advance;
    }
    return 0;
}

pub fn prepareAdvances(glyphs: anytype, options: anytype) !void {
    for (glyphs) |*glyph| {
        if (glyph.isInlineObject()) {
            const object = inline_object.find(
                options.inline_objects,
                glyph.cluster,
            ) orelse return error.InvalidInlineObjects;
            glyph.x_advance =
                if (object.kind == .in_flow) object.width else 0;
            continue;
        }
        if (glyph.isTab()) {
            glyph.x_advance = 0;
            continue;
        }
        glyph.x_advance += geometry.spacingForGlyph(
            glyph.codepoint,
            options,
        );
    }
}

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
                line_break.arbitrary,
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

fn requestedLineHeight(
    default_metrics: BaselineMetrics,
    requested: ?f32,
) f32 {
    return @max(default_metrics.lineHeight(), requested orelse 0);
}

fn glyphLineHeight(
    runs: anytype,
    glyphs: []const @import("../../glyph_position.zig").GlyphPosition,
    objects: []const inline_object.Object,
    glyph_index: usize,
    default_metrics: BaselineMetrics,
    requested: ?f32,
    styled_minimum: ?f32,
) f32 {
    return lineHeightForRange(
        runs,
        glyphs,
        objects,
        glyph_index,
        @min(glyph_index + 1, glyphs.len),
        default_metrics,
        requested,
        styled_minimum,
    );
}

fn lineHeightForRange(
    runs: anytype,
    glyphs: []const @import("../../glyph_position.zig").GlyphPosition,
    objects: []const inline_object.Object,
    glyph_start: usize,
    glyph_end: usize,
    default_metrics: BaselineMetrics,
    requested: ?f32,
    styled_minimum: ?f32,
) f32 {
    return geometry.resolvedLineInfo(
        runs,
        glyphs,
        objects,
        glyph_start,
        @max(glyph_start, glyph_end),
        default_metrics,
        requested,
        styled_minimum,
    ).metrics.lineHeight();
}
