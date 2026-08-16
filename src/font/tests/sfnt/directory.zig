//! SFNT offset-table, directory, range, padding, and checksum contracts.

const std = @import("std");
const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const fixture = @import("../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;

test "SFNT table payload ranges cannot overlap metadata or each other" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try support.setTableOffset(bytes, "kern", 12);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try support.setTableOffset(
            bytes,
            "kern",
            @intCast(try fixture.tableOffset(bytes, "head")),
        );
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory rejects duplicate tags" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    try fixture.setTableTag(bytes, "kern", "head");
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SFNT offset table search parameters must match table count" {
    const allocator = std.testing.allocator;
    inline for (.{ 6, 8, 10 }) |offset| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        fixture.writeU16(bytes, offset, readU16(bytes, offset) + 1);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory tags must be strictly sorted" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const first = 12;
    const second = 28;
    var first_tag: [4]u8 = undefined;
    var second_tag: [4]u8 = undefined;
    @memcpy(&first_tag, bytes[first..][0..4]);
    @memcpy(&second_tag, bytes[second..][0..4]);
    @memcpy(bytes[first..][0..4], &second_tag);
    @memcpy(bytes[second..][0..4], &first_tag);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SFNT table directory rejects non-printable tags" {
    const allocator = std.testing.allocator;
    inline for (.{ 0x1f, 0x7f, 0x80 }) |byte| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        bytes[12] = byte;
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory offsets must be long aligned" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    try support.setTableOffset(
        bytes,
        "cmap",
        @intCast(try fixture.tableOffset(bytes, "cmap") + 1),
    );
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SFNT table padding bytes must be zero" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const offset = try fixture.tableOffset(bytes, "head");
    const length = try fixture.tableLength(bytes, "head");
    try std.testing.expectEqual(@as(usize, 2), (4 - (length & 3)) & 3);
    bytes[offset + length] = 0x7f;
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SFNT table directory checksums match borrowed table bytes" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const offset = try fixture.tableOffset(bytes, "hhea");
        bytes[offset + 4] +%= 1;
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const offset = try fixture.tableOffset(bytes, "head");
        fixture.writeU32(bytes, offset + 8, 0xffff_ffff);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
        bytes[offset + 18] +%= 1;
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .big);
}
