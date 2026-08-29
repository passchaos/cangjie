//! Nested target ordering, cardinality, and Extension contracts.

const std = @import("std");
const acceleration = @import("../../../../accelerator/root.zig");
const nested = @import("../../../../execution/contextual/nested/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

const Executor = struct {
    pub fn applyExtensionSubtable(
        _: table.View,
        _: usize,
        _: *std.ArrayList(u16),
        _: std.mem.Allocator,
        _: u16,
        _: Options,
    ) nested.Error!void {
        return error.BadGsub;
    }

    pub fn applyExtensionChainingLookup(
        _: table.View,
        _: usize,
        _: u16,
        _: *std.ArrayList(u16),
        _: std.mem.Allocator,
        _: u16,
        _: Options,
    ) nested.Error!void {
        return error.BadGsub;
    }

    pub fn applyChainingLookup(
        _: table.View,
        _: usize,
        _: u16,
        _: *std.ArrayList(u16),
        _: std.mem.Allocator,
        _: u16,
        _: Options,
        _: ?*const acceleration.Lookup,
    ) nested.Error!void {
        return error.BadGsub;
    }

    pub fn applyNested(
        _: table.View,
        _: *std.ArrayList(u16),
        _: usize,
        _: u16,
        _: std.mem.Allocator,
        _: Options,
    ) nested.Error!nested.Change {
        return error.BadGsub;
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "nested multiple lookup reports real target cardinality" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 52;
    writeHeader(&bytes, 10, 1);
    writeLookup(&bytes, 14, 2, &.{8});
    const subtable = 22;
    writeU16(&bytes, subtable, 1);
    writeU16(&bytes, subtable + 2, 8); // Coverage.
    writeU16(&bytes, subtable + 4, 1);
    writeU16(&bytes, subtable + 6, 14); // Sequence.
    writeCoverage(&bytes, subtable + 8, 5);
    writeU16(&bytes, subtable + 14, 2);
    writeU16(&bytes, subtable + 16, 8);
    writeU16(&bytes, subtable + 18, 9);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 5, 2 });
    const change = try nested.apply(
        Executor,
        view(&bytes),
        &glyphs,
        1,
        0,
        allocator,
        .{},
    );
    try std.testing.expectEqual(@as(usize, 1), change.removed_len);
    try std.testing.expectEqual(@as(usize, 2), change.inserted_len);
    try std.testing.expectEqualSlices(u16, &.{ 1, 8, 9, 2 }, glyphs.items);
}

test "nested extension single targets one glyph without scanning the run" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;
    writeHeader(&bytes, 10, 1);
    writeLookup(&bytes, 14, 7, &.{8});
    const wrapper = 22;
    writeU16(&bytes, wrapper, 1);
    writeU16(&bytes, wrapper + 2, 1);
    writeU32(&bytes, wrapper + 4, 8);
    const single = wrapper + 8;
    writeU16(&bytes, single, 1);
    writeU16(&bytes, single + 2, 6);
    writeU16(&bytes, single + 4, 1);
    writeCoverage(&bytes, single + 6, 5);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 5, 5 });
    _ = try nested.apply(
        Executor,
        view(&bytes),
        &glyphs,
        1,
        0,
        allocator,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{ 5, 6 }, glyphs.items);
}

test "nested extension single uses prepared compact sidecar" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    writeHeader(&bytes, 10, 1);
    writeLookup(&bytes, 14, 7, &.{8});

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 5, 5 });
    const lookups = [_]acceleration.Lookup{.{
        .lookup_offset = 14,
        .lookup_type = 7,
        .subtable_count = 1,
        .extension_lookup_type = 1,
        .single_subst = .{
            .enabled = true,
            .single_mapping = true,
            .single_from = 5,
            .single_to = 9,
        },
    }};
    _ = try nested.apply(
        Executor,
        view(&bytes),
        &glyphs,
        1,
        0,
        allocator,
        .{ .lookup_accelerators = &lookups },
    );
    try std.testing.expectEqualSlices(u16, &.{ 5, 9 }, glyphs.items);
}

test "JSTF-disabled nested substitution lookup is skipped" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;
    writeHeader(&bytes, 10, 1);
    writeLookup(&bytes, 14, 1, &.{8});
    const single = 22;
    writeU16(&bytes, single, 1);
    writeU16(&bytes, single + 2, 6);
    writeU16(&bytes, single + 4, 1);
    writeCoverage(&bytes, single + 6, 5);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    _ = try nested.apply(
        Executor,
        view(&bytes),
        &glyphs,
        0,
        0,
        allocator,
        .{ .disabled_lookups = &.{0} },
    );
    try std.testing.expectEqualSlices(u16, &.{5}, glyphs.items);
}

fn writeHeader(bytes: []u8, lookup_list: u16, lookup_count: u16) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, lookup_list);
    writeU16(bytes, lookup_list, lookup_count);
    writeU16(bytes, lookup_list + 2, 4);
}

fn writeLookup(
    bytes: []u8,
    offset: usize,
    lookup_type: u16,
    children: []const u16,
) void {
    writeU16(bytes, offset, lookup_type);
    writeU16(bytes, offset + 2, 0);
    writeU16(bytes, offset + 4, @intCast(children.len));
    for (children, 0..) |child, index| {
        writeU16(bytes, offset + 6 + index * 2, child);
    }
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
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

fn view(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
