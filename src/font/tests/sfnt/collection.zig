//! TTC metadata, collection-level DSIG, and payload-ownership contracts.

const std = @import("std");
const font_mod = @import("../../../font.zig");
const test_font = @import("../../../test_font.zig");
const fixture = @import("../fixtures/sfnt.zig");
const support = @import("support.zig");

const Font = font_mod.Font;

test "TTC face offsets cannot overlap collection metadata" {
    const allocator = std.testing.allocator;
    const valid = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(valid);
    try std.testing.expectEqual(@as(usize, 1), try Font.faceCount(valid));

    const overlapping = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(overlapping);
    fixture.writeU32(overlapping, 12, 12);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(overlapping));

    const unaligned = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(unaligned);
    fixture.writeU32(unaligned, 12, 18);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(unaligned));

    const unselected = try test_font.buildNamedTtc(allocator);
    defer allocator.free(unselected);
    fixture.writeU32(unselected, 16, 16);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(unselected));
    try std.testing.expectError(error.BadSfnt, Font.faceCount(overlapping[0..15]));
}

test "TTC v2 DSIG descriptor validates range and null consistency" {
    var empty: [40]u8 = .{0} ** 40;
    support.writeTag(&empty, 0, "ttcf");
    fixture.writeU32(&empty, 4, 0x00020000);
    fixture.writeU32(&empty, 8, 1);
    fixture.writeU32(&empty, 12, 28);
    try std.testing.expectEqual(@as(usize, 1), try Font.faceCount(&empty));

    var partial = empty;
    support.writeTag(&partial, 16, "DSIG");
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&partial));

    var wrong_tag = empty;
    support.writeTag(&wrong_tag, 16, "BAD!");
    fixture.writeU32(&wrong_tag, 20, 4);
    fixture.writeU32(&wrong_tag, 24, 28);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&wrong_tag));

    var header_overlap = empty;
    support.writeTag(&header_overlap, 16, "DSIG");
    fixture.writeU32(&header_overlap, 20, 4);
    fixture.writeU32(&header_overlap, 24, 24);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&header_overlap));

    var out_of_bounds: [40]u8 = .{0} ** 40;
    support.writeTag(&out_of_bounds, 0, "ttcf");
    fixture.writeU32(&out_of_bounds, 4, 0x00020000);
    fixture.writeU32(&out_of_bounds, 8, 1);
    fixture.writeU32(&out_of_bounds, 12, 28);
    support.writeTag(&out_of_bounds, 16, "DSIG");
    fixture.writeU32(&out_of_bounds, 20, 8);
    fixture.writeU32(&out_of_bounds, 24, 36);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&out_of_bounds));
}

test "TTC v2 DSIG payload cannot alias faces or SFNT tables" {
    const allocator = std.testing.allocator;
    {
        const bytes = try support.buildMinimalTtcV2WithDsig(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }
    {
        const bytes = try support.buildMinimalTtcV2WithDsig(allocator);
        defer allocator.free(bytes);
        fixture.writeU32(bytes, 12, readU32(bytes, 24));
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
    {
        const bytes = try support.buildMinimalTtcV2WithDsig(allocator);
        defer allocator.free(bytes);
        const dsig = readU32(bytes, 24);
        try support.setTableOffsetAt(bytes, 28, "head", dsig);
        try support.setTableLengthAt(bytes, 28, "head", 4);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}
