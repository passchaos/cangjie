//! SequenceLookupRecord nested GSUB dispatch.
//!
//! Nested lookup semantics differ from whole-run execution: one matched input
//! position is targeted, cardinality changes must be reported to the record
//! map, and ligatures intentionally consume following glyphs from the real
//! run. This module owns those rules while recursive context formats stay
//! statically bound through a comptime Executor.

const std = @import("std");
const chaining_lookup = @import("../chaining/lookup/root.zig");
const contextual_context = @import("../context/root.zig");
pub const direct = @import("direct.zig");
const direct_single = @import("../../direct/single/root.zig");
pub const extension = @import("extension.zig");
const generic_lookup = @import("../../lookup/generic/root.zig");
const model = @import("../model.zig");
const filtering = @import("../../../runtime/filtering.zig");
const limits = @import("../../../runtime/limits.zig");
const lookup_order = @import("../../../../opentype/lookup_order.zig");
const mutation = @import("../../../runtime/mutation.zig");
const options = @import("../../../runtime/options.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Change = model.Change;
pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    lookup_index: u16,
    allocator: std.mem.Allocator,
    run: Options,
) Error!Change {
    // A JSTF disable set applies to the complete reassembled plan, including
    // lookups reached through SequenceLookupRecord rather than a top-level
    // feature edge.
    if (lookup_order.contains(run.disabled_lookups, lookup_index)) return .{};
    try limits.consumeNested(run);
    const lookup_list = try table.offset.required16(
        view,
        0,
        try view.readU16(8),
    );
    const lookup_count = try view.readU16(lookup_list);
    if (lookup_index >= lookup_count) return error.BadGsub;
    const lookup_offset = try table.offset.required16(
        view,
        lookup_list,
        try view.readU16(
            lookup_list + 2 + @as(usize, lookup_index) * 2,
        ),
    );
    const lookup_type = try view.readU16(lookup_offset);
    const lookup_flag = try view.readU16(lookup_offset + 2);
    const subtable_count = try view.readU16(lookup_offset + 4);

    var lookup_run = run;
    if ((lookup_flag & 0x0010) != 0) {
        lookup_run.active_mark_filtering_set = try view.readU16(
            lookup_offset + 6 + @as(usize, subtable_count) * 2,
        );
        try filtering.validateMarkFilteringSetIndex(lookup_run);
    }

    switch (lookup_type) {
        1 => {
            for (0..subtable_count) |subtable_index| {
                const subtable = lookup_offset + try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                );
                if (try direct_single.at(
                    view,
                    subtable,
                    glyphs,
                    glyph_index,
                    lookup_flag,
                    lookup_run,
                )) return .{};
            }
            return .{};
        },
        2 => {
            // MultipleSubst must stop at the first matching alternative;
            // rescanning a scratch replacement could cascade later subtables.
            for (0..subtable_count) |subtable_index| {
                const subtable = lookup_offset + try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                );
                if (try direct.multiple(
                    view,
                    subtable,
                    glyphs,
                    glyph_index,
                    allocator,
                    lookup_flag,
                    lookup_run,
                )) |change| return change;
            }
            return .{};
        },
        4 => {
            for (0..subtable_count) |subtable_index| {
                const subtable = lookup_offset + try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                );
                if (try direct.ligature(
                    view,
                    subtable,
                    glyphs,
                    glyph_index,
                    allocator,
                    lookup_flag,
                    lookup_run,
                )) |change| return change;
            }
            return .{};
        },
        5 => {
            for (0..subtable_count) |subtable_index| {
                const subtable = lookup_offset + try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                );
                if ((try contextual_context.at(
                    Executor,
                    view,
                    subtable,
                    glyphs,
                    glyph_index,
                    allocator,
                    lookup_flag,
                    lookup_run,
                )).matched) return .{};
            }
            return .{};
        },
        6 => {
            for (0..subtable_count) |subtable_index| {
                const subtable = lookup_offset + try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                );
                if ((try chaining_lookup.at(
                    Executor,
                    view,
                    subtable,
                    null,
                    glyphs,
                    glyph_index,
                    allocator,
                    lookup_flag,
                    lookup_run,
                )).matched) return .{};
            }
            return .{};
        },
        7 => {
            for (0..subtable_count) |subtable_index| {
                const wrapper = lookup_offset + try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                );
                if (try extension.applyAt(
                    Executor,
                    view,
                    wrapper,
                    glyphs,
                    glyph_index,
                    allocator,
                    lookup_flag,
                    lookup_run,
                )) |change| return change;
            }
        },
        else => {},
    }

    return applyScratchFallback(
        Executor,
        view,
        lookup_offset,
        glyphs,
        glyph_index,
        allocator,
        run,
    );
}

fn applyScratchFallback(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!Change {
    // Single-target lookup kinds can run on one detached glyph. Strip every
    // parallel sidecar because it describes the caller's complete run, then
    // atomically splice the resulting cardinality back into that real run.
    var scratch = std.ArrayList(GlyphId).empty;
    defer scratch.deinit(allocator);
    try scratch.append(allocator, glyphs.items[glyph_index]);
    var scratch_run = run;
    scratch_run.glyph_source_indices = null;
    scratch_run.glyph_substituted = null;
    scratch_run.glyph_stage_substituted = null;
    scratch_run.ligature_components = null;
    scratch_run.source_features = null;
    scratch_run.active_source_feature = null;
    scratch_run.active_source_feature_mask = 0;
    try generic_lookup.apply(
        Executor,
        view,
        lookup_offset,
        null,
        &scratch,
        allocator,
        scratch_run,
        null,
    );
    const prepared = try mutation.prepareReplacement(
        allocator,
        glyphs,
        run,
        glyph_index,
        1,
        scratch.items.len,
        filtering.sourceForGlyph(run, glyph_index),
    );
    prepared.commit(glyphs, scratch.items);
    return .{ .removed_len = 1, .inserted_len = scratch.items.len };
}
