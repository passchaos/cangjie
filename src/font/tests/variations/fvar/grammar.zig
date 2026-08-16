//! fvar table-region, axis-record, and instance-record contracts.

const std = @import("std");
const fvar = @import("../../../tables/variations/fvar/root.zig");
const sfnt = @import("../../../sfnt/root.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("../support.zig");

test "fvar axes and instance arrays stay inside declared table regions" {
    const allocator = std.testing.allocator;

    var overlapping_axes: [36]u8 = .{0} ** 36;
    fixture.writeU32(&overlapping_axes, 0, 0x00010000);
    fixture.writeU16(&overlapping_axes, 4, 12); // Points into the fvar header.
    fixture.writeU16(&overlapping_axes, 6, 2);
    fixture.writeU16(&overlapping_axes, 8, 1);
    fixture.writeU16(&overlapping_axes, 10, 20);
    @memcpy(overlapping_axes[12..16], "wght");
    try expectAxesError(&overlapping_axes, allocator);

    var truncated_instances: [36]u8 = .{0} ** 36;
    support.writeFvarHeader(&truncated_instances, 1);
    fixture.writeU16(&truncated_instances, 12, 1);
    fixture.writeU16(&truncated_instances, 14, 8);
    support.writeAxis(
        &truncated_instances,
        16,
        "wght",
        100.0,
        400.0,
        900.0,
        256,
    );
    try expectAxesError(&truncated_instances, allocator);

    var valid_with_instance: [44]u8 = .{0} ** 44;
    support.writeFvarHeader(&valid_with_instance, 1);
    fixture.writeU16(&valid_with_instance, 12, 1);
    fixture.writeU16(&valid_with_instance, 14, 8);
    support.writeAxis(
        &valid_with_instance,
        16,
        "wght",
        100.0,
        400.0,
        900.0,
        256,
    );
    fixture.writeU16(&valid_with_instance, 36, 300);
    support.writeF16Dot16(&valid_with_instance, 40, 400.0);
    const font = support.fvarFont(&valid_with_instance);
    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 1), axes.len);
    try std.testing.expectEqualStrings("wght", &axes[0].tag);

    var bad_count_size_pairs = valid_with_instance;
    fixture.writeU16(&bad_count_size_pairs, 6, 3);
    try expectAxesError(&bad_count_size_pairs, allocator);

    var padded_axis_record: [38]u8 = .{0} ** 38;
    support.writeFvarHeader(&padded_axis_record, 1);
    fixture.writeU16(&padded_axis_record, 10, 22);
    support.writeAxis(
        &padded_axis_record,
        16,
        "wght",
        100.0,
        400.0,
        900.0,
        256,
    );
    try expectAxesError(&padded_axis_record, allocator);

    var ambiguous_instance_size: [45]u8 = .{0} ** 45;
    support.writeFvarHeader(&ambiguous_instance_size, 1);
    fixture.writeU16(&ambiguous_instance_size, 12, 1);
    fixture.writeU16(&ambiguous_instance_size, 14, 9);
    support.writeAxis(
        &ambiguous_instance_size,
        16,
        "wght",
        100.0,
        400.0,
        900.0,
        256,
    );
    try expectAxesError(&ambiguous_instance_size, allocator);
}

test "fvar axis records require ordered ranges and unique visible tags" {
    const allocator = std.testing.allocator;

    var invalid_range: [36]u8 = .{0} ** 36;
    support.writeFvarHeader(&invalid_range, 1);
    support.writeAxis(
        &invalid_range,
        16,
        "wght",
        900.0,
        400.0,
        100.0,
        256,
    );
    try expectAxesError(&invalid_range, allocator);

    var duplicate_tags: [56]u8 = .{0} ** 56;
    support.writeFvarHeader(&duplicate_tags, 2);
    support.writeAxis(
        &duplicate_tags,
        16,
        "wght",
        100.0,
        400.0,
        900.0,
        256,
    );
    support.writeAxis(
        &duplicate_tags,
        36,
        "wght",
        50.0,
        100.0,
        200.0,
        257,
    );
    try expectAxesError(&duplicate_tags, allocator);

    var hidden_duplicate_tags = duplicate_tags;
    fixture.writeU16(&hidden_duplicate_tags, 52, 0x0001);
    const hidden_font = support.fvarFont(&hidden_duplicate_tags);
    const axes = try hidden_font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqual(@as(u16, 1), axes[1].flags);

    const normalized = try hidden_font.normalizedVariationCoordinates(
        allocator,
        &.{.{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 700.0 }},
    );
    defer allocator.free(normalized);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), normalized[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), normalized[1], 0.0001);
}

test "fvar instance coordinates stay inside axis ranges" {
    var bytes: [44]u8 = .{0} ** 44;
    support.writeFvarHeader(&bytes, 1);
    fixture.writeU16(&bytes, 12, 1);
    fixture.writeU16(&bytes, 14, 8);
    support.writeAxis(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    fixture.writeU16(&bytes, 36, 258);
    support.writeF16Dot16(&bytes, 40, 700.0);

    const record = fvarRecord(bytes.len);
    try fvar.validate(&bytes, record);

    var reserved_instance_flags = bytes;
    fixture.writeU16(&reserved_instance_flags, 38, 1);
    try std.testing.expectError(
        error.BadSfnt,
        fvar.validate(&reserved_instance_flags, record),
    );

    var coordinate_past_axis_range = bytes;
    support.writeF16Dot16(&coordinate_past_axis_range, 40, 950.0);
    try std.testing.expectError(
        error.BadSfnt,
        fvar.validate(&coordinate_past_axis_range, record),
    );
}

fn expectAxesError(data: []const u8, allocator: std.mem.Allocator) !void {
    const font = support.fvarFont(data);
    try std.testing.expectError(error.BadSfnt, font.variationAxes(allocator));
}

fn fvarRecord(length: usize) sfnt.Record {
    return .{
        .tag = .{ 'f', 'v', 'a', 'r' },
        .checksum = 0,
        .offset = 0,
        .length = length,
    };
}
