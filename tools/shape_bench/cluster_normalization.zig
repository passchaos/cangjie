const std = @import("std");
const cangjie = @import("cangjie");

const LegacyCluster = cangjie.testing.shaping_cluster.Cluster;

const IndicSyllableCluster = struct {
    byte_start: usize,
    byte_len: usize,
    base_cluster: usize,
    initial_reph: bool,
    has_prebase_matra: bool,
};

/// Normalize Cangjie's raw source clusters to the shaping-cluster contract
/// exposed by HarfBuzz and HarfRust at their default cluster level.
///
/// The source boundaries come from the same internal shaping iterator used by
/// Cangjie's USE initialization. They deliberately do not use public UAX #29
/// caret boundaries, so a Unicode data upgrade cannot change the parity oracle.
pub fn glyphClusters(
    allocator: std.mem.Allocator,
    text: []const u8,
    glyphs: []const cangjie.shaping.GlyphPosition,
    normalize: bool,
) ![]const u32 {
    const clusters = try allocator.alloc(u32, glyphs.len);
    if (!normalize) {
        for (glyphs, clusters) |glyph, *cluster| cluster.* = @intCast(glyph.cluster);
        return clusters;
    }

    const shaping_clusters = try cangjie.testing.shaping_cluster.itemize(
        allocator,
        text,
    );
    defer allocator.free(shaping_clusters);
    const indic_syllables = try indicSyllableClusters(allocator, text);
    defer allocator.free(indic_syllables);

    var previous_cluster: ?usize = null;
    var previous_raw_cluster: ?usize = null;
    for (glyphs, clusters, 0..) |glyph, *cluster, glyph_index| {
        const normalized = if (isPreBaseMatraCluster(text, glyph.cluster))
            normalizedPreBaseMatraClusterFromRun(indic_syllables, glyphs, glyph_index)
        else
            normalizedClusterStartForByte(
                text,
                shaping_clusters,
                indic_syllables,
                glyph.cluster,
                previous_cluster,
                previous_raw_cluster,
            );
        cluster.* = @intCast(normalized);
        previous_cluster = normalized;
        previous_raw_cluster = glyph.cluster;
    }
    return clusters;
}

fn normalizedClusterStartForByte(
    text: []const u8,
    graphemes: []const LegacyCluster,
    indic_syllables: []const IndicSyllableCluster,
    byte_offset: usize,
    previous_cluster: ?usize,
    previous_raw_cluster: ?usize,
) usize {
    if (codepointAtByte(text, byte_offset)) |codepoint| {
        if (previous_raw_cluster) |raw_cluster| {
            if (raw_cluster != byte_offset and
                isArabicPrependClusterLeader(text, raw_cluster)) return byte_offset;
        }
        if (isPreBaseMatra(codepoint)) {
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable|
                return syllable.base_cluster;
        } else if (codepoint == 0x094d) {
            if (previous_cluster) |cluster| return cluster;
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable|
                return syllable.byte_start;
        } else if (isDevanagariDependentMark(codepoint)) {
            if (previous_cluster) |cluster| return cluster;
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable|
                return syllable.base_cluster;
        } else if (isDevanagariConsonant(codepoint)) {
            if (indicSyllableContainingByte(indic_syllables, byte_offset)) |syllable| {
                if (syllable.has_prebase_matra) {
                    if (byte_offset < syllable.base_cluster) return syllable.byte_start;
                    if (byte_offset == syllable.base_cluster) return byte_offset;
                    return if (previous_cluster) |cluster|
                        if (cluster >= syllable.byte_start and cluster < byte_offset)
                            cluster
                        else
                            byte_offset
                    else
                        byte_offset;
                }
                if (syllable.initial_reph and byte_offset != syllable.byte_start) {
                    if (previous_cluster == syllable.byte_start and
                        previous_raw_cluster != syllable.byte_start and
                        followsVirama(text, byte_offset)) return syllable.byte_start;
                    return if (isFirstPostHalantConsonant(
                        text,
                        syllable.byte_start,
                        byte_offset,
                    ))
                        syllable.byte_start
                    else
                        byte_offset;
                }
                return byte_offset;
            }
        } else if (codepoint == 0x200d) {
            if (previous_cluster) |cluster| return cluster;
            return byte_offset;
        } else if (codepoint == 0x200c) {
            return byte_offset;
        } else if (isHangulConjoiningJamo(codepoint)) {
            return byte_offset;
        }
    }
    return graphemeClusterStartForByte(graphemes, byte_offset);
}

fn isHangulConjoiningJamo(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x11ff) or
        (codepoint >= 0xa960 and codepoint <= 0xa97f) or
        (codepoint >= 0xd7b0 and codepoint <= 0xd7ff);
}

fn isArabicPrependClusterLeader(text: []const u8, byte_offset: usize) bool {
    return switch (codepointAtByte(text, byte_offset) orelse return false) {
        0x0600...0x0605, 0x06dd, 0x070f, 0x0890...0x0891, 0x08e2 => true,
        else => false,
    };
}

fn graphemeClusterStartForByte(
    graphemes: []const LegacyCluster,
    byte_offset: usize,
) usize {
    for (graphemes) |current| {
        if (byte_offset >= current.byte_start and
            byte_offset < current.byte_start + current.byte_len) return current.byte_start;
    }
    return byte_offset;
}

fn isPreBaseMatraCluster(text: []const u8, byte_offset: usize) bool {
    return isPreBaseMatra(codepointAtByte(text, byte_offset) orelse return false);
}

fn normalizedPreBaseMatraClusterFromRun(
    indic_syllables: []const IndicSyllableCluster,
    glyphs: []const cangjie.shaping.GlyphPosition,
    glyph_index: usize,
) usize {
    const matra_cluster = glyphs[glyph_index].cluster;
    const syllable = indicSyllableContainingByte(
        indic_syllables,
        matra_cluster,
    ) orelse return matra_cluster;
    if (syllable.initial_reph) return syllable.byte_start;
    return syllable.base_cluster;
}

fn indicSyllableClusters(
    allocator: std.mem.Allocator,
    text: []const u8,
) ![]const IndicSyllableCluster {
    var clusters = std.ArrayList(IndicSyllableCluster).empty;
    errdefer clusters.deinit(allocator);

    var view = try std.unicode.Utf8View.init(text);
    var it = view.iterator();
    var cursor: usize = 0;
    var syllable_start: ?usize = null;
    var syllable_end: usize = 0;
    var saw_virama = false;
    var saw_post_virama_consonant = false;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        const byte_end = cursor;

        if (!isIndicSyllableCodepoint(codepoint)) {
            if (syllable_start) |start| {
                try appendIndicSyllable(&clusters, allocator, text, start, syllable_end);
                syllable_start = null;
            }
            saw_virama = false;
            saw_post_virama_consonant = false;
            continue;
        }

        if (syllable_start != null and isDevanagariBase(codepoint) and
            !saw_virama and byte_start != syllable_start.?)
        {
            try appendIndicSyllable(
                &clusters,
                allocator,
                text,
                syllable_start.?,
                syllable_end,
            );
            syllable_start = byte_start;
            saw_virama = false;
            saw_post_virama_consonant = false;
        } else if (syllable_start == null) {
            syllable_start = byte_start;
            saw_virama = false;
            saw_post_virama_consonant = false;
        }
        syllable_end = byte_end;

        if (codepoint == 0x094d) {
            saw_virama = true;
        } else if (saw_virama and codepoint == 0x200c) {
            try appendIndicSyllable(
                &clusters,
                allocator,
                text,
                syllable_start.?,
                syllable_end,
            );
            syllable_start = null;
            saw_virama = false;
            saw_post_virama_consonant = false;
        } else if (saw_virama and isDevanagariConsonant(codepoint)) {
            saw_post_virama_consonant = true;
            saw_virama = false;
        } else if (saw_post_virama_consonant and
            isDevanagariDependentMark(codepoint))
        {
            // Keep the mark in this syllable.
        } else if (!isDevanagariDependentMark(codepoint) and
            codepoint != 0x200c and codepoint != 0x200d)
        {
            saw_virama = false;
        }
    }

    if (syllable_start) |start|
        try appendIndicSyllable(&clusters, allocator, text, start, syllable_end);
    return try clusters.toOwnedSlice(allocator);
}

fn appendIndicSyllable(
    clusters: *std.ArrayList(IndicSyllableCluster),
    allocator: std.mem.Allocator,
    text: []const u8,
    start: usize,
    end: usize,
) !void {
    const initial_reph = startsWithInitialReph(text[start..end]);
    try clusters.append(allocator, .{
        .byte_start = start,
        .byte_len = end - start,
        .base_cluster = indicSyllableBaseCluster(text[start..end], start, initial_reph),
        .initial_reph = initial_reph,
        .has_prebase_matra = hasPreBaseMatra(text[start..end]),
    });
}

fn indicSyllableContainingByte(
    syllables: []const IndicSyllableCluster,
    byte_offset: usize,
) ?IndicSyllableCluster {
    for (syllables) |current| {
        if (byte_offset >= current.byte_start and
            byte_offset < current.byte_start + current.byte_len) return current;
    }
    return null;
}

fn codepointAtByte(text: []const u8, byte_offset: usize) ?u21 {
    var view = std.unicode.Utf8View.init(text) catch return null;
    var it = view.iterator();
    var cursor: usize = 0;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        if (byte_start == byte_offset) return codepoint;
        if (byte_start > byte_offset) return null;
    }
    return null;
}

fn startsWithInitialReph(text: []const u8) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    const first = it.nextCodepoint() orelse return false;
    const second = it.nextCodepoint() orelse return false;
    if (first != 0x0930 or second != 0x094d) return false;
    const third = it.nextCodepoint() orelse return false;
    if (third == 0x200c or third == 0x200d) return false;
    if (isDevanagariConsonant(third)) return true;
    while (it.nextCodepoint()) |codepoint| {
        if (isDevanagariConsonant(codepoint)) return true;
    }
    return false;
}

fn isFirstPostHalantConsonant(
    text: []const u8,
    syllable_start: usize,
    byte_offset: usize,
) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    var cursor: usize = 0;
    var previous_was_virama = false;
    var seen_post_halant_consonant = false;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        if (byte_start < syllable_start) continue;
        if (byte_start > byte_offset) return false;

        const is_target = byte_start == byte_offset;
        if (previous_was_virama and isDevanagariConsonant(codepoint)) {
            if (is_target) return !seen_post_halant_consonant;
            seen_post_halant_consonant = true;
        } else if (is_target) {
            return false;
        }
        previous_was_virama = codepoint == 0x094d;
    }
    return false;
}

fn followsVirama(text: []const u8, byte_offset: usize) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    var cursor: usize = 0;
    var previous: ?u21 = null;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;
        if (byte_start == byte_offset) return previous == 0x094d;
        if (byte_start > byte_offset) return false;
        previous = codepoint;
    }
    return false;
}

fn indicSyllableBaseCluster(
    text: []const u8,
    byte_base: usize,
    initial_reph: bool,
) usize {
    if (initial_reph) return byte_base;

    var view = std.unicode.Utf8View.init(text) catch return byte_base;
    var it = view.iterator();
    var cursor: usize = 0;
    var base_cluster = byte_base;
    var saw_virama = false;
    var virama_before_ra = false;
    while (it.nextCodepoint()) |codepoint| {
        const byte_start = cursor;
        cursor = it.i;

        if (codepoint == 0x094d) {
            saw_virama = true;
            continue;
        }
        if (saw_virama and isDevanagariConsonant(codepoint)) {
            if (codepoint == 0x0930) {
                virama_before_ra = true;
            } else {
                base_cluster = byte_base + byte_start;
            }
            saw_virama = false;
            continue;
        }
        if (isDevanagariConsonant(codepoint) and
            !virama_before_ra and base_cluster == byte_base)
            base_cluster = byte_base + byte_start;
        if (!isDevanagariDependentMark(codepoint) and
            codepoint != 0x200c and codepoint != 0x200d)
            saw_virama = false;
    }

    return if (virama_before_ra) byte_base else base_cluster;
}

fn isIndicSyllableCodepoint(codepoint: u21) bool {
    return isDevanagariBase(codepoint) or
        isDevanagariDependentMark(codepoint) or
        codepoint == 0x094d or codepoint == 0x200c or codepoint == 0x200d;
}

fn isDevanagariBase(codepoint: u21) bool {
    return isDevanagariConsonant(codepoint) or
        isDevanagariIndependentVowel(codepoint);
}

fn isDevanagariConsonant(codepoint: u21) bool {
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        (codepoint >= 0x0958 and codepoint <= 0x095f);
}

fn isDevanagariIndependentVowel(codepoint: u21) bool {
    return (codepoint >= 0x0904 and codepoint <= 0x0914) or
        codepoint == 0x0960 or codepoint == 0x0961;
}

fn isDevanagariDependentMark(codepoint: u21) bool {
    return (codepoint >= 0x0900 and codepoint <= 0x0903) or
        (codepoint >= 0x093a and codepoint <= 0x094c) or
        (codepoint >= 0x094e and codepoint <= 0x094f) or
        (codepoint >= 0x0951 and codepoint <= 0x0957);
}

fn isPreBaseMatra(codepoint: u21) bool {
    return codepoint == 0x093f;
}

fn hasPreBaseMatra(text: []const u8) bool {
    var view = std.unicode.Utf8View.init(text) catch return false;
    var it = view.iterator();
    while (it.nextCodepoint()) |codepoint| {
        if (isPreBaseMatra(codepoint)) return true;
    }
    return false;
}
