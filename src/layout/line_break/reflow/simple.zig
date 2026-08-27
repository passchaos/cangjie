//! Fast retained reflow for the ordinary single-run paragraph contract.
//!
//! The general greedy state machine supports exclusions, styled policy ranges,
//! tabs, discretionary hyphens, punctuation fitting, truncation, and resumable
//! commits. A retained paragraph with none of those policies can select lines
//! directly from its already-materialized UAX #14 opportunities. Keeping this
//! path separate makes its narrow proof auditable and leaves every advanced
//! feature on the general implementation.

const std = @import("std");

const geometry = @import("geometry.zig");
const opportunity = @import("../opportunity.zig");
const opportunities = @import("opportunities.zig");
const paragraph_options = @import("../../paragraph/options.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const shaped_boundary = @import("../shaped_boundary.zig");
const unicode = @import("../../../unicode.zig");

/// Build lines when the complete request is equivalent to plain greedy UAX
/// wrapping over one immutable run. Returns false before mutation whenever the
/// request requires any general-policy machinery.
pub fn tryBuild(
    buffer: anytype,
    text: []const u8,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    graphemes: ?[]const unicode.GraphemeCluster,
    line_breaks: ?[]const opportunity.Opportunity,
) !bool {
    const analyzed_graphemes = graphemes orelse return false;
    const analyzed_breaks = line_breaks orelse return false;
    if (!supportsOptions(options)) return false;

    buffer.lines.clearRetainingCapacity();
    const glyphs = buffer.glyphs.items;
    const run_info = geometry.resolvedLineInfo(
        buffer.runs.items,
        glyphs,
        &.{},
        0,
        glyphs.len,
        default_metrics,
        null,
        null,
    );
    const line_height = run_info.metrics.lineHeight();
    var line_start: usize = 0;
    var line_byte_start: usize = 0;
    var y: f32 = 0;
    const alignment: paragraph_types.TextAlign =
        if (options.direction == .rtl) .right else .left;

    while (line_start < glyphs.len) {
        // The preceding line may have scanned past the selected soft boundary
        // before it overflowed. Rebuild from the new source start so legal
        // opportunities in that already-seen prefix remain available. With a
        // retained opportunity slice this performs no Unicode decoding.
        var cursor = opportunities.Cursor.initRetainedAfter(
            analyzed_breaks,
            line_byte_start,
        );
        var last_break: ?usize = null;
        var line_width: f32 = 0;
        var index = line_start;
        var committed = false;
        while (index < glyphs.len) : (index += 1) {
            const glyph = glyphs[index];
            line_width += glyph.x_advance;
            const atom_continues = index + 1 < glyphs.len and
                glyphs[index + 1].cluster == glyph.cluster;
            const overflows = line_width > options.max_width;
            if (!overflows and !atom_continues) {
                const source_end = shaped_boundary.glyphSourceEnd(glyph);
                while (cursor.nextThrough(source_end)) |line_break| {
                    if (line_break.kind != .soft or
                        line_break.automatic_hyphen) continue;
                    if (shaped_boundary.sourceBoundaryIsUnsafe(
                        glyphs,
                        line_break.byte_offset,
                        index,
                    )) continue;
                    if (line_break.byte_offset > glyph.cluster and
                        line_break.byte_offset < source_end) continue;
                    if (line_break.byte_offset != source_end) continue;

                    // supportsShape proves one ordered output per source atom,
                    // with discretionary hyphens excluded. Consequently the
                    // general candidate recorder reduces to choosing either
                    // the boundary after this atom or, for collapsible break
                    // spaces, the boundary before its invisible line suffix.
                    const candidate = if (geometry.isDiscardableBreak(glyph.codepoint)) index else index + 1;
                    if (candidate > line_start) last_break = candidate;
                }
                continue;
            }
            if (!overflows or index + 1 <= line_start) continue;

            const selected = shaped_boundary.chooseOverflowBreak(
                glyphs,
                analyzed_graphemes,
                index,
                line_start,
                last_break,
                true,
                false,
            );
            if (selected.defer_break) continue;
            const break_end = selected.index;
            var next_line_start = break_end;
            geometry.trimLeadingSoftBreaks(glyphs, &next_line_start);
            const line_byte_end = shaped_boundary.byteEndForGlyphPrefix(
                glyphs,
                next_line_start,
                line_byte_start,
            );
            try geometry.appendLine(
                buffer,
                line_start,
                break_end,
                line_byte_start,
                line_byte_end,
                geometry.lineWidth(glyphs[line_start..break_end]),
                run_info,
                y,
                alignment,
                .{ .x = 0, .width = options.max_width, .indent = 0 },
                null,
            );
            y += line_height;
            line_start = next_line_start;
            line_byte_start = line_byte_end;
            committed = true;
            break;
        }
        if (committed) continue;

        try geometry.appendLine(
            buffer,
            line_start,
            glyphs.len,
            line_byte_start,
            text.len,
            line_width,
            run_info,
            y,
            alignment,
            .{ .x = 0, .width = options.max_width, .indent = 0 },
            null,
        );
        break;
    }
    return true;
}

fn supportsOptions(options: paragraph_options.Options) bool {
    return options.writing_mode == .horizontal_tb and
        options.line_break_strategy == .greedy and
        options.wrap_mode == .word and
        options.word_break == .normal and
        options.overflow_wrap == .break_word and
        options.white_space_collapse == .preserve and
        options.alignment == .start and
        options.line_height == null and
        options.max_lines == null and
        !options.ellipsis and
        std.math.isFinite(options.max_width) and
        options.max_width > 0 and
        options.letter_spacing == 0 and
        options.word_spacing == 0 and
        options.first_line_indent == 0 and
        options.paragraph_spacing == 0 and
        options.line_break_policy_ranges.len == 0 and
        options.exclusions.len == 0 and
        options.line_regions.len == 0 and
        options.inline_objects.len == 0 and
        options.out_of_flow_placements.len == 0 and
        options.tab_stops.len == 0 and
        options.word_break_dictionary == null and
        options.hyphenation.dictionary == null and
        options.hyphenation.character == null and
        options.hyphenation.max_consecutive_lines == null and
        options.punctuation.max_compression_fraction == 0 and
        options.punctuation.end_hanging_fraction == 0;
}
