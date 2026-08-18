//! Range, locale, and paragraph-style model tests.

const std = @import("std");
const style_model = @import("root.zig");
const inline_object = @import("../../layout/inline_object/root.zig");
const paragraph_options = @import("../../layout/paragraph/options.zig");
const paragraph_types = @import("../../layout/types/paragraph.zig");
const pipeline_types = @import("../../shaping/pipeline/types.zig");
const hyphenation = @import("../hyphenation/root.zig");
const segmentation = @import("../segmentation/root.zig");

const FontId = style_model.FontId;
const Language = style_model.Language;
const Locale = style_model.Locale;
const GlyphCluster = style_model.GlyphCluster;
const ParagraphStyle = style_model.ParagraphStyle;
const TextStyle = style_model.TextStyle;

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
    const placement = inline_object.Placement{
        .byte_index = 4,
        .geometry = .{
            .x = 1,
            .y = 2,
            .width = 3,
            .height = 4,
        },
    };
    const line_region = paragraph_options.LineRegion{
        .x = 12,
        .y = 34,
        .width = 56,
    };
    const line_break_policy_range =
        paragraph_options.LineBreakPolicyRange{
            .byte_start = 2,
            .byte_len = 4,
            .word_break = .break_all,
        };
    const tab_stops = [_]paragraph_options.TabStop{
        .{ .position = 24 },
        .{ .position = 72 },
    };
    const style = ParagraphStyle{
        .direction = .rtl,
        .text_align = .center,
        .line_height = 24,
        .max_lines = 2,
        .wrap_mode = .no_wrap,
        .word_break = .keep_all,
        .overflow_wrap = .anywhere,
        .white_space_collapse = .break_spaces,
        .line_break_strategy = .balanced,
        .overflow_mode = .ellipsis,
        .tab_width = 2,
        .tab_stops = &tab_stops,
        .first_line_indent = 10,
        .paragraph_spacing = 4,
        .line_regions = &.{line_region},
        .line_break_policy_ranges = &.{line_break_policy_range},
        .out_of_flow_placements = &.{placement},
        .word_break_dictionary = &dictionary,
        .hyphenation = .{
            .dictionary = &hyphenation_dictionary,
            .character = 0x2022,
            .max_consecutive_lines = 2,
        },
        .punctuation = .{
            .convention = .cns,
            .max_compression_fraction = 0.75,
            .end_hanging_fraction = 0.5,
        },
        .kashida = .{
            .enabled = false,
            .max_insertions_per_line = 3,
        },
        .font_expansion = .{ .enabled = false },
    };
    const options = style.paragraphOptions(80);

    try std.testing.expectEqual(pipeline_types.TextDirection.rtl, options.direction);
    try std.testing.expectEqual(paragraph_types.TextAlign.center, options.alignment);
    try std.testing.expectEqual(paragraph_types.WrapMode.no_wrap, options.wrap_mode);
    try std.testing.expectEqual(
        paragraph_types.WordBreak.keep_all,
        options.word_break,
    );
    try std.testing.expectEqual(
        paragraph_types.OverflowWrap.anywhere,
        options.overflow_wrap,
    );
    try std.testing.expectEqual(
        paragraph_types.WhiteSpaceCollapse.break_spaces,
        options.white_space_collapse,
    );
    try std.testing.expectEqual(
        paragraph_types.LineBreakStrategy.balanced,
        options.line_break_strategy,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 24), options.line_height.?, 0.001);
    try std.testing.expectEqual(@as(usize, 2), options.max_lines.?);
    try std.testing.expect(options.ellipsis);
    try std.testing.expectEqual(@as(usize, 2), options.tab_width);
    try std.testing.expectEqualSlices(
        @TypeOf(tab_stops[0]),
        &tab_stops,
        options.tab_stops,
    );
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
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        options.punctuation.end_hanging_fraction,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.75),
        options.punctuation.max_compression_fraction,
        0.001,
    );
    try std.testing.expectEqual(
        @TypeOf(options.punctuation.convention).cns,
        options.punctuation.convention,
    );
    try std.testing.expect(!options.kashida.enabled);
    try std.testing.expectEqual(
        @as(usize, 3),
        options.kashida.max_insertions_per_line,
    );
    try std.testing.expect(!options.font_expansion.enabled);
    try std.testing.expectApproxEqAbs(@as(f32, 10), options.first_line_indent, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), options.paragraph_spacing, 0.001);
    try std.testing.expectEqual(
        placement,
        options.out_of_flow_placements[0],
    );
    try std.testing.expectEqual(line_region, options.line_regions[0]);
    try std.testing.expectEqual(
        line_break_policy_range,
        options.line_break_policy_ranges[0],
    );

    const defaults = (ParagraphStyle{}).paragraphOptions(80);
    try std.testing.expectEqual(paragraph_types.TextAlign.start, defaults.alignment);
}

test "vertical alignment belongs to inline text style" {
    const text_style = TextStyle{
        .vertical_align = .middle,
        .wrap_mode = .no_wrap,
        .word_break = .keep_all,
        .overflow_wrap = .anywhere,
    };
    try std.testing.expectEqual(
        paragraph_types.VerticalAlign.middle,
        text_style.vertical_align,
    );
    try std.testing.expectEqual(
        paragraph_types.WrapMode.no_wrap,
        text_style.wrap_mode.?,
    );
    try std.testing.expectEqual(
        paragraph_types.WordBreak.keep_all,
        text_style.word_break.?,
    );
    try std.testing.expectEqual(
        paragraph_types.OverflowWrap.anywhere,
        text_style.overflow_wrap.?,
    );
    try std.testing.expect(!@hasField(ParagraphStyle, "vertical_align"));
}
