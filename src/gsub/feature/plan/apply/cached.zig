//! Cached staged and merged GSUB lookup-plan application.

const std = @import("std");
const merge = @import("../merge.zig");
const model = @import("../../model.zig");
const metadata = @import("../../../runtime/metadata.zig");
const options = @import("../../../runtime/options.zig");
const lookup_order = @import("../../../../opentype/lookup_order.zig");
const prefilter = @import("../../../runtime/prefilter/root.zig");
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
    var storage = state.Storage{};
    const prepared = try state.prepare(run, glyphs.items.len, &storage);
    if (try isEmpty(view)) {
        if (plan.entries.len != 0) return error.BadGsub;
        return;
    }
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
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
    if (prove_metadata) {
        try metadata.validateMergedLookupPlan(run, glyphs.items.len, plan);
    }
    var storage = state.Storage{};
    const prepared = try state.prepare(run, glyphs.items.len, &storage);
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
