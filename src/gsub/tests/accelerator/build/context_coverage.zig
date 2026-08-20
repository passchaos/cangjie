//! ContextSubst format-3 accelerator builder contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const table = @import("../../../table/root.zig");

test "context coverage builder preserves subtable and first-glyph order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 76;
    writeU16(&bytes, 0, 5);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 40);
    writeContext3(&bytes, 10, 5, 7);
    writeContext3(&bytes, 40, 5, 9);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    var result = try build.context_coverage.build(view, 0, 2, allocator);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), result.subtables.len);
    try std.testing.expectEqual(@as(usize, 4), result.coverage_offsets.len);
    try std.testing.expectEqual(@as(usize, 1), result.groups.len);
    try std.testing.expectEqualSlices(
        u16,
        &.{ 0, 1 },
        result.groups[0].subtable_indices,
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        result.group_slots[5],
    );
}

test "context coverage builder keeps mixed formats on generic path" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 5);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 2);

    var result = try build.context_coverage.build(
        .{ .data = &bytes, .offset = 0, .length = bytes.len },
        0,
        1,
        allocator,
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.subtables.len);
}

test "context direct slots reject sparse glyph spans" {
    const allocator = std.testing.allocator;
    const groups = [_]@import(
        "../../../accelerator/model.zig",
    ).ChainingGroup{.{
        .glyph = build.context_coverage.max_direct_group_slots,
        .subtable_indices = &.{0},
    }};
    const slots = try build.context_coverage.buildDirectSlots(
        &groups,
        allocator,
    );
    defer allocator.free(slots);
    try std.testing.expectEqual(@as(usize, 0), slots.len);
}

fn writeContext3(
    bytes: []u8,
    offset: usize,
    first: u16,
    second: u16,
) void {
    writeU16(bytes, offset, 3);
    writeU16(bytes, offset + 2, 2);
    writeU16(bytes, offset + 4, 0);
    writeU16(bytes, offset + 6, 14);
    writeU16(bytes, offset + 8, 20);
    writeCoverage1(bytes, offset + 14, first);
    writeCoverage1(bytes, offset + 20, second);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
