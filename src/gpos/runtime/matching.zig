//! LookupFlag, GDEF class, and source-metadata matching rules for GPOS.

const std = @import("std");
const GlyphId = @import("../../glyph.zig").GlyphId;
const options = @import("options.zig");
const unicode = @import("../../unicode.zig");

pub const Options = options.Options;
pub const Error = error{ BadGpos, InvalidShapingInput };

pub inline fn lookupIgnoresGlyph(
    lookup_flag: u16,
    run: Options,
    glyph: GlyphId,
) bool {
    if (lookup_flag == 0) return false;
    const classes = run.glyph_classes;
    const class = if (classes) |items|
        if (glyph < items.len) items[glyph] else 0
    else
        0;
    if (lookup_flag == 0x0008) return class == 3;
    return lookupIgnoresGlyphComplex(lookup_flag, run, glyph, class);
}

pub noinline fn lookupIgnoresGlyphComplex(
    lookup_flag: u16,
    run: Options,
    glyph: GlyphId,
    class: u16,
) bool {
    // UseMarkFilteringSet and MarkAttachmentType are independent filters.
    if ((lookup_flag & 0x0010) != 0) {
        const set_index =
            run.active_mark_filtering_set orelse return class == 3;
        const sets = run.mark_filtering_sets orelse return class == 3;
        if (set_index >= sets.len) return class == 3;
        if (class == 3 and !glyphInMarkFilteringSet(sets[set_index], glyph)) {
            return true;
        }
    }

    if (run.glyph_classes != null) {
        if ((lookup_flag & 0x0002) != 0 and class == 1) return true;
        if ((lookup_flag & 0x0004) != 0 and class == 2) return true;
        if ((lookup_flag & 0x0008) != 0 and class == 3) return true;
    }
    const attachment_type = lookup_flag >> 8;
    if (attachment_type == 0) return false;
    const attach_classes = run.mark_attach_classes orelse return class == 3;
    if (glyph >= attach_classes.len) return class == 3;
    const attach_class = attach_classes[glyph];
    // A non-zero MarkAttachClassDef entry is sufficient mark evidence even
    // when the font omitted or misclassified the glyph in GlyphClassDef.
    const is_mark = class == 3 or (class == 0 and attach_class != 0);
    if (!is_mark) return false;
    return attach_class != attachment_type;
}

pub fn glyphInAnyMarkFilteringSet(
    sets: []const []const GlyphId,
    glyph: GlyphId,
) bool {
    for (sets) |set| {
        if (glyphInMarkFilteringSet(set, glyph)) return true;
    }
    return false;
}

pub fn glyphInMarkFilteringSet(
    glyphs: []const GlyphId,
    glyph: GlyphId,
) bool {
    // GDEF Coverage expansion preserves strictly increasing glyph order.
    // Filtering sets in Arabic fonts commonly contain dozens of marks, and
    // every GPOS lookup probes them repeatedly; binary search avoids turning
    // each visibility check into a linear walk.
    var low: usize = 0;
    var high = glyphs.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (glyphs[mid] < glyph) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low < glyphs.len and glyphs[low] == glyph;
}

pub fn validateMarkFilteringSetIndex(run: Options) Error!void {
    const set_index = run.active_mark_filtering_set orelse return;
    const sets = run.mark_filtering_sets orelse return;
    if (set_index >= sets.len) return error.BadGpos;
}

pub fn runMayHaveMarkAttachments(
    glyphs: []const GlyphId,
    run: Options,
) bool {
    if (run.run_may_have_mark_attachments) |has_marks| return has_marks;
    const classes = run.glyph_classes orelse return true;
    for (glyphs) |glyph| {
        if (glyph < classes.len and classes[glyph] == 3) return true;
    }
    return false;
}

pub fn validate(run: Options, glyph_count: usize) Error!void {
    const metadata = run.run_metadata;
    for (run.normalized_variation_coords) |coord| {
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) {
            return error.InvalidShapingInput;
        }
    }
    if (metadata.glyph_source_indices) |sources| {
        if (sources.len != glyph_count) return error.InvalidShapingInput;
    }
    if (metadata.glyph_substituted) |substituted| {
        if (substituted.len != glyph_count) return error.InvalidShapingInput;
    }
    if (metadata.source_codepoints != null and
        metadata.glyph_source_indices == null)
    {
        return error.InvalidShapingInput;
    }
    if (metadata.source_boundaries != null and
        metadata.glyph_source_indices == null)
    {
        return error.InvalidShapingInput;
    }
    if (metadata.ligature_components) |store| {
        if (store.infos.items.len != glyph_count or !store.isValid()) {
            return error.InvalidShapingInput;
        }
    }
}

pub fn sourceForGlyph(run: Options, glyph_index: usize) usize {
    const sources =
        run.run_metadata.glyph_source_indices orelse return glyph_index;
    if (glyph_index >= sources.len) return glyph_index;
    return sources[glyph_index];
}

pub fn sourceCodepointForGlyph(
    run: Options,
    glyph_index: usize,
) ?u21 {
    const codepoints = run.run_metadata.source_codepoints orelse return null;
    const source = sourceForGlyph(run, glyph_index);
    if (source >= codepoints.len) return null;
    return codepoints[source];
}

pub fn glyphWasSubstituted(run: Options, glyph_index: usize) bool {
    const substituted =
        run.run_metadata.glyph_substituted orelse return false;
    return glyph_index < substituted.len and substituted[glyph_index];
}

pub fn markAttachmentSearchSkipsGlyph(
    run: Options,
    glyph_index: usize,
) bool {
    if (run.run_has_default_ignorables == false) return false;
    const codepoint =
        sourceCodepointForGlyph(run, glyph_index) orelse return false;
    if (run.visible_variation_selectors and
        unicode.isVariationSelector(codepoint))
    {
        return false;
    }
    return unicode.isDefaultIgnorableForShaping(codepoint) and
        !glyphWasSubstituted(run, glyph_index);
}

pub fn matchSkipsGlyph(
    lookup_flag: u16,
    run: Options,
    glyphs: []const GlyphId,
    glyph_index: usize,
) bool {
    if (lookupIgnoresGlyph(lookup_flag, run, glyphs[glyph_index])) return true;
    return markAttachmentSearchSkipsGlyph(run, glyph_index);
}
