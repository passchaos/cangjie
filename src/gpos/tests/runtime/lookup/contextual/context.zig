//! ContextPos execution contracts independent of recursive lookup dispatch.

const std = @import("std");
const context = @import("../../../../runtime/lookup/contextual/context.zig");
const table = @import("../../../../table/root.zig");

test "ContextPos format 3 maps positioning records to visible input glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;

    writeU16(&bytes, 0, 3); // ContextPos format 3.
    writeU16(&bytes, 2, 2); // Two input glyphs.
    writeU16(&bytes, 4, 1); // One positioning record.
    writeU16(&bytes, 6, 14);
    writeU16(&bytes, 8, 20);
    writeU16(&bytes, 10, 1); // Target the second visible input.
    writeU16(&bytes, 12, 7);
    writeCoverage(&bytes, 14, 3);
    writeCoverage(&bytes, 20, 5);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const glyphs = [_]u16{ 3, 4, 5 };
    var adjustments = std.ArrayList(context.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const matched = try context.collectAt(
        view,
        0,
        &glyphs,
        0,
        &adjustments,
        allocator,
        0x0008, // Ignore marks; glyph 4 is class 3 below.
        .{ .glyph_classes = &.{ 0, 0, 0, 0, 3, 0 } },
        captureRecords,
    );

    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 10), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i16, 1), adjustments.items[0].x_placement);
}

test "ContextPos format 1 stops after an authored glyph rule matches" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 34;

    writeU16(&bytes, 0, 1); // ContextPos format 1.
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 14);
    writeCoverage(&bytes, 8, 3);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 4);
    writeU16(&bytes, 18, 2); // Two inputs.
    writeU16(&bytes, 20, 1); // One positioning record.
    writeU16(&bytes, 22, 5); // Second glyph id.
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 9);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    var adjustments = std.ArrayList(context.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try context.collect(
        view,
        0,
        &.{ 3, 5, 3, 7 },
        &adjustments,
        allocator,
        0,
        .{},
        captureRecords,
    );

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
}

fn captureRecords(
    view: table.View,
    records_pos: usize,
    record_count: usize,
    input_indices: []const usize,
    _: []const u16,
    adjustments: *std.ArrayList(context.Adjustment),
    allocator: std.mem.Allocator,
    _: context.Options,
) context.Error!void {
    if (record_count != 1) return error.InvalidShapingInput;
    const sequence_index = try view.readU16(records_pos);
    if (sequence_index >= input_indices.len) return error.BadGpos;
    try adjustments.append(allocator, .{
        .index = input_indices[sequence_index],
        .x_advance = @intCast(records_pos),
        .x_placement = @intCast(record_count),
    });
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
