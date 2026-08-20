//! GPOS Lookup and ExtensionPos navigation contracts.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

test "Lookup header validates flags and MarkFilteringSet storage" {
    var bytes = [_]u8{0} ** 14;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0x0010);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 7);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const header = try positioning.lookup.dispatch.header(view, 0);
    try std.testing.expectEqual(@as(u16, 1), header.lookup_type);
    try std.testing.expectEqual(@as(?u16, 7), header.mark_filtering_set);

    writeU16(&bytes, 2, 0x0020);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.dispatch.header(view, 0),
    );
}

test "ExtensionPos resolves payload and rejects self aliases" {
    var bytes = [_]u8{0} ** 16;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 2);
    writeU32(&bytes, 4, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 0);
    writeU16(&bytes, 12, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const extension = try positioning.lookup.dispatch.extension(view, 0);
    try std.testing.expectEqual(@as(u16, 2), extension.lookup_type);
    try std.testing.expectEqual(@as(usize, 8), extension.payload_offset);
    try std.testing.expectEqual(
        @as(usize, 8),
        try positioning.lookup.dispatch.extensionPayload(view, 0, 2),
    );

    writeU32(&bytes, 4, 4);
    try std.testing.expectError(
        error.BadGpos,
        positioning.lookup.dispatch.extension(view, 0),
    );
    writeU32(&bytes, 4, 8);
    writeU16(&bytes, 2, 9);
    try std.testing.expectError(
        error.UnsupportedGpos,
        positioning.lookup.dispatch.extension(view, 0),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
