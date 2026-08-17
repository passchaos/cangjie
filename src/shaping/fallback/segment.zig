//! Split one homogeneous shaping item into contiguous fallback-font segments.
//!
//! The segmentation policy lives here; actual shaping remains supplied by a
//! generic context's `appendSegment` method. Zig resolves that method at
//! comptime, so this boundary adds no runtime callback or type erasure.

const std = @import("std");

const cache = @import("../context/cache/root.zig");
const font_fallback = @import("font/root.zig");
const unicode = @import("../../unicode.zig");

pub const Pen = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Input = struct {
    cascade: font_fallback.Cascade,
    fallback_cache: ?*cache.FontFallbackCache = null,
    glyph_index_cache: ?*cache.GlyphIndexCache = null,
    text: []const u8,
    cluster_base: usize = 0,
    pen: Pen = .{},
};

/// Invoke `context.appendSegment(cascade, font_index, text, cluster_base, pen)`
/// once for each maximal contiguous span assigned to one fallback face.
pub fn shape(context: anytype, input: Input) !Pen {
    if (input.cascade.fonts.len == 0) return error.EmptyFontCascade;

    var segment_start: usize = 0;
    var segment_font_index: ?usize = null;
    var next_pen = input.pen;

    if (isAscii(input.text)) {
        // Every ASCII byte is one grapheme. Avoid Unicode iteration on the
        // dominant Latin/UI path while preserving CR/LF face selection.
        for (input.text, 0..) |codepoint, cluster_start| {
            const font_index = try selectScalar(input, codepoint);
            if (segment_font_index == null) {
                segment_start = cluster_start;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                next_pen = try context.appendSegment(
                    input.cascade,
                    segment_font_index.?,
                    input.text[segment_start..cluster_start],
                    input.cluster_base + segment_start,
                    next_pen,
                );
                segment_start = cluster_start;
                segment_font_index = font_index;
            }
        }
    } else {
        var clusters = unicode.graphemeClustersAssumeValid(input.text);
        while (clusters.next()) |cluster| {
            const cluster_end = cluster.byte_start + cluster.byte_len;
            const font_index = try selectCluster(
                input,
                input.text[cluster.byte_start..cluster_end],
            );
            if (segment_font_index == null) {
                segment_start = cluster.byte_start;
                segment_font_index = font_index;
            } else if (segment_font_index.? != font_index) {
                next_pen = try context.appendSegment(
                    input.cascade,
                    segment_font_index.?,
                    input.text[segment_start..cluster.byte_start],
                    input.cluster_base + segment_start,
                    next_pen,
                );
                segment_start = cluster.byte_start;
                segment_font_index = font_index;
            }
        }
    }

    if (segment_font_index) |font_index| {
        next_pen = try context.appendSegment(
            input.cascade,
            font_index,
            input.text[segment_start..],
            input.cluster_base + segment_start,
            next_pen,
        );
    }
    return next_pen;
}

pub fn isAscii(text: []const u8) bool {
    for (text) |byte| {
        if (byte >= 0x80) return false;
    }
    return true;
}

fn selectScalar(input: Input, codepoint: u21) !usize {
    if (input.fallback_cache) |fallback_cache| {
        if (input.glyph_index_cache) |glyph_cache| {
            return try fallback_cache.selectFontWithGlyphCache(
                input.cascade,
                glyph_cache,
                codepoint,
            );
        }
        return try fallback_cache.selectFont(input.cascade, codepoint);
    }
    return try font_fallback.selectFontFrom(
        input.cascade.fonts,
        input.glyph_index_cache,
        codepoint,
    );
}

fn selectCluster(input: Input, cluster: []const u8) !usize {
    if (input.cascade.fonts.len == 1) return 0;
    if (cluster.len == 1 and cluster[0] < 0x80) {
        return try selectScalar(input, cluster[0]);
    }
    if (input.fallback_cache) |fallback_cache| {
        return try fallback_cache.selectFontForCluster(
            input.cascade,
            input.glyph_index_cache,
            cluster,
        );
    }
    return try font_fallback.selectFontForClusterFrom(
        input.cascade.fonts,
        input.glyph_index_cache,
        cluster,
    );
}
