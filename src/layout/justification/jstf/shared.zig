//! Shared OpenType JSTF language, source-range, and geometry helpers.

const std = @import("std");

const font_mod = @import("../../../font.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const paragraph_types = @import("../../types/paragraph.zig");
const pipeline_types = @import("../../../shaping/pipeline/types.zig");
const run_types = @import("../../types/runs.zig");
const unicode = @import("../../../unicode.zig");

pub const width_epsilon: f32 = 0.001;

pub const SourceRange = struct {
    start: usize,
    end: usize,
};

pub fn inheritShapeCaches(source: anytype, destination: anytype) void {
    destination.gdef_metadata_cache = source.gdef_metadata_cache;
    destination.gsub_table_proof_cache = source.gsub_table_proof_cache;
    destination.gpos_table_proof_cache = source.gpos_table_proof_cache;
    destination.lookup_selection_cache = source.lookup_selection_cache;
}

pub fn allEmpty(modifications: pipeline_types.JstfModifications) bool {
    return modifications.gsub_enable.len == 0 and
        modifications.gsub_disable.len == 0 and
        modifications.gpos_enable.len == 0 and
        modifications.gpos_disable.len == 0;
}

pub fn selectLanguage(
    info: font_mod.JstfInfo,
    script_tag: unicode.OpenTypeScriptTag,
    language_tag: unicode.OpenTypeLanguageTag,
) ?font_mod.JstfLanguageInfo {
    const script_bytes = tagBytes(@intFromEnum(script_tag));
    for (info.scripts) |script| {
        if (!std.mem.eql(u8, &script.tag, &script_bytes)) continue;
        const language_bytes = tagBytes(@intFromEnum(language_tag));
        for (script.languages) |candidate| {
            if (candidate.tag != null and
                std.mem.eql(u8, &candidate.tag.?, &language_bytes))
            {
                return candidate;
            }
        }
        return script.default_language;
    }
    return null;
}

pub fn sameStructure(a: anytype, b: anytype) bool {
    if (a.glyphs.items.len != b.glyphs.items.len or
        a.runs.items.len != b.runs.items.len)
    {
        return false;
    }
    for (a.glyphs.items, b.glyphs.items) |lhs, rhs| {
        if (lhs.glyph_id != rhs.glyph_id or
            lhs.cluster != rhs.cluster or
            lhs.source_byte_len != rhs.source_byte_len or
            lhs.codepoint != rhs.codepoint)
        {
            return false;
        }
    }
    return true;
}

pub fn interpolateGlyphGeometry(
    natural: []const GlyphPosition,
    maximum: []GlyphPosition,
    fraction: f32,
) void {
    for (natural, maximum) |base, *candidate| {
        candidate.x_advance = lerp(base.x_advance, candidate.x_advance, fraction);
        candidate.y_advance = lerp(base.y_advance, candidate.y_advance, fraction);
        candidate.x_offset = lerp(base.x_offset, candidate.x_offset, fraction);
        candidate.y_offset = lerp(base.y_offset, candidate.y_offset, fraction);
    }
}

pub fn reusableSourceRange(
    glyphs: []const GlyphPosition,
    line: paragraph_types.ParagraphLine,
) ?SourceRange {
    return reusableSourceRangeForGlyphs(
        glyphs,
        line.glyph_start,
        line.glyph_start + line.glyph_len,
    );
}

pub fn reusableSourceRangeForGlyphs(
    glyphs: []const GlyphPosition,
    glyph_start: usize,
    glyph_end: usize,
) ?SourceRange {
    if (glyph_start >= glyph_end or glyph_end > glyphs.len) return null;
    var start: usize = std.math.maxInt(usize);
    var end: usize = 0;
    for (glyphs[glyph_start..glyph_end]) |glyph| {
        if (glyph.isInlineObject() or
            glyph.isDiscretionaryHyphen() or
            glyph.isKashida() or
            glyph.isAutomaticHyphen() or
            glyph.isTab() or
            isMandatoryBreak(glyph.codepoint))
        {
            return null;
        }
        start = @min(start, glyph.cluster);
        end = @max(end, glyph.sourceByteEnd());
    }
    if (start == std.math.maxInt(usize) or start >= end) return null;
    return .{ .start = start, .end = end };
}

pub fn singleOwningRun(
    runs: []const run_types.CascadeRun,
    line: paragraph_types.ParagraphLine,
) ?run_types.CascadeRun {
    return singleOwningRunForGlyphs(
        runs,
        line.glyph_start,
        line.glyph_start + line.glyph_len,
    );
}

pub fn singleOwningRunForGlyphs(
    runs: []const run_types.CascadeRun,
    glyph_start: usize,
    glyph_end: usize,
) ?run_types.CascadeRun {
    if (glyph_start >= glyph_end) return null;
    var owner: ?run_types.CascadeRun = null;
    for (runs) |run| {
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= glyph_start or run.glyph_start >= glyph_end) continue;
        if (owner != null) return null;
        owner = run;
    }
    const run = owner orelse return null;
    if (run.glyph_start > glyph_start or
        run.glyph_start + run.glyph_len < glyph_end)
    {
        return null;
    }
    return run;
}

fn tagBytes(value: u32) [4]u8 {
    return .{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    };
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn isMandatoryBreak(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}
