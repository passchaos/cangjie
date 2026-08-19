//! Minimal East Asian punctuation compression for overfull inline fragments.
//!
//! Each eligible punctuation glyph contributes at most half its inline
//! advance, then the caller's normalized policy scales that capacity.
//! Compression first consumes adjacent punctuation gaps (CLREQ's
//! highest-priority case), then distributes any remaining required reduction
//! over unused punctuation capacity. Glyph advances/offsets carry the result
//! so rendering, caret, and selection geometry remain identical in horizontal
//! lines and positive-down vertical columns.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const regions = @import("../line_break/reflow/regions.zig");
const hanging = @import("hanging.zig");
const paragraph_options = @import("../paragraph/options.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const unicode = @import("../../unicode.zig");
const line_break_properties =
    @import("../../unicode/line_break/properties.zig");

/// Effective occupied-inline-size reduction available to logical line
/// selection.
///
/// Compressing the punctuation that also hangs reduces its hanging allowance,
/// so that raw side capacity contributes only `(1 - hanging_fraction)` toward
/// fitting. Other punctuation contributes its complete reduction.
pub fn effectiveCapacity(
    glyphs: []const GlyphPosition,
    glyph_start: usize,
    glyph_end: usize,
    compression_fraction: f32,
    hanging_fraction: f32,
    convention: paragraph_options.PunctuationConvention,
    writing_mode: pipeline_types.WritingMode,
) f32 {
    if (compression_fraction <= 0 or glyph_start >= glyph_end) return 0;
    const hanging_index =
        if (logicalHangingAmount(
            glyphs,
            glyph_start,
            glyph_end,
            hanging_fraction,
            writing_mode,
        ) > 0)
            glyph_end - 1
        else
            null;
    var total: f32 = 0;
    var atom_start = glyph_start;
    while (atom_start < glyph_end) {
        var atom_end = atom_start + 1;
        while (atom_end < glyph_end and
            glyphs[atom_end].cluster == glyphs[atom_start].cluster)
        {
            atom_end += 1;
        }
        const start_capacity = sideCapacity(
            glyphs[atom_start],
            compression_fraction,
            convention,
            writing_mode,
        ).start;
        const right_index = atom_end - 1;
        const end_capacity = sideCapacity(
            glyphs[right_index],
            compression_fraction,
            convention,
            writing_mode,
        ).end;
        total += start_capacity * effectiveFactor(
            atom_start,
            hanging_index,
            hanging_fraction,
        );
        total += end_capacity * effectiveFactor(
            right_index,
            hanging_index,
            hanging_fraction,
        );
        atom_start = atom_end;
    }
    return total;
}

/// Compress every overfull selected line/column after truncation and before
/// bidi.
///
/// Applying in logical order preserves whether blank space belongs to the
/// glyph's leading or trailing side; bidi then carries the adjusted advance and
/// offset to its physical position. One side-capacity allocation is reserved
/// before any mutation, so allocation failure leaves the output untouched.
pub fn apply(buffer: anytype, options: anytype) !void {
    const compression_fraction =
        options.punctuation.max_compression_fraction;
    if (compression_fraction <= 0 or buffer.lines.items.len == 0) return;
    var max_glyphs: usize = 0;
    for (buffer.lines.items) |line| {
        max_glyphs = @max(max_glyphs, line.glyph_len);
    }
    const sides = try buffer.allocator.alloc(Sides, max_glyphs);
    defer buffer.allocator.free(sides);

    const max_width = effectiveMaxWidth(options.max_width);
    for (buffer.lines.items) |line| {
        if (line.glyph_len == 0) continue;
        const glyph_end = line.glyph_start + line.glyph_len;
        const glyphs = buffer.glyphs.items[line.glyph_start..glyph_end];
        const available = if (options.writing_mode.isVertical())
            @max(0, max_width - line.indent)
        else
            regions.stored(line, max_width).width;
        const hanging_amount = logicalHangingAmount(
            buffer.glyphs.items,
            line.glyph_start,
            glyph_end,
            options.punctuation.end_hanging_fraction,
            options.writing_mode,
        );
        const occupied = inlineSize(glyphs, options.writing_mode) -
            hanging_amount;
        const required = @max(0, occupied - available);
        if (required <= 0) continue;
        // An indivisible fragment may be intentionally overfull. Compression
        // is a fit transaction, not a request to distort punctuation as far as
        // possible when the authored capacity cannot make that fragment fit.
        const capacity = effectiveCapacity(
            buffer.glyphs.items,
            line.glyph_start,
            glyph_end,
            compression_fraction,
            options.punctuation.end_hanging_fraction,
            options.punctuation.convention,
            options.writing_mode,
        );
        if (capacity + 0.001 < required) continue;
        const hanging_index: ?usize =
            if (hanging_amount > 0) glyphs.len - 1 else null;
        const applied = applyToLine(
            glyphs,
            sides[0..glyphs.len],
            required,
            compression_fraction,
            options.punctuation.end_hanging_fraction,
            options.punctuation.convention,
            hanging_index,
            options.writing_mode,
        );
        std.debug.assert(applied + 0.001 >= required);
    }
}

fn applyToLine(
    glyphs: []GlyphPosition,
    sides: []Sides,
    required: f32,
    compression_fraction: f32,
    hanging_fraction: f32,
    convention: paragraph_options.PunctuationConvention,
    hanging_index: ?usize,
    writing_mode: pipeline_types.WritingMode,
) f32 {
    std.debug.assert(glyphs.len == sides.len);
    for (glyphs, sides) |glyph, *entry| {
        entry.* = sideCapacity(
            glyph,
            compression_fraction,
            convention,
            writing_mode,
        );
    }
    restrictToSourceAtomEdges(glyphs, sides);
    var remaining = required;
    var effective_applied: f32 = 0;

    // Highest priority: collapse punctuation-facing punctuation at one source
    // boundary. Draw from the preceding glyph's inline-end side first,
    // matching CLREQ's preference to remove trailing blank space before
    // leading blank space on either physical inline axis.
    var index: usize = 0;
    while (index + 1 < glyphs.len and remaining > 0) : (index += 1) {
        if (glyphs[index].cluster == glyphs[index + 1].cluster) continue;
        const preceding_factor = effectiveFactor(
            index,
            hanging_index,
            hanging_fraction,
        );
        const following_factor = effectiveFactor(
            index + 1,
            hanging_index,
            hanging_fraction,
        );
        const preceding_effective = sides[index].end * preceding_factor;
        const following_effective = sides[index + 1].start * following_factor;
        if (preceding_effective + following_effective <= 0) continue;
        const from_preceding = if (preceding_factor > 0)
            @min(sides[index].end, remaining / preceding_factor)
        else
            0;
        shrinkEnd(&glyphs[index], from_preceding, writing_mode);
        sides[index].end -= from_preceding;
        const preceding_reduction = from_preceding * preceding_factor;
        remaining -= preceding_reduction;
        effective_applied += preceding_reduction;
        const from_following = if (following_factor > 0)
            @min(sides[index + 1].start, remaining / following_factor)
        else
            0;
        shrinkStart(&glyphs[index + 1], from_following, writing_mode);
        sides[index + 1].start -= from_following;
        const following_reduction = from_following * following_factor;
        remaining -= following_reduction;
        effective_applied += following_reduction;
    }

    // Second priority: all remaining punctuation-side capacity.
    for (glyphs, sides, 0..) |*glyph, *entry, glyph_index| {
        if (remaining <= 0) break;
        const factor = effectiveFactor(
            glyph_index,
            hanging_index,
            hanging_fraction,
        );
        if (factor <= 0) continue;
        const from_start = @min(entry.start, remaining / factor);
        shrinkStart(glyph, from_start, writing_mode);
        entry.start -= from_start;
        const start_reduction = from_start * factor;
        remaining -= start_reduction;
        effective_applied += start_reduction;
        if (remaining <= 0) break;
        const from_end = @min(entry.end, remaining / factor);
        shrinkEnd(glyph, from_end, writing_mode);
        entry.end -= from_end;
        const end_reduction = from_end * factor;
        remaining -= end_reduction;
        effective_applied += end_reduction;
    }
    return effective_applied;
}

const Sides = struct {
    start: f32 = 0,
    end: f32 = 0,
};

fn sideCapacity(
    glyph: GlyphPosition,
    fraction: f32,
    convention: paragraph_options.PunctuationConvention,
    writing_mode: pipeline_types.WritingMode,
) Sides {
    if (glyph.isInlineObject() or glyph.isDiscretionaryHyphen() or
        !line_break_properties.lookup(glyph.codepoint).east_asian or
        inlineAdvance(glyph, writing_mode) <= 0)
    {
        return .{};
    }
    const half = inlineAdvance(glyph, writing_mode) * 0.5 * fraction;
    if (explicitSides(glyph.codepoint, convention, half)) |sides| {
        return sides;
    }
    return switch (unicode.lineBreakClassForCodepoint(glyph.codepoint)) {
        .open_punctuation => .{ .start = half },
        .close_punctuation,
        .close_parenthesis,
        .exclamation,
        .nonstarter,
        => .{ .end = half },
        .infix_separator => .{
            .start = half / 2,
            .end = half / 2,
        },
        else => .{},
    };
}

fn explicitSides(
    codepoint: u21,
    convention: paragraph_options.PunctuationConvention,
    half: f32,
) ?Sides {
    if (convention == .generic) return null;
    if (isRightAlignedOpening(codepoint)) return .{ .start = half };
    if (isLeftAlignedClosing(codepoint)) return .{ .end = half };
    if (isStopPunctuation(codepoint)) {
        return switch (convention) {
            .gb, .jis => .{ .end = half },
            .cns => .{ .start = half / 2, .end = half / 2 },
            .generic => unreachable,
        };
    }
    if (isFullwidthQuestionOrExclamation(codepoint)) {
        return if (convention == .gb)
            .{ .end = half }
        else
            .{};
    }
    return null;
}

fn isRightAlignedOpening(codepoint: u21) bool {
    return switch (codepoint) {
        0x3008, // 〈
        0x300a, // 《
        0x300c, // 「
        0x300e, // 『
        0x3010, // 【
        0x3014, // 〔
        0x3016, // 〖
        0xff08, // （
        0xff3b, // ［
        0xff5b, // ｛
        => true,
        else => false,
    };
}

fn isLeftAlignedClosing(codepoint: u21) bool {
    return switch (codepoint) {
        0x3009, // 〉
        0x300b, // 》
        0x300d, // 」
        0x300f, // 』
        0x3011, // 】
        0x3015, // 〕
        0x3017, // 〗
        0xff09, // ）
        0xff3d, // ］
        0xff5d, // ｝
        => true,
        else => false,
    };
}

fn isStopPunctuation(codepoint: u21) bool {
    return switch (codepoint) {
        0x3001, // 、
        0x3002, // 。
        0xff0c, // ，
        0xff0e, // ．
        0xff1a, // ：
        0xff1b, // ；
        => true,
        else => false,
    };
}

fn isFullwidthQuestionOrExclamation(codepoint: u21) bool {
    return codepoint == 0xff01 or codepoint == 0xff1f;
}

fn restrictToSourceAtomEdges(
    glyphs: []const GlyphPosition,
    sides: []Sides,
) void {
    var start: usize = 0;
    while (start < glyphs.len) {
        var end = start + 1;
        while (end < glyphs.len and
            glyphs[end].cluster == glyphs[start].cluster)
        {
            end += 1;
        }
        for (start + 1..end) |index| sides[index].start = 0;
        for (start..end - 1) |index| sides[index].end = 0;
        start = end;
    }
}

fn effectiveFactor(
    glyph_index: usize,
    hanging_index: ?usize,
    hanging_fraction: f32,
) f32 {
    if (hanging_index != null and hanging_index.? == glyph_index) {
        return @max(0, 1 - hanging_fraction);
    }
    return 1;
}

fn shrinkStart(
    glyph: *GlyphPosition,
    amount: f32,
    writing_mode: pipeline_types.WritingMode,
) void {
    if (amount <= 0) return;
    if (writing_mode.isVertical()) {
        // Positive shaping y-offset moves ink upward in target space. Moving
        // ink toward the preceding pen removes top-side blank while the
        // reduced positive-down advance keeps the following pen attached.
        glyph.y_offset += amount;
        glyph.y_advance -= amount;
    } else {
        glyph.x_offset -= amount;
        glyph.x_advance -= amount;
    }
}

fn shrinkEnd(
    glyph: *GlyphPosition,
    amount: f32,
    writing_mode: pipeline_types.WritingMode,
) void {
    if (amount <= 0) return;
    if (writing_mode.isVertical()) {
        glyph.y_advance -= amount;
    } else {
        glyph.x_advance -= amount;
    }
}

fn inlineAdvance(
    glyph: GlyphPosition,
    writing_mode: pipeline_types.WritingMode,
) f32 {
    return if (writing_mode.isVertical())
        glyph.y_advance
    else
        glyph.x_advance;
}

fn inlineSize(
    glyphs: []const GlyphPosition,
    writing_mode: pipeline_types.WritingMode,
) f32 {
    if (!writing_mode.isVertical()) return geometry.lineWidth(glyphs);
    var result: f32 = 0;
    for (glyphs) |glyph| result += glyph.y_advance;
    return result;
}

fn logicalHangingAmount(
    glyphs: []const GlyphPosition,
    glyph_start: usize,
    glyph_end: usize,
    fraction: f32,
    writing_mode: pipeline_types.WritingMode,
) f32 {
    return if (writing_mode.isVertical())
        hanging.verticalLogicalEndAmount(
            glyphs,
            glyph_start,
            glyph_end,
            fraction,
        )
    else
        hanging.logicalEndAmount(
            glyphs,
            glyph_start,
            glyph_end,
            fraction,
        );
}

fn effectiveMaxWidth(max_width: f32) f32 {
    return if (max_width > 0 and std.math.isFinite(max_width))
        max_width
    else
        std.math.inf(f32);
}

test "compression uses only the reduction needed" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x3002, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x300c, .cluster = 3, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        effectiveCapacity(
            &glyphs,
            0,
            glyphs.len,
            1,
            0,
            .generic,
            .horizontal_tb,
        ),
        0.001,
    );
    var sides: [glyphs.len]Sides = undefined;
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        applyToLine(
            &glyphs,
            &sides,
            3,
            1,
            0,
            .generic,
            null,
            .horizontal_tb,
        ),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 7), glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), glyphs[1].x_advance, 0.001);
}

test "capacity counts only reusable source-atom edges" {
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x3002, .cluster = 0, .x_advance = 4 },
        .{ .glyph_id = 2, .codepoint = 0x3002, .cluster = 0, .x_advance = 6 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        effectiveCapacity(
            &glyphs,
            0,
            glyphs.len,
            1,
            0,
            .generic,
            .horizontal_tb,
        ),
        0.001,
    );
}

test "hanging reduces effective compression capacity at the same edge" {
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x4e00, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x3002, .cluster = 3, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 5),
        effectiveCapacity(
            &glyphs,
            0,
            glyphs.len,
            1,
            0,
            .generic,
            .horizontal_tb,
        ),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.5),
        effectiveCapacity(
            &glyphs,
            0,
            glyphs.len,
            1,
            0.5,
            .generic,
            .horizontal_tb,
        ),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        effectiveCapacity(
            &glyphs,
            0,
            glyphs.len,
            1,
            1,
            .generic,
            .horizontal_tb,
        ),
        0.001,
    );
}

test "GB CNS and JIS conventions classify stop and question punctuation" {
    const stop = GlyphPosition{
        .glyph_id = 1,
        .codepoint = 0x3002,
        .cluster = 0,
        .x_advance = 16,
    };
    const gb_stop = sideCapacity(stop, 1, .gb, .horizontal_tb);
    const cns_stop = sideCapacity(stop, 1, .cns, .horizontal_tb);
    const jis_stop = sideCapacity(stop, 1, .jis, .horizontal_tb);
    try std.testing.expectApproxEqAbs(@as(f32, 0), gb_stop.start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8), gb_stop.end, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), cns_stop.start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), cns_stop.end, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), jis_stop.start, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8), jis_stop.end, 0.001);

    const question = GlyphPosition{
        .glyph_id = 2,
        .codepoint = 0xff1f,
        .cluster = 3,
        .x_advance = 16,
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 8),
        sideCapacity(question, 1, .gb, .horizontal_tb).end,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        sideCapacity(question, 1, .cns, .horizontal_tb).end,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        sideCapacity(question, 1, .jis, .horizontal_tb).end,
        0.001,
    );
}

test "all regional conventions align brackets to the glyph edge" {
    const opening = GlyphPosition{
        .glyph_id = 1,
        .codepoint = 0x300c,
        .cluster = 0,
        .x_advance = 16,
    };
    const closing = GlyphPosition{
        .glyph_id = 2,
        .codepoint = 0x300d,
        .cluster = 3,
        .x_advance = 16,
    };
    for ([_]paragraph_options.PunctuationConvention{ .gb, .cns, .jis }) |style| {
        try std.testing.expectApproxEqAbs(
            @as(f32, 8),
            sideCapacity(opening, 1, style, .horizontal_tb).start,
            0.001,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, 8),
            sideCapacity(closing, 1, style, .horizontal_tb).end,
            0.001,
        );
    }
}

test "vertical compression uses y advance and converts top-side offsets" {
    var glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 0x300c,
            .cluster = 0,
            .x_advance = 0,
            .y_advance = 20,
        },
        .{
            .glyph_id = 2,
            .codepoint = 0x3002,
            .cluster = 3,
            .x_advance = 0,
            .y_advance = 20,
        },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 20),
        effectiveCapacity(
            &glyphs,
            0,
            glyphs.len,
            1,
            0,
            .jis,
            .vertical_rl,
        ),
        0.001,
    );
    var sides: [glyphs.len]Sides = undefined;
    try std.testing.expectApproxEqAbs(
        @as(f32, 15),
        applyToLine(
            &glyphs,
            &sides,
            15,
            1,
            0,
            .jis,
            null,
            .vertical_rl,
        ),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 10), glyphs[0].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 15), glyphs[1].y_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), glyphs[0].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), glyphs[1].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), glyphs[0].x_advance, 0.001);
}
