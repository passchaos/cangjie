//! Reverse lookup scan direction, subtable order, and LookupFlag contracts.

const std = @import("std");
const reverse = @import("../../../../execution/direct/reverse/root.zig");
const fixture = @import("fixture.zig");
const table = @import("../../../../table/root.zig");

test "reverse lookup skips ignored context glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 56;
    fixture.writeLookup(&bytes, 8, 0x0008, &.{8});
    fixture.writeReverse(&bytes, 8, 2, 9, &.{1}, &.{3});

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 4, 2, 5, 3 });
    const classes = [_]u16{ 0, 0, 0, 0, 3, 3 };
    try reverse.lookup(
        view(&bytes),
        0,
        1,
        &glyphs,
        0x0008,
        .{ .glyph_classes = &classes },
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 4, 9, 5, 3 },
        glyphs.items,
    );
}

test "reverse lookup is position-major and does not cascade one position" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 130;
    fixture.writeLookup(&bytes, 8, 0, &.{ 12, 50, 88 });
    fixture.writeReverse(&bytes, 12, 2, 3, &.{1}, &.{});
    fixture.writeReverse(&bytes, 50, 3, 4, &.{1}, &.{});
    fixture.writeReverse(&bytes, 88, 1, 5, &.{}, &.{3});

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    try reverse.lookup(view(&bytes), 0, 3, &glyphs, 0, .{});

    // The right glyph changes first, allowing the earlier position to observe
    // its refined lookahead. Only the first matching subtable owns a position.
    try std.testing.expectEqualSlices(u16, &.{ 5, 3 }, glyphs.items);
}

test "standalone reverse subtable scans backward and marks substitutions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    fixture.writeReverse(&bytes, 0, 2, 9, &.{}, &.{});
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 2, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false });

    try reverse.subtable(
        view(&bytes),
        0,
        &glyphs,
        0,
        .{ .glyph_substituted = &substituted },
    );
    try std.testing.expectEqualSlices(u16, &.{ 9, 9 }, glyphs.items);
    try std.testing.expectEqualSlices(
        bool,
        &.{ true, true },
        substituted.items,
    );
}

test "reverse lookup rejects malformed context before mutating earlier positions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    fixture.writeLookup(&bytes, 8, 0, &.{ 10, 40 });
    fixture.writeReverse(&bytes, 10, 2, 9, &.{}, &.{});
    // The later subtable is reached first at glyph 3. Its target coverage is
    // complete, but its lookahead Coverage offset aliases null and must fail.
    fixture.writeReverse(&bytes, 40, 3, 10, &.{}, &.{4});
    fixture.writeU16(&bytes, 40 + 8, 0);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 2, 3, 4 });
    try std.testing.expectError(
        error.BadGsub,
        reverse.lookup(view(&bytes), 0, 2, &glyphs, 0, .{}),
    );
    try std.testing.expectEqualSlices(u16, &.{ 2, 3, 4 }, glyphs.items);
}

fn view(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
