//! Portable inline-axis justification after shaping and line selection.
//!
//! Inter-word expansion remains the primary strategy because it applies
//! consistently across scripts. When a fragment has no expandable UAX #14 `SP`
//! atom, East Asian text falls back to conservative inter-character expansion
//! between adjacent ideographic/Kana/Hangul/Yi/Nushu source atoms. Punctuation,
//! nonstarters, combining output, and repeated GSUB output clusters are not
//! treated as independent opportunities.

const std = @import("std");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const unicode = @import("../../unicode.zig");

const OpportunityKind = enum {
    space,
    cjk_inter_character,
};

pub fn apply(
    glyphs: []GlyphPosition,
    natural_size: f32,
    target_size: f32,
    writing_mode: pipeline_types.WritingMode,
) f32 {
    if (glyphs.len == 0 or
        !std.math.isFinite(target_size) or
        target_size <= natural_size)
    {
        return natural_size;
    }

    var kind: OpportunityKind = .space;
    var opportunity_count = countSpaces(glyphs);
    if (opportunity_count == 0) {
        kind = .cjk_inter_character;
        opportunity_count = countCjkBoundaries(glyphs);
        if (opportunity_count == 0) return natural_size;
    }

    const total_extra = target_size - natural_size;
    const extra_per_opportunity =
        total_extra / @as(f32, @floatFromInt(opportunity_count));
    var applied_extra: f32 = 0;
    var applied_count: usize = 0;

    switch (kind) {
        .space => {
            var previous_space_cluster: ?usize = null;
            for (glyphs) |*glyph| {
                if (!isJustificationSpace(glyph.codepoint)) {
                    previous_space_cluster = null;
                    continue;
                }
                if (previous_space_cluster != null and
                    previous_space_cluster.? == glyph.cluster)
                {
                    continue;
                }
                previous_space_cluster = glyph.cluster;
                applyOpportunity(
                    glyph,
                    opportunity_count,
                    total_extra,
                    extra_per_opportunity,
                    &applied_count,
                    &applied_extra,
                    writing_mode,
                );
            }
        },
        .cjk_inter_character => {
            var index: usize = 0;
            while (index < glyphs.len) {
                const atom_end = sourceAtomEnd(glyphs, index);
                if (atom_end >= glyphs.len) break;
                if (isCjkAtom(glyphs[index].codepoint) and
                    isCjkAtom(glyphs[atom_end].codepoint))
                {
                    // Advance belongs to the final output glyph of the left
                    // source atom. This preserves one-to-many GSUB geometry and
                    // makes caret/selection positions consume the same gap.
                    applyOpportunity(
                        &glyphs[atom_end - 1],
                        opportunity_count,
                        total_extra,
                        extra_per_opportunity,
                        &applied_count,
                        &applied_extra,
                        writing_mode,
                    );
                }
                index = atom_end;
            }
        },
    }
    std.debug.assert(applied_count == opportunity_count);
    return natural_size + applied_extra;
}

fn applyOpportunity(
    glyph: *GlyphPosition,
    opportunity_count: usize,
    total_extra: f32,
    extra_per_opportunity: f32,
    applied_count: *usize,
    applied_extra: *f32,
    writing_mode: pipeline_types.WritingMode,
) void {
    applied_count.* += 1;
    // Give the final opportunity the floating-point residual so reported line
    // width and summed advances share one exact endpoint.
    const extra = if (applied_count.* == opportunity_count)
        total_extra - applied_extra.*
    else
        extra_per_opportunity;
    if (writing_mode.isVertical()) {
        glyph.y_advance += extra;
    } else {
        glyph.x_advance += extra;
    }
    applied_extra.* += extra;
}

fn countSpaces(glyphs: []const GlyphPosition) usize {
    // Count source atoms rather than output glyphs. GSUB may expand one source
    // space into multiple glyphs, but it remains one typographic opportunity.
    var count: usize = 0;
    var previous_space_cluster: ?usize = null;
    for (glyphs) |glyph| {
        if (!isJustificationSpace(glyph.codepoint)) {
            previous_space_cluster = null;
            continue;
        }
        if (previous_space_cluster != null and
            previous_space_cluster.? == glyph.cluster)
        {
            continue;
        }
        previous_space_cluster = glyph.cluster;
        count += 1;
    }
    return count;
}

fn countCjkBoundaries(glyphs: []const GlyphPosition) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (index < glyphs.len) {
        const atom_end = sourceAtomEnd(glyphs, index);
        if (atom_end >= glyphs.len) break;
        if (isCjkAtom(glyphs[index].codepoint) and
            isCjkAtom(glyphs[atom_end].codepoint))
        {
            count += 1;
        }
        index = atom_end;
    }
    return count;
}

fn sourceAtomEnd(glyphs: []const GlyphPosition, start: usize) usize {
    const cluster = glyphs[start].cluster;
    var end = start + 1;
    while (end < glyphs.len and glyphs[end].cluster == cluster) : (end += 1) {}
    return end;
}

fn isJustificationSpace(codepoint: u21) bool {
    // UAX #14 SP includes ordinary and Unicode breakable space separators.
    // Tabs retain tab-stop semantics, and non-breaking glue is deliberately
    // excluded even though both can be visually blank.
    return unicode.lineBreakClassForCodepoint(codepoint) == .space;
}

fn isCjkAtom(codepoint: u21) bool {
    const script = unicode.scriptForCodepoint(codepoint);
    switch (script) {
        .han, .hiragana, .katakana, .hangul, .yi, .nushu => {},
        else => return false,
    }

    // This is intentionally an allowlist. East Asian punctuation and
    // nonstarters need language-specific compression/hanging rules; treating
    // them as ordinary expansion atoms produces visibly incorrect spacing.
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .ideographic,
        .alphabetic,
        .hangul_l_jamo,
        .hangul_v_jamo,
        .hangul_t_jamo,
        .hangul_lv_syllable,
        .hangul_lvt_syllable,
        => true,
        else => false,
    };
}

test "inter-word justification counts one opportunity per source atom" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = ' ', .cluster = 1, .x_advance = 3 },
        .{ .glyph_id = 3, .codepoint = ' ', .cluster = 1, .x_advance = 2 },
        .{ .glyph_id = 4, .codepoint = 'A', .cluster = 2, .x_advance = 10 },
    };

    try std.testing.expectApproxEqAbs(@as(f32, 30), apply(&glyphs, 25, 30, .horizontal_tb), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8), glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), glyphs[2].x_advance, 0.001);

    // Deduplication is local to adjacent GSUB outputs, not a paragraph-global
    // cluster set; malformed/non-monotone input may reuse a cluster later.
    var reused_cluster = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = ' ', .cluster = 1, .x_advance = 5 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 2, .x_advance = 10 },
        .{ .glyph_id = 3, .codepoint = ' ', .cluster = 1, .x_advance = 5 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        apply(&reused_cluster, 20, 30, .horizontal_tb),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 10), reused_cluster[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), reused_cluster[2].x_advance, 0.001);

    // Non-breaking space is UAX #14 glue, not an expandable SP opportunity.
    var glued = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x00a0, .cluster = 1, .x_advance = 5 },
        .{ .glyph_id = 3, .codepoint = 'A', .cluster = 3, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(@as(f32, 25), apply(&glued, 25, 30, .horizontal_tb), 0.001);
}

test "CJK inter-character expansion respects source atoms and punctuation" {
    var ideographs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x4e00, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x4e01, .cluster = 3, .x_advance = 4 },
        .{ .glyph_id = 3, .codepoint = 0x4e01, .cluster = 3, .x_advance = 6 },
        .{ .glyph_id = 4, .codepoint = 0x4e02, .cluster = 6, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 36),
        apply(&ideographs, 30, 36, .horizontal_tb),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 13), ideographs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), ideographs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 9), ideographs[2].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), ideographs[3].x_advance, 0.001);

    var punctuation = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x4e00, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x3001, .cluster = 3, .x_advance = 10 },
        .{ .glyph_id = 3, .codepoint = 0x4e01, .cluster = 6, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        apply(&punctuation, 30, 36, .horizontal_tb),
        0.001,
    );
}

test "spaces take precedence over inter-character expansion" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x4e00, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = ' ', .cluster = 3, .x_advance = 5 },
        .{ .glyph_id = 3, .codepoint = 0x4e01, .cluster = 4, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(@as(f32, 35), apply(&glyphs, 25, 35, .horizontal_tb), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15), glyphs[1].x_advance, 0.001);
}

test "vertical justification updates only positive-down advances" {
    var glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 0x4e00,
            .cluster = 0,
            .x_advance = 0,
            .y_advance = 10,
        },
        .{
            .glyph_id = 2,
            .codepoint = 0x4e01,
            .cluster = 3,
            .x_advance = 0,
            .y_advance = 10,
        },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 30),
        apply(&glyphs, 20, 30, .vertical_rl),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), glyphs[0].x_advance, 0.001);
}
