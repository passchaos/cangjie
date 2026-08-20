//! Accelerated class-based chaining execution contracts.

const std = @import("std");
const class_context =
    @import("../../../../../../../opentype/class_context.zig");
const execute =
    @import("../../../../../../../gpos/runtime/lookup/contextual/chaining/class_accelerated/execute.zig");
const model =
    @import("../../../../../../../gpos/runtime/lookup/contextual/model.zig");
const table = @import("../../../../../../../gpos/table/root.zig");

test "accelerated class chaining matches sidecar classes and nested lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;
    writeCoverage(&bytes, 0, 3);
    writeClassDef1(&bytes, 6, 3, &.{ 2, 0, 3 });
    writeClassDef1(&bytes, 18, 7, &.{4});
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const classes = [_]u16{ 3, 4 };
    const rules = [_]class_context.Rule{.{
        .class_set = 2,
        .input_count = 2,
        .lookahead_count = 1,
        .hash = class_context.sequenceHash(&classes),
        .order = 0,
        .lookup_index = 12,
        .classes_start = 0,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 2,
        .start = 0,
        .len = 1,
        .max_input_count = 2,
        .max_lookahead_count = 1,
    }};
    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const result = try execute.collectAt(
        view,
        .{
            .coverage_offset = 0,
            .input_class_def = 6,
            .lookahead_class_def = 18,
            .rules = &rules,
            .classes = &classes,
            .groups = &groups,
        },
        &.{ 3, 5, 7 },
        0,
        &adjustments,
        allocator,
        0,
        .{},
        captureNested,
    );

    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 2), result.next_pos);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 12), adjustments.items[0].x_advance);
}

test "accelerated class chaining keeps nonmatching sidecars inert" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;
    writeCoverage(&bytes, 0, 3);
    writeClassDef1(&bytes, 6, 3, &.{ 2, 0, 3 });
    writeClassDef1(&bytes, 18, 7, &.{4});
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const expected = [_]u16{ 9, 4 };
    const rules = [_]class_context.Rule{.{
        .class_set = 2,
        .input_count = 2,
        .lookahead_count = 1,
        .hash = class_context.sequenceHash(&expected),
        .order = 0,
        .lookup_index = 12,
        .classes_start = 0,
    }};
    const groups = [_]class_context.RuleGroup{.{
        .class_set = 2,
        .start = 0,
        .len = 1,
        .max_input_count = 2,
        .max_lookahead_count = 1,
    }};
    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    const result = try execute.collectAt(
        view,
        .{
            .coverage_offset = 0,
            .input_class_def = 6,
            .lookahead_class_def = 18,
            .rules = &rules,
            .classes = &expected,
            .groups = &groups,
        },
        &.{ 3, 5, 7 },
        0,
        &adjustments,
        allocator,
        0,
        .{},
        captureNested,
    );

    try std.testing.expect(!result.matched);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
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
