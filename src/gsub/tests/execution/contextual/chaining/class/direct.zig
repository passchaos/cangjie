//! Direct and accelerated chaining-class parity contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const chaining_class =
    @import("../../../../../execution/contextual/chaining/class/root.zig");
const model = @import("../../../../../execution/contextual/model.zig");
const fixture = @import("fixture.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const table = @import("../../../../../table/root.zig");

const Executor = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        _: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        glyphs.items[target] += lookup_index + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "chaining class direct and builder accelerator preserve three regions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 192;
    const subtable = fixture.writeLookupWithSubtable(
        &bytes,
        2,
        .{ .start = 1, .values = &.{2} },
        .{ .start = 2, .values = &.{ 3, 5 } },
        .{ .start = 4, .values = &.{7} },
        &.{.{
            .backtrack = &.{2},
            .input = &.{ 3, 5 },
            .lookahead = &.{7},
            .records = &.{.{ .sequence_index = 0, .lookup_index = 5 }},
        }},
    );
    const view = fixture.validatedView(&bytes);
    const subtables = try accelerator.build.class_context.chaining.build(
        view,
        0,
        1,
        .direct,
        allocator,
    );
    defer accelerator.ownership.deinitChainingClassSubtables(
        allocator,
        subtables,
    );
    try std.testing.expectEqual(@as(usize, 1), subtables.len);

    var direct = std.ArrayList(u16).empty;
    defer direct.deinit(allocator);
    try direct.appendSlice(allocator, &.{ 1, 2, 3, 4 });
    const direct_result = try chaining_class.at(
        Executor,
        view,
        subtable,
        &direct,
        1,
        allocator,
        0,
        .{},
    );

    var accelerated = std.ArrayList(u16).empty;
    defer accelerated.deinit(allocator);
    try accelerated.appendSlice(allocator, &.{ 1, 2, 3, 4 });
    const accelerated_result = try chaining_class.acceleratedAt(
        Executor,
        view,
        subtables[0],
        &accelerated,
        1,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(direct_result.matched);
    try std.testing.expect(accelerated_result.matched);
    try std.testing.expectEqual(direct_result.next_pos, accelerated_result.next_pos);
    try std.testing.expectEqualSlices(u16, direct.items, accelerated.items);
    try std.testing.expectEqualSlices(u16, &.{ 1, 17, 3, 4 }, direct.items);
}

test "direct chaining class applies multiple authored records" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;
    const subtable = fixture.writeLookupWithSubtable(
        &bytes,
        1,
        null,
        .{ .start = 1, .values = &.{ 2, 3 } },
        null,
        &.{.{
            .input = &.{ 2, 3 },
            .records = &.{
                .{ .sequence_index = 0, .lookup_index = 1 },
                .{ .sequence_index = 1, .lookup_index = 2 },
            },
        }},
    );
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    const result = try chaining_class.at(
        Executor,
        fixture.validatedView(&bytes),
        subtable,
        &glyphs,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 12, 14 }, glyphs.items);
}

test "filtered chaining class position does not parse irrelevant payload" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 12;
    // Format 2 with a null required Coverage and InputClassDef would fail if
    // the single-position API parsed before checking source eligibility.
    std.mem.writeInt(u16, bytes[0..2], 2, .big);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.append(allocator, 0);

    const result = try chaining_class.at(
        Executor,
        fixture.validatedView(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_features = &.{0},
            .active_source_feature = 1,
        },
    );
    try std.testing.expect(!result.matched);
    try std.testing.expectEqualSlices(u16, &.{1}, glyphs.items);
}
