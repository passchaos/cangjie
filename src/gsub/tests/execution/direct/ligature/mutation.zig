//! LigatureSubst contextual Change, sidecar commit, and OOM atomicity.

const std = @import("std");
const ligature = @import("../../../../execution/direct/ligature/root.zig");
const ligature_provenance = @import("../../../../../ligature_provenance.zig");
const table = @import("../../../../table/root.zig");

test "contextual ligature reports physical component offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;
    writeLigatureSubtable(&bytes, 0, 1, &.{2}, 40);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 9, 2 });
    const classes = [_]u16{ 0, 1, 1, 1, 1, 1, 1, 1, 1, 3 };
    const change = (try ligature.at(
        view(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0x0008,
        .{ .glyph_classes = &classes },
    )).?;
    try std.testing.expectEqual(@as(usize, 2), change.removed_len);
    try std.testing.expectEqual(@as(usize, 1), change.inserted_len);
    try std.testing.expectEqual(@as(usize, 2), change.component_offsets[1]);
    try std.testing.expectEqualSlices(u16, &.{ 40, 9 }, glyphs.items);
}

test "ligature commit keeps every sidecar aligned" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;
    writeLigatureSubtable(&bytes, 0, 1, &.{2}, 40);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(allocator);
    try clusters.appendSlice(allocator, &.{ 0, 1 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(allocator);
    try substituted.appendSlice(allocator, &.{ false, false });
    var provenance = ligature_provenance.Store{};
    defer provenance.deinit(allocator);
    try provenance.infos.resize(allocator, 2);
    @memset(provenance.infos.items, .{});
    _ = try ligature.at(
        view(&bytes),
        0,
        &glyphs,
        0,
        allocator,
        0,
        .{
            .glyph_source_indices = &sources,
            .glyph_cluster_indices = &clusters,
            .glyph_substituted = &substituted,
            .ligature_components = &provenance,
        },
    );
    try std.testing.expectEqualSlices(u16, &.{40}, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{0}, sources.items);
    try std.testing.expectEqualSlices(usize, &.{0}, clusters.items);
    try std.testing.expectEqualSlices(bool, &.{true}, substituted.items);
    try std.testing.expectEqual(@as(usize, 1), provenance.infos.items.len);
    try std.testing.expect(provenance.infos.items[0].flags.ligated);
}

test "ligature provenance allocation failure leaves the run untouched" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 30;
    writeLigatureSubtable(&bytes, 0, 1, &.{2}, 40);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    var provenance = ligature_provenance.Store{};
    defer provenance.deinit(allocator);
    try provenance.infos.resize(allocator, 2);
    @memset(provenance.infos.items, .{});
    provenance.sources.shrinkAndFree(allocator, 0);
    var failing = std.testing.FailingAllocator.init(
        allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        ligature.at(
            view(&bytes),
            0,
            &glyphs,
            0,
            failing.allocator(),
            0,
            .{
                .glyph_source_indices = &sources,
                .ligature_components = &provenance,
            },
        ),
    );
    try std.testing.expectEqualSlices(u16, &.{ 1, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, sources.items);
    try std.testing.expectEqual(@as(usize, 2), provenance.infos.items.len);
    try std.testing.expectEqual(@as(usize, 0), provenance.sources.items.len);
}

fn view(bytes: []const u8) table.View {
    return .{ .data = bytes, .offset = 0, .length = bytes.len };
}

fn writeLigatureSubtable(
    bytes: []u8,
    offset: usize,
    first: u16,
    components: []const u16,
    output: u16,
) void {
    const set = offset + 8;
    const definition = set + 4;
    const coverage = definition + 4 + components.len * 2;
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(coverage - offset));
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, @intCast(set - offset));
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, @intCast(definition - set));
    writeU16(bytes, definition, output);
    writeU16(bytes, definition + 2, @intCast(components.len + 1));
    for (components, 0..) |component, index| {
        writeU16(bytes, definition + 4 + index * 2, component);
    }
    writeU16(bytes, coverage, 1);
    writeU16(bytes, coverage + 2, 1);
    writeU16(bytes, coverage + 4, first);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
