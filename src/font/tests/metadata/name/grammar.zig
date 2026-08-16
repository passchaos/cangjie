//! Focused OpenType name-table grammar and cross-table contracts.

const std = @import("std");
const font_mod = @import("../../../../font.zig");
const name = @import("../../../../opentype/name.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;
const NameId = name.NameId;

test "name table storage offset cannot overlap metadata records" {
    var out: [16]u8 = undefined;

    var format0: [20]u8 = .{0} ** 20;
    fixture.writeU16(&format0, 0, 0);
    fixture.writeU16(&format0, 2, 1);
    fixture.writeU16(&format0, 4, 6); // Points at the first NameRecord, not at string storage.
    support.writeUtf16Record(&format0, 6, 1, 2, 0);
    try std.testing.expectError(error.BadSfnt, name.readString(&format0, support.table(format0.len), @intFromEnum(NameId.family), &out));

    var format1: [28]u8 = .{0} ** 28;
    fixture.writeU16(&format1, 0, 1);
    fixture.writeU16(&format1, 2, 1);
    fixture.writeU16(&format1, 4, 20); // After langTagCount, but still inside the LangTagRecord array.
    support.writeUtf16Record(&format1, 6, 1, 2, 0);
    fixture.writeU16(&format1, 18, 1); // langTagCount
    fixture.writeU16(&format1, 20, 4); // LangTagRecord.length
    fixture.writeU16(&format1, 22, 2); // LangTagRecord.offset
    try std.testing.expectError(error.BadSfnt, name.readString(&format1, support.table(format1.len), @intFromEnum(NameId.family), &out));
}

test "name table format 1 validates language tag storage ranges" {
    var bytes: [32]u8 = .{0} ** 32;
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 1);
    fixture.writeU16(&bytes, 4, 24);
    support.writeUtf16Record(&bytes, 6, 1, 4, 0);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 4);
    fixture.writeU16(&bytes, 22, 4);
    bytes[25] = 'O';
    bytes[27] = 'K';
    bytes[29] = 'e';
    bytes[31] = 'n';

    var out: [16]u8 = undefined;
    try std.testing.expectEqualStrings("OK", (try name.readString(&bytes, support.table(bytes.len), @intFromEnum(NameId.family), &out)).?);

    fixture.writeU16(&bytes, 22, 6);
    try std.testing.expectError(error.BadSfnt, name.readString(&bytes, support.table(bytes.len), @intFromEnum(NameId.family), &out));
}

test "single-byte name strings must decode to UTF-8 ASCII" {
    var bytes: [21]u8 = .{0} ** 21;
    fixture.writeU16(&bytes, 0, 0);
    fixture.writeU16(&bytes, 2, 1);
    fixture.writeU16(&bytes, 4, 18);
    support.writeRecord(&bytes, 6, 1, 0, 0, @intFromEnum(NameId.family), 3, 0);
    bytes[18] = 'M';
    bytes[19] = 'a';
    bytes[20] = 'c';

    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings("Mac", (try name.readString(&bytes, support.table(bytes.len), @intFromEnum(NameId.family), &out)).?);

    // Platform 1 strings are not intrinsically UTF-8; bytes above ASCII depend
    // on a legacy Macintosh encoding table this API does not implement.
    bytes[19] = 0x8e;
    try std.testing.expectError(error.InvalidName, name.readString(&bytes, support.table(bytes.len), @intFromEnum(NameId.family), &out));
}

test "name table validates every record string at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);
    const name_offset: usize = @intCast(try fixture.tableOffset(bytes, "name"));
    const record = try fixture.nameRecordOffset(bytes, name_offset, @intFromEnum(NameId.typographic_subfamily));
    fixture.writeU16(bytes, record + 8, 1); // UTF-16 name strings must have an even byte length.

    try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
}

test "name table validates every record storage range at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);
    const name_offset: usize = @intCast(try fixture.tableOffset(bytes, "name"));
    const name_length = try fixture.tableLength(bytes, "name");
    const storage_offset = std.mem.readInt(
        u16,
        bytes[name_offset + 4 ..][0..2],
        .big,
    );
    const storage_length = name_length - storage_offset;
    const record = try fixture.nameRecordOffset(bytes, name_offset, @intFromEnum(NameId.postscript_name));
    fixture.writeU16(bytes, record + 10, @intCast(storage_length)); // Non-empty record starts just past storage.

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "name table rejects invalid platform encodings at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);
    const name_offset: usize = @intCast(try fixture.tableOffset(bytes, "name"));
    const record = try fixture.nameRecordOffset(bytes, name_offset, @intFromEnum(NameId.family));
    fixture.writeU16(bytes, record, 5); // OpenType name tables only define platform IDs 0 through 4.

    try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
}

test "name table records must be sorted by complete key" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildNamedTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildNamedTtf(allocator);
        defer allocator.free(bytes);
        const name_offset: usize = @intCast(try fixture.tableOffset(bytes, "name"));
        const subfamily = try fixture.nameRecordOffset(bytes, name_offset, @intFromEnum(NameId.subfamily));
        // Duplicate platform/encoding/language/nameID tuples are ambiguous:
        // two records would have the same lookup score, so the returned string
        // would depend on table order rather than a stable OpenType key.
        fixture.writeU16(bytes, subfamily + 6, @intFromEnum(NameId.family));
        try fixture.updateTableChecksum(bytes, "name");

        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtf(allocator);
        defer allocator.free(bytes);
        const name_offset: usize = @intCast(try fixture.tableOffset(bytes, "name"));
        const family = try fixture.nameRecordOffset(bytes, name_offset, @intFromEnum(NameId.family));
        const subfamily = try fixture.nameRecordOffset(bytes, name_offset, @intFromEnum(NameId.subfamily));
        // Reordering keys without changing storage still leaves every string
        // individually valid. The directory itself is malformed because nameID
        // 2 appears before nameID 1 for the same platform/encoding/language.
        fixture.writeU16(bytes, family + 6, @intFromEnum(NameId.subfamily));
        fixture.writeU16(bytes, subfamily + 6, @intFromEnum(NameId.family));
        try fixture.updateTableChecksum(bytes, "name");

        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }
}

test "PostScript name strings validate FontName syntax" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "CangjieSans-Regular");
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var out: [64]u8 = undefined;
        try std.testing.expectEqualStrings("CangjieSans-Regular", (try font.nameString(.postscript_name, &out)).?);
    }

    {
        const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "Bad Name");
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var out: [64]u8 = undefined;
        try std.testing.expectError(error.InvalidName, font.nameString(.postscript_name, &out));
    }

    {
        const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "Bad/Name");
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var out: [64]u8 = undefined;
        try std.testing.expectError(error.InvalidName, font.nameString(.postscript_name, &out));
    }
}

test "name table format 1 language ids reference valid UTF-16 language tags" {
    var bytes: [32]u8 = .{0} ** 32;
    fixture.writeU16(&bytes, 0, 1); // format 1 name table.
    fixture.writeU16(&bytes, 2, 1);
    fixture.writeU16(&bytes, 4, 24);
    support.writeRecord(&bytes, 6, 3, 1, 0x8000, 1, 4, 0);
    fixture.writeU16(&bytes, 18, 1); // one LangTagRecord.
    fixture.writeU16(&bytes, 20, 4);
    fixture.writeU16(&bytes, 22, 4);
    bytes[25] = 'O';
    bytes[27] = 'K';
    bytes[29] = 'e';
    bytes[31] = 'n';

    try name.validate(&bytes, support.table(bytes.len));

    var bad_language_id = bytes;
    fixture.writeU16(&bad_language_id, 10, 0x8001);
    try std.testing.expectError(error.BadSfnt, name.validate(&bad_language_id, support.table(bad_language_id.len)));

    var bad_language_tag = bytes;
    fixture.writeU16(&bad_language_tag, 20, 3);
    try std.testing.expectError(error.InvalidName, name.validate(&bad_language_tag, support.table(bad_language_tag.len)));
}

test "name table format 1 validates language tag syntax" {
    var bytes: [36]u8 = .{0} ** 36;
    fixture.writeU16(&bytes, 0, 1); // format 1 name table.
    fixture.writeU16(&bytes, 2, 1);
    fixture.writeU16(&bytes, 4, 24);
    support.writeRecord(&bytes, 6, 3, 1, 0x8000, @intFromEnum(NameId.family), 2, 0);
    fixture.writeU16(&bytes, 18, 1); // one LangTagRecord.
    fixture.writeU16(&bytes, 20, 10);
    fixture.writeU16(&bytes, 22, 2);
    bytes[25] = 'A';
    bytes[27] = 'e';
    bytes[29] = 'n';
    bytes[31] = '-';
    bytes[33] = 'U';
    bytes[35] = 'S';

    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings("A", (try name.readString(&bytes, support.table(bytes.len), @intFromEnum(NameId.family), &out)).?);

    var underscore = bytes;
    underscore[31] = '_';
    try std.testing.expectError(error.InvalidName, name.validate(&underscore, support.table(underscore.len)));

    var trailing_separator = bytes;
    trailing_separator[33] = 0;
    trailing_separator[35] = '-';
    try std.testing.expectError(error.InvalidName, name.validate(&trailing_separator, support.table(trailing_separator.len)));

    var single_primary = bytes;
    fixture.writeU16(&single_primary, 20, 2);
    single_primary[25] = 'x';
    try std.testing.expectError(error.InvalidName, name.validate(&single_primary, support.table(single_primary.len)));

    var numeric_primary = bytes;
    numeric_primary[27] = '1';
    try std.testing.expectError(error.InvalidName, name.validate(&numeric_primary, support.table(numeric_primary.len)));
}
