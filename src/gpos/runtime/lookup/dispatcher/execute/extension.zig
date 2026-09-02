//! Whole-lookup ExtensionPos strategy selection.

const std = @import("std");
const contextual = @import("../../contextual/root.zig");
const extension = @import("../../extension/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const marks = @import("../../marks/root.zig");
const nested = @import("../../nested.zig");
const options = @import("../../../options.zig");
const pair = @import("../../pair/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const runtime_dispatch = @import("../../../dispatch.zig");
const table = @import("../../../../table/root.zig");
const validation = @import("../../../../validation/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error ||
    error{ UnsupportedGpos, InvalidShapingInput } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn collect(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    lookup_accelerator: ?*const @import("../../../../accelerator/model.zig").Lookup,
) Error!void {
    // ExtensionPos only widens offsets, but a lookup remains atomic. Fixed
    // wrapper checks alone cannot prevent a later malformed payload from
    // leaving earlier positioning output visible.
    if (!view.assume_validated) {
        try validation.lookup.headerAndExtensions(view, lookup_offset);
    }
    const wrapped_type = try runtime_dispatch.resolvedExtensionType(
        view,
        lookup_offset,
        9,
        subtable_count,
        lookup_index,
        run,
    );
    if (wrapped_type) |resolved_type| {
        switch (resolved_type) {
            1 => return extension.lookup.collectSingle(
                view,
                lookup_offset,
                subtable_count,
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
            ),
            2 => {
                if (lookup_accelerator) |accelerator| {
                    if (accelerator.pair_pos_extension and
                        accelerator.pair_pos_subtables.len == subtable_count)
                    {
                        return pair.accelerated.collectLookup(
                            view,
                            lookup_offset,
                            subtable_count,
                            accelerator,
                            glyphs,
                            adjustments,
                            allocator,
                            lookup_flag,
                            run,
                        );
                    }
                }
                return pair.generic.collectExtensionLookup(
                    view,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                );
            },
            4, 6 => if (lookup_accelerator) |accelerator| {
                if (try extension.prepared_marks.collectLookup(
                    view,
                    resolved_type,
                    subtable_count,
                    accelerator,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                )) return;
            } else {},
            5 => if (lookup_accelerator) |accelerator| {
                if (accelerator.mark_to_ligature_subtables.len ==
                    subtable_count)
                {
                    for (accelerator.mark_to_ligature_subtables) |subtable| {
                        try marks.ligature.collectParsed(
                            view,
                            subtable,
                            glyphs,
                            adjustments,
                            allocator,
                            lookup_flag,
                            run,
                        );
                    }
                    return;
                }
            },
            7 => if (lookup_accelerator) |accelerator| {
                if (accelerator.context_class_subtables.len == subtable_count) {
                    return contextual.context_class_accelerated.collectLookup(
                        view,
                        glyphs,
                        adjustments,
                        allocator,
                        lookup_flag,
                        run,
                        accelerator.context_class_subtables,
                        nested.apply,
                    );
                }
            },
            // Wrapped ChainContextPos may use glyph or class formats, so only
            // the proven class accelerator bypasses generic wrapper ordering.
            8 => if (lookup_accelerator) |accelerator| {
                if (accelerator.chaining_class_subtables.len != 0) {
                    return contextual.chaining.class_accelerated.lookup.collect(
                        view,
                        subtable_count,
                        glyphs,
                        adjustments,
                        allocator,
                        lookup_flag,
                        run,
                        accelerator,
                        nested.apply,
                    );
                }
            },
            else => {},
        }
    }
    return extension.lookup.collectMixed(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
        nested.contextCollect,
        nested.chainingCollect,
    );
}
