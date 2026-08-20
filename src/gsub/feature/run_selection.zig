//! Run-specific GSUB feature policy and lookup canonicalization.
//!
//! Script/LangSys resolution supplies candidate FeatureRecords. This module
//! applies source-level run options, FeatureVariations, required-feature
//! semantics, vertical global search, and lookup-order canonicalization.

const std = @import("std");
const model = @import("model.zig");
const options = @import("../runtime/options.zig");
const selection = @import("selection.zig");
const table = @import("../table/root.zig");
const unicode = @import("../../unicode.zig");
const variations = @import("variations.zig");

pub const Error = table.view.Error || error{UnsupportedGsub};
pub const Options = options.Options;
pub const View = table.View;

pub const SelectedLookup = struct {
    index: u16,
    value: u32 = 1,
    random: bool = false,
};

pub fn lookupIndices(
    view: View,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var selected = try lookupRecords(view, allocator, run);
    defer selected.deinit(allocator);
    var lookups = std.ArrayList(u16).empty;
    errdefer lookups.deinit(allocator);
    try lookups.ensureUnusedCapacity(allocator, selected.items.len);
    for (selected.items) |item| lookups.appendAssumeCapacity(item.index);
    return lookups;
}

pub fn lookupRecords(
    view: View,
    allocator: std.mem.Allocator,
    run: Options,
) (Error || std.mem.Allocator.Error)!std.ArrayList(SelectedLookup) {
    var feature_indices = std.ArrayList(selection.Item).empty;
    defer feature_indices.deinit(allocator);
    var lookups = std.ArrayList(SelectedLookup).empty;
    errdefer lookups.deinit(allocator);

    const script_list = try requiredTopLevelOffset(view, 4);
    const feature_list = try requiredTopLevelOffset(view, 6);
    const script_offset = (try selection.script(
        view,
        script_list,
        run.script_tag,
    )) orelse 0;
    if (script_offset != 0) {
        try selection.collect(
            view,
            script_offset,
            run.language_tag,
            &feature_indices,
            allocator,
        );
    }

    const feature_count = try view.readU16(feature_list);
    if (!view.assume_validated) {
        try selection.validateFeatureRecords(
            view,
            feature_list,
            feature_count,
        );
    }
    const variation_index = try variations.matchingRecord(
        view,
        run.normalized_variation_coords,
    );
    var active_langsys_has_vert = false;
    for (feature_indices.items) |candidate| {
        if (candidate.index >= feature_count) continue;
        const record =
            feature_list + 2 + @as(usize, candidate.index) * 6;
        const tag = try view.readU32(record);
        active_langsys_has_vert =
            active_langsys_has_vert or tag == unicode.tag("vert");
        // LangSys.ReqFeatureIndex is mandatory even when an override disables
        // the same tag or the tag is not normally enabled by default.
        if (!candidate.required and !enabled(tag, run)) continue;
        const value = if (candidate.required) 1 else featureValue(tag, run);
        try appendFeatureLookups(
            view,
            feature_list,
            candidate.index,
            record,
            variation_index,
            value,
            !candidate.required and
                tag == unicode.tag("rand") and
                value == model.random_value,
            &lookups,
            allocator,
        );
    }

    // HarfBuzz treats `vert` as F_GLOBAL_SEARCH. Old CJK fonts often place it
    // only under `kana`, while Common punctuation resolves to no Script entry.
    if (run.vertical and
        !active_langsys_has_vert and
        enabled(unicode.tag("vert"), run))
    {
        for (0..feature_count) |feature_index| {
            const record = feature_list + 2 + feature_index * 6;
            if (try view.readU32(record) != unicode.tag("vert")) continue;
            try appendFeatureLookups(
                view,
                feature_list,
                @intCast(feature_index),
                record,
                variation_index,
                featureValue(unicode.tag("vert"), run),
                false,
                &lookups,
                allocator,
            );
            break;
        }
    }

    sortUniqueRecords(&lookups);
    return lookups;
}

pub fn enabled(feature_tag: u32, run: Options) bool {
    for (run.features) |override| {
        if (override.tag == feature_tag) return override.enabled;
    }
    if (feature_tag == unicode.tag("rand")) return true;
    return defaultEnabled(feature_tag) or
        (run.script_tag == .tibt and
            (feature_tag == unicode.tag("abvs") or
                feature_tag == unicode.tag("blws"))) or
        (run.vertical and
            (feature_tag == unicode.tag("vert") or
                feature_tag == unicode.tag("vrt2"))) or
        (run.text_direction == .ltr and
            (feature_tag == unicode.tag("ltra") or
                feature_tag == unicode.tag("ltrm"))) or
        (run.text_direction == .rtl and
            (feature_tag == unicode.tag("rtla") or
                feature_tag == unicode.tag("rtlm")));
}

pub fn featureValue(feature_tag: u32, run: Options) u32 {
    for (run.features) |override| {
        if (override.tag == feature_tag) return override.effectiveValue();
    }
    if (feature_tag == unicode.tag("rand")) return model.random_value;
    return 1;
}

pub fn defaultEnabled(feature_tag: u32) bool {
    return feature_tag == unicode.tag("ccmp") or
        feature_tag == unicode.tag("locl") or
        feature_tag == unicode.tag("rvrn") or
        feature_tag == unicode.tag("rlig") or
        feature_tag == unicode.tag("liga") or
        feature_tag == unicode.tag("clig") or
        feature_tag == unicode.tag("calt") or
        feature_tag == unicode.tag("rclt");
}

pub fn sortUniqueIndices(lookups: *std.ArrayList(u16)) void {
    if (lookups.items.len < 2) return;
    std.sort.heap(u16, lookups.items, {}, lessIndex);
    var write: usize = 1;
    var previous = lookups.items[0];
    for (lookups.items[1..]) |lookup_index| {
        if (lookup_index == previous) continue;
        lookups.items[write] = lookup_index;
        write += 1;
        previous = lookup_index;
    }
    lookups.shrinkRetainingCapacity(write);
}

/// Merge JSTF-enabled indexes into a value-aware active selection.
///
/// Existing records retain alternate values and random-feature state. Newly
/// enabled lookups use the OpenType default value, and canonicalization merges
/// duplicates without erasing richer state from an already-active feature.
pub fn mergeEnabledRecords(
    lookups: *std.ArrayList(SelectedLookup),
    allocator: std.mem.Allocator,
    enabled_lookups: []const u16,
) std.mem.Allocator.Error!void {
    try lookups.ensureUnusedCapacity(allocator, enabled_lookups.len);
    for (enabled_lookups) |index| {
        lookups.appendAssumeCapacity(.{ .index = index });
    }
    sortUniqueRecords(lookups);
}

fn appendFeatureLookups(
    view: View,
    feature_list: usize,
    feature_index: u16,
    feature_record: usize,
    variation_index: ?usize,
    value: u32,
    random: bool,
    lookups: *std.ArrayList(SelectedLookup),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    const default_feature = try table.offset.required16(
        view,
        feature_list,
        try view.readU16(feature_record + 4),
    );
    const feature_offset = if (variation_index) |record_index|
        try variations.substitutedFeatureOffset(
            view,
            record_index,
            feature_index,
        ) orelse default_feature
    else
        default_feature;
    const lookup_count = try view.readU16(feature_offset + 2);
    for (0..lookup_count) |lookup_index| {
        try lookups.append(allocator, .{
            .index = try view.readU16(feature_offset + 4 + lookup_index * 2),
            .value = value,
            .random = random,
        });
    }
}

fn sortUniqueRecords(lookups: *std.ArrayList(SelectedLookup)) void {
    if (lookups.items.len < 2) return;
    std.sort.heap(SelectedLookup, lookups.items, {}, lessSelected);
    var write: usize = 1;
    var previous = lookups.items[0];
    for (lookups.items[1..]) |lookup| {
        if (lookup.index == previous.index) {
            if (lookups.items[write - 1].value == 1) {
                lookups.items[write - 1].value = lookup.value;
            }
            lookups.items[write - 1].random =
                lookups.items[write - 1].random or lookup.random;
        } else {
            lookups.items[write] = lookup;
            write += 1;
            previous = lookup;
        }
    }
    lookups.shrinkRetainingCapacity(write);
}

fn requiredTopLevelOffset(view: View, field_offset: usize) Error!usize {
    return table.offset.required16(
        view,
        0,
        try view.readU16(field_offset),
    );
}

fn lessIndex(_: void, lhs: u16, rhs: u16) bool {
    return lhs < rhs;
}

fn lessSelected(_: void, lhs: SelectedLookup, rhs: SelectedLookup) bool {
    return lhs.index < rhs.index;
}
