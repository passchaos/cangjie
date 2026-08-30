//! Affinity-aware caret, hit-test, and selection fragment coverage.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;

test "text geometry affinity distinguishes both sides of a soft wrap" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};

    const text = "A A";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 20 },
    );
    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);

    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expectEqual(layout.lines.len, geometry.lines.len);

    const boundary = layout.lines[1].byte_start;
    const upstream = geometry.caret(.{
        .byte_offset = boundary,
        .affinity = .upstream,
    }).?;
    const downstream = geometry.caret(.{
        .byte_offset = boundary,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 0), upstream.line_index);
    try std.testing.expectEqual(@as(usize, 1), downstream.line_index);
    try std.testing.expect(upstream.rect.y < downstream.rect.y);

    const upstream_cursor = geometry.cursorAt(upstream.position).?;
    const next_cursor = geometry.cursorNextVisual(upstream_cursor).?;
    try std.testing.expectEqual(downstream.position, next_cursor.position);
    const line_cursor = geometry.cursorNextLine(upstream_cursor).?;
    try std.testing.expectEqual(@as(usize, 1), geometry.cursorGeometry(line_cursor).?.line_index);
    try std.testing.expect(line_cursor.preferred_inline != null);
    const restored_cursor = geometry.cursorPreviousLine(line_cursor).?;
    try std.testing.expectEqual(upstream.position, restored_cursor.position);

    const second_line_hit = geometry.hitTest(
        downstream.rect.x,
        downstream.rect.y + 1,
    ).?;
    try std.testing.expectEqual(@as(usize, 1), second_line_hit.line_index);

    const next_line = geometry.nextVisualCaret(upstream.position).?;
    try std.testing.expectEqual(downstream.position, next_line.position);
    try std.testing.expectEqual(@as(usize, 1), next_line.line_index);
    const previous_line =
        geometry.previousVisualCaret(downstream.position).?;
    try std.testing.expectEqual(upstream.position, previous_line.position);
    try std.testing.expectEqual(@as(usize, 0), previous_line.line_index);

    const preferred_x = upstream.rect.x;
    const vertical_next = geometry.nextLineCaret(
        upstream.position,
        preferred_x,
    ).?;
    try std.testing.expectEqual(@as(usize, 1), vertical_next.line_index);
    try std.testing.expectApproxEqAbs(
        preferred_x,
        vertical_next.rect.x,
        0.001,
    );
    const vertical_previous = geometry.previousLineCaret(
        vertical_next.position,
        preferred_x,
    ).?;
    try std.testing.expectEqual(@as(usize, 0), vertical_previous.line_index);
    try std.testing.expectApproxEqAbs(
        preferred_x,
        vertical_previous.rect.x,
        0.001,
    );
    try std.testing.expect(
        geometry.previousLineCaret(upstream.position, preferred_x) == null,
    );

    const across_lines = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = text.len },
    );
    defer allocator.free(across_lines);
    try std.testing.expectEqual(@as(usize, 2), across_lines.len);
    try std.testing.expectEqual(@as(usize, 0), across_lines[0].line_index);
    try std.testing.expectEqual(@as(usize, 1), across_lines[1].line_index);
}

test "text geometry retains trailing hard-break and empty paragraph carets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const cascade = FontCascade.init(&fonts);
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();

    const text = "A\n";
    const trailing_layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        text,
        20,
        .{ .max_width = 100 },
    );
    var trailing = try paragraph.buildGeometry(
        allocator,
        text,
        trailing_layout,
        .{},
    );
    defer trailing.deinit();
    try std.testing.expectEqual(@as(usize, 2), trailing.lines.len);
    try std.testing.expectEqual(@as(usize, 0), trailing.lines[1].span_len);
    try std.testing.expectEqual(
        @as(usize, 1),
        trailing.lines[1].visual_caret_len,
    );
    const first_line_stops = trailing.lines[0].visualCaretStops(
        trailing.visual_caret_stops,
    );
    try std.testing.expect(first_line_stops.len >= 3);
    // The visible 'A' end and zero-width hard-break atom share x but are
    // separate topology steps with different logical ownership.
    try std.testing.expectApproxEqAbs(
        first_line_stops[first_line_stops.len - 2].inline_position,
        first_line_stops[first_line_stops.len - 1].inline_position,
        0.001,
    );
    try std.testing.expect(
        first_line_stops[first_line_stops.len - 2].from_start.byte_offset !=
            first_line_stops[first_line_stops.len - 1].from_start.byte_offset,
    );
    const final_caret = trailing.caret(.{
        .byte_offset = text.len,
        .affinity = .downstream,
    }).?;
    try std.testing.expectEqual(@as(usize, 1), final_caret.line_index);
    try std.testing.expectApproxEqAbs(
        trailing.lines[1].bounds.y,
        final_caret.rect.y,
        0.001,
    );
    const final_hit = trailing.hitTest(
        final_caret.rect.x + 50,
        final_caret.rect.y + 1,
    ).?;
    try std.testing.expectEqual(text.len, final_hit.position.byte_offset);
    try std.testing.expect(
        trailing.nextVisualCaret(final_caret.position) == null,
    );
    const from_first_to_empty = trailing.nextLineCaret(
        .{ .byte_offset = 0, .affinity = .downstream },
        500,
    ).?;
    try std.testing.expectEqual(@as(usize, 1), from_first_to_empty.line_index);
    try std.testing.expectEqual(text.len, from_first_to_empty.position.byte_offset);
    try std.testing.expect(
        trailing.nextLineCaret(from_first_to_empty.position, 500) == null,
    );
    const back_to_hard_break = trailing.previousLineCaret(
        from_first_to_empty.position,
        500,
    ).?;
    try std.testing.expectEqual(@as(usize, 0), back_to_hard_break.line_index);
    try std.testing.expectEqual(
        first_line_stops[first_line_stops.len - 1].from_end,
        back_to_hard_break.position,
    );

    const empty_layout = try TextShaper.layoutParagraphUtf8(
        cascade,
        &layout_buffer,
        "",
        20,
        .{ .max_width = 100 },
    );
    var empty = try paragraph.buildGeometry(
        allocator,
        "",
        empty_layout,
        .{},
    );
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 1), empty.lines.len);
    try std.testing.expectEqual(@as(usize, 0), empty.spans.len);
    const empty_caret = empty.caret(.{ .byte_offset = 0 }).?;
    try std.testing.expectEqual(@as(usize, 0), empty_caret.position.byte_offset);
    try std.testing.expect(empty_caret.rect.height > 0);
}

test "text geometry rejects non-boundary caret offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A\u{0301}";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 100 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();
    try std.testing.expect(geometry.caret(.{ .byte_offset = 1 }) == null);
    try std.testing.expect(geometry.caret(.{
        .byte_offset = text.len + 1,
    }) == null);
    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = 1, .byte_end = text.len },
        ),
    );
    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = text.len, .byte_end = 0 },
        ),
    );
    const empty_selection = try geometry.selectionFragments(
        allocator,
        .{ .byte_start = 0, .byte_end = 0 },
    );
    defer allocator.free(empty_selection);
    try std.testing.expectEqual(@as(usize, 0), empty_selection.len);
}

test "text geometry rejects selection ranges hidden by truncation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A A A";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{
            .max_width = 20,
            .max_lines = 1,
        },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectError(
        error.InvalidTextRange,
        geometry.selectionFragments(
            allocator,
            .{ .byte_start = 0, .byte_end = text.len },
        ),
    );
    try std.testing.expect((try geometry.wordAt(allocator, 4)) == null);
}

test "vertical caret navigation clamps preferred x on unequal lines" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "AAA\nA";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    const first_line_end = geometry.caret(.{
        .byte_offset = layout.lines[0].byteEnd(),
        .affinity = .upstream,
    }).?;
    const clamped = geometry.nextLineCaret(
        first_line_end.position,
        first_line_end.rect.x,
    ).?;
    const second_stops = geometry.lines[1].visualCaretStops(
        geometry.visual_caret_stops,
    );
    try std.testing.expectApproxEqAbs(
        second_stops[second_stops.len - 1].inline_position,
        clamped.rect.x,
        0.001,
    );
    try std.testing.expect(
        geometry.nextLineCaret(
            first_line_end.position,
            std.math.nan(f32),
        ) == null,
    );
}

test "text geometry resolves UAX words and wrapped visual fragments" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "AAA AAA";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 30 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    var first = (try geometry.wordAt(allocator, 1)).?;
    defer first.deinit(allocator);
    try std.testing.expectEqual(
        paragraph.TextGeometrySelectionRange{
            .byte_start = 0,
            .byte_end = 3,
        },
        first.range,
    );
    try std.testing.expectEqual(@as(usize, 1), first.fragments.len);

    try std.testing.expect((try geometry.wordAt(allocator, 3)) == null);

    var second = (try geometry.wordAt(allocator, 4)).?;
    defer second.deinit(allocator);
    try std.testing.expectEqual(
        paragraph.TextGeometrySelectionRange{
            .byte_start = 4,
            .byte_end = text.len,
        },
        second.range,
    );
    try std.testing.expectEqual(@as(usize, 1), second.fragments.len);
    try std.testing.expect(second.fragments[0].line_index >
        first.fragments[0].line_index);
    try std.testing.expect((try geometry.wordAt(allocator, text.len + 1)) == null);

    const first_start = geometry.caret(.{ .byte_offset = 0 }).?;
    const next_word = geometry.nextVisualWord(first_start.position).?;
    try std.testing.expectEqual(@as(usize, 4), next_word.position.byte_offset);
    try std.testing.expectEqual(
        paragraph.TextGeometryAffinity.downstream,
        next_word.position.affinity,
    );
    const previous_word = geometry.previousVisualWord(next_word.position).?;
    try std.testing.expectEqual(@as(usize, 0), previous_word.position.byte_offset);
    try std.testing.expect(geometry.previousVisualWord(first_start.position) == null);
    try std.testing.expect(geometry.nextVisualWord(next_word.position) == null);

    const logical_next = geometry.nextLogicalWord(first_start.position).?;
    try std.testing.expectEqual(@as(usize, 4), logical_next.position.byte_offset);
    const inside_second = geometry.caret(.{
        .byte_offset = 5,
        .affinity = .downstream,
    }).?;
    const logical_current_start =
        geometry.previousLogicalWord(inside_second.position).?;
    try std.testing.expectEqual(
        @as(usize, 4),
        logical_current_start.position.byte_offset,
    );
    const logical_previous =
        geometry.previousLogicalWord(logical_current_start.position).?;
    try std.testing.expectEqual(@as(usize, 0), logical_previous.position.byte_offset);
    const logical_end = geometry.nextLogicalWord(logical_next.position).?;
    try std.testing.expectEqual(text.len, logical_end.position.byte_offset);
}

test "text geometry exposes allocation-free word and grapheme ranges" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    // U+0301 and the emoji ZWJ sequence exercise UAX #29 clusters containing
    // both combining scalars and several multi-byte code points.
    const family = "👩‍💻";
    const text = "A\u{0301} " ++ family ++ "!B";
    const accented_end = "A\u{0301}".len;
    const family_start = accented_end + 1;
    const family_end = family_start + family.len;
    const final_start = family_end + 1;
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 500 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    const accented = paragraph.TextGeometrySelectionRange{
        .byte_start = 0,
        .byte_end = accented_end,
    };
    const space = paragraph.TextGeometrySelectionRange{
        .byte_start = accented_end,
        .byte_end = family_start,
    };
    const emoji = paragraph.TextGeometrySelectionRange{
        .byte_start = family_start,
        .byte_end = family_end,
    };
    const punctuation = paragraph.TextGeometrySelectionRange{
        .byte_start = family_end,
        .byte_end = final_start,
    };
    const final = paragraph.TextGeometrySelectionRange{
        .byte_start = final_start,
        .byte_end = text.len,
    };

    // Paragraph start normalizes upstream to the sole following grapheme.
    try std.testing.expectEqual(
        accented,
        geometry.graphemeRangeAt(0, .upstream).?,
    );
    try std.testing.expectEqual(
        accented,
        geometry.graphemeRangeAt(1, .downstream).?,
    );
    try std.testing.expectEqual(
        accented,
        geometry.graphemeRangeAt(accented_end - 1, .upstream).?,
    );

    // Affinity selects the logical neighbor only at an exact boundary.
    try std.testing.expectEqual(
        accented,
        geometry.graphemeRangeAt(accented_end, .upstream).?,
    );
    try std.testing.expectEqual(
        space,
        geometry.graphemeRangeAt(accented_end, .downstream).?,
    );
    try std.testing.expectEqual(
        space,
        geometry.graphemeRangeAt(family_start, .upstream).?,
    );
    try std.testing.expectEqual(
        emoji,
        geometry.graphemeRangeAt(family_start, .downstream).?,
    );
    try std.testing.expectEqual(
        emoji,
        geometry.graphemeRangeAt(family_start + 4, .upstream).?,
    );
    try std.testing.expectEqual(
        emoji,
        geometry.graphemeRangeAt(family_end, .upstream).?,
    );
    try std.testing.expectEqual(
        punctuation,
        geometry.graphemeRangeAt(family_end, .downstream).?,
    );
    try std.testing.expectEqual(
        final,
        geometry.graphemeRangeAt(text.len, .upstream).?,
    );
    // Paragraph end normalizes downstream to the sole preceding grapheme.
    try std.testing.expectEqual(
        final,
        geometry.graphemeRangeAt(text.len, .downstream).?,
    );
    try std.testing.expect(
        geometry.graphemeRangeAt(text.len + 1, .upstream) == null,
    );

    try std.testing.expectEqual(
        accented,
        geometry.wordRangeAt(1).?,
    );
    try std.testing.expect(geometry.wordRangeAt(accented_end) == null);
    try std.testing.expect(geometry.wordRangeAt(family_start) == null);
    try std.testing.expect(geometry.wordRangeAt(family_end) == null);
    try std.testing.expectEqual(final, geometry.wordRangeAt(final_start).?);
    try std.testing.expectEqual(final, geometry.wordRangeAt(text.len).?);
    try std.testing.expect(geometry.wordRangeAt(text.len + 1) == null);
}

test "text geometry range queries retain source omitted by truncation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A A A";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 20, .max_lines = 1 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expectEqual(
        paragraph.TextGeometrySelectionRange{
            .byte_start = 4,
            .byte_end = text.len,
        },
        geometry.wordRangeAt(4).?,
    );
    try std.testing.expectEqual(
        paragraph.TextGeometrySelectionRange{
            .byte_start = 4,
            .byte_end = text.len,
        },
        geometry.graphemeRangeAt(4, .downstream).?,
    );
    // The geometry-bearing API still rejects a source-only, truncated word.
    try std.testing.expect((try geometry.wordAt(allocator, 4)) == null);
}

test "empty text geometry has no grapheme or word range" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        "",
        20,
        .{ .max_width = 100 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        "",
        layout,
        .{},
    );
    defer geometry.deinit();

    try std.testing.expect(geometry.wordRangeAt(0) == null);
    try std.testing.expect(geometry.graphemeRangeAt(0, .upstream) == null);
    try std.testing.expect(geometry.graphemeRangeAt(0, .downstream) == null);
}

test "visual word navigation follows mixed-direction line order" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = "A \u{05d0}\u{05d1}";
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 200 },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{ .direction = .ltr },
    );
    defer geometry.deinit();

    const latin = geometry.caret(.{ .byte_offset = 0 }).?;
    const hebrew = geometry.nextVisualWord(latin.position).?;
    try std.testing.expectEqual(@as(usize, 2), hebrew.position.byte_offset);
    try std.testing.expect(hebrew.rect.x > latin.rect.x);
    const back = geometry.previousVisualWord(hebrew.position).?;
    try std.testing.expectEqual(latin.position, back.position);
}

test "accessibility runs own text and expose line semantics" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const Font{&font};
    const text = try allocator.dupe(u8, "A A\nA");
    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&fonts),
        &layout_buffer,
        text,
        20,
        .{ .max_width = 25, .alignment = .center },
    );
    var geometry = try paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{},
    );
    allocator.free(text);
    defer geometry.deinit();

    try std.testing.expect(geometry.lines.len >= 3);
    try std.testing.expectEqual(
        paragraph.TextGeometryLineBreakKind.soft,
        geometry.lines[0].break_kind,
    );
    var found_hard = false;
    for (geometry.lines) |line| {
        found_hard = found_hard or line.break_kind == .hard;
    }
    try std.testing.expect(found_hard);
    try std.testing.expectEqual(
        paragraph.Align.center,
        geometry.lines[0].alignment.?,
    );

    var runs = geometry.accessibilityRuns();
    const first = runs.next().?;
    try std.testing.expectEqualStrings("A "[0..first.text.len], first.text);
    try std.testing.expect(first.graphemes.len != 0);
    try std.testing.expectEqual(@as(usize, 0), first.word_starts[0]);
    try std.testing.expect(first.font_run != null);
    if (first.next_on_line) |next| {
        try std.testing.expectEqual(
            first.span_index,
            geometry.spans[next].previous_on_line.?,
        );
    }
}
