//! AlternateSubst selection, filtering, random, and lookup-order contracts.

const std = @import("std");
const alternate = @import("../../../../execution/direct/alternate/root.zig");
const feature = @import("../../../../feature/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

test "alternate selection is one-based and updates metadata" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 20;
    writeAlternate(&bytes, 0, 10, &.{ 20, 30 });

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.append(allocator, false);
    try alternate.subtable(view(&bytes), 0, &glyphs, 0, .{
        .active_feature_value = 2,
        .glyph_substituted = &substituted,
    });
    try std.testing.expectEqualSlices(u16, &.{30}, glyphs.items);
    try std.testing.expect(substituted.items[0]);

    glyphs.items[0] = 10;
    substituted.items[0] = false;
    try alternate.subtable(view(&bytes), 0, &glyphs, 0, .{
        .active_feature_value = 0,
        .glyph_substituted = &substituted,
    });
    try std.testing.expectEqualSlices(u16, &.{10}, glyphs.items);
    try std.testing.expect(!substituted.items[0]);
}

test "alternate selection honors lookup flags and source scope" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 20;
    writeAlternate(&bytes, 0, 3, &.{30});
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 3, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    const source_features = [_]u32{ 0x63616c74, 0 };
    var classes = [_]u16{0} ** 4;
    classes[3] = 3;

    try alternate.subtable(view(&bytes), 0, &glyphs, 0x0008, .{
        .glyph_classes = &classes,
    });
    try std.testing.expectEqualSlices(u16, &.{ 3, 3 }, glyphs.items);

    classes[3] = 0;
    try alternate.subtable(view(&bytes), 0, &glyphs, 0, .{
        .glyph_source_indices = &sources,
        .source_features = &source_features,
        .active_source_feature = source_features[0],
    });
    try std.testing.expectEqualSlices(u16, &.{ 30, 3 }, glyphs.items);
}

test "direct and extension alternate lookups do not cascade" {
    const allocator = std.testing.allocator;
    var direct = [_]u8{0} ** 50;
    writeU16(&direct, 0, 3);
    writeU16(&direct, 4, 2);
    writeU16(&direct, 6, 10);
    writeU16(&direct, 8, 30);
    writeAlternate(&direct, 10, 10, &.{20});
    writeAlternate(&direct, 30, 20, &.{30});
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });
    try alternate.lookup(view(&direct), 0, 2, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(u16, &.{ 20, 30 }, glyphs.items);

    var extension = [_]u8{0} ** 66;
    writeU16(&extension, 0, 7);
    writeU16(&extension, 4, 2);
    writeU16(&extension, 6, 10);
    writeU16(&extension, 8, 38);
    writeExtension(&extension, 10, 3, 8);
    writeAlternate(&extension, 18, 10, &.{20});
    writeExtension(&extension, 38, 3, 8);
    writeAlternate(&extension, 46, 20, &.{30});
    glyphs.items[0] = 10;
    glyphs.items[1] = 20;
    try alternate.extensionLookup(
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

test "alternate random selection follows wrapping minstd sequence" {
    var state: u32 = 1;
    const expected = [_]u32{ 2, 1, 1, 1, 1, 1, 3, 3, 1, 2, 2, 3 };
    for (expected) |choice| {
        try std.testing.expectEqual(
            choice,
            alternate.randomIndex(&state, 3),
        );
    }

    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 22;
    writeAlternate(&bytes, 0, 10, &.{ 20, 30, 40 });
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 10 });
    state = 1;
    try alternate.subtable(view(&bytes), 0, &glyphs, 0, randomRun(&state));
    try std.testing.expectEqualSlices(u16, &.{ 30, 20 }, glyphs.items);
}

test "alternate random selection requires explicit state" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 20;
    writeAlternate(&bytes, 0, 10, &.{ 20, 30 });
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);
    try std.testing.expectError(
        error.InvalidShapingInput,
        alternate.subtable(view(&bytes), 0, &glyphs, 0, .{
            .active_feature_value = feature.random_value,
            .active_feature_random = true,
        }),
    );
    try std.testing.expectEqualSlices(u16, &.{10}, glyphs.items);
}

test "alternate lookup allocation failure is atomic" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 50;
    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 30);
    writeAlternate(&bytes, 10, 10, &.{20});
    writeAlternate(&bytes, 30, 20, &.{30});
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendNTimes(allocator, 10, 129);
    var failing = std.testing.FailingAllocator.init(
        allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        alternate.lookup(
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
        try std.testing.expectEqual(@as(u16, 10), glyph);
    }
}

fn randomRun(state: *u32) Options {
    return .{
        .active_feature_value = feature.random_value,
        .active_feature_random = true,
        .random_state = state,
    };
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeAlternate(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    alternates: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 8);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 14);
    writeCoverage1(bytes, offset + 8, glyph);
    writeU16(bytes, offset + 14, @intCast(alternates.len));
    for (alternates, 0..) |alternate_glyph, index| {
        writeU16(bytes, offset + 16 + index * 2, alternate_glyph);
    }
}

fn writeExtension(
    bytes: []u8,
    offset: usize,
    lookup_type: u16,
    payload: u32,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, lookup_type);
    writeU32(bytes, offset + 4, payload);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
