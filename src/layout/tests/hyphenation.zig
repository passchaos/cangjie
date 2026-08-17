//! End-to-end paragraph integration for optional Liang hyphenation.

const std = @import("std");

const font_mod = @import("../../font.zig");
const glyph_position = @import("../glyph_position.zig");
const retained_paragraph = @import("../paragraph/retained.zig");
const styled_buffer = @import("../styled_buffer.zig");
const styled_paragraph = @import("../styled_paragraph.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const Dictionary = @import("../../text/hyphenation/root.zig").Dictionary;
const test_font = @import("../../test_font.zig");

const latin_codepoints = [_]u32{
    0x002d,
    '.',
    'a',
    'b',
    'c',
    'e',
    'h',
    'i',
    'n',
    'o',
    'p',
    'r',
    't',
    'y',
    0x00ad,
    0x2010,
    0x2022,
};

test "selected Liang boundary inserts one source-neutral line-end glyph" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &latin_codepoints,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const wide = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "hyphenation",
        20,
        .{
            .max_width = 1000,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);
    try std.testing.expectEqual("hyphenation".len, wide.glyphs.len);
    for (wide.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }

    const wrapped = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "hyphenation",
        20,
        .{
            .max_width = wide.glyphs[0].x_advance * 2 +
                try hyphenAdvance(&font, 20) + 0.5,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    try std.testing.expect(wrapped.lines.len >= 2);
    const first = wrapped.lines[0];
    try std.testing.expectEqual(@as(usize, 3), first.glyph_len);
    const automatic = wrapped.glyphs[first.glyph_start + first.glyph_len - 1];
    try std.testing.expect(automatic.isAutomaticHyphen());
    try std.testing.expect(automatic.isDiscretionaryHyphen());
    try std.testing.expectEqual(@as(usize, 2), automatic.cluster);
    try std.testing.expectEqual(@as(usize, 0), automatic.source_byte_len);
    try std.testing.expectEqual(@as(usize, 2), first.byteEnd());
    try std.testing.expectEqual(first.byteEnd(), wrapped.lines[1].byte_start);
    try std.testing.expectApproxEqAbs(
        first.width,
        lineAdvance(first.glyphs(wrapped)),
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 1), first.run_len);
    try std.testing.expectEqual(
        wrapped.glyphs.len,
        wrapped.runs[0].glyph_len,
    );

    const hit = wrapped.hitTest(
        first.x + first.width - automatic.x_advance / 2,
        first.y,
    );
    try std.testing.expectEqual(@as(usize, 2), hit.cluster);
}

test "automatic hyphenation cannot bypass shaped boundary safety" {
    const allocator = std.testing.allocator;
    // The broad cmap maps every scalar to one glyph and the legacy kern table
    // marks the A/B source boundary unsafe. The dictionary opportunity must
    // therefore remain unavailable even under extreme overflow.
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        true,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try Dictionary.init(
        allocator,
        "a1b",
        "",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AB",
        20,
        .{
            .max_width = 1,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    for (paragraph.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }
}

test "automatic hyphen follows the RTL visual line end" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(allocator, &.{
        0x002d,
        0x05d0,
        0x05d1,
        0x05d2,
        0x05d3,
        0x2010,
    });
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try Dictionary.init(
        allocator,
        "א1ב",
        "אב-גד",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const unwrapped = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "אבגד",
        20,
        .{
            .max_width = 1000,
            .direction = .rtl,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    const wrapped = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "אבגד",
        20,
        .{
            .max_width = unwrapped.glyphs[0].x_advance * 2 +
                try hyphenAdvance(&font, 20) + 0.5,
            .direction = .rtl,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    try std.testing.expect(wrapped.lines.len >= 2);
    const first = wrapped.lines[0].glyphs(wrapped);
    try std.testing.expect(first.len != 0);
    try std.testing.expect(first[0].isAutomaticHyphen());
    try std.testing.expectEqual("אב".len, first[0].cluster);
}

test "ellipsis removes an automatic continuation hyphen" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &latin_codepoints,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "hyphenation",
        20,
        .{
            .max_width = 16 * 2 + try hyphenAdvance(&font, 20) + 0.5,
            .max_lines = 1,
            .ellipsis = true,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    const first = paragraph.lines[0].glyphs(paragraph);
    for (first) |glyph| {
        try std.testing.expect(!glyph.isDiscretionaryHyphen());
    }
    try std.testing.expectEqual(@as(u21, '.'), first[first.len - 1].codepoint);
}

test "retained automatic hyphenation is repeatable across widths" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &latin_codepoints,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();

    var shape_buffer = context_output.Buffer.init(allocator);
    defer shape_buffer.deinit();
    var paragraph = try shaping_orchestrator.TextShaper.shapeParagraphUtf8(
        allocator,
        cascade,
        &shape_buffer,
        "hyphenation",
        20,
        .{
            .max_width = 1000,
            .hyphenation = .{ .dictionary = &dictionary },
        },
    );
    defer paragraph.deinit();
    const pristine = try allocator.dupe(
        glyph_position.GlyphPosition,
        paragraph.glyphs,
    );
    defer allocator.free(pristine);
    const narrow_width = paragraph.glyphs[0].x_advance * 2 +
        try hyphenAdvance(&font, 20) + 0.5;

    var reflow = retained_paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const narrow = try paragraph.layout(&reflow, .{
        .max_width = narrow_width,
        .hyphenation = .{ .dictionary = &dictionary },
    });
    try std.testing.expect(narrow.lines.len >= 2);
    try std.testing.expect(
        narrow.lines[0].glyphs(narrow)[
            narrow.lines[0].glyph_len - 1
        ].isAutomaticHyphen(),
    );

    const custom = try paragraph.layout(&reflow, .{
        .max_width = narrow_width,
        .hyphenation = .{
            .dictionary = &dictionary,
            .character = 0x2022,
        },
    });
    const custom_hyphen = custom.lines[0].glyphs(custom)[
        custom.lines[0].glyph_len - 1
    ];
    try std.testing.expect(custom_hyphen.isAutomaticHyphen());
    try std.testing.expectEqual(@as(u21, 0x2022), custom_hyphen.codepoint);

    const suppressed = try paragraph.layout(&reflow, .{
        .max_width = narrow_width,
        .hyphenation = .{
            .dictionary = &dictionary,
            .max_consecutive_lines = 0,
        },
    });
    for (suppressed.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }

    const wide = try paragraph.layout(&reflow, .{
        .max_width = 1000,
        .hyphenation = .{ .dictionary = &dictionary },
    });
    try std.testing.expectEqual(@as(usize, 1), wide.lines.len);
    try std.testing.expectEqual(pristine.len, wide.glyphs.len);
    for (wide.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }
    try std.testing.expectEqualSlices(
        glyph_position.GlyphPosition,
        pristine,
        paragraph.glyphs,
    );
    try std.testing.expectError(
        error.ParagraphShapingOptionsChanged,
        paragraph.layout(&reflow, .{ .max_width = narrow_width }),
    );
}

test "styled automatic hyphen inherits the preceding fragment style" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &latin_codepoints,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try Dictionary.init(
        allocator,
        "a1b",
        "ab-c",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    var styled = styled_buffer.Buffer.init(allocator);
    defer styled.deinit();
    const text = "abc";
    const spans = [_]styled_paragraph.Span{
        .{
            .byte_start = 0,
            .byte_len = 2,
            .style_index = 7,
            .font_size = 20,
            .letter_spacing = 3,
            .minimum_line_height = 30,
        },
        .{
            .byte_start = 2,
            .byte_len = text.len - 2,
            .style_index = 9,
            .font_size = 40,
        },
    };

    const paragraph =
        try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
            cascade,
            &buffer,
            &styled,
            text,
            20,
            &spans,
            .{
                .max_width = 2 * (16 + 3) +
                    try hyphenAdvance(&font, 20) + 0.5,
                .max_lines = 1,
                .hyphenation = .{
                    .dictionary = &dictionary,
                    .character = 0x2022,
                },
            },
        );
    // Two retained source glyphs plus one insertion deliberately equal the
    // original three-glyph metadata length. This guards against treating equal
    // list lengths as proof that no automatic sidecar insertion is needed.
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 3), paragraph.glyphs.len);
    const automatic_index =
        paragraph.lines[0].glyph_start + paragraph.lines[0].glyph_len - 1;
    try std.testing.expect(paragraph.glyphs[automatic_index].isAutomaticHyphen());
    try std.testing.expectEqual(
        @as(u21, 0x2022),
        paragraph.glyphs[automatic_index].codepoint,
    );
    try std.testing.expectEqual(
        paragraph.glyphs.len,
        styled.glyphMetadata().len,
    );
    const metadata = styled.glyphMetadata()[automatic_index];
    try std.testing.expectEqual(@as(u32, 7), metadata.style_index);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        metadata.layout_spacing,
        0.001,
    );
    try std.testing.expectEqual(@as(?f32, 30), metadata.minimum_line_height);
}

test "consecutive hyphenated line limit resets after an unhyphenated line" {
    const allocator = std.testing.allocator;
    const codepoints = [_]u32{
        0x002d,
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'i',
        'j',
        'k',
        'l',
        'm',
        'n',
        0x2010,
    };
    const bytes = try test_font.buildCodepointSetTtf(allocator, &codepoints);
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try Dictionary.init(
        allocator,
        "a1b",
        "abc-def-ghi-jkl-mn",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    const width = 16 * 3 + try hyphenAdvance(&font, 20) + 0.5;

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "abcdefghijklmn",
        20,
        .{
            .max_width = width,
            .hyphenation = .{
                .dictionary = &dictionary,
                .max_consecutive_lines = 1,
            },
        },
    );

    var hyphenated_count: usize = 0;
    var previous_hyphenated = false;
    for (paragraph.lines) |line| {
        const glyphs = line.glyphs(paragraph);
        const hyphenated = glyphs.len != 0 and
            glyphs[glyphs.len - 1].isAutomaticHyphen();
        try std.testing.expect(!(previous_hyphenated and hyphenated));
        hyphenated_count += @intFromBool(hyphenated);
        previous_hyphenated = hyphenated;
    }
    try std.testing.expect(hyphenated_count >= 2);
}

test "unsupported requested hyphen character does not become invisible" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildCodepointSetTtf(
        allocator,
        &latin_codepoints,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const cascade = font_fallback.Cascade.init(&.{&font});
    var dictionary = try englishDictionary(allocator);
    defer dictionary.deinit();

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const paragraph = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "hyphenation",
        20,
        .{
            .max_width = 16 * 2 + try hyphenAdvance(&font, 20) + 0.5,
            .hyphenation = .{
                .dictionary = &dictionary,
                .character = 0x2603,
            },
        },
    );
    for (paragraph.glyphs) |glyph| {
        try std.testing.expect(!glyph.isAutomaticHyphen());
    }
}

fn englishDictionary(allocator: std.mem.Allocator) !Dictionary {
    return Dictionary.init(
        allocator,
        "hyphenation",
        "hy-phen-ation",
        .{ .left_min = 2, .right_min = 2 },
    );
}

fn hyphenAdvance(font: *const font_mod.Font, font_size: f32) !f32 {
    return codepointAdvance(font, font_size, 0x2010);
}

fn codepointAdvance(
    font: *const font_mod.Font,
    font_size: f32,
    codepoint: u21,
) !f32 {
    const metrics = try font.horizontalMetrics(try font.glyphIndex(codepoint));
    return @as(f32, @floatFromInt(metrics.advance_width)) *
        (font_size / @as(f32, @floatFromInt(font.units_per_em)));
}

fn lineAdvance(glyphs: []const glyph_position.GlyphPosition) f32 {
    var total: f32 = 0;
    for (glyphs) |glyph| total += glyph.x_advance;
    return total;
}
