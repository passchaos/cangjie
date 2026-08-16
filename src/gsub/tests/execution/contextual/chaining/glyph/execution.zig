//! ChainContextSubst format-1 execution and traversal contracts.

const std = @import("std");
const glyph_chaining =
    @import("../../../../../execution/contextual/chaining/glyph/root.zig");
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
        allocator: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        if (lookup_index == 7) {
            try glyphs.replaceRange(allocator, target, 1, &.{ 20, 21 });
            return .{ .removed_len = 1, .inserted_len = 2 };
        }
        glyphs.items[target] += lookup_index + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "glyph chaining whole-subtable traversal applies each logical match" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    fixture.writeSubtable(&bytes, 0, 1, &.{
        .{
            .input = &.{ 1, 2 },
            .records = &.{.{ .sequence_index = 0, .lookup_index = 1 }},
        },
    });
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 1, 2 });

    try glyph_chaining.subtable(
        Executor,
        fixture.validatedView(&bytes),
        0,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{ 12, 2, 12, 2 }, glyphs.items);
}

test "glyph chaining resume position follows nested input growth" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    fixture.writeSubtable(&bytes, 0, 1, &.{
        .{
            .input = &.{ 1, 2 },
            .records = &.{.{ .sequence_index = 1, .lookup_index = 7 }},
        },
    });
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });

    const result = try glyph_chaining.at(
        Executor,
        fixture.validatedView(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqual(@as(usize, 3), result.next_pos);
    try std.testing.expectEqualSlices(u16, &.{ 1, 20, 21 }, glyphs.items);
}
