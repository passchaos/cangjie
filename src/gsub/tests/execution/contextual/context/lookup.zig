//! Direct, ExtensionSubst, and cached ContextSubst lookup parity.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
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

test "direct and extension context lookups preserve subtable alternatives" {
    const allocator = std.testing.allocator;
    var direct_bytes = [_]u8{0} ** 80;
    fixture.writeLookup(&direct_bytes, 5, &.{ 10, 38 });
    writeCoverageSubtable(&direct_bytes, 10, 7, 2, 0);
    writeCoverageSubtable(&direct_bytes, 38, 1, 2, 1);

    var direct = std.ArrayList(u16).empty;
    defer direct.deinit(allocator);
    try direct.appendSlice(allocator, &.{ 1, 2 });
    try context.lookup(
        Executor,
        validatedView(&direct_bytes),
        0,
        2,
        &direct,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{ 12, 2 }, direct.items);

    var extension_bytes = [_]u8{0} ** 112;
    fixture.writeLookup(&extension_bytes, 7, &.{ 10, 46 });
    fixture.writeExtensionWrapper(&extension_bytes, 10, 18);
    writeCoverageSubtable(&extension_bytes, 18, 7, 2, 0);
    fixture.writeExtensionWrapper(&extension_bytes, 46, 54);
    writeCoverageSubtable(&extension_bytes, 54, 1, 2, 1);
    var extension = std.ArrayList(u16).empty;
    defer extension.deinit(allocator);
    try extension.appendSlice(allocator, &.{ 1, 2 });
    try context.extensionLookup(
        Executor,
        validatedView(&extension_bytes),
        0,
        2,
        &extension,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(u16, direct.items, extension.items);
}

test "cached coverage lookup matches generic output" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    fixture.writeLookup(&bytes, 5, &.{ 10, 38 });
    writeCoverageSubtable(&bytes, 10, 7, 2, 0);
    writeCoverageSubtable(&bytes, 38, 1, 2, 1);
    const view = validatedView(&bytes);
    const cached = try accelerator.build.lookup.one(view, 0, allocator);
    defer {
        var lookups = [_]accelerator.Lookup{cached};
        accelerator.ownership.deinitContents(allocator, &lookups);
    }

    var generic = std.ArrayList(u16).empty;
    defer generic.deinit(allocator);
    try generic.appendSlice(allocator, &.{ 1, 2 });
    try context.lookup(
        Executor,
        view,
        0,
        2,
        &generic,
        allocator,
        0,
        .{},
    );

    var accelerated = std.ArrayList(u16).empty;
    defer accelerated.deinit(allocator);
    try accelerated.appendSlice(allocator, &.{ 1, 2 });
    try context.acceleratedCoverageLookup(
        Executor,
        view,
        &accelerated,
        allocator,
        0,
        .{},
        &cached,
    );
    try std.testing.expectEqualSlices(u16, generic.items, accelerated.items);
}

fn writeCoverageSubtable(
    bytes: []u8,
    base: usize,
    first: u16,
    second: u16,
    lookup_index: u16,
) void {
    fixture.writeU16(bytes, base, 3);
    fixture.writeU16(bytes, base + 2, 2);
    fixture.writeU16(bytes, base + 4, 1);
    fixture.writeU16(bytes, base + 6, 14);
    fixture.writeU16(bytes, base + 8, 20);
    fixture.writeRecord(bytes, base + 10, 0, lookup_index);
    fixture.writeCoverage1(bytes, base + 14, first);
    fixture.writeCoverage1(bytes, base + 20, second);
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
