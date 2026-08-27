//! Styled horizontal bidi integration coverage.

const std = @import("std");
const support = @import("../support.zig");
const test_font = @import("../../../test_font.zig");

test "pure RTL styled lines keep glyph metadata parallel" {
    const allocator = std.testing.allocator;
    const text = "אב אב אב";
    const bytes = try test_font.buildLastResortCmapTtfWithKern(
        allocator,
        false,
    );
    defer allocator.free(bytes);
    var font = try support.Font.parse(allocator, bytes);
    defer font.deinit();
    var buffer = support.LayoutBuffer.init(allocator);
    defer buffer.deinit();
    var styled = support.StyledParagraphBuffer.init(allocator);
    defer styled.deinit();
    const spans = [_]support.StyledParagraphSpan{.{
        .byte_start = 0,
        .byte_len = text.len,
        .style_index = 7,
        .font_size = 20,
        .letter_spacing = 1,
        .word_spacing = 3,
    }};

    const layout = try support.TextShaper.layoutStyledParagraphUtf8(
        support.FontCascade.init(&.{&font}),
        &buffer,
        &styled,
        text,
        20,
        &spans,
        .{
            .max_width = 48,
            .direction = .rtl,
        },
    );
    try std.testing.expect(layout.lines.len >= 2);
    try std.testing.expectEqual(layout.glyphs.len, styled.glyphMetadata().len);
    for (layout.glyphs, styled.glyphMetadata()) |glyph, metadata| {
        try std.testing.expectEqual(@as(u32, 7), metadata.style_index);
        try std.testing.expectEqual(
            // CSS/Parley word spacing is additive to letter spacing. A space
            // therefore receives both values rather than replacing the
            // ordinary inter-character contribution.
            @as(f32, if (glyph.codepoint == ' ') 4 else 1),
            metadata.layout_spacing,
        );
    }
    try std.testing.expectEqual(@as(usize, 1), layout.runs.len);
    var visible_glyphs: usize = 0;
    for (layout.lines) |line| {
        // Wrapped spaces are retained outside the visible ranges. The pure
        // RTL fast path must compact later lines across those logical gaps in
        // exactly the same way as the general bidi transaction.
        try std.testing.expectEqual(visible_glyphs, line.glyph_start);
        visible_glyphs += line.glyph_len;
        try std.testing.expectEqual(@as(usize, 0), line.run_start);
        try std.testing.expectEqual(@as(usize, 1), line.run_len);
        const glyphs = line.glyphs(layout);
        for (glyphs[1..], glyphs[0 .. glyphs.len - 1]) |current, previous| {
            try std.testing.expect(current.cluster <= previous.cluster);
        }
    }
    try std.testing.expect(visible_glyphs < layout.glyphs.len);
}
