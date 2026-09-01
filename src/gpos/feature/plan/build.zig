//! Construction of stable, allocator-owned GPOS lookup plans.

const std = @import("std");
const LookupAccelerator = @import("../../accelerator/model.zig").Lookup;
const model = @import("model.zig");
const options = @import("../../runtime/options.zig");
const runtime_dispatch = @import("../../runtime/dispatch.zig");
const run_selection = @import("../run_selection.zig");
const table = @import("../../table/root.zig");

pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const Options = options.Options;
pub const View = table.View;

/// Build the lookup traversal selected by the same rules as an ordinary run.
///
/// This is an internal trusted-cache boundary: `run` must name the exact
/// validated sidecar allocation for every non-empty LookupList and must not
/// itself carry a preselected lookup list. Callers must reuse the plan only for
/// the selection options represented by their cache key.
///
/// JSTF-enabled lookups are intentionally not baked into the plan. They are a
/// per-reshape modifier; the plan executor declines such runs so the ordinary
/// dispatcher can merge them without polluting a reusable selection cache.
pub fn lookupPlan(
    data: []const u8,
    offset: usize,
    length: usize,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!model.LookupPlan {
    const view = try tableView(
        data,
        offset,
        length,
        run.assume_validated,
    );
    if (try view.readU16(0) != 1) return error.UnsupportedGpos;
    return buildFromView(view, allocator, run);
}

fn buildFromView(
    view: View,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!model.LookupPlan {
    // A plan is the canonical selection itself, not a copy of another cached
    // selection. Accepting this caller-provided escape hatch would allow
    // duplicate or reordered entries that the plan executor cannot distinguish
    // from corruption. The ordinary runtime remains available for that case.
    if (!view.assume_validated or
        run.selected_lookups != null or
        run.enabled_lookups.len != 0)
    {
        return error.InvalidShapingInput;
    }

    // Bind the sidecar allocation before feature selection. Even a no-op plan
    // for a non-empty LookupList must not become a portable way to suppress
    // another cached font's positioning. A truly empty LookupList has no
    // sidecar allocation to bind.
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    const sidecars: ?[]const LookupAccelerator = if (lookup_count == 0)
        null
    else
        runtime_dispatch.exactSidecars(view, run) orelse
            return error.InvalidShapingInput;

    var selected_owned = try run_selection.lookupIndices(view, allocator, run);
    defer selected_owned.deinit(allocator);
    const selected = selected_owned.items;

    // Empty feature selection has two meanings in the historical executor. A
    // real feature topology with no active edge is a no-op, while low-level
    // topology-free tables retain the apply-all fallback used by tests and
    // tooling. Resolve that ambiguity while constructing the plan so an empty
    // plan always has the single, reusable meaning "successful no-op".
    if (selected.len == 0 and
        (run.features.len != 0 or
            (!run.apply_all_if_unselected and try hasFeatureTopology(view))))
    {
        return emptyPlan(view, allocator, sidecars);
    }

    var entries = std.ArrayList(model.LookupPlanEntry).empty;
    errdefer entries.deinit(allocator);

    if (selected.len != 0) {
        try entries.ensureTotalCapacity(allocator, selected.len);
        for (selected) |lookup_index| {
            // Match ordinary run traversal: externally supplied selections
            // may contain stale indexes, which are safely ignored. Plans
            // produced from the normal selector are already in range.
            if (lookup_index >= lookup_count) continue;
            entries.appendAssumeCapacity(.{
                .lookup_index = lookup_index,
                .lookup_offset = try lookupOffset(
                    view,
                    lookup_list,
                    lookup_index,
                ),
            });
        }
    } else {
        try entries.ensureTotalCapacity(allocator, lookup_count);
        for (0..lookup_count) |lookup_index| {
            entries.appendAssumeCapacity(.{
                .lookup_index = @intCast(lookup_index),
                .lookup_offset = try lookupOffset(
                    view,
                    lookup_list,
                    @intCast(lookup_index),
                ),
            });
        }
    }

    if (entries.items.len == 0) {
        // Allocate the canonical empty result before releasing any capacity
        // accumulated while dropping stale indexes. If that allocation fails,
        // the enclosing errdefer remains the single owner of `entries`.
        const empty = try emptyPlan(view, allocator, sidecars);
        entries.deinit(allocator);
        return empty;
    }

    // Non-empty plans are executable only with the exact immutable sidecar
    // allocation used here. Binding it during construction prevents a plan
    // from one cache/font from selecting coincidentally equal tuples in
    // another accelerator allocation.
    const exact_sidecars = sidecars orelse return error.InvalidShapingInput;
    for (entries.items) |entry| {
        if (entry.lookup_index >= exact_sidecars.len or
            exact_sidecars[entry.lookup_index].lookup_offset != entry.lookup_offset)
        {
            return error.InvalidShapingInput;
        }
    }
    return .{
        .entries = try entries.toOwnedSlice(allocator),
        .identity = identity(view, exact_sidecars),
    };
}

fn emptyPlan(
    view: View,
    allocator: std.mem.Allocator,
    sidecars: ?[]const LookupAccelerator,
) std.mem.Allocator.Error!model.LookupPlan {
    return .{
        .entries = try allocator.alloc(model.LookupPlanEntry, 0),
        .identity = identity(view, sidecars),
    };
}

fn identity(
    view: View,
    sidecars: ?[]const LookupAccelerator,
) model.PlanIdentity {
    return .{
        .data_ptr = view.data.ptr,
        .data_len = view.data.len,
        .table_offset = view.offset,
        .table_length = view.length,
        .accelerators_addr = if (sidecars) |lookups|
            @intFromPtr(lookups.ptr)
        else
            0,
        .accelerator_count = if (sidecars) |lookups| lookups.len else 0,
    };
}

fn lookupOffset(
    view: View,
    lookup_list: usize,
    lookup_index: u16,
) Error!usize {
    return table.offset.required16(
        view,
        lookup_list,
        try view.readU16(
            lookup_list + 2 + @as(usize, lookup_index) * 2,
        ),
    );
}

fn hasFeatureTopology(view: View) Error!bool {
    const script_list = try view.readU16(4);
    const feature_list = try view.readU16(6);
    return script_list != 0 and
        feature_list != 0 and
        try view.readU16(script_list) != 0 and
        try view.readU16(feature_list) != 0;
}

fn requiredLookupList(view: View) Error!usize {
    return table.offset.required16(
        view,
        0,
        try readU16ForStructure(view, 8),
    );
}

fn tableView(
    data: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool,
) Error!View {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGpos;
    }
    return .{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = assume_validated,
    };
}

fn readU16ForStructure(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
