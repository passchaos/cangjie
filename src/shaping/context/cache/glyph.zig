const std = @import("std");

const font_mod = @import("../../../font.zig");
const Font = font_mod.Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;

pub const GlyphMetrics = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

pub const VerticalGlyphMetrics = struct {
    advance_height: u16,
    top_side_bearing: i16,
};

const GlyphMetricsKey = struct {
    font_addr: usize,
    glyph_id: GlyphId,
    variation_hash: u64 = 0,
};

pub const GlyphMetricsCache = struct {
    const direct_capacity = 2048;
    const HorizontalDirectEntry = struct {
        key: GlyphMetricsKey = .{ .font_addr = 0, .glyph_id = 0 },
        metrics: GlyphMetrics = .{ .advance_width = 0, .left_side_bearing = 0 },
        valid: bool = false,
    };
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphMetricsKey, GlyphMetrics),
    vertical_entries: std.AutoHashMap(GlyphMetricsKey, ?VerticalGlyphMetrics),
    direct_entries: [direct_capacity]HorizontalDirectEntry = [_]HorizontalDirectEntry{.{}} ** direct_capacity,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GlyphMetricsCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GlyphMetricsKey, GlyphMetrics).init(allocator),
            .vertical_entries = std.AutoHashMap(GlyphMetricsKey, ?VerticalGlyphMetrics).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphMetricsCache) void {
        self.vertical_entries.deinit();
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GlyphMetricsCache) void {
        self.entries.clearRetainingCapacity();
        self.vertical_entries.clearRetainingCapacity();
        self.direct_entries = [_]HorizontalDirectEntry{.{}} ** direct_capacity;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn horizontalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !GlyphMetrics {
        return try self.horizontalMetricsAtCoords(font, glyph_id, &.{});
    }

    pub fn horizontalMetricsAtCoords(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId, normalized_variation_coords: []const f32) !GlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id, normalized_variation_coords);
        const direct = &self.direct_entries[directMetricsIndex(key)];
        if (direct.valid and glyphMetricsKeysEqual(direct.key, key)) {
            self.hits += 1;
            return direct.metrics;
        }
        if (self.entries.get(key)) |metrics| {
            direct.* = .{ .key = key, .metrics = metrics, .valid = true };
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        // Faces reachable here were parsed before entering the shaping
        // pipeline and must remain immutable while cache keys borrow them.
        // Reuse that proof rather than checksumming hhea/hmtx for every cache
        // miss; public font metric APIs retain mutation-aware validation.
        const raw = try font_mod.shaping.horizontalMetricsAtCoords(
            font,
            glyph_id,
            normalized_variation_coords,
        );
        const metrics = GlyphMetrics{
            .advance_width = raw.advance_width,
            .left_side_bearing = raw.left_side_bearing,
        };
        try self.entries.put(key, metrics);
        direct.* = .{ .key = key, .metrics = metrics, .valid = true };
        return metrics;
    }

    pub fn verticalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !?VerticalGlyphMetrics {
        return try self.verticalMetricsAtCoords(font, glyph_id, &.{});
    }

    pub fn verticalMetricsAtCoords(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId, normalized_variation_coords: []const f32) !?VerticalGlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id, normalized_variation_coords);
        if (self.vertical_entries.get(key)) |metrics| {
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        const raw = if (normalized_variation_coords.len == 0)
            try font.verticalMetrics(glyph_id)
        else
            try font.verticalMetricsAtCoords(glyph_id, normalized_variation_coords);
        const metrics: ?VerticalGlyphMetrics = if (raw) |value| .{
            .advance_height = value.advance_height,
            .top_side_bearing = value.top_side_bearing,
        } else null;
        try self.vertical_entries.put(key, metrics);
        return metrics;
    }
};

fn directMetricsIndex(key: GlyphMetricsKey) usize {
    // Glyph id is the strongest locality signal: shaping repeatedly requests
    // the same small alphabet from one face and variation instance. Mix the
    // complete identity so fallback fonts and variable instances can coexist;
    // exact key comparison still resolves all collisions before returning.
    var mixed: u64 = @intCast(key.font_addr);
    mixed = (mixed >> 4) ^ key.variation_hash;
    mixed ^= @as(u64, key.glyph_id) *% 0x9e37_79b9_7f4a_7c15;
    mixed ^= mixed >> 32;
    return @intCast(mixed & (GlyphMetricsCache.direct_capacity - 1));
}

fn glyphMetricsKeysEqual(a: GlyphMetricsKey, b: GlyphMetricsKey) bool {
    return a.font_addr == b.font_addr and
        a.glyph_id == b.glyph_id and
        a.variation_hash == b.variation_hash;
}

test "glyph metrics direct cache is exact and cleared with the backing map" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var cache = GlyphMetricsCache.init(std.testing.allocator);
    defer cache.deinit();

    const expected = try cache.horizontalMetrics(&font, 1);
    const key = glyphMetricsKey(&font, 1, &.{});
    const slot = directMetricsIndex(key);
    try std.testing.expect(cache.direct_entries[slot].valid);
    try std.testing.expect(glyphMetricsKeysEqual(key, cache.direct_entries[slot].key));

    // Remove the authoritative map entry so this repeat can succeed only via
    // the exact direct slot, not by falling through to the old cache path.
    try std.testing.expect(cache.entries.remove(key));
    const from_direct = try cache.horizontalMetrics(&font, 1);
    try std.testing.expectEqual(expected, from_direct);
    try std.testing.expectEqual(@as(usize, 1), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    // Glyph ids separated by the power-of-two slot count collide. A foreign
    // complete key must miss the slot and fall back to the authoritative map.
    try cache.entries.put(key, expected);
    cache.direct_entries[slot].key.glyph_id +%= GlyphMetricsCache.direct_capacity;
    const after_collision = try cache.horizontalMetrics(&font, 1);
    try std.testing.expectEqual(expected, after_collision);
    try std.testing.expect(glyphMetricsKeysEqual(key, cache.direct_entries[slot].key));
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    cache.clear();
    try std.testing.expect(!cache.direct_entries[slot].valid);
    try std.testing.expectEqual(@as(usize, 0), cache.hits);
    try std.testing.expectEqual(@as(usize, 0), cache.misses);
}

test "shaping metrics reuse the parsed immutable face proof" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    const tables = try font.tables(std.testing.allocator);
    defer std.testing.allocator.free(tables);
    var hhea_tail: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hhea")) {
            hhea_tail = table.offset + table.length - 1;
        }
    }

    // Corrupt only reserved hhea padding: the metric payload stays unchanged,
    // but mutation-aware public access must observe the checksum failure.
    bytes[hhea_tail orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.InvalidMetrics, font.horizontalMetrics(1));

    var cache = GlyphMetricsCache.init(std.testing.allocator);
    defer cache.deinit();
    const metrics = try cache.horizontalMetrics(&font, 1);
    try std.testing.expectEqual(@as(u16, 800), metrics.advance_width);
    try std.testing.expectEqual(@as(i16, 0), metrics.left_side_bearing);
}

const GlyphIndexKey = struct {
    font_addr: usize,
    codepoint: u21,
};

pub const GlyphIndexCache = struct {
    const ascii_capacity = 128;
    const direct_capacity = 2048;
    const AsciiEntry = struct {
        font_addr: usize = 0,
        glyph_id: GlyphId = 0,
        valid: bool = false,
    };
    const DirectEntry = struct {
        font_addr: usize = 0,
        codepoint: u21 = 0,
        glyph_id: GlyphId = 0,
        valid: bool = false,
    };

    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphIndexKey, GlyphId),
    ascii_entries: [ascii_capacity]AsciiEntry = [_]AsciiEntry{.{}} ** ascii_capacity,
    direct_entries: [direct_capacity]DirectEntry = [_]DirectEntry{.{}} ** direct_capacity,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GlyphIndexCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GlyphIndexKey, GlyphId).init(allocator),
        };
    }

    pub fn deinit(self: *GlyphIndexCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GlyphIndexCache) void {
        self.entries.clearRetainingCapacity();
        self.ascii_entries = [_]AsciiEntry{.{}} ** ascii_capacity;
        self.direct_entries = [_]DirectEntry{.{}} ** direct_capacity;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn glyphIndex(self: *GlyphIndexCache, font: *const Font, codepoint: u21) !GlyphId {
        const font_addr = @intFromPtr(font);
        if (codepoint < ascii_capacity) {
            const ascii = &self.ascii_entries[@intCast(codepoint)];
            if (ascii.valid and ascii.font_addr == font_addr) {
                self.hits += 1;
                return ascii.glyph_id;
            }
        }

        const key = GlyphIndexKey{ .font_addr = font_addr, .codepoint = codepoint };
        const direct = &self.direct_entries[directGlyphIndex(key)];
        if (direct.valid and direct.font_addr == font_addr and direct.codepoint == codepoint) {
            self.hits += 1;
            return direct.glyph_id;
        }
        if (self.entries.get(key)) |glyph_id| {
            direct.* = .{
                .font_addr = font_addr,
                .codepoint = codepoint,
                .glyph_id = glyph_id,
                .valid = true,
            };
            self.hits += 1;
            if (codepoint < ascii_capacity) {
                self.ascii_entries[@intCast(codepoint)] = .{
                    .font_addr = font_addr,
                    .glyph_id = glyph_id,
                    .valid = true,
                };
            }
            return glyph_id;
        }
        self.misses += 1;
        const glyph_id = try font.glyphIndex(codepoint);
        try self.entries.put(key, glyph_id);
        direct.* = .{
            .font_addr = font_addr,
            .codepoint = codepoint,
            .glyph_id = glyph_id,
            .valid = true,
        };
        if (codepoint < ascii_capacity) {
            self.ascii_entries[@intCast(codepoint)] = .{
                .font_addr = font_addr,
                .glyph_id = glyph_id,
                .valid = true,
            };
        }
        return glyph_id;
    }
};

fn directGlyphIndex(key: GlyphIndexKey) usize {
    // Non-ASCII shaping repeatedly maps a small script alphabet. Mix the full
    // font/codepoint identity with integer operations only; exact key checks
    // make direct-map collisions fall through to the authoritative hash map.
    var mixed: u64 = @intCast(key.font_addr >> 4);
    mixed ^= @as(u64, key.codepoint) *% 0x9e37_79b9_7f4a_7c15;
    mixed ^= mixed >> 32;
    return @intCast(mixed & (GlyphIndexCache.direct_capacity - 1));
}

test "glyph index direct cache is exact for non-ASCII mappings" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildSingleCodepointTtf(std.testing.allocator, 0x0915);
    defer std.testing.allocator.free(bytes);

    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var cache = GlyphIndexCache.init(std.testing.allocator);
    defer cache.deinit();

    const codepoint: u21 = 0x0915;
    const expected = try cache.glyphIndex(&font, codepoint);
    const key = GlyphIndexKey{
        .font_addr = @intFromPtr(&font),
        .codepoint = codepoint,
    };
    const slot = directGlyphIndex(key);
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(GlyphIndexCache.DirectEntry));
    try std.testing.expect(cache.direct_entries[slot].valid);
    try std.testing.expectEqual(key.font_addr, cache.direct_entries[slot].font_addr);
    try std.testing.expectEqual(key.codepoint, cache.direct_entries[slot].codepoint);

    // Remove the backing entry: an exact repeat can now succeed only from the
    // direct slot, not through AutoHashMap's Wyhash path.
    try std.testing.expect(cache.entries.remove(key));
    try std.testing.expectEqual(expected, try cache.glyphIndex(&font, codepoint));
    try std.testing.expectEqual(@as(usize, 1), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    // Codepoints separated by the power-of-two slot count collide in the low
    // index bits. A mismatching complete key must fall through and refill from
    // the authoritative map rather than returning the foreign glyph.
    try cache.entries.put(key, expected);
    cache.direct_entries[slot].codepoint +%= GlyphIndexCache.direct_capacity;
    cache.direct_entries[slot].glyph_id = 0;
    try std.testing.expectEqual(expected, try cache.glyphIndex(&font, codepoint));
    try std.testing.expectEqual(key.font_addr, cache.direct_entries[slot].font_addr);
    try std.testing.expectEqual(key.codepoint, cache.direct_entries[slot].codepoint);
    try std.testing.expectEqual(@as(usize, 2), cache.hits);
    try std.testing.expectEqual(@as(usize, 1), cache.misses);

    cache.clear();
    try std.testing.expect(!cache.direct_entries[slot].valid);
}

fn glyphMetricsKey(font: *const Font, glyph_id: GlyphId, normalized_variation_coords: []const f32) GlyphMetricsKey {
    return .{
        .font_addr = @intFromPtr(font),
        .glyph_id = glyph_id,
        .variation_hash = variationCoordsHash(normalized_variation_coords),
    };
}

fn variationCoordsHash(coords: []const f32) u64 {
    if (coords.len == 0) return 0;
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&coords.len));
    for (coords) |coord| {
        const bits: u32 = @bitCast(coord);
        hasher.update(std.mem.asBytes(&bits));
    }
    return hasher.final();
}
