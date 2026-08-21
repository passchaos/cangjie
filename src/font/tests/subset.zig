const std = @import("std");
const public = @import("../../api/font/root.zig");
const test_font = @import("../../test_font.zig");

test "preserve-GID TrueType subset keeps selected glyphs and cmap only" {
    const allocator = std.testing.allocator;
    const source = try test_font.buildFallbackMarkTtf(allocator);
    defer allocator.free(source);
    var face = try public.Face.parse(allocator, source);
    defer face.deinit();

    var subset = try public.subset.trueTypeAlloc(
        allocator,
        &face,
        &.{1},
        .{},
    );
    defer subset.deinit();
    try std.testing.expect(subset.program.len < source.len);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, subset.retained_glyphs);

    var parsed = try public.Face.parse(allocator, subset.program);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u16, 4), parsed.properties().glyph_count);
    try std.testing.expectEqual(@as(u16, 1), try parsed.glyphs().index('X'));
    try std.testing.expectEqual(@as(u16, 0), try parsed.glyphs().index('x'));
    try std.testing.expect((try parsed.glyphs().bounds(1)).x_max > 0);
    try std.testing.expectEqual(@as(i16, 0), (try parsed.glyphs().bounds(2)).x_max);
}

test "preserve-GID TrueType subset closes compound components" {
    const allocator = std.testing.allocator;
    const source = try test_font.buildCompoundPointMatchTtf(allocator);
    defer allocator.free(source);
    var face = try public.Face.parse(allocator, source);
    defer face.deinit();

    var subset = try public.subset.trueTypeAlloc(
        allocator,
        &face,
        &.{3},
        .{},
    );
    defer subset.deinit();
    try std.testing.expectEqualSlices(
        u16,
        &.{ 0, 1, 2, 3 },
        subset.retained_glyphs,
    );

    var parsed = try public.Face.parse(allocator, subset.program);
    defer parsed.deinit();
    var outline = try parsed.glyphs().outline(allocator, 3);
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 9), outline.commands.items.len);
}

test "preserve-GID TrueType subset keeps or strips variation families" {
    const allocator = std.testing.allocator;
    const source = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(source);
    var face = try public.Face.parse(allocator, source);
    defer face.deinit();

    var variable = try public.subset.trueTypeAlloc(
        allocator,
        &face,
        &.{1},
        .{},
    );
    defer variable.deinit();
    var variable_face = try public.Face.parse(allocator, variable.program);
    defer variable_face.deinit();
    const axes = try variable_face.variations().axes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 1), axes.len);
    const varied = try variable_face.glyphs().boundsAt(1, &.{1});
    const default = try variable_face.glyphs().bounds(1);
    try std.testing.expect(varied.x_max != default.x_max);

    var static = try public.subset.trueTypeAlloc(
        allocator,
        &face,
        &.{1},
        .{ .preserve_variations = false },
    );
    defer static.deinit();
    var static_face = try public.Face.parse(allocator, static.program);
    defer static_face.deinit();
    const static_axes = try static_face.variations().axes(allocator);
    defer allocator.free(static_axes);
    try std.testing.expectEqual(@as(usize, 0), static_axes.len);
    try std.testing.expectEqual(default, try static_face.glyphs().bounds(1));
}

test "preserve-GID TrueType subset validates limits and unsupported profiles" {
    const allocator = std.testing.allocator;
    const source = try test_font.buildCompoundPointMatchTtf(allocator);
    defer allocator.free(source);
    var face = try public.Face.parse(allocator, source);
    defer face.deinit();

    try std.testing.expectError(
        error.InvalidFontSubsetOptions,
        public.subset.trueTypeAlloc(allocator, &face, &.{3}, .{
            .max_output_bytes = 0,
        }),
    );
    try std.testing.expectError(
        error.InvalidFontSubsetGlyph,
        public.subset.trueTypeAlloc(allocator, &face, &.{5}, .{}),
    );
    try std.testing.expectError(
        error.FontSubsetGlyphLimitExceeded,
        public.subset.trueTypeAlloc(allocator, &face, &.{3}, .{
            .max_retained_glyphs = 3,
        }),
    );
    try std.testing.expectError(
        error.FontSubsetComponentLimitExceeded,
        public.subset.trueTypeAlloc(allocator, &face, &.{3}, .{
            .max_component_edges = 1,
        }),
    );
    const mapping_source = try test_font.buildFallbackMarkTtf(allocator);
    defer allocator.free(mapping_source);
    var mapping_face = try public.Face.parse(allocator, mapping_source);
    defer mapping_face.deinit();
    try std.testing.expectError(
        error.FontSubsetCmapLimitExceeded,
        public.subset.trueTypeAlloc(allocator, &mapping_face, &.{2}, .{
            .max_cmap_mappings = 1,
        }),
    );
    try std.testing.expectError(
        error.FontSubsetOutputLimitExceeded,
        public.subset.trueTypeAlloc(allocator, &face, &.{1}, .{
            .max_output_bytes = 64,
        }),
    );

    const color = try test_font.buildColorTtf(allocator);
    defer allocator.free(color);
    var color_face = try public.Face.parse(allocator, color);
    defer color_face.deinit();
    try std.testing.expectError(
        error.UnsupportedFontSubset,
        public.subset.trueTypeAlloc(allocator, &color_face, &.{1}, .{}),
    );
}

test "preserve-GID TrueType subset is leak free under allocation failure" {
    const source = try test_font.buildCompoundPointMatchTtf(
        std.testing.allocator,
    );
    defer std.testing.allocator.free(source);
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        struct {
            fn run(allocator: std.mem.Allocator, bytes: []const u8) !void {
                var face = try public.Face.parse(allocator, bytes);
                defer face.deinit();
                var subset = try public.subset.trueTypeAlloc(
                    allocator,
                    &face,
                    &.{3},
                    .{},
                );
                defer subset.deinit();
                var parsed = try public.Face.parse(allocator, subset.program);
                defer parsed.deinit();
                var outline = try parsed.glyphs().outline(allocator, 3);
                defer outline.deinit();
            }
        }.run,
        .{source},
    );
}
