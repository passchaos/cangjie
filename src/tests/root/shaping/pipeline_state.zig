//! Reusable shaping scratch and attachment pipeline invariants.

const std = @import("std");
const support = @import("../support.zig");

const Font = support.Font;
const GlyphPosition = support.GlyphPosition;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const attachment = @import("../../../attachment.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const position_attachments =
    @import("../../../shaping/pipeline/positioning/attachments.zig");
const unicode = @import("../../../unicode.zig");

test "attachment scratch is needed only for emitted attachment adjustments" {
    try std.testing.expect(!position_attachments.hasGpos(&.{
        .{ .index = 0, .x_advance = -20, .pair_positioned = true },
    }));
    try std.testing.expect(position_attachments.hasGpos(&.{
        .{ .index = 0, .attachment_type = .mark, .attachment_parent_index = 1 },
    }));
    try std.testing.expect(position_attachments.hasGpos(&.{
        .{ .index = 0, .attachment_type = .cursive, .attachment_parent_index = 1 },
    }));
}

test "attachment remapping scratch follows emitted adjustment type across runs" {
    const test_font = @import("../../../test_font.zig");
    const mark_bytes = try test_font.buildMinimalGposMarkTtf(std.testing.allocator);
    defer std.testing.allocator.free(mark_bytes);
    var mark_font = try Font.parse(std.testing.allocator, mark_bytes);
    defer mark_font.deinit();
    const pair_bytes = try test_font.buildMinimalGposTtf(std.testing.allocator);
    defer std.testing.allocator.free(pair_bytes);
    var pair_font = try Font.parse(std.testing.allocator, pair_bytes);
    defer pair_font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const mark_run = try TextShaper.shapeUtf8(&mark_font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), mark_run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.shape_scratch.attachment_links.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.shape_scratch.glyph_output_indices.items.len);

    // Shape into the same reusable buffer. Its clear step drops the old lengths,
    // and PairPos does not regrow arrays that it cannot consume.
    const pair_run = try TextShaper.shapeUtf8(&pair_font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), pair_run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.attachment_links.items.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.glyph_output_indices.items.len);
}

test "ordinary shaping clears and leaves stch sidecar empty" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    // Model reuse after a prior stretch-bearing segment. ShapeScratch.clear
    // must drop that old length, and the ordinary output loop must not regrow
    // the sidecar with `.none` entries.
    try buffer.shape_scratch.stch_actions.append(
        std.testing.allocator,
        @intFromEnum(ligature_provenance.StchAction.fixed),
    );
    const run = try TextShaper.shapeUtf8(&font, &buffer, "AA", 20);
    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectEqual(@as(usize, 0), buffer.shape_scratch.stch_actions.items.len);
}

test "USE shaping zeroes synthesized nonspacing marks without a GDEF table" {
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtf(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    var font = try Font.parse(std.testing.allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(std.testing.allocator);
    defer buffer.deinit();

    const features = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("kern"), .enabled = false },
    };
    const run = try TextShaper.shapeUtf8WithOptions(
        &font,
        &buffer,
        "𑀓𑀸", // BRAHMI LETTER KA + Mn VOWEL SIGN AA.
        1000,
        .{ .script_tag = .brah, .features = &features },
    );

    try std.testing.expectEqual(@as(usize, 2), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 800), run.glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), run.glyphs[1].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -800), run.glyphs[1].x_offset, 0.001);
}

test "mark attachment propagation keeps long advances in user space" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 50000 },
        .{ .glyph_id = 2, .codepoint = 'A', .cluster = 1, .x_advance = 0, .x_offset = 12 },
    };
    var links = [_]attachment.Link{
        .{},
        .{ .kind = .mark, .parent_index = 0 },
    };

    attachment.propagateOffsets(GlyphPosition, &glyphs, &links, .forward, .horizontal);

    // Large paragraphs can place a mark many glyph advances after its base
    // before MarkBase/MarkLig positioning pulls it back. This offset is well
    // within f32 layout range and must not be converted back through i16.
    try std.testing.expectApproxEqAbs(@as(f32, 12.0 - 50000.0), glyphs[1].x_offset, 0.01);
}
