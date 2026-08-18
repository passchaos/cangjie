//! Mapping between source-text boundaries and retained shaped glyphs.
//!
//! Paragraph wrapping may reuse a shaped run only at boundaries that do not
//! participate in GSUB/GPOS/fallback relationships. This module keeps that
//! invariant in one place for both UAX #14 opportunities and emergency
//! grapheme wrapping; otherwise an emergency break could silently bypass an
//! `unsafe-to-break` flag rejected by the normal word-wrap path.

const std = @import("std");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const unicode = @import("../../unicode.zig");

pub const OverflowBreak = struct {
    index: usize,
    uses_current_discardable: bool = false,
    /// The current candidate is still part of an indivisible shaped span.
    /// Continue consuming glyphs until a later safe source boundary appears.
    defer_break: bool = false,
};

pub fn chooseOverflowBreak(
    glyphs: []const GlyphPosition,
    grapheme_clusters: []const unicode.GraphemeCluster,
    index: usize,
    line_start: usize,
    last_break: ?usize,
    emergency_enabled: bool,
    preserve_discardable: bool,
) OverflowBreak {
    if (!preserve_discardable and
        isDiscardableBreak(glyphs[index].codepoint) and
        !outputBoundaryIsUnsafe(glyphs, index))
    {
        return .{ .index = index, .uses_current_discardable = true };
    }
    if (last_break) |break_index| {
        if (break_index > line_start and
            !outputBoundaryIsUnsafe(glyphs, break_index))
        {
            return .{ .index = break_index };
        }
    }
    if (!emergency_enabled) {
        // With no legal earlier boundary, overflow is intentional. Consume
        // the complete shaped stream instead of repeatedly reconsidering the
        // same overfull atom as a fabricated line edge.
        return .{ .index = glyphs.len, .defer_break = true };
    }
    return graphemeOverflowBreak(
        glyphs,
        grapheme_clusters,
        index,
        line_start,
    );
}

pub fn sourceBoundaryIsUnsafe(
    glyphs: []const GlyphPosition,
    byte_offset: usize,
    current_index: usize,
) bool {
    if (glyphs.len == 0) return false;
    const current = @min(current_index, glyphs.len - 1);

    // Line-break opportunities are consumed as soon as the current shaped
    // atom ends, so an unsafe boundary can only be carried by that glyph or
    // the immediately following atom. Every output sharing a cluster queries
    // the same source-byte sidecar bit during construction, making one glyph
    // per atom sufficient and preserving O(1) work per UAX #14 opportunity.
    const current_glyph = glyphs[current];
    if (current_glyph.cluster == byte_offset and
        current_glyph.isUnsafeToBreakBefore())
    {
        return true;
    }
    if (current + 1 >= glyphs.len) return false;
    const next_glyph = glyphs[current + 1];
    return next_glyph.cluster == byte_offset and
        next_glyph.isUnsafeToBreakBefore();
}

pub fn glyphClusterStart(glyph: GlyphPosition) usize {
    return glyph.cluster;
}

pub fn glyphSourceEnd(glyph: GlyphPosition) usize {
    return glyph.sourceByteEnd();
}

pub fn byteEndForGlyphPrefix(
    glyphs: []const GlyphPosition,
    glyph_end: usize,
    fallback: usize,
) usize {
    var byte_end = fallback;
    // Logical line byte boundaries are independent of visual glyph order. A
    // prefix scan is therefore intentionally source-oriented: it finds the
    // largest source end represented before the visual split even when bidi
    // clusters inside that prefix are not monotonic.
    for (glyphs[0..@min(glyph_end, glyphs.len)]) |glyph| {
        byte_end = @max(byte_end, glyphSourceEnd(glyph));
    }
    return byte_end;
}

pub fn glyphIndexForSourceBoundary(
    glyphs: []const GlyphPosition,
    boundary: usize,
    line_start: usize,
    fallback: usize,
) ?usize {
    var index = line_start + 1;
    while (index < glyphs.len and index <= fallback) : (index += 1) {
        if (glyphClusterStart(glyphs[index]) >= boundary) return index;
    }
    if (glyphs.len != 0 and
        fallback >= glyphs.len and
        boundary >= glyphSourceEnd(glyphs[glyphs.len - 1]))
    {
        return glyphs.len;
    }
    return null;
}

fn graphemeOverflowBreak(
    glyphs: []const GlyphPosition,
    grapheme_clusters: []const unicode.GraphemeCluster,
    index: usize,
    line_start: usize,
) OverflowBreak {
    const cluster_start = glyphClusterStart(glyphs[index]);
    const line_cluster_start = glyphClusterStart(glyphs[line_start]);
    const current_cluster = graphemeClusterContaining(
        grapheme_clusters,
        cluster_start,
    ) orelse {
        const break_index = nextSafeOutputBoundary(
            glyphs,
            grapheme_clusters,
            index + 1,
        );
        if (break_index <= index + 1) return .{ .index = break_index };
        return .{ .index = break_index, .defer_break = true };
    };
    const current_cluster_start = current_cluster.byte_start;
    const current_cluster_end =
        current_cluster.byte_start + current_cluster.byte_len;

    if (current_cluster_start > line_cluster_start) {
        const candidate = glyphIndexForSourceBoundary(
            glyphs,
            current_cluster_start,
            line_start,
            index,
        ) orelse index;
        const break_index = nextSafeOutputBoundary(
            glyphs,
            grapheme_clusters,
            candidate,
        );
        if (break_index <= index + 1) return .{ .index = break_index };
        return .{ .index = break_index, .defer_break = true };
    }

    // MultipleSubst and other one-to-many transformations can emit adjacent
    // glyphs with the same source cluster. Source extent alone cannot tell
    // whether the current output is the last member, so consume the entire
    // atom. Once complete, the following boundary must still pass the shaping
    // safety check; a kern or mark relationship may cross grapheme clusters.
    const cluster_continues = index + 1 < glyphs.len and
        glyphClusterStart(glyphs[index + 1]) == current_cluster_start;
    if (!cluster_continues and
        glyphSourceEnd(glyphs[index]) >= current_cluster_end)
    {
        const break_index = nextSafeOutputBoundary(
            glyphs,
            grapheme_clusters,
            index + 1,
        );
        if (break_index <= index + 1) return .{ .index = break_index };
        return .{ .index = break_index, .defer_break = true };
    }
    return .{ .index = index, .defer_break = true };
}

fn nextSafeOutputBoundary(
    glyphs: []const GlyphPosition,
    grapheme_clusters: []const unicode.GraphemeCluster,
    candidate: usize,
) usize {
    var break_index = candidate;
    // A positioning relationship can chain across multiple glyphs. Defer to
    // the first following source-atom and grapheme boundary that is not marked
    // unsafe rather than reconsidering the same candidate forever. Requiring
    // a distinct output cluster also prevents one-to-many substitutions from
    // becoming splittable merely because only their first output carries an
    // unsafe flag.
    while (!outputBoundaryIsReusable(
        glyphs,
        grapheme_clusters,
        break_index,
    )) {
        break_index += 1;
    }
    return break_index;
}

/// Whether an output boundary can be reused as an emergency paragraph break.
///
/// High-quality breakers enumerate the complete candidate graph instead of
/// discovering only the first overflowing boundary. They must use exactly the
/// same grapheme and shaping-safety predicate as greedy emergency wrapping.
pub fn outputBoundaryIsReusable(
    glyphs: []const GlyphPosition,
    grapheme_clusters: []const unicode.GraphemeCluster,
    break_index: usize,
) bool {
    if (break_index >= glyphs.len) return true;
    if (break_index == 0 or outputBoundaryIsUnsafe(glyphs, break_index)) {
        return false;
    }
    const byte_offset = glyphClusterStart(glyphs[break_index]);
    if (byte_offset == glyphClusterStart(glyphs[break_index - 1])) {
        return false;
    }
    for (grapheme_clusters) |cluster| {
        if (cluster.byte_start == byte_offset) return true;
        if (cluster.byte_start > byte_offset) return false;
    }
    return false;
}

fn outputBoundaryIsUnsafe(
    glyphs: []const GlyphPosition,
    break_index: usize,
) bool {
    // The end of the shaped stream does not split a shaping relationship.
    if (break_index >= glyphs.len) return false;
    return glyphs[break_index].isUnsafeToBreakBefore();
}

fn graphemeClusterContaining(
    clusters: []const unicode.GraphemeCluster,
    byte_offset: usize,
) ?unicode.GraphemeCluster {
    for (clusters) |cluster| {
        const end = cluster.byte_start + cluster.byte_len;
        if (byte_offset >= cluster.byte_start and byte_offset < end) {
            return cluster;
        }
    }
    return null;
}

fn isDiscardableBreak(codepoint: u21) bool {
    return codepoint == ' ' or codepoint == '\t';
}

test "emergency breaks defer across unsafe positioning boundaries" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 16,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'B',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 16,
            .flags = .{ .unsafe_to_break_before = true },
        },
    };
    const clusters = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = 1 },
        .{ .byte_start = 1, .byte_len = 1 },
    };

    const after_first = chooseOverflowBreak(
        &glyphs,
        &clusters,
        0,
        0,
        null,
        true,
        false,
    );
    try std.testing.expect(after_first.defer_break);

    const after_second = chooseOverflowBreak(
        &glyphs,
        &clusters,
        1,
        0,
        null,
        true,
        false,
    );
    try std.testing.expect(!after_second.defer_break);
    try std.testing.expectEqual(@as(usize, 2), after_second.index);
}

test "disabled emergency wrapping intentionally keeps overfull content" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 16,
        },
        .{
            .glyph_id = 1,
            .codepoint = 'B',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 16,
        },
    };
    const clusters = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = 1 },
        .{ .byte_start = 1, .byte_len = 1 },
    };
    const selected = chooseOverflowBreak(
        &glyphs,
        &clusters,
        0,
        0,
        null,
        false,
        false,
    );
    try std.testing.expect(selected.defer_break);
    try std.testing.expectEqual(glyphs.len, selected.index);
}

test "deferred breaks never split multiple outputs of one source atom" {
    const glyphs = [_]GlyphPosition{
        .{
            .glyph_id = 1,
            .codepoint = 'A',
            .cluster = 0,
            .source_byte_len = 1,
            .x_advance = 16,
        },
        .{
            .glyph_id = 2,
            .codepoint = 'B',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 8,
            .flags = .{ .unsafe_to_break_before = true },
        },
        .{
            .glyph_id = 3,
            .codepoint = 'B',
            .cluster = 1,
            .source_byte_len = 1,
            .x_advance = 8,
        },
        .{
            .glyph_id = 4,
            .codepoint = 'C',
            .cluster = 2,
            .source_byte_len = 1,
            .x_advance = 16,
        },
    };
    const clusters = [_]unicode.GraphemeCluster{
        .{ .byte_start = 0, .byte_len = 1 },
        .{ .byte_start = 1, .byte_len = 1 },
        .{ .byte_start = 2, .byte_len = 1 },
    };

    const after_first = chooseOverflowBreak(
        &glyphs,
        &clusters,
        0,
        0,
        null,
        true,
        false,
    );
    try std.testing.expect(after_first.defer_break);
    try std.testing.expectEqual(@as(usize, 3), after_first.index);
}
