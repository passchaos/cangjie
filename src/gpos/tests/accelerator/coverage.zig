//! GPOS owned Coverage accelerator contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const table = @import("../../table/root.zig");

test "owned Coverage preserves format 1 and 2 indexes" {
    var bytes = [_]u8{0} ** 30;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 3);
    writeU16(&bytes, 4, 3);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 20);

    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 2);
    writeU16(&bytes, 14, 30);
    writeU16(&bytes, 16, 32);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 40);
    writeU16(&bytes, 22, 42);
    writeU16(&bytes, 24, 3);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const glyphs = try accelerator.coverage.Owned.build(
        view,
        0,
        std.testing.allocator,
    );
    defer glyphs.deinit(std.testing.allocator);
    try std.testing.expect(glyphs == .direct);
    try std.testing.expectEqual(@as(?usize, 0), glyphs.index(3));
    try std.testing.expectEqual(@as(?usize, 2), glyphs.index(20));
    try std.testing.expectEqual(@as(?usize, null), glyphs.index(9));

    const ranges = try accelerator.coverage.Owned.build(
        view,
        10,
        std.testing.allocator,
    );
    defer ranges.deinit(std.testing.allocator);
    try std.testing.expect(ranges == .direct);
    try std.testing.expectEqual(@as(?usize, 0), ranges.index(30));
    try std.testing.expectEqual(@as(?usize, 2), ranges.index(32));
    try std.testing.expectEqual(@as(?usize, 3), ranges.index(40));
    try std.testing.expectEqual(@as(?usize, 5), ranges.index(42));
    try std.testing.expectEqual(@as(?usize, null), ranges.index(33));
}

test "owned Coverage sequences reject null child offsets atomically" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 8);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectError(
        error.BadGpos,
        accelerator.coverage.Owned.buildSequence(
            view,
            0,
            0,
            2,
            std.testing.allocator,
        ),
    );
}

test "compact owned Coverage builds direct indexes" {
    var bytes = [_]u8{0} ** 20;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 3);
    writeU16(&bytes, 6, 8);
    const coverage = try accelerator.coverage.Owned.build(
        .{ .data = &bytes, .offset = 0, .length = bytes.len },
        0,
        std.testing.allocator,
    );
    defer coverage.deinit(std.testing.allocator);
    try std.testing.expect(coverage == .direct);
    try std.testing.expectEqual(@as(?usize, 0), coverage.index(3));
    try std.testing.expectEqual(@as(?usize, 1), coverage.index(8));
    try std.testing.expectEqual(@as(?usize, null), coverage.index(4));
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
