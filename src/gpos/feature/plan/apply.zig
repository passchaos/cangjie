//! Atomic admission and execution of reusable GPOS lookup plans.

const std = @import("std");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const model = @import("model.zig");
const options = @import("../../runtime/options.zig");
const positioning = @import("../../positioning/root.zig");
const runtime_dispatch = @import("../../runtime/dispatch.zig");
const lookup_dispatcher = @import("../../runtime/lookup/dispatcher/root.zig");
const table = @import("../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error = lookup_dispatcher.Error;
pub const Options = options.Options;
pub const View = table.View;

/// Apply a plan for an internal run whose table and glyph metadata are proved.
///
/// `false` is an atomic decline: no adjustment has been appended and callers
/// may execute the ordinary path instead. The complete table/sidecar identity
/// and every `(lookup_index, lookup_offset)` tuple are checked before the first
/// lookup runs, so a stale later tuple cannot be discovered after output was
/// produced by an earlier lookup. The internal cache must also match the live
/// script, language, feature, mark-presence, and apply-all selection inputs to
/// those used by the builder; those values are intentionally not duplicated in
/// this compact execution artifact.
pub fn afterProof(
    data: []const u8,
    offset: usize,
    length: usize,
    plan: model.LookupPlan,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) Error!bool {
    // Enabled lookups change the traversal and are deliberately not part of a
    // reusable plan. Profiling retains the ordinary run's selection/apply
    // intervals, so profiled calls also stay on that path.
    if (run.selected_lookups != null or
        run.enabled_lookups.len != 0 or
        run.shape_profile != null)
    {
        return false;
    }
    if (!run.assume_validated or
        length < 10 or
        offset > data.len or
        length > data.len - offset)
    {
        return false;
    }
    const identity = plan.identity orelse return false;
    if (identity.data_ptr != data.ptr or
        identity.data_len != data.len or
        identity.table_offset != offset or
        identity.table_length != length)
    {
        return false;
    }
    // A genuinely empty LookupList has no sidecar identity. A no-op selection
    // over a non-empty list remains bound to the exact accelerator allocation.
    if (plan.entries.len == 0) {
        if (identity.accelerator_count == 0) {
            return identity.accelerators_addr == 0;
        }
        const view = View{
            .data = data,
            .offset = offset,
            .length = length,
            .assume_validated = true,
        };
        const sidecars = runtime_dispatch.exactSidecars(view, run) orelse
            return false;
        return identity.accelerators_addr == @intFromPtr(sidecars.ptr) and
            identity.accelerator_count == sidecars.len;
    }

    const view = View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = true,
    };
    const sidecars = runtime_dispatch.exactSidecars(view, run) orelse
        return false;
    if (identity.accelerators_addr != @intFromPtr(sidecars.ptr) or
        identity.accelerator_count != sidecars.len)
    {
        return false;
    }

    // This is intentionally a separate full pass. Never combine validation
    // with dispatch: adjustment output is append-only and cannot be rolled
    // back safely if a stale tuple occurs later in the plan.
    var previous_index: ?u16 = null;
    for (plan.entries) |entry| {
        if (previous_index) |previous| {
            if (entry.lookup_index <= previous) return false;
        }
        if (entry.lookup_index >= sidecars.len or
            sidecars[entry.lookup_index].lookup_offset != entry.lookup_offset)
        {
            return false;
        }
        previous_index = entry.lookup_index;
    }

    var digest_cache = lookup_dispatcher.DigestCache.init();
    for (plan.entries) |entry| {
        try lookup_dispatcher.collectAfterAcceleratorProof(
            view,
            entry.lookup_index,
            glyphs,
            adjustments,
            allocator,
            run,
            &digest_cache,
            &sidecars[entry.lookup_index],
        );
    }
    return true;
}
