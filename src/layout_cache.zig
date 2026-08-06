const std = @import("std");

const Font = @import("font.zig").Font;
const GdefLookupMetadata = @import("font.zig").GdefLookupMetadata;
const GlyphId = @import("glyph.zig").GlyphId;

pub const GlyphMetrics = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

pub const VerticalGlyphMetrics = struct {
    advance_height: u16,
    top_side_bearing: i16,
};

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

const GposTableProofCacheKey = struct {
    font_addr: usize,
};

pub const GposTableProofCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GposTableProofCacheKey, void),
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) GposTableProofCache {
        return .{
            .allocator = allocator,
            .entries = std.AutoHashMap(GposTableProofCacheKey, void).init(allocator),
        };
    }

    pub fn deinit(self: *GposTableProofCache) void {
        self.entries.deinit();
        self.* = undefined;
    }

    pub fn clear(self: *GposTableProofCache) void {
        self.entries.clearRetainingCapacity();
        self.hits = 0;
        self.misses = 0;
    }

    pub fn prove(self: *GposTableProofCache, font: *const Font) !void {
        const key = GposTableProofCacheKey{ .font_addr = @intFromPtr(font) };
        if (self.entries.contains(key)) {
            self.hits += 1;
            return;
        }
        self.misses += 1;
        try font.proveGposTableForShaping();
        try self.entries.put(key, {});
    }
};

const GlyphMetricsKey = struct {
    font_addr: usize,
    glyph_id: GlyphId,
};

pub const GlyphMetricsCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphMetricsKey, GlyphMetrics),
    vertical_entries: std.AutoHashMap(GlyphMetricsKey, ?VerticalGlyphMetrics),
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
        self.hits = 0;
        self.misses = 0;
    }

    pub fn horizontalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !GlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id);
        if (self.entries.get(key)) |metrics| {
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        const raw = try font.horizontalMetrics(glyph_id);
        const metrics = GlyphMetrics{
            .advance_width = raw.advance_width,
            .left_side_bearing = raw.left_side_bearing,
        };
        try self.entries.put(key, metrics);
        return metrics;
    }

    pub fn verticalMetrics(self: *GlyphMetricsCache, font: *const Font, glyph_id: GlyphId) !?VerticalGlyphMetrics {
        const key = glyphMetricsKey(font, glyph_id);
        if (self.vertical_entries.get(key)) |metrics| {
            self.hits += 1;
            return metrics;
        }
        self.misses += 1;
        const raw = try font.verticalMetrics(glyph_id);
        const metrics: ?VerticalGlyphMetrics = if (raw) |value| .{
            .advance_height = value.advance_height,
            .top_side_bearing = value.top_side_bearing,
        } else null;
        try self.vertical_entries.put(key, metrics);
        return metrics;
    }
};

const GlyphIndexKey = struct {
    font_addr: usize,
    codepoint: u21,
};

pub const GlyphIndexCache = struct {
    const ascii_capacity = 128;
    const AsciiEntry = struct {
        font_addr: usize = 0,
        glyph_id: GlyphId = 0,
        valid: bool = false,
    };

    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(GlyphIndexKey, GlyphId),
    ascii_entries: [ascii_capacity]AsciiEntry = [_]AsciiEntry{.{}} ** ascii_capacity,
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
        if (self.entries.get(key)) |glyph_id| {
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

fn glyphMetricsKey(font: *const Font, glyph_id: GlyphId) GlyphMetricsKey {
    return .{
        .font_addr = @intFromPtr(font),
        .glyph_id = glyph_id,
    };
}
