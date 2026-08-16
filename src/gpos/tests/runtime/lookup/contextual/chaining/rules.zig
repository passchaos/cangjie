//! ChainContextPos glyph and class rule execution contracts.

const std = @import("std");
const chaining =
    @import("../../../../../runtime/lookup/contextual/chaining/root.zig");
const context_model =
    @import("../../../../../runtime/lookup/contextual/model.zig");
const table = @import("../../../../../table/root.zig");

test "glyph chaining maps records across ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;

    writeCoverage(&bytes, 0, 3);
    writeU16(&bytes, 6, 2); // RuleSet offset from the synthetic list base.
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 4);
    writeU16(&bytes, 12, 1); // Backtrack count.
    writeU16(&bytes, 14, 2);
    writeU16(&bytes, 16, 2); // Input count.
    writeU16(&bytes, 18, 5);
    writeU16(&bytes, 20, 1); // Lookahead count.
    writeU16(&bytes, 22, 7);
    writeU16(&bytes, 24, 1); // Position record count.
    writeU16(&bytes, 26, 1);
    writeU16(&bytes, 28, 9);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const glyphs = [_]u16{ 2, 3, 4, 5, 7 };
    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[4] = 3;
    var adjustments = std.ArrayList(context_model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const matched = try chaining.glyph.collectAt(
        view,
        .{
            .coverage_offset = 0,
            .sets = .{ .base_offset = 6, .offsets_pos = 6, .count = 1 },
        },
        &glyphs,
        1,
        &adjustments,
        allocator,
        0x0008,
        .{ .glyph_classes = &glyph_classes },
        captureRecordTarget,
    );

    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 3), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 9), adjustments.items[0].x_advance);
}

test "class chaining matches backtrack input and lookahead definitions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 68;

    writeCoverage(&bytes, 0, 3);
    writeClassDef1(&bytes, 6, 2, &.{1});
    writeClassDef1(&bytes, 14, 3, &.{ 2, 0, 3 });
    writeClassDef1(&bytes, 26, 7, &.{4});
    writeU16(&bytes, 34, 0);
    writeU16(&bytes, 36, 0);
    writeU16(&bytes, 38, 6); // Class 2 RuleSet.
    writeU16(&bytes, 40, 1);
    writeU16(&bytes, 42, 4);
    writeU16(&bytes, 44, 1); // Backtrack count.
    writeU16(&bytes, 46, 1);
    writeU16(&bytes, 48, 2); // Input count.
    writeU16(&bytes, 50, 3);
    writeU16(&bytes, 52, 1); // Lookahead count.
    writeU16(&bytes, 54, 4);
    writeU16(&bytes, 56, 1); // Position record count.
    writeU16(&bytes, 58, 1);
    writeU16(&bytes, 60, 11);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    var adjustments = std.ArrayList(context_model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const matched = try chaining.class.collectAt(
        view,
        .{
            .coverage_offset = 0,
            .backtrack_class_def = 6,
            .input_class_def = 14,
            .lookahead_class_def = 26,
            .sets = .{ .base_offset = 34, .offsets_pos = 34, .count = 3 },
        },
        &.{ 2, 3, 5, 7 },
        1,
        &adjustments,
        allocator,
        0,
        .{},
        captureRecordTarget,
    );

    try std.testing.expect(matched);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 11), adjustments.items[0].x_advance);
}

fn captureRecordTarget(
    view: table.View,
    records_pos: usize,
    record_count: usize,
    input_indices: []const usize,
    _: []const u16,
    adjustments: *std.ArrayList(context_model.Adjustment),
    allocator: std.mem.Allocator,
    _: context_model.Options,
) context_model.Error!void {
    if (record_count != 1) return error.InvalidShapingInput;
    const sequence_index = try view.readU16(records_pos);
    if (sequence_index >= input_indices.len) return error.BadGpos;
    try adjustments.append(allocator, .{
        .index = input_indices[sequence_index],
        .x_advance = @intCast(try view.readU16(records_pos + 2)),
    });
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    start: u16,
    classes: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, @intCast(classes.len));
    for (classes, 0..) |class, index| {
        writeU16(bytes, offset + 6 + index * 2, class);
    }
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
