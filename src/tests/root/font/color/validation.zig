//! Parse-boundary validation for modern OpenType color tables.

const std = @import("std");

const support = @import("../../support.zig");
const Font = support.Font;
const writeI16 = support.writeI16Test;
const writeU16 = support.writeU16Test;
const writeU32 = support.writeU32Test;
const test_font = @import("../../../../test_font.zig");

test "CPAL palette lookup revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildColorTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const color = (try font.paletteColor(0, 0)).?;
    try std.testing.expectEqual(@as(u8, 255), color.red);

    const cpal = try tableOffset(bytes, "CPAL");
    bytes[cpal + 18] -%= 1;
    try std.testing.expectError(
        error.BadSfnt,
        font.paletteColor(0, 0),
    );
}

test "color APIs reject glyph IDs outside maxp with and without COLR" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildColorTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidGlyph,
            font.colorLayers(allocator, font.glyph_count),
        );
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidGlyph,
            font.colorPaint(font.glyph_count),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidGlyph,
            font.colorLayers(allocator, font.glyph_count),
        );
        try std.testing.expectError(
            error.InvalidGlyph,
            font.colorPaint(font.glyph_count),
        );
    }
}

test "COLR APIs revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildColorTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const layers = try font.colorLayers(allocator, 1);
        defer allocator.free(layers);
        try std.testing.expectEqual(@as(usize, 2), layers.len);

        const colr = try tableOffset(bytes, "COLR");
        // Keep the layer graph semantically valid by selecting the other
        // declared CPAL entry; only the borrowed COLR checksum should fail.
        bytes[colr + 22] +%= 1;
        try std.testing.expectError(
            error.BadSfnt,
            font.colorLayers(allocator, 1),
        );
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expect((try font.colorPaint(1)) != null);

        const colr = try tableOffset(bytes, "COLR");
        // 0x2000 -> 0x2100 remains a legal alpha, isolating checksum
        // revalidation from PaintSolid semantic validation.
        bytes[colr + 47] +%= 1;
        try std.testing.expectError(
            error.BadSfnt,
            font.colorPaint(1),
        );
    }
}

test "COLR palette indices are validated at parse time" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildColorTtf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU16(bytes, colr + 22, 2);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU16(bytes, colr + 45, 2);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1GlyphTtf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU16(bytes, colr + 51, 2);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1LayersTtf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU16(bytes, colr + 80, 2);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }
}

test "COLR v1 reachable Paint formats are validated at parse time" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        bytes[colr + 44] = 0;
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1LayersTtf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        bytes[colr + 73] = 33;
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }
}

test "COLR v1 top-level offsets own distinct non-header payloads" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU32(bytes, colr + 14, 30);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1LayersTtf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU32(bytes, colr + 18, 26);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeU32(bytes, colr + 18, 34);
        writeU32(bytes, colr + 34, 0);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }
}

test "COLR v1 PaintSolid alpha is validated at parse time" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeI16(bytes, colr + 47, -1);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr = try tableOffset(bytes, "COLR");
        writeI16(bytes, colr + 47, 0x4001);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }
}

fn tableOffset(
    bytes: []const u8,
    comptime tag: *const [4]u8,
) error{BadSfnt}!usize {
    if (bytes.len < 12) return error.BadSfnt;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    if (table_count > (bytes.len - 12) / 16) return error.BadSfnt;
    for (0..table_count) |index| {
        const record = 12 + index * 16;
        if (!std.mem.eql(u8, bytes[record..][0..4], tag)) continue;
        const offset = std.mem.readInt(u32, bytes[record + 8 ..][0..4], .big);
        if (offset > bytes.len) return error.BadSfnt;
        return offset;
    }
    return error.BadSfnt;
}
