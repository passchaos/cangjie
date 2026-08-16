//! Lookup-local state preparation before GPOS execution.
//!
//! Most lookups borrow the caller's immutable run options unchanged. Only
//! UseMarkFilteringSet needs a lookup-local copy because the active set index
//! lives in the Lookup header rather than in run-wide shaping state.

const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const runtime_dispatch = @import("../../dispatch.zig");
const shape_profile = @import("../../../../shape_profile.zig");
const table = @import("../../../table/root.zig");

pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const Header = runtime_dispatch.Header;
pub const Options = options.Options;
pub const View = table.View;

/// Resolve a Lookup header and account for its concrete kind in profiling.
pub fn header(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    run: Options,
) Error!Header {
    const resolved = try runtime_dispatch.header(
        view,
        lookup_offset,
        lookup_index,
        run,
    );
    recordProfile(run.shape_profile, resolved.lookup_type);
    return resolved;
}

/// Build the exceptional lookup-local options required by mark filtering.
///
/// Returning `null` keeps ordinary lookups on the direct borrowed-options
/// path; callers only materialize and pass a copied `Options` value when bit 4
/// is present in the LookupFlag.
pub fn markFilteringOptions(
    resolved: Header,
    run: Options,
) Error!?Options {
    if (!usesMarkFilteringSet(resolved.lookup_flag)) return null;

    var customized = run;
    customized.active_mark_filtering_set = resolved.mark_filtering_set;
    try matching.validateMarkFilteringSetIndex(customized);
    return customized;
}

pub fn usesMarkFilteringSet(lookup_flag: u16) bool {
    return (lookup_flag & 0x0010) != 0;
}

fn recordProfile(
    profile: ?*shape_profile.ShapeStageProfile,
    lookup_type: u16,
) void {
    const active = profile orelse return;
    active.gpos_lookup_count += 1;
    switch (lookup_type) {
        1 => active.gpos_single_lookup_count += 1,
        2 => active.gpos_pair_lookup_count += 1,
        4, 5, 6 => active.gpos_mark_lookup_count += 1,
        7, 8 => active.gpos_context_lookup_count += 1,
        9 => active.gpos_extension_lookup_count += 1,
        else => {},
    }
}
