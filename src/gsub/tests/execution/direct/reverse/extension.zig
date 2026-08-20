//! Extension-wrapped reverse lookup accelerator parity.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const reverse = @import("../../../../execution/direct/reverse/root.zig");
const fixture = @import("fixture.zig");
const table = @import("../../../../table/root.zig");

test "extension reverse accelerator preserves authored subtable order" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;
    fixture.writeLookup(&bytes, 7, 0, &.{ 10, 44 });
    fixture.writeExtensionWrapper(&bytes, 10, 18);
    fixture.writeReverse(&bytes, 18, 2, 9, &.{}, &.{3});
    fixture.writeExtensionWrapper(&bytes, 44, 52);
    fixture.writeReverse(&bytes, 52, 2, 10, &.{}, &.{});

    const view = validatedView(&bytes);
    const cached = try accelerator.build.lookup.one(view, 0, allocator);
    defer {
        var lookups = [_]accelerator.Lookup{cached};
        accelerator.ownership.deinitContents(allocator, &lookups);
    }
    try std.testing.expect(cached.reverse_chaining_groups.len != 0);

    try expectGenericAndCached(
        view,
        &cached,
        &.{ 2, 3 },
        &.{ 9, 3 },
        allocator,
    );
    try expectGenericAndCached(
        view,
        &cached,
        &.{ 2, 4 },
        &.{ 10, 4 },
        allocator,
    );
}

test "exact extension reverse accelerator selects the full context" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 110;
    fixture.writeLookup(&bytes, 7, 0, &.{ 10, 60 });
    fixture.writeExtensionWrapper(&bytes, 10, 18);
    fixture.writeReverse(&bytes, 18, 2, 9, &.{1}, &.{ 3, 4 });
    fixture.writeExtensionWrapper(&bytes, 60, 68);
    fixture.writeReverse(&bytes, 68, 2, 10, &.{1}, &.{ 3, 5 });

    const view = validatedView(&bytes);
    const cached = try accelerator.build.lookup.one(view, 0, allocator);
    defer {
        var lookups = [_]accelerator.Lookup{cached};
        accelerator.ownership.deinitContents(allocator, &lookups);
    }
    try std.testing.expectEqual(
        @as(usize, 2),
        cached.reverse_chaining_exact_contexts.len,
    );

    try expectGenericAndCached(
        view,
        &cached,
        &.{ 1, 2, 3, 4 },
        &.{ 1, 9, 3, 4 },
        allocator,
    );
    try expectGenericAndCached(
        view,
        &cached,
        &.{ 1, 2, 3, 5 },
        &.{ 1, 10, 3, 5 },
        allocator,
    );
    try expectGenericAndCached(
        view,
        &cached,
        &.{ 1, 2, 3, 6 },
        &.{ 1, 2, 3, 6 },
        allocator,
    );
}

fn expectGenericAndCached(
    view: table.View,
    cached: *const accelerator.Lookup,
    input: []const u16,
    expected: []const u16,
    allocator: std.mem.Allocator,
) !void {
    var generic = std.ArrayList(u16).empty;
    defer generic.deinit(allocator);
    try generic.appendSlice(allocator, input);
    try reverse.extensionLookup(view, 0, 2, &generic, 0, .{}, null);

    var accelerated = std.ArrayList(u16).empty;
    defer accelerated.deinit(allocator);
    try accelerated.appendSlice(allocator, input);
    try reverse.extensionLookup(view, 0, 2, &accelerated, 0, .{}, cached);

    try std.testing.expectEqualSlices(u16, expected, generic.items);
    try std.testing.expectEqualSlices(u16, generic.items, accelerated.items);
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
