//! Accelerator-backed LigatureSubst execution and second-component prefilters.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const prefilter = @import("../../../../runtime/prefilter/root.zig");
const commit = @import("../commit.zig");
const matching = @import("../matching.zig");
const metadata = @import("../metadata.zig");
const model = @import("../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = std.mem.Allocator.Error;
const Ligature = accelerator.model.LigatureSubstitution;

pub fn apply(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return applyKind(
        false,
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn applyPrefiltered(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return applyKind(
        true,
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub noinline fn applyRequiredSecond(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    @branchHint(.cold);
    if (matching.requiredSecondDigest(ligature)) |second_digest| {
        if (!hasAdjacentDigestPair(
            glyphs.items,
            ligature.first_component_digest,
            second_digest,
        )) return;
        return applyPrefiltered(
            ligature,
            glyphs,
            allocator,
            lookup_flag,
            run,
        );
    }
    const second_components = matching.requiredSecondComponents(ligature);
    if (second_components.len == 0 or
        !(if (lookup_flag == 0 and
            run.run_has_default_ignorables == false)
            hasAdjacentRequiredPair(
                glyphs.items,
                ligature.first_component_digest,
                second_components,
            )
        else
            prefilter.hasAnyGlyph(glyphs.items, second_components)))
    {
        return;
    }
    return applyPrefiltered(
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn applyAt(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?model.Change {
    if (glyph_index >= glyphs.items.len) return null;
    const first = glyphs.items[glyph_index];
    if (!ligature.first_component_digest.mayHave(first) or
        filtering.lookupIgnoresGlyph(lookup_flag, run, first)) return null;
    const set = matching.setForGlyph(ligature, first) orelse return null;
    var component_offsets: [model.max_components]usize = undefined;
    const found = tryMatch(
        ligature,
        set,
        glyphs.items[glyph_index..],
        glyph_index,
        lookup_flag,
        run,
        &component_offsets,
    ) orelse return null;
    const info = try metadata.componentInfo(
        allocator,
        run,
        glyph_index,
        found,
    );
    metadata.mergeClusters(run, glyph_index, found);
    return commit.apply(glyphs, glyph_index, found, info, run);
}

fn tryMatch(
    ligature: Ligature,
    set: accelerator.model.LigatureSet,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    component_offsets: *[model.max_components]usize,
) ?model.Match {
    return if (ligature.prefilter_second)
        matching.acceleratedPrefilteredMatch(
            ligature,
            set,
            glyphs,
            glyph_base,
            lookup_flag,
            run,
            component_offsets,
        )
    else
        matching.acceleratedMatch(
            ligature,
            set,
            glyphs,
            glyph_base,
            lookup_flag,
            run,
            component_offsets,
        );
}

fn hasAdjacentDigestPair(
    glyphs: []const GlyphId,
    first_digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
    second_digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
) bool {
    if (glyphs.len < 2) return false;
    for (glyphs[0 .. glyphs.len - 1], glyphs[1..]) |first, second| {
        if (first_digest.mayHave(first) and second_digest.mayHave(second)) {
            return true;
        }
    }
    return false;
}

fn hasAdjacentRequiredPair(
    glyphs: []const GlyphId,
    first_digest: @import("../../../../../glyph_digest.zig").GlyphDigest,
    sorted_seconds: []const GlyphId,
) bool {
    if (glyphs.len < 2) return false;
    for (glyphs[0 .. glyphs.len - 1], glyphs[1..]) |first, second| {
        if (!first_digest.mayHave(first)) continue;
        if (std.sort.binarySearch(
            GlyphId,
            sorted_seconds,
            second,
            glyphOrder,
        ) != null) return true;
    }
    return false;
}

fn glyphOrder(target: GlyphId, item: GlyphId) std.math.Order {
    return std.math.order(target, item);
}

test "adjacent required pair rejects separated candidates" {
    var first = @import("../../../../../glyph_digest.zig").GlyphDigest.empty();
    first.add(5);
    try std.testing.expect(hasAdjacentRequiredPair(&.{ 5, 7 }, first, &.{7}));
    try std.testing.expect(!hasAdjacentRequiredPair(
        &.{ 5, 9, 7 },
        first,
        &.{7},
    ));
}

fn applyKind(
    comptime prefilter_second: bool,
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    var component_offsets: [model.max_components]usize = undefined;
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) : (glyph_index += 1) {
        const first = glyphs.items[glyph_index];
        if (!ligature.first_component_digest.mayHave(first)) continue;
        // The digest is a cheap necessary condition independent of feature
        // scope and LookupFlag visibility. Rejecting misses first avoids both
        // metadata lookups for the overwhelming non-candidate population.
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, first)) continue;
        const set = matching.setForGlyph(ligature, first) orelse continue;
        const found = if (prefilter_second)
            matching.acceleratedPrefilteredMatch(
                ligature,
                set,
                glyphs.items[glyph_index..],
                glyph_index,
                lookup_flag,
                run,
                &component_offsets,
            )
        else
            matching.acceleratedMatch(
                ligature,
                set,
                glyphs.items[glyph_index..],
                glyph_index,
                lookup_flag,
                run,
                &component_offsets,
            );
        const matched = found orelse continue;
        const info = try metadata.componentInfo(
            allocator,
            run,
            glyph_index,
            matched,
        );
        metadata.mergeClusters(run, glyph_index, matched);
        _ = commit.apply(glyphs, glyph_index, matched, info, run);
    }
}
