//! Name-string lookups revalidate caller-owned `name` table bytes.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;
const NameId = font_mod.NameId;

test "lazy PostScript name lookup revalidates borrowed bytes" {
    const allocator = std.testing.allocator;
    const bytes = try namedFont(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings(
        "CangjieSans-Regular",
        (try font.nameString(.postscript_name, &out)).?,
    );

    const name_offset = try sfnt_fixture.tableOffset(bytes, "name");
    const string_offset = try absoluteStringOffset(
        bytes,
        name_offset,
        .postscript_name,
    );
    // UTF-16BE stores ASCII in every low byte. Introducing a space keeps the
    // encoding valid but violates PostScript FontName syntax.
    bytes[string_offset + 1] = ' ';
    try std.testing.expectError(
        error.BadSfnt,
        font.nameString(.postscript_name, &out),
    );
}

test "lazy name lookup revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const bytes = try namedFont(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings(
        "Cangjie Sans",
        (try font.nameString(.family, &out)).?,
    );

    const name_offset = try sfnt_fixture.tableOffset(bytes, "name");
    const string_offset = try absoluteStringOffset(
        bytes,
        name_offset,
        .family,
    );
    // Keep UTF-16BE well formed while changing user-facing metadata.
    bytes[string_offset + 1] = 'D';
    try std.testing.expectError(
        error.BadSfnt,
        font.nameString(.family, &out),
    );
}

fn namedFont(allocator: std.mem.Allocator) ![]u8 {
    return test_font.buildNamedTtfWithPostScript(
        allocator,
        "Cangjie Sans",
        "Regular",
        "Cangjie Sans Regular",
        "CangjieSans-Regular",
    );
}

fn absoluteStringOffset(
    bytes: []const u8,
    name_offset: usize,
    name_id: NameId,
) !usize {
    const record = try sfnt_fixture.nameRecordOffset(
        bytes,
        name_offset,
        @intFromEnum(name_id),
    );
    const storage_offset = readU16(bytes, name_offset + 4);
    const relative_string_offset = readU16(bytes, record + 10);
    return name_offset + storage_offset + relative_string_offset;
}

fn readU16(bytes: []const u8, offset: usize) usize {
    return std.mem.readInt(u16, bytes[offset..][0..2], .big);
}
