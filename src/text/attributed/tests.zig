const std = @import("std");
const attributed_model = @import("root.zig");
const style = @import("../style/root.zig");
const database = @import("../../database.zig");
const font_mod = @import("../../font.zig");
const glyph_mod = @import("../../glyph.zig");
const styled_buffer = @import("../../layout/styled_buffer.zig");
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
