//! GPOS first-glyph group index contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const table = @import("../../table/root.zig");

test "glyph groups preserve candidate ordering and exact lookup" {
    const allocator = std.testing.allocator;
    var pairs = [_]accelerator.glyph_groups.Pair{
        .{ .glyph = 30, .subtable_index = 3 },
        .{ .glyph = 10, .subtable_index = 2 },
        .{ .glyph = 10, .subtable_index = 1 },
        .{ .glyph = 20, .subtable_index = 4 },
    };
    const groups = try accelerator.glyph_groups.buildGroups(&pairs, allocator);
    defer accelerator.glyph_groups.deinitGroups(groups, allocator);
    const slots = try accelerator.glyph_groups.buildSlots(groups, allocator);
    defer allocator.free(slots);

    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 2 },
        accelerator.glyph_groups.find(groups, slots, 10).?,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{4},
        accelerator.glyph_groups.find(groups, slots, 20).?,
    );
    try std.testing.expect(
        accelerator.glyph_groups.find(groups, slots, 21) == null,
    );
}

test "glyph group hash slots preserve hits misses and binary fallback" {
    const allocator = std.testing.allocator;
    const group_count = accelerator.glyph_groups.min_groups_for_hash;
    var groups: [group_count]accelerator.glyph_groups.Group = undefined;
    var group_indices: [group_count][1]u16 = undefined;
    for (&groups, 0..) |*group, index| {
        group_indices[index][0] = @intCast(index);
        group.* = .{
            .glyph = @intCast(13 + index * 19),
            .subtable_indices = &group_indices[index],
        };
    }
    const slots =
        try accelerator.glyph_groups.buildSlots(&groups, allocator);
    defer allocator.free(slots);
    for (groups, 0..) |group, index| {
        const candidates = accelerator.glyph_groups.find(
            &groups,
            slots,
            group.glyph,
        ) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualSlices(
            u16,
            &.{@intCast(index)},
            candidates,
        );
    }
    try std.testing.expect(
        accelerator.glyph_groups.find(&groups, slots, 12) == null,
    );

    const small_groups = groups[0 .. group_count - 1];
    const small_slots =
        try accelerator.glyph_groups.buildSlots(small_groups, allocator);
    defer allocator.free(small_slots);
    try std.testing.expectEqual(@as(usize, 0), small_slots.len);
    const fallback = accelerator.glyph_groups.find(
        small_groups,
        small_slots,
        small_groups[3].glyph,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &group_indices[3], fallback);
}

test "Coverage pairs expand ranges and reject malformed ordering" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 11);
    writeU16(&bytes, 8, 0);
    writeU16(&bytes, 10, 20);
    writeU16(&bytes, 12, 20);
    writeU16(&bytes, 14, 2);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var pairs = std.ArrayList(accelerator.glyph_groups.Pair).empty;
    defer pairs.deinit(std.testing.allocator);

    try accelerator.glyph_groups.appendCoveragePairs(
        view,
        0,
        7,
        &pairs,
        std.testing.allocator,
    );
    try std.testing.expectEqualSlices(
        accelerator.glyph_groups.Pair,
        &.{
            .{ .glyph = 10, .subtable_index = 7 },
            .{ .glyph = 11, .subtable_index = 7 },
            .{ .glyph = 20, .subtable_index = 7 },
        },
        pairs.items,
    );

    writeU16(&bytes, 10, 11);
    try std.testing.expectError(
        error.BadGpos,
        accelerator.glyph_groups.appendCoveragePairs(
            view,
            0,
            8,
            &pairs,
            std.testing.allocator,
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
