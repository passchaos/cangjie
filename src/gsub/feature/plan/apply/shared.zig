//! Shared lookup invocation for feature-plan application.

const std = @import("std");
const model = @import("../../model.zig");
const options = @import("../../../runtime/options.zig");
const lookup_order = @import("../../../../opentype/lookup_order.zig");
const prefilter = @import("../../../runtime/prefilter/root.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const RunDigestCache = prefilter.Cache;
pub const View = table.View;

pub fn entry(
    comptime Executor: type,
    comptime plan_sidecars_proved: bool,
    view: View,
    lookup_count: u16,
    plan_entry: model.LookupPlanEntry,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    cache: *RunDigestCache,
) Error!void {
    if (plan_sidecars_proved) {
        std.debug.assert(
            plan_entry.lookup_offsets.len == plan_entry.lookups.len,
        );
    } else if (plan_entry.lookup_offsets.len != plan_entry.lookups.len) {
        return error.BadGsub;
    }
    const plan_sidecars = if (plan_sidecars_proved)
        run.lookup_accelerators.?
    else
        undefined;
    if (run.disabled_lookups.len == 0) {
        if (run.shape_profile == null) {
            for (plan_entry.lookups, plan_entry.lookup_offsets) |index, offset| {
                if (plan_sidecars_proved) {
                    std.debug.assert(index < plan_sidecars.len);
                    const sidecar = &plan_sidecars[index];
                    // The internal plan and sidecar slices were built from the
                    // same validated font table. Keep a debug assertion for
                    // that ownership contract without paying an identity
                    // branch for every lookup in release shaping.
                    std.debug.assert(sidecar.lookup_offset == offset);
                    std.debug.assert(sidecar.lookup_type != 0);
                    try Executor.applyLookupUnprofiledAfterPlanProof(
                        view,
                        offset,
                        index,
                        glyphs,
                        allocator,
                        run,
                        cache,
                        sidecar,
                    );
                } else {
                    if (index >= lookup_count) return error.BadGsub;
                    try Executor.applyLookupUnprofiled(
                        view,
                        offset,
                        index,
                        glyphs,
                        allocator,
                        run,
                        cache,
                    );
                }
            }
            return;
        }
        for (plan_entry.lookups, plan_entry.lookup_offsets) |index, offset| {
            if (plan_sidecars_proved) {
                std.debug.assert(index < plan_sidecars.len);
            } else if (index >= lookup_count) {
                return error.BadGsub;
            }
            try Executor.applyLookup(
                view,
                offset,
                index,
                glyphs,
                allocator,
                run,
                cache,
            );
        }
        return;
    }
    for (plan_entry.lookups, plan_entry.lookup_offsets) |index, offset| {
        if (plan_sidecars_proved) {
            std.debug.assert(index < plan_sidecars.len);
        } else if (index >= lookup_count) {
            return error.BadGsub;
        }
        if (lookup_order.contains(run.disabled_lookups, index)) continue;
        try Executor.applyLookup(
            view,
            offset,
            index,
            glyphs,
            allocator,
            run,
            cache,
        );
    }
}

pub fn indices(
    comptime Executor: type,
    view: View,
    lookup_list: usize,
    lookup_count: u16,
    selected: []const u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    cache: *RunDigestCache,
) Error!void {
    for (selected) |index| {
        if (index >= lookup_count) return error.BadGsub;
        if (lookup_order.contains(run.disabled_lookups, index)) continue;
        const offset = try table.offset.required16(
            view,
            lookup_list,
            try view.readU16(
                lookup_list + 2 + @as(usize, index) * 2,
            ),
        );
        try Executor.applyLookup(
            view,
            offset,
            index,
            glyphs,
            allocator,
            run,
            cache,
        );
    }
}
