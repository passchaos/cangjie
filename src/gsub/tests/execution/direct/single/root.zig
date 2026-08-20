//! SingleSubst whole-lookup, contextual, and accelerator contracts.

const std = @import("std");
const build = @import("../../../../accelerator/build/root.zig");
const single = @import("../../../../execution/direct/single/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

test "entry execution preserves sorted mapping filtering and metadata" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 3);
    writeU16(&bytes, 6, 30);
    writeU16(&bytes, 8, 31);
    writeU16(&bytes, 10, 40);
    writeCoverage2(&bytes, 12);

    const mappings = try build.single.entries(
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        0,
        allocator,
    );
    defer allocator.free(mappings);
    try std.testing.expectEqual(build.single.Entry{
        .from = 10,
        .to = 30,
    }, single.entryForGlyph(mappings, 10).?);
    try std.testing.expect(single.entryForGlyph(mappings, 19) == null);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 9, 10, 11, 20, 21 });
    var classes = [_]u16{0} ** 22;
    classes[11] = 3;
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendNTimes(allocator, false, glyphs.items.len);

    single.entries(mappings, &glyphs, 0x0008, .{
        .glyph_classes = &classes,
        .glyph_substituted = &substituted,
    });
    try std.testing.expectEqualSlices(
        u16,
        &.{ 9, 30, 11, 40, 21 },
        glyphs.items,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, true, false, true, false },
        substituted.items,
    );
}

test "direct and extension lookups preserve non-cascading subtable order" {
    const allocator = std.testing.allocator;
    var direct = [_]u8{0} ** 38;
    writeU16(&direct, 0, 1);
    writeU16(&direct, 4, 2);
    writeU16(&direct, 6, 10);
    writeU16(&direct, 8, 24);
    writeSingleDelta(&direct, 10, 10, 10);
    writeSingleDelta(&direct, 24, 20, 10);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });
    try single.lookup(view(&direct), 0, 2, &glyphs, allocator, 0, .{});
    // The glyph produced by subtable zero must not cascade into subtable one,
    // while an originally-authored glyph 20 still follows lookup order.
    try std.testing.expectEqualSlices(u16, &.{ 20, 30 }, glyphs.items);

    var extension = [_]u8{0} ** 54;
    writeU16(&extension, 0, 7);
    writeU16(&extension, 4, 2);
    writeU16(&extension, 6, 10);
    writeU16(&extension, 8, 32);
    writeExtension(&extension, 10, 8);
    writeSingleDelta(&extension, 18, 10, 10);
    writeExtension(&extension, 32, 8);
    writeSingleDelta(&extension, 40, 20, 10);
    glyphs.items[0] = 10;
    glyphs.items[1] = 20;
    try single.extensionLookup(
        view(&extension),
        0,
        2,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{ 20, 30 }, glyphs.items);
}

test "single lookup heap scratch releases on malformed later subtable" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 24);
    writeSingleDelta(&bytes, 10, 1, 1);
    writeU16(&bytes, 24, 9); // Unsupported second subtable format.

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendNTimes(allocator, 1, 129);
    try std.testing.expectError(
        error.EndOfStream,
        single.lookup(view(&bytes), 0, 2, &glyphs, allocator, 0, .{}),
    );
}

test "single lookup allocation failure is atomic" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 38;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 24);
    writeSingleDelta(&bytes, 10, 1, 1);
    writeSingleDelta(&bytes, 24, 2, 1);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendNTimes(allocator, 1, 129);
    var failing = std.testing.FailingAllocator.init(
        allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        single.lookup(
            view(&bytes),
            0,
            2,
            &glyphs,
            failing.allocator(),
            0,
            .{},
        ),
    );
    for (glyphs.items) |glyph| {
        try std.testing.expectEqual(@as(u16, 1), glyph);
    }
}

test "contextual and accelerated targets share mutation semantics" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 14;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 8);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 42);
    writeCoverage1(&bytes, 8, 7);
    const table_view = view(&bytes);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 7 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false });
    const run = singleRun(&substituted);

    try std.testing.expect(try single.at(
        table_view,
        0,
        &glyphs,
        1,
        0,
        run,
    ));
    try std.testing.expectEqual(@as(u16, 42), glyphs.items[1]);
    try std.testing.expect(substituted.items[1]);

    glyphs.items[1] = 7;
    substituted.items[1] = false;
    const compact = try build.single.compact(table_view, 0);
    try std.testing.expect(try single.acceleratedAt(
        table_view,
        compact,
        &glyphs,
        1,
        run,
    ));
    try std.testing.expectEqual(@as(u16, 42), glyphs.items[1]);
    try std.testing.expect(substituted.items[1]);
}

fn singleRun(substituted: *std.ArrayList(bool)) Options {
    return .{ .glyph_substituted = substituted };
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeSingleDelta(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 6);
    writeI16(bytes, offset + 4, delta);
    writeCoverage1(bytes, offset + 6, glyph);
}

fn writeExtension(bytes: []u8, offset: usize, payload: u32) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU32(bytes, offset + 4, payload);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeCoverage2(bytes: []u8, offset: usize) void {
    writeU16(bytes, offset, 2);
    writeU16(bytes, offset + 2, 2);
    writeU16(bytes, offset + 4, 10);
    writeU16(bytes, offset + 6, 11);
    writeU16(bytes, offset + 8, 0);
    writeU16(bytes, offset + 10, 20);
    writeU16(bytes, offset + 12, 20);
    writeU16(bytes, offset + 14, 2);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
