//! Style matching revalidates caller-owned OS/2 metadata.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

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
