const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const gsub = @import("gsub.zig");
const unicode = @import("unicode.zig");

const rphf_feature = unicode.tag("rphf");

pub fn shouldShape(script_tag: unicode.OpenTypeScriptTag) bool {
    return switch (script_tag) {
        .dev2 => true,
        else => false,
    };
}

pub fn reorderPreBaseMatras(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
    codepoints: []const u21,
) void {
    var index: usize = 1;
    while (index < glyph_source_indices.items.len) : (index += 1) {
        const source_index = glyph_source_indices.items[index];
        if (source_index >= codepoints.len) continue;
        if (!isPreBaseMatra(codepoints[source_index])) continue;

        swapGlyphMetadata(glyph_ids, glyph_source_indices, ligature_components, index - 1, index);
    }
}

pub fn markInitialRephs(source_features: []u32, codepoints: []const u21) bool {
    @memset(source_features, 0);
    var marked = false;

    var index: usize = 0;
    while (index < codepoints.len) {
        if (!isDevanagariSyllableCodepoint(codepoints[index])) {
            index += 1;
            continue;
        }

        const syllable_start = index;
        const syllable_end = devanagariSyllableEnd(codepoints, syllable_start);
        if (hasInitialReph(codepoints, syllable_start, syllable_end)) {
            source_features[syllable_start] = rphf_feature;
            marked = true;
        }
        index = syllable_end;
    }

    return marked;
}

pub fn reorderRephs(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
    codepoints: []const u21,
) void {
    var index: usize = 0;
    while (index < glyph_source_indices.items.len) {
        const source_index = glyph_source_indices.items[index];
        if (!isFormedReph(ligature_components.items[index], source_index, codepoints)) {
            index += 1;
            continue;
        }

        const syllable_end = devanagariSyllableEnd(codepoints, source_index);
        const target = rephTargetGlyphIndex(glyph_source_indices.items, source_index, syllable_end, index);
        moveGlyphMetadata(glyph_ids, glyph_source_indices, ligature_components, index, target);
        index = target + 1;
    }
}

const pre_reorder_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("nukt") },
    .{ .tag = unicode.tag("akhn") },
};

const basic_feature_applications_without_reph = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("rkrf") },
    .{ .tag = unicode.tag("half") },
    .{ .tag = unicode.tag("cjct") },
};

const basic_feature_applications_with_reph = [_]gsub.FeatureApplication{
    .{ .tag = rphf_feature, .source_scoped = true },
    .{ .tag = unicode.tag("rkrf") },
    .{ .tag = unicode.tag("half") },
    .{ .tag = unicode.tag("cjct") },
};

const final_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("pres") },
    .{ .tag = unicode.tag("abvs") },
    .{ .tag = unicode.tag("blws") },
    .{ .tag = unicode.tag("psts") },
};

pub fn preReorderFeatureApplications() []const gsub.FeatureApplication {
    return &pre_reorder_feature_applications;
}

pub fn basicFeatureApplications(has_initial_reph: bool) []const gsub.FeatureApplication {
    return if (has_initial_reph)
        &basic_feature_applications_with_reph
    else
        &basic_feature_applications_without_reph;
}

pub fn finalFeatureApplications() []const gsub.FeatureApplication {
    return &final_feature_applications;
}

fn isPreBaseMatra(codepoint: u21) bool {
    return switch (codepoint) {
        0x093f => true,
        else => false,
    };
}

fn hasInitialReph(codepoints: []const u21, syllable_start: usize, syllable_end: usize) bool {
    if (syllable_start + 2 >= syllable_end) return false;
    if (codepoints[syllable_start] != 0x0930 or codepoints[syllable_start + 1] != 0x094d) return false;
    if (isJoiner(codepoints[syllable_start + 2])) return false;
    return hasConsonant(codepoints[syllable_start + 2 .. syllable_end]);
}

fn devanagariSyllableEnd(codepoints: []const u21, start: usize) usize {
    var index = start;
    var saw_virama = false;
    while (index < codepoints.len) : (index += 1) {
        const codepoint = codepoints[index];
        if (!isDevanagariSyllableCodepoint(codepoint)) break;
        if (index != start and isDevanagariConsonant(codepoint) and !saw_virama) break;

        saw_virama = if (codepoint == 0x094d)
            true
        else if (saw_virama and isJoiner(codepoint))
            true
        else
            false;
    }
    return index;
}

fn isFormedReph(info: gpos.LigatureComponentInfo, source_index: usize, codepoints: []const u21) bool {
    if (source_index + 1 >= codepoints.len) return false;
    if (codepoints[source_index] != 0x0930 or codepoints[source_index + 1] != 0x094d) return false;
    if (info.component_count < 2) return false;
    return info.component_sources[0] == source_index and info.component_sources[1] == source_index + 1;
}

fn rephTargetGlyphIndex(sources: []const usize, syllable_start: usize, syllable_end: usize, reph_index: usize) usize {
    var target = reph_index;
    for (sources, 0..) |source, glyph_index| {
        if (glyph_index == reph_index) continue;
        if (source < syllable_start or source >= syllable_end) continue;
        target = glyph_index;
    }
    return target;
}

fn hasConsonant(codepoints: []const u21) bool {
    for (codepoints) |codepoint| {
        if (isDevanagariConsonant(codepoint)) return true;
    }
    return false;
}

fn isDevanagariSyllableCodepoint(codepoint: u21) bool {
    return isDevanagariConsonant(codepoint) or
        isDevanagariDependentMark(codepoint) or
        codepoint == 0x094d or
        isJoiner(codepoint);
}

fn isDevanagariConsonant(codepoint: u21) bool {
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        (codepoint >= 0x0958 and codepoint <= 0x095f);
}

fn isDevanagariDependentMark(codepoint: u21) bool {
    return (codepoint >= 0x093a and codepoint <= 0x094c) or
        (codepoint >= 0x094e and codepoint <= 0x094f) or
        (codepoint >= 0x0951 and codepoint <= 0x0957);
}

fn isJoiner(codepoint: u21) bool {
    return codepoint == 0x200c or codepoint == 0x200d;
}

fn swapGlyphMetadata(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
    a: usize,
    b: usize,
) void {
    std.mem.swap(GlyphId, &glyph_ids.items[a], &glyph_ids.items[b]);
    std.mem.swap(usize, &glyph_source_indices.items[a], &glyph_source_indices.items[b]);
    std.mem.swap(gpos.LigatureComponentInfo, &ligature_components.items[a], &ligature_components.items[b]);
}

fn moveGlyphMetadata(
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    ligature_components: *std.ArrayList(gpos.LigatureComponentInfo),
    from: usize,
    to: usize,
) void {
    if (from == to) return;
    if (from < to) {
        var index = from;
        while (index < to) : (index += 1) {
            swapGlyphMetadata(glyph_ids, glyph_source_indices, ligature_components, index, index + 1);
        }
    } else {
        var index = from;
        while (index > to) {
            swapGlyphMetadata(glyph_ids, glyph_source_indices, ligature_components, index, index - 1);
            index -= 1;
        }
    }
}
