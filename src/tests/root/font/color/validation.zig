//! Parse-boundary validation for modern OpenType color tables.

const std = @import("std");

const support = @import("../../support.zig");
const Font = support.Font;
const writeI16 = support.writeI16Test;
const writeU16 = support.writeU16Test;
const writeU32 = support.writeU32Test;
const test_font = @import("../../../../test_font.zig");

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
