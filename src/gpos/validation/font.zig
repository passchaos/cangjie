//! Exhaustive font-load validation for one complete GPOS table.
//!
//! Runtime shaping validates only reachable lookup payloads. Font loading must
//! instead prove the entire activation graph and LookupList, including glyph
//! references that no current run happens to visit.

const feature = @import("../feature/root.zig");
const table = @import("../table/root.zig");
const lookup_validation = @import("lookup.zig");

pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const View = table.View;

/// Validate all supported GPOS glyph references against maxp.numGlyphs.
///
/// Unsupported lookup kinds remain ignorable, matching runtime shaping, while
/// malformed supported lookups and out-of-range glyph ids are rejected.
pub fn glyphBounds(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: u16,
) Error!void {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGpos;
    }
    const view = View{
        .data = data,
        .offset = offset,
        .length = length,
        .validating_full_lookup_list = true,
        .glyph_count = glyph_count,
    };
    if (try readU16(view, 0) != 1) return error.UnsupportedGpos;

    const lookup_list = try requiredLookupList(view);
    const lookup_count = try readU16(view, lookup_list);
    try view.ensure(lookup_list + 2, @as(usize, lookup_count) * 2);

    const feature_count =
        try feature.validation.lookupReferences(view, lookup_count);
    try feature.validation.scriptReferences(view, feature_count);

    for (0..lookup_count) |lookup_index| {
        const lookup = try requiredLookupOffset(
            view,
            lookup_list,
            try readU16(
                view,
                lookup_list + 2 + lookup_index * 2,
            ),
        );
        try lookup_validation.headerAndExtensions(view, lookup);
        try lookup_validation.lookupSubtables(
            view,
            lookup,
            try readU16(view, lookup),
            try readU16(view, lookup + 4),
        );
    }
}

pub fn requiredTopLevelOffset(
    view: View,
    field_offset: usize,
) Error!usize {
    // ScriptList, FeatureList, and LookupList are mandatory even when their
    // record counts are zero. A null pointer would alias the GPOS header.
    return table.offset.required16(
        view,
        0,
        try readU16(view, field_offset),
    );
}

pub fn requiredLookupList(view: View) Error!usize {
    return requiredTopLevelOffset(view, 8);
}

pub fn requiredLookupOffset(
    view: View,
    lookup_list: usize,
    relative_offset: u16,
) Error!usize {
    // LookupList children are required. Zero would reinterpret the count and
    // offset array as a Lookup header.
    return table.offset.required16(
        view,
        lookup_list,
        relative_offset,
    );
}

fn readU16(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
