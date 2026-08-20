//! GSUB metadata mutation and allocation-failure atomicity contracts.

const std = @import("std");
const filtering = @import("../../runtime/filtering.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const mutation = @import("../../runtime/mutation.zig");

test "mark substituted updates epochs and both substitution sidecars" {
    var cumulative = std.ArrayList(bool).empty;
    defer cumulative.deinit(std.testing.allocator);
    try cumulative.appendSlice(std.testing.allocator, &.{ false, false });
    var stage = std.ArrayList(bool).empty;
    defer stage.deinit(std.testing.allocator);
    try stage.appendSlice(std.testing.allocator, &.{ false, false });
    var generation: usize = 7;

    mutation.markSubstituted(.{
        .glyph_substituted = &cumulative,
        .glyph_stage_substituted = &stage,
        .glyph_mutation_generation = &generation,
    }, 1);

    try std.testing.expectEqual(@as(usize, 8), generation);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, cumulative.items);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, stage.items);
}

test "replacement keeps every metadata sidecar aligned and preserves provenance" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator);
    defer fixture.deinit(allocator);

    const prepared = try mutation.prepareReplacement(
        allocator,
        &fixture.glyphs,
        fixture.options(),
        1,
        1,
        3,
        4,
    );
    prepared.commit(&fixture.glyphs, &.{ 7, 8, 9 });

    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 7, 8, 9, 3 },
        fixture.glyphs.items,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 4, 4, 4, 2 },
        fixture.sources.items,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 10, 20, 20, 20, 30 },
        fixture.clusters.items,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, true, true, true, false },
        fixture.substituted.items,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, true, true, true, false },
        fixture.stage.items,
    );
    try std.testing.expectEqual(@as(usize, 5), fixture.store.infos.items.len);
    for (fixture.store.infos.items[1..4], 0..) |info, index| {
        try std.testing.expect(info.flags.multiplied);
        try std.testing.expectEqual(
            @as(u4, @intCast(index)),
            info.flags.multiple_component,
        );
        try std.testing.expect(info.flags.synthetic_base);
    }
    try std.testing.expectEqual(
        @as(usize, 4),
        filtering.sourceForGlyph(fixture.options(), 2),
    );
}

test "prepared deletion shrinks glyphs and every sidecar in one commit" {
    const allocator = std.testing.allocator;
    var fixture = try Fixture.init(allocator);
    defer fixture.deinit(allocator);
    var generation: usize = 2;
    var run = fixture.options();
    run.glyph_mutation_generation = &generation;

    const prepared = try mutation.prepareReplacement(
        allocator,
        &fixture.glyphs,
        run,
        1,
        1,
        0,
        0,
    );
    prepared.commit(&fixture.glyphs, &.{});

    try std.testing.expectEqual(@as(usize, 3), generation);
    try std.testing.expectEqualSlices(u16, &.{ 1, 3 }, fixture.glyphs.items);
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 2 },
        fixture.sources.items,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 10, 30 },
        fixture.clusters.items,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        fixture.substituted.items,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        fixture.stage.items,
    );
    try std.testing.expectEqual(@as(usize, 2), fixture.store.infos.items.len);
}

test "replacement preflights every sidecar before changing cardinality" {
    const allocator = std.testing.allocator;
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var fixture = try Fixture.init(allocator);
        defer fixture.deinit(allocator);

        // Force every sidecar to its exact current capacity so growth reaches
        // a distinct allocator preflight point.
        fixture.glyphs.shrinkAndFree(allocator, fixture.glyphs.items.len);
        fixture.sources.shrinkAndFree(allocator, fixture.sources.items.len);
        fixture.clusters.shrinkAndFree(allocator, fixture.clusters.items.len);
        fixture.substituted.shrinkAndFree(
            allocator,
            fixture.substituted.items.len,
        );
        fixture.stage.shrinkAndFree(allocator, fixture.stage.items.len);
        fixture.store.infos.shrinkAndFree(
            allocator,
            fixture.store.infos.items.len,
        );

        var failing = std.testing.FailingAllocator.init(
            allocator,
            .{ .fail_index = fail_index },
        );
        const result = mutation.prepareReplacement(
            failing.allocator(),
            &fixture.glyphs,
            fixture.options(),
            1,
            1,
            3,
            4,
        );
        if (result) |prepared| {
            if (failing.has_induced_failure) {
                return error.SwallowedOutOfMemoryError;
            }
            prepared.commit(&fixture.glyphs, &.{ 7, 8, 9 });
            break;
        } else |err| switch (err) {
            error.OutOfMemory => {
                try fixture.expectOriginal();
            },
        }
    }
}

const Fixture = struct {
    glyphs: std.ArrayList(u16) = .empty,
    sources: std.ArrayList(usize) = .empty,
    clusters: std.ArrayList(usize) = .empty,
    substituted: std.ArrayList(bool) = .empty,
    stage: std.ArrayList(bool) = .empty,
    store: ligature_provenance.Store = .{},

    fn init(allocator: std.mem.Allocator) !Fixture {
        var result = Fixture{};
        errdefer result.deinit(allocator);
        try result.glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
        try result.sources.appendSlice(allocator, &.{ 0, 1, 2 });
        try result.clusters.appendSlice(allocator, &.{ 10, 20, 30 });
        try result.substituted.appendSlice(
            allocator,
            &.{ false, false, false },
        );
        try result.stage.appendSlice(
            allocator,
            &.{ false, false, false },
        );
        try result.store.infos.appendSlice(allocator, &.{
            .{},
            .{ .flags = .{ .synthetic_base = true } },
            .{},
        });
        return result;
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.store.deinit(allocator);
        self.stage.deinit(allocator);
        self.substituted.deinit(allocator);
        self.clusters.deinit(allocator);
        self.sources.deinit(allocator);
        self.glyphs.deinit(allocator);
        self.* = .{};
    }

    fn options(self: *Fixture) mutation.Options {
        return .{
            .glyph_source_indices = &self.sources,
            .glyph_cluster_indices = &self.clusters,
            .glyph_substituted = &self.substituted,
            .glyph_stage_substituted = &self.stage,
            .ligature_components = &self.store,
        };
    }

    fn expectOriginal(self: *Fixture) !void {
        try std.testing.expectEqualSlices(
            u16,
            &.{ 1, 2, 3 },
            self.glyphs.items,
        );
        try std.testing.expectEqualSlices(
            usize,
            &.{ 0, 1, 2 },
            self.sources.items,
        );
        try std.testing.expectEqualSlices(
            usize,
            &.{ 10, 20, 30 },
            self.clusters.items,
        );
        try std.testing.expectEqualSlices(
            bool,
            &.{ false, false, false },
            self.substituted.items,
        );
        try std.testing.expectEqualSlices(
            bool,
            &.{ false, false, false },
            self.stage.items,
        );
        try std.testing.expectEqual(@as(usize, 3), self.store.infos.items.len);
        try std.testing.expect(
            self.store.infos.items[1].flags.synthetic_base,
        );
        try std.testing.expect(
            !self.store.infos.items[1].flags.multiplied,
        );
    }
};
