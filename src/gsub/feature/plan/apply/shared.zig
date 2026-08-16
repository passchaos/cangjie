//! Shared lookup invocation for feature-plan application.

const std = @import("std");
const model = @import("../../model.zig");
const options = @import("../../../runtime/options.zig");
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
    view: View,
    lookup_count: u16,
    plan_entry: model.LookupPlanEntry,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    cache: *RunDigestCache,
) Error!void {
    if (plan_entry.lookup_offsets.len != plan_entry.lookups.len) {
        return error.BadGsub;
    }
    for (plan_entry.lookups, plan_entry.lookup_offsets) |index, offset| {
        if (index >= lookup_count) return error.BadGsub;
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
