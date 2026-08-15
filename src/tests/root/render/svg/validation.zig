//! Parsed-font SVG table boundary validation.

const std = @import("std");

const support = @import("../../support.zig");
const Font = support.Font;
const writeU16 = support.writeU16Test;
const writeU32 = support.writeU32Test;
const test_font = @import("../../../../test_font.zig");

test "SVG document payload root is validated at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);
    const svg = try tableOffset(bytes, "SVG ");
    const list_offset = readU32(bytes, svg + 2);
    const list = svg + list_offset;
    const document_offset = readU32(bytes, list + 2 + 4);
    bytes[list + document_offset + 1] = 'g';

    try std.testing.expectError(
        error.BadSfnt,
        Font.parse(allocator, bytes),
    );
}

test "SVG document glyph range ordering is enforced at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);
    const svg = try tableOffset(bytes, "SVG ");

    writeU16(bytes, svg, 0);
    writeU32(bytes, svg + 2, 10);
    writeU16(bytes, svg + 10, 2);
    writeU16(bytes, svg + 12, 1);
    writeU16(bytes, svg + 14, 1);
    writeU32(bytes, svg + 16, 26);
    writeU32(bytes, svg + 20, 4);
    writeU16(bytes, svg + 24, 1);
    writeU16(bytes, svg + 26, 1);
    writeU32(bytes, svg + 28, 30);
    writeU32(bytes, svg + 32, 4);

    try std.testing.expectError(
        error.BadSfnt,
        Font.parse(allocator, bytes),
    );
}

test "SVG document byte range overlap is rejected at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);
    const svg = try tableOffset(bytes, "SVG ");

    writeU16(bytes, svg, 0);
    writeU32(bytes, svg + 2, 10);
    writeU16(bytes, svg + 10, 2);
    writeU16(bytes, svg + 12, 0);
    writeU16(bytes, svg + 14, 0);
    writeU32(bytes, svg + 16, 26);
    writeU32(bytes, svg + 20, 8);
    writeU16(bytes, svg + 24, 1);
    writeU16(bytes, svg + 26, 1);
    writeU32(bytes, svg + 28, 30);
    writeU32(bytes, svg + 32, 8);

    try std.testing.expectError(
        error.BadSfnt,
        Font.parse(allocator, bytes),
    );
}

test "SVG header and document length are validated at parse time" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildSvgTtf(allocator);
        defer allocator.free(bytes);
        const svg = try tableOffset(bytes, "SVG ");
        writeU32(bytes, svg + 6, 1);
        try std.testing.expectError(
            error.BadSfnt,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildSvgTtf(allocator);
        defer allocator.free(bytes);
        const svg = try tableOffset(bytes, "SVG ");
        const list = svg + readU32(bytes, svg + 2);
        writeU32(bytes, list + 2 + 8, 0);
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
    const count = std.mem.readInt(u16, bytes[4..6], .big);
    if (count > (bytes.len - 12) / 16) return error.BadSfnt;
    for (0..count) |index| {
        const record = 12 + index * 16;
        if (!std.mem.eql(u8, bytes[record..][0..4], tag)) continue;
        const offset = readU32(bytes, record + 8);
        if (offset > bytes.len) return error.BadSfnt;
        return offset;
    }
    return error.BadSfnt;
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}
