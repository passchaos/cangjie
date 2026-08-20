//! ContextSubst format-1/2/3 execution contracts.

const std = @import("std");
const context = @import("../../../../execution/contextual/context/root.zig");
const model = @import("../../../../execution/contextual/model.zig");
const fixture = @import("fixture.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

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
        glyphs.items[target] += @as(u16, lookup_index) + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "glyph context preserves authored rule order and skipped physical glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 70;
    // Format 1, one set, two rules. The first rule misses component 9; the
    // second matches [1,2] around ignored physical glyph 4.
    fixture.writeU16(&bytes, 0, 1);
    fixture.writeU16(&bytes, 2, 50);
    fixture.writeU16(&bytes, 4, 1);
    fixture.writeU16(&bytes, 6, 8);
    fixture.writeU16(&bytes, 8, 2);
    fixture.writeU16(&bytes, 10, 6);
    fixture.writeU16(&bytes, 12, 16);
    fixture.writeU16(&bytes, 14, 2);
    fixture.writeU16(&bytes, 16, 1);
    fixture.writeU16(&bytes, 18, 9);
    fixture.writeRecord(&bytes, 20, 0, 0);
    fixture.writeU16(&bytes, 24, 2);
    fixture.writeU16(&bytes, 26, 1);
    fixture.writeU16(&bytes, 28, 2);
    fixture.writeRecord(&bytes, 30, 0, 1);
    fixture.writeCoverage1(&bytes, 50, 1);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 4, 2 });
    const classes = [_]u16{ 0, 0, 0, 0, 3 };
    const result = try context.at(
        Executor,
        validatedView(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0x0008,
        .{ .glyph_classes = &classes },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 12, 4, 2 }, glyphs.items);
}

test "class context requires coverage and matching subsequent classes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    fixture.writeU16(&bytes, 0, 2);
    fixture.writeU16(&bytes, 2, 40);
    fixture.writeU16(&bytes, 4, 46);
    fixture.writeU16(&bytes, 6, 2);
    fixture.writeU16(&bytes, 8, 0);
    fixture.writeU16(&bytes, 10, 12);
    fixture.writeU16(&bytes, 12, 1);
    fixture.writeU16(&bytes, 14, 4);
    fixture.writeU16(&bytes, 16, 2);
    fixture.writeU16(&bytes, 18, 1);
    fixture.writeU16(&bytes, 20, 2);
    fixture.writeRecord(&bytes, 22, 1, 2);
    fixture.writeCoverage1(&bytes, 40, 1);
    fixture.writeClassDef1(&bytes, 46, 1, &.{ 1, 2 });

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    const result = try context.at(
        Executor,
        validatedView(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 14 }, glyphs.items);
}

test "coverage context matches every input coverage" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    fixture.writeU16(&bytes, 0, 3);
    fixture.writeU16(&bytes, 2, 2);
    fixture.writeU16(&bytes, 4, 1);
    fixture.writeU16(&bytes, 6, 14);
    fixture.writeU16(&bytes, 8, 20);
    fixture.writeRecord(&bytes, 10, 0, 3);
    fixture.writeCoverage1(&bytes, 14, 1);
    fixture.writeCoverage1(&bytes, 20, 2);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    const result = try context.at(
        Executor,
        validatedView(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 14, 2 }, glyphs.items);
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
