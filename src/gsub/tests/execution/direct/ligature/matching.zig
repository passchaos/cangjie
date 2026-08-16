//! LigatureSubst authored preference and shaping-transparent glyph rules.

const std = @import("std");
const build = @import("../../../../accelerator/build/root.zig");
const ligature = @import("../../../../execution/direct/ligature/root.zig");
const ownership = @import("../../../../accelerator/ownership.zig");
const table = @import("../../../../table/root.zig");

test "direct matcher preserves authored LigatureSet preference" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 6);
    writeU16(&bytes, 4, 14);
    writeU16(&bytes, 6, 40);
    writeU16(&bytes, 8, 2);
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 14, 50);
    writeU16(&bytes, 16, 3);
    writeU16(&bytes, 18, 2);
    writeU16(&bytes, 20, 3);
    var offsets: [ligature.max_components]usize = undefined;

    const match = (try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 2, 3 },
        0,
        0,
        .{},
        &offsets,
    )).?;
    try std.testing.expectEqual(@as(u16, 40), match.ligature);
    try std.testing.expectEqual(@as(usize, 2), match.component_count);
}

test "direct matcher applies CGJ and variation-selector visibility rules" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 4);
    writeU16(&bytes, 4, 40);
    writeU16(&bytes, 6, 2);
    writeU16(&bytes, 8, 2);
    var offsets: [ligature.max_components]usize = undefined;
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2 });

    const cgj = [_]u21{ 'A', 0x034f, 'B' };
    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 9, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &cgj,
        },
        &offsets,
    )) != null);

    const blocked_cgj = [_]u21{ 0x064e, 0x034f, 0x0651 };
    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 0, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &blocked_cgj,
        },
        &offsets,
    )) == null);

    const selector = [_]u21{ 'A', 0xfe00, 'B' };
    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 0, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &selector,
        },
        &offsets,
    )) != null);
    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 0, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &selector,
            .visible_variation_selectors = true,
        },
        &offsets,
    )) == null);

    const selector_with_glyph = [_]u21{ 'A', 0xfe00, 'B' };
    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 9, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &selector_with_glyph,
        },
        &offsets,
    )) == null);

    const mongolian_fvs = [_]u21{ 0x1868, 0x180d, 0x180a };
    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 0, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_codepoints = &mongolian_fvs,
        },
        &offsets,
    )) == null);
}

test "direct matcher stops at source syllable boundaries" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 4);
    writeU16(&bytes, 4, 40);
    writeU16(&bytes, 6, 2);
    writeU16(&bytes, 8, 2);
    var offsets: [ligature.max_components]usize = undefined;
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });
    const syllables = [_]u8{ 1, 2 };

    try std.testing.expect((try ligature.directMatch(
        view(&bytes),
        0,
        &.{ 1, 2 },
        0,
        0,
        .{
            .glyph_source_indices = &sources,
            .source_syllables = &syllables,
            .match_source_syllable = true,
        },
        &offsets,
    )) == null);
}

test "accelerated and prefiltered matchers preserve component offsets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeLigatureSubtable(&bytes, 0, 1, &.{ 2, 3 }, 40);
    const accelerated = try build.ligature.build(
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        0,
        allocator,
    );
    defer ownership.deinitContents(allocator, &.{.{
        .ligature_subst = accelerated,
    }});
    const set = ligature.setForGlyph(accelerated, 1).?;
    const classes = [_]u16{ 0, 1, 1, 1, 3 };
    var direct_offsets: [ligature.max_components]usize = undefined;
    var prefiltered_offsets: [ligature.max_components]usize = undefined;
    const glyphs = [_]u16{ 1, 4, 2, 3 };

    const direct = ligature.acceleratedMatch(
        accelerated,
        set,
        &glyphs,
        0,
        0x0008,
        .{ .glyph_classes = &classes },
        &direct_offsets,
    ).?;
    const prefiltered = ligature.acceleratedPrefilteredMatch(
        accelerated,
        set,
        &glyphs,
        0,
        0x0008,
        .{ .glyph_classes = &classes },
        &prefiltered_offsets,
    ).?;
    try std.testing.expectEqual(direct.ligature, prefiltered.ligature);
    try std.testing.expectEqualSlices(
        usize,
        direct.component_offsets[0..direct.component_count],
        prefiltered.component_offsets[0..prefiltered.component_count],
    );
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
    writeCoverage1(bytes, coverage, first);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
