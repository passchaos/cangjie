//! Pure cmap scalar and variation lookup contracts.

const std = @import("std");

const cmap = @import("../../tables/cmap/root.zig");

test "scalar lookup dispatches compact and segmented formats" {
    var format4: [32]u8 = .{0} ** 32;
    writeU16(&format4, 0, 4);
    writeU16(&format4, 2, format4.len);
    writeU16(&format4, 6, 4);
    writeU16(&format4, 8, 4);
    writeU16(&format4, 10, 1);
    writeU16(&format4, 14, 'A');
    writeU16(&format4, 16, 0xffff);
    writeU16(&format4, 18, 0);
    writeU16(&format4, 20, 'A');
    writeU16(&format4, 22, 0xffff);
    writeI16(&format4, 24, 1 - @as(i16, 'A'));
    writeI16(&format4, 26, 1);

    try std.testing.expectEqual(
        @as(u16, 1),
        try cmap.glyph(&format4, subtable(4, 0, format4.len), 'A'),
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try cmap.glyph(&format4, subtable(4, 0, format4.len), 'B'),
    );

    var format12: [28]u8 = .{0} ** 28;
    writeU16(&format12, 0, 12);
    writeU32(&format12, 4, format12.len);
    writeU32(&format12, 12, 1);
    writeU32(&format12, 16, 0x10000);
    writeU32(&format12, 20, 0x10001);
    writeU32(&format12, 24, 7);
    try std.testing.expectEqual(
        @as(u16, 8),
        try cmap.glyph(&format12, subtable(12, 0, format12.len), 0x10001),
    );

    var format13 = format12;
    writeU16(&format13, 0, 13);
    try std.testing.expectEqual(
        @as(u16, 7),
        try cmap.glyph(&format13, subtable(13, 0, format13.len), 0x10001),
    );
}

test "format 4 idRangeOffset remains inside the declared subtable" {
    var valid: [32]u8 = .{0} ** 32;
    writeU16(&valid, 0, 4);
    writeU16(&valid, 2, 26);
    writeU16(&valid, 6, 2);
    writeU16(&valid, 14, 'A');
    writeU16(&valid, 16, 0);
    writeU16(&valid, 18, 'A');
    writeI16(&valid, 20, 0);
    writeU16(&valid, 22, 2);
    writeU16(&valid, 24, 99);
    try std.testing.expectEqual(
        @as(u16, 99),
        try cmap.glyph(&valid, subtable(4, 0, 26), 'A'),
    );

    var truncated = valid;
    writeU16(&truncated, 2, 24);
    try std.testing.expectError(
        error.BadSfnt,
        cmap.glyph(&truncated, subtable(4, 0, 24), 'A'),
    );
}

test "scalar lookup rejects unsupported and truncated subtables" {
    var unsupported: [10]u8 = .{0} ** 10;
    writeU16(&unsupported, 0, 14);
    try std.testing.expectError(
        error.UnsupportedCmap,
        cmap.glyph(&unsupported, subtable(14, 0, unsupported.len), 'A'),
    );

    var truncated: [20]u8 = .{0} ** 20;
    writeU16(&truncated, 0, 10);
    writeU32(&truncated, 4, truncated.len);
    writeU32(&truncated, 12, 'A');
    writeU32(&truncated, 16, 1);
    try std.testing.expectError(
        error.BadSfnt,
        cmap.glyph(&truncated, subtable(10, 0, truncated.len), 'A'),
    );

    var trailing_group: [30]u8 = .{0} ** 30;
    writeU16(&trailing_group, 0, 12);
    writeU32(&trailing_group, 4, trailing_group.len);
    writeU32(&trailing_group, 12, 1);
    writeU32(&trailing_group, 16, 'A');
    writeU32(&trailing_group, 20, 'A');
    writeU32(&trailing_group, 24, 9);
    try std.testing.expectError(
        error.BadSfnt,
        cmap.glyph(
            &trailing_group,
            subtable(12, 0, trailing_group.len),
            'A',
        ),
    );
}

test "variation lookup distinguishes explicit default and absent results" {
    var table: [38]u8 = .{0} ** 38;
    writeU16(&table, 0, 14);
    writeU32(&table, 2, table.len);
    writeU32(&table, 6, 1);
    writeU24(&table, 10, 0xfe0f);
    writeU32(&table, 13, 21);
    writeU32(&table, 17, 29);

    writeU32(&table, 21, 1);
    writeU24(&table, 25, 'B');
    table[28] = 0;

    writeU32(&table, 29, 1);
    writeU24(&table, 33, 'A');
    writeU16(&table, 36, 3);

    try std.testing.expectEqual(
        cmap.VariationResult{ .explicit_glyph = 3 },
        try cmap.variationGlyph(
            &table,
            0,
            table.len,
            'A',
            0xfe0f,
            4,
        ),
    );
    try std.testing.expectEqual(
        cmap.VariationResult.use_default,
        try cmap.variationGlyph(
            &table,
            0,
            table.len,
            'B',
            0xfe0f,
            4,
        ),
    );
    try std.testing.expectEqual(
        cmap.VariationResult.none,
        try cmap.variationGlyph(
            &table,
            0,
            table.len,
            'C',
            0xfe0f,
            4,
        ),
    );

    var invalid_selector = table;
    writeU24(&invalid_selector, 10, 'A');
    try std.testing.expectError(
        error.BadSfnt,
        cmap.variationGlyph(
            &invalid_selector,
            0,
            invalid_selector.len,
            'A',
            0xfe0f,
            4,
        ),
    );
}

fn subtable(format: u16, offset: usize, length: usize) cmap.Subtable {
    return .{
        .platform_id = 0,
        .encoding_id = if (format == 13) 6 else 4,
        .offset = offset,
        .length = length,
        .format = format,
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast(value >> 16);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
