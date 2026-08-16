//! MultipleSubst accelerator builder contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const table = @import("../../../table/root.zig");

test "multiple builder sorts entries and records singleton sequences" {
    var bytes = [_]u8{0} ** 34;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 22);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 14);
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 30);
    writeU16(&bytes, 14, 2);
    writeU16(&bytes, 16, 40);
    writeU16(&bytes, 18, 41);
    writeCoverage1(&bytes, 22, &.{ 9, 5 });
    // Coverage is intentionally unsorted only under assume_validated; the
    // builder still canonicalizes its native entry table by glyph id.
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const result = try build.multiple.build(view, 0, std.testing.allocator);
    defer std.testing.allocator.free(result.entries);
    try std.testing.expectEqual(@as(u16, 5), result.entries[0].glyph);
    try std.testing.expectEqual(@as(u16, 0), result.entries[0].single_to);
    try std.testing.expectEqual(@as(u16, 9), result.entries[1].glyph);
    try std.testing.expectEqual(@as(u16, 30), result.entries[1].single_to);
}

test "multiple builder ignores unsupported formats" {
    var bytes = [_]u8{0} ** 2;
    writeU16(&bytes, 0, 2);
    const result = try build.multiple.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, 0, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result.entries.len);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
