const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const gpos = @import("gpos.zig");
const unicode = @import("unicode.zig");

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

const gsub = @import("gsub.zig");

const indic_feature_applications = [_]gsub.FeatureApplication{
    .{ .tag = unicode.tag("abvs") },
    .{ .tag = unicode.tag("psts") },
};

pub fn featureApplications() []const gsub.FeatureApplication {
    return &indic_feature_applications;
}

fn isPreBaseMatra(codepoint: u21) bool {
    return switch (codepoint) {
        0x093f => true,
        else => false,
    };
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
