//! Ligature provenance component folding and GPOS base-mark hints.

const std = @import("std");
const ligature = @import("../../../../execution/direct/ligature/root.zig");
const ligature_provenance = @import("../../../../../ligature_provenance.zig");
const Options = @import("../../../../runtime/options.zig").Options;

test "provenance folds non-first MultipleSubst pieces" {
    const allocator = std.testing.allocator;
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 2, 2, 4 });
    var store = ligature_provenance.Store{};
    defer store.deinit(allocator);
    try store.infos.appendSlice(allocator, &.{
        .{},
        .{ .flags = .{ .multiplied = true, .multiple_component = 0 } },
        .{ .flags = .{ .multiplied = true, .multiple_component = 1 } },
        .{},
    });
    var offsets = [_]usize{0} ** ligature.max_components;
    offsets[1] = 1;
    offsets[2] = 2;
    offsets[3] = 3;
    const info = try ligature.componentInfo(
        allocator,
        .{
            .glyph_source_indices = &sources,
            .ligature_components = &store,
        },
        0,
        match(50, 4, &offsets),
    );
    try std.testing.expectEqual(@as(u8, 3), info.component_count);
    try std.testing.expectEqual(@as(u8, 4), info.source_count);
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 2, 2, 4 },
        store.componentSources(info).?,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 2, 4 },
        store.logicalComponentSources(info).?,
    );
}

test "base plus marks records the GPOS attachment hint" {
    const allocator = std.testing.allocator;
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    var store = ligature_provenance.Store{};
    defer store.deinit(allocator);
    try store.infos.resize(allocator, 2);
    @memset(store.infos.items, .{});
    var offsets = [_]usize{0} ** ligature.max_components;
    offsets[1] = 1;
    const base_mark = [_]u21{ 0x05e0, 0x05bc };
    const info = try ligature.componentInfo(
        allocator,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &base_mark,
            .ligature_components = &store,
        },
        0,
        match(83, 2, &offsets),
    );
    try std.testing.expect(info.flags.base_mark_ligature);
    const mark_mark = [_]u21{ 0x05b8, 0x05bd };
    const mark_info = try ligature.componentInfo(
        allocator,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &mark_mark,
            .ligature_components = &store,
        },
        0,
        match(97, 2, &offsets),
    );
    try std.testing.expect(!mark_info.flags.base_mark_ligature);
}

test "provenance preserves a synthetic base from any component" {
    const allocator = std.testing.allocator;
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(allocator);
    try sources.appendSlice(allocator, &.{ 0, 1 });
    var store = ligature_provenance.Store{};
    defer store.deinit(allocator);
    try store.infos.appendSlice(allocator, &.{
        .{},
        .{ .flags = .{ .synthetic_base = true } },
    });
    var offsets = [_]usize{0} ** ligature.max_components;
    offsets[1] = 1;

    const info = try ligature.componentInfo(
        allocator,
        .{
            .glyph_source_indices = &sources,
            .ligature_components = &store,
        },
        0,
        match(40, 2, &offsets),
    );
    try std.testing.expect(info.flags.synthetic_base);
}

fn match(
    output: u16,
    count: usize,
    offsets: *const [ligature.max_components]usize,
) ligature.Match {
    return .{
        .ligature = output,
        .component_count = count,
        .component_offsets = offsets,
        .match_end = count,
    };
}
