//! UTF-8 decoding, cmap mapping, and initial shaping-cluster ownership.
//!
//! This stage creates every glyph-parallel source sidecar consumed by GSUB.
//! Later stages may reorder or substitute these arrays, but must preserve their
//! cardinality and source identity invariants.

const std = @import("std");

const Font = @import("../../../font.zig").Font;
const GlyphId = @import("../../../glyph.zig").GlyphId;
const cache_mod = @import("../../context/cache/root.zig");
const GlyphIndexCache = cache_mod.GlyphIndexCache;
const scratch_mod = @import("../../context/scratch.zig");
const source_buffer = @import("buffer.zig");
const support = @import("support.zig");
const thai_lao = @import("thai_lao.zig");
const unicode = @import("../../../unicode.zig");

pub const Result = struct {
    has_default_ignorable: bool = false,
    run_has_decimal_number: bool = false,
    run_has_letter: bool = false,
    /// The source scan already decodes every scalar. Preserve the fact that no
    /// scalar can trigger bidi visual reordering so the top-level shaper does
    /// not decode and classify the same non-ASCII run a second time.
    may_need_bidi_reorder: bool = false,
    default_ignorable_invisible_glyph_id: ?GlyphId = null,
};

pub fn populate(
    allocator: std.mem.Allocator,
    font: *const Font,
    glyph_index_cache: ?*GlyphIndexCache,
    scratch: *scratch_mod.ShapeScratch,
    text: []const u8,
    cluster_base: usize,
    all_ascii: bool,
    options: anytype,
) !Result {
    scratch.clear();
    const glyph_ids = &scratch.glyph_ids;
    const codepoints = &scratch.codepoints;
    const clusters = &scratch.clusters;
    const source_ends = &scratch.source_ends;
    const glyph_source_indices = &scratch.glyph_source_indices;
    const glyph_cluster_indices = &scratch.glyph_cluster_indices;
    const glyph_substituted = &scratch.glyph_substituted;
    const ligature_components = &scratch.ligature_components;

    // Valid UTF-8 has at most one retained source per input byte. Reserve every
    // parallel array once so cmap does not repeat capacity checks per scalar.
    try glyph_ids.ensureUnusedCapacity(allocator, text.len);
    try codepoints.ensureUnusedCapacity(allocator, text.len);
    try clusters.ensureUnusedCapacity(allocator, text.len);
    try source_ends.ensureUnusedCapacity(allocator, text.len);
    try glyph_source_indices.ensureUnusedCapacity(allocator, text.len);
    try glyph_cluster_indices.ensureUnusedCapacity(allocator, text.len);
    try glyph_substituted.ensureUnusedCapacity(allocator, text.len);
    try ligature_components.infos.ensureUnusedCapacity(allocator, text.len);

    var result = Result{};
    const track_rtl_numeric_guard = options.needsRtlNumericDirectionGuard();
    if (all_ascii and options.direction == .ltr) {
        // The caller already validated and classified this run. One byte is one
        // source scalar and no variation/default-ignorable handling is needed.
        for (text, 0..) |byte, cluster| {
            const glyph_id = try support.glyphIndex(font, glyph_index_cache, byte);
            if (track_rtl_numeric_guard) {
                result.run_has_decimal_number =
                    result.run_has_decimal_number or
                    support.isDecimalNumber(byte);
                result.run_has_letter =
                    result.run_has_letter or support.isLetter(byte);
            }
            source_buffer.appendIdentity(
                scratch,
                glyph_id,
                byte,
                cluster_base + cluster,
                cluster_base + cluster + 1,
            );
        }
        return result;
    }
    const track_bidi_reorder = options.reorder_bidi and
        !options.writing_mode.isVertical() and
        options.direction != .rtl;
    const common_ltr_script = commonLtrScriptRange(options.script);

    // Public shaping entry points validate the complete UTF-8 request before
    // any source buffer is mutated. Decode directly here so the hot loop does
    // not construct a temporary slice and re-enter the checked std decoder for
    // each scalar. Continuation-byte and range validity are therefore trusted
    // exactly like `Utf8Iterator.nextCodepoint()` after that proof.
    var source_byte_index: usize = 0;
    while (source_byte_index < text.len) {
        const local_cluster = source_byte_index;
        const decoded = decodeValidatedUtf8(text, source_byte_index);
        const codepoint = decoded.codepoint;
        source_byte_index += decoded.byte_len;
        if (track_rtl_numeric_guard) {
            result.run_has_decimal_number =
                result.run_has_decimal_number or
                support.isDecimalNumber(codepoint);
            result.run_has_letter =
                result.run_has_letter or support.isLetter(codepoint);
        }
        if (track_bidi_reorder and
            !result.may_need_bidi_reorder and
            !scalarInRange(codepoint, common_ltr_script))
        {
            result.may_need_bidi_reorder =
                unicode.mayNeedBidiVisualReorder(codepoint);
        }

        if (unicode.isVariationSelector(codepoint)) {
            if (glyph_ids.items.len == 0) continue;
            if (options.script_tag != .mym2) {
                if (try font.variationGlyphIndex(
                    codepoints.items[codepoints.items.len - 1],
                    codepoint,
                )) |variant_glyph| {
                    glyph_ids.items[glyph_ids.items.len - 1] = variant_glyph;
                    source_ends.items[source_ends.items.len - 1] =
                        cluster_base + source_byte_index;
                    continue;
                }
            }
            // Myanmar's syllable grammar retains VS as an explicit source.
            const selector_glyph =
                try support.glyphIndex(font, glyph_index_cache, codepoint);
            result.has_default_ignorable = true;
            source_ends.items[source_ends.items.len - 1] =
                cluster_base + source_byte_index;
            const source_cluster = if ((options.cluster_level == null or
                options.cluster_level.?.groupsGraphemes()) and
                clusters.items.len != 0)
                clusters.items[clusters.items.len - 1] - cluster_base
            else
                local_cluster;
            source_buffer.append(
                scratch,
                selector_glyph,
                codepoint,
                cluster_base + source_cluster,
                cluster_base + source_byte_index,
                if (source_cluster != local_cluster and
                    glyph_cluster_indices.items.len != 0)
                    glyph_cluster_indices.items[
                        glyph_cluster_indices.items.len - 1
                    ]
                else
                    glyph_cluster_indices.items.len,
            );
            continue;
        }

        result.has_default_ignorable =
            result.has_default_ignorable or
            unicode.isDefaultIgnorableForShaping(codepoint);
        if (thai_lao.usesPreprocess(options.script_tag) and thai_lao.isSaraAm(codepoint)) {
            try thai_lao.appendSaraAm(
                font,
                glyph_index_cache,
                scratch,
                codepoint,
                local_cluster,
                cluster_base,
                source_byte_index,
                options.cluster_level,
            );
            continue;
        }

        // Canonical Arabic composition has only six possible starters. Keep
        // the common source loop out of the font-aware lookahead helper; its
        // internal guard remains authoritative for direct callers.
        const composition = if (support.canStartArabicComposition(codepoint))
            try support.arabicCompositionForFontAt(
                font,
                glyph_index_cache,
                codepoint,
                text,
                source_byte_index,
            )
        else
            null;
        const local_source_end =
            if (composition) |value| value.byte_end else source_byte_index;
        const normalized_codepoint =
            if (composition) |value| value.codepoint else codepoint;
        const glyph_id = if (composition) |value| glyph: {
            source_byte_index = value.byte_end;
            break :glyph value.glyph_id;
        } else glyph: {
            const presented = try support.presentationCodepoint(
                font,
                glyph_index_cache,
                codepoint,
                options,
            );
            break :glyph try support.fallbackGlyphIndex(
                font,
                glyph_index_cache,
                presented,
            );
        };

        const explicit_cluster_level = options.cluster_level;
        const inherit_grapheme_cluster = if (explicit_cluster_level) |level|
            level.groupsGraphemes()
        else
            true;
        var leading_default_ignorable_cluster = false;
        if (codepoints.items.len == 1 and clusters.items.len == 1) {
            leading_default_ignorable_cluster =
                support.inheritsLeadingDefaultIgnorableCluster(
                    codepoints.items,
                    clusters.items,
                    try support.resolveInvisibleGlyph(
                        font,
                        glyph_index_cache,
                        &result.default_ignorable_invisible_glyph_id,
                    ),
                );
        }
        var previous_zwnj_cluster = false;
        if (options.direction == .rtl and
            codepoints.items.len != 0 and
            codepoints.items[codepoints.items.len - 1] == 0x200c)
        {
            previous_zwnj_cluster = support.inheritsPreviousZwnjCluster(
                true,
                codepoints.items,
                try support.resolveInvisibleGlyph(
                    font,
                    glyph_index_cache,
                    &result.default_ignorable_invisible_glyph_id,
                ),
            );
        }
        const inherits_previous_cluster =
            leading_default_ignorable_cluster or
            codepoint == 0x200d or
            (explicit_cluster_level != null and
                unicode.isUnicodeMarkCodepoint(codepoint)) or
            (options.script_tag == .tibt and support.isTibetanExtender(codepoint)) or
            (thai_lao.usesPreprocess(options.script_tag) and
                thai_lao.isClusterExtender(codepoint)) or
            previous_zwnj_cluster or
            (options.direction == .rtl and
                unicode.inheritsPreviousClusterInRtlShaping(codepoint));
        const source_cluster = if (inherit_grapheme_cluster and
            inherits_previous_cluster and clusters.items.len != 0)
            clusters.items[clusters.items.len - 1] - cluster_base
        else
            local_cluster;
        source_buffer.append(
            scratch,
            glyph_id,
            normalized_codepoint,
            cluster_base + source_cluster,
            cluster_base + local_source_end,
            if (source_cluster != local_cluster and
                glyph_cluster_indices.items.len != 0)
                glyph_cluster_indices.items[
                    glyph_cluster_indices.items.len - 1
                ]
            else
                glyph_cluster_indices.items.len,
        );
    }
    return result;
}

const ScriptRange = struct {
    start: u21,
    len: u21,
};

fn commonLtrScriptRange(script: unicode.Script) ?ScriptRange {
    return switch (script) {
        .devanagari => .{ .start = 0x0900, .len = 0x80 },
        else => null,
    };
}

inline fn scalarInRange(codepoint: u21, range: ?ScriptRange) bool {
    const active = range orelse return false;
    return codepoint -% active.start < active.len;
}

const DecodedUtf8 = struct {
    codepoint: u21,
    byte_len: u3,
};

/// Decode one scalar after the public request boundary has validated the
/// complete UTF-8 slice. Keeping this helper out of line avoids expanding the
/// already-large source-population loop while still omitting redundant scalar
/// validation.
noinline fn decodeValidatedUtf8(text: []const u8, index: usize) DecodedUtf8 {
    const first = text[index];
    if (first < 0x80) return .{ .codepoint = first, .byte_len = 1 };
    if (first < 0xe0) {
        return .{
            .codepoint = (@as(u21, first & 0x1f) << 6) |
                @as(u21, text[index + 1] & 0x3f),
            .byte_len = 2,
        };
    }
    if (first < 0xf0) {
        return .{
            .codepoint = (@as(u21, first & 0x0f) << 12) |
                (@as(u21, text[index + 1] & 0x3f) << 6) |
                @as(u21, text[index + 2] & 0x3f),
            .byte_len = 3,
        };
    }
    return .{
        .codepoint = (@as(u21, first & 0x07) << 18) |
            (@as(u21, text[index + 1] & 0x3f) << 12) |
            (@as(u21, text[index + 2] & 0x3f) << 6) |
            @as(u21, text[index + 3] & 0x3f),
        .byte_len = 4,
    };
}

test "validated source decoder matches the standard UTF-8 decoder" {
    const representatives = [_]u21{
        0x00,
        'A',
        0x7f,
        0x80,
        0x7ff,
        0x800,
        0x0930,
        0xd7ff,
        0xe000,
        0xffff,
        0x10000,
        0x10ffff,
    };
    for (representatives) |codepoint| {
        var encoded: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(codepoint, &encoded);
        const bytes = encoded[0..len];
        const decoded = decodeValidatedUtf8(bytes, 0);
        try std.testing.expectEqual(codepoint, decoded.codepoint);
        try std.testing.expectEqual(len, decoded.byte_len);
        try std.testing.expectEqual(
            try std.unicode.utf8Decode(bytes),
            decoded.codepoint,
        );
    }
}

test "source scan recognizes bidi visual-reorder triggers" {
    for (0x0900..0x0980) |codepoint| {
        const range = commonLtrScriptRange(.devanagari).?;
        try std.testing.expect(scalarInRange(@intCast(codepoint), range));
        try std.testing.expect(!unicode.mayNeedBidiVisualReorder(
            @intCast(codepoint),
        ));
    }
    const range = commonLtrScriptRange(.devanagari).?;
    try std.testing.expect(!scalarInRange(0x202e, range));
    try std.testing.expect(unicode.mayNeedBidiVisualReorder(0x05d0));
    try std.testing.expect(unicode.mayNeedBidiVisualReorder(0x202e));
}

pub const ArabicCompositionMatch = support.ArabicCompositionMatch;
pub const arabicCompositionForFontAt = support.arabicCompositionForFontAt;
pub const glyphIndex = support.glyphIndex;
pub const fallbackGlyphIndex = support.fallbackGlyphIndex;
pub const isDecimalNumber = support.isDecimalNumber;
pub const isLetter = support.isLetter;
