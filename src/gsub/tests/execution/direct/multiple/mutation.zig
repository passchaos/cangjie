//! MultipleSubst cardinality, sidecar, budget, and failure atomicity.

const std = @import("std");
const multiple = @import("../../../../execution/direct/multiple/root.zig");
const ligature_provenance = @import("../../../../../ligature_provenance.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

test "multiple expansion keeps sidecars and provenance aligned" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeMultiple(&bytes, 0, 10, &.{ 20, 21 });
    var fixture = try Fixture.init(allocator, &.{10});
    defer fixture.deinit(allocator);
    fixture.sources.items[0] = 3;
    fixture.clusters.items[0] = 7;
    const ligature = try fixture.provenance.addLigature(
        allocator,
        &.{ 3, 4 },
    );
    fixture.provenance.infos.items[0] = ligature;

    const change = (try multiple.at(
        view(&bytes),
        0,
        &fixture.glyphs,
        0,
        allocator,
        0,
        fixture.options(),
    )).?;
    try std.testing.expectEqual(@as(usize, 1), change.removed_len);
    try std.testing.expectEqual(@as(usize, 2), change.inserted_len);
    try std.testing.expectEqualSlices(u16, &.{ 20, 21 }, fixture.glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 3, 3 }, fixture.sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 7, 7 }, fixture.clusters.items);
    try std.testing.expectEqualSlices(bool, &.{ true, true }, fixture.stage.items);
    for (fixture.provenance.infos.items, 0..) |info, index| {
        try std.testing.expect(info.flags.multiplied);
        try std.testing.expectEqual(@as(u4, @intCast(index)), info.flags.multiple_component);
        try std.testing.expectEqual(ligature.source_start, info.source_start);
    }
}

test "multiple subtable deletes consecutive index-zero matches" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 20;
    writeMultiple(&bytes, 0, 10, &.{});
    var fixture = try Fixture.init(allocator, &.{ 10, 10, 11 });
    defer fixture.deinit(allocator);
    var operations_left: usize = 2;
    var run = fixture.options();
    run.operations_left = &operations_left;
    run.max_glyph_count = 8;

    try multiple.subtable(
        view(&bytes),
        0,
        &fixture.glyphs,
        allocator,
        0,
        run,
    );
    try std.testing.expectEqualSlices(u16, &.{11}, fixture.glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{2}, fixture.sources.items);
    try std.testing.expectEqualSlices(usize, &.{2}, fixture.clusters.items);
    try std.testing.expectEqualSlices(bool, &.{false}, fixture.stage.items);
    try std.testing.expectEqual(@as(usize, 0), operations_left);
}

test "multiple budget failure leaves glyphs and sidecars unchanged" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeMultiple(&bytes, 0, 10, &.{ 20, 21 });
    var fixture = try Fixture.init(allocator, &.{10});
    defer fixture.deinit(allocator);
    var operations_left: usize = 0;
    var run = fixture.options();
    run.operations_left = &operations_left;
    run.max_glyph_count = 8;

    try std.testing.expectError(
        error.ShapingLimitExceeded,
        multiple.subtable(
            view(&bytes),
            0,
            &fixture.glyphs,
            allocator,
            0,
            run,
        ),
    );
    try fixture.expectOriginal(&.{10});
    try std.testing.expectEqual(@as(usize, 0), operations_left);
}

test "multiple allocation failures preserve contents and operation budget" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;
    writeMultiple(&bytes, 0, 10, &.{ 20, 21, 22 });

    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var fixture = try Fixture.init(allocator, &.{10});
        defer fixture.deinit(allocator);
        fixture.shrink(allocator);
        var operations_left: usize = 1;
        var run = fixture.options();
        run.operations_left = &operations_left;
        run.max_glyph_count = 8;
        var failing = std.testing.FailingAllocator.init(
            allocator,
            .{ .fail_index = fail_index },
        );

        const result = multiple.subtable(
            view(&bytes),
            0,
            &fixture.glyphs,
            failing.allocator(),
            0,
            run,
        );
        if (result) {
            if (failing.has_induced_failure) {
                return error.SwallowedOutOfMemoryError;
            }
            try std.testing.expectEqualSlices(
                u16,
                &.{ 20, 21, 22 },
                fixture.glyphs.items,
            );
            try std.testing.expectEqual(@as(usize, 0), operations_left);
            break;
        } else |err| switch (err) {
            error.OutOfMemory => {
                try fixture.expectOriginal(&.{10});
                try std.testing.expectEqual(@as(usize, 1), operations_left);
            },
            else => return err,
        }
    }
}

const Fixture = struct {
    glyphs: std.ArrayList(u16) = .empty,
    sources: std.ArrayList(usize) = .empty,
    clusters: std.ArrayList(usize) = .empty,
    substituted: std.ArrayList(bool) = .empty,
    stage: std.ArrayList(bool) = .empty,
    provenance: ligature_provenance.Store = .{},

    fn init(
        allocator: std.mem.Allocator,
        glyphs: []const u16,
    ) !Fixture {
        var result = Fixture{};
        errdefer result.deinit(allocator);
        try result.glyphs.appendSlice(allocator, glyphs);
        for (0..glyphs.len) |index| {
            try result.sources.append(allocator, index);
            try result.clusters.append(allocator, index);
            try result.substituted.append(allocator, false);
            try result.stage.append(allocator, false);
            try result.provenance.infos.append(allocator, .{});
        }
        return result;
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.provenance.deinit(allocator);
        self.stage.deinit(allocator);
        self.substituted.deinit(allocator);
        self.clusters.deinit(allocator);
        self.sources.deinit(allocator);
        self.glyphs.deinit(allocator);
        self.* = .{};
    }

    fn options(self: *Fixture) Options {
        return .{
            .glyph_source_indices = &self.sources,
            .glyph_cluster_indices = &self.clusters,
            .glyph_substituted = &self.substituted,
            .glyph_stage_substituted = &self.stage,
            .ligature_components = &self.provenance,
        };
    }

    fn shrink(self: *Fixture, allocator: std.mem.Allocator) void {
        self.glyphs.shrinkAndFree(allocator, self.glyphs.items.len);
        self.sources.shrinkAndFree(allocator, self.sources.items.len);
        self.clusters.shrinkAndFree(allocator, self.clusters.items.len);
        self.substituted.shrinkAndFree(
            allocator,
            self.substituted.items.len,
        );
        self.stage.shrinkAndFree(allocator, self.stage.items.len);
        self.provenance.infos.shrinkAndFree(
            allocator,
            self.provenance.infos.items.len,
        );
    }

    fn expectOriginal(
        self: *Fixture,
        glyphs: []const u16,
    ) !void {
        try std.testing.expectEqualSlices(u16, glyphs, self.glyphs.items);
        try std.testing.expectEqual(glyphs.len, self.sources.items.len);
        try std.testing.expectEqual(glyphs.len, self.clusters.items.len);
        try std.testing.expectEqual(glyphs.len, self.substituted.items.len);
        try std.testing.expectEqual(glyphs.len, self.stage.items.len);
        try std.testing.expectEqual(glyphs.len, self.provenance.infos.items.len);
        for (glyphs, 0..) |_, index| {
            try std.testing.expectEqual(index, self.sources.items[index]);
            try std.testing.expectEqual(index, self.clusters.items[index]);
            try std.testing.expect(!self.substituted.items[index]);
            try std.testing.expect(!self.stage.items[index]);
            try std.testing.expect(
                !self.provenance.infos.items[index].flags.multiplied,
            );
        }
    }
};

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeMultiple(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    replacements: []const u16,
) void {
    const coverage_offset: u16 = @intCast(10 + replacements.len * 2);
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, coverage_offset);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, offset + 10 + index * 2, replacement);
    }
    writeCoverage1(bytes, offset + coverage_offset, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
