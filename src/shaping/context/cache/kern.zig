//! Engine-local proof cache for legacy `kern` lookup handles.
//!
//! `Font` deliberately keeps its low-level shaping entry point mutation-aware,
//! so obtaining a handle rechecks the complete borrowed table checksum. An
//! `Engine` has a stronger documented lifetime contract: cached face bytes must
//! remain alive and immutable until `clearCaches`. Under that contract the
//! first lookup can establish the proof and later logical shaping runs can
//! reuse the table record without hashing a potentially large `kern` table.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const Font = font_mod.Font;
const KernLookupForShaping = font_mod.KernLookupForShaping;
const font_shaping = font_mod.shaping;

pub const KernLookupCache = struct {
    const Entry = struct {
        font_addr: usize,
        lookup: KernLookupForShaping,
    };

    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    last_entry: ?usize = null,
    hits: usize = 0,
    misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) KernLookupCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *KernLookupCache) void {
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *KernLookupCache) void {
        self.entries.clearRetainingCapacity();
        self.last_entry = null;
        self.hits = 0;
        self.misses = 0;
    }

    /// Return a handle whose table checksum was proved on the first lookup.
    /// Callers must first establish that the font has a legacy `kern` table.
    pub fn lookup(
        self: *KernLookupCache,
        font: *const Font,
    ) !KernLookupForShaping {
        const font_addr = @intFromPtr(font);
        if (self.last_entry) |index| {
            const entry = self.entries.items[index];
            if (entry.font_addr == font_addr) {
                self.hits += 1;
                return entry.lookup;
            }
        }
        for (self.entries.items, 0..) |entry, index| {
            if (entry.font_addr != font_addr) continue;
            self.last_entry = index;
            self.hits += 1;
            return entry.lookup;
        }

        self.misses += 1;
        const value = try font_shaping.kernLookupForShaping(font);
        try self.entries.append(self.allocator, .{
            .font_addr = font_addr,
            .lookup = value,
        });
        self.last_entry = self.entries.items.len - 1;
        return value;
    }
};

test "legacy kern lookup cache proves each immutable font once" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();

    var cache = KernLookupCache.init(std.testing.allocator);
    defer cache.deinit();

    const first = try cache.lookup(&font);
    const second = try cache.lookup(&font);
    try std.testing.expectEqual(@as(i16, -100), try first.kerning(1, 1));
    try std.testing.expectEqual(@as(i16, -100), try second.kerning(1, 1));
    try std.testing.expectEqual(@as(usize, 1), cache.misses);
    try std.testing.expectEqual(@as(usize, 1), cache.hits);

    cache.clear();
    try std.testing.expectEqual(@as(usize, 0), cache.entries.items.len);
    try std.testing.expectEqual(@as(?usize, null), cache.last_entry);
    try std.testing.expectEqual(@as(usize, 0), cache.hits);
    try std.testing.expectEqual(@as(usize, 0), cache.misses);
}
