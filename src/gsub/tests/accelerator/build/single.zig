//! SingleSubst accelerator builder contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const table = @import("../../../table/root.zig");

test "single builder decodes compact delta and sorted entries" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 6);
    writeI16(&bytes, 4, 3);
    writeCoverage1(&bytes, 6, &.{ 5, 8 });
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    const compact = try build.single.compact(view, 0);
    try std.testing.expect(compact.enabled);
    try std.testing.expect(!compact.single_mapping);
    const entries = try build.single.entries(view, 0, std.testing.allocator);
    defer std.testing.allocator.free(entries);
    try std.testing.expectEqualSlices(build.single.Entry, &.{
        .{ .from = 5, .to = 8 },
        .{ .from = 8, .to = 11 },
    }, entries);
}

test "single builder records singleton format 2 fast mapping" {
    var bytes = [_]u8{0} ** 14;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 42);
    writeCoverage1(&bytes, 8, &.{7});
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    const compact = try build.single.compact(view, 0);
    try std.testing.expect(compact.single_mapping);
    try std.testing.expectEqual(@as(u16, 7), compact.single_from);
    try std.testing.expectEqual(@as(u16, 42), compact.single_to);

    const entries = try build.single.entries(view, 0, std.testing.allocator);
    defer std.testing.allocator.free(entries);
    try std.testing.expectEqualSlices(build.single.Entry, &.{
        .{ .from = 7, .to = 42 },
    }, entries);
}

test "single entries reject format 2 coverage cardinality mismatch" {
    var bytes = [_]u8{0} ** 14;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 42);
    writeCoverage1(&bytes, 8, &.{7});

    try std.testing.expectError(
        error.BadGsub,
        build.single.entries(.{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
        }, 0, std.testing.allocator),
    );
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

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
