//! Source-order glyph metadata used by the detached ranged-GSUB executor.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const gpos = @import("../../../gpos.zig");
const GlyphIndexCache = @import("../../../layout_cache.zig").GlyphIndexCache;
const ligature_provenance = @import("../../../ligature_provenance.zig");
const ranges_mod = @import("ranges.zig");
const run_metadata = @import("../../run_metadata.zig");
const cluster_safety = @import("../../cluster_safety.zig");
const unicode = @import("../../../unicode.zig");

pub const Buffer = struct {
    text_byte_len: usize = 0,
    glyph_ids: std.ArrayList(GlyphId) = .empty,
    codepoints: std.ArrayList(u21) = .empty,
    source_byte_starts: std.ArrayList(usize) = .empty,
    source_byte_ends: std.ArrayList(usize) = .empty,
    glyph_sources: std.ArrayList(usize) = .empty,
    glyph_clusters: std.ArrayList(usize) = .empty,
    glyph_substituted: std.ArrayList(bool) = .empty,
    source_features: std.ArrayList(u32) = .empty,
    tag_values: std.ArrayList(ranges_mod.TagValue) = .empty,
    ordinary_overrides: std.ArrayList(unicode.FeatureOverride) = .empty,
    gpos_adjustments: std.ArrayList(gpos.Adjustment) = .empty,
    attachment_links: std.ArrayList(@import("../../../attachment.zig").Link) = .empty,
    unsafe_glyphs: run_metadata.UnsafeGlyphs = .{},
    source_boundaries: cluster_safety.SourceBoundaries = .{},
    ligature_components: ligature_provenance.Store = .{},

    pub fn deinit(self: *Buffer, allocator: std.mem.Allocator) void {
        self.ligature_components.deinit(allocator);
        self.source_boundaries.deinit(allocator);
        self.attachment_links.deinit(allocator);
        self.gpos_adjustments.deinit(allocator);
        self.ordinary_overrides.deinit(allocator);
        self.tag_values.deinit(allocator);
        self.source_features.deinit(allocator);
        self.glyph_substituted.deinit(allocator);
        self.glyph_clusters.deinit(allocator);
        self.glyph_sources.deinit(allocator);
        self.source_byte_ends.deinit(allocator);
        self.source_byte_starts.deinit(allocator);
        self.codepoints.deinit(allocator);
        self.glyph_ids.deinit(allocator);
    }

    pub fn build(
        self: *Buffer,
        font: *const Font,
        glyph_index_cache: ?*GlyphIndexCache,
        allocator: std.mem.Allocator,
        text: []const u8,
    ) !void {
        self.text_byte_len = text.len;
        try self.glyph_ids.ensureUnusedCapacity(allocator, text.len);
        try self.codepoints.ensureUnusedCapacity(allocator, text.len);
        try self.source_byte_starts.ensureUnusedCapacity(allocator, text.len);
        try self.source_byte_ends.ensureUnusedCapacity(allocator, text.len);
        try self.glyph_sources.ensureUnusedCapacity(allocator, text.len);
        try self.glyph_clusters.ensureUnusedCapacity(allocator, text.len);
        try self.glyph_substituted.ensureUnusedCapacity(allocator, text.len);
        try self.ligature_components.infos.ensureUnusedCapacity(
            allocator,
            text.len,
        );

        var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (iterator.i < text.len) {
            const byte_start = iterator.i;
            const codepoint = iterator.nextCodepoint() orelse break;
            // Variation-selector folding must update source extents and cmap14
            // identity together. The first ranged API rejects that case rather
            // than retaining a subtly different cluster contract.
            if (unicode.isVariationSelector(codepoint)) {
                return error.UnsupportedFeatureRanges;
            }
            const glyph_id = if (glyph_index_cache) |cache|
                try cache.glyphIndex(font, codepoint)
            else
                try font.glyphIndex(codepoint);
            const source = self.codepoints.items.len;
            self.glyph_ids.appendAssumeCapacity(glyph_id);
            self.codepoints.appendAssumeCapacity(codepoint);
            self.source_byte_starts.appendAssumeCapacity(byte_start);
            self.source_byte_ends.appendAssumeCapacity(iterator.i);
            self.glyph_sources.appendAssumeCapacity(source);
            self.glyph_clusters.appendAssumeCapacity(source);
            self.glyph_substituted.appendAssumeCapacity(false);
            self.ligature_components.infos.appendAssumeCapacity(.{});
        }
    }
};
