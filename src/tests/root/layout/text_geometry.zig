//! Platform-neutral paragraph text-run geometry integration coverage.

const std = @import("std");

const inline_object = @import("../../../layout/inline_object/root.zig");
const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const StyledParagraphBuffer = support.StyledParagraphBuffer;
const TextShaper = support.TextShaper;

test "text geometry divides a shaped ligature over source graphemes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalGsubTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const text = "AA AA";
    const layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqual(@as(usize, 3), layout.glyphs.len);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(text.len, geometry.source_byte_len);
    try std.testing.expectEqual(@as(usize, 1), geometry.spans.len);
    try std.testing.expectEqual(@as(usize, 5), geometry.graphemes.len);
    const span = geometry.spans[0];
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.ltr,
        span.direction,
    );
    try std.testing.expectEqual(@as(usize, 0), span.byte_start);
    try std.testing.expectEqual(text.len, span.byte_len);
    try std.testing.expect(span.font_run != null);
    try std.testing.expectEqual(@as(usize, 0), span.font_run.?.run_index);
    try std.testing.expectEqual(@as(usize, 0), span.font_run.?.cascade_index);
    try std.testing.expectApproxEqAbs(
        geometry.graphemes[0].width,
        geometry.graphemes[1].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        layout.glyphs[0].x_advance,
        geometry.graphemes[0].width + geometry.graphemes[1].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        layout.glyphs[2].x_advance,
        geometry.graphemes[3].width + geometry.graphemes[4].width,
        0.001,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 3 },
        span.wordStarts(geometry.word_starts),
    );
    const internal_selection = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 1, .byte_end = 2 },
    );
    defer allocator.free(internal_selection);
    try std.testing.expectEqual(@as(usize, 1), internal_selection.len);
    try std.testing.expectApproxEqAbs(
        geometry.graphemes[1].inline_position,
        internal_selection[0].rect.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        geometry.graphemes[1].width,
        internal_selection[0].rect.width,
        0.001,
    );

    // Geometry owns its flat arrays rather than borrowing the reusable layout
    // buffer. A subsequent shaping call must not invalidate the first result.
    _ = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        "A",
        20,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqual(@as(usize, 5), geometry.graphemes.len);
    try std.testing.expectEqual(@as(usize, 3), geometry.graphemes[3].byte_start);
}

test "text geometry prefers authored GDEF ligature carets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildGdefLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        "AA",
        20,
        .{ .max_width = 100 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        "AA",
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 2), geometry.graphemes.len);
    // The ligature advance is 20. GDEF authors its boundary at 300/1000 em,
    // yielding 6 + 14 rather than the fallback 10 + 10 split.
    try std.testing.expectApproxEqAbs(
        @as(f32, 6),
        geometry.graphemes[0].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 14),
        geometry.graphemes[1].width,
        0.001,
    );
    try std.testing.expect(geometry.graphemes[0].authored_ligature_caret);
    try std.testing.expect(geometry.graphemes[1].authored_ligature_caret);

    const internal = geometry.caret(.{
        .byte_offset = 1,
        .affinity = .downstream,
    }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 6), internal.rect.x, 0.001);
    const hit_before = geometry.hitTest(5, 8).?;
    try std.testing.expectEqual(@as(usize, 1), hit_before.position.byte_offset);
    try std.testing.expectEqual(
        paragraph.TextGeometryAffinity.upstream,
        hit_before.position.affinity,
    );
    const hit_after = geometry.hitTest(8, 8).?;
    try std.testing.expectEqual(@as(usize, 1), hit_after.position.byte_offset);
    try std.testing.expectEqual(
        paragraph.TextGeometryAffinity.downstream,
        hit_after.position.affinity,
    );

    const stops = geometry.lines[0].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectEqual(@as(usize, 3), stops.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0), stops[0].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), stops[1].x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), stops[2].x, 0.001);
    const next_internal = geometry.nextVisualCaret(.{
        .byte_offset = 0,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 1), next_internal.position.byte_offset);
    try std.testing.expectEqual(
        paragraph.TextGeometryAffinity.upstream,
        next_internal.position.affinity,
    );
    const previous_internal = geometry.previousVisualCaret(.{
        .byte_offset = 2,
        .affinity = .upstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 1), previous_internal.position.byte_offset);
    try std.testing.expectEqual(
        paragraph.TextGeometryAffinity.downstream,
        previous_internal.position.affinity,
    );
}

test "text geometry applies GDEF caret variation at the final run instance" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildGdefVariableLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        "AA",
        20,
        .{
            .max_width = 100,
            .normalized_variation_coords = &.{0.5},
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        "AA",
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectApproxEqAbs(
        @as(f32, 6.14),
        geometry.graphemes[0].width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        layout.glyphs[0].x_advance - 6.14,
        geometry.graphemes[1].width,
        0.001,
    );
    try std.testing.expect(geometry.graphemes[0].authored_ligature_caret);
}

test "text geometry falls back when GDEF caret cardinality mismatches source" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildGdefLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const face = @import("../../../font/face/root.zig").backend.face(&font);
    const glyphs = [_]@import("../../../layout/glyph_position.zig").GlyphPosition{.{
        .glyph_id = 2,
        .codepoint = 'A',
        .cluster = 0,
        .source_byte_len = 3,
        .x_advance = 30,
    }};
    const runs = [_]support.CascadeRun{.{
        .font = face,
        .font_index = 0,
        .font_size = 20,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    }};
    const lines = [_]support.ParagraphLine{.{
        .glyph_start = 0,
        .glyph_len = 1,
        .run_start = 0,
        .run_len = 1,
        .byte_start = 0,
        .byte_len = 3,
        .x = 0,
        .y = 0,
        .width = 30,
        .height = 20,
        .baseline = 16,
        .ascent = 16,
        .descent = 4,
        .leading = 0,
    }};
    const layout = support.ParagraphLayout{
        .glyphs = &glyphs,
        .runs = &runs,
        .lines = &lines,
        .width = 30,
        .height = 20,
    };

    var geometry = try paragraph.buildGeometry(
        allocator,
        "AAA",
        layout,
        .{},
    );
    defer geometry.deinit();
    for (geometry.graphemes) |grapheme| {
        try std.testing.expectApproxEqAbs(
            @as(f32, 10),
            grapheme.width,
            0.001,
        );
        try std.testing.expect(!grapheme.authored_ligature_caret);
    }
}

test "text geometry falls back when authored GDEF caret exceeds final advance" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildGdefLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const face = @import("../../../font/face/root.zig").backend.face(&font);
    const glyphs = [_]@import("../../../layout/glyph_position.zig").GlyphPosition{.{
        .glyph_id = 2,
        .codepoint = 'A',
        .cluster = 0,
        .source_byte_len = 2,
        .x_advance = 4,
    }};
    const runs = [_]support.CascadeRun{.{
        .font = face,
        .font_index = 0,
        .font_size = 20,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    }};
    const lines = [_]support.ParagraphLine{.{
        .glyph_start = 0,
        .glyph_len = 1,
        .run_start = 0,
        .run_len = 1,
        .byte_start = 0,
        .byte_len = 2,
        .x = 0,
        .y = 0,
        .width = 4,
        .height = 20,
        .baseline = 16,
        .ascent = 16,
        .descent = 4,
        .leading = 0,
    }};
    const layout = support.ParagraphLayout{
        .glyphs = &glyphs,
        .runs = &runs,
        .lines = &lines,
        .width = 4,
        .height = 20,
    };

    var geometry = try paragraph.buildGeometry(
        allocator,
        "AA",
        layout,
        .{},
    );
    defer geometry.deinit();
    for (geometry.graphemes) |grapheme| {
        try std.testing.expectApproxEqAbs(
            @as(f32, 2),
            grapheme.width,
            0.001,
        );
        try std.testing.expect(!grapheme.authored_ligature_caret);
    }
}

test "RTL ligature geometry reverses authored GDEF component assignment" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildGdefLigatureCaretTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const face = @import("../../../font/face/root.zig").backend.face(&font);
    const glyphs = [_]@import("../../../layout/glyph_position.zig").GlyphPosition{.{
        .glyph_id = 2,
        .codepoint = 0x05d0,
        .cluster = 0,
        .source_byte_len = 4,
        .x_advance = 20,
    }};
    const runs = [_]support.CascadeRun{.{
        .font = face,
        .font_index = 0,
        .font_size = 20,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    }};
    const lines = [_]support.ParagraphLine{.{
        .glyph_start = 0,
        .glyph_len = 1,
        .run_start = 0,
        .run_len = 1,
        .byte_start = 0,
        .byte_len = 4,
        .x = 0,
        .y = 0,
        .width = 20,
        .height = 20,
        .baseline = 16,
        .ascent = 16,
        .descent = 4,
        .leading = 0,
    }};
    const layout = support.ParagraphLayout{
        .glyphs = &glyphs,
        .runs = &runs,
        .lines = &lines,
        .width = 20,
        .height = 20,
    };
    const text = "אב";

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{ .direction = .rtl },
    );
    defer geometry.deinit();
    const graphemes = geometry.spans[0].graphemes(geometry.graphemes);
    try std.testing.expectApproxEqAbs(@as(f32, 14), graphemes[0].width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), graphemes[1].width, 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f32, 6),
        graphemes[0].inline_position,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        graphemes[1].inline_position,
        0.001,
    );
}

test "text geometry keeps bidi spans logical and positions RTL graphemes visually" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    const text = "AאבB";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    try std.testing.expectEqualSlices(usize, &.{ 0, 3, 1, 5 }, &.{
        layout.glyphs[0].cluster,
        layout.glyphs[1].cluster,
        layout.glyphs[2].cluster,
        layout.glyphs[3].cluster,
    });

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.ltr,
        geometry.spans[0].direction,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[1].direction,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.ltr,
        geometry.spans[2].direction,
    );
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[0].previous_on_line);
    try std.testing.expectEqual(@as(?usize, 1), geometry.spans[0].next_on_line);
    try std.testing.expectEqual(@as(?usize, 0), geometry.spans[1].previous_on_line);
    try std.testing.expectEqual(@as(?usize, 2), geometry.spans[1].next_on_line);
    try std.testing.expectEqual(@as(?usize, 1), geometry.spans[2].previous_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[2].next_on_line);

    const rtl = geometry.spans[1].graphemes(geometry.graphemes);
    try std.testing.expectEqual(@as(usize, 1), rtl[0].byte_start);
    try std.testing.expectEqual(@as(usize, 3), rtl[1].byte_start);
    try std.testing.expectApproxEqAbs(@as(f32, 10), rtl[0].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), rtl[1].inline_position, 0.001);
    try std.testing.expectApproxEqAbs(
        layout.glyphs[0].x_advance,
        geometry.spans[1].bounds.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 20), geometry.spans[1].bounds.width, 0.001);

    const rtl_start = geometry.caret(.{
        .byte_offset = 1,
        .affinity = .downstream,
    }).?;
    const rtl_end = geometry.caret(.{
        .byte_offset = 5,
        .affinity = .upstream,
    }).?;
    try std.testing.expect(rtl_start.rect.x > rtl_end.rect.x);

    const rtl_right_hit = geometry.hitTest(rtl_start.rect.x - 1, 8).?;
    try std.testing.expectEqual(
        @as(usize, 1),
        rtl_right_hit.position.byte_offset,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometryAffinity.downstream,
        rtl_right_hit.position.affinity,
    );

    const discontiguous = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = 3 },
    );
    defer allocator.free(discontiguous);
    // Logical A+Alef are separated visually by the selected run's unselected
    // Bet, so preserving two fragments is required for correct bidi painting.
    try std.testing.expectEqual(@as(usize, 2), discontiguous.len);
    try std.testing.expect(discontiguous[0].rect.x <
        discontiguous[1].rect.x);

    const visual_stops = geometry.lines[0].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectEqual(@as(usize, 5), visual_stops.len);
    for (visual_stops[1..], visual_stops[0 .. visual_stops.len - 1]) |
        current,
        previous,
    | {
        try std.testing.expect(current.x >= previous.x);
    }

    var forward = geometry.caret(.{
        .byte_offset = 0,
        .affinity = .downstream,
    }).?;
    const expected_forward = [_]paragraph.TextGeometryCaretPosition{
        .{ .byte_offset = 1, .affinity = .upstream },
        .{ .byte_offset = 3, .affinity = .downstream },
        .{ .byte_offset = 1, .affinity = .downstream },
        .{ .byte_offset = text.len, .affinity = .upstream },
    };
    for (expected_forward) |expected| {
        forward = geometry.nextVisualCaret(forward.position).?;
        try std.testing.expectEqual(expected, forward.position);
    }
    try std.testing.expect(
        geometry.nextVisualCaret(forward.position) == null,
    );

    var backward = forward;
    const expected_backward = [_]paragraph.TextGeometryCaretPosition{
        .{ .byte_offset = 5, .affinity = .downstream },
        .{ .byte_offset = 3, .affinity = .upstream },
        .{ .byte_offset = 5, .affinity = .upstream },
        .{ .byte_offset = 0, .affinity = .downstream },
    };
    for (expected_backward) |expected| {
        backward = geometry.previousVisualCaret(backward.position).?;
        try std.testing.expectEqual(expected, backward.position);
    }
    try std.testing.expect(
        geometry.previousVisualCaret(backward.position) == null,
    );

    const middle = geometry.caret(.{
        .byte_offset = 3,
        .affinity = .downstream,
    }).?;
    // A synthetic second-line query is covered in the interaction suite; here
    // assert that an absent adjacent line and non-finite preferred x are
    // rejected without changing bidi affinity.
    try std.testing.expect(
        geometry.nextLineCaret(middle.position, middle.rect.x) == null,
    );
    try std.testing.expect(
        geometry.previousLineCaret(
            middle.position,
            std.math.inf(f32),
        ) == null,
    );
}

test "text geometry honors an explicit RTL paragraph base direction" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "אב";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{
            .max_width = 100,
            .direction = .rtl,
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{ .direction = .rtl },
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 1), geometry.spans.len);
    try std.testing.expectEqual(
        paragraph.TextGeometryDirection.rtl,
        geometry.spans[0].direction,
    );
    const graphemes = geometry.spans[0].graphemes(geometry.graphemes);
    try std.testing.expectEqual(@as(usize, 0), graphemes[0].byte_start);
    try std.testing.expectEqual(@as(usize, 2), graphemes[1].byte_start);
    try std.testing.expect(graphemes[0].inline_position >
        graphemes[1].inline_position);
}

test "styled text geometry splits style identities and links only within a line" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);

    const text = "AA\nAA";
    const styles = [_]paragraph.StyledSpan{
        .{ .byte_start = 0, .byte_len = 1, .style_index = 4, .font_size = 16 },
        .{ .byte_start = 1, .byte_len = 2, .style_index = 7, .font_size = 16 },
        .{ .byte_start = 3, .byte_len = 2, .style_index = 9, .font_size = 16 },
    };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    var styled_buffer = StyledParagraphBuffer.init(allocator);
    defer styled_buffer.deinit();
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &layout_buffer,
        &styled_buffer,
        text,
        16,
        &styles,
        .{ .max_width = 100 },
    );

    var geometry = try paragraph.buildStyledGeometry(
        allocator,
        text,
        layout,
        &styles,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(@as(?u32, 4), geometry.spans[0].style_index);
    try std.testing.expectEqual(@as(?u32, 7), geometry.spans[1].style_index);
    try std.testing.expectEqual(@as(?u32, 9), geometry.spans[2].style_index);
    try std.testing.expectEqual(@as(usize, 0), geometry.spans[0].line_index);
    try std.testing.expectEqual(@as(usize, 0), geometry.spans[1].line_index);
    try std.testing.expectEqual(@as(usize, 1), geometry.spans[2].line_index);
    try std.testing.expectEqual(@as(?usize, 1), geometry.spans[0].next_on_line);
    try std.testing.expectEqual(@as(?usize, 0), geometry.spans[1].previous_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[1].next_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[2].previous_on_line);
    try std.testing.expectEqual(@as(?usize, null), geometry.spans[2].next_on_line);
    try std.testing.expectEqualSlices(
        usize,
        &.{0},
        geometry.spans[0].wordStarts(geometry.word_starts),
    );
    try std.testing.expectEqual(@as(usize, 0), geometry.spans[1].word_start_len);
    try std.testing.expectEqualSlices(
        usize,
        &.{0},
        geometry.spans[2].wordStarts(geometry.word_starts),
    );
}

test "text geometry preserves fallback ownership and fontless inline objects" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const primary_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtf(
        allocator,
        'B',
    );
    defer allocator.free(fallback_bytes);
    var primary = try Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    const fonts = [_]*const Font{ &primary, &fallback };
    const cascade = FontCascade.init(&fonts);

    const text = "A" ++ inline_object.object_replacement_utf8 ++ "B";
    const object = inline_object.Object{
        .id = 8,
        .byte_index = 1,
        .width = 12,
        .height = 18,
    };
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{
            .max_width = 200,
            .inline_objects = &.{object},
        },
    );

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(@as(usize, 3), geometry.spans.len);
    try std.testing.expectEqual(@as(?usize, 0), if (geometry.spans[0].font_run) |run|
        run.cascade_index
    else
        null);
    try std.testing.expect(geometry.spans[1].font_run == null);
    try std.testing.expectEqual(@as(usize, 1), geometry.spans[1].byte_start);
    try std.testing.expectApproxEqAbs(
        object.width,
        geometry.spans[1].bounds.width,
        0.001,
    );
    try std.testing.expectEqual(@as(?usize, 1), if (geometry.spans[2].font_run) |run|
        run.cascade_index
    else
        null);
}
