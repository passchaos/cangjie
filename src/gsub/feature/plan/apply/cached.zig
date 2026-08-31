//! Cached staged and merged GSUB lookup-plan application.

const std = @import("std");
const merge = @import("../merge.zig");
const model = @import("../../model.zig");
const metadata = @import("../../../runtime/metadata.zig");
const options = @import("../../../runtime/options.zig");
const runtime_dispatch = @import("../../../runtime/dispatch.zig");
const lookup_order = @import("../../../../opentype/lookup_order.zig");
const prefilter = @import("../../../runtime/prefilter/root.zig");
const plan_prefilter = @import("prefilter.zig");
const shared = @import("shared.zig");
const state = @import("../../../runtime/state.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Error = shared.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn staged(
    comptime Executor: type,
    comptime plan_sidecars_proved: bool,
    view: View,
    plan: model.LookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    prove_metadata: bool,
) Error!void {
    if (prove_metadata) {
        try metadata.validateLookupPlan(run, glyphs.items.len, plan);
    }
    if (try isEmpty(view)) {
        if (plan.entries.len != 0) return error.BadGsub;
        return;
    }
    if (plan_sidecars_proved and !planHasLookups(plan)) return;
    // A cached-plan proof is a claim about both the table and the accelerator
    // allocation. Bind that claim once, then validate the complete plan before
    // any entry can filter or mutate the run. In particular, a bad tuple in a
    // later stage must not be discovered after an earlier stage has executed.
    const plan_sidecars = if (plan_sidecars_proved)
        try exactStagedSidecars(view, run, plan)
    else {};
    const lookup_count = if (plan_sidecars_proved)
        undefined
    else
        try view.readU16(try requiredLookupList(view));
    var storage = state.Storage{};
    const prepared = if (plan_sidecars_proved)
        try state.prepareForExactSidecars(
            run,
            plan_sidecars,
            glyphs.items.len,
            &storage,
        )
    else
        try state.prepareForTable(
            view,
            run,
            glyphs.items.len,
            &storage,
        );
    var cache = prefilter.Cache.init();
    for (plan.entries) |entry| {
        var selected = prepared;
        selected.active_source_feature =
            if (entry.application.source_scoped)
                entry.application.tag
            else
                null;
        selected.match_source_syllable =
            entry.application.match_source_syllable;
        selected.active_auto_zwnj = entry.application.auto_zwnj;
        selected.active_auto_zwj = entry.application.auto_zwj;
        selected.active_feature_value = entry.application.value;
        selected.active_feature_random = merge.isRandom(entry.application);
        try shared.entry(
            Executor,
            plan_sidecars_proved,
            view,
            lookup_count,
            entry,
            plan_sidecars,
            glyphs,
            allocator,
            selected,
            &cache,
        );
    }
}

pub fn merged(
    comptime Executor: type,
    view: View,
    plan: model.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    prove_metadata: bool,
) Error!void {
    if (plan.lookups.len == 0) return;
    return mergedNonEmpty(
        Executor,
        view,
        plan,
        glyphs,
        allocator,
        run,
        prove_metadata,
    );
}

/// Apply a cached merged plan after proving its metadata contract. Table,
/// sidecar-allocation, and complete plan correspondence are rebound here so a
/// stale cache cannot turn the caller's proof claim into unchecked mutation.
pub fn mergedAfterPlanProof(
    comptime Executor: type,
    view: View,
    plan: model.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    if (plan.lookups.len != plan.lookup_offsets.len) return error.BadGsub;
    if (plan.lookups.len == 0) return;
    const sidecars = try exactMergedSidecars(view, run, plan);

    var storage = state.Storage{};
    const prepared = try state.prepareForExactSidecars(
        run,
        sidecars,
        glyphs.items.len,
        &storage,
    );
    var cache = prefilter.Cache.init();
    for (plan.lookups, plan.lookup_offsets) |lookup, offset| {
        if (lookup_order.contains(run.disabled_lookups, lookup.lookup)) {
            continue;
        }
        const sidecar = &sidecars[lookup.lookup];
        var selected = prepared;
        selected.active_source_feature = null;
        selected.active_source_feature_mask = lookup.source_mask;
        selected.active_auto_zwnj = lookup.auto_zwnj;
        selected.active_auto_zwj = lookup.auto_zwj;
        selected.match_source_syllable = lookup.match_source_syllable;
        selected.active_feature_value = lookup.value;
        selected.active_feature_random = lookup.random;
        if (selected.shape_profile == null) {
            if (!plan_prefilter.mayMatch(
                sidecar,
                glyphs.items,
                selected,
                &cache,
            )) continue;
            try Executor.applyLookupUnprofiledAfterPlanProof(
                view,
                offset,
                lookup.lookup,
                glyphs,
                allocator,
                selected,
                &cache,
                sidecar,
            );
        } else {
            try Executor.applyLookupAfterPlanProof(
                view,
                offset,
                lookup.lookup,
                glyphs,
                allocator,
                selected,
                &cache,
                sidecar,
            );
        }
    }
}

noinline fn mergedNonEmpty(
    comptime Executor: type,
    view: View,
    plan: model.MergedLookupPlan,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    prove_metadata: bool,
) Error!void {
    if (prove_metadata) {
        try metadata.validateMergedLookupPlan(run, glyphs.items.len, plan);
    }
    var storage = state.Storage{};
    const prepared = try state.prepareForTable(
        view,
        run,
        glyphs.items.len,
        &storage,
    );
    if (try isEmpty(view)) {
        if (plan.lookups.len != 0 or plan.lookup_offsets.len != 0) {
            return error.BadGsub;
        }
        return;
    }
    if (plan.lookups.len != plan.lookup_offsets.len) return error.BadGsub;
    const lookup_count = try view.readU16(try requiredLookupList(view));
    var cache = prefilter.Cache.init();
    for (plan.lookups, plan.lookup_offsets) |lookup, offset| {
        if (lookup.lookup >= lookup_count) return error.BadGsub;
        if (lookup_order.contains(run.disabled_lookups, lookup.lookup)) continue;
        var selected = prepared;
        selected.active_source_feature = null;
        selected.active_source_feature_mask = lookup.source_mask;
        selected.active_auto_zwnj = lookup.auto_zwnj;
        selected.active_auto_zwj = lookup.auto_zwj;
        selected.match_source_syllable = lookup.match_source_syllable;
        selected.active_feature_value = lookup.value;
        selected.active_feature_random = lookup.random;
        try Executor.applyLookup(
            view,
            offset,
            lookup.lookup,
            glyphs,
            allocator,
            selected,
            &cache,
        );
    }
}

fn isEmpty(view: View) Error!bool {
    return try view.readU16(4) == 0 and
        try view.readU16(6) == 0 and
        try view.readU16(8) == 0;
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(view, 0, try view.readU16(8));
}

fn planHasLookups(plan: model.LookupPlan) bool {
    for (plan.entries) |entry| {
        if (entry.lookups.len != 0 or entry.lookup_offsets.len != 0) {
            return true;
        }
    }
    return false;
}

fn exactStagedSidecars(
    view: View,
    run: Options,
    plan: model.LookupPlan,
) Error![]const runtime_dispatch.Lookup {
    for (plan.entries) |entry| {
        if (entry.lookups.len != entry.lookup_offsets.len) {
            return error.BadGsub;
        }
    }
    const sidecars = runtime_dispatch.exactSidecars(view, run) orelse
        return error.InvalidShapingInput;
    for (plan.entries) |entry| {
        for (entry.lookups, entry.lookup_offsets) |index, offset| {
            try validatePlanLookup(sidecars, index, offset);
        }
    }
    return sidecars;
}

fn exactMergedSidecars(
    view: View,
    run: Options,
    plan: model.MergedLookupPlan,
) Error![]const runtime_dispatch.Lookup {
    const sidecars = runtime_dispatch.exactSidecars(view, run) orelse
        return error.InvalidShapingInput;
    for (plan.lookups, plan.lookup_offsets) |lookup, offset| {
        try validatePlanLookup(sidecars, lookup.lookup, offset);
    }
    return sidecars;
}

fn validatePlanLookup(
    sidecars: []const runtime_dispatch.Lookup,
    index: u16,
    offset: usize,
) Error!void {
    _ = runtime_dispatch.lookupInExactSidecars(
        sidecars,
        offset,
        index,
    ) orelse return error.BadGsub;
}
