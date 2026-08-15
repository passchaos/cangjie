//! Hangul Jamo source features and cluster preparation.

const shaping_metadata = @import("../../../shaping_metadata.zig");
const unicode = @import("../../../unicode.zig");

pub fn needsDefaultDisabledCalt(codepoints: []const u21) bool {
    var has_jamo = false;
    for (codepoints) |codepoint| {
        if (isJamo(codepoint)) {
            has_jamo = true;
            continue;
        }
        if (isSyllable(codepoint)) continue;
        const script = unicode.scriptForCodepoint(codepoint);
        if (script != .common and script != .inherited and
            script != .unknown)
        {
            return false;
        }
    }
    return has_jamo;
}

pub fn hasJamo(codepoints: []const u21) bool {
    for (codepoints) |codepoint| {
        if (featureTag(codepoint) != null) return true;
    }
    return false;
}

pub fn markSourceFeatures(
    source_features: []u32,
    codepoints: []const u21,
) bool {
    @memset(source_features, 0);
    var any = false;
    var source: usize = 0;
    while (source < codepoints.len) {
        if (!isLeading(codepoints[source]) or
            source + 1 >= codepoints.len or
            !isVowel(codepoints[source + 1]))
        {
            source += 1;
            continue;
        }
        source_features[source] = unicode.tag("ljmo");
        source_features[source + 1] = unicode.tag("vjmo");
        any = true;
        if (source + 2 < codepoints.len and
            isTrailing(codepoints[source + 2]))
        {
            source_features[source + 2] = unicode.tag("tjmo");
            source += 3;
        } else {
            source += 2;
        }
    }
    return any;
}

pub fn featuresCoverAll(
    source_features: []const u32,
    codepoints: []const u21,
) bool {
    for (codepoints, source_features) |codepoint, feature| {
        if (featureTag(codepoint) != null and feature == 0) return false;
    }
    return true;
}

pub fn mergeClusters(
    clusters: []usize,
    sources: []const usize,
    codepoints: []const u21,
) void {
    var glyph_index: usize = 0;
    while (glyph_index < sources.len) {
        const source = sources[glyph_index];
        if (source >= codepoints.len or !isLeading(codepoints[source])) {
            glyph_index += 1;
            continue;
        }
        var end = glyph_index + 1;
        var saw_vowel = false;
        while (end < sources.len) : (end += 1) {
            const next_source = sources[end];
            if (next_source >= codepoints.len) break;
            const codepoint = codepoints[next_source];
            if (!saw_vowel and isVowel(codepoint)) {
                saw_vowel = true;
                continue;
            }
            if (saw_vowel and isTrailing(codepoint)) continue;
            break;
        }
        if (saw_vowel) {
            shaping_metadata.mergeMonotoneClusters(
                clusters,
                glyph_index,
                end,
            );
        }
        glyph_index = end;
    }
}

pub fn withJamoFeatures(
    out: []unicode.FeatureOverride,
    overrides: []const unicode.FeatureOverride,
) ?[]const unicode.FeatureOverride {
    if (out.len < overrides.len + 3) return null;
    var count: usize = 0;
    var has_ljmo = false;
    var has_vjmo = false;
    var has_tjmo = false;
    for (overrides) |override| {
        if (override.tag == unicode.tag("ljmo")) has_ljmo = true;
        if (override.tag == unicode.tag("vjmo")) has_vjmo = true;
        if (override.tag == unicode.tag("tjmo")) has_tjmo = true;
        out[count] = override;
        count += 1;
    }
    inline for (.{
        .{ unicode.tag("ljmo"), &has_ljmo },
        .{ unicode.tag("vjmo"), &has_vjmo },
        .{ unicode.tag("tjmo"), &has_tjmo },
    }) |entry| {
        if (!entry[1].*) {
            out[count] = .{ .tag = entry[0], .enabled = true };
            count += 1;
        }
    }
    return out[0..count];
}

fn featureTag(codepoint: u21) ?u32 {
    if (isLeading(codepoint)) return unicode.tag("ljmo");
    if (isVowel(codepoint)) return unicode.tag("vjmo");
    if (isTrailing(codepoint)) return unicode.tag("tjmo");
    return null;
}

fn isSyllable(codepoint: u21) bool {
    return codepoint >= 0xac00 and codepoint <= 0xd7af;
}

fn isJamo(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x11ff) or
        (codepoint >= 0x3130 and codepoint <= 0x318f) or
        (codepoint >= 0xa960 and codepoint <= 0xa97f) or
        (codepoint >= 0xd7b0 and codepoint <= 0xd7ff);
}

fn isLeading(codepoint: u21) bool {
    return (codepoint >= 0x1100 and codepoint <= 0x115f) or
        (codepoint >= 0xa960 and codepoint <= 0xa97f);
}

fn isVowel(codepoint: u21) bool {
    return (codepoint >= 0x1160 and codepoint <= 0x11a7) or
        (codepoint >= 0xd7b0 and codepoint <= 0xd7c7);
}

fn isTrailing(codepoint: u21) bool {
    return (codepoint >= 0x11a8 and codepoint <= 0x11ff) or
        (codepoint >= 0xd7cb and codepoint <= 0xd7fb);
}
