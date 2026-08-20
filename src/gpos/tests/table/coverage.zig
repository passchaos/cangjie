//! GPOS Coverage and ClassDef focused contracts.

const std = @import("std");
const table = @import("../../table/root.zig");

test "GPOS indexed Coverage format 2 enforces dense disjoint ranges" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 12);
    writeU16(&bytes, 8, 0);
    writeU16(&bytes, 10, 13);
    writeU16(&bytes, 12, 14);
    writeU16(&bytes, 14, 3);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 15,
    };

    try table.coverage.validate(view, 0, .indexed);
    try std.testing.expectEqual(
        @as(?usize, 2),
        try table.coverage.index(view, 0, 12),
    );
    try std.testing.expectEqual(
        @as(?u16, 13),
        try table.coverage.glyphAt(view, 0, 3),
    );
    try std.testing.expectEqual(@as(usize, 5), try table.coverage.glyphCount(view, 0));
    try table.coverage.validateIndices(view, 0, 5);
    const digest = try table.coverage.digest(view, 0);
    try std.testing.expect(digest.mayHave(10));
    try std.testing.expect(digest.mayHave(14));
    try std.testing.expectError(
        error.BadGpos,
        table.coverage.validateIndices(view, 0, 4),
    );

    var bounded = view;
    bounded.glyph_count = 14;
    try std.testing.expectError(
        error.BadGpos,
        table.coverage.validate(bounded, 0, .indexed),
    );

    writeU16(&bytes, 14, 4);
    try std.testing.expectError(
        error.BadGpos,
        table.coverage.validate(view, 0, .indexed),
    );
}

test "GPOS membership Coverage accepts duplicates without weakening indexed users" {
    var bytes = [_]u8{0} ** 10;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 3);
    writeU16(&bytes, 4, 5);
    writeU16(&bytes, 6, 5);
    writeU16(&bytes, 8, 7);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .glyph_count = 8,
    };

    try table.coverage.validate(view, 0, .membership);
    try std.testing.expect(try table.coverage.contains(view, 0, 5, .membership));
    try std.testing.expect(!(try table.coverage.contains(view, 0, 6, .membership)));
    try std.testing.expectError(
        error.BadGpos,
        table.coverage.validate(view, 0, .indexed),
    );
    try std.testing.expectError(
        error.BadGpos,
        table.coverage.index(view, 0, 5),
    );
}

test "GPOS ClassDef validates glyph and consumer class bounds" {
    var bytes = [_]u8{0} ** 10;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0xfffe);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 1);
    writeU16(&bytes, 8, 2);
    const detached = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try table.class_def.validateWithLimit(detached, 0, 3);
    try std.testing.expectEqual(
        @as(u16, 1),
        try table.class_def.value(detached, 0, 0xfffe),
    );
    try std.testing.expectEqual(
        @as(u16, 2),
        try table.class_def.value(detached, 0, 0xffff),
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try table.class_def.value(detached, 0, 0xfffd),
    );
    try std.testing.expectError(
        error.BadGpos,
        table.class_def.validateWithLimit(detached, 0, 2),
    );

    var bounded = detached;
    bounded.glyph_count = 0xffff;
    try std.testing.expectError(
        error.BadGpos,
        table.class_def.validate(bounded, 0),
    );
}

test "GPOS coverage and classes reach the full glyph-id boundary" {
    var coverage_bytes = [_]u8{0} ** 10;
    writeU16(&coverage_bytes, 0, 2);
    writeU16(&coverage_bytes, 2, 1);
    writeU16(&coverage_bytes, 4, 0);
    writeU16(&coverage_bytes, 6, 0xffff);
    writeU16(&coverage_bytes, 8, 0);
    const coverage_view = table.View{
        .data = &coverage_bytes,
        .offset = 0,
        .length = coverage_bytes.len,
    };
    try std.testing.expectEqual(
        @as(?usize, 0xfffe),
        try table.coverage.index(coverage_view, 0, 0xfffe),
    );
    try std.testing.expectEqual(
        @as(?usize, 0xffff),
        try table.coverage.index(coverage_view, 0, 0xffff),
    );

    var class_bytes = [_]u8{0} ** 10;
    writeU16(&class_bytes, 0, 1);
    writeU16(&class_bytes, 2, 0xfffe);
    writeU16(&class_bytes, 4, 2);
    writeU16(&class_bytes, 6, 7);
    writeU16(&class_bytes, 8, 9);
    const class_view = table.View{
        .data = &class_bytes,
        .offset = 0,
        .length = class_bytes.len,
    };
    try std.testing.expectEqual(
        @as(u16, 7),
        try table.class_def.value(class_view, 0, 0xfffe),
    );
    try std.testing.expectEqual(
        @as(u16, 9),
        try table.class_def.value(class_view, 0, 0xffff),
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try table.class_def.value(class_view, 0, 0xfffd),
    );
}

test "GPOS ClassDef format 2 rejects overlapping and reversed ranges" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 12);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 12);
    writeU16(&bytes, 12, 14);
    writeU16(&bytes, 14, 2);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(
        error.BadGpos,
        table.class_def.validate(view, 0),
    );
    try std.testing.expectError(
        error.BadGpos,
        table.class_def.value(view, 0, 12),
    );

    writeU16(&bytes, 10, 13);
    writeU16(&bytes, 12, 11);
    try std.testing.expectError(
        error.BadGpos,
        table.class_def.validate(view, 0),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
