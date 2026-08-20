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
    const second_components = matching.requiredSecondComponents(ligature);
    if (second_components.len == 0 or
        !prefilter.hasAnyGlyph(glyphs.items, second_components))
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
        if (!filtering.sourceFeatureAllowsGlyph(run, glyph_index)) continue;
        const first = glyphs.items[glyph_index];
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
