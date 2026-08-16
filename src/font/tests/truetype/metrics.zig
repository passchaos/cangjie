//! TrueType metric APIs revalidate caller-owned metric headers and payloads.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;
const VerticalMetrics = font_mod.VerticalMetrics;

test "vertical table and adjusted metrics share one concrete value type" {
    try std.testing.expect(
        font_mod.VerticalMetricInfo == font_mod.VerticalMetrics,
    );
}

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

test "metric headers expose decoded horizontal and vertical metadata" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const header = try font.horizontalHeaderInfo();
        try std.testing.expectEqual(@as(u32, 0x00010000), header.version);
        try std.testing.expectEqual(@as(i16, 800), header.ascender);
        try std.testing.expectEqual(@as(i16, -200), header.descender);
        try std.testing.expectEqual(@as(u16, 2), header.long_metric_count);
        try std.testing.expect((try font.verticalHeaderInfo()) == null);
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const header = (try font.verticalHeaderInfo()).?;
        try std.testing.expectEqual(@as(u32, 0x00011000), header.version);
        try std.testing.expectEqual(@as(u16, 1), header.long_metric_count);
    }
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

test "shaping vertical origin falls back when deployed vertical metrics are unusable" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    const vhea_offset = try sfnt_fixture.tableOffset(bytes, "vhea");
    writeInvalidLineAdvance(bytes, vhea_offset);
    try sfnt_fixture.updateTableChecksum(bytes, "vhea");
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(1));
    const origin = try font_mod.shaping.shapingVerticalOriginYForShaping(
        &font,
        1,
        &.{},
    );
    try std.testing.expect(origin > font.descender);
}

test "metric table contracts reject malformed headers and payload lengths" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try sfnt_fixture.setTableLength(bytes, "hhea", 34);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try sfnt_fixture.setTableLength(bytes, "hmtx", 6);
        try std.testing.expectError(
            error.InvalidMetrics,
            Font.parse(allocator, bytes),
        );
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const hhea_offset = try sfnt_fixture.tableOffset(bytes, "hhea");
        writeInvalidLineAdvance(bytes, hhea_offset);
        try sfnt_fixture.updateTableChecksum(bytes, "hhea");
        try std.testing.expectError(
            error.InvalidMetrics,
            Font.parse(allocator, bytes),
        );
    }

    {
        const original = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(original);
        const bytes = try allocator.alloc(u8, original.len + 4);
        defer allocator.free(bytes);
        @memcpy(bytes[0..original.len], original);
        @memset(bytes[original.len..], 0);
        try sfnt_fixture.setTableLength(bytes, "hhea", 37);
        try sfnt_fixture.updateTableChecksum(bytes, "hhea");
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try sfnt_fixture.setTableLength(bytes, "vmtx", 4);
        try sfnt_fixture.updateTableChecksum(bytes, "vmtx");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidMetrics,
            font.verticalMetrics(1),
        );
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset = try sfnt_fixture.tableOffset(bytes, "vhea");
        sfnt_fixture.writeU16(bytes, vhea_offset + 34, 0);
        try sfnt_fixture.updateTableChecksum(bytes, "vhea");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidMetrics,
            font.verticalMetrics(0),
        );
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset = try sfnt_fixture.tableOffset(bytes, "vhea");
        sfnt_fixture.writeU16(bytes, vhea_offset + 34, 3);
        try sfnt_fixture.updateTableChecksum(bytes, "vhea");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidMetrics,
            font.verticalMetrics(0),
        );
    }

    inline for (.{
        .{ .old_tag = "vmtx", .new_tag = "zzzz" },
        .{ .old_tag = "vhea", .new_tag = "vhdz" },
    }) |case| {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try sfnt_fixture.setTableTag(
            bytes,
            case.old_tag,
            case.new_tag,
        );
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(
            error.InvalidMetrics,
            font.verticalMetrics(0),
        );
    }
}

test "metric header APIs revalidate borrowed checksums" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const hhea_offset = try sfnt_fixture.tableOffset(bytes, "hhea");
        bytes[hhea_offset] +%= 1;
        try std.testing.expectError(error.BadSfnt, font.horizontalHeaderInfo());
        try std.testing.expectError(
            error.InvalidMetrics,
            font.horizontalMetricsTable(allocator),
        );
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const vhea_offset = try sfnt_fixture.tableOffset(bytes, "vhea");
        bytes[vhea_offset] +%= 1;
        try std.testing.expectError(error.BadSfnt, font.verticalHeaderInfo());
        try std.testing.expectError(
            error.InvalidMetrics,
            font.verticalMetricsTable(allocator),
        );
    }
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
