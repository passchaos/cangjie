//! STAT public metadata APIs revalidate table structure and cross-table names.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "STAT design axes public API revalidates borrowed metadata" {
    const allocator = std.testing.allocator;
    try expectMissingStatMetadata(allocator);
    try expectStatMetadata(allocator);
    try expectBorrowedNameRevalidation(allocator);
    try expectBorrowedStatChecksumRevalidation(allocator);
    try expectFvarAxisOrderRevalidation(allocator);
}

fn expectMissingStatMetadata(allocator: std.mem.Allocator) !void {
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.statDesignAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 0), axes.len);

    const values = try font.statAxisValues(allocator);
    defer font.freeStatAxisValues(allocator, values);
    try std.testing.expectEqual(@as(usize, 0), values.len);
    try std.testing.expectEqual(
        @as(?u16, null),
        try font.statElidedFallbackNameId(allocator),
    );
}

fn expectStatMetadata(allocator: std.mem.Allocator) !void {
    const bytes = try test_font.buildVariableStatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.statDesignAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqualStrings("wght", &axes[0].tag);
    try std.testing.expectEqual(@as(u16, 256), axes[0].name_id);
    try std.testing.expectEqual(@as(u16, 0), axes[0].ordering);
    try std.testing.expectEqualStrings("wdth", &axes[1].tag);
    try std.testing.expectEqual(@as(u16, 257), axes[1].name_id);
    try std.testing.expectEqual(@as(u16, 1), axes[1].ordering);

    const values = try font.statAxisValues(allocator);
    defer font.freeStatAxisValues(allocator, values);
    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(@as(u16, 1), values[0].format);
    try std.testing.expectEqual(@as(?u16, 0), values[0].axis_index);
    try std.testing.expectEqual(@as(u16, 2), values[0].name_id);
    try std.testing.expectApproxEqAbs(
        @as(f32, 400.0),
        values[0].value.?,
        0.001,
    );
    try std.testing.expectEqual(
        @as(?u16, 2),
        try font.statElidedFallbackNameId(allocator),
    );
}

fn expectBorrowedNameRevalidation(allocator: std.mem.Allocator) !void {
    const bytes = try test_font.buildVariableStatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const name_offset = try sfnt_fixture.tableOffset(bytes, "name");
    const axis_name_record = try sfnt_fixture.nameRecordOffset(
        bytes,
        name_offset,
        256,
    );
    // Keep STAT unchanged so this isolates its borrowed cross-table NameID.
    sfnt_fixture.writeU16(bytes, axis_name_record + 6, 400);
    try std.testing.expectError(
        error.InvalidName,
        font.statDesignAxes(allocator),
    );

    // Restore the axis label before invalidating the NameID shared by the
    // AxisValue and elided-fallback metadata. Each API then fails for its own
    // referenced name rather than an earlier unrelated mutation.
    sfnt_fixture.writeU16(bytes, axis_name_record + 6, 256);
    const value_name_record = try sfnt_fixture.nameRecordOffset(
        bytes,
        name_offset,
        2,
    );
    sfnt_fixture.writeU16(bytes, value_name_record + 6, 401);
    try std.testing.expectError(
        error.InvalidName,
        font.statAxisValues(allocator),
    );
    try std.testing.expectError(
        error.InvalidName,
        font.statElidedFallbackNameId(allocator),
    );
}

fn expectBorrowedStatChecksumRevalidation(
    allocator: std.mem.Allocator,
) !void {
    const bytes = try test_font.buildVariableStatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.statDesignAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(u16, 0), axes[0].ordering);

    const stat_offset = try sfnt_fixture.tableOffset(bytes, "STAT");
    // Ordering 2 remains structurally valid, but the caller-owned STAT bytes no
    // longer match the directory checksum authenticated by Font.parse.
    sfnt_fixture.writeU16(bytes, stat_offset + 26, 2);
    try expectAllStatApisError(&font, allocator, error.BadSfnt);
}

fn expectFvarAxisOrderRevalidation(allocator: std.mem.Allocator) !void {
    const bytes = try test_font.buildVariableStatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const stat_offset = try sfnt_fixture.tableOffset(bytes, "STAT");
    // The second STAT axis no longer follows fvar's axis order.
    @memcpy(bytes[stat_offset + 28 ..][0..4], "opsz");
    try std.testing.expectError(
        error.BadSfnt,
        font.statDesignAxes(allocator),
    );
}

fn expectAllStatApisError(
    font: *const Font,
    allocator: std.mem.Allocator,
    expected: anyerror,
) !void {
    try std.testing.expectError(
        expected,
        font.statDesignAxes(allocator),
    );
    try std.testing.expectError(
        expected,
        font.statAxisValues(allocator),
    );
    try std.testing.expectError(
        expected,
        font.statElidedFallbackNameId(allocator),
    );
}
