//! Direct retained bidi permutation for one-scalar/one-glyph paragraphs.
//!
//! The preparation-time proof makes scalar indexes usable as glyph indexes.
//! This module keeps only the run-owner sidecars needed when fallback runs
//! fragment under UAX #9 L2; cluster lookup and duplicate suppression remain
//! unnecessary for the complete transaction.

const std = @import("std");

const mapping = @import("mapping.zig");
const runs = @import("runs.zig");
const run_types = @import("../../types/runs.zig");
const bidi = @import("../../../text/bidi.zig");
const unicode = @import("../../../unicode.zig");

/// Apply line-local bidi when preparation proved scalar index == glyph index.
///
/// Returns false before mutation if the restored output no longer satisfies
/// the proof. Run offsets are intentionally left to the presentation layer's
/// single shared offset pass.
pub fn apply(
    buffer: anytype,
    paragraph: unicode.BidiParagraph,
) !bool {
    const glyphs = buffer.glyphs.items;
    if (glyphs.len == 0 or buffer.lines.items.len == 0 or
        glyphs.len != paragraph.scalars.len or
        paragraph.classes.len != paragraph.scalars.len or
        paragraph.levels.len != paragraph.scalars.len or
        !runsOwnCompleteGlyphStream(buffer.runs.items, glyphs.len))
    {
        return false;
    }
    for (glyphs, paragraph.scalars, paragraph.classes) |glyph, scalar, class| {
        if (glyph.cluster != scalar.byte_start or
            glyph.source_byte_len != scalar.byte_len or
            glyph.codepoint != scalar.codepoint or
            glyph.synthetic_glyph_id != null or
            glyph.isDiscretionaryHyphen() or
            glyph.isAutomaticHyphen() or
            glyph.isInlineObject() or
            glyph.isKashida() or
            glyph.isTab() or
            scalarRemovedByX9(class))
        {
            return false;
        }
    }

    // Validate every source range before swapping either owner. Trimmed line
    // whitespace can create gaps, so containment is weaker than equality.
    var previous_glyph_end: usize = 0;
    for (buffer.lines.items) |line| {
        const glyph_end = std.math.add(
            usize,
            line.glyph_start,
            line.glyph_len,
        ) catch return false;
        const byte_end = std.math.add(
            usize,
            line.byte_start,
            line.byte_len,
        ) catch return false;
        if (line.glyph_start < previous_glyph_end or glyph_end > glyphs.len)
            return false;
        const scalar_start = paragraph.scalarIndexForByte(
            line.byte_start,
        ) orelse return false;
        const scalar_end = paragraph.scalarIndexForByte(
            byte_end,
        ) orelse return false;
        if (line.glyph_start < scalar_start or glyph_end > scalar_end)
            return false;
        previous_glyph_end = glyph_end;
    }

    const single_owning_run = buffer.runs.items.len == 1 and
        buffer.runs.items[0].glyph_start == 0 and
        buffer.runs.items[0].glyph_len == glyphs.len;
    const scratch = &buffer.bidi_reorder_scratch;
    if (single_owning_run)
        try scratch.beginDirectSingleOwningRun(
            buffer.allocator,
            &buffer.glyphs,
        )
    else
        try scratch.beginDirect(
            buffer.allocator,
            &buffer.runs,
            &buffer.glyphs,
        );
    var transaction_open = true;
    errdefer if (transaction_open) {
        if (single_owning_run)
            scratch.rollbackSingleOwningRun(&buffer.glyphs)
        else
            scratch.rollback(&buffer.runs, &buffer.glyphs);
    };
    try scratch.line_levels.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );
    try scratch.visual_order.ensureTotalCapacity(
        buffer.allocator,
        paragraph.scalars.len,
    );

    const old_glyphs = scratch.old_glyphs.items;
    const old_runs = if (single_owning_run)
        buffer.runs.items
    else
        scratch.old_runs.items;
    const glyph_run_indices = scratch.glyph_run_indices.items;
    const visual_glyphs = &buffer.glyphs;
    const visual_run_indices = &scratch.visual_run_indices;
    for (buffer.lines.items) |line| {
        const old_line_start = line.glyph_start;
        const old_line_end = old_line_start + line.glyph_len;
        if (line.byte_len == 0 or old_line_start == old_line_end) continue;
        const scalar_start = paragraph.scalarIndexForByte(
            line.byte_start,
        ).?;
        const scalar_end = paragraph.scalarIndexForByte(
            line.byte_start + line.byte_len,
        ).?;
        try paragraph.visualOrderAndLevelsRetaining(
            buffer.allocator,
            scalar_start,
            scalar_end,
            &.{},
            &scratch.line_levels,
            &scratch.visual_order,
        );
        for (scratch.visual_order.items) |scalar_index| {
            if (scalar_index < old_line_start or scalar_index >= old_line_end)
                continue;
            const owner = if (single_owning_run)
                @as(usize, 0)
            else
                glyph_run_indices[scalar_index];
            if (owner >= old_runs.len) return error.InvalidBidiMap;
            const scalar = paragraph.scalars[scalar_index];
            const level = scratch.line_levels.items[
                scalar_index - scalar_start
            ];
            visual_glyphs.appendAssumeCapacity(mapping.visualizedGlyph(
                old_glyphs[scalar_index],
                run_types.fontForBackend(old_runs[owner]),
                if (level & 1 != 0 and bidi.mayHaveBidiMirror(scalar.codepoint))
                    unicode.mirroredCodepoint(scalar.codepoint)
                else
                    scalar.codepoint,
            ));
            if (!single_owning_run)
                visual_run_indices.appendAssumeCapacity(owner);
        }
    }

    // Match the general unseen pass: every glyph excluded from visible line
    // ranges becomes one stable logical suffix, including inter-line spaces.
    var logical_cursor: usize = 0;
    for (buffer.lines.items) |line| {
        for (logical_cursor..line.glyph_start) |glyph_index| {
            appendGapGlyph(
                single_owning_run,
                old_glyphs,
                glyph_run_indices,
                glyph_index,
                visual_glyphs,
                visual_run_indices,
            );
        }
        logical_cursor = line.glyph_start + line.glyph_len;
    }
    for (logical_cursor..old_glyphs.len) |glyph_index| {
        appendGapGlyph(
            single_owning_run,
            old_glyphs,
            glyph_run_indices,
            glyph_index,
            visual_glyphs,
            visual_run_indices,
        );
    }
    if (visual_glyphs.items.len != old_glyphs.len or
        (!single_owning_run and
            visual_run_indices.items.len != old_glyphs.len))
    {
        return error.InvalidBidiMap;
    }

    // Rebuilding can allocate, so line records remain pristine until it
    // succeeds and the existing rollback can restore both swapped owners.
    if (!single_owning_run)
        try runs.rebuild(buffer, old_runs, visual_run_indices.items);
    var visual_start: usize = 0;
    for (buffer.lines.items) |*line| {
        line.glyph_start = visual_start;
        visual_start += line.glyph_len;
        if (single_owning_run) {
            line.run_start = 0;
            line.run_len = @intFromBool(line.glyph_len != 0);
        } else {
            const run_range = runs.range(
                buffer.runs.items,
                line.glyph_start,
                line.glyph_start + line.glyph_len,
            );
            line.run_start = run_range.start;
            line.run_len = run_range.len;
        }
    }
    transaction_open = false;
    return true;
}

fn appendGapGlyph(
    single_owning_run: bool,
    old_glyphs: anytype,
    glyph_run_indices: []const usize,
    glyph_index: usize,
    visual_glyphs: anytype,
    visual_run_indices: *std.ArrayList(usize),
) void {
    visual_glyphs.appendAssumeCapacity(old_glyphs[glyph_index]);
    if (!single_owning_run) visual_run_indices.appendAssumeCapacity(
        glyph_run_indices[glyph_index],
    );
}

fn scalarRemovedByX9(class: unicode.ExactBidiClass) bool {
    return switch (class) {
        .rle, .lre, .rlo, .lro, .pdf, .bn => true,
        else => false,
    };
}

fn runsOwnCompleteGlyphStream(font_runs: anytype, glyph_count: usize) bool {
    if (font_runs.len == 0) return false;
    var glyph_cursor: usize = 0;
    for (font_runs) |run| {
        if (run.glyph_start != glyph_cursor or run.glyph_len == 0) return false;
        glyph_cursor = std.math.add(
            usize,
            run.glyph_start,
            run.glyph_len,
        ) catch return false;
        if (glyph_cursor > glyph_count) return false;
    }
    return glyph_cursor == glyph_count;
}
