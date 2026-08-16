//! Style matching revalidates caller-owned OS/2 metadata.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");
const table_only = @import("../fixtures/table_only.zig");

const Font = font_mod.Font;

test "OS/2 style attributes revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const bytes = try styledFont(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectRegularStyle(&font);

    const os2_offset = try sfnt_fixture.tableOffset(bytes, "OS/2");
    sfnt_fixture.writeU16(bytes, os2_offset + 6, 10);
    try std.testing.expectError(error.BadSfnt, font.styleAttributes());

    sfnt_fixture.writeU16(bytes, os2_offset + 6, 5);
    sfnt_fixture.writeU16(bytes, os2_offset + 62, 0x0060);
    try std.testing.expectError(error.BadSfnt, font.styleAttributes());
}

test "OS/2 style attributes revalidate borrowed table checksum" {
    const allocator = std.testing.allocator;
    const bytes = try styledFont(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectRegularStyle(&font);

    const os2_offset = try sfnt_fixture.tableOffset(bytes, "OS/2");
    // Weight 500 is valid by itself, but the table no longer matches the SFNT
    // checksum accepted when this borrowed Font was parsed.
    sfnt_fixture.writeU16(bytes, os2_offset + 4, 500);
    try std.testing.expectError(error.BadSfnt, font.styleAttributes());
}

test "OS/2 style attributes respect versioned table lengths" {
    var valid_v4: [96]u8 = .{0} ** 96;
    sfnt_fixture.writeU16(&valid_v4, 0, 4);
    sfnt_fixture.writeU16(&valid_v4, 4, 650);
    sfnt_fixture.writeU16(&valid_v4, 6, 3);
    sfnt_fixture.writeU16(&valid_v4, 62, 0x0021);

    const valid = os2Font(&valid_v4, valid_v4.len);
    const attributes = try valid.styleAttributes();
    try std.testing.expectEqual(@as(u16, 650), attributes.weight);
    try std.testing.expectEqual(@as(u16, 3), attributes.width);
    try std.testing.expect(attributes.italic);
    try std.testing.expect(attributes.bold);

    try std.testing.expectError(
        error.BadSfnt,
        os2Font(&valid_v4, 64).styleAttributes(),
    );

    var valid_v5: [100]u8 = .{0} ** 100;
    sfnt_fixture.writeU16(&valid_v5, 0, 5);
    sfnt_fixture.writeU16(&valid_v5, 4, 400);
    sfnt_fixture.writeU16(&valid_v5, 6, 5);
    try std.testing.expectError(
        error.BadSfnt,
        os2Font(&valid_v5, 96).styleAttributes(),
    );
}

test "OS/2 table is validated at parse time" {
    const allocator = std.testing.allocator;
    {
        const bytes = try styledFont(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }
    {
        const bytes = try test_font.buildNamedTtfWithStyle(
            allocator,
            "Metric Sans",
            "Wide",
            "Metric Sans Wide",
            400,
            10,
            false,
            false,
        );
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
    {
        const bytes = try test_font.buildNamedTtfWithStyle(
            allocator,
            "Metric Sans",
            "Broken",
            "Metric Sans Broken",
            0,
            5,
            false,
            false,
        );
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
    {
        const bytes = try styledFont(allocator);
        defer allocator.free(bytes);
        try sfnt_fixture.setTableLength(bytes, "OS/2", 64);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
    {
        const bytes = try styledFont(allocator);
        defer allocator.free(bytes);
        const offset = try sfnt_fixture.tableOffset(bytes, "OS/2");
        sfnt_fixture.writeU16(bytes, offset + 62, 0x0400);
        try sfnt_fixture.updateTableChecksum(bytes, "OS/2");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const attributes = try font.styleAttributes();
        try std.testing.expect(!attributes.italic);
        try std.testing.expect(!attributes.bold);
    }
    {
        const bytes = try test_font.buildNamedTtfWithStyle(
            allocator,
            "Metric Sans",
            "Bold",
            "Metric Sans Bold",
            700,
            5,
            false,
            true,
        );
        defer allocator.free(bytes);
        const offset = try sfnt_fixture.tableOffset(bytes, "OS/2");
        sfnt_fixture.writeU16(bytes, offset + 62, 0x0060);
        try sfnt_fixture.updateTableChecksum(bytes, "OS/2");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expect((try font.styleAttributes()).bold);
    }
}

fn styledFont(allocator: std.mem.Allocator) ![]u8 {
    return test_font.buildNamedTtfWithStyle(
        allocator,
        "Metric Sans",
        "Regular",
        "Metric Sans Regular",
        400,
        5,
        false,
        false,
    );
}

fn expectRegularStyle(font: *const Font) !void {
    const attributes = try font.styleAttributes();
    try std.testing.expectEqual(@as(u16, 400), attributes.weight);
    try std.testing.expectEqual(@as(u16, 5), attributes.width);
}

fn os2Font(data: []const u8, declared_length: usize) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.os2 = table_only.record(
        data,
        .{ 'O', 'S', '/', '2' },
        0,
        declared_length,
    );
    return font;
}
