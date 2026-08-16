//! SinglePos runtime execution contracts.

const std = @import("std");
const single = @import("../../../runtime/lookup/single.zig");
const output = @import("../../../runtime/output/root.zig");
const table = @import("../../../table/root.zig");

test "SinglePos subtables are ordered alternatives per glyph" {
    var bytes = [_]u8{0} ** 42;
    // Lookup with two format-1 subtables.
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 26);

    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 8);
    writeU16(&bytes, 14, 0x0001);
    writeI16(&bytes, 16, 20);
    writeCoverage1(&bytes, 18, 5);

    writeU16(&bytes, 26, 1);
    writeU16(&bytes, 28, 8);
    writeU16(&bytes, 30, 0x0001);
    writeI16(&bytes, 32, 50);
    writeCoverage1(&bytes, 34, 5);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(single.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try single.collectLookup(
        view,
        0,
        2,
        &.{5},
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    );
    const result = output.adjustments.find(adjustments.items, 0).?;
    try std.testing.expectEqual(@as(i16, 20), result.x_placement);
}

test "SinglePos format 2 selects indexed values for nested targets" {
    var bytes = [_]u8{0} ** 22;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 0x0004);
    writeU16(&bytes, 6, 2);
    writeI16(&bytes, 8, -10);
    writeI16(&bytes, 10, -30);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 2);
    writeU16(&bytes, 16, 5);
    writeU16(&bytes, 18, 6);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(single.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expect(try single.collectAt(
        view,
        0,
        6,
        3,
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    ));
    try std.testing.expectEqual(
        @as(i16, -30),
        output.adjustments.find(adjustments.items, 3).?.x_advance,
    );
}

test "accelerated SinglePos preserves authored subtable alternatives" {
    var bytes = [_]u8{0} ** 12;
    writeCoverage1(&bytes, 0, 7);
    writeCoverage1(&bytes, 6, 7);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const subtables = [_]single.Parsed{
        .{
            .subtable_offset = 0,
            .pos_format = 1,
            .coverage_offset = 0,
            .value_format = 0x0001,
            .value_size = 2,
            .values_pos = 0,
            .value = .{ .index = 0, .x_placement = 11 },
        },
        .{
            .subtable_offset = 0,
            .pos_format = 1,
            .coverage_offset = 6,
            .value_format = 0x0001,
            .value_size = 2,
            .values_pos = 0,
            .value = .{ .index = 0, .x_placement = 44 },
        },
    };
    var adjustments = std.ArrayList(single.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expect(try single.collectAtAccelerated(
        view,
        &subtables,
        7,
        1,
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    ));
    try std.testing.expectEqual(
        @as(i16, 11),
        output.adjustments.find(adjustments.items, 1).?.x_placement,
    );
}

test "SinglePos rejects unsorted indexed coverage during execution" {
    var bytes = [_]u8{0} ** 20;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 10);
    writeU16(&bytes, 4, 0x0004);
    writeI16(&bytes, 6, 30);
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 2);
    writeU16(&bytes, 14, 10);
    writeU16(&bytes, 16, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(single.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.BadGpos,
        single.collect(
            view,
            0,
            &.{10},
            &adjustments,
            std.testing.allocator,
            0,
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
