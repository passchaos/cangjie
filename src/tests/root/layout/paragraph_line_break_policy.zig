//! UTF-8 ranged and attributed paragraph wrapping policy.

const std = @import("std");

const paragraph = @import("../../../api/paragraph/root.zig");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

const Font = support.Font;
const FontCascade = support.FontCascade;
const LayoutBuffer = support.LayoutBuffer;
const ReflowBuffer = support.ReflowBuffer;
const StyledParagraphBuffer = support.StyledParagraphBuffer;
const StyledParagraphSpan = support.StyledParagraphSpan;
const TextShaper = support.TextShaper;

test "ranged no-wrap defers emergency wrapping until the following style" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAABBBB";
    const ranges = [_]paragraph.LineBreakPolicyRange{.{
        .byte_start = 0,
        .byte_len = 4,
        .wrap_mode = .no_wrap,
    }};

    const greedy = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 33,
            .line_break_policy_ranges = &ranges,
        },
    );
    try std.testing.expect(greedy.lines.len > 1);
    // The boundary after byte 4 belongs to the preceding no-wrap range. The
    // first legal emergency boundary is after one scalar of the next style.
    try std.testing.expectEqual(@as(usize, 5), greedy.lines[0].byte_len);
    try std.testing.expect(greedy.lines[0].width > 17);

    const balanced = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 17,
            .line_break_strategy = .balanced,
            .line_break_policy_ranges = &ranges,
        },
    );
    try std.testing.expect(balanced.lines.len > 1);
    try std.testing.expectEqual(@as(usize, 5), balanced.lines[0].byte_len);
}

test "ranged no-wrap never suppresses Unicode hard breaks" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AA\nAA";
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 1,
            .line_break_policy_ranges = &.{.{
                .byte_start = 0,
                .byte_len = text.len,
                .wrap_mode = .no_wrap,
            }},
        },
    );

    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectEqual(@as(usize, "AA\n".len), layout.lines[0].byte_len);
    try std.testing.expectEqual(@as(usize, "AA".len), layout.lines[1].byte_len);
}

test "ranged break-all affects only its owned source boundaries" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "AAAABBBB";
    const ranges = [_]paragraph.LineBreakPolicyRange{.{
        .byte_start = 0,
        .byte_len = 4,
        .word_break = .break_all,
    }};
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 17,
            .overflow_wrap = .normal,
            .line_break_policy_ranges = &ranges,
        },
    );

    try std.testing.expectEqual(@as(usize, 5), layout.lines.len);
    for (layout.lines[0..4]) |line| {
        try std.testing.expectEqual(@as(usize, 1), line.byte_len);
    }
    try std.testing.expectEqual(@as(usize, 4), layout.lines[4].byte_len);
    try std.testing.expect(layout.lines[4].width > 17);
}

test "ranged keep-all suppresses only covered CJK boundaries" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedCjkTtfWithKern(allocator, false);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    const text = "一丁丂";
    const first_len = "一".len;
    const first_two_len = "一丁".len;
    const layout = try TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        text,
        20,
        .{
            .max_width = 33,
            .overflow_wrap = .normal,
            .line_break_policy_ranges = &.{.{
                .byte_start = 0,
                .byte_len = first_len,
                .word_break = .keep_all,
            }},
        },
    );

    try std.testing.expectEqual(@as(usize, 2), layout.lines.len);
    try std.testing.expectEqual(first_two_len, layout.lines[0].byte_len);
    try std.testing.expect(layout.lines[0].width <= 33.001);
    try std.testing.expectEqual(
        @as(usize, "丂".len),
        layout.lines[1].byte_len,
    );
}

test "retained paragraphs reflow ranged policy without reshaping" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    const text = "AAAABBBB";
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{ .max_width = 1000 },
    );
    defer shaped.deinit();
    const pristine = try allocator.dupe(
        @TypeOf(shaped.glyphs[0]),
        shaped.glyphs,
    );
    defer allocator.free(pristine);
    var reflow = ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const ranges = [_]paragraph.LineBreakPolicyRange{.{
        .byte_start = 0,
        .byte_len = 4,
        .word_break = .break_all,
    }};

    const ranged = try shaped.layout(&reflow, .{
        .max_width = 17,
        .overflow_wrap = .normal,
        .line_break_policy_ranges = &ranges,
    });
    try std.testing.expectEqual(@as(usize, 5), ranged.lines.len);
    const widths = try shaped.contentWidths(.{
        .max_width = 17,
        .overflow_wrap = .normal,
        .line_break_policy_ranges = &ranges,
    });
    try std.testing.expectApproxEqAbs(@as(f32, 64), widths.min, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 128), widths.max, 0.001);

    const inherited = try shaped.layout(&reflow, .{
        .max_width = 17,
        .overflow_wrap = .normal,
    });
    try std.testing.expectEqual(@as(usize, 1), inherited.lines.len);
    try std.testing.expectEqualSlices(
        @TypeOf(shaped.glyphs[0]),
        pristine,
        shaped.glyphs,
    );
}

test "resumable retained breaker advances ranged policy one line at a time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var shape_buffer = LayoutBuffer.init(allocator);
    defer shape_buffer.deinit();
    const text = "AAAABBBB";
    var shaped = try TextShaper.shapeParagraphUtf8(
        allocator,
        FontCascade.init(&.{&font}),
        &shape_buffer,
        text,
        20,
        .{ .max_width = 1000 },
    );
    defer shaped.deinit();
    const ranges = [_]paragraph.LineBreakPolicyRange{.{
        .byte_start = 0,
        .byte_len = 4,
        .wrap_mode = .no_wrap,
    }};
    var expected_reflow = ReflowBuffer.init(allocator);
    defer expected_reflow.deinit();
    const options = paragraph.Options{
        .max_width = 17,
        .line_break_policy_ranges = &ranges,
    };
    const expected = try shaped.layout(&expected_reflow, options);

    var incremental_reflow = ReflowBuffer.init(allocator);
    defer incremental_reflow.deinit();
    var breaker = try shaped.breakLines(&incremental_reflow, options);
    defer breaker.deinit();
    var committed: usize = 0;
    while (true) {
        switch (try breaker.advance(.{})) {
            .line => |line| {
                committed += 1;
                try std.testing.expectEqual(
                    line,
                    (try breaker.partialLayout()).lines[committed - 1],
                );
            },
            .height_exceeded => return error.UnexpectedHeightExceeded,
            .complete => |actual| {
                try std.testing.expectEqual(expected.lines.len, committed);
                try std.testing.expectEqualSlices(
                    paragraph.Line,
                    expected.lines,
                    actual.lines,
                );
                break;
            },
        }
    }
}

test "styled spans project wrapping policy without splitting metadata" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AAAABBBB";
    const spans = [_]StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 4,
            .style_index = 7,
            .font_size = 20,
            .wrap_mode = .no_wrap,
        },
        .{
            .byte_start = 4,
            .byte_len = 4,
            .style_index = 9,
            .font_size = 20,
        },
    };
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{ .max_width = 17 },
    );

    try std.testing.expect(layout.lines.len > 1);
    try std.testing.expectEqual(@as(usize, 5), layout.lines[0].byte_len);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
    for (styled.glyphMetadata()[0..4]) |metadata| {
        try std.testing.expectEqual(@as(u32, 7), metadata.style_index);
    }
    for (styled.glyphMetadata()[4..]) |metadata| {
        try std.testing.expectEqual(@as(u32, 9), metadata.style_index);
    }
}

test "styled wrapping overrides merge with paragraph policy ranges" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AAAABBBB";
    const spans = [_]StyledParagraphSpan{
        .{
            .byte_start = 0,
            .byte_len = 4,
            .style_index = 1,
            .font_size = 20,
            // Override only word-break; retain the paragraph-authored
            // no-wrap value over the same range.
            .word_break = .break_all,
        },
        .{
            .byte_start = 4,
            .byte_len = 4,
            .style_index = 2,
            .font_size = 20,
        },
    };
    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 17,
            .line_break_policy_ranges = &.{.{
                .byte_start = 0,
                .byte_len = 4,
                .wrap_mode = .no_wrap,
            }},
        },
    );

    try std.testing.expect(layout.lines.len > 1);
    try std.testing.expectEqual(@as(usize, 5), layout.lines[0].byte_len);
}

test "styled layout shares intrinsic analysis with emergency wrapping" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const text = "AAAA AAA";
    const spans = [_]StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 3,
        .font_size = 20,
    }};

    const layout = try TextShaper.layoutStyledParagraphUtf8(
        FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 17,
            .word_break = .break_all,
            .overflow_wrap = .anywhere,
        },
    );

    try std.testing.expect(layout.lines.len > 1);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
    for (styled.glyphMetadata()) |metadata| {
        try std.testing.expectEqual(@as(u32, 3), metadata.style_index);
    }
    const widths = styled.contentWidths().?;
    try std.testing.expect(widths.min < widths.max);
}

test "line-break policy ranges reject overlap and invalid UTF-8 boundaries" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = LayoutBuffer.init(allocator);
    defer buffer.deinit();

    try std.testing.expectError(
        error.InvalidParagraphOptions,
        TextShaper.layoutParagraphUtf8(
            FontCascade.init(&.{&font}),
            &buffer,
            "AAAA",
            20,
            .{
                .max_width = 20,
                .line_break_policy_ranges = &.{
                    .{
                        .byte_start = 0,
                        .byte_len = 3,
                        .wrap_mode = .no_wrap,
                    },
                    .{
                        .byte_start = 2,
                        .byte_len = 2,
                        .word_break = .break_all,
                    },
                },
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidParagraphOptions,
        TextShaper.layoutParagraphUtf8(
            FontCascade.init(&.{&font}),
            &buffer,
            "一",
            20,
            .{
                .max_width = 20,
                .line_break_policy_ranges = &.{.{
                    .byte_start = 1,
                    .byte_len = 1,
                    .wrap_mode = .no_wrap,
                }},
            },
        ),
    );
}
