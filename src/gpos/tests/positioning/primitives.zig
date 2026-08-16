//! GPOS Anchor, Device, and ValueRecord contracts.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

test "ValueRecord decodes scalars and validates parent-relative children" {
    var bytes = [_]u8{0} ** 32;
    writeI16(&bytes, 0, 50);
    writeI16(&bytes, 2, -25);
    writeI16(&bytes, 4, 30);
    writeI16(&bytes, 6, -10);
    writeU16(&bytes, 8, 16);
    writeU16(&bytes, 10, 0);
    writeU16(&bytes, 12, 22);
    writeU16(&bytes, 14, 0);
    // Device at parent + 16.
    writeU16(&bytes, 16, 12);
    writeU16(&bytes, 18, 12);
    writeU16(&bytes, 20, 1);
    // VariationIndex at parent + 22.
    writeU16(&bytes, 22, 7);
    writeU16(&bytes, 24, 3);
    writeU16(&bytes, 26, 0x8000);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectEqual(
        @as(usize, 16),
        try positioning.value_record.size(0x00ff),
    );
    try std.testing.expect(
        positioning.value_record.hasDeviceOffsets(0x00ff),
    );
    const value = try positioning.value_record.read(view, 0, 0x00ff, 0);
    try std.testing.expectEqual(@as(i16, 50), value.x_placement);
    try std.testing.expectEqual(@as(i16, -25), value.y_placement);
    try std.testing.expectEqual(@as(i16, 30), value.x_advance);
    try std.testing.expectEqual(@as(i16, -10), value.y_advance);

    writeU16(&bytes, 8, 30);
    try std.testing.expectError(
        error.BadGpos,
        positioning.value_record.validate(view, 0, 0x00ff, 0),
    );
    try std.testing.expectError(
        error.BadGpos,
        positioning.value_record.size(0x0100),
    );
}

test "Device validation distinguishes packed deltas and VariationIndex" {
    var bytes = [_]u8{0} ** 10;
    writeU16(&bytes, 0, 12);
    writeU16(&bytes, 2, 14);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 0);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try positioning.device.validate(view, 0);

    writeU16(&bytes, 2, 11);
    try std.testing.expectError(
        error.BadGpos,
        positioning.device.validate(view, 0),
    );
    writeU16(&bytes, 2, 14);
    writeU16(&bytes, 4, 4);
    try std.testing.expectError(
        error.UnsupportedGpos,
        positioning.device.validate(view, 0),
    );
    writeU16(&bytes, 4, 0x8000);
    try positioning.device.validate(view, 0);
}

test "Anchor formats preserve size contracts and VariationIndex deltas" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeI16(&bytes, 2, 20);
    writeI16(&bytes, 4, -10);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectEqual(
        positioning.anchor.Value{ .x = 20, .y = -10 },
        try positioning.anchor.read(view, 0, .{}),
    );

    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 16);
    writeU16(&bytes, 10, 0);
    writeU16(&bytes, 12, 0);
    writeU16(&bytes, 14, 0x8000);
    writeU16(&bytes, 16, 0);
    writeU16(&bytes, 18, 1);
    writeU16(&bytes, 20, 0x8000);

    const store = 24;
    writeU16(&bytes, store + 0, 1);
    writeU32(&bytes, store + 2, 12);
    writeU16(&bytes, store + 6, 1);
    writeU32(&bytes, store + 8, 24);
    writeU16(&bytes, store + 12, 1);
    writeU16(&bytes, store + 14, 1);
    writeI16(&bytes, store + 16, 0);
    writeI16(&bytes, store + 18, 0x4000);
    writeI16(&bytes, store + 20, 0x4000);
    writeU16(&bytes, store + 24, 2);
    writeU16(&bytes, store + 26, 1);
    writeU16(&bytes, store + 28, 1);
    writeU16(&bytes, store + 30, 0);
    writeI16(&bytes, store + 32, 8);
    writeI16(&bytes, store + 34, -6);

    try positioning.anchor.validate(view, 0);
    try std.testing.expectEqual(
        positioning.anchor.Value{ .x = 24, .y = -13 },
        try positioning.anchor.read(view, 0, .{
            .normalized_coords = &.{0.5},
            .variation_store = .{
                .data = &bytes,
                .table_offset = 0,
                .table_length = bytes.len,
                .store_offset = store,
            },
        }),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
