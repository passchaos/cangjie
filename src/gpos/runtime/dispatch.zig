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
    if (view.assume_validated) {
        if (acceleratorAny(lookup_index, run)) |cached| {
            if (cached.lookup_offset == lookup_offset and
                cached.lookup_type != 0)
            {
                return .{
                    .lookup_type = cached.lookup_type,
                    .lookup_flag = cached.lookup_flag,
                    .subtable_count = cached.subtable_count,
                    .mark_filtering_set = cached.mark_filtering_set,
                };
            }
        }
    }
    return positioning.lookup.dispatch.header(view, lookup_offset);
}

pub fn acceleratorWithCoverage(
    lookup_index: ?u16,
    run: Options,
) ?*const accelerator.Lookup {
    const cached = acceleratorAny(lookup_index, run) orelse return null;
    if (cached.coverage_digest.isEmpty()) return null;
    return cached;
}

pub fn acceleratorAny(
    lookup_index: ?u16,
    run: Options,
) ?*const accelerator.Lookup {
    const accelerators = run.lookup_accelerators orelse return null;
    const index = lookup_index orelse return null;
    if (index >= accelerators.len) return null;
    return &accelerators[index];
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
        if (acceleratorAny(lookup_index, run)) |cached| {
            // Prove all dispatch fields before trusting a table-derived cached
            // extension type; foreign or stale sidecars fall back to parsing.
            if (cached.lookup_offset == lookup_offset and
                cached.lookup_type == lookup_type and
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
