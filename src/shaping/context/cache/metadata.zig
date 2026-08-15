const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GdefLookupMetadata = @import("../../../font.zig").GdefLookupMetadata;

const GdefMetadataCacheKey = struct {
    font_addr: usize,
};

pub const GdefMetadataCache = struct {
    const Entry = struct {
        key: GdefMetadataCacheKey,
        metadata: GdefLookupMetadata,
    };

    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GdefMetadataCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *GdefMetadataCache) void {
        self.clear();
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *GdefMetadataCache) void {
        for (self.entries.items) |*entry| {
            entry.metadata.deinit(self.allocator);
        }
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn metadata(self: *GdefMetadataCache, font: *const Font) !*const GdefLookupMetadata {
        const key = GdefMetadataCacheKey{ .font_addr = @intFromPtr(font) };
        for (self.entries.items) |*entry| {
            if (entry.key.font_addr == key.font_addr) {
                self.hits += 1;
                return &entry.metadata;
            }
        }

        self.misses += 1;
        var metadata_value = try font.gdefLookupMetadataForShaping(self.allocator);
        errdefer metadata_value.deinit(self.allocator);
        try self.entries.append(self.allocator, .{
            .key = key,
            .metadata = metadata_value,
        });
        return &self.entries.items[self.entries.items.len - 1].metadata;
    }
};

const TableProofCacheKey = struct {
    font_addr: usize,
};

pub const GsubTableProofCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(TableProofCacheKey, void),
    last_font_addr: ?usize = null,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GsubTableProofCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(TableProofCacheKey, void).init(allocator),
        };
    }

    pub fn deinit(self: *GsubTableProofCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GsubTableProofCache) void {
        self.entries.clearRetainingCapacity();
        self.last_font_addr = null;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn prove(self: *GsubTableProofCache, font: *const Font) !void {
        const font_addr = @intFromPtr(font);
        // Consecutive runs overwhelmingly use the same face. Keep the hash
        // set for arbitrary fallback cascades, but let the normal path prove
        // membership with one pointer comparison instead of finalizing a hash
        // for every shaped word.
        if (self.last_font_addr == font_addr) {
            self.hits += 1;
            return;
        }
        const key = TableProofCacheKey{ .font_addr = font_addr };
        if (self.entries.contains(key)) {
            self.last_font_addr = font_addr;
            self.hits += 1;
            return;
        }
        self.misses += 1;
        try font.proveGsubTableForShaping();
        try self.entries.put(key, {});
        self.last_font_addr = font_addr;
    }
};

pub const GposTableProofCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(TableProofCacheKey, void),
    last_font_addr: ?usize = null,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GposTableProofCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(TableProofCacheKey, void).init(allocator),
        };
    }

    pub fn deinit(self: *GposTableProofCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GposTableProofCache) void {
        self.entries.clearRetainingCapacity();
        self.last_font_addr = null;
        self.hits = 0;
        self.misses = 0;
    }

    pub fn prove(self: *GposTableProofCache, font: *const Font) !void {
        const font_addr = @intFromPtr(font);
        if (self.last_font_addr == font_addr) {
            self.hits += 1;
            return;
        }
        const key = TableProofCacheKey{ .font_addr = font_addr };
        if (self.entries.contains(key)) {
            self.last_font_addr = font_addr;
            self.hits += 1;
            return;
        }
        self.misses += 1;
        try font.proveGposTableForShaping();
        try self.entries.put(key, {});
        self.last_font_addr = font_addr;
    }
};

test "table proof caches fast-path consecutive fonts and reset locality" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildScriptFeatureGsubTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);

    var font_a = try Font.parse(std.testing.allocator, bytes);
    defer font_a.deinit();
    var font_b = try Font.parse(std.testing.allocator, bytes);
    defer font_b.deinit();

    var gsub_cache = GsubTableProofCache.init(std.testing.allocator);
    defer gsub_cache.deinit();
    try gsub_cache.prove(&font_a);
    try gsub_cache.prove(&font_a);
    try gsub_cache.prove(&font_b);
    try gsub_cache.prove(&font_a); // Hash-set hit after switching faces.
    try std.testing.expectEqual(@as(usize, 2), gsub_cache.hits);
    try std.testing.expectEqual(@as(usize, 2), gsub_cache.misses);
    try std.testing.expectEqual(@as(?usize, @intFromPtr(&font_a)), gsub_cache.last_font_addr);

    var gpos_cache = GposTableProofCache.init(std.testing.allocator);
    defer gpos_cache.deinit();
    try gpos_cache.prove(&font_a);
    try gpos_cache.prove(&font_a);
    try std.testing.expectEqual(@as(usize, 1), gpos_cache.hits);
    try std.testing.expectEqual(@as(usize, 1), gpos_cache.misses);

    gsub_cache.clear();
    try std.testing.expectEqual(@as(?usize, null), gsub_cache.last_font_addr);
    try std.testing.expectEqual(@as(usize, 0), gsub_cache.hits);
    try std.testing.expectEqual(@as(usize, 0), gsub_cache.misses);
}
