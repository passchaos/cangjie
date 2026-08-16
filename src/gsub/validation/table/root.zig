//! Whole-table GSUB structural and glyph-bound validation.

const feature = @import("../../feature/root.zig");
const service = @import("../../table/service.zig");
const table = @import("../../table/root.zig");
const validation = @import("../root.zig");

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded };
pub const View = table.View;

pub const Mode = enum {
    /// Font-load validation rejects every malformed authored child.
    strict,
    /// Shaping admits the documented compatibility exceptions and temporary
    /// SingleSubst delta outputs used by later lookups.
    shaping,
};

pub fn glyphBounds(
    comptime Executor: type,
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: u16,
    mode: Mode,
) Error!void {
    var view = try service.view(data, offset, length, false);
    view.glyph_count = glyph_count;
    view.allow_transient_single_delta = mode == .shaping;
    if (try service.isEmpty(view)) return;

    const lookup_list = try service.requiredLookupList(view);
    const lookup_count = try service.read(view, lookup_list);
    try view.ensure(
        lookup_list + 2,
        @as(usize, lookup_count) * 2,
    );
    const feature_count =
        try feature.validation.lookupReferences(view, lookup_count);
    if (mode == .strict) {
        try feature.validation.scriptReferences(view, feature_count);
    } else {
        feature.validation.scriptReferences(view, feature_count) catch {};
    }

    for (0..lookup_count) |lookup_index| {
        const lookup_offset = try service.requiredLookup(
            view,
            lookup_list,
            try service.read(
                view,
                lookup_list + 2 + lookup_index * 2,
            ),
        );
        const lookup_type = try validation.lookup.validateHeader(
            Executor,
            view,
            lookup_offset,
        );
        try validation.lookup.validateSubtables(
            Executor,
            view,
            lookup_offset,
            lookup_type,
            try service.read(view, lookup_offset + 4),
            if (mode == .strict) .strict else .shaping,
        );
    }
}
