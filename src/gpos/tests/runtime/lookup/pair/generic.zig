//! Generic PairPos runtime contracts.

const std = @import("std");
const pair = @import("../../../../runtime/lookup/pair/root.zig");
const output = @import("../../../../runtime/output/root.zig");
const table = @import("../../../../table/root.zig");

test "PairPos subtables are ordered alternatives" {
    var bytes = [_]u8{0} ** 70;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 40);
    writePairSubtable(&bytes, 10, 5, 7, -20);
    writePairSubtable(&bytes, 40, 5, 7, -50);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(pair.generic.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try pair.generic.collectLookup(
        view,
        0,
        2,
        &.{ 5, 7 },
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    );
    try std.testing.expectEqual(
        @as(i16, -20),
        output.adjustments.find(adjustments.items, 0).?.x_advance,
    );
}

test "PairPos ValueFormat2 consumes the second participating glyph" {
    var bytes = [_]u8{0} ** 34;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 24);
    writeU16(&bytes, 4, 0);
    writeU16(&bytes, 6, 0x0004);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 12);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 7);
    writeI16(&bytes, 16, -10);
    writeCoverage1(&bytes, 24, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(pair.generic.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    const parsed = try @import(
        "../../../../positioning/root.zig",
    ).lookup.pair.parse(view, 0);

    try std.testing.expect(try pair.generic.collectAtParsed(
        view,
        parsed,
        &.{ 5, 7, 8 },
        0,
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    ));
    try std.testing.expectEqual(
        @as(usize, 2),
        pair.generic.advanceAfterPair(&.{ 5, 7, 8 }, 0, 0, .{}, true),
    );
}

fn writePairSubtable(
    bytes: []u8,
    offset: usize,
    first: u16,
    second: u16,
    x_advance: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 20);
    writeU16(bytes, offset + 4, 0x0004);
    writeU16(bytes, offset + 6, 0);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 12);
    writeU16(bytes, offset + 12, 1);
    writeU16(bytes, offset + 14, second);
    writeI16(bytes, offset + 16, x_advance);
    writeCoverage1(bytes, offset + 20, first);
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
