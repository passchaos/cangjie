//! PostScript glyph-name lookups revalidate caller-owned `post` bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "post glyph names are exposed and revalidated from borrowed bytes" {
    const allocator = std.testing.allocator;
    var post = customPostTable();
    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqualStrings(
        ".notdef",
        (try font.glyphName(0)).?,
    );
    try expectCustomGlyphName(&font, "A.alt");
    try std.testing.expectError(error.InvalidGlyph, font.glyphName(2));

    const post_offset = try sfnt_fixture.tableOffset(bytes, "post");
    // Custom names borrow Pascal strings from the caller's SFNT buffer. The
    // slash makes that name invalid under the public glyph-name contract.
    bytes[post_offset + 43] = '/';
    try std.testing.expectError(error.BadSfnt, font.glyphName(1));
}

test "post glyph names revalidate borrowed table checksum" {
    const allocator = std.testing.allocator;
    var post = customPostTable();
    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectCustomGlyphName(&font, "A.alt");

    const post_offset = try sfnt_fixture.tableOffset(bytes, "post");
    // Keep Pascal-string grammar valid while changing the borrowed name. The
    // table no longer matches the checksum authenticated by Font.parse.
    bytes[post_offset + 39] = 'B';
    try std.testing.expectError(error.BadSfnt, font.glyphName(1));
}

fn customPostTable() [44]u8 {
    var post: [44]u8 = .{0} ** 44;
    sfnt_fixture.writeU32(&post, 0, 0x00020000);
    sfnt_fixture.writeU16(&post, 32, 2);
    sfnt_fixture.writeU16(&post, 34, 0);
    sfnt_fixture.writeU16(&post, 36, 258);
    post[38] = 5;
    @memcpy(post[39..44], "A.alt");
    return post;
}

fn expectCustomGlyphName(font: *const Font, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, (try font.glyphName(1)).?);
}
