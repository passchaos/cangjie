//! Feature-specific lookup selection for staged GSUB plans.
//!
//! Run-wide default policy lives in `run_selection.zig`. This module resolves
//! exactly one requested feature from an already selected Script/LangSys,
//! including FeatureVariations and the exact cached feature-index fast path.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const options = @import("../../runtime/options.zig");
const feature_selection = @import("../selection.zig");
const run_selection = @import("../run_selection.zig");
const table = @import("../../table/root.zig");
const variations = @import("../variations.zig");

pub const Error = table.coverage.Error;
pub const Item = feature_selection.Item;
pub const Options = options.Options;
pub const View = table.View;

pub const Context = struct {
    feature_list: usize,
    feature_count: u16,
    lookup_list: usize,
    lookup_count: u16,
};

pub fn context(view: View) Error!Context {
    const feature_list = try table.offset.required16(
        view,
        0,
        try view.readU16(6),
    );
    const lookup_list = try table.offset.required16(
        view,
        0,
        try view.readU16(8),
    );
    return .{
        .feature_list = feature_list,
        .feature_count = try view.readU16(feature_list),
        .lookup_list = lookup_list,
        .lookup_count = try view.readU16(lookup_list),
    };
}

pub fn collectForRun(
    view: View,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!std.ArrayList(Item) {
    var items = std.ArrayList(Item).empty;
    errdefer items.deinit(allocator);
    const script_list = try table.offset.required16(
        view,
        0,
        try view.readU16(4),
    );
    const script_offset = (try feature_selection.script(
        view,
        script_list,
        run.script_tag,
    )) orelse return items;
    try feature_selection.collect(
        view,
        script_offset,
        run.language_tag,
        &items,
        allocator,
    );
    return items;
}

pub fn selectedLookups(
    view: View,
    feature_tag: u32,
    items: []const Item,
    plan_context: Context,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)![]u16 {
    if (borrowedLookups(
        view,
        feature_tag,
        items,
        plan_context.feature_count,
        run,
    )) |borrowed| {
        return allocator.dupe(u16, borrowed);
    }
    return selectedLookupsOwned(
        view,
        feature_tag,
        items,
        plan_context,
        allocator,
        run,
    );
}

pub fn borrowedLookups(
    view: View,
    feature_tag: u32,
    items: []const Item,
    feature_count: u16,
    run: Options,
) ?[]const u16 {
    if (run.normalized_variation_coords.len != 0) return null;
    if (!view.assume_validated or items.len == 0) return null;
    const sidecars = run.lookup_accelerators orelse return null;
    const index = accelerator.feature_index.exact(
        view.data,
        view.offset,
        view.length,
        sidecars,
    ) orelse return null;
    return accelerator.feature_index.selectedLookups(
        index,
        feature_tag,
        items,
        feature_count,
    );
}

pub fn selectedLookupsOwned(
    view: View,
    feature_tag: u32,
    items: []const Item,
    plan_context: Context,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)![]u16 {
    var selected = std.ArrayList(u16).empty;
    errdefer selected.deinit(allocator);
    const variation_index = try variations.matchingRecord(
        view,
        run.normalized_variation_coords,
    );
    for (items) |item| {
        if (item.index >= plan_context.feature_count) continue;
        const record =
            plan_context.feature_list + 2 + @as(usize, item.index) * 6;
        if (try view.readU32(record) != feature_tag) continue;
        const default_feature = try table.offset.required16(
            view,
            plan_context.feature_list,
            try view.readU16(record + 4),
        );
        const feature_offset = if (variation_index) |record_index|
            try variations.substitutedFeatureOffset(
                view,
                record_index,
                item.index,
            ) orelse default_feature
        else
            default_feature;
        const lookup_count = try view.readU16(feature_offset + 2);
        for (0..lookup_count) |lookup_index| {
            const index = try view.readU16(
                feature_offset + 4 + lookup_index * 2,
            );
            if (index >= plan_context.lookup_count) return error.BadGsub;
            try selected.append(allocator, index);
        }
    }
    run_selection.sortUniqueIndices(&selected);
    return selected.toOwnedSlice(allocator);
}

pub fn lookupOffsets(
    view: View,
    lookup_list: usize,
    lookups: []const u16,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]usize {
    const offsets = try allocator.alloc(usize, lookups.len);
    errdefer allocator.free(offsets);
    for (lookups, offsets) |lookup_index, *lookup_offset| {
        lookup_offset.* = try table.offset.required16(
            view,
            lookup_list,
            try view.readU16(
                lookup_list + 2 + @as(usize, lookup_index) * 2,
            ),
        );
    }
    return offsets;
}

pub fn contains(applications: []const @import("../model.zig").Application, tag: u32) bool {
    for (applications) |application| {
        if (application.tag == tag) return true;
    }
    return false;
}
