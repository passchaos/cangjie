//! PosLookupRecord execution and nested GPOS lookup dispatch.
//!
//! Contextual lookup modules call `records` through a comptime-known function
//! parameter. Keeping the recursive graph here preserves static calls without
//! erased contexts while separating nested-target semantics from top-level
//! whole-run lookup traversal.

const std = @import("std");
const contextual_bindings = @import("nested/contextual.zig");
const cursive = @import("cursive.zig");
const extension = @import("extension/root.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const marks = @import("marks/root.zig");
const lookup_order = @import("../../../opentype/lookup_order.zig");
const limits = @import("../limits.zig");
const options = @import("../options.zig");
const pair = @import("pair/root.zig");
const positioning = @import("../../positioning/root.zig");
const record_runner = @import("nested/records.zig");
const runtime_dispatch = @import("../dispatch.zig");
const runtime_matching = @import("../matching.zig");
const single = @import("single.zig");
const table = @import("../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error ||
    error{ UnsupportedGpos, InvalidShapingInput } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn records(
    view: View,
    records_pos: usize,
    record_count: usize,
    input_indices: []const usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    return record_runner.apply(
        view,
        records_pos,
        record_count,
        input_indices,
        glyphs,
        adjustments,
        allocator,
        run,
        apply,
    );
}

pub fn apply(
    view: View,
    glyphs: []const GlyphId,
    target_index: usize,
    lookup_index: u16,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    if (target_index >= glyphs.len) return error.BadGpos;
    // PosLookupRecord recursion is part of the same modified JSTF plan. A
    // disabled lookup must not re-enter through an active contextual parent.
    if (lookup_order.contains(run.disabled_lookups, lookup_index)) return;
    // Only PosLookupRecord dispatch crosses this boundary. Reject before
    // lookup parsing or adjustment mutation, and do not count ExtensionPos
    // wrappers as an additional edge.
    var nested_run = try limits.enterContext(run);

    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    if (lookup_index >= lookup_count) return error.BadGpos;
    const lookup = try table.offset.required16(
        view,
        lookup_list,
        try view.readU16(lookup_list + 2 + @as(usize, lookup_index) * 2),
    );
    const lookup_type = try view.readU16(lookup);
    const lookup_flag = try view.readU16(lookup + 2);
    const subtable_count = try view.readU16(lookup + 4);
    const exact_accelerator = runtime_dispatch.withCoverage(
        runtime_dispatch.exact(
            view,
            lookup,
            lookup_type,
            subtable_count,
            lookup_index,
            run,
        ),
    );

    if ((lookup_flag & 0x0010) != 0) {
        nested_run.active_mark_filtering_set = try view.readU16(
            lookup + 6 + @as(usize, subtable_count) * 2,
        );
        try runtime_matching.validateMarkFilteringSetIndex(nested_run);
    }
    if (lookup_type == 1) {
        if (exact_accelerator) |accelerator| {
            if (accelerator.single_pos_subtables.len != 0) {
                _ = try single.collectAtAccelerated(
                    view,
                    accelerator.single_pos_subtables,
                    glyphs[target_index],
                    target_index,
                    adjustments,
                    allocator,
                    lookup_flag,
                    nested_run,
                );
                return;
            }
        }
    }
    if (lookup_type == 8) {
        if (exact_accelerator) |accelerator| {
            if (accelerator.chaining_coverage_only) {
                _ = try @import("contextual/root.zig").chaining.coverage.lookup.collectNestedAt(
                    view,
                    lookup,
                    subtable_count,
                    glyphs,
                    target_index,
                    adjustments,
                    allocator,
                    lookup_flag,
                    nested_run,
                    accelerator,
                    records,
                    apply,
                );
                return;
            }
        }
    }
    if (lookup_type == 5) {
        if (exact_accelerator) |accelerator| {
            if (accelerator.mark_to_ligature_subtables.len == subtable_count) {
                for (accelerator.mark_to_ligature_subtables) |subtable| {
                    _ = try marks.ligature.collectAtParsed(
                        view,
                        subtable,
                        glyphs,
                        target_index,
                        adjustments,
                        allocator,
                        lookup_flag,
                        nested_run,
                    );
                }
                return;
            }
        }
    }
    if (lookup_type == 7 or lookup_type == 9) {
        if (exact_accelerator) |accelerator| {
            const wraps_context = lookup_type == 7 or
                accelerator.extension_lookup_type == 7;
            if (wraps_context and
                accelerator.context_class_subtables.len == subtable_count)
            {
                _ = try @import("contextual/root.zig").context_class_accelerated
                    .collectNestedAt(
                    view,
                    glyphs,
                    target_index,
                    adjustments,
                    allocator,
                    lookup_flag,
                    nested_run,
                    accelerator.context_class_subtables,
                    apply,
                );
                return;
            }
        }
    }
    if (lookup_type == 9) {
        if (exact_accelerator) |accelerator| {
            if (accelerator.extension_lookup_type == 5 and
                accelerator.mark_to_ligature_subtables.len == subtable_count)
            {
                for (accelerator.mark_to_ligature_subtables) |subtable| {
                    if (try marks.ligature.collectAtParsed(
                        view,
                        subtable,
                        glyphs,
                        target_index,
                        adjustments,
                        allocator,
                        lookup_flag,
                        nested_run,
                    )) return;
                }
                return;
            }
            if (accelerator.chaining_class_subtables.len != 0) {
                _ = try @import("contextual/root.zig").chaining.class_accelerated.lookup
                    .collectNestedAt(
                    view,
                    subtable_count,
                    glyphs,
                    target_index,
                    adjustments,
                    allocator,
                    lookup_flag,
                    nested_run,
                    accelerator,
                    apply,
                );
                return;
            }
        }
    }

    for (0..subtable_count) |subtable_index| {
        const subtable = try table.offset.required16(
            view,
            lookup,
            try view.readU16(lookup + 6 + subtable_index * 2),
        );
        switch (lookup_type) {
            1 => if (try single.collectAt(
                view,
                subtable,
                glyphs[target_index],
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            )) return,
            2 => if (try pair.generic.collectAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            )) return,
            3 => _ = try cursive.collectAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            ),
            4 => _ = try marks.base.collectAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
                &.{},
            ),
            5 => _ = try marks.ligature.collectAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            ),
            6 => _ = try marks.mark.collectAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            ),
            7 => if (try contextAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            )) return,
            8 => if (try chainingAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
            )) return,
            9 => if (try extension.nested.collectAt(
                view,
                subtable,
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                nested_run,
                contextAt,
                chainingAt,
            )) return,
            else => {},
        }
    }
}

pub fn contextCollect(
    view: View,
    subtable: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return contextual_bindings.contextCollect(
        view,
        subtable,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
        records,
    );
}

pub fn chainingCollect(
    view: View,
    subtable: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return contextual_bindings.chainingCollect(
        view,
        subtable,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
        records,
        apply,
    );
}

pub fn contextAt(
    view: View,
    subtable: usize,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    return contextual_bindings.contextAt(
        view,
        subtable,
        glyphs,
        target_index,
        adjustments,
        allocator,
        lookup_flag,
        run,
        records,
    );
}

pub fn chainingAt(
    view: View,
    subtable: usize,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    return contextual_bindings.chainingAt(
        view,
        subtable,
        glyphs,
        target_index,
        adjustments,
        allocator,
        lookup_flag,
        run,
        records,
        apply,
    );
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try view.readU16(8));
}
