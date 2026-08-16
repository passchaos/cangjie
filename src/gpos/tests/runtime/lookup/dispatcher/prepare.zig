//! Top-level Lookup preparation contracts.

const std = @import("std");
const prepare =
    @import("../../../../runtime/lookup/dispatcher/prepare.zig");
const shape_profile = @import("../../../../../shape_profile.zig");

test "lookup preparation customizes only mark filtering state" {
    const sets = [_][]const u16{ &.{5}, &.{7} };
    const original: prepare.Options = .{
        .mark_filtering_sets = &sets,
        .active_mark_filtering_set = 0,
    };

    try std.testing.expect(!prepare.usesMarkFilteringSet(0));
    try std.testing.expect(!prepare.usesMarkFilteringSet(0xff00));
    try std.testing.expect(prepare.usesMarkFilteringSet(0x0010));
    try std.testing.expect(prepare.usesMarkFilteringSet(0xff10));
    try std.testing.expectEqual(
        @as(?prepare.Options, null),
        try prepare.markFilteringOptions(.{
            .lookup_type = 1,
            .lookup_flag = 0xff00,
            .subtable_count = 0,
            .mark_filtering_set = null,
        }, original),
    );

    const customized = (try prepare.markFilteringOptions(.{
        .lookup_type = 1,
        .lookup_flag = 0xff10,
        .subtable_count = 0,
        .mark_filtering_set = 1,
    }, original)).?;
    try std.testing.expectEqual(@as(?u16, 0), original.active_mark_filtering_set);
    try std.testing.expectEqual(
        @as(?u16, 1),
        customized.active_mark_filtering_set,
    );
}

test "lookup preparation rejects an unavailable mark filtering set" {
    const sets = [_][]const u16{&.{5}};
    try std.testing.expectError(
        error.BadGpos,
        prepare.markFilteringOptions(.{
            .lookup_type = 1,
            .lookup_flag = 0x0010,
            .subtable_count = 0,
            .mark_filtering_set = 1,
        }, .{ .mark_filtering_sets = &sets }),
    );
}

test "lookup preparation records the resolved lookup kind" {
    var bytes = [_]u8{0} ** 6;
    writeU16(&bytes, 0, 4);
    var profile: shape_profile.ShapeStageProfile = .{};
    const resolved = try prepare.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, 0, null, .{ .shape_profile = &profile });

    try std.testing.expectEqual(@as(u16, 4), resolved.lookup_type);
    try std.testing.expectEqual(@as(usize, 1), profile.gpos_lookup_count);
    try std.testing.expectEqual(@as(usize, 1), profile.gpos_mark_lookup_count);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
