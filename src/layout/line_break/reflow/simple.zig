//! Fast retained reflow for an ordinary paragraph with fixed run ownership.
//!
//! The general greedy state machine supports exclusions, styled policy ranges,
//! tabs, discretionary hyphens, punctuation fitting, truncation, and resumable
//! commits. A retained paragraph with none of those policies can select lines
//! directly from its already-materialized UAX #14 opportunities. In-flow
//! object markers remain supported because their width and line metrics are
//! explicit, immutable atoms; fallback runs and object positioning still use
//! the established shared records. Keeping this path separate makes its narrow
//! proof auditable and leaves every advanced feature on the general path.

const std = @import("std");

const geometry = @import("geometry.zig");
const inline_object = @import("../../inline_object/root.zig");
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
    if (!supports(options)) return false;

    buffer.lines.clearRetainingCapacity();
    const glyphs = buffer.glyphs.items;
    var line_start: usize = 0;
    var line_byte_start: usize = 0;
    var y: f32 = 0;
    const alignment = geometry.resolvedAlignment(options);

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

                    // Paragraph preparation proved one ordered output per
                    // source atom, with discretionary hyphens excluded. The
                    // general candidate recorder therefore reduces to either
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
            const run_info = resolvedLineInfo(
                buffer.runs.items,
                glyphs,
                options.inline_objects,
                line_start,
                break_end,
                line_byte_start,
                line_byte_end,
                default_metrics,
            );
            try appendSimpleLine(
                buffer,
                line_start,
                break_end,
                line_byte_start,
                line_byte_end,
                finalLineWidth(
                    glyphs[line_start..break_end],
                    options.direction,
                ),
                run_info,
                y,
                alignment,
                options.max_width,
            );
            y += run_info.metrics.lineHeight();
            line_start = next_line_start;
            line_byte_start = line_byte_end;
            committed = true;
            break;
        }
        if (committed) continue;

        const run_info = resolvedLineInfo(
            buffer.runs.items,
            glyphs,
            options.inline_objects,
            line_start,
            glyphs.len,
            line_byte_start,
            text.len,
            default_metrics,
        );
        try appendSimpleLine(
            buffer,
            line_start,
            glyphs.len,
            line_byte_start,
            text.len,
            if (options.direction == .rtl)
                finalLineWidth(glyphs[line_start..], options.direction)
            else
                line_width,
            run_info,
            y,
            alignment,
            options.max_width,
        );
        break;
    }
    return true;
}

fn resolvedLineInfo(
    runs: anytype,
    glyphs: []const @import("../../glyph_position.zig").GlyphPosition,
    objects: []const inline_object.Object,
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
    default_metrics: geometry.BaselineMetrics,
) geometry.LineRunInfo {
    var info = geometry.lineRunInfoWithoutObjects(
        runs,
        glyph_start,
        glyph_end,
        default_metrics,
    );
    if (objects.len != 1) {
        return geometry.resolvedLineInfo(
            runs,
            glyphs,
            objects,
            glyph_start,
            glyph_end,
            default_metrics,
            null,
            null,
        );
    }
    const object = objects[0];
    if (object.kind == .in_flow and
        object.byte_index >= byte_start and
        object.byte_index < byte_end)
    {
        // The retained simple-shape proof guarantees that the sole validated
        // marker owns exactly one glyph in this source range. Use that proof
        // instead of rescanning every glyph on every reflow merely to locate
        // the object whose byte index is already known.
        const metrics = inline_object.verticalMetrics(object);
        info.metrics.ascent = @max(info.metrics.ascent, metrics.ascent);
        info.metrics.descent = @max(info.metrics.descent, metrics.descent);
    }
    return info;
}

fn finalLineWidth(
    glyphs: []const @import("../../glyph_position.zig").GlyphPosition,
    direction: anytype,
) f32 {
    if (direction != .rtl) return geometry.lineWidth(glyphs);

    // Pure-RTL presentation reverses this slice. Accumulate in that eventual
    // visual order now, preserving the public float bits without a second
    // whole-line pass after permutation.
    var width: f32 = 0;
    var index = glyphs.len;
    while (index != 0) {
        index -= 1;
        width += glyphs[index].x_advance;
    }
    return width;
}

fn appendSimpleLine(
    buffer: anytype,
    glyph_start: usize,
    glyph_end: usize,
    byte_start: usize,
    byte_end: usize,
    width: f32,
    run_info: geometry.LineRunInfo,
    y: f32,
    alignment: paragraph_types.TextAlign,
    max_width: f32,
) !void {
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = glyph_start,
        .glyph_len = glyph_end - glyph_start,
        .run_start = run_info.run_start,
        .run_len = run_info.run_len,
        .byte_start = byte_start,
        .byte_len = byte_end - byte_start,
        .x = geometry.alignedLineX(width, max_width, alignment),
        .y = y,
        .indent = 0,
        .region_x = 0,
        .region_width = max_width,
        .region_inline_start = 0,
        .region_inline_size = max_width,
        .resolved_alignment = alignment,
        .width = width,
        .justification_target = null,
        .height = run_info.metrics.lineHeight(),
        .baseline = run_info.metrics.ascent,
        .ascent = run_info.metrics.ascent,
        .descent = run_info.metrics.descent,
        .leading = run_info.metrics.leading,
    });
}

/// Whether the request can use the strict retained line builder. Callers may
/// use this proof before preparing reusable input that would be incomplete for
/// dictionary, hyphenation, or range-tailored fallback paths.
pub fn supports(options: paragraph_options.Options) bool {
    return options.writing_mode == .horizontal_tb and
        options.line_break_strategy == .greedy and
        options.wrap_mode == .word and
        options.word_break == .normal and
        options.overflow_wrap == .break_word and
        options.white_space_collapse == .preserve and
        (options.alignment == .start or options.alignment == .center) and
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
        options.tab_stops.len == 0 and
        options.word_break_dictionary == null and
        options.hyphenation.dictionary == null and
        options.hyphenation.character == null and
        options.hyphenation.max_consecutive_lines == null and
        options.punctuation.max_compression_fraction == 0 and
        options.punctuation.end_hanging_fraction == 0;
}
