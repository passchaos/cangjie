//! Shared GSUB glyph visibility, LookupFlag, and source-scope policy.
//!
//! Every function consumes the concrete run `Options` value plus glyph/index
//! inputs. The module owns no state and uses no erased callback boundary.

const feature = @import("../feature/root.zig");
const GlyphId = @import("../../glyph.zig").GlyphId;
const options = @import("options.zig");
const unicode = @import("../../unicode.zig");

pub const Error = error{BadGsub};
pub const Options = options.Options;

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

pub fn validateMarkFilteringSetIndex(run: Options) Error!void {
    const index = run.active_mark_filtering_set orelse return;
    const sets = run.mark_filtering_sets orelse return;
    if (index >= sets.len) return error.BadGsub;
}

pub fn sourceForGlyph(run: Options, glyph_index: usize) usize {
    const sources = run.glyph_source_indices orelse return glyph_index;
    if (glyph_index >= sources.items.len) return glyph_index;
    return sources.items[glyph_index];
}

pub fn clusterForGlyph(run: Options, glyph_index: usize) usize {
    const clusters =
        run.glyph_cluster_indices orelse return sourceForGlyph(run, glyph_index);
    if (glyph_index >= clusters.items.len) {
        return sourceForGlyph(run, glyph_index);
    }
    return clusters.items[glyph_index];
}

pub fn sourceFeatureAllowsGlyph(run: Options, glyph_index: usize) bool {
    if (run.active_source_feature_mask == 0 and
        run.active_source_feature == null)
    {
        return true;
    }
    const features = run.source_features orelse return false;
    const source = sourceForGlyph(run, glyph_index);
    if (source >= features.len) return false;
    const assigned = features[source];
    if ((assigned & feature.source_mask_marker) != 0) {
        const active_mask = if (run.active_source_feature_mask != 0)
            run.active_source_feature_mask
        else
            feature.sourceMaskForTag(
                run.active_source_feature.?,
            ) orelse return false;
        return (assigned &
            (active_mask & ~feature.source_mask_marker)) != 0;
    }
    const active = run.active_source_feature orelse return false;
    return assigned == active;
}

pub fn sourceCodepointForGlyph(
    run: Options,
    glyph_index: usize,
) ?u21 {
    const codepoints = run.source_codepoints orelse return null;
    const source = sourceForGlyph(run, glyph_index);
    if (source >= codepoints.len) return null;
    return codepoints[source];
}

pub fn sourceSyllableForGlyph(
    run: Options,
    glyph_index: usize,
) ?u8 {
    if (!run.match_source_syllable) return null;
    const syllables = run.source_syllables orelse return null;
    const source = sourceForGlyph(run, glyph_index);
    if (source >= syllables.len) return null;
    return syllables[source];
}

pub fn sourceSyllableAllowsGlyph(
    run: Options,
    anchor_syllable: ?u8,
    glyph_index: usize,
) bool {
    const anchor = anchor_syllable orelse return true;
    return sourceSyllableForGlyph(run, glyph_index) == anchor;
}

pub fn glyphWasSubstituted(run: Options, glyph_index: usize) bool {
    const substituted = run.glyph_substituted orelse return false;
    return glyph_index < substituted.items.len and
        substituted.items[glyph_index];
}

pub fn contextualMaySkipGlyph(
    lookup_flag: u16,
    run: Options,
    glyphs: []const GlyphId,
    glyph_index: usize,
    context_match: bool,
) bool {
    if (lookupIgnoresGlyph(lookup_flag, run, glyphs[glyph_index])) return true;
    const codepoint =
        sourceCodepointForGlyph(run, glyph_index) orelse return false;
    if (run.visible_variation_selectors and
        unicode.isVariationSelector(codepoint))
    {
        return false;
    }
    // Mongolian FVS stays visible during GSUB even when cmap returned glyph
    // zero, so fonts can consume it and an unconsumed selector blocks context.
    if (unicode.isMongolianFreeVariationSelector(codepoint)) return false;
    // CGJ is always transparent unless ligature-specific reorder protection
    // below proves it acted as a barrier.
    if (codepoint == 0x034f) return true;
    if (!context_match) return false;
    if (codepoint == 0x180e) return false;
    if (glyphWasSubstituted(run, glyph_index)) return false;
    if (!unicode.isDefaultIgnorableForShaping(codepoint)) return false;
    if (codepoint == 0x200c and !run.active_auto_zwnj) return false;
    if (codepoint == 0x200d and !run.active_auto_zwj) return false;
    return true;
}

pub fn ligatureMaySkipGlyph(
    lookup_flag: u16,
    run: Options,
    glyphs: []const GlyphId,
    glyph_base: usize,
    relative_index: usize,
) bool {
    if (lookupIgnoresGlyph(lookup_flag, run, glyphs[relative_index])) {
        return true;
    }
    const codepoint = sourceCodepointForGlyph(
        run,
        glyph_base + relative_index,
    ) orelse return false;
    if (codepoint == 0x034f) {
        return !cgjPreventedMarkReorder(
            run,
            glyph_base + relative_index,
        );
    }
    if (unicode.isMongolianFreeVariationSelector(codepoint)) return false;
    return !run.visible_variation_selectors and
        glyphs[relative_index] == 0 and
        unicode.isVariationSelector(codepoint);
}

pub fn ligatureAnchorSyllable(run: Options, glyph_base: usize) ?u8 {
    return sourceSyllableForGlyph(run, glyph_base);
}

pub fn ligatureAllowsRelativeGlyph(
    run: Options,
    anchor_syllable: ?u8,
    glyph_base: usize,
    relative_index: usize,
) bool {
    return sourceSyllableAllowsGlyph(
        run,
        anchor_syllable,
        glyph_base + relative_index,
    );
}

noinline fn lookupIgnoresGlyphComplex(
    lookup_flag: u16,
    run: Options,
    glyph: GlyphId,
    class: u16,
) bool {
    // UseMarkFilteringSet and high-byte MarkAttachmentType are independent;
    // apply both when a lookup declares both mechanisms.
    if ((lookup_flag & 0x0010) != 0) {
        const set_index =
            run.active_mark_filtering_set orelse return class == 3;
        const sets = run.mark_filtering_sets orelse return class == 3;
        if (set_index >= sets.len) return class == 3;
        const in_selected_set =
            glyphInMarkFilteringSet(sets[set_index], glyph);
        if (class == 3 and !in_selected_set) return true;
    }
    if (run.glyph_classes != null) {
        if ((lookup_flag & 0x0002) != 0 and class == 1) return true;
        if ((lookup_flag & 0x0004) != 0 and class == 2) return true;
        if ((lookup_flag & 0x0008) != 0 and class == 3) return true;
    }
    const mark_attachment_type = lookup_flag >> 8;
    if (mark_attachment_type != 0) {
        const attach_classes =
            run.mark_attach_classes orelse return class == 3;
        if (glyph >= attach_classes.len) return class == 3;
        const attach_class = attach_classes[glyph];
        // MarkAttachClassDef can classify marks even when GlyphClassDef is
        // absent or unhelpful.
        const is_mark = class == 3 or (class == 0 and attach_class != 0);
        if (!is_mark) return false;
        return attach_class != mark_attachment_type;
    }
    return false;
}

fn glyphInMarkFilteringSet(
    glyphs: []const GlyphId,
    glyph: GlyphId,
) bool {
    for (glyphs) |candidate| {
        if (candidate == glyph) return true;
    }
    return false;
}

fn cgjPreventedMarkReorder(run: Options, glyph_index: usize) bool {
    const sources = run.glyph_source_indices orelse return false;
    const codepoints = run.source_codepoints orelse return false;
    if (glyph_index == 0 or glyph_index + 1 >= sources.items.len) return false;
    const previous_source = sources.items[glyph_index - 1];
    const next_source = sources.items[glyph_index + 1];
    if (previous_source >= codepoints.len or next_source >= codepoints.len) {
        return false;
    }
    const previous_class = unicode.modifiedCombiningClassForShaping(
        codepoints[previous_source],
    );
    const next_class = unicode.modifiedCombiningClassForShaping(
        codepoints[next_source],
    );
    return next_class != 0 and previous_class > next_class;
}
