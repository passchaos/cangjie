//! Whole-table and per-lookup GSUB accelerator orchestration.

const std = @import("std");
const chaining_coverage = @import("../chaining_coverage/root.zig");
const class_context = @import("../class_context/root.zig");
const context_coverage = @import("../context_coverage.zig");
pub const extension = @import("extension.zig");
const extension_reverse = @import("extension_reverse.zig");
const feature_index = @import("../../feature_index.zig");
pub const header = @import("../../../validation/lookup/header.zig");
const ligature = @import("../ligature/root.zig");
const model = @import("../../model.zig");
const multiple = @import("../multiple.zig");
const ownership = @import("../../ownership.zig");
const single = @import("../single.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Lookup = model.Lookup;
pub const View = table.View;

pub fn build(
    data: []const u8,
    offset: usize,
    length: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]Lookup {
    if (length < 10 or offset > data.len or length > data.len - offset) {
        return error.BadGsub;
    }
    const view = View{
        .data = data,
        .offset = offset,
        .length = length,
        .assume_validated = true,
    };
    if (try view.readU16(0) != 1) return error.UnsupportedGsub;
    if (try isEmptyTopology(view)) return allocator.alloc(Lookup, 0);

    const lookup_list = try table.offset.required16(
        view,
        0,
        try view.readU16(8),
    );
    const lookup_count = try view.readU16(lookup_list);
    const lookups = try allocator.alloc(Lookup, lookup_count);
    @memset(lookups, .{});
    var built_count: usize = 0;
    errdefer {
        ownership.deinitContents(allocator, lookups[0..built_count]);
        allocator.free(lookups);
    }

    var table_uses_run_digest_cache = false;
    var ligature_digest_lookup_count: usize = 0;
    for (lookups, 0..) |*lookup, lookup_index| {
        const lookup_offset = try table.offset.required16(
            view,
            lookup_list,
            try view.readU16(lookup_list + 2 + lookup_index * 2),
        );
        // Runtime dispatch trusts these fixed fields when sidecar identity is
        // exact, so direct public accelerator construction proves the complete
        // lookup header even when the surrounding font was parsed elsewhere.
        _ = try header.validate(view, lookup_offset);
        lookup.* = try one(view, lookup_offset, allocator);
        table_uses_run_digest_cache = table_uses_run_digest_cache or
            (lookup.chaining_coverage_only and
                !lookup.chaining_input_digest.isEmpty());
        if (!lookup.ligature_subst.first_component_digest.isEmpty()) {
            ligature_digest_lookup_count += 1;
        }
        built_count += 1;
    }

    // One ligature lookup already scans the run once. Two or more amortize a
    // shared mutation-aware digest across independent first-component sets.
    table_uses_run_digest_cache =
        table_uses_run_digest_cache or ligature_digest_lookup_count >= 2;
    if (lookups.len != 0) {
        lookups[0].table_uses_run_digest_cache = table_uses_run_digest_cache;
        // Detached low-level fixtures may expose only a LookupList. Feature
        // indexing remains optional when the top-level offset is explicitly
        // zero, while a present FeatureList is parsed strictly.
        if (try view.readU16(6) != 0) {
            lookups[0].feature_index = try feature_index.create(
                view,
                lookups,
                lookup_count,
                allocator,
            );
        }
    }
    return lookups;
}

/// Build one lookup after the caller has proved its fixed header with
/// `header.validate`. Whole-table construction does this before entry; focused
/// tests and internal tooling may use the same two-step contract explicitly.
pub fn one(
    view: View,
    lookup_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Lookup {
    const lookup_type = try view.readU16(lookup_offset);
    const lookup_flag = try view.readU16(lookup_offset + 2);
    const subtable_count = try view.readU16(lookup_offset + 4);
    var lookup = Lookup{
        .lookup_offset = lookup_offset,
        .lookup_type = lookup_type,
        .lookup_flag = lookup_flag,
        .subtable_count = subtable_count,
        .mark_filtering_set = if ((lookup_flag & 0x0010) != 0)
            try view.readU16(
                lookup_offset + 6 + @as(usize, subtable_count) * 2,
            )
        else
            null,
    };
    if (lookup_type == 1 and subtable_count == 1) {
        const subtable = try requiredSubtable(view, lookup_offset, 0);
        lookup.single_subst_entries =
            try single.entries(view, subtable, allocator);
        errdefer allocator.free(lookup.single_subst_entries);
        if (lookup_flag == 0) {
            lookup.single_subst = try single.compact(view, subtable);
        }
    }
    if (lookup_type == 2 and subtable_count == 1) {
        lookup.multiple_subst = try multiple.build(
            view,
            try requiredSubtable(view, lookup_offset, 0),
            allocator,
        );
    }
    if (lookup_type == 4 and subtable_count == 1) {
        lookup.ligature_subst = try ligature.build(
            view,
            try requiredSubtable(view, lookup_offset, 0),
            allocator,
        );
    }
    if (lookup_type == 5) {
        lookup.context_class_subtables = try class_context.context.build(
            view,
            lookup_offset,
            subtable_count,
            .direct,
            allocator,
        );
        if (lookup.context_class_subtables.len != 0) return lookup;
        const coverage = try context_coverage.build(
            view,
            lookup_offset,
            subtable_count,
            allocator,
        );
        lookup.context_coverage_subtables = coverage.subtables;
        lookup.context_coverage_offsets = coverage.coverage_offsets;
        lookup.context_groups = coverage.groups;
        lookup.context_group_slots = coverage.group_slots;
        if (lookup.context_coverage_subtables.len != 0) return lookup;
    }
    if (lookup_type == 7) {
        lookup.extension_lookup_type =
            try extension.commonType(view, lookup_offset, subtable_count);
        if (lookup.extension_lookup_type) |wrapped_type| {
            if (wrapped_type == 6 and
                try chaining_coverage.lookupUsesCoverageOnly(
                    view,
                    lookup_offset,
                    subtable_count,
                    true,
                ))
            {
                var chaining = try chaining_coverage.build(
                    view,
                    lookup_offset,
                    subtable_count,
                    true,
                    lookup.single_subst,
                    lookup.extension_lookup_type,
                    allocator,
                );
                copyDispatch(&chaining, lookup);
                return chaining;
            }
            if (wrapped_type == 5) {
                lookup.context_class_subtables =
                    try class_context.context.build(
                        view,
                        lookup_offset,
                        subtable_count,
                        .extension,
                        allocator,
                    );
                if (lookup.context_class_subtables.len != 0) return lookup;
            }
            if (wrapped_type == 6) {
                lookup.chaining_class_subtables =
                    try class_context.chaining.build(
                        view,
                        lookup_offset,
                        subtable_count,
                        .extension,
                        allocator,
                    );
                if (lookup.chaining_class_subtables.len != 0) return lookup;
            }
            if (wrapped_type == 8) {
                return extension_reverse.build(
                    view,
                    lookup_offset,
                    subtable_count,
                    lookup,
                    allocator,
                );
            }
        }
    }
    if (lookup_type == 6) {
        lookup.chaining_class_subtables = try class_context.chaining.build(
            view,
            lookup_offset,
            subtable_count,
            .direct,
            allocator,
        );
        if (lookup.chaining_class_subtables.len != 0) return lookup;
    }
    if (lookup_type != 6 or
        !try chaining_coverage.lookupUsesCoverageOnly(
            view,
            lookup_offset,
            subtable_count,
            false,
        ))
    {
        return lookup;
    }

    var chaining = try chaining_coverage.build(
        view,
        lookup_offset,
        subtable_count,
        false,
        lookup.single_subst,
        lookup.extension_lookup_type,
        allocator,
    );
    copyDispatch(&chaining, lookup);
    return chaining;
}

fn requiredSubtable(
    view: View,
    lookup_offset: usize,
    subtable_index: usize,
) Error!usize {
    return table.offset.required16(
        view,
        lookup_offset,
        try view.readU16(lookup_offset + 6 + subtable_index * 2),
    );
}

fn copyDispatch(target: *Lookup, source: Lookup) void {
    target.lookup_offset = source.lookup_offset;
    target.lookup_type = source.lookup_type;
    target.lookup_flag = source.lookup_flag;
    target.subtable_count = source.subtable_count;
    target.mark_filtering_set = source.mark_filtering_set;
}

fn isEmptyTopology(view: View) Error!bool {
    return try view.readU16(4) == 0 and
        try view.readU16(6) == 0 and
        try view.readU16(8) == 0;
}
