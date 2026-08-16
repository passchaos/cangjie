//! Position-major ReverseChainSingleSubst lookup execution.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const mutation = @import("../../../runtime/mutation.zig");
const reverse_context = @import("../../../runtime/reverse_context.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const matching = @import("matching.zig");
const subtable = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Lookup = accelerator.Lookup;
const View = table.View;

pub fn apply(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) Error!void {
    var position = glyphs.items.len;
    while (position > 0) {
        position -= 1;
        for (0..subtable_count) |subtable_index| {
            const child = lookup_offset + try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            );
            if (try subtable.applyAt(
                view,
                child,
                glyphs,
                position,
                lookup_flag,
                run,
            )) break;
        }
    }
}

pub fn applyExtension(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
    cached: ?*const Lookup,
) Error!void {
    var position = glyphs.items.len;
    while (position > 0) {
        position -= 1;
        if (cached) |lookup| {
            try applyAcceleratedAt(
                view,
                lookup,
                glyphs,
                position,
                lookup_flag,
                run,
            );
            continue;
        }
        for (0..subtable_count) |subtable_index| {
            const wrapper = lookup_offset + try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            );
            const payload = try accelerator.build.lookup.extension.payload(
                view,
                wrapper,
                8,
            );
            if (try subtable.applyAt(
                view,
                payload,
                glyphs,
                position,
                lookup_flag,
                run,
            )) break;
        }
    }
}

fn applyAcceleratedAt(
    view: View,
    lookup: *const Lookup,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!void {
    const glyph = glyphs.items[position];
    if (!filtering.sourceFeatureAllowsGlyph(run, position) or
        filtering.lookupIgnoresGlyph(lookup_flag, run, glyph))
    {
        return;
    }

    if (lookup.reverse_chaining_exact_contexts.len != 0) {
        const key = matching.exactKey(
            glyphs.items,
            position,
            lookup_flag,
            run,
        ) orelse return;
        const entry = reverse_context.find(
            lookup.reverse_chaining_exact_contexts,
            key,
        ) orelse return;
        // Exact contexts are emitted only when every subtable in the lookup
        // has this shape. `find` sorts equal keys by authored subtable index,
        // so the returned replacement preserves first-subtable ownership.
        glyphs.items[position] = entry.substitute;
        mutation.markSubstituted(run, position);
        return;
    }

    const candidate_subtables = accelerator.index.chaining.findIndices(
        lookup.reverse_chaining_groups,
        &.{},
        glyph,
    ) orelse return;
    for (candidate_subtables) |subtable_index| {
        if (subtable_index >= lookup.reverse_chaining_subtables.len) {
            return error.BadGsub;
        }
        if (try subtable.applyParsedAt(
            view,
            lookup.reverse_chaining_subtables[subtable_index],
            glyphs,
            position,
            lookup_flag,
            run,
        )) break;
    }
}
