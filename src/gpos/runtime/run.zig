//! Whole-run GPOS selection and LookupList traversal.
//!
//! This layer owns state whose lifetime spans every active lookup in one glyph
//! run: option validation, feature selection, profiling intervals, and the
//! shared coverage-digest cache. Concrete lookup execution remains delegated
//! to the lookup dispatcher.

const std = @import("std");
const feature = @import("../feature/root.zig");
const GlyphId = @import("../../glyph.zig").GlyphId;
const lookup_order = @import("../../opentype/lookup_order.zig");
const lookup_dispatcher = @import("lookup/dispatcher/root.zig");
const matching = @import("matching.zig");
const options = @import("options.zig");
const positioning = @import("../positioning/root.zig");
const table = @import("../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const Options = options.Options;
pub const View = table.View;

/// Collect all active positioning adjustments for one post-GSUB glyph run.
pub fn collect(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    return collectImpl(
        data,
        offset,
        length,
        glyphs,
        adjustments,
        allocator,
        run,
        true,
    );
}

pub fn collectAfterMetadataProof(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    return collectImpl(
        data,
        offset,
        length,
        glyphs,
        adjustments,
        allocator,
        run,
        false,
    );
}

fn collectImpl(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
    comptime prove_metadata: bool,
) (Error || std.mem.Allocator.Error)!void {
    const view = try tableView(data, offset, length, run.assume_validated);
    if (prove_metadata) try matching.validate(run, glyphs.len);
    try requireSupportedVersion(view);

    // GPOS shares the OpenType Layout activation graph with GSUB, but its
    // default feature policy is positioning-specific and lives in this
    // feature-selection module.
    const select_start = profileNow(run);
    var selected_owned = if (run.selected_lookups == null)
        try selectedLookupIndices(view, allocator, run)
    else
        std.ArrayList(u16).empty;
    if (run.shape_profile) |profile| {
        profile.gpos_select_ns += profileElapsed(select_start, run);
    }
    defer selected_owned.deinit(allocator);
    const base_selected = run.selected_lookups orelse selected_owned.items;
    var enabled_selected_owned: ?[]u16 = null;
    defer if (enabled_selected_owned) |selected| allocator.free(selected);
    const selected = if (run.enabled_lookups.len == 0)
        base_selected
    else selected: {
        const merged = try lookup_order.mergeEnabled(
            allocator,
            base_selected,
            run.enabled_lookups,
        );
        enabled_selected_owned = merged;
        break :selected merged;
    };
    const has_feature_topology = try hasFeatureTopology(view);

    // An empty selection for a real feature topology means the requested
    // Script/LangSys activates nothing. Low-level callers may retain the
    // historical all-lookup fallback for topology-free test or tooling data.
    if (selected.len == 0 and
        (run.features.len != 0 or
            (!run.apply_all_if_unselected and has_feature_topology)))
    {
        return;
    }

    const apply_start = profileNow(run);
    defer {
        if (run.shape_profile) |profile| {
            profile.gpos_apply_ns += profileElapsed(apply_start, run);
        }
    }
    const lookup_list = try requiredLookupList(view);
    const lookup_count = try view.readU16(lookup_list);
    var digest_cache = lookup_dispatcher.DigestCache.init();
    digest_cache.primeUnfiltered(glyphs);
    if (selected.len != 0) {
        for (selected) |lookup_index| {
            if (lookup_index >= lookup_count) continue;
            try collectLookup(
                view,
                lookup_list,
                lookup_index,
                glyphs,
                adjustments,
                allocator,
                run,
                &digest_cache,
            );
        }
        return;
    }
    for (0..lookup_count) |lookup_index| {
        try collectLookup(
            view,
            lookup_list,
            @intCast(lookup_index),
            glyphs,
            adjustments,
            allocator,
            run,
            &digest_cache,
        );
    }
}

/// Return the canonical active lookup indexes for a source-level run.
pub fn lookupIndicesForOptions(
    data: []const u8,
    offset: usize,
    length: usize,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)![]u16 {
    const view = try tableView(data, offset, length, run.assume_validated);
    try requireSupportedVersion(view);
    var lookups = try selectedLookupIndices(view, allocator, run);
    return lookups.toOwnedSlice(allocator);
}

pub fn selectedLookupIndices(
    view: View,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!std.ArrayList(u16) {
    return feature.run_selection.lookupIndices(view, allocator, run);
}

fn collectLookup(
    view: View,
    lookup_list: usize,
    lookup_index: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
    digest_cache: *lookup_dispatcher.DigestCache,
) (Error || std.mem.Allocator.Error)!void {
    const lookup = cached: {
        if (run.assume_validated) {
            if (run.lookup_accelerators) |accelerators| {
                if (lookup_index < accelerators.len and
                    accelerators[lookup_index].lookup_offset_proved)
                {
                    break :cached accelerators[lookup_index].lookup_offset;
                }
            }
        }
        break :cached try table.offset.required16(
            view,
            lookup_list,
            // LookupList array reads retain scalar EndOfStream behavior; only
            // the mandatory top-level pointer is normalized to BadGpos.
            try view.readU16(
                lookup_list + 2 + @as(usize, lookup_index) * 2,
            ),
        );
    };
    return lookup_dispatcher.collectWithIndex(
        view,
        lookup,
        lookup_index,
        glyphs,
        adjustments,
        allocator,
        run,
        digest_cache,
    );
}

fn tableView(
    data: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool,
) Error!View {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGpos;
    }
    return .{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = assume_validated,
    };
}

fn requireSupportedVersion(view: View) Error!void {
    if (try view.readU16(0) != 1) return error.UnsupportedGpos;
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
    return table.offset.required16(
        view,
        0,
        try readU16ForStructure(view, 8),
    );
}

fn readU16ForStructure(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn profileNow(run: Options) i128 {
    return if (run.shape_profile != null)
        std.Io.Clock.now(.awake, run.profile_io.?).nanoseconds
    else
        0;
}

fn profileElapsed(start: i128, run: Options) i128 {
    return std.Io.Clock.now(.awake, run.profile_io.?).nanoseconds - start;
}
