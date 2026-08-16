//! ChainContextPos format-3 execution contracts.

const std = @import("std");
const execute =
    @import("../../../../../../runtime/lookup/contextual/chaining/coverage/execute.zig");
const model =
    @import("../../../../../../runtime/lookup/contextual/model.zig");
const table = @import("../../../../../../table/root.zig");

test "simple coverage chaining applies its nested record to the first input" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;

    writeU16(&bytes, 0, 3); // ChainContextPos format 3.
    writeU16(&bytes, 2, 0); // No backtrack.
    writeU16(&bytes, 4, 1); // One input.
    writeU16(&bytes, 6, 18);
    writeU16(&bytes, 8, 1); // One lookahead.
    writeU16(&bytes, 10, 24);
    writeU16(&bytes, 12, 1); // One positioning record.
    writeU16(&bytes, 14, 0);
    writeU16(&bytes, 16, 7);
    writeCoverage(&bytes, 18, 3);
    writeCoverage(&bytes, 24, 5);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const subtable =
        (try execute.parse(view, 0)) orelse return error.TestUnexpectedResult;
    const glyphs = [_]u16{ 3, 4, 5 };
    var glyph_classes = [_]u16{0} ** 6;
    glyph_classes[4] = 3;
    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const result = try execute.collectAt(
        false,
        view,
        subtable,
        &glyphs,
        0,
        &adjustments,
        allocator,
        0x0008,
        .{ .glyph_classes = &glyph_classes },
        rejectRecords,
        captureNested,
    );

    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 2), result.next_pos);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 7), adjustments.items[0].x_advance);
}

test "accelerated coverage execution trusts only its proven first input" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;

    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 18);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 24);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 0);
    writeU16(&bytes, 16, 4);
    // The first Coverage intentionally does not contain glyph 3.
    writeCoverage(&bytes, 18, 9);
    writeCoverage(&bytes, 24, 5);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const subtable =
        (try execute.parse(view, 0)) orelse return error.TestUnexpectedResult;
    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const generic = try execute.collectAt(
        false,
        view,
        subtable,
        &.{ 3, 5 },
        0,
        &adjustments,
        allocator,
        0,
        .{},
        rejectRecords,
        captureNested,
    );
    try std.testing.expect(!generic.matched);

    const accelerated = try execute.collectAt(
        true,
        view,
        subtable,
        &.{ 3, 5 },
        0,
        &adjustments,
        allocator,
        0,
        .{},
        rejectRecords,
        captureNested,
    );
    try std.testing.expect(accelerated.matched);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
}

fn rejectRecords(
    _: table.View,
    _: usize,
    _: usize,
    _: []const usize,
    _: []const u16,
    _: *std.ArrayList(model.Adjustment),
    _: std.mem.Allocator,
    _: model.Options,
) model.Error!void {
    return error.InvalidShapingInput;
}

fn captureNested(
    _: table.View,
    _: []const u16,
    target_index: usize,
    lookup_index: u16,
    adjustments: *std.ArrayList(model.Adjustment),
    allocator: std.mem.Allocator,
    _: model.Options,
) model.Error!void {
    try adjustments.append(allocator, .{
        .index = target_index,
        .x_advance = @intCast(lookup_index),
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
