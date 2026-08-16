//! GPOS table-view and offset contracts.

const std = @import("std");
const table = @import("../../table/root.zig");

test "GPOS table view bounds all reads to the declared table range" {
    const bytes = [_]u8{
        0xaa, 0xbb,
        0x12, 0x34,
        0xfe, 0xdc,
        0x89, 0xab,
        0xcd, 0xef,
        0x55,
    };
    const view = table.View{
        .data = &bytes,
        .offset = 2,
        .length = 8,
    };

    try std.testing.expectEqual(@as(u16, 0x1234), try view.readU16(0));
    try std.testing.expectEqual(@as(i16, -292), try view.readI16(2));
    try std.testing.expectEqual(@as(u32, 0x89abcdef), try view.readU32(4));
    try std.testing.expectError(error.EndOfStream, view.readU16(7));
    try std.testing.expectError(error.BadGpos, view.ensure(7, 2));
    try std.testing.expectEqualSlices(u8, bytes[2..10], try view.bytes());

    const invalid = table.View{
        .data = &bytes,
        .offset = std.math.maxInt(usize),
        .length = 2,
    };
    try std.testing.expectError(error.EndOfStream, invalid.readU16(0));
    try std.testing.expectError(error.EndOfStream, invalid.ensure(0, 1));
}

test "GPOS required optional and extension offsets enforce their contracts" {
    const bytes = [_]u8{0} ** 16;
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectEqual(@as(usize, 7), try table.offset.required16(view, 3, 4));
    try std.testing.expectEqual(@as(usize, 8), try table.offset.required32(view, 3, 5));
    try std.testing.expectEqual(@as(?usize, null), try table.offset.optional16(view, 3, 0));
    try std.testing.expectEqual(@as(?usize, null), try table.offset.optional32(view, 3, 0));
    try std.testing.expectError(error.BadGpos, table.offset.required16(view, 3, 0));
    try std.testing.expectError(error.BadGpos, table.offset.required32(view, 15, 2));
    try std.testing.expectError(error.BadGpos, table.offset.optional16(view, 17, 1));
    try std.testing.expectError(error.BadGpos, table.offset.extensionPayload(view, 0, 4));
    try std.testing.expectEqual(@as(usize, 8), try table.offset.extensionPayload(view, 0, 8));
}

test "GPOS scalar reads reject overflowing relative offsets" {
    const bytes = [_]u8{ 0, 1, 2, 3 };
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const offset = std.math.maxInt(usize);
    try std.testing.expectError(error.EndOfStream, view.readU16(offset));
    try std.testing.expectError(error.EndOfStream, view.readI16(offset));
    try std.testing.expectError(error.EndOfStream, view.readU32(offset));
}
