//! GSUB table-view and offset contracts.

const std = @import("std");
const table = @import("../../table/root.zig");

test "GSUB table view bounds all reads to the declared table range" {
    const bytes = [_]u8{ 0xaa, 0xbb, 0x12, 0x34, 0xfe, 0xdc, 0x55 };
    const view = table.View{
        .data = &bytes,
        .offset = 2,
        .length = 4,
    };

    try std.testing.expectEqual(@as(u16, 0x1234), try view.readU16(0));
    try std.testing.expectEqual(@as(i16, -292), try view.readI16(2));
    try std.testing.expectError(error.EndOfStream, view.readU16(3));
    try std.testing.expectError(error.BadGsub, view.ensure(3, 2));
    try std.testing.expectEqualSlices(u8, bytes[2..6], try view.bytes());

    const invalid = table.View{
        .data = &bytes,
        .offset = std.math.maxInt(usize),
        .length = 2,
    };
    try std.testing.expectError(error.EndOfStream, invalid.readU16(0));
}

test "GSUB required and extension offsets reject aliases and overflow" {
    const bytes = [_]u8{0} ** 16;
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = 16,
    };

    try std.testing.expectEqual(@as(usize, 7), try table.offset.required16(view, 3, 4));
    try std.testing.expectEqual(@as(?usize, null), try table.offset.optional16(view, 3, 0));
    try std.testing.expectError(error.BadGsub, table.offset.required16(view, 3, 0));
    try std.testing.expectError(error.BadGsub, table.offset.required32(view, 15, 2));
    try std.testing.expectError(error.BadGsub, table.offset.extensionPayload(view, 0, 4));
    try std.testing.expectEqual(@as(usize, 8), try table.offset.extensionPayload(view, 0, 8));
}
