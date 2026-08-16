//! Whole-run GSUB selection, profiling, and LookupList traversal.

const std = @import("std");
pub const cached = @import("cached.zig");
const feature = @import("../../feature/root.zig");
const metadata = @import("../metadata.zig");
const options = @import("../options.zig");
const prefilter = @import("../prefilter/root.zig");
const profile = @import("../../execution/lookup/profile.zig");
const state = @import("../state.zig");
const table = @import("../../table/root.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    try metadata.validate(run, glyphs.items.len);
    var storage = state.Storage{};
    const prepared = try state.prepare(run, glyphs.items.len, &storage);
    const view = View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = prepared.assume_validated,
    };
    if (try view.readU16(0) != 1) return error.UnsupportedGsub;
    if (try isEmpty(view)) return;

    const select_start = profile.now(
        prepared.shape_profile,
        prepared.profile_io,
    );
    var selected_owned = if (prepared.selected_lookups == null) blk: {
        break :blk feature.run_selection.lookupRecords(
            view,
            allocator,
            prepared,
        ) catch |err| {
            if (err == error.BadGsub and try canFallbackSelection(view)) {
                break :blk std.ArrayList(
                    feature.run_selection.SelectedLookup,
                ).empty;
            }
            return err;
        };
    } else std.ArrayList(feature.run_selection.SelectedLookup).empty;
    if (prepared.shape_profile) |active| {
        active.gsub_select_ns += profile.elapsed(
            select_start,
            prepared.profile_io,
        );
    }
    defer selected_owned.deinit(allocator);

    const selected_count = if (prepared.selected_lookups) |selected|
        selected.len
    else
        selected_owned.items.len;
    if (selected_count == 0 and
        (prepared.features.len != 0 or
            (!prepared.apply_all_if_unselected and
                try hasFeatureTopology(view))))
    {
        return;
    }

    const apply_start = profile.now(
        prepared.shape_profile,
        prepared.profile_io,
    );
    defer {
        if (prepared.shape_profile) |active| {
            active.gsub_apply_ns += profile.elapsed(
                apply_start,
                prepared.profile_io,
            );
        }
    }
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    var cache = prefilter.Cache.init();
    if (prepared.selected_lookups) |selected| {
        for (selected) |index| {
            if (index >= lookup_count) continue;
            try applyOne(
                Executor,
                view,
                lookup_list,
                index,
                glyphs,
                allocator,
                prepared,
                &cache,
            );
        }
    } else if (selected_owned.items.len != 0) {
        for (selected_owned.items) |selected| {
            if (selected.index >= lookup_count) continue;
            var selected_run = prepared;
            selected_run.active_feature_value = selected.value;
            selected_run.active_feature_random = selected.random;
            try applyOne(
                Executor,
                view,
                lookup_list,
                selected.index,
                glyphs,
                allocator,
                selected_run,
                &cache,
            );
        }
    } else {
        for (0..lookup_count) |lookup_index| {
            try applyOne(
                Executor,
                view,
                lookup_list,
                @intCast(lookup_index),
                glyphs,
                allocator,
                prepared,
                &cache,
            );
        }
    }
}

fn applyOne(
    comptime Executor: type,
    view: View,
    lookup_list: usize,
    lookup_index: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    cache: *prefilter.Cache,
) Error!void {
    const lookup_offset = try table.offset.required16(
        view,
        lookup_list,
        try view.readU16(
            lookup_list + 2 + @as(usize, lookup_index) * 2,
        ),
    );
    return Executor.applyLookup(
        view,
        lookup_offset,
        lookup_index,
        glyphs,
        allocator,
        run,
        cache,
    );
}

fn isEmpty(view: View) Error!bool {
    return try view.readU16(4) == 0 and
        try view.readU16(6) == 0 and
        try view.readU16(8) == 0;
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
    return table.offset.required16(view, 0, try view.readU16(8));
}

fn canFallbackSelection(view: View) Error!bool {
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    try view.ensure(lookup_list + 2, @as(usize, lookup_count) * 2);
    _ = try feature.validation.lookupReferences(view, lookup_count);
    return true;
}
