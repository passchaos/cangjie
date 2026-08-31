//! GSUB cached FeatureList index contracts.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");
const table = @import("../../table/root.zig");
const unicode = @import("../../../unicode.zig");

test "feature index represents an absent FeatureList with owned empties" {
    var bytes = [_]u8{0} ** 10;
    writeU32(&bytes, 0, 0x00010000);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    var data = try acceleration.feature_index.build(
        view,
        1,
        std.testing.allocator,
    );
    defer data.deinit(std.testing.allocator);

    try std.testing.expect(!data.has_random_feature);
    try std.testing.expectEqual(@as(usize, 0), data.records.len);
    try std.testing.expectEqual(@as(usize, 0), data.lookups.len);
}

test "feature index keeps nonzero FeatureList offsets strict" {
    var bytes = [_]u8{0} ** 10;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 6, 10);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(
        error.EndOfStream,
        acceleration.feature_index.build(view, 1, std.testing.allocator),
    );
}

test "feature index borrows only canonical unique lookup records" {
    var bytes = [_]u8{0} ** 48;
    writeFeatureList(
        &bytes,
        unicode.tag("liga"),
        &.{ 1, 3 },
        unicode.tag("rlig"),
        &.{2},
    );
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    var data = try acceleration.feature_index.build(
        view,
        4,
        std.testing.allocator,
    );
    defer data.deinit(std.testing.allocator);

    const index = acceleration.model.FeatureIndex{
        .data_ptr = bytes[0..].ptr,
        .data_len = bytes.len,
        .table_offset = 0,
        .table_length = bytes.len,
        .accelerators_addr = 0,
        .accelerator_count = 0,
        .has_random_feature = false,
        .records = data.records,
        .lookups = data.lookups,
    };
    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 3 },
        acceleration.feature_index.selectedLookups(
            &index,
            unicode.tag("liga"),
            &.{.{ .index = 0 }},
            2,
        ).?,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{},
        acceleration.feature_index.selectedLookups(
            &index,
            unicode.tag("calt"),
            &.{.{ .index = 0 }},
            2,
        ).?,
    );

    // Two active records with the same tag need the owned union/sort/dedup
    // path even when both records are independently canonical.
    data.records[1].tag = unicode.tag("liga");
    try std.testing.expect(acceleration.feature_index.selectedLookups(
        &index,
        unicode.tag("liga"),
        &.{ .{ .index = 0 }, .{ .index = 1 } },
        2,
    ) == null);

    writeU16(&bytes, 32, 3);
    writeU16(&bytes, 34, 1);
    var noncanonical = try acceleration.feature_index.build(
        view,
        4,
        std.testing.allocator,
    );
    defer noncanonical.deinit(std.testing.allocator);
    try std.testing.expect(!noncanonical.records[0].borrowable);
}

test "feature index random capability requires exact table and sidecar identity" {
    var bytes = [_]u8{0} ** 48;
    writeFeatureList(
        &bytes,
        unicode.tag("rand"),
        &.{1},
        unicode.tag("rlig"),
        &.{2},
    );
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    var accelerators = [_]acceleration.Lookup{.{}};
    const index = try acceleration.feature_index.create(
        view,
        &accelerators,
        4,
        std.testing.allocator,
    );
    defer acceleration.feature_index.destroy(index, std.testing.allocator);
    accelerators[0].feature_index = index;

    try std.testing.expectEqual(
        @as(?bool, true),
        acceleration.feature_index.hasRandomFeature(
            &bytes,
            0,
            bytes.len,
            &accelerators,
        ),
    );
    try std.testing.expect(acceleration.feature_index.hasRandomFeature(
        &bytes,
        1,
        bytes.len - 1,
        &accelerators,
    ) == null);
    var foreign_bytes = bytes;
    try std.testing.expect(acceleration.feature_index.hasRandomFeature(
        &foreign_bytes,
        0,
        foreign_bytes.len,
        &accelerators,
    ) == null);
    var copied_accelerators = accelerators;
    try std.testing.expect(acceleration.feature_index.hasRandomFeature(
        &bytes,
        0,
        bytes.len,
        &copied_accelerators,
    ) == null);

    var ordinary_bytes = [_]u8{0} ** 48;
    writeFeatureList(
        &ordinary_bytes,
        unicode.tag("liga"),
        &.{1},
        unicode.tag("rlig"),
        &.{2},
    );
    const ordinary_view = table.View{
        .data = &ordinary_bytes,
        .offset = 0,
        .length = ordinary_bytes.len,
    };
    var ordinary_accelerators = [_]acceleration.Lookup{.{}};
    const ordinary_index = try acceleration.feature_index.create(
        ordinary_view,
        &ordinary_accelerators,
        4,
        std.testing.allocator,
    );
    defer acceleration.feature_index.destroy(
        ordinary_index,
        std.testing.allocator,
    );
    ordinary_accelerators[0].feature_index = ordinary_index;
    try std.testing.expectEqual(
        @as(?bool, false),
        acceleration.feature_index.hasRandomFeature(
            &ordinary_bytes,
            0,
            ordinary_bytes.len,
            &ordinary_accelerators,
        ),
    );
    try std.testing.expect(acceleration.feature_index.hasRandomFeature(
        &ordinary_bytes,
        0,
        ordinary_bytes.len,
        &.{.{}},
    ) == null);
}

test "feature index rejects lookup indexes outside LookupList" {
    var bytes = [_]u8{0} ** 48;
    writeFeatureList(
        &bytes,
        unicode.tag("liga"),
        &.{4},
        unicode.tag("rlig"),
        &.{2},
    );
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectError(
        error.BadGsub,
        acceleration.feature_index.build(view, 4, std.testing.allocator),
    );
}

fn writeFeatureList(
    bytes: []u8,
    first_tag: u32,
    first_lookups: []const u16,
    second_tag: u32,
    second_lookups: []const u16,
) void {
    // Only the GSUB version and FeatureList are required by the index builder.
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 0);
    writeU16(bytes, 6, 14);

    writeU16(bytes, 14, 2);
    writeU32(bytes, 16, first_tag);
    writeU16(bytes, 20, 14);
    writeU32(bytes, 22, second_tag);
    writeU16(bytes, 26, 22);

    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, @intCast(first_lookups.len));
    for (first_lookups, 0..) |lookup, index| {
        writeU16(bytes, 32 + index * 2, lookup);
    }
    writeU16(bytes, 36, 0);
    writeU16(bytes, 38, @intCast(second_lookups.len));
    for (second_lookups, 0..) |lookup, index| {
        writeU16(bytes, 40 + index * 2, lookup);
    }
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
