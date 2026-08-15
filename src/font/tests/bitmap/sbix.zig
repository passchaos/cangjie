//! Public sbix APIs revalidate caller-owned strike metadata.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const table_only = @import("../fixtures/table_only.zig");

const Font = font_mod.Font;

test "sbix public bitmap APIs revalidate borrowed strike offsets" {
    var bytes = emptySbix();
    const font = fixture(&bytes);
    try std.testing.expectEqual(
        @as(?u16, 16),
        try font.bestBitmapStrikePpem(16),
    );
    const strikes = try font.bitmapStrikes(std.testing.allocator);
    defer std.testing.allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expect(
        (try font.bitmapGlyphPng(0, 16)) == null,
    );

    // The unrequested glyph boundary makes the whole borrowed strike invalid.
    writeU32(&bytes, 24, 12);
    try std.testing.expectError(
        error.BadSfnt,
        font.bitmapStrikes(std.testing.allocator),
    );
    try std.testing.expectError(
        error.BadSfnt,
        font.bestBitmapStrikePpem(16),
    );
    try std.testing.expectError(
        error.BadSfnt,
        font.bitmapGlyphPng(0, 16),
    );
}

test "sbix public bitmap APIs revalidate borrowed table checksum" {
    var bytes = emptySbix();
    const font = fixture(&bytes);
    try std.testing.expectEqual(
        @as(?u16, 16),
        try font.bestBitmapStrikePpem(16),
    );

    // ppem 17 remains structurally valid, isolating the checksum contract.
    writeU16(&bytes, 12, 17);
    try std.testing.expectError(
        error.BadSfnt,
        font.bestBitmapStrikePpem(16),
    );
    try std.testing.expectError(
        error.BadSfnt,
        font.bitmapGlyphPng(0, 16),
    );
}

test "public bitmap APIs reject invalid request sizes before table reads" {
    var bytes = emptySbix();
    const font = fixture(&bytes);
    try std.testing.expectEqual(
        @as(?u16, 16),
        try font.bestBitmapStrikePpem(16),
    );

    for ([_]f32{
        0,
        -1,
        std.math.inf(f32),
        std.math.nan(f32),
    }) |size| {
        try std.testing.expectError(
            error.InvalidBitmapSize,
            font.bestBitmapStrikePpem(size),
        );
    }
    try std.testing.expectError(
        error.InvalidBitmapSize,
        font.bitmapGlyphPng(0, 0),
    );
    try std.testing.expectError(
        error.InvalidBitmapSize,
        font.bitmapGlyphPng(0, std.math.nan(f32)),
    );
}

fn fixture(data: []const u8) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.sbix = table_only.record(data, .{ 's', 'b', 'i', 'x' }, 0, data.len);
    return font;
}

fn emptySbix() [40]u8 {
    var bytes: [40]u8 = .{0} ** 40;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 12);
    writeU16(&bytes, 12, 16);
    writeU16(&bytes, 14, 72);
    writeU32(&bytes, 16, 16);
    writeU32(&bytes, 20, 16);
    writeU32(&bytes, 24, 16);
    return bytes;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
