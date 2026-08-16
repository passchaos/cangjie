//! Direct GSUB subtable validation contracts.

const std = @import("std");
const table = @import("../../table/root.zig");
const validation = @import("../../validation/root.zig");

test "single validation distinguishes font and shaping delta bounds" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 6);
    writeI16(&bytes, 4, 0x7fff);
    writeCoverage1(&bytes, 6, 1);

    const font_view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 3,
    };
    try std.testing.expectError(
        error.BadGsub,
        validation.direct.single.validate(font_view, 0),
    );
    var shaping_view = font_view;
    shaping_view.allow_transient_single_delta = true;
    try validation.direct.single.validate(shaping_view, 0);
}

test "single format 2 validates coverage cardinality and substitute bounds" {
    var bytes = [_]u8{0} ** 18;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 10);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 3);
    writeCoverage1List(&bytes, 10, &.{ 1, 2 });

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 3,
    };
    try std.testing.expectError(
        error.BadGsub,
        validation.direct.single.validate(view, 0),
    );

    writeU16(&bytes, 10 + 2, 1);
    try std.testing.expectError(
        error.BadGsub,
        validation.direct.single.validate(view, 0),
    );
    writeU16(&bytes, 6, 2);
    try validation.direct.single.validate(view, 0);
}

test "set and sequence validation requires real coverage-indexed children" {
    var bytes = [_]u8{0} ** 20;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 0);
    writeCoverage1(&bytes, 8, 1);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 4,
    };

    try std.testing.expectError(
        error.BadGsub,
        validation.direct.set_sequence.multiple(view, 0),
    );
    try std.testing.expectError(
        error.BadGsub,
        validation.direct.set_sequence.alternate(view, 0),
    );

    writeU16(&bytes, 6, 14);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 2);
    try validation.direct.set_sequence.multiple(view, 0);
    try validation.direct.set_sequence.alternate(view, 0);
}

test "ligature shaping mode skips missing authored children only" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 0);
    writeCoverage1(&bytes, 8, 1);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 4,
    };
    try std.testing.expectError(
        error.BadGsub,
        validation.direct.ligature.validate(view, 0, .strict),
    );
    try validation.direct.ligature.validate(view, 0, .shaping);

    writeU16(&bytes, 6, 14);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 4);
    writeU16(&bytes, 18, 2);
    writeU16(&bytes, 20, 0);
    try std.testing.expectError(
        error.BadGsub,
        validation.direct.ligature.validate(view, 0, .strict),
    );
    try validation.direct.ligature.validate(view, 0, .shaping);
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

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}
