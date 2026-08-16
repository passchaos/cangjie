//! MarkBasePos runtime contracts.

const std = @import("std");
const marks = @import("../../../../runtime/lookup/marks/root.zig");
const output_state = @import("../../../../runtime/output/root.zig");
const table = @import("../../../../table/root.zig");

test "MarkBasePos attaches a mark to the nearest covered base" {
    var bytes = [_]u8{0} ** 48;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 18);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 24);
    writeU16(&bytes, 10, 36);
    writeCoverage1(&bytes, 12, 22);
    writeCoverage1(&bytes, 18, 20);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 6);
    writeAnchor1(&bytes, 30, 10, 15);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeAnchor1(&bytes, 40, 100, 120);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(marks.base.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try marks.base.collect(
        view,
        0,
        &.{ 20, 22 },
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    );
    const mark = output_state.adjustments.find(adjustments.items, 1).?;
    try std.testing.expectEqual(@as(i16, 90), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 105), mark.y_placement);
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
}

test "nested MarkBasePos targets only the requested mark" {
    var bytes = [_]u8{0} ** 58;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 20);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 26);
    writeU16(&bytes, 10, 48);
    writeCoverageList1(&bytes, 12, &.{ 22, 23 });
    writeCoverage1(&bytes, 20, 20);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 0);
    writeU16(&bytes, 30, 10);
    writeU16(&bytes, 32, 0);
    writeU16(&bytes, 34, 16);
    writeAnchor1(&bytes, 36, 10, 15);
    writeAnchor1(&bytes, 42, 20, 25);
    writeU16(&bytes, 48, 1);
    writeU16(&bytes, 50, 4);
    writeAnchor1(&bytes, 52, 100, 120);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(marks.base.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expect(try marks.base.collectAt(
        view,
        0,
        &.{ 20, 22, 23 },
        2,
        &adjustments,
        std.testing.allocator,
        0,
        .{},
        &.{},
    ));
    try std.testing.expect(output_state.adjustments.find(
        adjustments.items,
        1,
    ) == null);
    try std.testing.expect(output_state.adjustments.find(
        adjustments.items,
        2,
    ) != null);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeCoverageList1(bytes, offset, &.{glyph});
}

fn writeCoverageList1(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
}

fn writeAnchor1(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16(bytes, offset, 1);
    writeI16(bytes, offset + 2, x);
    writeI16(bytes, offset + 4, y);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
