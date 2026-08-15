const std = @import("std");

const font_mod = @import("../font.zig");
const unicode = @import("../unicode.zig");

const Font = font_mod.Font;
const ascii_classes = buildAsciiClasses();

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
    var cursor: usize = 0;
    while (cursor < text.len) {
        const first = text[cursor];
        const codepoint: u21 = if (first < 0x80) ascii: {
            cursor += 1;
            break :ascii first;
        } else decoded: {
            break :decoded decodeValid(text, &cursor);
        };
        const class = if (first < 0x80)
            ascii_classes[first]
        else
            unicode.exactBidiClassForCodepoint(codepoint);
        switch (class) {
            .r, .al => saw_strong_rtl = true,
            // Weak and neutral classes resolve from the surrounding paragraph
            // direction. Only genuine LTR/number content or explicit controls
            // require the complete level resolver for this fast-path proof.
            .l, .en, .an => return .mixed,
            .lre, .lro, .rle, .rlo, .pdf, .lri, .rli, .fsi, .pdi => return .mixed,
            else => {},
        }
    }
    return if (saw_strong_rtl) .pure_rtl else .empty;
}

inline fn decodeValid(text: []const u8, cursor: *usize) u21 {
    const start = cursor.*;
    const first = text[start];
    const second = text[start + 1];
    if (first < 0xe0) {
        cursor.* = start + 2;
        return (@as(u21, first & 0x1f) << 6) |
            @as(u21, second & 0x3f);
    }
    const third = text[start + 2];
    if (first < 0xf0) {
        cursor.* = start + 3;
        return (@as(u21, first & 0x0f) << 12) |
            (@as(u21, second & 0x3f) << 6) |
            @as(u21, third & 0x3f);
    }
    const fourth = text[start + 3];
    cursor.* = start + 4;
    return (@as(u21, first & 0x07) << 18) |
        (@as(u21, second & 0x3f) << 12) |
        (@as(u21, third & 0x3f) << 6) |
        @as(u21, fourth & 0x3f);
}

fn buildAsciiClasses() [128]unicode.ExactBidiClass {
    var result: [128]unicode.ExactBidiClass = undefined;
    for (&result, 0..) |*value, codepoint| {
        value.* = unicode.exactBidiClassForCodepoint(@intCast(codepoint));
    }
    return result;
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
        // Most Arabic/Hebrew runs contain no mirrored scalar. Avoid a binary
        // search in the complete Unicode mirror map for every glyph when a
        // cheap range proof excludes every known mirrored character.
        for (glyphs.items) |*glyph| {
            if (!mayHaveBidiMirror(glyph.codepoint)) continue;
            const mirrored = unicode.mirroredCodepoint(glyph.codepoint);
            if (mirrored == glyph.codepoint) continue;
            const mirrored_glyph = face.glyphIndex(mirrored) catch continue;
            if (mirrored_glyph == 0) continue;
            glyph.codepoint = mirrored;
            glyph.glyph_id = mirrored_glyph;
        }
    }
}

fn mayHaveBidiMirror(codepoint: u21) bool {
    if (codepoint < 0x28) return false;
    if (codepoint <= 0x7d) {
        return codepoint == '(' or codepoint == ')' or
            codepoint == '<' or codepoint == '>' or
            codepoint == '[' or codepoint == ']' or
            codepoint == '{' or codepoint == '}';
    }
    // Unicode 17 BidiMirroring contains no entry in the high-traffic
    // Hebrew/Arabic blocks. Remaining mappings occupy punctuation,
    // mathematical, CJK, presentation-form, and fullwidth ranges.
    if (codepoint < 0x00ab) return false;
    if (codepoint > 0x00bb and codepoint < 0x0f3a) return false;
    if (codepoint > 0x0f3d and codepoint < 0x169b) return false;
    if (codepoint > 0x169c and codepoint < 0x2039) return false;
    return codepoint <= 0xff63;
}

test "pure RTL input classification keeps mixed bidi on the general path" {
    try std.testing.expectEqual(VisualOrderInputKind.empty, visualOrderInputKind("", true));
    try std.testing.expectEqual(VisualOrderInputKind.empty, visualOrderInputKind("   ", true));
    try std.testing.expectEqual(VisualOrderInputKind.pure_rtl, visualOrderInputKind("سلام، دنیا", true));
    try std.testing.expectEqual(VisualOrderInputKind.mixed, visualOrderInputKind("سلام 12", true));
    // The pure-RTL path mirrors glyphs after reversal, so paired punctuation
    // alone does not require the allocating general map.
    try std.testing.expectEqual(VisualOrderInputKind.pure_rtl, visualOrderInputKind("(سلام)", true));
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
