//! Accelerated two-input ContextPos class matching contracts.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const class_context = @import("../../../../../opentype/class_context.zig");
const execute = @import("../../../../runtime/lookup/contextual/context_class_accelerated.zig");
const model = @import("../../../../runtime/lookup/contextual/model.zig");
const table = @import("../../../../table/root.zig");

test "accelerated ContextPos class rule targets its authored input" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeClassDef1(&bytes, 0, 5, &.{ 2, 4 });
    const rules = [_]accelerator.model.ContextClassRule{.{
        .second_class = 4,
        .sequence_index = 1,
        .lookup_index = 12,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 2,
        .start = 0,
        .len = 1,
        .min_input_count = 2,
        .max_input_count = 2,
        .max_lookahead_count = 0,
    }};
    const coverage_glyphs = try allocator.dupe(u16, &.{5});
    defer allocator.free(coverage_glyphs);
    const subtables = [_]accelerator.model.ContextClassSubtable{.{
        .coverage = .{ .glyphs = coverage_glyphs },
        .class_def_offset = 0,
        .rules = &rules,
        .groups = &groups,
    }};
    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try execute.collectLookup(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        &.{ 5, 6 },
        &adjustments,
        allocator,
        0,
        .{},
        &subtables,
        captureNested,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 12), adjustments.items[0].x_advance);
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
