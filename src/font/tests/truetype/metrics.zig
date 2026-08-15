//! TrueType metric APIs revalidate caller-owned metric headers and payloads.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;
const VerticalMetrics = font_mod.VerticalMetrics;

test "horizontal metrics revalidate borrowed hhea bytes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectHorizontalAdvance(&font, 800);

    const hhea_offset = try sfnt_fixture.tableOffset(bytes, "hhea");
    // Reserved hhea fields must remain zero after parse.
    sfnt_fixture.writeU16(bytes, hhea_offset + 24, 1);
    try std.testing.expectError(
        error.InvalidMetrics,
        font.horizontalMetrics(1),
    );

    sfnt_fixture.writeU16(bytes, hhea_offset + 24, 0);
    writeInvalidLineAdvance(bytes, hhea_offset);
    try std.testing.expectError(
        error.InvalidMetrics,
        font.horizontalMetrics(1),
    );

    writeCanonicalLineMetrics(bytes, hhea_offset);
    // The payload was encoded for two long metrics. Reinterpreting it as one
    // long metric plus one compressed bearing leaves unauthenticated trailing
    // bytes and must not silently change the table's logical layout.
    sfnt_fixture.writeU16(bytes, hhea_offset + 34, 1);
    try std.testing.expectError(
        error.InvalidMetrics,
        font.horizontalMetrics(1),
    );
}

test "horizontal metrics revalidate borrowed hmtx checksum" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectHorizontalAdvance(&font, 800);

    const hmtx_offset = try sfnt_fixture.tableOffset(bytes, "hmtx");
    // Length and metric count remain valid, but the returned advance would no
    // longer be one of the values authenticated by Font.parse.
    sfnt_fixture.writeU16(bytes, hmtx_offset + 4, 700);
    try std.testing.expectError(
        error.BadSfnt,
        font.horizontalMetrics(1),
    );
}

test "vertical metrics revalidate borrowed vmtx checksum" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const initial = (try font.verticalMetrics(0)).?;
    try std.testing.expectEqual(@as(u16, 1000), initial.advance_height);

    const vmtx_offset = try sfnt_fixture.tableOffset(bytes, "vmtx");
    sfnt_fixture.writeU16(bytes, vmtx_offset, 900);
    try std.testing.expectError(error.BadSfnt, font.verticalMetrics(0));
}

test "vertical metrics API revalidates borrowed vhea and vmtx bytes" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expect(font.hasVerticalMetrics());
    try expectVerticalMetric(&font, 0);
    try expectVerticalMetric(&font, 1);
    try std.testing.expectError(error.InvalidGlyph, font.verticalMetrics(2));

    const vhea_offset = try sfnt_fixture.tableOffset(bytes, "vhea");
    // Reserved vhea fields must remain zero after parse.
    sfnt_fixture.writeU16(bytes, vhea_offset + 24, 1);
    try std.testing.expectError(
        error.InvalidMetrics,
        font.verticalMetrics(1),
    );

    sfnt_fixture.writeU16(bytes, vhea_offset + 24, 0);
    writeInvalidLineAdvance(bytes, vhea_offset);
    try std.testing.expectError(
        error.InvalidMetrics,
        font.verticalMetrics(1),
    );

    writeCanonicalLineMetrics(bytes, vhea_offset);
    // The borrowed vmtx table contains only one full metric.
    sfnt_fixture.writeU16(bytes, vhea_offset + 34, 2);
    try std.testing.expectError(
        error.InvalidMetrics,
        font.verticalMetrics(1),
    );
}

test "vertical metrics API reports absence without requiring vertical tables" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expect(!font.hasVerticalMetrics());
    try std.testing.expectEqual(
        @as(?VerticalMetrics, null),
        try font.verticalMetrics(0),
    );
}

fn expectHorizontalAdvance(font: *const Font, expected: u16) !void {
    const metrics = try font.horizontalMetrics(1);
    try std.testing.expectEqual(expected, metrics.advance_width);
}

fn expectVerticalMetric(font: *const Font, glyph_id: u16) !void {
    const metrics = (try font.verticalMetrics(glyph_id)).?;
    try std.testing.expectEqual(@as(u16, 1000), metrics.advance_height);
    try std.testing.expectEqual(@as(i16, 0), metrics.top_side_bearing);
}

fn writeInvalidLineAdvance(bytes: []u8, offset: usize) void {
    sfnt_fixture.writeI16(bytes, offset + 4, 100);
    sfnt_fixture.writeI16(bytes, offset + 6, 200);
    sfnt_fixture.writeI16(bytes, offset + 8, 100);
}

fn writeCanonicalLineMetrics(bytes: []u8, offset: usize) void {
    sfnt_fixture.writeI16(bytes, offset + 4, 800);
    sfnt_fixture.writeI16(bytes, offset + 6, -200);
    sfnt_fixture.writeI16(bytes, offset + 8, 0);
}
