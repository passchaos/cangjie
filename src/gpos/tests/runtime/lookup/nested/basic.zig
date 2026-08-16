//! Nested PosLookupRecord dispatch contracts.

const std = @import("std");
const nested = @import("../../../../runtime/lookup/nested.zig");

test "nested records map sequence indexes to lookup targets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;
    writeU16(&bytes, 8, 12);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 4);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 8);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 8);
    writeU16(&bytes, 28, 0x0001);
    writeI16(&bytes, 30, 33);
    writeCoverage(&bytes, 32, 5);
    writeU16(&bytes, 40, 0);
    writeU16(&bytes, 42, 0);

    const view = nested.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(nested.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try nested.records(
        view,
        40,
        1,
        &.{0},
        &.{5},
        &adjustments,
        allocator,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "nested records reject a later invalid sequence atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;
    writeU16(&bytes, 8, 12);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 4);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 8);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 8);
    writeU16(&bytes, 28, 0x0001);
    writeI16(&bytes, 30, 33);
    writeCoverage(&bytes, 32, 5);
    writeU16(&bytes, 40, 0);
    writeU16(&bytes, 42, 0);
    writeU16(&bytes, 44, 1);
    writeU16(&bytes, 46, 0);
    const view = nested.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(nested.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(
        error.BadGpos,
        nested.records(
            view,
            40,
            2,
            &.{0},
            &.{5},
            &adjustments,
            allocator,
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
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
