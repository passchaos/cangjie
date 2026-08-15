//! fvar axis enumeration and design-coordinate normalization contracts.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const sfnt_fixture = @import("../fixtures/sfnt.zig");
const table_only = @import("../fixtures/table_only.zig");

const Font = font_mod.Font;

test "fvar public axes API revalidates borrowed axis name references" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try expectAxes(&font, allocator, 2);

    const name_offset = try sfnt_fixture.tableOffset(bytes, "name");
    const axis_name = try sfnt_fixture.nameRecordOffset(
        bytes,
        name_offset,
        256,
    );
    // Leave fvar unchanged so the failure isolates its cross-table NameID
    // ownership contract.
    sfnt_fixture.writeU16(bytes, axis_name + 6, 400);
    try std.testing.expectError(
        error.InvalidName,
        font.variationAxes(allocator),
    );
}

test "fvar public axes API revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqual(@as(f32, 100.0), axes[0].min_value);

    const fvar_offset = try sfnt_fixture.tableOffset(bytes, "fvar");
    // Keep the range ordered and every NameID valid while changing user-facing
    // metadata after parse. The borrowed table no longer matches its checksum.
    writeF16Dot16(bytes, fvar_offset + 20, 200.0);
    try std.testing.expectError(
        error.BadSfnt,
        font.variationAxes(allocator),
    );
}

test "fvar public axes API revalidates all table metadata" {
    const allocator = std.testing.allocator;
    var bytes = oneAxisFvarWithInstance();

    const font = fvarFixture(&bytes);
    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 1), axes.len);
    try std.testing.expectEqual(@as(u16, 0), axes[0].flags);

    var reserved_axis_flags = bytes;
    // Only HIDDEN_AXIS is defined by OpenType.
    sfnt_fixture.writeU16(&reserved_axis_flags, 32, 0x0002);
    try expectAxesError(&reserved_axis_flags, allocator);

    var invalid_axis_tag = bytes;
    // Axis tags use the same printable-ASCII contract as SFNT table tags.
    invalid_axis_tag[16] = 0x1f;
    try expectAxesError(&invalid_axis_tag, allocator);

    var reserved_instance_flags = bytes;
    sfnt_fixture.writeU16(&reserved_instance_flags, 38, 1);
    try expectAxesError(&reserved_instance_flags, allocator);

    var coordinate_past_axis_range = bytes;
    writeF16Dot16(&coordinate_past_axis_range, 40, 950.0);
    try expectAxesError(&coordinate_past_axis_range, allocator);
}

test "normalized variation coordinates reject duplicate and unknown public tags" {
    const allocator = std.testing.allocator;
    var bytes = twoAxisFvar();
    const font = fvarFixture(&bytes);

    const normalized = try font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 700.0 },
        .{ .tag = .{ 'w', 'd', 't', 'h' }, .value = 125.0 },
    });
    defer allocator.free(normalized);
    try std.testing.expectEqual(@as(usize, 2), normalized.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.6),
        normalized[0],
        0.0001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        normalized[1],
        0.0001,
    );

    try expectCoordinateError(&font, allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 650.0 },
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 700.0 },
    });
    try expectCoordinateError(&font, allocator, &.{
        .{ .tag = .{ 'W', 'G', 'H', 'T' }, .value = 700.0 },
    });
    try expectCoordinateError(&font, allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = std.math.nan(f32) },
    });
}

fn fvarFixture(data: []const u8) Font {
    var font = table_only.init(Font, data, 2, 2);
    font.fvar = table_only.record(
        data,
        .{ 'f', 'v', 'a', 'r' },
        0,
        data.len,
    );
    return font;
}

fn oneAxisFvarWithInstance() [44]u8 {
    var bytes: [44]u8 = .{0} ** 44;
    writeFvarHeader(&bytes, 1);
    sfnt_fixture.writeU16(&bytes, 12, 1);
    sfnt_fixture.writeU16(&bytes, 14, 8);
    writeAxis(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    sfnt_fixture.writeU16(&bytes, 36, 300);
    sfnt_fixture.writeU16(&bytes, 38, 0);
    writeF16Dot16(&bytes, 40, 400.0);
    return bytes;
}

fn twoAxisFvar() [56]u8 {
    var bytes: [56]u8 = .{0} ** 56;
    writeFvarHeader(&bytes, 2);
    writeAxis(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeAxis(&bytes, 36, "wdth", 50.0, 100.0, 200.0, 257);
    return bytes;
}

fn writeFvarHeader(bytes: []u8, axis_count: u16) void {
    sfnt_fixture.writeU32(bytes, 0, 0x00010000);
    sfnt_fixture.writeU16(bytes, 4, 16);
    sfnt_fixture.writeU16(bytes, 6, 2);
    sfnt_fixture.writeU16(bytes, 8, axis_count);
    sfnt_fixture.writeU16(bytes, 10, 20);
}

fn writeAxis(
    bytes: []u8,
    offset: usize,
    comptime tag: *const [4]u8,
    minimum: f32,
    default: f32,
    maximum: f32,
    name_id: u16,
) void {
    @memcpy(bytes[offset..][0..4], tag);
    writeF16Dot16(bytes, offset + 4, minimum);
    writeF16Dot16(bytes, offset + 8, default);
    writeF16Dot16(bytes, offset + 12, maximum);
    sfnt_fixture.writeU16(bytes, offset + 16, 0);
    sfnt_fixture.writeU16(bytes, offset + 18, name_id);
}

fn writeF16Dot16(bytes: []u8, offset: usize, value: f32) void {
    const fixed: i32 = @intFromFloat(value * 65536.0);
    std.mem.writeInt(i32, bytes[offset..][0..4], fixed, .big);
}

fn expectAxes(font: *const Font, allocator: std.mem.Allocator, count: usize) !void {
    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(count, axes.len);
    try std.testing.expectEqual(@as(u16, 256), axes[0].name_id);
}

fn expectAxesError(data: []const u8, allocator: std.mem.Allocator) !void {
    const font = fvarFixture(data);
    try std.testing.expectError(
        error.BadSfnt,
        font.variationAxes(allocator),
    );
}

fn expectCoordinateError(
    font: *const Font,
    allocator: std.mem.Allocator,
    coordinates: []const font_mod.VariationCoordinate,
) !void {
    try std.testing.expectError(
        error.BadSfnt,
        font.normalizedVariationCoordinates(allocator, coordinates),
    );
}
