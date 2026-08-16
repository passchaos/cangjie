//! Font-owned kern lifecycle and source-level API contracts.

const std = @import("std");

const font_mod = @import("../../../../font.zig");
const test_font = @import("../../../../test_font.zig");
const sfnt_fixture = @import("../../fixtures/sfnt.zig");
const kern = @import("../../../tables/kerning/kern/root.zig");

const Font = font_mod.Font;

test "public kern metadata aliases concrete module types" {
    try std.testing.expect(font_mod.KernTableDialect == kern.Dialect);
    try std.testing.expect(font_mod.KernSubtableInfo == kern.Subtable);
    try std.testing.expect(font_mod.KernInfo == kern.Info);
}

test "Font kern rejects invalid public glyph ids" {
    var data = legacyTable();
    const font = tableOnlyFont(&data);
    try std.testing.expectError(error.InvalidGlyph, font.kerning(2, 1));
    try std.testing.expectError(error.InvalidGlyph, font.kerning(1, 2));
}

test "Font kern revalidates borrowed pair arrays and checksum" {
    const allocator = std.testing.allocator;
    var table = legacyTable();
    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &table);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(i16, -40), try font.kerning(1, 1));

    const offset = try sfnt_fixture.tableOffset(bytes, "kern");
    sfnt_fixture.writeU16(bytes, offset + 20, 2);
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));

    sfnt_fixture.writeU16(bytes, offset + 20, 1);
    sfnt_fixture.writeI16(bytes, offset + 22, -20);
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
}

test "Font kern revalidates borrowed format 0 search metadata" {
    const allocator = std.testing.allocator;
    var table = legacyTable();
    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &table);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(i16, -40), try font.kerning(1, 1));

    const offset = try sfnt_fixture.tableOffset(bytes, "kern");
    sfnt_fixture.writeU16(bytes, offset + 14, 1);
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
}

test "Font parse validates Apple kern pair glyph ids" {
    const allocator = std.testing.allocator;
    var table: [31]u8 = .{0} ** 31;
    sfnt_fixture.writeU32(&table, 0, 0x00010000);
    sfnt_fixture.writeU32(&table, 4, 1);
    sfnt_fixture.writeU32(&table, 8, 23);
    sfnt_fixture.writeU16(&table, 16, 1);
    sfnt_fixture.writeU16(&table, 18, 6);
    sfnt_fixture.writeU16(&table, 24, 1);
    sfnt_fixture.writeU16(&table, 26, 2);
    sfnt_fixture.writeI16(&table, 28, -35);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &table);
    defer allocator.free(bytes);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

fn legacyTable() [24]u8 {
    var data: [24]u8 = .{0} ** 24;
    sfnt_fixture.writeU16(&data, 2, 1);
    sfnt_fixture.writeU16(&data, 6, 20);
    sfnt_fixture.writeU16(&data, 8, 1);
    sfnt_fixture.writeU16(&data, 10, 1);
    sfnt_fixture.writeU16(&data, 12, 6);
    sfnt_fixture.writeU16(&data, 18, 1);
    sfnt_fixture.writeU16(&data, 20, 1);
    sfnt_fixture.writeI16(&data, 22, -40);
    return data;
}

fn tableOnlyFont(data: []const u8) Font {
    const fixture = @import("../../fixtures/table_only.zig");
    var font = fixture.init(Font, data, 2, 2);
    font.kern = fixture.record(
        data,
        .{ 'k', 'e', 'r', 'n' },
        0,
        data.len,
    );
    return font;
}
