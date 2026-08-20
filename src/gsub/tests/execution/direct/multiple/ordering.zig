//! MultipleSubst filtering, accelerator, and lookup-order contracts.

const std = @import("std");
const accelerator = @import("../../../../accelerator/model.zig");
const multiple = @import("../../../../execution/direct/multiple/root.zig");
const table = @import("../../../../table/root.zig");

test "multiple lookup honors filters and source scope" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeMultiple(&bytes, 0, 3, &.{ 30, 31 });
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 3, 3 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    const source_features = [_]u32{ 0x66696e61, 0 };
    var classes = [_]u16{0} ** 4;
    classes[3] = 3;

    try multiple.subtable(view(&bytes), 0, &glyphs, allocator, 0x0008, .{
        .glyph_classes = &classes,
    });
    try std.testing.expectEqualSlices(u16, &.{ 3, 3 }, glyphs.items);

    classes[3] = 0;
    try multiple.subtable(view(&bytes), 0, &glyphs, allocator, 0, .{
        .glyph_source_indices = &sources,
        .source_features = &source_features,
        .active_source_feature = source_features[0],
    });
    try std.testing.expectEqualSlices(u16, &.{ 30, 31, 3 }, glyphs.items);
}

test "direct and extension multiple lookups do not cascade" {
    const allocator = std.testing.allocator;
    var direct = [_]u8{0} ** 58;
    writeU16(&direct, 0, 2);
    writeU16(&direct, 4, 2);
    writeU16(&direct, 6, 10);
    writeU16(&direct, 8, 34);
    writeMultiple(&direct, 10, 10, &.{ 20, 21 });
    writeMultiple(&direct, 34, 20, &.{ 30, 31 });

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 10, 20 });
    try multiple.lookup(view(&direct), 0, 2, &glyphs, allocator, 0, .{});
    try std.testing.expectEqualSlices(
        u16,
        &.{ 20, 21, 30, 31 },
        glyphs.items,
    );

    var extension = [_]u8{0} ** 82;
    writeU16(&extension, 0, 7);
    writeU16(&extension, 4, 2);
    writeU16(&extension, 6, 10);
    writeU16(&extension, 8, 50);
    writeExtension(&extension, 10, 2, 8);
    writeMultiple(&extension, 18, 10, &.{ 20, 21 });
    writeExtension(&extension, 50, 2, 8);
    writeMultiple(&extension, 58, 20, &.{ 30, 31 });
    glyphs.clearRetainingCapacity();
    try glyphs.appendSlice(allocator, &.{ 10, 20 });
    try multiple.extensionLookup(
        view(&extension),
        0,
        2,
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{ 20, 21, 30, 31 },
        glyphs.items,
    );
}

test "accelerated singleton uses its predecoded substitute" {
    const allocator = std.testing.allocator;
    // The table contains no readable sequence payload. A validated accelerator
    // has already decoded singleton output and should not parse it again.
    const bytes = [_]u8{};
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);
    const entries = [_]accelerator.MultipleEntry{.{
        .glyph = 7,
        .sequence_offset = 99,
        .glyph_count = 1,
        .single_to = 42,
    }};
    try multiple.accelerated(
        view(&bytes),
        .{ .entries = &entries },
        &glyphs,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{42}, glyphs.items);
    try std.testing.expectEqual(
        entries[0],
        multiple.entryForGlyph(&entries, 7).?,
    );
    try std.testing.expect(multiple.entryForGlyph(&entries, 8) == null);
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeMultiple(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    replacements: []const u16,
) void {
    const coverage_offset: u16 = @intCast(10 + replacements.len * 2);
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, coverage_offset);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, offset + 10 + index * 2, replacement);
    }
    writeCoverage1(bytes, offset + coverage_offset, glyph);
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
