const std = @import("std");

const context_mod = @import("../../shaping/context/root.zig");
const dictionary_mod = @import("../../text/segmentation/root.zig");
const font_mod = @import("../../font.zig");
const layout = @import("../../layout.zig");
const test_font = @import("../../test_font.zig");

const thai_text = "กขคง";

fn expectDictionaryFirstLine(paragraph: layout.ParagraphLayout) !void {
    try std.testing.expectEqual(@as(usize, 3), paragraph.lines.len);
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 0), paragraph.lines[0].byte_start);
    try std.testing.expectEqual("ก".len, paragraph.lines[0].byte_len);
}

test "dictionary opportunities reach one-shot retained and styled paragraphs" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);

    const dictionary = try dictionary_mod.WordBreakDictionary.init(
        allocator,
        .thai,
        &.{ "ก", "ขคง" },
    );
    defer dictionary.deinit();
    const context = try context_mod.TextContext.init(allocator, .{});
    defer context.deinit();

    // UAX #14 treats this SA run as one alphabetic fragment by default. Its
    // emergency fallback fills two glyphs, whereas the dictionary makes the
    // one-glyph word the preferred opportunity before overflow.
    const default_layout = try context.layoutParagraph(
        cascade,
        thai_text,
        20,
        .{ .max_width = 35 },
    );
    try std.testing.expectEqual(@as(usize, 2), default_layout.lines[0].glyph_len);

    const one_shot = try context.layoutParagraph(
        cascade,
        thai_text,
        20,
        .{
            .max_width = 35,
            .word_break_dictionary = dictionary,
        },
    );
    try expectDictionaryFirstLine(one_shot);

    var shaped = try context.shapeParagraph(
        cascade,
        thai_text,
        20,
        .{
            .max_width = 100,
            .word_break_dictionary = dictionary,
        },
    );
    defer shaped.deinit();
    var reflow = layout.ReflowBuffer.init(allocator);
    defer reflow.deinit();
    const retained = try shaped.layout(&reflow, .{
        .max_width = 35,
        .word_break_dictionary = dictionary,
    });
    try expectDictionaryFirstLine(retained);
    try std.testing.expectError(
        error.ParagraphShapingOptionsChanged,
        shaped.layout(&reflow, .{ .max_width = 35 }),
    );

    const spans = [_]layout.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = thai_text.len,
        .style_index = 4,
        .font_size = 20,
    }};
    const styled = try context.layoutStyledParagraph(
        cascade,
        thai_text,
        20,
        &spans,
        .{
            .max_width = 35,
            .word_break_dictionary = dictionary,
        },
    );
    try expectDictionaryFirstLine(styled.layout);
    try std.testing.expectEqual(
        styled.layout.glyphs.len,
        styled.glyph_metadata.len,
    );
}

test "dictionary opportunities cannot bypass shaped boundary safety" {
    const allocator = std.testing.allocator;
    // This fixture maps every scalar to one glyph and kerns that pair. Every
    // interior source boundary is consequently unsafe to reuse without
    // reshaping, including the otherwise valid dictionary word boundary.
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        true,
    );
    defer allocator.free(bytes);
    var font = try font_mod.Font.parse(allocator, bytes);
    defer font.deinit();
    const fonts = [_]*const font_mod.Font{&font};
    const cascade = layout.FontCascade.init(&fonts);
    const dictionary = try dictionary_mod.WordBreakDictionary.init(
        allocator,
        .thai,
        &.{ "ก", "ขคง" },
    );
    defer dictionary.deinit();
    const context = try context_mod.TextContext.init(allocator, .{});
    defer context.deinit();

    const paragraph = try context.layoutParagraph(
        cascade,
        thai_text,
        20,
        .{
            .max_width = 20,
            .word_break_dictionary = dictionary,
        },
    );
    try std.testing.expectEqual(@as(usize, 1), paragraph.lines.len);
    try std.testing.expectEqual(
        paragraph.glyphs.len,
        paragraph.lines[0].glyph_len,
    );
}
