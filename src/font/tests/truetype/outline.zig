//! TrueType outline APIs revalidate caller-owned loca and glyf bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "glyph outline API revalidates borrowed loca and glyf bytes" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const loca_offset = try sfnt_fixture.tableOffset(bytes, "loca");
        // Glyph 0's short loca entry now decreases before glyph 1.
        sfnt_fixture.writeU16(bytes, loca_offset, 7);
        try expectOutlineError(&font, allocator, error.BadSfnt);
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const glyf_offset = try sfnt_fixture.tableOffset(bytes, "glyf");
        // Glyph 0 is not requested. The whole borrowed table must still be
        // authenticated before returning glyph 1 bounds or outline data.
        sfnt_fixture.writeI16(bytes, glyf_offset, 1);
        try expectOutlineError(&font, allocator, error.BadSfnt);
    }
}

test "glyph outline API revalidates borrowed glyf checksum" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var outline = try font.glyphOutline(allocator, 1);
    outline.deinit();

    const glyf_offset = try sfnt_fixture.tableOffset(bytes, "glyf");
    const glyph_one = glyf_offset + 12;
    // Keep the glyph grammar valid while changing its borrowed bounding box.
    // Lazy outline loading must reject bytes no longer covered by the checksum
    // accepted during Font.parse.
    sfnt_fixture.writeI16(bytes, glyph_one + 6, 600);
    try expectOutlineError(&font, allocator, error.BadSfnt);
}

fn expectOutlineError(
    font: *const Font,
    allocator: std.mem.Allocator,
    expected: anyerror,
) !void {
    try std.testing.expectError(expected, font.glyphBounds(1));
    try std.testing.expectError(expected, font.glyphOutline(allocator, 1));
}
