//! Source-backed direct retained bidi L2 integration coverage.

const std = @import("std");
const support = @import("../../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const Font = support.Font;
const GlyphPosition = support.GlyphPosition;
const CascadeRun = support.CascadeRun;
const FontCascade = support.FontCascade;
const ReflowBuffer = support.ReflowBuffer;

fn expectSameParagraphLayout(
    expected: support.ParagraphLayout,
    actual: support.ParagraphLayout,
) !void {
    try std.testing.expectEqualSlices(GlyphPosition, expected.glyphs, actual.glyphs);
    try std.testing.expectEqualSlices(CascadeRun, expected.runs, actual.runs);
    try std.testing.expectEqualSlices(
        support.ParagraphLine,
        expected.lines,
        actual.lines,
    );
    try std.testing.expectEqual(expected.width, actual.width);
    try std.testing.expectEqual(expected.height, actual.height);
}

fn snapshotParagraphLayout(
    allocator: std.mem.Allocator,
    layout: support.ParagraphLayout,
) !support.ParagraphLayout {
    const glyphs = try allocator.dupe(GlyphPosition, layout.glyphs);
    errdefer allocator.free(glyphs);
    const runs = try allocator.dupe(CascadeRun, layout.runs);
    errdefer allocator.free(runs);
    const lines = try allocator.dupe(support.ParagraphLine, layout.lines);
    return .{
        .glyphs = glyphs,
        .runs = runs,
        .normalized_variation_coords = layout.normalized_variation_coords,
        .lines = lines,
        .inline_objects = layout.inline_objects,
        .writing_mode = layout.writing_mode,
        .width = layout.width,
        .height = layout.height,
    };
}

fn freeParagraphLayoutSnapshot(
    allocator: std.mem.Allocator,
    layout: support.ParagraphLayout,
) void {
    allocator.free(layout.lines);
    allocator.free(layout.runs);
    allocator.free(layout.glyphs);
}

fn expectDirectSourceScratch(
    reflow: *const ReflowBuffer,
    line_count: usize,
) !void {
    const scratch = &reflow.buffer.bidi_reorder_scratch;
    // The fused source path applies L2 directly to copied glyph records. It
    // must never materialize the old scalar-index permutation sidecar.
    try std.testing.expectEqual(@as(usize, 0), scratch.visual_order.items.len);
    try std.testing.expectEqual(@as(usize, 0), scratch.visual_order.capacity);
    try std.testing.expectEqual(@as(usize, 0), scratch.glyph_cluster_index.capacity);
    try std.testing.expectEqual(@as(usize, 0), scratch.seen.capacity);
    try std.testing.expectEqual(line_count, scratch.direct_line_ranges.items.len);
}

fn expectDenseSingleRunLayout(
    layout: support.ParagraphLayout,
    source_glyph_count: usize,
) !usize {
    try std.testing.expectEqual(source_glyph_count, layout.glyphs.len);
    try std.testing.expectEqual(@as(usize, 1), layout.runs.len);
    try std.testing.expectEqual(@as(usize, 0), layout.runs[0].glyph_start);
    try std.testing.expectEqual(source_glyph_count, layout.runs[0].glyph_len);

    var visible_count: usize = 0;
    for (layout.lines) |line| {
        try std.testing.expectEqual(visible_count, line.glyph_start);
        try std.testing.expectEqual(@as(usize, 0), line.run_start);
        try std.testing.expectEqual(
            @as(usize, @intFromBool(line.glyph_len != 0)),
            line.run_len,
        );
        visible_count += line.glyph_len;
    }
    return visible_count;
}

test "direct retained bidi L2 matches general layout across LTR reflows" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Retained Mirror Sans",
        "Regular",
        "Retained Mirror Sans Regular",
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    const text = "(אב) A (אב) A ";

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        text,
        20,
        .{ .max_width = 200, .direction = .ltr },
    );
    defer shaped.deinit();
    try std.testing.expect(shaped.simple_reflow);
    try std.testing.expect(shaped.direct_bidi_scalar_glyphs);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var one_shot_buffer = LayoutBuffer.init(allocator);
    defer one_shot_buffer.deinit();
    var saw_wrapping_gap = false;
    for ([_]f32{ 60, 200, 75, 60 }) |width| {
        const retained = try shaped.layout(&reflow, .{
            .max_width = width,
            .direction = .ltr,
        });
        const retained_snapshot = try snapshotParagraphLayout(allocator, retained);
        defer freeParagraphLayoutSnapshot(allocator, retained_snapshot);
        const expected = try TextShaper.layoutParagraphUtf8(
            cascade,
            &one_shot_buffer,
            text,
            20,
            .{ .max_width = width, .direction = .ltr },
        );
        try expectSameParagraphLayout(expected, retained_snapshot);
        const visible_count = try expectDenseSingleRunLayout(
            retained,
            shaped.glyphs.len,
        );
        saw_wrapping_gap = saw_wrapping_gap or visible_count < retained.glyphs.len;
        try expectDirectSourceScratch(&reflow, retained.lines.len);
    }
    try std.testing.expect(saw_wrapping_gap);
}

test "direct retained bidi ranges partition trimmed spaces exactly once" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    const text = "A אב   B גד   C";

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        text,
        20,
        .{ .max_width = 200, .direction = .ltr },
    );
    defer shaped.deinit();
    try std.testing.expect(shaped.direct_bidi_scalar_glyphs);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const layout = try shaped.layout(&reflow, .{
        .max_width = 55,
        .direction = .ltr,
    });
    const ranges = reflow.buffer.bidi_reorder_scratch.direct_line_ranges.items;
    try std.testing.expect(ranges.len > 1);
    var expected_start: usize = 0;
    for (ranges) |range| {
        try std.testing.expectEqual(expected_start, range.scalar_start);
        try std.testing.expect(range.scalar_start <= range.scalar_end);
        expected_start = range.scalar_end;
    }
    try std.testing.expectEqual(shaped.glyphs.len, expected_start);

    const visible_count = try expectDenseSingleRunLayout(
        layout,
        shaped.glyphs.len,
    );
    try std.testing.expect(shaped.glyphs.len - visible_count >= 4);
    const suffix = layout.glyphs[visible_count..];
    var previous_cluster: ?usize = null;
    for (suffix) |glyph| {
        try std.testing.expectEqual(@as(u21, ' '), glyph.codepoint);
        if (previous_cluster) |previous|
            try std.testing.expect(previous < glyph.cluster);
        previous_cluster = glyph.cluster;
    }
    try expectDirectSourceScratch(&reflow, layout.lines.len);
}

test "direct retained bidi L2 matches general RTL numbers and neutrals" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    const text = "א 12ב";

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        text,
        20,
        .{ .max_width = 240, .direction = .rtl },
    );
    defer shaped.deinit();
    try std.testing.expect(shaped.simple_reflow);
    try std.testing.expect(shaped.direct_bidi_scalar_glyphs);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    var one_shot_buffer = LayoutBuffer.init(allocator);
    defer one_shot_buffer.deinit();
    for ([_]f32{ 120, 48, 75, 48 }) |width| {
        const retained = try shaped.layout(&reflow, .{
            .max_width = width,
            .direction = .rtl,
        });
        const retained_snapshot = try snapshotParagraphLayout(allocator, retained);
        defer freeParagraphLayoutSnapshot(allocator, retained_snapshot);
        const expected = try TextShaper.layoutParagraphUtf8(
            cascade,
            &one_shot_buffer,
            text,
            20,
            .{ .max_width = width, .direction = .rtl },
        );
        try expectSameParagraphLayout(expected, retained_snapshot);
        _ = try expectDenseSingleRunLayout(retained, shaped.glyphs.len);
        try expectDirectSourceScratch(&reflow, retained.lines.len);
    }

    // The wide reflow exercises both L2 thresholds: the outer RTL sequence
    // reverses around a neutral space while the numeric subrun stays LTR.
    const wide = try shaped.layout(&reflow, .{
        .max_width = 120,
        .direction = .rtl,
    });
    try std.testing.expectEqualSlices(usize, &.{ 5, 3, 4, 2, 0 }, &.{
        wide.glyphs[0].cluster,
        wide.glyphs[1].cluster,
        wide.glyphs[2].cluster,
        wide.glyphs[3].cluster,
        wide.glyphs[4].cluster,
    });
    try std.testing.expectEqualSlices(u21, &.{ 0x05d1, '1', '2', ' ', 0x05d0 }, &.{
        wide.glyphs[0].codepoint,
        wide.glyphs[1].codepoint,
        wide.glyphs[2].codepoint,
        wide.glyphs[3].codepoint,
        wide.glyphs[4].codepoint,
    });
    try expectDirectSourceScratch(&reflow, wide.lines.len);
}

test "direct retained bidi mirrors odd-level brackets in mixed LTR text" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const bytes = try test_font.buildNamedBidiMirrorTtfWithNames(
        allocator,
        "Retained Mixed Mirror Sans",
        "Regular",
        "Retained Mixed Mirror Sans Regular",
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = FontCascade.init(&.{&font});
    const text = "A אב(אב) A";

    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        text,
        20,
        .{ .max_width = 200, .direction = .ltr },
    );
    defer shaped.deinit();
    try std.testing.expect(shaped.direct_bidi_scalar_glyphs);

    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const visual = try shaped.layout(&reflow, .{
        .max_width = 200,
        .direction = .ltr,
    });
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 11, 9, 7, 6, 4, 2, 12, 13 }, &.{
        visual.glyphs[0].cluster,
        visual.glyphs[1].cluster,
        visual.glyphs[2].cluster,
        visual.glyphs[3].cluster,
        visual.glyphs[4].cluster,
        visual.glyphs[5].cluster,
        visual.glyphs[6].cluster,
        visual.glyphs[7].cluster,
        visual.glyphs[8].cluster,
        visual.glyphs[9].cluster,
    });
    // The source ')' at byte 11 and '(' at byte 6 both have odd effective
    // levels. Mirroring updates their public codepoints and glyph ids to the
    // opposite cmap entries while the clusters retain source ownership.
    try std.testing.expectEqual(@as(u21, '('), visual.glyphs[2].codepoint);
    try std.testing.expectEqual(try font.glyphIndex('('), visual.glyphs[2].glyph_id);
    try std.testing.expectEqual(@as(u21, ')'), visual.glyphs[5].codepoint);
    try std.testing.expectEqual(try font.glyphIndex(')'), visual.glyphs[5].glyph_id);
    try expectDirectSourceScratch(&reflow, visual.lines.len);
}

test "source-backed direct bidi clears every failed transaction" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../../test_font.zig");
    const bytes = try test_font.buildLastResortCmapTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        "AB אב 12 אב AB אב 34 אב",
        20,
        .{ .max_width = 200, .direction = .ltr },
    );
    defer shaped.deinit();

    // Walk every allocation in a fresh source-backed reflow. The first success
    // proves that every preceding failure point returned OOM without publishing
    // partial glyph, run, line, or direct-range output.
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(allocator, .{
            .fail_index = fail_index,
        });
        var reflow = ReflowBuffer.init(failing.allocator());
        defer reflow.deinit();
        const result = shaped.layout(&reflow, .{
            .max_width = 48,
            .direction = .ltr,
        });
        if (result) |_| {
            try std.testing.expect(!failing.has_induced_failure);
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(@as(usize, 0), reflow.buffer.glyphs.items.len);
            try std.testing.expectEqual(@as(usize, 0), reflow.buffer.runs.items.len);
            try std.testing.expectEqual(@as(usize, 0), reflow.buffer.lines.items.len);
            try std.testing.expectEqual(
                @as(usize, 0),
                reflow.buffer.bidi_reorder_scratch.direct_line_ranges.items.len,
            );

            failing.fail_index = std.math.maxInt(usize);
            failing.resize_fail_index = std.math.maxInt(usize);
            const recovered = try shaped.layout(&reflow, .{
                .max_width = 48,
                .direction = .ltr,
            });
            try std.testing.expectEqual(shaped.glyphs.len, recovered.glyphs.len);
            try std.testing.expect(recovered.lines.len > 1);
            try expectDirectSourceScratch(&reflow, recovered.lines.len);
        }
    }
}
