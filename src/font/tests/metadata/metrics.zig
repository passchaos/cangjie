//! Decoration and script metrics expose validated, scalable font metadata.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;
const MetricSource = font_mod.FontDecorationMetricSource;

test "font decoration metrics prefer post underline and OS/2 strikeout" {
    const allocator = std.testing.allocator;
    var post: [32]u8 = .{0} ** 32;
    sfnt_fixture.writeU32(&post, 0, 0x00030000);
    sfnt_fixture.writeI16(&post, 8, -125);
    sfnt_fixture.writeI16(&post, 10, 45);

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const metrics = try font.decorationMetrics();
    try std.testing.expectEqual(MetricSource.font, metrics.underline_source);
    try std.testing.expectEqual(
        @as(i16, -125),
        metrics.underline_position,
    );
    try std.testing.expectEqual(
        @as(i16, 45),
        metrics.underline_thickness,
    );
    try std.testing.expectEqual(
        MetricSource.fallback,
        metrics.strikeout_source,
    );
    try std.testing.expect(metrics.strikeout_thickness > 0);

    const scaled = try font.scaledDecorationMetrics(20);
    try std.testing.expectApproxEqAbs(
        @as(f32, -2.5),
        scaled.underline_position,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.9),
        scaled.underline_thickness,
        0.001,
    );
}

test "font decoration metrics read OS/2 strikeout and fallback invalid underline" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedTtfWithStyle(
        allocator,
        "Metric Sans",
        "Regular",
        "Metric Sans Regular",
        400,
        5,
        false,
        false,
    );
    defer allocator.free(bytes);

    const os2_offset = try sfnt_fixture.tableOffset(bytes, "OS/2");
    sfnt_fixture.writeI16(bytes, os2_offset + 26, 70);
    sfnt_fixture.writeI16(bytes, os2_offset + 28, 330);
    try sfnt_fixture.updateTableChecksum(bytes, "OS/2");

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const metrics = try font.decorationMetrics();
    try std.testing.expectEqual(
        MetricSource.fallback,
        metrics.underline_source,
    );
    try std.testing.expectEqual(
        MetricSource.font,
        metrics.strikeout_source,
    );
    try std.testing.expectEqual(
        @as(i16, 330),
        metrics.strikeout_position,
    );
    try std.testing.expectEqual(
        @as(i16, 70),
        metrics.strikeout_thickness,
    );
}

test "font script metrics read OS/2 superscript and subscript values" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildScriptMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const metrics = (try font.scriptMetrics()) orelse
        return error.MissingScriptMetrics;
    try std.testing.expectEqual(@as(i16, 640), metrics.superscript_x_size);
    try std.testing.expectEqual(@as(i16, 630), metrics.superscript_y_size);
    try std.testing.expectEqual(@as(i16, 13), metrics.superscript_x_offset);
    try std.testing.expectEqual(@as(i16, 360), metrics.superscript_y_offset);
    try std.testing.expectEqual(@as(i16, 620), metrics.subscript_x_size);
    try std.testing.expectEqual(@as(i16, 610), metrics.subscript_y_size);
    try std.testing.expectEqual(@as(i16, 11), metrics.subscript_x_offset);
    try std.testing.expectEqual(@as(i16, 140), metrics.subscript_y_offset);

    const scaled = (try font.scaledScriptMetrics(20)) orelse
        return error.MissingScaledScriptMetrics;
    try expectApprox(12.8, scaled.superscript_x_size);
    try expectApprox(12.6, scaled.superscript_y_size);
    try expectApprox(0.26, scaled.superscript_x_offset);
    try expectApprox(7.2, scaled.superscript_y_offset);
    try expectApprox(12.4, scaled.subscript_x_size);
    try expectApprox(12.2, scaled.subscript_y_size);
    try expectApprox(0.22, scaled.subscript_x_offset);
    try expectApprox(2.8, scaled.subscript_y_offset);
}

test "font script metrics handle missing and mutated OS/2 tables" {
    const allocator = std.testing.allocator;

    const minimal = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(minimal);
    var minimal_font = try Font.parse(allocator, minimal);
    defer minimal_font.deinit();
    try std.testing.expect((try minimal_font.scriptMetrics()) == null);

    const bytes = try test_font.buildScriptMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    _ = try font.scriptMetrics();

    const os2_offset = try sfnt_fixture.tableOffset(bytes, "OS/2");
    sfnt_fixture.writeI16(bytes, os2_offset + 20, 631);
    try std.testing.expectError(error.BadSfnt, font.scriptMetrics());
}

test "font decoration metrics revalidate borrowed table checksums" {
    const allocator = std.testing.allocator;
    var post: [32]u8 = .{0} ** 32;
    sfnt_fixture.writeU32(&post, 0, 0x00030000);
    sfnt_fixture.writeI16(&post, 8, -100);
    sfnt_fixture.writeI16(&post, 10, 40);

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    _ = try font.decorationMetrics();

    const post_offset = try sfnt_fixture.tableOffset(bytes, "post");
    sfnt_fixture.writeI16(bytes, post_offset + 10, 41);
    try std.testing.expectError(
        error.BadSfnt,
        font.decorationMetrics(),
    );
}

fn expectApprox(expected: f32, actual: f32) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 0.001);
}
