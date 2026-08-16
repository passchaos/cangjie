//! Public `post` metadata and glyph-name format integration contracts.

const std = @import("std");

const font_mod = @import("../../../../font.zig");
const test_font = @import("../../../../test_font.zig");
const sfnt_fixture = @import("../../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "post table structural contracts are validated at parse time" {
    const allocator = std.testing.allocator;

    {
        var post = postTable(32, 0x00030000);
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const info = (try font.postInfo()).?;
        try std.testing.expectEqual(@as(u32, 0x00030000), info.format);
        try std.testing.expectEqual(@as(?u16, null), info.glyph_name_count);
    }

    {
        var post = postTable(44, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 2);
        sfnt_fixture.writeU16(&post, 34, 0);
        sfnt_fixture.writeU16(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "A.alt");
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const info = (try font.postInfo()).?;
        try std.testing.expectEqual(@as(?u16, 2), info.glyph_name_count);
    }

    {
        var post = postTable(36, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 3);
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(42, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 2);
        sfnt_fixture.writeU16(&post, 34, 0);
        sfnt_fixture.writeU16(&post, 36, 258);
        post[38] = 4;
        @memcpy(post[39..42], "Alt");
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(46, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 2);
        sfnt_fixture.writeU16(&post, 34, 0);
        sfnt_fixture.writeU16(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "A.alt");
        post[44] = 1;
        post[45] = 'B';
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(44, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 2);
        sfnt_fixture.writeU16(&post, 34, 0);
        sfnt_fixture.writeU16(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "bad/-");
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        // Optional custom text does not invalidate otherwise usable outlines,
        // metrics, or shaping, but the dedicated public accessor remains strict.
        _ = try font.postInfo();
        _ = try font.decorationMetrics();
        try std.testing.expectError(error.BadSfnt, font.glyphName(1));
    }

    {
        var post = postTable(39, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 2);
        sfnt_fixture.writeU16(&post, 34, 0);
        sfnt_fixture.writeU16(&post, 36, 258);
        post[38] = 0;
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        // FreeType, FontTools, and HarfBuzz accept this deployed empty-name
        // representation; expose it as absence, not an empty public name.
        try std.testing.expectEqual(
            @as(?[]const u8, null),
            try font.glyphName(1),
        );
    }

    {
        var post = postTable(44, 0x00020000);
        sfnt_fixture.writeU16(&post, 32, 2);
        sfnt_fixture.writeU16(&post, 34, 0);
        sfnt_fixture.writeU16(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "ae-ar");
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectEqualStrings("ae-ar", (try font.glyphName(1)).?);
    }

    {
        var post = postTable(36, 0x00025000);
        sfnt_fixture.writeU16(&post, 32, 2);
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
    }

    {
        var post = postTable(36, 0x00025000);
        sfnt_fixture.writeU16(&post, 32, 2);
        post[34] = 0xff;
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(37, 0x00025000);
        sfnt_fixture.writeU16(&post, 32, 2);
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(36, 0x00040000);
        sfnt_fixture.writeU16(&post, 32, 0xffff);
        sfnt_fixture.writeU16(&post, 34, 'A');
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const info = (try font.postInfo()).?;
        try std.testing.expectEqual(@as(?u16, 2), info.glyph_name_count);
    }

    {
        var post = postTable(38, 0x00040000);
        sfnt_fixture.writeU16(&post, 32, 0xffff);
        sfnt_fixture.writeU16(&post, 34, 'A');
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(34, 0x00040000);
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(32, 0x00010000);
        try expectParseError(allocator, &post);
    }

    {
        var post = postTable(32, 0x00050000);
        try expectParseError(allocator, &post);
    }
}

test "post glyph names support standard aliases and absent-name formats" {
    const allocator = std.testing.allocator;

    {
        var post = postTable(36, 0x00025000);
        sfnt_fixture.writeU16(&post, 32, 2);
        post[34] = 0;
        post[35] = 35;

        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqualStrings(".notdef", (try font.glyphName(0)).?);
        try std.testing.expectEqualStrings("A", (try font.glyphName(1)).?);
    }

    {
        var post = postTable(32, 0x00030000);
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(
            @as(?[]const u8, null),
            try font.glyphName(1),
        );
    }
}

fn postTable(comptime length: usize, format: u32) [length]u8 {
    var table: [length]u8 = .{0} ** length;
    sfnt_fixture.writeU32(&table, 0, format);
    return table;
}

fn expectParseError(
    allocator: std.mem.Allocator,
    post: []const u8,
) !void {
    const bytes = try test_font.buildMinimalTtfWithPost(allocator, post);
    defer allocator.free(bytes);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}
