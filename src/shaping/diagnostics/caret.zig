//! UTF-8 source-span and caret round-trip diagnostics.

const std = @import("std");

const GlyphPosition = @import("../../layout/glyph_position.zig").GlyphPosition;
const paragraph_types = @import("../../layout/types/paragraph.zig");
const types = @import("types.zig");
const unicode = @import("../../unicode.zig");

pub fn analyze(
    allocator: std.mem.Allocator,
    text: []const u8,
    paragraph: paragraph_types.ParagraphLayout,
) !types.ClusterCaretConsistencyReport {
    var issues = std.ArrayList(types.ClusterCaretDiagnostic).empty;
    errdefer issues.deinit(allocator);

    for (paragraph.glyphs, 0..) |glyph, glyph_index| {
        const source_end = sourceEnd(glyph);
        if (!try validateSourceSpan(
            allocator,
            text,
            glyph,
            glyph_index,
            &issues,
        )) continue;

        try checkBoundary(
            allocator,
            paragraph,
            glyph_index,
            glyph.cluster,
            .leading_caret_roundtrip_mismatch,
            &issues,
        );
        try checkBoundary(
            allocator,
            paragraph,
            glyph_index,
            source_end,
            .trailing_caret_roundtrip_mismatch,
            &issues,
        );
    }

    const graphemes = try unicode.itemizeGraphemeClusters(allocator, text);
    defer allocator.free(graphemes);
    for (graphemes) |grapheme| {
        try checkBoundary(
            allocator,
            paragraph,
            null,
            grapheme.byte_start,
            .grapheme_boundary_roundtrip_mismatch,
            &issues,
        );
        try checkBoundary(
            allocator,
            paragraph,
            null,
            grapheme.byte_start + grapheme.byte_len,
            .grapheme_boundary_roundtrip_mismatch,
            &issues,
        );
    }

    const owned_issues = try issues.toOwnedSlice(allocator);
    return .{
        .glyph_count = paragraph.glyphs.len,
        .caret_boundary_count = paragraph.glyphs.len * 2,
        .grapheme_boundary_count = graphemes.len * 2,
        .issue_count = owned_issues.len,
        .issues = owned_issues,
    };
}

fn validateSourceSpan(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyph: GlyphPosition,
    glyph_index: usize,
    issues: *std.ArrayList(types.ClusterCaretDiagnostic),
) !bool {
    const source_end = sourceEnd(glyph);
    var valid = true;

    if (glyph.source_byte_len == 0) {
        valid = false;
        try issues.append(allocator, .{
            .kind = .empty_source_span,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    }
    if (glyph.cluster > text.len) {
        valid = false;
        try issues.append(allocator, .{
            .kind = .glyph_cluster_out_of_bounds,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    } else if (!isUtf8Boundary(text, glyph.cluster)) {
        valid = false;
        try issues.append(allocator, .{
            .kind = .cluster_not_utf8_boundary,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    }
    if (source_end > text.len) {
        valid = false;
        try issues.append(allocator, .{
            .kind = .glyph_source_end_out_of_bounds,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    } else if (!isUtf8Boundary(text, source_end)) {
        valid = false;
        try issues.append(allocator, .{
            .kind = .source_end_not_utf8_boundary,
            .glyph_index = glyph_index,
            .cluster = glyph.cluster,
            .source_end = source_end,
        });
    }
    return valid;
}

fn checkBoundary(
    allocator: std.mem.Allocator,
    paragraph: paragraph_types.ParagraphLayout,
    glyph_index: ?usize,
    byte_offset: usize,
    kind: types.ClusterCaretIssueKind,
    issues: *std.ArrayList(types.ClusterCaretDiagnostic),
) !void {
    const position = paragraph_types.positionForCluster(
        paragraph,
        byte_offset,
    );
    const actual = paragraph_types.positionByteOffset(paragraph, position);
    if (actual == byte_offset) return;
    try issues.append(allocator, .{
        .kind = kind,
        .glyph_index = glyph_index,
        .cluster = byte_offset,
        .source_end = byte_offset,
        .expected_byte_offset = byte_offset,
        .actual_byte_offset = actual,
    });
}

fn sourceEnd(glyph: GlyphPosition) usize {
    return glyph.cluster + @max(glyph.source_byte_len, 1);
}

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset > text.len) return false;
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0xc0) != 0x80;
}
