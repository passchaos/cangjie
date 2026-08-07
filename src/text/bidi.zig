const std = @import("std");

const font_mod = @import("../font.zig");
const unicode = @import("../unicode.zig");

const Font = font_mod.Font;

pub const VisualOrderInputKind = enum {
    empty,
    pure_rtl,
    mixed,
};

/// Classify a shaped run before paying for the general bidi map path.
///
/// Paragraphs made only from RTL text plus neutral spacing/punctuation are the
/// common Arabic benchmark/UI case.  Their visual order is just the reverse of
/// the already shaped logical glyph clusters; numbers, LTR words, or bracket
/// mirroring still require the full unicode.BidiMap path.
pub fn visualOrderInputKind(text: []const u8, direction_is_rtl: bool) VisualOrderInputKind {
    if (text.len == 0) return .empty;
    if (!direction_is_rtl) return .mixed;

    var saw_strong_rtl = false;
    var it = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (it.nextCodepoint()) |codepoint| {
        if (unicode.mirroredCodepoint(codepoint) != codepoint) return .mixed;
        switch (unicode.bidiClassForCodepoint(codepoint)) {
            .rtl => saw_strong_rtl = true,
            .neutral => {},
            // Numbers and LTR spans have their own direction runs in the
            // project's bidi model; preserving their visual order needs the
            // complete per-codepoint map.
            .number, .ltr => return .mixed,
        }
    }
    return if (saw_strong_rtl) .pure_rtl else .empty;
}

pub fn applyPureRtlVisualOrder(glyphs: anytype, font: ?*const Font) void {
    const Glyph = @TypeOf(glyphs.items[0]);
    if (glyphs.items.len > 1) {
        // The general BidiMap path iterates RTL glyph clusters from the end of
        // the run and walks glyphs inside each cluster backwards.  For a
        // paragraph made only of RTL and neutral characters this is equivalent
        // to reversing the already-shaped glyph stream in place.
        std.mem.reverse(Glyph, glyphs.items);
    }
    if (font) |face| {
        for (glyphs.items) |*glyph| {
            const mirrored = unicode.mirroredCodepoint(glyph.codepoint);
            if (mirrored == glyph.codepoint) continue;
            const mirrored_glyph = face.glyphIndex(mirrored) catch continue;
            if (mirrored_glyph == 0) continue;
            glyph.codepoint = mirrored;
            glyph.glyph_id = mirrored_glyph;
        }
    }
}

test "pure RTL input classification keeps mixed bidi on the general path" {
    try std.testing.expectEqual(VisualOrderInputKind.empty, visualOrderInputKind("", true));
    try std.testing.expectEqual(VisualOrderInputKind.empty, visualOrderInputKind("   ", true));
    try std.testing.expectEqual(VisualOrderInputKind.pure_rtl, visualOrderInputKind("سلام، دنیا", true));
    try std.testing.expectEqual(VisualOrderInputKind.mixed, visualOrderInputKind("سلام 12", true));
    try std.testing.expectEqual(VisualOrderInputKind.mixed, visualOrderInputKind("(سلام)", true));
    try std.testing.expectEqual(VisualOrderInputKind.mixed, visualOrderInputKind("سلام A", true));
    try std.testing.expectEqual(VisualOrderInputKind.mixed, visualOrderInputKind("سلام", false));
}

test "pure RTL visual order reverses the shaped glyph stream in place" {
    const DummyGlyph = struct {
        glyph_id: u16,
        codepoint: u21,
        cluster: usize,
    };

    var glyphs = std.ArrayList(DummyGlyph).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{
        .{ .glyph_id = 1, .codepoint = 0x0633, .cluster = 0 },
        .{ .glyph_id = 2, .codepoint = 0x0644, .cluster = 2 },
        .{ .glyph_id = 3, .codepoint = 0x0627, .cluster = 4 },
        .{ .glyph_id = 4, .codepoint = 0x0645, .cluster = 6 },
    });

    applyPureRtlVisualOrder(&glyphs, null);
    try std.testing.expectEqualSlices(u16, &.{ 4, 3, 2, 1 }, &.{
        glyphs.items[0].glyph_id,
        glyphs.items[1].glyph_id,
        glyphs.items[2].glyph_id,
        glyphs.items[3].glyph_id,
    });
}
