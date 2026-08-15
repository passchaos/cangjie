//! Public SVG lookups revalidate caller-owned directory and document bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const table_only = @import("../fixtures/table_only.zig");

const Font = font_mod.Font;

test "SVG public document lookup revalidates byte-range ownership" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 0);
    writeU32(&bytes, 2, 10);
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 26);
    writeU32(&bytes, 20, 6);
    writeU16(&bytes, 24, 2);
    writeU16(&bytes, 26, 2);
    writeU32(&bytes, 28, 32);
    writeU32(&bytes, 32, 6);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..48], "<svg/>");

    const font = svgFixture(&bytes);
    const original = (try font.svgGlyphDocument(2)).?;
    try std.testing.expectEqualSlices(u8, "<svg/>", original.data);

    writeU32(&bytes, 28, 30);
    try std.testing.expectError(
        error.BadSfnt,
        font.svgGlyphDocument(2),
    );
}

test "SVG public document lookup revalidates every borrowed XML payload" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16(&bytes, 0, 0);
    writeU32(&bytes, 2, 10);
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 26);
    writeU32(&bytes, 20, 6);
    writeU16(&bytes, 24, 2);
    writeU16(&bytes, 26, 2);
    writeU32(&bytes, 28, 32);
    writeU32(&bytes, 32, 8);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..50], "<svg/>  ");

    const font = svgFixture(&bytes);
    const original = (try font.svgGlyphDocument(1)).?;
    try std.testing.expectEqualSlices(u8, "<svg/>", original.data);

    @memcpy(bytes[42..50], "<g></g> ");
    try std.testing.expectError(
        error.BadSfnt,
        font.svgGlyphDocument(1),
    );

    @memcpy(bytes[42..50], "<svg/>  ");
    @memcpy(bytes[36..42], "<g></>");
    try std.testing.expectError(
        error.BadSfnt,
        font.svgGlyphDocument(1),
    );
}

test "SVG public document lookup revalidates borrowed table checksum" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16(&bytes, 0, 0);
    writeU32(&bytes, 2, 10);
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 14);
    writeU32(&bytes, 20, 8);
    @memcpy(bytes[24..32], "<svg/>  ");

    const font = svgFixture(&bytes);
    const original = (try font.svgGlyphDocument(1)).?;
    try std.testing.expectEqualSlices(u8, "<svg/>  ", original.data);

    // The payload remains valid XML; only the expected table checksum changes.
    bytes[31] = '\n';
    try std.testing.expectError(
        error.BadSfnt,
        font.svgGlyphDocument(1),
    );
}

fn svgFixture(data: []const u8) Font {
    var font = table_only.init(Font, data, 4, 2);
    font.svg = table_only.record(data, .{ 'S', 'V', 'G', ' ' }, 0, data.len);
    return font;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
