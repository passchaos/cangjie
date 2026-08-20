//! Stable renderer-free trace of cluster-safe font fallback decisions.

const std = @import("std");

const arabic_normalization = @import("../../arabic_normalization.zig");
const font_fallback = @import("../fallback/font/root.zig");
const types = @import("types.zig");
const unicode = @import("../../unicode.zig");

/// Trace the font/glyph selected for each visible source scalar.
///
/// Variation selectors are folded into the preceding scalar, matching the
/// shaping pipeline's source-span model. The caller owns the returned slice.
pub fn analyze(
    allocator: std.mem.Allocator,
    cascade: font_fallback.Cascade,
    text: []const u8,
) ![]types.FontFallbackDecision {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    if (cascade.fonts.len == 0) return error.EmptyFontCascade;

    var decisions = std.ArrayList(types.FontFallbackDecision).empty;
    errdefer decisions.deinit(allocator);

    var clusters = unicode.graphemeClustersAssumeValid(text);
    while (clusters.next()) |cluster| {
        const cluster_end = cluster.byte_start + cluster.byte_len;
        const cluster_text = text[cluster.byte_start..cluster_end];
        const font_index = try font_fallback.selectFontForClusterFrom(
            cascade.fonts,
            null,
            cluster_text,
        );
        const font = cascade.fonts[font_index];

        var iterator =
            std.unicode.Utf8Iterator{ .bytes = cluster_text, .i = 0 };
        while (iterator.i < cluster_text.len) {
            const local_start = iterator.i;
            const codepoint = iterator.nextCodepoint() orelse break;
            if (unicode.isVariationSelector(codepoint) or
                font_fallback.isClusterCoverageIgnorable(codepoint))
            {
                // Detached selectors and join controls influence cluster
                // selection but do not produce visible diagnostic records.
                continue;
            }

            if (try arabic_normalization.composeAtForFont(
                font,
                null,
                codepoint,
                cluster_text,
                iterator.i,
            )) |composition| {
                try decisions.append(allocator, .{
                    .byte_start = cluster.byte_start + local_start,
                    .byte_len = composition.byte_end - local_start,
                    .codepoint = composition.codepoint,
                    .font_index = font_index,
                    .glyph_id = composition.glyph_id,
                });
                iterator.i = composition.byte_end;
                continue;
            }

            var byte_len = iterator.i - local_start;
            var variation_selector: ?u21 = null;
            var used_variation_mapping = false;
            if (nextVariationSelector(cluster_text, iterator.i)) |selector| {
                variation_selector = selector;
                _ = iterator.nextCodepoint();
                byte_len = iterator.i - local_start;
                used_variation_mapping =
                    try font.variationGlyphIndex(codepoint, selector) != null;
            }

            const glyph_id = if (variation_selector) |selector|
                try font.glyphIndexWithVariation(codepoint, selector)
            else
                try font.glyphIndex(codepoint);

            try decisions.append(allocator, .{
                .byte_start = cluster.byte_start + local_start,
                .byte_len = byte_len,
                .codepoint = codepoint,
                .variation_selector = variation_selector,
                .font_index = font_index,
                .glyph_id = glyph_id,
                .used_variation_mapping = used_variation_mapping,
            });
        }
    }

    return try decisions.toOwnedSlice(allocator);
}

fn nextVariationSelector(text: []const u8, byte_index: usize) ?u21 {
    if (byte_index >= text.len) return null;
    var lookahead =
        std.unicode.Utf8Iterator{ .bytes = text, .i = byte_index };
    const selector = lookahead.nextCodepoint() orelse return null;
    return if (unicode.isVariationSelector(selector)) selector else null;
}
