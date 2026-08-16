//! SinglePos and PairPos grammar contracts.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

test "SinglePos parsing exposes scalar and array layouts" {
    var bytes = [_]u8{0} ** 26;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 0x0004);
    writeI16(&bytes, 6, -30);
    writeCoverage1(&bytes, 8, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const scalar = try positioning.lookup.single.parse(view, 0);
    try std.testing.expectEqual(@as(u16, 1), scalar.pos_format);
    try std.testing.expectEqual(@as(i16, -30), scalar.value.x_advance);
    try positioning.lookup.single.validate(view, 0);

    @memset(&bytes, 0);
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 0x0004);
    writeU16(&bytes, 6, 2);
    writeI16(&bytes, 8, -20);
    writeI16(&bytes, 10, -40);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 2);
    writeU16(&bytes, 16, 5);
    writeU16(&bytes, 18, 6);
    const array = try positioning.lookup.single.parse(view, 0);
    try std.testing.expectEqual(@as(u16, 2), array.value_count);
    try std.testing.expectEqual(@as(usize, 8), array.values_pos);
    try positioning.lookup.single.validate(view, 0);

    writeU16(&bytes, 6, 1);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.single.validate(view, 0),
    );
}

test "PairPos format 1 validates and searches ordered PairSets" {
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 24);
    writeU16(&bytes, 4, 0x0004);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 12);
    writeU16(&bytes, 12, 2);
    writeU16(&bytes, 14, 7);
    writeI16(&bytes, 16, -20);
    writeU16(&bytes, 18, 9);
    writeI16(&bytes, 20, -40);
    writeCoverage1(&bytes, 24, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const parsed = try positioning.lookup.pair.parse(view, 0);
    try std.testing.expectEqual(@as(u16, 1), parsed.pos_format);
    try positioning.lookup.pair.validate(view, 0);
    try std.testing.expectEqual(
        @as(?usize, 18),
        try positioning.lookup.pair.findAfterProof(view, 12, 2, 2, 0, 9),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        try positioning.lookup.pair.findAfterProof(view, 12, 2, 2, 0, 8),
    );

    writeU16(&bytes, 18, 7);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.pair.validate(view, 0),
    );
    writeU16(&bytes, 10, 0);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.pair.validate(view, 0),
    );
}

test "PairPos format 2 validates class matrix cardinality" {
    var bytes = [_]u8{0} ** 52;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 28);
    writeU16(&bytes, 4, 0x0004);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 34);
    writeU16(&bytes, 10, 42);
    writeU16(&bytes, 12, 2);
    writeU16(&bytes, 14, 2);
    writeI16(&bytes, 16, 0);
    writeI16(&bytes, 18, -10);
    writeI16(&bytes, 20, -20);
    writeI16(&bytes, 22, -30);
    writeCoverage1(&bytes, 28, 5);
    writeClassDef1(&bytes, 34, 5, 1);
    writeClassDef1(&bytes, 42, 6, 1);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 8,
    };

    const parsed = try positioning.lookup.pair.parse(view, 0);
    try std.testing.expectEqual(@as(usize, 16), parsed.matrix_offset);
    try positioning.lookup.pair.validate(view, 0);

    writeU16(&bytes, 40, 2);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.pair.validate(view, 0),
    );
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    class: u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, glyph);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, class);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
