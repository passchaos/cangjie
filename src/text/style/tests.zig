//! Range, locale, and paragraph-style model tests.

const std = @import("std");
const style_model = @import("root.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const hyphenation = @import("../hyphenation/root.zig");
const segmentation = @import("../segmentation/root.zig");

const FontId = style_model.FontId;
const Language = style_model.Language;
const Locale = style_model.Locale;
const GlyphCluster = style_model.GlyphCluster;
const ParagraphStyle = style_model.ParagraphStyle;

test "core identifiers locale and glyph cluster helpers" {
    const font_id = FontId{ .index = 3 };
    try std.testing.expect(font_id.isValid());
    try std.testing.expect(!FontId.invalid.isValid());

    const language = Language{ .tag = "zh" };
    try std.testing.expect(language.isValid());
    const bad_language = Language{ .tag = "bad tag" };
    try std.testing.expect(!bad_language.isValid());

    const locale = Locale{ .tag = "zh-Hans-CN" };
    try std.testing.expect(locale.isValid());
    try std.testing.expectEqualStrings("zh", locale.language().tag);
    const parts = try locale.parse();
    try std.testing.expectEqualStrings("zh", parts.language);
    try std.testing.expectEqualStrings("Hans", parts.script.?);
    try std.testing.expectEqualStrings("CN", parts.region.?);

    const variant_locale = Locale{ .tag = "sl-rozaj-biske" };
    const variant_parts = try variant_locale.parse();
    try std.testing.expectEqualStrings("sl", variant_parts.language);
    try std.testing.expect(variant_parts.script == null);
    try std.testing.expect(variant_parts.region == null);
    try std.testing.expectEqual(@as(usize, 2), variant_parts.variantSlice().len);
    try std.testing.expectEqualStrings("rozaj", variant_parts.variantSlice()[0]);
    const bad_locale = Locale{ .tag = "bad tag" };
    try std.testing.expect(!bad_locale.isValid());

    const mixed = Locale{ .tag = "ZH_hANS_cn_ROZAJ" };
    const canonical = try mixed.canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(canonical);
    try std.testing.expectEqualStrings("zh-Hans-CN-rozaj", canonical);

    const hebrew_alias = try (Locale{ .tag = "IW-il" }).canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(hebrew_alias);
    try std.testing.expectEqualStrings("he-IL", hebrew_alias);
    const indonesian_alias = try (Locale{ .tag = "in-ID" }).canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(indonesian_alias);
    try std.testing.expectEqualStrings("id-ID", indonesian_alias);
    const yiddish_alias = try (Locale{ .tag = "ji" }).canonicalize(std.testing.allocator);
    defer std.testing.allocator.free(yiddish_alias);
    try std.testing.expectEqualStrings("yi", yiddish_alias);

    const cluster = GlyphCluster{
        .text_range = .{ .start = 1, .len = 3 },
        .glyph_range = .{ .start = 4, .len = 2 },
    };
    try std.testing.expect(cluster.containsByte(2));
    try std.testing.expect(!cluster.containsByte(4));
    try std.testing.expectEqual(@as(usize, 6), cluster.glyph_range.end());
}

test "paragraph style converts to paragraph options" {
    var dictionary = try segmentation.WordBreakDictionary.init(
        std.testing.allocator,
        .thai,
        &.{"ไทย"},
    );
    defer dictionary.deinit();
    var hyphenation_dictionary = try hyphenation.Dictionary.init(
        std.testing.allocator,
        "a1b",
        "",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer hyphenation_dictionary.deinit();
    const style = ParagraphStyle{
        .direction = .rtl,
        .text_align = .center,
        .line_height = 24,
        .max_lines = 2,
        .wrap_mode = .no_wrap,
        .overflow_mode = .ellipsis,
        .tab_width = 2,
        .first_line_indent = 10,
        .paragraph_spacing = 4,
        .word_break_dictionary = &dictionary,
        .hyphenation = .{
            .dictionary = &hyphenation_dictionary,
            .character = 0x2022,
            .max_consecutive_lines = 2,
        },
    };
    const options = style.paragraphOptions(80);

    try std.testing.expectEqual(pipeline_types.TextDirection.rtl, options.direction);
    try std.testing.expectEqual(paragraph_types.TextAlign.center, options.alignment);
    try std.testing.expectEqual(paragraph_types.WrapMode.no_wrap, options.wrap_mode);
    try std.testing.expectApproxEqAbs(@as(f32, 24), options.line_height.?, 0.001);
    try std.testing.expectEqual(@as(usize, 2), options.max_lines.?);
    try std.testing.expect(options.ellipsis);
    try std.testing.expectEqual(@as(usize, 2), options.tab_width);
    try std.testing.expectEqual(&dictionary, options.word_break_dictionary.?);
    try std.testing.expectEqual(
        &hyphenation_dictionary,
        options.hyphenation.dictionary.?,
    );
    try std.testing.expectEqual(
        @as(?u21, 0x2022),
        options.hyphenation.character,
    );
    try std.testing.expectEqual(
        @as(?usize, 2),
        options.hyphenation.max_consecutive_lines,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 10), options.first_line_indent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), options.paragraph_spacing, 0.001);

    const defaults = (ParagraphStyle{}).paragraphOptions(80);
    try std.testing.expectEqual(paragraph_types.TextAlign.start, defaults.alignment);
}
