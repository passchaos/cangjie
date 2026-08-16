//! GSUB Coverage and ClassDef focused contracts.

const std = @import("std");
const table = @import("../../table/root.zig");

test "Coverage format 2 preserves first overlapping range and dense indexes" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 12);
    writeU16(&bytes, 8, 0);
    writeU16(&bytes, 10, 12);
    writeU16(&bytes, 12, 14);
    writeU16(&bytes, 14, 3);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try table.coverage.validate(view, 0, .indexed);
    try std.testing.expectEqual(
        @as(?usize, 2),
        try table.coverage.index(view, 0, 12),
    );
    try std.testing.expectEqual(@as(?u16, 12), try table.coverage.glyphAt(view, 0, 2));
    try std.testing.expectEqual(@as(usize, 6), try table.coverage.glyphCount(view, 0));
}

test "Coverage membership accepts duplicate format 1 glyphs only in membership mode" {
    var bytes = [_]u8{0} ** 8;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 7);
    writeU16(&bytes, 6, 7);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(
        error.BadGsub,
        table.coverage.validate(view, 0, .indexed),
    );
    try table.coverage.validate(view, 0, .membership);
}

test "ClassDef handles the upper glyph boundary and missing optional table" {
    var bytes = [_]u8{0} ** 10;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0xfffe);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 7);
    writeU16(&bytes, 8, 9);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectEqual(@as(u16, 7), try table.class_def.value(view, 0, 0xfffe));
    try std.testing.expectEqual(@as(u16, 9), try table.class_def.value(view, 0, 0xffff));
    try std.testing.expectEqual(
        @as(u16, 0),
        try table.class_def.value(view, table.class_def.empty_offset, 42),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
