//! Owned staged and merged GSUB lookup-plan builders.

const std = @import("std");
const merge = @import("merge.zig");
const model = @import("../model.zig");
const options = @import("../../runtime/options.zig");
const selection = @import("selection.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn lookupPlan(
    view: View,
    applications: []const model.Application,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!model.LookupPlan {
    var items = try selection.collectForRun(view, allocator, run);
    defer items.deinit(allocator);
    const context = try selection.context(view);

    var entries = std.ArrayList(model.LookupPlanEntry).empty;
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.lookups);
            allocator.free(entry.lookup_offsets);
        }
        entries.deinit(allocator);
    }
    for (items.items) |item| {
        if (!item.required or item.index >= context.feature_count) continue;
        const record =
            context.feature_list + 2 + @as(usize, item.index) * 6;
        const required_tag = try view.readU32(record);
        if (selection.contains(applications, required_tag)) continue;
        try appendEntry(
            view,
            required_tag,
            .{ .tag = required_tag },
            items.items,
            context,
            &entries,
            allocator,
            run,
        );
    }
    for (applications) |application| {
        try appendEntry(
            view,
            application.tag,
            application,
            items.items,
            context,
            &entries,
            allocator,
            run,
        );
    }
    return .{ .entries = try entries.toOwnedSlice(allocator) };
}

pub fn mergedPlan(
    view: View,
    applications: []const model.Application,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!model.MergedLookupPlan {
    var items = try selection.collectForRun(view, allocator, run);
    defer items.deinit(allocator);
    const context = try selection.context(view);
    var lookups = std.ArrayList(model.MergedLookup).empty;
    errdefer lookups.deinit(allocator);

    for (items.items) |item| {
        if (!item.required or item.index >= context.feature_count) continue;
        const record =
            context.feature_list + 2 + @as(usize, item.index) * 6;
        const required_tag = try view.readU32(record);
        if (selection.contains(applications, required_tag)) continue;
        const selected = try selection.selectedLookups(
            view,
            required_tag,
            items.items,
            context,
            allocator,
            run,
        );
        defer allocator.free(selected);
        try merge.append(
            &lookups,
            allocator,
            selected,
            .{ .tag = required_tag },
        );
    }
    for (applications) |application| {
        const selected = try selection.selectedLookups(
            view,
            application.tag,
            items.items,
            context,
            allocator,
            run,
        );
        defer allocator.free(selected);
        try merge.append(&lookups, allocator, selected, application);
    }

    merge.canonicalize(&lookups);
    const owned = try lookups.toOwnedSlice(allocator);
    errdefer allocator.free(owned);
    const indices = try allocator.alloc(u16, owned.len);
    defer allocator.free(indices);
    for (owned, indices) |lookup, *index| index.* = lookup.lookup;
    return .{
        .lookups = owned,
        .lookup_offsets = try selection.lookupOffsets(
            view,
            context.lookup_list,
            indices,
            allocator,
        ),
    };
}

fn appendEntry(
    view: View,
    tag: u32,
    application: model.Application,
    items: []const selection.Item,
    context: selection.Context,
    entries: *std.ArrayList(model.LookupPlanEntry),
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    const lookups = try selection.selectedLookups(
        view,
        tag,
        items,
        context,
        allocator,
        run,
    );
    errdefer allocator.free(lookups);
    const offsets = try selection.lookupOffsets(
        view,
        context.lookup_list,
        lookups,
        allocator,
    );
    errdefer allocator.free(offsets);
    try entries.append(allocator, .{
        .application = application,
        .lookups = lookups,
        .lookup_offsets = offsets,
    });
}
