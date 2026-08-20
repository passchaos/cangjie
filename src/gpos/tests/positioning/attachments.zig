//! CursivePos and mark-attachment grammar contracts.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

test "CursivePos validates coverage cardinality and optional anchors" {
    var bytes = [_]u8{0} ** 36;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 14);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 22);
    writeU16(&bytes, 10, 28);
    writeU16(&bytes, 12, 0);
    writeCoverage1List(&bytes, 14, &.{ 5, 6 });
    writeAnchor1(&bytes, 22, 10, 20);
    writeAnchor1(&bytes, 28, 30, 40);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const parsed = try positioning.lookup.cursive.parse(view, 0);
    try std.testing.expectEqual(@as(u16, 2), parsed.entry_exit_count);
    try positioning.lookup.cursive.validate(view, 0);

    writeU16(&bytes, 4, 1);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.cursive.validate(view, 0),
    );
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 8, 35);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.cursive.validate(view, 0),
    );
}

test "MarkBasePos requires array children and indexed coverage parity" {
    var bytes = [_]u8{0} ** 56;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 18);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 24);
    writeU16(&bytes, 10, 36);
    writeCoverage1(&bytes, 12, 5);
    writeCoverage1(&bytes, 18, 6);
    // MarkArray: one class-0 mark and mandatory anchor.
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 6);
    writeAnchor1(&bytes, 30, 10, 20);
    // BaseArray: one base, one optional anchor.
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeAnchor1(&bytes, 40, 30, 40);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const parsed = try positioning.lookup.marks.parseMarkToBase(view, 0);
    try std.testing.expectEqual(@as(u16, 1), parsed.class_count);
    try positioning.lookup.marks.validateMarkToBase(view, 0);

    writeU16(&bytes, 8, 0);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.marks.validateMarkToBase(view, 0),
    );
    writeU16(&bytes, 8, 24);
    writeU16(&bytes, 28, 0);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.marks.validateMarkToBase(view, 0),
    );
}

test "MarkLigPos and MarkMarkPos validate required and optional anchor grids" {
    var bytes = [_]u8{0} ** 72;
    writeMarkAttachmentHeader(&bytes);
    writeCoverage1(&bytes, 12, 5);
    writeCoverage1(&bytes, 18, 6);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 6);
    writeAnchor1(&bytes, 30, 10, 20);

    // LigatureArray with one required LigatureAttach and one optional anchor.
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeU16(&bytes, 40, 1);
    writeU16(&bytes, 42, 4);
    writeAnchor1(&bytes, 44, 30, 40);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try positioning.lookup.marks.validateMarkToLigature(view, 0);

    writeU16(&bytes, 38, 0);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.marks.validateMarkToLigature(view, 0),
    );

    // Reuse the header as MarkMarkPos: Mark2Array is an optional anchor grid.
    writeU16(&bytes, 38, 4);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 4);
    writeAnchor1(&bytes, 40, 50, 60);
    try positioning.lookup.marks.validateMarkToMark(view, 0);
    writeU16(&bytes, 38, 40);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.marks.validateMarkToMark(view, 0),
    );
}

fn writeMarkAttachmentHeader(bytes: []u8) void {
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 12);
    writeU16(bytes, 4, 18);
    writeU16(bytes, 6, 1);
    writeU16(bytes, 8, 24);
    writeU16(bytes, 10, 36);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeCoverage1List(bytes, offset, &.{glyph});
}

fn writeCoverage1List(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
}

fn writeAnchor1(
    bytes: []u8,
    offset: usize,
    x: i16,
    y: i16,
) void {
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
