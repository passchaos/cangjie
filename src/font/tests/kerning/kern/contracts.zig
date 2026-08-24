//! Pure legacy OpenType and Apple kern table contracts.

const std = @import("std");

const kern = @import("../../../tables/kerning/kern/root.zig");
const sfnt = @import("../../../sfnt/root.zig");

test "legacy format 0 accumulates eligible subtables" {
    var data: [64]u8 = .{0} ** 64;
    writeU16(&data, 2, 3);
    writeLegacyFormat0(&data, 4, 0x0003, 1, 1, -100);
    writeLegacyFormat0(&data, 24, 0x0005, 1, 1, -80);
    writeLegacyFormat0(&data, 44, 0x0001, 1, 1, -30);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    try std.testing.expectEqual(
        @as(i16, -30),
        try kern.kerningAfterProof(&data, table, 1, 1),
    );

    // Two normal horizontal subtables add rather than replace by default.
    writeU16(&data, 4 + 4, 0x0001);
    writeU16(&data, 24 + 4, 0x0001);
    try std.testing.expectEqual(
        @as(i16, -210),
        try kern.kerningAfterProof(&data, table, 1, 1),
    );
}

test "legacy override coverage replaces accumulated kerning" {
    var data: [44]u8 = .{0} ** 44;
    writeU16(&data, 2, 2);
    writeLegacyFormat0(&data, 4, 0x0001, 1, 1, -40);
    writeLegacyFormat0(&data, 24, 0x0009, 1, 1, -70);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    try std.testing.expectEqual(
        @as(i16, -70),
        try kern.kerningAfterProof(&data, table, 1, 1),
    );
}

test "format 0 accepts canonical empty search metadata" {
    var data: [18]u8 = .{0} ** 18;
    writeU16(&data, 2, 1);
    writeU16(&data, 6, 14);
    writeU16(&data, 8, 0x0001);
    // FontTools emits the one-record searchRange even for an empty pair array.
    writeU16(&data, 12, 6);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    try std.testing.expectEqual(
        @as(i16, 0),
        try kern.kerningAfterProof(&data, table, 1, 1),
    );
}

test "Apple format 0 accumulates horizontal pair subtables" {
    var data: [54]u8 = .{0} ** 54;
    writeU32(&data, 0, 0x00010000);
    writeU32(&data, 4, 2);
    writeAppleFormat0(&data, 8, 0x0000, 1, 1, -35);
    writeAppleFormat0(&data, 31, 0x0000, 1, 1, -45);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    try std.testing.expectEqual(
        @as(i16, -80),
        try kern.kerningAfterProof(&data, table, 1, 1),
    );
}

test "Apple format 2 applies class kerning" {
    var data: [58]u8 = .{0} ** 58;
    writeU32(&data, 0, 0x00010000);
    writeU32(&data, 4, 1);
    writeU32(&data, 8, 50);
    writeU16(&data, 12, 0x0002);
    writeU16(&data, 16, 4);
    writeU16(&data, 18, 24);
    writeU16(&data, 20, 34);
    writeU16(&data, 22, 16);
    writeI16(&data, 26, -40);
    writeU16(&data, 32, 0);
    writeU16(&data, 34, 1);
    writeU16(&data, 36, 16);
    writeU16(&data, 42, 1);
    writeU16(&data, 44, 1);
    writeU16(&data, 46, 2);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    try std.testing.expectEqual(
        @as(i16, -40),
        try kern.kerningAfterProof(&data, table, 0, 1),
    );
    try std.testing.expectEqual(
        @as(i16, 0),
        try kern.kerningAfterProof(&data, table, 1, 1),
    );
}

test "kern metadata uses concrete module value types" {
    var data: [24]u8 = .{0} ** 24;
    writeU16(&data, 2, 1);
    writeLegacyFormat0(&data, 4, 0x0001, 1, 1, -40);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    const info = try kern.info(std.testing.allocator, &data, table);
    defer kern.free(std.testing.allocator, info);

    try std.testing.expectEqual(kern.Dialect.legacy, info.dialect);
    try std.testing.expectEqual(@as(usize, 1), info.subtables.len);
    try std.testing.expectEqual(@as(?u16, 1), info.subtables[0].pair_count);
}

test "Apple kern metadata exposes coverage and tuple fields" {
    var data: [31]u8 = .{0} ** 31;
    writeU32(&data, 0, 0x00010000);
    writeU32(&data, 4, 1);
    writeAppleFormat0(&data, 8, 0x2000, 1, 1, -35);
    writeU16(&data, 14, 7);

    const table = record(&data);
    try kern.validate(&data, table, 2);
    const info = try kern.info(std.testing.allocator, &data, table);
    defer kern.free(std.testing.allocator, info);

    try std.testing.expectEqual(kern.Dialect.apple, info.dialect);
    try std.testing.expectEqual(@as(usize, 1), info.subtables.len);
    try std.testing.expect(info.subtables[0].variation);
    try std.testing.expectEqual(@as(?u16, 7), info.subtables[0].tuple_index);
    try std.testing.expectEqual(@as(?u16, 1), info.subtables[0].pair_count);
}

test "kern validation rejects malformed ownership and pair arrays" {
    {
        var data: [25]u8 = .{0} ** 25;
        writeU16(&data, 2, 1);
        writeLegacyFormat0(&data, 4, 0x0001, 1, 1, -40);
        try std.testing.expectError(
            error.BadSfnt,
            kern.validate(&data, record(&data), 2),
        );
    }
    {
        var data: [24]u8 = .{0} ** 24;
        writeU16(&data, 2, 1);
        writeLegacyFormat0(&data, 4, 0x0001, 2, 1, -40);
        try std.testing.expectError(
            error.BadSfnt,
            kern.validate(&data, record(&data), 2),
        );
    }
    {
        var data: [30]u8 = .{0} ** 30;
        writeU16(&data, 2, 1);
        writeU16(&data, 6, 26);
        writeU16(&data, 8, 0x0001);
        writeU16(&data, 10, 2);
        writeU16(&data, 12, 6);
        writeU16(&data, 18, 1);
        writeU16(&data, 20, 1);
        writeI16(&data, 22, -40);
        writeU16(&data, 24, 0);
        writeU16(&data, 26, 1);
        writeI16(&data, 28, -20);
        try std.testing.expectError(
            error.BadSfnt,
            kern.validate(&data, record(&data), 2),
        );
    }
}

test "kern validation rejects nonzero legacy subtable versions" {
    var data = [_]u8{0} ** 24;
    writeU16(&data, 2, 1);
    writeLegacyFormat0(&data, 4, 0x0001, 1, 1, -40);
    writeU16(&data, 4, 1);
    try std.testing.expectError(
        error.BadSfnt,
        kern.validate(&data, record(&data), 2),
    );
}

test "kern subtable sequences consume the complete declared payload" {
    {
        var data = [_]u8{0} ** 25;
        writeU16(&data, 2, 1);
        writeLegacyFormat0(&data, 4, 0x0001, 1, 1, -40);
        try std.testing.expectError(
            error.BadSfnt,
            kern.validate(&data, record(&data), 2),
        );
    }
    {
        var data = [_]u8{0} ** 32;
        writeU32(&data, 0, 0x00010000);
        writeU32(&data, 4, 1);
        writeAppleFormat0(&data, 8, 0x0000, 1, 1, -35);
        try std.testing.expectError(
            error.BadSfnt,
            kern.validate(&data, record(&data), 2),
        );
    }
}

test "format 0 ignores stale binary-search metadata" {
    {
        var data = [_]u8{0} ** 24;
        writeU16(&data, 2, 1);
        writeLegacyFormat0(&data, 4, 0x0001, 1, 1, -40);
        writeU16(&data, 12, 12);
        try kern.validate(&data, record(&data), 2);
        try std.testing.expectEqual(
            @as(i16, -40),
            try kern.kerningAfterProof(&data, record(&data), 1, 1),
        );
    }
    {
        var data = [_]u8{0} ** 31;
        writeU32(&data, 0, 0x00010000);
        writeU32(&data, 4, 1);
        writeAppleFormat0(&data, 8, 0x0000, 1, 1, -35);
        writeU16(&data, 22, 2);
        try kern.validate(&data, record(&data), 2);
        try std.testing.expectEqual(
            @as(i16, -35),
            try kern.kerningAfterProof(&data, record(&data), 1, 1),
        );
    }
}

test "legacy final format 0 recovers a wrapped UInt16 length" {
    const pair_count: u16 = 10_921;
    const actual_length = 4 + 14 + @as(usize, pair_count) * 6;
    const data = try std.testing.allocator.alloc(u8, actual_length);
    defer std.testing.allocator.free(data);
    @memset(data, 0);
    writeU16(data, 2, 1);
    // The true subtable length is 65,540 and therefore wraps to four.
    writeU16(data, 6, @truncate(actual_length - 4));
    writeU16(data, 8, 0x0001);
    writeU16(data, 10, pair_count);
    for (0..pair_count) |index| {
        const offset = 18 + index * 6;
        writeU16(data, offset, @intCast(index));
        writeU16(data, offset + 2, 1);
        writeI16(data, offset + 4, -1);
    }

    const table = record(data);
    try kern.validate(data, table, pair_count + 1);
    try std.testing.expectEqual(
        @as(i16, -1),
        try kern.kerningAfterProof(data, table, pair_count - 1, 1),
    );
}

test "format 0 rejects truncated binary search headers" {
    var data = [_]u8{0} ** 16;
    writeU16(&data, 2, 1);
    writeU16(&data, 6, 12);
    writeU16(&data, 8, 0x0001);
    try std.testing.expectError(
        error.BadSfnt,
        kern.validate(&data, record(&data), 2),
    );
}

fn record(data: []const u8) sfnt.Record {
    return .{
        .tag = .{ 'k', 'e', 'r', 'n' },
        .checksum = 0,
        .offset = 0,
        .length = data.len,
    };
}

fn writeLegacyFormat0(
    bytes: []u8,
    offset: usize,
    coverage: u16,
    left: u16,
    right: u16,
    value: i16,
) void {
    writeU16(bytes, offset + 2, 20);
    writeU16(bytes, offset + 4, coverage);
    writeFormat0Body(bytes, offset + 6, left, right, value);
}

fn writeAppleFormat0(
    bytes: []u8,
    offset: usize,
    coverage: u16,
    left: u16,
    right: u16,
    value: i16,
) void {
    writeU32(bytes, offset, 23);
    writeU16(bytes, offset + 4, coverage);
    writeFormat0Body(bytes, offset + 8, left, right, value);
}

fn writeFormat0Body(
    bytes: []u8,
    offset: usize,
    left: u16,
    right: u16,
    value: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 6);
    writeU16(bytes, offset + 8, left);
    writeU16(bytes, offset + 10, right);
    writeI16(bytes, offset + 12, value);
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
