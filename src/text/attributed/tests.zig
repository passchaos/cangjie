const std = @import("std");
const attributed_model = @import("root.zig");
const style = @import("../style/root.zig");
const database = @import("../../font/database/root.zig");
const font_mod = @import("../../font.zig");
const glyph_mod = @import("../../glyph.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");
const render_bridge = @import("../../render/bridge/root.zig");
const context_output = @import("../../shaping/context/output.zig");
const font_fallback = @import("../../shaping/fallback/font/root.zig");
const shaping_orchestrator = @import("../../shaping/orchestrator.zig");
const test_font = @import("../../test_font.zig");
const unicode = @import("../../unicode.zig");

const OwnedFont = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    font: font_mod.Font,

    fn init(allocator: std.mem.Allocator, bytes: []u8) !OwnedFont {
        errdefer allocator.free(bytes);
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .font = try font_mod.Font.parse(allocator, bytes),
        };
    }

    fn deinit(self: *OwnedFont) void {
        self.font.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

test "unified attributed paragraph wraps sizes and preserves paint runs" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(allocator, try test_font.buildMinimalTtf(allocator));
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{
            .font_size = 20,
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        } },
        .{ .byte_range = .{ .start = 2, .len = 3 }, .style = .{
            .font_size = 40,
            .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        } },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = "A A A", .spans = &spans },
        60,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.lines.len);
    try std.testing.expect(result.lines[1].height >= 40);
    try std.testing.expectEqual(@as(usize, 2), result.style_runs.len);
    try std.testing.expectEqual(@as(u8, 255), result.style_runs[0].style.color.r);
    try std.testing.expectEqual(@as(u8, 255), result.style_runs[1].style.color.b);
}

test "attributed vertical align places runs decorations and objects in line box" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const marker = @import("../../layout/inline_object/root.zig");
    const text = "A" ++ marker.object_replacement_utf8 ++ "A";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 1 },
            .style = .{
                .font_size = 20,
                .vertical_align = .top,
                .decoration = .{ .underline = true },
            },
        },
        .{
            .byte_range = .{
                .start = 1,
                .len = marker.object_replacement_utf8.len,
            },
            .style = .{
                .font_size = 20,
                .vertical_align = .middle,
            },
        },
        .{
            .byte_range = .{
                .start = 1 + marker.object_replacement_utf8.len,
                .len = 1,
            },
            .style = .{
                .font_size = 20,
                .vertical_align = .bottom,
                .decoration = .{ .strikethrough = true },
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .inline_objects = &.{.{
                .id = 42,
                .byte_index = 1,
                .width = 10,
                .height = 40,
                .baseline = 20,
            }},
        },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectApproxEqAbs(
        @as(f32, 40),
        result.lines[0].height,
        0.001,
    );
    try std.testing.expect(result.glyphs[0].y_offset < 0);
    try std.testing.expect(result.glyphs[2].y_offset > 0);
    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
    try std.testing.expectApproxEqAbs(
        result.lines[0].y,
        result.inline_objects[0].y,
        0.001,
    );
    try std.testing.expectEqual(@as(usize, 2), result.decorations.len);
    try std.testing.expect(
        result.decorations[0].rect.y != result.decorations[1].rect.y,
    );

    var draw_list = try render_bridge.buildGlyphDrawList(
        allocator,
        result.paragraph,
        .{ .decorations = result.decorations },
    );
    defer draw_list.deinit();
    try std.testing.expectEqual(@as(usize, 2), draw_list.glyphs.len);
    try std.testing.expect(draw_list.glyphs[0].y_offset < 0);
    try std.testing.expect(draw_list.glyphs[1].y_offset > 0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        draw_list.runs[0].baseline_y -
            (result.lines[0].y + result.lines[0].baseline),
        0.001,
    );
}

test "attributed layout exposes final styled intrinsic widths" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildLastResortCmapTtfWithKern(
            allocator,
            false,
        ),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = "AAAA AAA";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 5 },
            .style = .{ .font_size = 20 },
        },
        .{
            .byte_range = .{ .start = 5, .len = text.len - 5 },
            .style = .{
                .font_size = 30,
                .letter_spacing = 2,
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .paragraph_style = .{
                .overflow_wrap = .anywhere,
            },
        },
        60,
    );
    defer result.deinit();

    try std.testing.expect(
        result.content_widths.min < result.content_widths.max,
    );
    try std.testing.expect(result.content_widths.min > 16);
    try std.testing.expect(
        result.content_widths.max >= result.paragraph.width,
    );
}

test "attributed balanced wrapping keeps style metadata aligned" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = "AAA AA AA A";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 4 },
            .style = .{
                .font_size = 20,
                .color = .{ .r = 240, .g = 20, .b = 10, .a = 255 },
                .decoration = .{ .underline = true },
            },
        },
        .{
            .byte_range = .{ .start = 4, .len = text.len - 4 },
            .style = .{
                .font_size = 20,
                .color = .{ .r = 10, .g = 40, .b = 220, .a = 255 },
                .decoration = .{ .strikethrough = true },
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .paragraph_style = .{
                .line_break_strategy = .balanced,
            },
        },
        80,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.lines.len);
    try std.testing.expectEqual(@as(usize, 3), result.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), result.lines[1].glyph_len);
    try std.testing.expectEqual(result.glyphs.len, result.style_runs[0].glyph_len +
        result.style_runs[1].glyph_len);
    var saw_first_style = false;
    var saw_second_style = false;
    for (result.decorations) |segment| {
        try std.testing.expect(segment.line_index < result.lines.len);
        if (segment.style_index == 0 and segment.kind == .underline) {
            saw_first_style = true;
        }
        if (segment.style_index == 1 and segment.kind == .strikethrough) {
            saw_second_style = true;
        }
    }
    try std.testing.expect(saw_first_style);
    try std.testing.expect(saw_second_style);
}

test "attributed overflow wrapping preserves style and decoration sidecars" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildLastResortCmapTtfWithKern(
            allocator,
            false,
        ),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = "AAAA";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 2 },
            .style = .{
                .font_size = 20,
                .decoration = .{ .underline = true },
            },
        },
        .{
            .byte_range = .{ .start = 2, .len = 2 },
            .style = .{
                .font_size = 20,
                .decoration = .{ .strikethrough = true },
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .paragraph_style = .{
                .word_break = .break_all,
                .overflow_wrap = .normal,
            },
        },
        17,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.lines.len);
    try std.testing.expectEqual(result.glyphs.len, 4);
    var saw_underline = false;
    var saw_strike = false;
    for (result.decorations) |segment| {
        try std.testing.expect(segment.line_index < result.lines.len);
        saw_underline = saw_underline or segment.kind == .underline;
        saw_strike = saw_strike or segment.kind == .strikethrough;
    }
    try std.testing.expect(saw_underline);
    try std.testing.expect(saw_strike);
}

test "attributed text spans override paragraph wrapping policy" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildLastResortCmapTtfWithKern(
            allocator,
            false,
        ),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = "AAAABBBB";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 4 },
            .style = .{
                .font_size = 20,
                .wrap_mode = .no_wrap,
                .decoration = .{ .underline = true },
            },
        },
        .{
            .byte_range = .{ .start = 4, .len = 4 },
            .style = .{
                .font_size = 20,
                .decoration = .{ .strikethrough = true },
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = text, .spans = &spans },
        17,
    );
    defer result.deinit();

    try std.testing.expect(result.lines.len > 1);
    try std.testing.expectEqual(@as(usize, 5), result.lines[0].byte_len);
    try std.testing.expect(result.lines[0].width > 17);
    try std.testing.expectEqual(@as(usize, 2), result.style_runs.len);
    try std.testing.expectEqual(@as(usize, 4), result.style_runs[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 4), result.style_runs[1].glyph_len);
}

test "attributed whitespace collapse preserves paint and decoration ownership" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildLastResortCmapTtfWithKern(
            allocator,
            false,
        ),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = " A   A ";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 3 },
            .style = .{
                .font_size = 20,
                .color = .{ .r = 180, .g = 20, .b = 10, .a = 255 },
                .decoration = .{ .underline = true },
            },
        },
        .{
            .byte_range = .{ .start = 3, .len = text.len - 3 },
            .style = .{
                .font_size = 20,
                .color = .{ .r = 10, .g = 40, .b = 200, .a = 255 },
                .decoration = .{ .strikethrough = true },
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .paragraph_style = .{
                .white_space_collapse = .collapse,
            },
        },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.lines.len);
    try std.testing.expectEqual(result.glyphs.len, 7);
    try std.testing.expectEqual(@as(f32, 0), result.glyphs[0].x_advance);
    try std.testing.expectEqual(@as(f32, 0), result.glyphs[6].x_advance);
    try std.testing.expectEqual(
        result.glyphs.len,
        result.style_runs[0].glyph_len + result.style_runs[1].glyph_len,
    );
    var saw_underline = false;
    var saw_strike = false;
    for (result.decorations) |segment| {
        saw_underline = saw_underline or segment.kind == .underline;
        saw_strike = saw_strike or segment.kind == .strikethrough;
        try std.testing.expect(segment.rect.width > 0);
    }
    try std.testing.expect(saw_underline);
    try std.testing.expect(saw_strike);
}

test "unified attributed paragraph applies feature spacing and measurement" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildScriptFeatureGsubTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const enable_sups = [_]unicode.FeatureOverride{
        .{ .tag = unicode.tag("sups"), .enabled = true },
    };
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{
            .font_size = 20,
        } },
        .{ .byte_range = .{ .start = 1, .len = 2 }, .style = .{
            .font_size = 20,
            .font_features = &enable_sups,
            .letter_spacing = 3,
        } },
    };
    const attributed = attributed_model.AttributedText{ .text = "AAA", .spans = &spans };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        attributed,
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), result.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 2), result.glyphs[1].glyph_id);
    try std.testing.expectApproxEqAbs(@as(f32, 23), result.glyphs[1].x_advance, 0.001);

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    const measured = try attributed_model.measureAttributedTextUtf8(
        font_fallback.Cascade.init(&fonts),
        &buffer,
        attributed,
        200,
    );
    try std.testing.expectApproxEqAbs(result.paragraph.width, measured.width, 0.001);
    try std.testing.expectApproxEqAbs(result.paragraph.height, measured.height, 0.001);
}

test "paint-only spans preserve ligatures and selection geometry" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalGsubTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{
            .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        } },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = "AA", .spans = &spans },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.glyphs.len);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 2), result.glyphs[0].glyph_id);
    try std.testing.expect(result.paragraph.selectionRectForBytes(0, 2).width > 0);
}

test "styled bidi order carries paint fragments" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildLastResortCmapTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const text = "A אב";
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{} },
        .{ .byte_range = .{ .start = 2, .len = text.len - 2 }, .style = .{
            .decoration = .{ .underline = true },
        } },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = text, .spans = &spans },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqualSlices(u21, &.{ 'A', ' ', 0x05d1, 0x05d0 }, &.{
        result.glyphs[0].codepoint,
        result.glyphs[1].codepoint,
        result.glyphs[2].codepoint,
        result.glyphs[3].codepoint,
    });
    var saw_underlined = false;
    for (result.style_runs) |run| {
        saw_underlined = saw_underlined or run.style.decoration.underline;
    }
    try std.testing.expect(saw_underlined);
    try std.testing.expectEqual(@as(usize, 1), result.decorations.len);
    const segment = result.decorations[0];
    try std.testing.expectEqual(
        attributed_model.TextDecorationKind.underline,
        segment.kind,
    );
    try std.testing.expectEqual(@as(usize, 0), segment.line_index);
    try std.testing.expectEqual(@as(u32, 1), segment.style_index);
    try std.testing.expect(segment.rect.width > 0);
    // Logical Hebrew is reordered to the physical right of the Latin prefix;
    // decoration geometry must use that final visual location.
    try std.testing.expect(segment.rect.x >= result.glyphs[0].x_advance);
}

test "attributed decorations split at wraps styles and font runs" {
    const allocator = std.testing.allocator;
    const primary_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'A',
        800,
        -200,
        0,
    );
    defer allocator.free(primary_bytes);
    const fallback_bytes = try test_font.buildSingleCodepointTtfWithLineMetrics(
        allocator,
        'B',
        1100,
        -350,
        100,
    );
    defer allocator.free(fallback_bytes);
    var primary = try font_mod.Font.parse(allocator, primary_bytes);
    defer primary.deinit();
    var fallback = try font_mod.Font.parse(allocator, fallback_bytes);
    defer fallback.deinit();
    const fonts = [_]*const font_mod.Font{ &primary, &fallback };
    const text = "AB AB";
    const spans = [_]style.StyleSpan{
        .{
            .byte_range = .{ .start = 0, .len = 2 },
            .style = .{
                .font_size = 20,
                .color = .{ .r = 200, .g = 10, .b = 20, .a = 255 },
                .decoration = .{ .underline = true },
            },
        },
        .{
            .byte_range = .{ .start = 2, .len = text.len - 2 },
            .style = .{
                .font_size = 30,
                .color = .{ .r = 20, .g = 30, .b = 220, .a = 255 },
                .decoration = .{
                    .underline = true,
                    .strikethrough = true,
                },
            },
        },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = text, .spans = &spans },
        45,
    );
    defer result.deinit();

    try std.testing.expect(result.lines.len >= 2);
    try std.testing.expect(result.decorations.len >= 4);
    var saw_primary_underline = false;
    var saw_fallback_underline = false;
    var saw_second_line_strike = false;
    for (result.decorations) |segment| {
        try std.testing.expect(segment.rect.width > 0);
        try std.testing.expect(segment.rect.height >= 0.5);
        if (segment.kind == .underline and segment.font_run_index == 0) {
            saw_primary_underline = true;
        }
        if (segment.kind == .underline and segment.font_run_index != 0) {
            saw_fallback_underline = true;
        }
        if (segment.kind == .strikethrough and segment.line_index != 0) {
            saw_second_line_strike = true;
        }
    }
    try std.testing.expect(saw_primary_underline);
    try std.testing.expect(saw_fallback_underline);
    try std.testing.expect(saw_second_line_strike);
}

test "decorations bridge through render origin with style color" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]style.StyleSpan{.{
        .byte_range = .{ .start = 0, .len = 2 },
        .style = .{
            .font_size = 20,
            .color = .{ .r = 9, .g = 80, .b = 170, .a = 230 },
            .decoration = .{
                .underline = true,
                .strikethrough = true,
            },
        },
    }};
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = "AA", .spans = &spans },
        100,
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.decorations.len);

    var draw_list = try render_bridge.buildGlyphDrawList(
        allocator,
        result.paragraph,
        .{
            .origin_x = 5,
            .origin_y = 7,
            .decorations = result.decorations,
        },
    );
    defer draw_list.deinit();
    try std.testing.expectEqual(result.decorations.len, draw_list.decorations.len);
    for (result.decorations, draw_list.decorations) |source, drawn| {
        try std.testing.expectEqual(source.kind, drawn.kind);
        try std.testing.expectEqual(source.color, drawn.color);
        try std.testing.expectApproxEqAbs(
            source.rect.x + 5,
            drawn.rect.x,
            0.001,
        );
        try std.testing.expectApproxEqAbs(
            source.rect.y + 7,
            drawn.rect.y,
            0.001,
        );
    }
}

test "underline rectangle uses font centerline metrics" {
    const allocator = std.testing.allocator;
    var post: [32]u8 = .{0} ** 32;
    const sfnt_fixture = @import("../../font/tests/fixtures/sfnt.zig");
    sfnt_fixture.writeU32(&post, 0, 0x00030000);
    sfnt_fixture.writeI16(&post, 8, -125);
    sfnt_fixture.writeI16(&post, 10, 45);
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalTtfWithPost(allocator, &post),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]style.StyleSpan{.{
        .byte_range = .{ .start = 0, .len = 1 },
        .style = .{
            .font_size = 20,
            .decoration = .{ .underline = true },
        },
    }};
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = "A", .spans = &spans },
        100,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.decorations.len);
    const segment = result.decorations[0];
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.9),
        segment.rect.height,
        0.001,
    );
    const baseline_y =
        result.lines[0].y + result.lines[0].baseline;
    try std.testing.expectApproxEqAbs(
        baseline_y + 2.5 - 0.45,
        segment.rect.y,
        0.001,
    );
}

test "underline continues through tab but stops at inline object" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const marker = @import("../../layout/inline_object/root.zig");
    const text =
        "A\tA" ++ marker.object_replacement_utf8 ++ "A";
    const spans = [_]style.StyleSpan{.{
        .byte_range = .{ .start = 0, .len = text.len },
        .style = .{
            .font_size = 20,
            .decoration = .{ .underline = true },
        },
    }};
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .inline_objects = &.{.{
                .id = 91,
                .byte_index = 3,
                .width = 14,
                .height = 18,
            }},
        },
        120,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.decorations.len);
    try std.testing.expectApproxEqAbs(
        result.paragraph.glyphs[0].x_advance +
            result.paragraph.glyphs[1].x_advance +
            result.paragraph.glyphs[2].x_advance,
        result.decorations[0].rect.width +
            result.decorations[1].rect.width,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        result.decorations[0].rect.x +
            result.decorations[0].rect.width,
        result.decorations[1].rect.x,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        result.paragraph.glyphs[0].x_advance +
            result.paragraph.glyphs[1].x_advance +
            result.paragraph.glyphs[2].x_advance +
            result.paragraph.glyphs[3].x_advance,
        result.decorations[2].rect.x,
        0.001,
    );
}

test "attributed paragraph retains inline object geometry and style metadata" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildMinimalTtf(allocator),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const marker = @import("../../layout/inline_object/root.zig");
    const text = "A" ++ marker.object_replacement_utf8 ++ "A";
    const spans = [_]style.StyleSpan{.{
        .byte_range = .{ .start = 0, .len = text.len },
        .style = .{ .color = .{ .r = 5, .g = 10, .b = 15, .a = 255 } },
    }};
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = text,
            .spans = &spans,
            .inline_objects = &.{.{
                .id = 88,
                .byte_index = 1,
                .width = 14,
                .height = 18,
            }},
        },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.inline_objects.len);
    try std.testing.expectEqual(@as(u64, 88), result.inline_objects[0].id);
    try std.testing.expectEqual(@as(usize, 1), result.style_runs.len);
    try std.testing.expectEqual(@as(usize, 3), result.style_runs[0].glyph_len);

    const attributed = attributed_model.AttributedText{
        .text = text,
        .spans = &spans,
        .inline_objects = &.{.{
            .id = 88,
            .byte_index = 1,
            .width = 14,
            .height = 18,
        }},
    };
    try std.testing.expectError(
        error.InlineObjectsRequireParagraphLayout,
        attributed_model.layoutAttributedRunsUtf8(
            allocator,
            font_fallback.Cascade.init(&fonts),
            attributed,
        ),
    );
}

test "styled cascade fallback keeps size and minimum line height" {
    const allocator = std.testing.allocator;
    var primary = try OwnedFont.init(
        allocator,
        try test_font.buildSingleCodepointTtf(allocator, 'A'),
    );
    defer primary.deinit();
    var fallback = try OwnedFont.init(
        allocator,
        try test_font.buildSingleCodepointTtfWithLineMetrics(
            allocator,
            'B',
            1100,
            -350,
            100,
        ),
    );
    defer fallback.deinit();
    const fonts = [_]*const font_mod.Font{ &primary.font, &fallback.font };
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{
            .font_size = 20,
        } },
        .{ .byte_range = .{ .start = 1, .len = 1 }, .style = .{
            .font_size = 40,
            .line_height = 70,
        } },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{ .text = "AB", .spans = &spans },
        200,
    );
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.font_runs[1].font_index);
    try std.testing.expectApproxEqAbs(@as(f32, 40), result.font_runs[1].font_size, 0.001);
    try std.testing.expect(result.lines[0].height >= 70);
}

test "styled Arabic items retain joining context" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(
        allocator,
        try test_font.buildCodepointSetTtf(
            allocator,
            &.{ 0x0627, 0x0628, 0xfe8e },
        ),
    );
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{
            .font_size = 20,
        } },
        .{ .byte_range = .{ .start = 2, .len = 2 }, .style = .{
            .font_size = 24,
            .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        } },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        font_fallback.Cascade.init(&fonts),
        .{
            .text = "با",
            .spans = &spans,
            .paragraph_style = .{ .direction = .rtl },
        },
        200,
    );
    defer result.deinit();

    // ALEF is the second logical item but first visually. It must use the final
    // presentation-form glyph, proving the preceding style item was context.
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 3), result.glyphs[0].glyph_id);
}

test "styled ellipsis inherits terminal paint and buffer reuse clears metadata" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(allocator, try test_font.buildMinimalTtf(allocator));
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    const cascade = font_fallback.Cascade.init(&fonts);
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 2 }, .style = .{} },
        .{ .byte_range = .{ .start = 2, .len = 5 }, .style = .{
            .color = .{ .r = 0, .g = 180, .b = 0, .a = 255 },
            .decoration = .{ .underline = true },
        } },
    };
    var result = try attributed_model.layoutAttributedParagraphUtf8(
        allocator,
        cascade,
        .{
            .text = "A A A A",
            .spans = &spans,
            .paragraph_style = .{ .max_lines = 1, .ellipsis = true },
        },
        45,
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(u8, 180), result.style_runs[result.style_runs.len - 1].style.color.g);
    try std.testing.expectEqual(@as(u21, '.'), result.glyphs[result.glyphs.len - 1].codepoint);
    const terminal_style_index =
        result.style_runs[result.style_runs.len - 1].style_index;
    var terminal_decoration_end: ?f32 = null;
    for (result.decorations) |segment| {
        if (segment.style_index != terminal_style_index) continue;
        terminal_decoration_end = segment.rect.x + segment.rect.width;
    }
    try std.testing.expect(terminal_decoration_end != null);
    var line_advance: f32 = 0;
    const line = result.lines[result.lines.len - 1];
    for (result.glyphs[line.glyph_start .. line.glyph_start + line.glyph_len]) |glyph| {
        line_advance += glyph.x_advance;
    }
    // Synthetic ellipsis dots inherit terminal paint and must be included in
    // the final decoration rectangle rather than ending at source text.
    try std.testing.expectApproxEqAbs(
        line.x + line_advance,
        terminal_decoration_end.?,
        0.001,
    );

    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    var styled = styled_buffer.Buffer.init(allocator);
    defer styled.deinit();
    _ = try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        "AA",
        16,
        &.{.{ .byte_start = 0, .byte_len = 2, .style_index = 9, .font_size = 16 }},
        .{ .max_width = 100 },
    );
    try std.testing.expectEqual(@as(usize, 2), styled.glyphMetadata().len);
    _ = try shaping_orchestrator.TextShaper.layoutParagraphUtf8(
        cascade,
        &buffer,
        "AA",
        16,
        .{ .max_width = 100 },
    );
    // Ordinary layout owns no style state and therefore cannot mutate a
    // caller-owned sidecar. Starting another styled layout resets it.
    try std.testing.expectEqual(@as(usize, 2), styled.glyphMetadata().len);
    _ = try shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
        cascade,
        &buffer,
        &styled,
        "",
        16,
        &.{},
        .{ .max_width = 100 },
    );
    try std.testing.expectEqual(@as(usize, 0), styled.glyphMetadata().len);
}

test "styled paragraph rejects incomplete source partitions" {
    const allocator = std.testing.allocator;
    var owned = try OwnedFont.init(allocator, try test_font.buildMinimalTtf(allocator));
    defer owned.deinit();
    const fonts = [_]*const font_mod.Font{&owned.font};
    var buffer = context_output.Buffer.init(allocator);
    defer buffer.deinit();
    var styled = styled_buffer.Buffer.init(allocator);
    defer styled.deinit();
    try std.testing.expectError(
        error.InvalidStyleSpans,
        shaping_orchestrator.TextShaper.layoutStyledParagraphUtf8(
            font_fallback.Cascade.init(&fonts),
            &buffer,
            &styled,
            "AA",
            16,
            &.{.{ .byte_start = 1, .byte_len = 1, .style_index = 0, .font_size = 16 }},
            .{ .max_width = 100 },
        ),
    );
}

test "font database resolves attributed families weights and fallback" {
    const allocator = std.testing.allocator;
    const primary_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(
        allocator,
        'A',
        "Primary Sans",
        "Regular",
        "Primary Sans Regular",
    );
    defer allocator.free(primary_bytes);
    const alternate_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(
        allocator,
        'B',
        "Alternate Sans",
        "Regular",
        "Alternate Sans Regular",
    );
    defer allocator.free(alternate_bytes);
    const fallback_bytes = try test_font.buildNamedSingleCodepointTtfWithNames(
        allocator,
        'C',
        "Fallback Sans",
        "Regular",
        "Fallback Sans Regular",
    );
    defer allocator.free(fallback_bytes);
    const regular_bytes = try test_font.buildNamedTtfWithStyle(
        allocator,
        "Weighted Sans",
        "Regular",
        "Weighted Sans Regular",
        400,
        5,
        false,
        false,
    );
    defer allocator.free(regular_bytes);
    const bold_italic_bytes = try test_font.buildNamedTtfWithStyle(
        allocator,
        "Weighted Sans",
        "Bold Italic",
        "Weighted Sans Bold Italic",
        700,
        5,
        true,
        true,
    );
    defer allocator.free(bold_italic_bytes);

    var font_database = database.FontDatabase.init(allocator);
    defer font_database.deinit();
    _ = try font_database.addFontBytes(primary_bytes);
    _ = try font_database.addFontBytes(alternate_bytes);
    _ = try font_database.addFontBytes(fallback_bytes);
    _ = try font_database.addFontBytes(regular_bytes);
    _ = try font_database.addFontBytes(bold_italic_bytes);

    const text = "ABCA";
    const spans = [_]style.StyleSpan{
        .{ .byte_range = .{ .start = 0, .len = 1 }, .style = .{} },
        .{ .byte_range = .{ .start = 1, .len = 2 }, .style = .{
            .font_family = "Alternate Sans",
            .color = .{ .r = 20, .g = 40, .b = 60, .a = 255 },
        } },
        .{ .byte_range = .{ .start = 3, .len = 1 }, .style = .{
            .font_family = "Weighted Sans",
            .font_weight = .bold,
            .font_style = .italic,
        } },
    };
    const attributed = attributed_model.AttributedText{ .text = text, .spans = &spans };
    var result = try font_database.layoutAttributedParagraphUtf8(
        allocator,
        attributed,
        .{ .family = "Primary Sans" },
        300,
    );
    defer result.deinit();

    const primary = font_database.match(.{ .family = "Primary Sans" }).?.face;
    const alternate = font_database.match(.{ .family = "Alternate Sans" }).?.face;
    const fallback = font_database.match(.{ .family = "Fallback Sans" }).?.face;
    const bold_italic = font_database.match(.{
        .family = "Weighted Sans",
        .weight = 700,
        .style = .italic,
    }).?.face;
    try std.testing.expectEqual(@as(usize, 4), result.font_runs.len);
    try std.testing.expectEqual(
        primary,
        result.font_runs[0].font,
    );
    try std.testing.expectEqual(
        alternate,
        result.font_runs[1].font,
    );
    try std.testing.expectEqual(
        fallback,
        result.font_runs[2].font,
    );
    try std.testing.expectEqual(
        bold_italic,
        result.font_runs[3].font,
    );
    try std.testing.expectEqual(@as(usize, 0), result.font_runs[0].font_index);
    try std.testing.expectEqual(@as(usize, 1), result.font_runs[1].font_index);
    try std.testing.expectEqual(@as(usize, 2), result.font_runs[2].font_index);
    try std.testing.expectEqual(@as(usize, 3), result.font_runs[3].font_index);
    try std.testing.expectEqual(@as(u8, 40), result.style_runs[1].style.color.g);

    const measured = try font_database.measureAttributedTextUtf8(
        allocator,
        attributed,
        .{ .family = "Primary Sans" },
        300,
    );
    try std.testing.expectApproxEqAbs(result.paragraph.width, measured.width, 0.001);
    try std.testing.expectApproxEqAbs(result.paragraph.height, measured.height, 0.001);
}

test "font database attributed layout reports unresolved families" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildNamedSingleCodepointTtfWithNames(
        allocator,
        'A',
        "Present Sans",
        "Regular",
        "Present Sans Regular",
    );
    defer allocator.free(bytes);
    var font_database = database.FontDatabase.init(allocator);
    defer font_database.deinit();
    _ = try font_database.addFontBytes(bytes);

    const spans = [_]style.StyleSpan{.{
        .byte_range = .{ .start = 0, .len = 1 },
        .style = .{ .font_family = "Missing Sans" },
    }};
    try std.testing.expectError(
        error.FontFamilyNotFound,
        font_database.layoutAttributedParagraphUtf8(
            allocator,
            attributed_model.AttributedText{ .text = "A", .spans = &spans },
            .{ .family = "Present Sans" },
            100,
        ),
    );
}
