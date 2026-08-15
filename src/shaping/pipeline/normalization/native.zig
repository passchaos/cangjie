//! Native-direction reversal while preserving grapheme-internal order.

const std = @import("std");

const GlyphId = @import("../../../glyph.zig").GlyphId;
const ligature_provenance =
    @import("../../../ligature_provenance.zig");
const scratch_mod = @import("../../context/scratch.zig");
const unicode = @import("../../../unicode.zig");

/// Reverse the post-cmap stream into a script's native OpenType direction.
///
/// A simple full-array reverse would invert combining marks inside one
/// grapheme. Reverse each grapheme group first, then the complete stream, so
/// group order changes while glyph order inside every group remains stable.
pub fn reverse(scratch: *scratch_mod.ShapeScratch) void {
    const len = scratch.glyph_ids.items.len;
    if (len < 2) return;

    var group_start: usize = 0;
    var index: usize = 1;
    while (index <= len) : (index += 1) {
        if (index < len and continuesGrapheme(scratch, index)) continue;
        reverseRange(scratch, group_start, index);
        group_start = index;
    }
    reverseRange(scratch, 0, len);
}

fn continuesGrapheme(
    scratch: *const scratch_mod.ShapeScratch,
    glyph_index: usize,
) bool {
    const source_index =
        if (glyph_index < scratch.glyph_source_indices.items.len)
            scratch.glyph_source_indices.items[glyph_index]
        else
            glyph_index;
    if (source_index < scratch.codepoints.items.len and
        unicode.isUnicodeMarkCodepoint(
            scratch.codepoints.items[source_index],
        ))
    {
        return true;
    }
    return cluster(scratch, glyph_index) ==
        cluster(scratch, glyph_index - 1);
}

fn cluster(
    scratch: *const scratch_mod.ShapeScratch,
    glyph_index: usize,
) usize {
    if (glyph_index >= scratch.glyph_cluster_indices.items.len) {
        return glyph_index;
    }
    const source_index = scratch.glyph_cluster_indices.items[glyph_index];
    if (source_index >= scratch.clusters.items.len) return source_index;
    return scratch.clusters.items[source_index];
}

fn reverseRange(
    scratch: *scratch_mod.ShapeScratch,
    start: usize,
    end: usize,
) void {
    var left = start;
    var right = end;
    while (left + 1 < right) {
        right -= 1;
        swap(scratch, left, right);
        left += 1;
    }
}

fn swap(
    scratch: *scratch_mod.ShapeScratch,
    a: usize,
    b: usize,
) void {
    std.mem.swap(GlyphId, &scratch.glyph_ids.items[a], &scratch.glyph_ids.items[b]);
    std.mem.swap(
        usize,
        &scratch.glyph_source_indices.items[a],
        &scratch.glyph_source_indices.items[b],
    );
    std.mem.swap(
        usize,
        &scratch.glyph_cluster_indices.items[a],
        &scratch.glyph_cluster_indices.items[b],
    );
    std.mem.swap(
        bool,
        &scratch.glyph_substituted.items[a],
        &scratch.glyph_substituted.items[b],
    );
    std.mem.swap(
        ligature_provenance.Info,
        &scratch.ligature_components.infos.items[a],
        &scratch.ligature_components.infos.items[b],
    );
}
