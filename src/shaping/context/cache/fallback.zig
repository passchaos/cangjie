//! Cascade-aware memoization of scalar and cluster font fallback.
//!
//! A cached font index has meaning only for one ordered cascade. Both cache
//! maps therefore include an exact cascade identity instead of assuming an
//! `Engine` will process only one fallback list during its lifetime.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const font_fallback = @import("../../fallback/font/root.zig");
const GlyphIndexCache = @import("glyph.zig").GlyphIndexCache;

const CascadeIdentity = struct {
    hash: u64,
    fonts: []const *const Font,

    fn init(cascade: font_fallback.Cascade) CascadeIdentity {
        return .{
            .hash = cascade.identity_hash,
            .fonts = cascade.fonts,
        };
    }

    fn eql(a: CascadeIdentity, b: CascadeIdentity) bool {
        if (a.hash != b.hash or a.fonts.len != b.fonts.len) return false;
        for (a.fonts, b.fonts) |a_font, b_font| {
            if (a_font != b_font) return false;
        }
        return true;
    }
};

const CascadeCache = struct {
    identity: CascadeIdentity,
    entries: std.AutoHashMap(u21, usize),
    cluster_entries: std.StringHashMap(usize),

    fn init(
        allocator: std.mem.Allocator,
        hash: u64,
        owned_fonts: []const *const Font,
    ) CascadeCache {
        return .{
            .identity = .{ .hash = hash, .fonts = owned_fonts },
            .entries = std.AutoHashMap(u21, usize).init(allocator),
            .cluster_entries = std.StringHashMap(usize).init(allocator),
        };
    }

    fn deinit(self: *CascadeCache, allocator: std.mem.Allocator) void {
        var iterator = self.cluster_entries.iterator();
        while (iterator.next()) |entry| allocator.free(entry.key_ptr.*);
        self.cluster_entries.deinit();
        self.entries.deinit();
        allocator.free(self.identity.fonts);
        self.* = undefined;
    }
};

pub const FontFallbackCache = struct {
    allocator: std.mem.Allocator,
    /// Each group owns one exact cascade identity and its O(1) decision maps.
    /// Group lookup is linear only in the number of distinct cascades used by
    /// this engine, rather than in the number of cached scalars or clusters.
    groups: std.ArrayList(CascadeCache) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) FontFallbackCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FontFallbackCache) void {
        self.clear();
        self.groups.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *FontFallbackCache) void {
        for (self.groups.items) |*group| group.deinit(self.allocator);
        self.groups.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn scalarEntryCount(self: *const FontFallbackCache) usize {
        var total: usize = 0;
        for (self.groups.items) |group| total += group.entries.count();
        return total;
    }

    pub fn clusterEntryCount(self: *const FontFallbackCache) usize {
        var total: usize = 0;
        for (self.groups.items) |group| {
            total += group.cluster_entries.count();
        }
        return total;
    }

    pub fn selectFont(
        self: *FontFallbackCache,
        cascade: font_fallback.Cascade,
        codepoint: u21,
    ) !usize {
        return try self.selectFontWithOptionalGlyphCache(
            cascade,
            null,
            codepoint,
        );
    }

    pub fn selectFontWithGlyphCache(
        self: *FontFallbackCache,
        cascade: font_fallback.Cascade,
        glyph_index_cache: *GlyphIndexCache,
        codepoint: u21,
    ) !usize {
        return try self.selectFontWithOptionalGlyphCache(
            cascade,
            glyph_index_cache,
            codepoint,
        );
    }

    pub fn selectFontForCluster(
        self: *FontFallbackCache,
        cascade: font_fallback.Cascade,
        glyph_index_cache: ?*GlyphIndexCache,
        cluster: []const u8,
    ) !usize {
        if (cluster.len == 1 and cluster[0] < 0x80) {
            return try self.selectFontWithOptionalGlyphCache(
                cascade,
                glyph_index_cache,
                cluster[0],
            );
        }

        const group = try self.getOrCreateCascade(cascade);
        if (group.cluster_entries.get(cluster)) |font_index| {
            self.hits += 1;
            return font_index;
        }

        self.misses += 1;
        const font_index = try font_fallback.selectFontForClusterFrom(
            cascade.fonts,
            glyph_index_cache,
            cluster,
        );
        const owned_cluster = try self.allocator.dupe(u8, cluster);
        errdefer self.allocator.free(owned_cluster);
        try group.cluster_entries.put(owned_cluster, font_index);
        return font_index;
    }

    fn selectFontWithOptionalGlyphCache(
        self: *FontFallbackCache,
        cascade: font_fallback.Cascade,
        glyph_index_cache: ?*GlyphIndexCache,
        codepoint: u21,
    ) !usize {
        const group = try self.getOrCreateCascade(cascade);
        if (group.entries.get(codepoint)) |font_index| {
            self.hits += 1;
            return font_index;
        }

        self.misses += 1;
        const font_index = try font_fallback.selectFontFrom(
            cascade.fonts,
            glyph_index_cache,
            codepoint,
        );
        try group.entries.put(codepoint, font_index);
        return font_index;
    }

    fn getOrCreateCascade(
        self: *FontFallbackCache,
        cascade: font_fallback.Cascade,
    ) !*CascadeCache {
        if (cascade.fonts.len == 0) return error.EmptyFontCascade;
        const identity = CascadeIdentity.init(cascade);
        for (self.groups.items) |*group| {
            if (group.identity.eql(identity)) return group;
        }

        const owned_fonts =
            try self.allocator.dupe(*const Font, cascade.fonts);
        errdefer self.allocator.free(owned_fonts);
        try self.groups.append(
            self.allocator,
            CascadeCache.init(self.allocator, identity.hash, owned_fonts),
        );
        return &self.groups.items[self.groups.items.len - 1];
    }
};

test "fallback cache separates reordered cascades" {
    const test_font = @import("../../../test_font.zig");
    const allocator = std.testing.allocator;
    const primary_bytes =
        try test_font.buildCodepointSetTtf(allocator, &.{'A'});
    defer allocator.free(primary_bytes);
    const complete_bytes =
        try test_font.buildCodepointSetTtf(allocator, &.{ 'A', 0x0301 });
    defer allocator.free(complete_bytes);

    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var complete = try Font.parse(allocator, complete_bytes);
    defer complete.deinit();

    const primary_first = [_]*const Font{ &primary, &complete };
    const complete_first = [_]*const Font{ &complete, &primary };
    const primary_first_cascade =
        font_fallback.Cascade.init(primary_first[0..]);
    const complete_first_cascade =
        font_fallback.Cascade.init(complete_first[0..]);
    var cache = FontFallbackCache.init(allocator);
    defer cache.deinit();

    try std.testing.expectEqual(
        @as(usize, 1),
        try cache.selectFont(primary_first_cascade, 0x0301),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try cache.selectFont(complete_first_cascade, 0x0301),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        try cache.selectFontForCluster(
            primary_first_cascade,
            null,
            "A\u{0301}",
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try cache.selectFontForCluster(
            complete_first_cascade,
            null,
            "A\u{0301}",
        ),
    );

    // Repeats hit their own cascade group rather than reusing the other
    // cascade's numerically valid but semantically different font index.
    _ = try cache.selectFont(primary_first_cascade, 0x0301);
    _ = try cache.selectFontForCluster(
        complete_first_cascade,
        null,
        "A\u{0301}",
    );
    try std.testing.expectEqual(@as(usize, 2), cache.groups.items.len);
    try std.testing.expectEqual(@as(usize, 2), cache.scalarEntryCount());
    try std.testing.expectEqual(@as(usize, 2), cache.clusterEntryCount());
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 4), cache.misses);
}
