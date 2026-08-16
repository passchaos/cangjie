//! Direct and Extension chaining lookup traversal contracts.

const std = @import("std");
const lookup =
    @import("../../../../../execution/contextual/chaining/lookup/root.zig");
const model = @import("../../../../../execution/contextual/model.zig");
const fixture = @import("../../context/fixture.zig");
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
        glyphs.items[target] += @as(u16, lookup_index) + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "direct chaining lookup tries subtables per position" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;
    fixture.writeLookup(&bytes, 6, &.{ 10, 40 });
    writeCoverageChaining(&bytes, 10, 9, 0, 1);
    writeCoverageChaining(&bytes, 40, 2, 0, 1);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 2, 2 });
    try lookup.apply(
        Executor,
        validatedView(&bytes),
        0,
        2,
        &glyphs,
        allocator,
        0,
        .{},
        null,
    );
    try std.testing.expectEqualSlices(u16, &.{ 13, 13 }, glyphs.items);
}

test "extension chaining lookup follows wrappers and preserves flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    fixture.writeLookup(&bytes, 7, &.{8});
    fixture.writeExtensionWrapperType(&bytes, 8, 16, 6);
    writeCoverageChaining(&bytes, 16, 2, 0, 1);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 9, 2 });
    const classes = [_]u16{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 };
    try lookup.applyExtension(
        Executor,
        validatedView(&bytes),
        0,
        1,
        &glyphs,
        allocator,
        0x0008,
        .{ .glyph_classes = &classes },
    );
    try std.testing.expectEqualSlices(u16, &.{ 9, 13 }, glyphs.items);
}

fn writeCoverageChaining(
    bytes: []u8,
    base: usize,
    glyph: u16,
    sequence_index: u16,
    lookup_index: u16,
) void {
    fixture.writeU16(bytes, base, 3);
    fixture.writeU16(bytes, base + 2, 0); // Backtrack count.
    fixture.writeU16(bytes, base + 4, 1); // Input count.
    fixture.writeU16(bytes, base + 6, 16); // Input coverage.
    fixture.writeU16(bytes, base + 8, 0); // Lookahead count.
    fixture.writeU16(bytes, base + 10, 1); // Record count.
    fixture.writeRecord(
        bytes,
        base + 12,
        sequence_index,
        lookup_index,
    );
    fixture.writeCoverage1(bytes, base + 16, glyph);
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
