//! GSUB FeatureVariations parsing and matching contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const table = @import("../../table/root.zig");

test "FeatureVariations use record order and default missing axes to zero" {
    var bytes = [_]u8{0} ** 68;
    writeHeader(&bytes, 14);

    // FeatureVariations contains a constrained first record followed by an
    // unconditional fallback. Record order is the OpenType priority order.
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU32(&bytes, 18, 2);
    writeU32(&bytes, 22, 24); // ConditionSet at 38.
    writeU32(&bytes, 26, 0);
    writeU32(&bytes, 30, 0); // Unconditional second record.
    writeU32(&bytes, 34, 0);

    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 6); // Condition at 44.
    writeU16(&bytes, 44, 1);
    writeU16(&bytes, 46, 1); // Axis index 1.
    writeI16(&bytes, 48, -4096); // -0.25.
    writeI16(&bytes, 50, 4096); // 0.25.

    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(?usize, 0),
        try feature.variations.matchingRecord(view, &.{0.75}),
    );
    try std.testing.expectEqual(
        @as(?usize, 1),
        try feature.variations.matchingRecord(view, &.{ 0.75, 0.5 }),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        try feature.variations.matchingRecord(view, &.{}),
    );
}

test "FeatureVariations resolve replacement features from substitution base" {
    var bytes = [_]u8{0} ** 64;
    writeHeader(&bytes, 14);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU32(&bytes, 18, 1);
    writeU32(&bytes, 22, 0);
    writeU32(&bytes, 26, 16); // FeatureTableSubstitution at 30.

    writeU16(&bytes, 30, 1);
    writeU16(&bytes, 32, 0);
    writeU16(&bytes, 34, 2);
    writeU16(&bytes, 36, 3);
    writeU32(&bytes, 38, 18); // Replacement Feature at 48.
    writeU16(&bytes, 42, 7);
    writeU32(&bytes, 44, 28); // Replacement Feature at 58.

    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(?usize, 48),
        try feature.variations.substitutedFeatureOffset(view, 0, 3),
    );
    try std.testing.expectEqual(
        @as(?usize, 58),
        try feature.variations.substitutedFeatureOffset(view, 0, 7),
    );
    try std.testing.expectEqual(
        @as(?usize, null),
        try feature.variations.substitutedFeatureOffset(view, 0, 5),
    );
}

test "FeatureVariations reject truncated record arrays and zero replacements" {
    var bytes = [_]u8{0} ** 30;
    writeHeader(&bytes, 14);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU32(&bytes, 18, 2); // Only one eight-byte record fits.

    const truncated = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectError(
        error.BadGsub,
        feature.variations.matchingRecord(truncated, &.{0.5}),
    );

    writeU32(&bytes, 18, 1);
    writeU32(&bytes, 22, 0);
    writeU32(&bytes, 26, 0);
    try std.testing.expectEqual(
        @as(?usize, null),
        try feature.variations.substitutedFeatureOffset(truncated, 0, 0),
    );
}

fn writeHeader(bytes: []u8, variations_offset: u32) void {
    writeU16(bytes, 0, 1);
    writeU16(bytes, 2, 1);
    writeU32(bytes, 10, variations_offset);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
