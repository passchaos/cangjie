//! Top-level Lookup execution and atomicity contracts.

const std = @import("std");
const dispatcher =
    @import("../../../../runtime/lookup/dispatcher/root.zig");

test "dispatcher preflights every direct subtable before output" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 24);
    writeSingle(&bytes, 10, 5, 20);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 8);
    writeU16(&bytes, 28, 0x0001);
    writeI16(&bytes, 30, 50);
    // The second subtable's Coverage starts exactly at the declared table end.

    var adjustments = std.ArrayList(dispatcher.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(
        error.BadGpos,
        dispatcher.collect(.{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
        }, 0, &.{5}, &adjustments, allocator, .{}),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "dispatcher applies the Lookup header mark filtering set" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0x0010);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 1);
    writeSingle(&bytes, 10, 7, 33);

    var classes = [_]u16{0} ** 8;
    classes[7] = 3;
    const sets = [_][]const u16{ &.{5}, &.{7} };
    var adjustments = std.ArrayList(dispatcher.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try dispatcher.collect(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, 0, &.{7}, &adjustments, allocator, .{
        .glyph_classes = &classes,
        .mark_filtering_sets = &sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

fn writeSingle(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    placement: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 8);
    writeU16(bytes, offset + 4, 0x0001);
    writeI16(bytes, offset + 6, placement);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 1);
    writeU16(bytes, offset + 12, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
