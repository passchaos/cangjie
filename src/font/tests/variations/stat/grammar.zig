//! Focused STAT axis and AxisValue grammar contracts.

const std = @import("std");
const stat_mod = @import("../../../tables/variations/stat/root.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("support.zig");
const variation_support = @import("../support.zig");

test "STAT design axes may differ from fvar presentation axes" {
    var bytes: [78]u8 = .{0} ** 78;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 16);
    fixture.writeU16(&bytes, 6, 2);
    fixture.writeU16(&bytes, 8, 1);
    fixture.writeU16(&bytes, 10, 20);
    support.writeFvarAxis(&bytes, 16, "wght");

    const stat_offset = 36;
    support.writeHeader(&bytes, stat_offset, 1, 1, 28);
    support.writeAxis(&bytes, stat_offset + 20, "wght", 256, 0);
    fixture.writeU16(&bytes, stat_offset + 28, 2);
    support.writeFormat1Default(&bytes, stat_offset + 30, 0);

    const fvar = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };
    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = stat_offset, .length = bytes.len - stat_offset };
    const names = support.names(&.{ 0, 2, 256, 258 });
    try stat_mod.validate(std.testing.allocator, &bytes, stat, fvar, &names);

    var mismatched = bytes;
    @memcpy(mismatched[stat_offset + 20 ..][0..4], "wdth");
    try stat_mod.validate(std.testing.allocator, &mismatched, stat, fvar, &names);
}

test "STAT design axes have unique tags and ordering values" {
    var bytes: [56]u8 = .{0} ** 56;
    support.writeHeader(&bytes, 0, 2, 0, 0);
    support.writeAxis(&bytes, 20, "wght", 256, 0);
    support.writeAxis(&bytes, 28, "wdth", 257, 1);

    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = support.names(&.{ 2, 256, 257 });
    try stat_mod.validate(std.testing.allocator, &bytes, stat, null, &names);

    var duplicate_tag = bytes;
    support.writeAxis(&duplicate_tag, 28, "wght", 257, 1);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_tag, stat, null, &names));

    var duplicate_order = bytes;
    support.writeAxis(&duplicate_order, 28, "wdth", 257, 0);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_order, stat, null, &names));

    var invalid_axis_tag = bytes;
    invalid_axis_tag[28] = 0x7f; // STAT design-axis tags must also be printable OpenType tags.
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &invalid_axis_tag, stat, null, &names));
}

test "STAT AxisValue offsets and axis indexes stay inside declared records" {
    var metadata_overlap: [42]u8 = .{0} ** 42;
    support.writeHeader(&metadata_overlap, 0, 1, 1, 28);
    support.writeAxis(&metadata_overlap, 20, "wght", 256, 0);
    fixture.writeU16(&metadata_overlap, 28, 0); // Points back into the AxisValue offsets array.
    support.writeFormat1Default(&metadata_overlap, 30, 0);

    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = metadata_overlap.len };
    const names = support.names(&.{ 0, 2, 256, 258 });
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &metadata_overlap, stat, null, &names));

    var bad_axis_index = metadata_overlap;
    fixture.writeU16(&bad_axis_index, 28, 2);
    support.writeFormat1Default(&bad_axis_index, 30, 1); // Only axis 0 is declared.
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &bad_axis_index, stat, null, &names));
}

test "STAT AxisValue offset array may be out of payload order" {
    var bytes: [64]u8 = .{0} ** 64;
    support.writeHeader(&bytes, 0, 1, 2, 28);
    support.writeAxis(&bytes, 20, "wght", 256, 0);
    fixture.writeU16(&bytes, 28, 4);
    fixture.writeU16(&bytes, 30, 24);
    support.writeFormat2(&bytes, 32, 0, 258, 350.0, 300.0, 400.0);
    support.writeFormat1(&bytes, 52, 0, 259, 500.0);

    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = support.names(&.{ 0, 2, 256, 258, 259 });
    try stat_mod.validate(std.testing.allocator, &bytes, stat, null, &names);

    var decreasing_offsets = bytes;
    fixture.writeU16(&decreasing_offsets, 28, 24);
    fixture.writeU16(&decreasing_offsets, 30, 4);
    try stat_mod.validate(std.testing.allocator, &decreasing_offsets, stat, null, &names);

    var duplicate_offsets = bytes;
    fixture.writeU16(&duplicate_offsets, 30, 4);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_offsets, stat, null, &names));
}

test "STAT AxisValue payloads do not overlap" {
    var bytes: [64]u8 = .{0} ** 64;
    support.writeHeader(&bytes, 0, 1, 2, 28);
    support.writeAxis(&bytes, 20, "wght", 256, 0);
    fixture.writeU16(&bytes, 28, 4);
    fixture.writeU16(&bytes, 30, 24);
    support.writeFormat2(&bytes, 32, 0, 258, 350.0, 300.0, 400.0);
    support.writeFormat1(&bytes, 52, 0, 258, 500.0);

    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = support.names(&.{ 0, 2, 256, 258 });
    try stat_mod.validate(std.testing.allocator, &bytes, stat, null, &names);

    var overlapping_payload = bytes;
    fixture.writeU16(&overlapping_payload, 30, 12); // Starts inside the first 20-byte AxisValue record.
    support.writeFormat1(&overlapping_payload, 40, 0, 258, 400.0);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &overlapping_payload, stat, null, &names));
}

test "STAT AxisValue ranges and points avoid ambiguous overlaps" {
    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = 94 };
    const names = support.names(&.{ 0, 2, 256, 258, 259, 260, 261 });

    var touching_ranges: [94]u8 = .{0} ** 94;
    support.writeHeader(&touching_ranges, 0, 1, 3, 28);
    support.writeAxis(&touching_ranges, 20, "wght", 256, 0);
    fixture.writeU16(&touching_ranges, 28, 6);
    fixture.writeU16(&touching_ranges, 30, 26);
    fixture.writeU16(&touching_ranges, 32, 46);
    support.writeFormat2(&touching_ranges, 34, 0, 258, 350.0, 300.0, 400.0);
    support.writeFormat2(&touching_ranges, 54, 0, 259, 450.0, 400.0, 500.0);
    support.writeFormat1(&touching_ranges, 74, 0, 260, 500.0);
    try stat_mod.validate(std.testing.allocator, &touching_ranges, stat, null, &names);

    var overlapping_ranges = touching_ranges;
    support.writeFormat2(&overlapping_ranges, 54, 0, 259, 450.0, 399.0, 500.0);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &overlapping_ranges, stat, null, &names));

    var duplicate_boundary_nominal = touching_ranges;
    support.writeFormat2(&duplicate_boundary_nominal, 34, 0, 258, 400.0, 300.0, 400.0);
    support.writeFormat2(&duplicate_boundary_nominal, 54, 0, 259, 400.0, 400.0, 500.0);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_boundary_nominal, stat, null, &names));

    var point_inside_range = touching_ranges;
    support.writeFormat1(&point_inside_range, 74, 0, 260, 350.0);
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &point_inside_range, stat, null, &names));

    var linked_point_at_nominal = touching_ranges;
    support.writeFormat3(&linked_point_at_nominal, 74, 0, 258, 350.0, 700.0);
    try stat_mod.validate(std.testing.allocator, &linked_point_at_nominal, stat, null, &names);

    var duplicate_points: [60]u8 = .{0} ** 60;
    support.writeHeader(&duplicate_points, 0, 1, 2, 28);
    support.writeAxis(&duplicate_points, 20, "wght", 256, 0);
    fixture.writeU16(&duplicate_points, 28, 4);
    fixture.writeU16(&duplicate_points, 30, 16);
    support.writeFormat1(&duplicate_points, 32, 0, 258, 400.0);
    support.writeFormat3(&duplicate_points, 44, 0, 261, 400.0, 700.0);
    const duplicate_points_stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = duplicate_points.len };
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_points, duplicate_points_stat, null, &names));
}

test "STAT format 4 AxisValue records reference each axis once" {
    var duplicate_axis: [46]u8 = .{0} ** 46;
    support.writeHeader(&duplicate_axis, 0, 1, 1, 28);
    support.writeAxis(&duplicate_axis, 20, "wght", 256, 0);
    fixture.writeU16(&duplicate_axis, 28, 2);
    fixture.writeU16(&duplicate_axis, 30, 4);
    fixture.writeU16(&duplicate_axis, 32, 2); // axisCount.
    fixture.writeU16(&duplicate_axis, 34, 0); // flags.
    fixture.writeU16(&duplicate_axis, 36, 258);
    fixture.writeU16(&duplicate_axis, 38, 0);
    variation_support.writeF16Dot16(&duplicate_axis, 40, 400.0);
    fixture.writeU16(&duplicate_axis, 44, 0); // Duplicate axis index.

    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = duplicate_axis.len };
    const names = support.names(&.{ 0, 2, 256, 258 });
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_axis, stat, null, &names));
}

test "STAT single-axis format 4 values must not duplicate point or range labels" {
    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = 80 };
    const names = support.names(&.{ 0, 2, 256, 258, 259, 260 });

    var bytes: [80]u8 = .{0} ** 80;
    support.writeHeader(&bytes, 0, 1, 3, 28);
    support.writeAxis(&bytes, 20, "wght", 256, 0);
    fixture.writeU16(&bytes, 28, 6);
    fixture.writeU16(&bytes, 30, 18);
    fixture.writeU16(&bytes, 32, 38);
    support.writeFormat1(&bytes, 34, 0, 258, 700.0);
    support.writeFormat2(&bytes, 46, 0, 259, 450.0, 400.0, 500.0);
    support.writeFormat4(&bytes, 66, 260, &.{
        .{ .axis_index = 0, .value = 300.0 },
    });
    try stat_mod.validate(std.testing.allocator, &bytes, stat, null, &names);

    var duplicate_point = bytes;
    support.writeFormat4(&duplicate_point, 66, 260, &.{
        .{ .axis_index = 0, .value = 700.0 },
    });
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &duplicate_point, stat, null, &names));

    var inside_range = bytes;
    support.writeFormat4(&inside_range, 66, 260, &.{
        .{ .axis_index = 0, .value = 450.0 },
    });
    try std.testing.expectError(error.BadSfnt, stat_mod.validate(std.testing.allocator, &inside_range, stat, null, &names));

    var boundary = bytes;
    support.writeFormat4(&boundary, 66, 260, &.{
        .{ .axis_index = 0, .value = 400.0 },
    });
    try stat_mod.validate(std.testing.allocator, &boundary, stat, null, &names);
}

test "STAT format 4 AxisValue coordinate sets tolerate platform duplicates" {
    var bytes: [96]u8 = .{0} ** 96;
    support.writeHeader(&bytes, 0, 2, 3, 36);
    support.writeAxis(&bytes, 20, "wght", 256, 0);
    support.writeAxis(&bytes, 28, "wdth", 257, 1);
    fixture.writeU16(&bytes, 36, 6);
    fixture.writeU16(&bytes, 38, 26);
    fixture.writeU16(&bytes, 40, 40);
    support.writeFormat4(&bytes, 42, 258, &.{
        .{ .axis_index = 0, .value = 400.0 },
        .{ .axis_index = 1, .value = 100.0 },
    });
    support.writeFormat4(&bytes, 62, 259, &.{
        .{ .axis_index = 0, .value = 400.0 },
    });
    support.writeFormat4(&bytes, 76, 260, &.{
        .{ .axis_index = 0, .value = 700.0 },
        .{ .axis_index = 1, .value = 100.0 },
    });

    const stat = @import("../../../sfnt/root.zig").Record{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = support.names(&.{ 2, 256, 257, 258, 259, 260 });
    try stat_mod.validate(std.testing.allocator, &bytes, stat, null, &names);

    var duplicate_coordinate_set = bytes;
    support.writeFormat4(&duplicate_coordinate_set, 76, 260, &.{
        .{ .axis_index = 1, .value = 100.0 },
        .{ .axis_index = 0, .value = 400.0 },
    });
    try stat_mod.validate(std.testing.allocator, &duplicate_coordinate_set, stat, null, &names);
}
