const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;

const Kind = enum {
    em,
    em_2,
    em_3,
    em_4,
    em_5,
    em_6,
    em_16,
    four_em_18,
    space,
    figure,
    punctuation,
    narrow,
};

pub fn glyphForCodepoint(font: *const Font, codepoint: u21) !?GlyphId {
    if (kindForCodepoint(codepoint) == null) return null;
    if (try font.glyphIndex(codepoint) != 0) return null;
    const space_glyph = try font.glyphIndex(' ');
    return if (space_glyph != 0) space_glyph else null;
}

pub fn advanceWidth(font: *const Font, codepoint: u21, glyph_id: GlyphId, current_advance: u16) !?i32 {
    const kind = kindForCodepoint(codepoint) orelse return null;
    if (try font.glyphIndex(codepoint) != 0) return null;
    const space_glyph = try font.glyphIndex(' ');
    if (space_glyph == 0 or glyph_id != space_glyph) return null;

    const upem: i32 = @intCast(font.units_per_em);
    return switch (kind) {
        .space => @intCast(current_advance),
        .em => upem,
        .em_2 => divRounded(upem, 2),
        .em_3 => divRounded(upem, 3),
        .em_4 => divRounded(upem, 4),
        .em_5 => divRounded(upem, 5),
        .em_6 => divRounded(upem, 6),
        .em_16 => divRounded(upem, 16),
        .four_em_18 => @intCast(@divTrunc(@as(i64, upem) * 4, 18)),
        .figure => try figureAdvance(font) orelse @intCast(current_advance),
        .punctuation => try punctuationAdvance(font) orelse @intCast(current_advance),
        .narrow => @divTrunc(@as(i32, @intCast(current_advance)), 2),
    };
}

pub fn advanceHeight(font: *const Font, codepoint: u21, glyph_id: GlyphId, default_advance: i32) !?i32 {
    const kind = kindForCodepoint(codepoint) orelse return null;
    const space_glyph = try font.glyphIndex(' ');
    if (space_glyph == 0 or glyph_id != space_glyph) return null;
    if (kind != .space and try font.glyphIndex(codepoint) != 0) return null;

    const upem: i32 = @intCast(font.units_per_em);
    const length = switch (kind) {
        .space => default_advance,
        .em => upem,
        .em_2 => divRounded(upem, 2),
        .em_3 => divRounded(upem, 3),
        .em_4 => divRounded(upem, 4),
        .em_5 => divRounded(upem, 5),
        .em_6 => divRounded(upem, 6),
        .em_16 => divRounded(upem, 16),
        .four_em_18 => @as(i32, @intCast(@divTrunc(@as(i64, upem) * 4, 18))),
        .figure => default_advance,
        .punctuation => default_advance,
        .narrow => @divTrunc(default_advance, 2),
    };
    return -length;
}

pub fn mayNeedHorizontalAdvanceFallback(codepoint: u21) bool {
    return switch (kindForCodepoint(codepoint) orelse return false) {
        // U+0020 and U+00A0 fallback returns the current space advance, so the
        // normal glyph metrics path is already equivalent in horizontal text.
        .space => false,
        else => true,
    };
}

pub fn mayNeedVerticalAdvanceFallback(codepoint: u21) bool {
    return kindForCodepoint(codepoint) != null;
}

fn kindForCodepoint(codepoint: u21) ?Kind {
    return switch (codepoint) {
        0x0020, 0x00a0 => .space,
        0x2000, 0x2002 => .em_2,
        0x2001, 0x2003, 0x3000 => .em,
        0x2004 => .em_3,
        0x2005 => .em_4,
        0x2006 => .em_6,
        0x2007 => .figure,
        0x2008 => .punctuation,
        0x2009 => .em_5,
        0x200a => .em_16,
        0x202f => .narrow,
        0x205f => .four_em_18,
        else => null,
    };
}

fn divRounded(value: i32, divisor: i32) i32 {
    return @divTrunc(value + @divTrunc(divisor, 2), divisor);
}

fn figureAdvance(font: *const Font) !?i32 {
    var codepoint: u21 = '0';
    while (codepoint <= '9') : (codepoint += 1) {
        const glyph_id = try font.glyphIndex(codepoint);
        if (glyph_id == 0) continue;
        const metrics = try font.horizontalMetrics(glyph_id);
        return @intCast(metrics.advance_width);
    }
    return null;
}

fn punctuationAdvance(font: *const Font) !?i32 {
    const period = try font.glyphIndex('.');
    if (period != 0) {
        const metrics = try font.horizontalMetrics(period);
        return @intCast(metrics.advance_width);
    }
    const comma = try font.glyphIndex(',');
    if (comma != 0) {
        const metrics = try font.horizontalMetrics(comma);
        return @intCast(metrics.advance_width);
    }
    return null;
}
