//! Chaining group and first-pair index contracts.

const std = @import("std");
const GlyphDigest = @import("../../../../glyph_digest.zig").GlyphDigest;
const chaining = @import("../../../accelerator/index/chaining.zig");
const model = @import("../../../accelerator/model.zig");

test "chaining group slots preserve hits misses and sorted fallback" {
    const allocator = std.testing.allocator;
    var groups: [chaining.min_groups_for_hash]model.ChainingGroup = undefined;
    var indices: [chaining.min_groups_for_hash][1]u16 = undefined;
    for (&groups, 0..) |*group, index| {
        indices[index][0] = @intCast(index);
        group.* = .{
            .glyph = @intCast(10 + index * 17),
            .subtable_indices = &indices[index],
        };
    }
    const slots = try chaining.buildSlots(&groups, allocator);
    defer allocator.free(slots);
    for (groups, 0..) |group, index| {
        try std.testing.expectEqualSlices(
            u16,
            &.{@intCast(index)},
            chaining.findIndices(&groups, slots, group.glyph).?,
        );
    }
    try std.testing.expect(chaining.findIndices(&groups, slots, 9) == null);
    try std.testing.expectEqualSlices(
        u16,
        &.{0},
        chaining.findIndices(groups[0..1], &.{}, groups[0].glyph).?,
    );
}

test "chaining pair builder groups repeated pairs in authored index order" {
    const allocator = std.testing.allocator;
    var pairs = [_]model.ChainingPairEntry{
        .{ .first = 30, .second = 7, .subtable_index = 4 },
        .{ .first = 10, .second = 2, .subtable_index = 1 },
        .{ .first = 10, .second = 2, .subtable_index = 3 },
        .{ .first = 10, .second = 5, .subtable_index = 2 },
        .{ .first = 42, .second = 8, .subtable_index = 9 },
        .{ .first = 11, .second = 1, .subtable_index = 6 },
        .{ .first = 12, .second = 1, .subtable_index = 7 },
        .{ .first = 13, .second = 1, .subtable_index = 8 },
    };
    const groups = try chaining.buildPairGroups(&pairs, allocator);
    defer {
        for (groups) |group| allocator.free(group.subtable_indices);
        allocator.free(groups);
    }
    const slots = try chaining.buildPairSlots(groups, allocator);
    defer allocator.free(slots);

    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 3 },
        chaining.findPairIndices(groups, slots, 10, 2).?,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{4},
        chaining.findPairIndices(groups, slots, 30, 7).?,
    );
    try std.testing.expect(
        chaining.findPairIndices(groups, slots, 10, 9) == null,
    );
}

test "chaining groups derive second-input digest metadata" {
    var second_digest = GlyphDigest.empty();
    second_digest.add(22);
    var groups = [_]model.ChainingGroup{
        .{ .glyph = 10, .subtable_indices = &.{ 0, 1 } },
    };
    const subtables = [_]model.ChainingCoverageSubtable{
        .{ .input_count = 1 },
        .{ .input_count = 2, .second_input_digest = second_digest },
    };

    chaining.fillSecondInputMetadata(&groups, &subtables);
    try std.testing.expect(groups[0].has_no_second_input);
    try std.testing.expect(groups[0].second_input_digest.mayHave(22));
}
