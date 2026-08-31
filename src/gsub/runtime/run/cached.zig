//! Exact accelerator-backed cached lookup selection.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const lookup_order = @import("../../../opentype/lookup_order.zig");
const options = @import("../options.zig");
const prefilter = @import("../prefilter/root.zig");
const state = @import("../state.zig");
const table = @import("../../table/root.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

/// Apply a trusted non-empty cached selection or decline without mutation.
pub noinline fn apply(
    comptime Executor: type,
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
) Error!bool {
    if (!run.assume_validated) return false;
    // The layout shaper installs one shared bounded budget. Without it this
    // shortcut must decline rather than create an independently unbounded run.
    if (run.operations_left == null or run.max_glyph_count == null) {
        return false;
    }
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return false;
    }
    const base_selected = run.selected_lookups orelse return false;
    var enabled_selected_owned: ?[]u16 = null;
    defer if (enabled_selected_owned) |selected| allocator.free(selected);
    const selected = if (run.enabled_lookups.len == 0)
        base_selected
    else selected: {
        const merged = try lookup_order.mergeEnabled(
            allocator,
            base_selected,
            run.enabled_lookups,
        );
        enabled_selected_owned = merged;
        break :selected merged;
    };
    if (selected.len == 0) return false;
    const sidecars = run.lookup_accelerators orelse return false;
    _ = accelerator.feature_index.exact(
        data,
        offset,
        length,
        sidecars,
    ) orelse return false;

    // Prove every index and exact lookup identity before the first mutation so
    // fallback remains safe if any cached element is stale.
    for (selected) |index| {
        if (index >= sidecars.len) return false;
        const sidecar = &sidecars[index];
        if (sidecar.lookup_offset == 0 or sidecar.lookup_type == 0) {
            return false;
        }
    }

    const view = View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = true,
    };
    var storage = state.Storage{};
    const prepared = try state.prepareForExactSidecars(
        run,
        sidecars,
        glyphs.items.len,
        &storage,
    );
    var cache = prefilter.Cache.init();
    for (selected) |index| {
        if (lookup_order.contains(run.disabled_lookups, index)) continue;
        try Executor.applyLookupAfterPlanProof(
            view,
            sidecars[index].lookup_offset,
            index,
            glyphs,
            allocator,
            prepared,
            &cache,
            &sidecars[index],
        );
    }
    return true;
}
