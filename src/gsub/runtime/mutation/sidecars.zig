//! Allocation-preflight and commit details for GSUB metadata sidecars.

const std = @import("std");
const filtering = @import("../filtering.zig");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const options = @import("../options.zig");

pub const Options = options.Options;

pub const Prepared = struct {
    run: Options,
    glyph_index: usize,
    removed_len: usize,
    inserted_len: usize,
    source: usize,
    cluster: usize,
    component_info: ligature_provenance.Info,

    pub fn commit(prepared: Prepared) void {
        const run = prepared.run;
        if (run.glyph_source_indices) |items| {
            replaceRepeated(
                usize,
                items,
                prepared.glyph_index,
                prepared.removed_len,
                prepared.inserted_len,
                prepared.source,
            );
        }
        if (run.glyph_cluster_indices) |items| {
            replaceRepeated(
                usize,
                items,
                prepared.glyph_index,
                prepared.removed_len,
                prepared.inserted_len,
                prepared.cluster,
            );
        }
        if (run.glyph_substituted) |items| {
            replaceRepeated(
                bool,
                items,
                prepared.glyph_index,
                prepared.removed_len,
                prepared.inserted_len,
                true,
            );
        }
        if (run.glyph_stage_substituted) |items| {
            replaceRepeated(
                bool,
                items,
                prepared.glyph_index,
                prepared.removed_len,
                prepared.inserted_len,
                true,
            );
        }
        if (run.ligature_components) |store| {
            replaceProvenance(
                &store.infos,
                prepared.glyph_index,
                prepared.removed_len,
                prepared.inserted_len,
                prepared.component_info,
            );
        }
    }
};

pub fn prepare(
    allocator: std.mem.Allocator,
    run: Options,
    glyph_index: usize,
    removed_len: usize,
    inserted_len: usize,
    source: usize,
) std.mem.Allocator.Error!Prepared {
    const cluster = filtering.clusterForGlyph(run, glyph_index);
    var component_info: ligature_provenance.Info =
        if (run.ligature_components) |store|
            if (glyph_index < store.infos.items.len)
                store.infos.items[glyph_index]
            else
                .{}
        else
            .{};
    if (inserted_len > 1) {
        component_info.flags.multiplied = true;
        component_info.flags.multiple_component = 0;
    }

    if (run.glyph_source_indices) |items| {
        try ensureReplacementCapacity(
            usize,
            allocator,
            items,
            glyph_index,
            removed_len,
            inserted_len,
        );
    }
    if (run.glyph_cluster_indices) |items| {
        try ensureReplacementCapacity(
            usize,
            allocator,
            items,
            glyph_index,
            removed_len,
            inserted_len,
        );
    }
    if (run.glyph_substituted) |items| {
        try ensureReplacementCapacity(
            bool,
            allocator,
            items,
            glyph_index,
            removed_len,
            inserted_len,
        );
    }
    if (run.glyph_stage_substituted) |items| {
        try ensureReplacementCapacity(
            bool,
            allocator,
            items,
            glyph_index,
            removed_len,
            inserted_len,
        );
    }
    if (run.ligature_components) |store| {
        try ensureReplacementCapacity(
            ligature_provenance.Info,
            allocator,
            &store.infos,
            glyph_index,
            removed_len,
            inserted_len,
        );
    }

    return .{
        .run = run,
        .glyph_index = glyph_index,
        .removed_len = removed_len,
        .inserted_len = inserted_len,
        .source = source,
        .cluster = cluster,
        .component_info = component_info,
    };
}

pub fn remove(run: Options, glyph_index: usize, removed_len: usize) void {
    Prepared.commit(.{
        .run = run,
        .glyph_index = glyph_index,
        .removed_len = removed_len,
        .inserted_len = 0,
        .source = 0,
        .cluster = 0,
        .component_info = .{},
    });
}

fn ensureReplacementCapacity(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: *std.ArrayList(T),
    index: usize,
    removed_len: usize,
    inserted_len: usize,
) std.mem.Allocator.Error!void {
    if (index > items.items.len) return;
    const removed = boundedRemoval(items.items.len, index, removed_len);
    const target = std.math.add(
        usize,
        items.items.len - removed,
        inserted_len,
    ) catch return error.OutOfMemory;
    try items.ensureTotalCapacity(allocator, target);
}

fn replaceRepeated(
    comptime T: type,
    items: *std.ArrayList(T),
    index: usize,
    removed_len: usize,
    inserted_len: usize,
    value: T,
) void {
    if (index > items.items.len) return;
    const removed = boundedRemoval(items.items.len, index, removed_len);
    replaceRangeRepeatedAssumeCapacity(
        T,
        items,
        index,
        removed,
        inserted_len,
        value,
    );
}

fn replaceProvenance(
    items: *std.ArrayList(ligature_provenance.Info),
    index: usize,
    removed_len: usize,
    inserted_len: usize,
    base: ligature_provenance.Info,
) void {
    if (index > items.items.len) return;
    const removed = boundedRemoval(items.items.len, index, removed_len);
    const tail_start = index + removed;
    const old_len = items.items.len;
    const new_len = old_len - removed + inserted_len;
    const tail = items.items[tail_start..old_len];
    items.items.len = new_len;
    @memmove(items.items[index + inserted_len .. new_len], tail);
    for (items.items[index .. index + inserted_len], 0..) |*item, item_index| {
        item.* = base;
        item.flags.multiple_component = @intCast(@min(item_index, 0x0f));
    }
}

fn replaceRangeRepeatedAssumeCapacity(
    comptime T: type,
    items: *std.ArrayList(T),
    index: usize,
    removed_len: usize,
    inserted_len: usize,
    value: T,
) void {
    const tail_start = index + removed_len;
    const old_len = items.items.len;
    const new_len = old_len - removed_len + inserted_len;
    const tail = items.items[tail_start..old_len];
    items.items.len = new_len;
    @memmove(items.items[index + inserted_len .. new_len], tail);
    @memset(items.items[index .. index + inserted_len], value);
}

fn boundedRemoval(length: usize, index: usize, requested: usize) usize {
    if (index > length) return 0;
    return @min(requested, length - index);
}
