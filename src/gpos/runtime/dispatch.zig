//! Runtime lookup dispatch with validated accelerator identity checks.

const accelerator = @import("../accelerator/root.zig");
const positioning = @import("../positioning/root.zig");
const options = @import("options.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;
pub const Options = options.Options;
pub const Header = positioning.lookup.dispatch.Header;

pub fn header(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    run: Options,
) Error!Header {
    const parsed = try positioning.lookup.dispatch.header(view, lookup_offset);
    if (exact(
        view,
        lookup_offset,
        parsed.lookup_type,
        parsed.subtable_count,
        lookup_index,
        run,
    )) |cached| {
        return .{
            .lookup_type = cached.lookup_type,
            .lookup_flag = cached.lookup_flag,
            .subtable_count = cached.subtable_count,
            .mark_filtering_set = cached.mark_filtering_set,
        };
    }
    return parsed;
}

pub inline fn withCoverage(
    cached: ?*const accelerator.Lookup,
) ?*const accelerator.Lookup {
    const lookup = cached orelse return null;
    if (lookup.coverage_digest.isEmpty()) return null;
    return lookup;
}

/// Return the complete sidecar slice only when it belongs to this exact
/// validated GPOS range and still occupies its original allocation.
///
/// This is an allocation/range identity check, not a content hash or a
/// lifetime guard. The API contract requires both allocations to remain alive
/// and immutable before this function may inspect them.
pub inline fn exactSidecars(
    view: View,
    run: Options,
) ?[]const accelerator.Lookup {
    if (!view.assume_validated) return null;
    const accelerators = run.lookup_accelerators orelse return null;
    if (accelerators.len == 0) return null;
    const identity = accelerators[0].table_identity orelse return null;
    if (identity.data_ptr != view.data.ptr or
        identity.data_len != view.data.len or
        identity.table_offset != view.offset or
        identity.table_length != view.length or
        identity.accelerators_addr != @intFromPtr(accelerators.ptr) or
        identity.accelerator_count != accelerators.len)
    {
        return null;
    }
    return accelerators;
}

pub inline fn lookupInExactSidecars(
    accelerators: []const accelerator.Lookup,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    lookup_index: ?u16,
) ?*const accelerator.Lookup {
    const index = lookup_index orelse return null;
    if (index >= accelerators.len) return null;
    const cached = &accelerators[index];
    if (cached.lookup_offset != lookup_offset or
        cached.lookup_type != lookup_type or
        cached.subtable_count != subtable_count)
    {
        return null;
    }
    return cached;
}

pub inline fn exact(
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    lookup_index: ?u16,
    run: Options,
) ?*const accelerator.Lookup {
    return lookupInExactSidecars(
        exactSidecars(view, run) orelse return null,
        lookup_offset,
        lookup_type,
        subtable_count,
        lookup_index,
    );
}

pub fn resolvedExtensionType(
    view: View,
    lookup_offset: usize,
    lookup_type: u16,
    subtable_count: u16,
    lookup_index: ?u16,
    run: Options,
) Error!?u16 {
    if (view.assume_validated) {
        if (exact(
            view,
            lookup_offset,
            lookup_type,
            subtable_count,
            lookup_index,
            run,
        )) |cached| {
            // Prove all dispatch fields before trusting a table-derived cached
            // extension type; foreign or stale sidecars fall back to parsing.
            if (cached.lookup_type == lookup_type and
                cached.subtable_count == subtable_count)
            {
                return cached.extension_lookup_type;
            }
        }
    }
    return positioning.lookup.dispatch.commonExtensionType(
        view,
        lookup_offset,
        subtable_count,
    );
}
