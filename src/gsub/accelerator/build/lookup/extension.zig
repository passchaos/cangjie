//! ExtensionSubst wrapper inspection shared by lookup build and execution.

const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;

/// Return the common wrapped lookup type, or `null` when wrappers are mixed or
/// a subtable is not ExtensionSubst format 1. Recursive type 7 is unsupported
/// because ExtensionSubst is only an addressing layer, never a lookup graph.
pub fn commonType(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
) Error!?u16 {
    var common: ?u16 = null;
    for (0..subtable_count) |subtable_index| {
        const wrapper = lookup_offset +
            try view.readU16(lookup_offset + 6 + subtable_index * 2);
        if (try view.readU16(wrapper) != 1) return null;
        const wrapped_type = try view.readU16(wrapper + 2);
        if (wrapped_type == 7) return error.UnsupportedGsub;
        if (common) |existing| {
            if (existing != wrapped_type) return null;
        } else {
            common = wrapped_type;
        }
    }
    return common;
}

pub fn payload(
    view: View,
    wrapper: usize,
    expected_lookup_type: u16,
) Error!usize {
    if (try view.readU16(wrapper) != 1) return error.UnsupportedGsub;
    const wrapped_type = try view.readU16(wrapper + 2);
    if (wrapped_type == 7 or wrapped_type != expected_lookup_type) {
        return error.UnsupportedGsub;
    }
    return table.offset.extensionPayload(
        view,
        wrapper,
        try view.readU32(wrapper + 4),
    );
}
