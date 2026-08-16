//! MarkMarkPos runtime contracts.

const std = @import("std");
const marks = @import("../../../../runtime/lookup/marks/root.zig");
const output_state = @import("../../../../runtime/output/root.zig");
const table = @import("../../../../table/root.zig");

test "MarkMarkPos attaches one mark to the preceding covered mark" {
    var bytes = [_]u8{0} ** 46;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 18);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 24);
    writeU16(&bytes, 10, 36);
    writeCoverage1(&bytes, 12, 22);
    writeCoverage1(&bytes, 18, 21);
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
    var adjustments = std.ArrayList(marks.mark.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try marks.mark.collect(
        view,
        0,
        &.{ 21, 22 },
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

test "MarkMarkPos skips lookup-flag ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 18);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 24);
    writeU16(&bytes, 10, 44);
    writeCoverage1(&bytes, 12, 12);
    writeCoverage1(&bytes, 18, 10);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 8);
    writeAnchor1(&bytes, 32, 0, 0);
    writeU16(&bytes, 44, 1);
    writeU16(&bytes, 46, 6);
    writeAnchor1(&bytes, 50, 50, 70);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[10] = 3;
    glyph_classes[11] = 1;
    glyph_classes[12] = 3;
    var adjustments = std.ArrayList(marks.mark.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try marks.mark.collect(
        view,
        0,
        &.{ 10, 11, 12 },
        &adjustments,
        allocator,
        0x0002,
        .{ .glyph_classes = &glyph_classes },
    );
    const mark = output_state.adjustments.find(adjustments.items, 2).?;
    try std.testing.expectEqual(@as(?usize, 0), mark.attachment_parent_index);
    try std.testing.expectEqual(@as(i16, 50), mark.x_placement);
    try std.testing.expectEqual(@as(i16, 70), mark.y_placement);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
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
