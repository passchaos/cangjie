//! Source population for proved homogeneous three-byte UTF-8 runs.
//!
//! The caller owns UTF-8 validation and the script/mode proof. This module
//! deliberately accepts only ranges whose generic source behavior is one
//! identity record per scalar.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const cache_mod = @import("../../context/cache/root.zig");
const GlyphIndexCache = cache_mod.GlyphIndexCache;
const scratch_mod = @import("../../context/scratch.zig");
const source_buffer = @import("buffer.zig");
const support = @import("support.zig");
const unicode = @import("../../../unicode.zig");

pub fn supportsJapaneseScript(script: unicode.Script) bool {
    return switch (script) {
        .han, .hiragana, .katakana => true,
        else => false,
    };
}

pub fn isJapaneseText(text: []const u8) bool {
    if (text.len == 0 or text.len % 3 != 0) return false;
    var index: usize = 0;
    while (index < text.len) : (index += 3) {
        const first = text[index];
        const second = text[index + 1];
        const third = text[index + 2];
        if (first < 0xe3 or first > 0xe9 or
            second & 0xc0 != 0x80 or
            third & 0xc0 != 0x80)
        {
            return false;
        }
        const codepoint = decode(text, index);
        // Public entry points have already validated UTF-8. Restrict the proof
        // to Japanese text blocks whose scalars have identity presentation and
        // independent default clusters. U+302A..U+302F and
        // U+3099..U+309A are combining marks; U+303E is a variation selector.
        if (!isJapaneseCodepoint(codepoint)) return false;
    }
    return true;
}

fn isJapaneseCodepoint(codepoint: u21) bool {
    return (codepoint >= 0x3000 and codepoint <= 0x3029) or
        (codepoint >= 0x3030 and codepoint <= 0x303d) or
        codepoint == 0x303f or
        (codepoint >= 0x3041 and codepoint <= 0x3098) or
        (codepoint >= 0x309b and codepoint <= 0x30ff) or
        (codepoint >= 0x3400 and codepoint <= 0x4dbf) or
        (codepoint >= 0x4e00 and codepoint <= 0x9fff);
}

pub fn populate(
    font: *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    scratch: *scratch_mod.ShapeScratch,
    text: []const u8,
    cluster_base: usize,
    comptime ideographic_space_fallback: bool,
) !void {
    std.debug.assert(text.len != 0 and text.len % 3 == 0);
    var byte_index: usize = 0;
    while (byte_index < text.len) : (byte_index += 3) {
        const codepoint = decode(text, byte_index);
        const glyph_id = if (ideographic_space_fallback and
            codepoint == 0x3000)
            try support.fallbackGlyphIndex(
                font,
                glyph_index_cache,
                codepoint,
            )
        else
            try support.glyphIndex(font, glyph_index_cache, codepoint);
        // Append only after the fallible cmap lookup succeeds. On OOM, every
        // glyph-parallel list therefore remains synchronized at the completed
        // prefix, matching the generic source population contract.
        source_buffer.appendIdentity(
            scratch,
            glyph_id,
            codepoint,
            cluster_base + byte_index,
            cluster_base + byte_index + 3,
        );
    }
}

inline fn decode(text: []const u8, index: usize) u21 {
    return (@as(u21, text[index] & 0x0f) << 12) |
        (@as(u21, text[index + 1] & 0x3f) << 6) |
        @as(u21, text[index + 2] & 0x3f);
}

pub const testing = struct {
    /// Test-only bypass used to compare this specialization directly with the
    /// generic source loop instead of relying on eligibility side effects.
    pub fn populateForced(
        allocator: std.mem.Allocator,
        font: *const Font,
        glyph_index_cache: ?*GlyphIndexCache,
        scratch: *scratch_mod.ShapeScratch,
        text: []const u8,
        cluster_base: usize,
    ) !void {
        std.debug.assert(isJapaneseText(text));
        try scratch.glyph_ids.ensureUnusedCapacity(allocator, text.len);
        try scratch.codepoints.ensureUnusedCapacity(allocator, text.len);
        try scratch.clusters.ensureUnusedCapacity(allocator, text.len);
        try scratch.source_ends.ensureUnusedCapacity(allocator, text.len);
        try scratch.glyph_source_indices.ensureUnusedCapacity(
            allocator,
            text.len,
        );
        try scratch.glyph_cluster_indices.ensureUnusedCapacity(
            allocator,
            text.len,
        );
        try scratch.glyph_substituted.ensureUnusedCapacity(allocator, text.len);
        try scratch.ligature_components.infos.ensureUnusedCapacity(
            allocator,
            text.len,
        );
        return populate(
            font,
            glyph_index_cache,
            scratch,
            text,
            cluster_base,
            true,
        );
    }
};

test "Japanese three-byte proof excludes generic-source behavior" {
    try std.testing.expect(isJapaneseText("日本語かなカナ、。「」々　"));
    try std.testing.expect(isJapaneseText("㐀龿"));

    try std.testing.expect(!isJapaneseText("日本語\nかな"));
    try std.testing.expect(!isJapaneseText("漢字A"));
    try std.testing.expect(!isJapaneseText("一\u{e0100}"));
    try std.testing.expect(!isJapaneseText("一\u{fe0f}"));
    try std.testing.expect(!isJapaneseText("一\u{200d}"));
    try std.testing.expect(!isJapaneseText("一\u{202e}"));
    try std.testing.expect(!isJapaneseText("一\u{3099}"));
    try std.testing.expect(!isJapaneseText("一\u{303e}"));
    try std.testing.expect(!isJapaneseText("一\u{20000}"));
    try std.testing.expect(!isJapaneseText(""));
    // Invalid UTF-8 is normally rejected before source population. Retaining
    // these structural checks prevents direct/internal callers from admitting
    // malformed triples if that outer boundary is ever refactored.
    try std.testing.expect(!isJapaneseText("\xe4\x00\x80"));
    try std.testing.expect(!isJapaneseText("\xe4\xb8\x00"));
}

test "Japanese three-byte proof exhaustively admits only zero modified classes" {
    for (0x3000..0xa000) |raw_codepoint| {
        const codepoint: u21 = @intCast(raw_codepoint);
        var encoded: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(codepoint, &encoded);
        const admitted = isJapaneseText(encoded[0..len]);
        // Compare the byte-level run predicate with its scalar helper, then
        // validate the helper against the independent generated Unicode data.
        const expected = isJapaneseCodepoint(codepoint);
        try std.testing.expectEqual(expected, admitted);
        if (admitted) {
            try std.testing.expectEqual(
                @as(u8, 0),
                unicode.modifiedCombiningClassForShaping(codepoint),
            );
        }
    }
}
