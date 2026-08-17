//! Owned cache storage for complete shaped runs.
//!
//! This module owns cached glyph/run arrays and the source identity needed to
//! validate a hit. Copying an entry into a caller's output buffer remains an
//! orchestration concern, keeping this cache independent of paragraph policy.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const glyph_position = @import("../../../layout/glyph_position.zig");
const run_types = @import("../../../layout/types/runs.zig");
const shaping_plan = @import("../../plan/root.zig");
const unicode = @import("../../../unicode.zig");

pub const ShapedRunCacheKey = struct {
    cascade_hash: u64,
    text_hash: u64,
    font_size_bits: u32,
    plan: shaping_plan.ShapePlanKey,
    /// Borrowed for lookup keys and owned by the cache for stored keys.
    fonts: []const *const Font,
    /// Borrowed for lookup keys and owned by the cache for stored keys.
    text: []const u8,
    /// Dynamic plan inputs are retained exactly because their hashes are only
    /// rejection filters and cannot, by themselves, prove cache identity.
    features: []const unicode.FeatureOverride,
    normalized_variation_coords: []const f32,
    context_before: []const u8,
    context_after: []const u8,

    pub fn init(
        fonts: []const *const Font,
        text: []const u8,
        font_size: f32,
        options: shaping_plan.ShapeOptions,
    ) ShapedRunCacheKey {
        return .{
            .cascade_hash = cascadeHash(fonts),
            .text_hash = std.hash.Wyhash.hash(0, text),
            .font_size_bits = @bitCast(font_size),
            .plan = shaping_plan.ShapePlanKey.fromText(text, options),
            .fonts = fonts,
            .text = text,
            .features = options.features,
            .normalized_variation_coords = options.normalized_variation_coords,
            .context_before = options.context_before,
            .context_after = options.context_after,
        };
    }

    pub fn eql(a: ShapedRunCacheKey, b: ShapedRunCacheKey) bool {
        if (a.cascade_hash != b.cascade_hash or
            a.text_hash != b.text_hash or
            a.font_size_bits != b.font_size_bits or
            !a.plan.eql(b.plan) or
            a.fonts.len != b.fonts.len or
            !std.mem.eql(u8, a.text, b.text) or
            !featureOverridesEqual(a.features, b.features) or
            !variationCoordsEqual(
                a.normalized_variation_coords,
                b.normalized_variation_coords,
            ) or
            !std.mem.eql(u8, a.context_before, b.context_before) or
            !std.mem.eql(u8, a.context_after, b.context_after))
        {
            return false;
        }

        // Hashes are only rejection filters. Exact source and cascade identity
        // prevent an adversarial or accidental collision from returning glyphs
        // shaped for different bytes or different face ordering.
        for (a.fonts, b.fonts) |a_font, b_font| {
            if (a_font != b_font) return false;
        }
        return true;
    }
};

pub const ShapedRunCacheEntry = struct {
    key: ShapedRunCacheKey,
    glyphs: []glyph_position.GlyphPosition,
    runs: []run_types.CascadeRun,
    variation_coords: []f32,
    hits: usize = 0,
};

pub const ShapedRunCache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(ShapedRunCacheEntry) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ShapedRunCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ShapedRunCache) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *ShapedRunCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.key.fonts);
            self.allocator.free(entry.key.text);
            self.allocator.free(entry.key.features);
            self.allocator.free(entry.key.normalized_variation_coords);
            self.allocator.free(entry.key.context_before);
            self.allocator.free(entry.key.context_after);
            self.allocator.free(entry.glyphs);
            self.allocator.free(entry.runs);
            self.allocator.free(entry.variation_coords);
        }
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn key(
        fonts: []const *const Font,
        text: []const u8,
        font_size: f32,
        options: shaping_plan.ShapeOptions,
    ) ShapedRunCacheKey {
        return .init(fonts, text, font_size, options);
    }

    /// Return a borrowed entry that remains valid until the cache is mutated.
    pub fn lookup(
        self: *ShapedRunCache,
        key_value: ShapedRunCacheKey,
    ) ?*const ShapedRunCacheEntry {
        for (self.entries.items) |*entry| {
            if (!entry.key.eql(key_value)) continue;
            self.hits += 1;
            entry.hits += 1;
            return entry;
        }
        self.misses += 1;
        return null;
    }

    pub fn store(
        self: *ShapedRunCache,
        key_value: ShapedRunCacheKey,
        shaped: run_types.ShapedText,
    ) !void {
        const fonts = try self.allocator.dupe(*const Font, key_value.fonts);
        errdefer self.allocator.free(fonts);
        const text = try self.allocator.dupe(u8, key_value.text);
        errdefer self.allocator.free(text);
        const features = try self.allocator.dupe(
            unicode.FeatureOverride,
            key_value.features,
        );
        errdefer self.allocator.free(features);
        const normalized_variation_coords = try self.allocator.dupe(
            f32,
            key_value.normalized_variation_coords,
        );
        errdefer self.allocator.free(normalized_variation_coords);
        const context_before = try self.allocator.dupe(
            u8,
            key_value.context_before,
        );
        errdefer self.allocator.free(context_before);
        const context_after = try self.allocator.dupe(
            u8,
            key_value.context_after,
        );
        errdefer self.allocator.free(context_after);
        const glyphs = try self.allocator.dupe(
            glyph_position.GlyphPosition,
            shaped.glyphs,
        );
        errdefer self.allocator.free(glyphs);
        const runs = try self.allocator.dupe(run_types.CascadeRun, shaped.runs);
        errdefer self.allocator.free(runs);
        const variation_coords = try self.allocator.dupe(
            f32,
            shaped.normalized_variation_coords,
        );
        errdefer self.allocator.free(variation_coords);

        var owned_key = key_value;
        owned_key.fonts = fonts;
        owned_key.text = text;
        owned_key.features = features;
        owned_key.normalized_variation_coords = normalized_variation_coords;
        owned_key.context_before = context_before;
        owned_key.context_after = context_after;
        try self.entries.append(self.allocator, .{
            .key = owned_key,
            .glyphs = glyphs,
            .runs = runs,
            .variation_coords = variation_coords,
        });
    }
};

fn cascadeHash(fonts: []const *const Font) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (fonts) |font| {
        const addr = @intFromPtr(font);
        hasher.update(std.mem.asBytes(&addr));
    }
    return hasher.final();
}

fn featureOverridesEqual(
    a: []const unicode.FeatureOverride,
    b: []const unicode.FeatureOverride,
) bool {
    if (a.len != b.len) return false;
    for (a, b) |a_feature, b_feature| {
        if (a_feature.tag != b_feature.tag or
            a_feature.effectiveValue() != b_feature.effectiveValue())
        {
            return false;
        }
    }
    return true;
}

fn variationCoordsEqual(a: []const f32, b: []const f32) bool {
    if (a.len != b.len) return false;
    for (a, b) |a_coord, b_coord| {
        if (@as(u32, @bitCast(a_coord)) != @as(u32, @bitCast(b_coord))) {
            return false;
        }
    }
    return true;
}

test "shaped-run keys verify source bytes after hash filtering" {
    var a = ShapedRunCacheKey.init(&.{}, "abc", 20, .{});
    var b = ShapedRunCacheKey.init(&.{}, "xyz", 20, .{});
    b.text_hash = a.text_hash;

    try std.testing.expect(!a.eql(b));
    a.text = b.text;
    try std.testing.expect(a.eql(b));
}

test "shaped-run keys verify dynamic options after hash filtering" {
    const liga_off = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("liga"), .enabled = false },
    };
    const kern_off = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const a = ShapedRunCacheKey.init(&.{}, "abc", 20, .{
        .features = &liga_off,
        .normalized_variation_coords = &.{0.25},
        .context_before = "a",
    });
    var b = ShapedRunCacheKey.init(&.{}, "abc", 20, .{
        .features = &kern_off,
        .normalized_variation_coords = &.{0.5},
        .context_before = "b",
    });
    b.plan.feature_hash = a.plan.feature_hash;
    b.plan.variation_hash = a.plan.variation_hash;
    b.plan.context_hash = a.plan.context_hash;

    try std.testing.expect(!a.eql(b));
}

test "shaped-run cache owns borrowed key text" {
    var text = [_]u8{ 'a', 'b', 'c' };
    var cache = ShapedRunCache.init(std.testing.allocator);
    defer cache.deinit();

    const key_value = ShapedRunCacheKey.init(&.{}, &text, 20, .{});
    try cache.store(key_value, .{ .glyphs = &.{}, .runs = &.{} });
    text[0] = 'z';

    const original = ShapedRunCacheKey.init(&.{}, "abc", 20, .{});
    const mutated = ShapedRunCacheKey.init(&.{}, &text, 20, .{});
    try std.testing.expect(cache.lookup(original) != null);
    try std.testing.expect(cache.lookup(mutated) == null);
}
