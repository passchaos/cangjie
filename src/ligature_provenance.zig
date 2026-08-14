const std = @import("std");

pub const max_components = 64;

pub const StchAction = enum(u2) {
    none,
    fixed,
    repeating,
};

pub const Flags = packed struct(u16) {
    multiplied: bool = false,
    synthetic_base: bool = false,
    base_mark_ligature: bool = false,
    /// The glyph was produced by LigatureSubst even when nested
    /// MultipleSubst pieces collapse to one logical component.
    ligated: bool = false,
    multiple_component: u4 = 0,
    stch_action: StchAction = .none,
    reserved: u6 = 0,
};

/// Per-glyph ligature provenance.
///
/// Ordinary glyphs use the all-default value and do not consume source-pool
/// storage. For a real ligature, `source_start` identifies an immutable slice
/// in `Store.sources`. Handles may be copied freely: MultipleSubst deliberately
/// shares one source slice across every output glyph.
pub const Info = struct {
    /// Offset of this ligature's immutable source slice in `Store.sources`.
    /// Undefined for ordinary glyphs because `source_count == 0` prevents the
    /// offset from being dereferenced.
    source_start: u32 = 0,
    /// Number of logical source components represented by this glyph. OpenType
    /// limits supported ligatures to `max_components`.
    component_count: u8 = 1,
    /// Number of retained source-history positions when it differs from the
    /// logical component list. Zero aliases the ordinary component slice and
    /// avoids storing duplicate views for the overwhelmingly common case.
    /// Non-first MultipleSubst pieces can make this exceed component_count:
    /// they contribute zero logical weight to a later ligature, but Indic
    /// reordering still needs their original sources.
    source_count: u8 = 0,
    /// Compact per-glyph flags and small counters. MultipleSubst uses the
    /// component index for mark handling and Arabic/Syriac `stch` parity.
    flags: Flags = .{},

    pub fn isLigature(self: Info) bool {
        // Preserve compatibility with detached tests/callers that construct
        // component-bearing provenance directly, while allowing a genuine
        // LigatureSubst result to carry one logical component.
        return self.flags.ligated or self.component_count > 1;
    }
};

/// Owns compact per-glyph handles and append-only ligature component sources.
///
/// Source slices are never edited structurally after publication, so copied
/// handles remain valid until `clear` or `deinit`. Source-index renumbering
/// updates pool values in place; scanning the pool rather than every handle is
/// essential because several handles may share one slice.
pub const Store = struct {
    infos: std.ArrayList(Info) = .empty,
    sources: std.ArrayList(usize) = .empty,

    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        self.sources.deinit(allocator);
        self.infos.deinit(allocator);
        self.* = .{};
    }

    pub fn clear(self: *Store) void {
        self.infos.clearRetainingCapacity();
        self.sources.clearRetainingCapacity();
    }

    /// Appends an ordered component-source slice and returns its compact
    /// handle. Callers retain the returned value in one or more glyph slots.
    pub fn addLigature(
        self: *Store,
        allocator: std.mem.Allocator,
        component_sources: []const usize,
    ) std.mem.Allocator.Error!Info {
        return self.addLigatureWithSources(
            allocator,
            component_sources,
            component_sources,
        );
    }

    /// Retain both the complete source history and the logical GPOS components.
    ///
    /// Usually these slices are identical. They differ when a later ligature
    /// consumes a MultipleSubst sequence: every output source remains relevant
    /// to script reordering and public spans, but only the first piece has
    /// ligation weight and receives a distinct MarkLig component.
    pub fn addLigatureWithSources(
        self: *Store,
        allocator: std.mem.Allocator,
        all_sources: []const usize,
        logical_component_sources: []const usize,
    ) std.mem.Allocator.Error!Info {
        std.debug.assert(all_sources.len > 1);
        std.debug.assert(all_sources.len <= max_components);
        std.debug.assert(logical_component_sources.len != 0);
        std.debug.assert(logical_component_sources.len <= max_components);
        std.debug.assert(sourcesAreMonotone(all_sources));
        std.debug.assert(sourcesAreMonotone(logical_component_sources));
        if (self.sources.items.len > std.math.maxInt(u32)) return error.OutOfMemory;

        const shared_sources = std.mem.eql(
            usize,
            all_sources,
            logical_component_sources,
        );
        const source_start: u32 = @intCast(self.sources.items.len);
        try self.sources.appendSlice(allocator, all_sources);
        if (!shared_sources) {
            try self.sources.appendSlice(allocator, logical_component_sources);
        }
        return .{
            .source_start = source_start,
            .component_count = @intCast(logical_component_sources.len),
            .source_count = if (shared_sources) 0 else @intCast(all_sources.len),
            .flags = .{ .ligated = true },
        };
    }

    /// Returns the source slice for a ligature handle. An empty slice denotes
    /// an ordinary glyph; null denotes malformed or stale metadata.
    pub fn componentSources(self: *const Store, info: Info) ?[]const usize {
        const count: usize = if (info.source_count != 0)
            info.source_count
        else if (info.component_count > 1)
            // Compatibility for detached tests and callers that construct a
            // component-bearing Info directly.
            info.component_count
        else
            return &.{};
        if (count > max_components) return null;

        const start: usize = info.source_start;
        if (start > self.sources.items.len or count > self.sources.items.len - start) return null;
        return self.sources.items[start .. start + count];
    }

    /// Return one source position per logical MarkLig component.
    pub fn logicalComponentSources(self: *const Store, info: Info) ?[]const usize {
        if (info.source_count != 0) {
            const start = @as(usize, info.source_start) + @as(usize, info.source_count);
            const count: usize = info.component_count;
            if (start > self.sources.items.len or count > self.sources.items.len - start) return null;
            return self.sources.items[start .. start + count];
        }
        // Compatibility for detached tests and callers using the older layout.
        return self.componentSources(info);
    }

    pub fn infoIsValid(self: *const Store, info: Info) bool {
        const sources = self.componentSources(info) orelse return false;
        const logical_sources = self.logicalComponentSources(info) orelse return false;
        return sourcesAreMonotone(sources) and sourcesAreMonotone(logical_sources);
    }

    pub fn isValid(self: *const Store) bool {
        for (self.infos.items) |info| {
            if (!self.infoIsValid(info)) return false;
        }
        return true;
    }

    /// Renumbers original-source positions after a source scalar insertion or
    /// decomposition. Each pool entry is visited exactly once even when its
    /// handle is shared by a MultipleSubst expansion.
    pub fn shiftSourceIndices(self: *Store, first_shifted: usize, delta: usize) void {
        if (delta == 0) return;
        for (self.sources.items) |*source| {
            if (source.* >= first_shifted) source.* += delta;
        }
    }
};

fn sourcesAreMonotone(sources: []const usize) bool {
    if (sources.len <= 1) return true;
    var previous = sources[0];
    for (sources[1..]) |source| {
        if (source < previous) return false;
        previous = source;
    }
    return true;
}

test "ordinary glyph provenance occupies one compact handle and no source pool" {
    var store = Store{};
    defer store.deinit(std.testing.allocator);

    try store.infos.resize(std.testing.allocator, 1024);
    @memset(store.infos.items, .{});

    try std.testing.expectEqual(@as(usize, 8), @sizeOf(Info));
    try std.testing.expectEqual(@as(usize, 0), store.sources.items.len);
    try std.testing.expect(store.isValid());
}

test "ligature handles share immutable component source slices" {
    var store = Store{};
    defer store.deinit(std.testing.allocator);

    var info = try store.addLigature(std.testing.allocator, &.{ 2, 5, 9 });
    info.flags.multiplied = true;
    try store.infos.appendSlice(std.testing.allocator, &.{ info, info });

    try std.testing.expectEqualSlices(usize, &.{ 2, 5, 9 }, store.componentSources(store.infos.items[0]).?);
    try std.testing.expectEqualSlices(usize, &.{ 2, 5, 9 }, store.logicalComponentSources(store.infos.items[0]).?);
    try std.testing.expectEqual(store.infos.items[0].source_start, store.infos.items[1].source_start);
    try std.testing.expect(store.isValid());
}

test "source renumbering updates a shared slice exactly once" {
    var store = Store{};
    defer store.deinit(std.testing.allocator);

    const info = try store.addLigature(std.testing.allocator, &.{ 1, 3 });
    try store.infos.appendSlice(std.testing.allocator, &.{ info, info });

    store.shiftSourceIndices(2, 2);

    try std.testing.expectEqualSlices(usize, &.{ 1, 5 }, store.componentSources(store.infos.items[0]).?);
    try std.testing.expectEqualSlices(usize, &.{ 1, 5 }, store.componentSources(store.infos.items[1]).?);
    try std.testing.expectEqualSlices(usize, &.{ 1, 5 }, store.logicalComponentSources(store.infos.items[0]).?);
}

test "validation rejects out-of-range and unordered source slices" {
    var store = Store{};
    defer store.deinit(std.testing.allocator);

    try store.sources.appendSlice(std.testing.allocator, &.{ 3, 2 });
    try std.testing.expect(!store.infoIsValid(.{ .source_start = 0, .component_count = 2 }));
    try std.testing.expect(!store.infoIsValid(.{ .source_start = 1, .component_count = 2 }));
}
