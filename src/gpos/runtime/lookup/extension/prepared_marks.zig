//! Exact prepared execution for homogeneous ExtensionPos mark lookups.
//!
//! Callers must first prove the complete lookup sidecar's table/allocation
//! identity. This module additionally requires one parsed sidecar per authored
//! wrapper, so a partial or manually altered slice cannot bypass generic
//! wrapper parsing or change subtable precedence.

const std = @import("std");
const accelerator_model = @import("../../../accelerator/model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const marks = @import("../marks/root.zig");
const model = @import("model.zig");

const Adjustment = model.Adjustment;
const Error = model.Error;
const Lookup = accelerator_model.Lookup;
const Options = model.Options;
const View = model.View;

fn hasPreparedMarkSlice(
    wrapped_type: u16,
    subtable_count: u16,
    accelerator: *const Lookup,
) bool {
    if (accelerator.lookup_type != 9 or
        accelerator.extension_lookup_type != wrapped_type)
    {
        return false;
    }
    return switch (wrapped_type) {
        4 => accelerator.mark_to_base_subtables.len == subtable_count,
        6 => accelerator.mark_to_mark_subtables.len == subtable_count,
        else => false,
    };
}

/// Execute a whole homogeneous mark lookup when its prepared slice is complete.
/// Returns false when the caller must retain the generic ExtensionPos path.
pub fn collectLookup(
    view: View,
    wrapped_type: u16,
    subtable_count: u16,
    accelerator: *const Lookup,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    if (!hasPreparedMarkSlice(wrapped_type, subtable_count, accelerator))
        return false;
    switch (wrapped_type) {
        4 => {
            for (accelerator.mark_to_base_subtables) |subtable| {
                try marks.base.collectParsed(
                    view,
                    subtable,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                );
            }
        },
        6 => {
            for (accelerator.mark_to_mark_subtables) |subtable| {
                if (subtable.class_count == 0 or glyphs.len < 2) continue;
                for (0..glyphs.len) |glyph_index| {
                    _ = try marks.mark.collectAtParsed(
                        view,
                        subtable,
                        glyphs,
                        glyph_index,
                        adjustments,
                        allocator,
                        lookup_flag,
                        run,
                    );
                }
            }
        },
        else => return false,
    }
    return true;
}

/// Apply an exact homogeneous mark lookup to one PosLookupRecord target. The
/// complete sidecar slice is walked in authored order and stops at its first
/// matching subtable, exactly like the generic nested wrapper loop.
pub fn collectAt(
    view: View,
    wrapped_type: u16,
    subtable_count: u16,
    accelerator: *const Lookup,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    if (!hasPreparedMarkSlice(wrapped_type, subtable_count, accelerator))
        return false;
    switch (wrapped_type) {
        4 => {
            for (accelerator.mark_to_base_subtables) |subtable| {
                if (try marks.base.collectAtParsed(
                    view,
                    subtable,
                    glyphs,
                    target_index,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                    &.{},
                    null,
                )) break;
            }
        },
        6 => {
            for (accelerator.mark_to_mark_subtables) |subtable| {
                if (try marks.mark.collectAtParsed(
                    view,
                    subtable,
                    glyphs,
                    target_index,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                )) break;
            }
        },
        else => return false,
    }
    return true;
}
