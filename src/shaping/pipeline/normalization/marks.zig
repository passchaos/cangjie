//! Modified-combining-class ordering before script-specific GSUB.

const std = @import("std");

const GlyphId = @import("../../../glyph.zig").GlyphId;
const ligature_provenance =
    @import("../../../ligature_provenance.zig");
const shaping_metadata = @import("../../../shaping_metadata.zig");
const pipeline_types = @import("../types.zig");
const unicode = @import("../../../unicode.zig");

pub const Input = struct {
    glyph_ids: *std.ArrayList(GlyphId),
    glyph_source_indices: *std.ArrayList(usize),
    glyph_cluster_indices: *std.ArrayList(usize),
    glyph_substituted: *std.ArrayList(bool),
    ligature_components: *ligature_provenance.Store,
    codepoints: []const u21,
};

pub fn reorder(
    input: Input,
    cluster_level: ?pipeline_types.ClusterLevel,
) void {
    var run_start: ?usize = null;
    for (
        input.glyph_source_indices.items,
        0..,
    ) |source_index, glyph_index| {
        if (sortClass(source_index, input.codepoints) == 0) {
            if (run_start) |start| {
                reorderRun(
                    input,
                    start,
                    glyph_index,
                    cluster_level,
                );
            }
            run_start = null;
            continue;
        }
        if (run_start == null) run_start = glyph_index;
    }
    if (run_start) |start| {
        reorderRun(
            input,
            start,
            input.glyph_source_indices.items.len,
            cluster_level,
        );
    }
}

/// Move Arabic modifier combining marks to the front of their CCC groups.
///
/// HarfBuzz performs this after generic CCC sorting but before joining-mask
/// feature stages. The move updates every glyph-parallel sidecar together.
pub fn reorderArabicModifiers(input: Input) void {
    var run_start: ?usize = null;
    for (
        input.glyph_source_indices.items,
        0..,
    ) |source_index, glyph_index| {
        if (sortClass(source_index, input.codepoints) == 0) {
            if (run_start) |start| {
                reorderArabicModifierRun(input, start, glyph_index);
            }
            run_start = null;
            continue;
        }
        if (run_start == null) run_start = glyph_index;
    }
    if (run_start) |start| {
        reorderArabicModifierRun(
            input,
            start,
            input.glyph_source_indices.items.len,
        );
    }
}

fn reorderRun(
    input: Input,
    start: usize,
    end: usize,
    cluster_level: ?pipeline_types.ClusterLevel,
) void {
    var i = start + 1;
    while (i < end) : (i += 1) {
        var destination = i;
        const current_class = sortClass(
            input.glyph_source_indices.items[i],
            input.codepoints,
        );
        while (destination > start and
            sortClass(
                input.glyph_source_indices.items[destination - 1],
                input.codepoints,
            ) > current_class) : (destination -= 1)
        {}
        if (destination == i) continue;
        if (cluster_level) |level| {
            if (level.isMonotone()) {
                shaping_metadata.mergeMonotoneClusters(
                    input.glyph_cluster_indices.items,
                    destination,
                    i + 1,
                );
            }
        }
        var move_index = i;
        while (move_index > destination) {
            swapAdjacent(input, move_index - 1, move_index);
            move_index -= 1;
        }
    }
}

fn reorderArabicModifierRun(
    input: Input,
    start: usize,
    end: usize,
) void {
    var group_start = start;
    for ([_]u8{ 220, 230 }) |target_class| {
        var index = group_start;
        while (index < end and
            sortClass(
                input.glyph_source_indices.items[index],
                input.codepoints,
            ) < target_class) : (index += 1)
        {}
        if (index == end) break;
        if (sortClass(
            input.glyph_source_indices.items[index],
            input.codepoints,
        ) > target_class) continue;

        var group_end = index;
        while (group_end < end and
            sortClass(
                input.glyph_source_indices.items[group_end],
                input.codepoints,
            ) == target_class and
            input.glyph_source_indices.items[group_end] <
                input.codepoints.len and
            isArabicModifier(
                input.codepoints[
                    input.glyph_source_indices.items[group_end]
                ],
            )) : (group_end += 1)
        {}

        if (group_end == index) continue;
        var move_index = index;
        while (move_index < group_end) : (move_index += 1) {
            shaping_metadata.move(
                input.glyph_ids,
                input.glyph_source_indices,
                input.glyph_cluster_indices,
                input.glyph_substituted,
                input.ligature_components,
                move_index,
                group_start,
            );
            group_start += 1;
        }
    }
}

fn swapAdjacent(input: Input, a: usize, b: usize) void {
    std.mem.swap(
        GlyphId,
        &input.glyph_ids.items[a],
        &input.glyph_ids.items[b],
    );
    std.mem.swap(
        usize,
        &input.glyph_source_indices.items[a],
        &input.glyph_source_indices.items[b],
    );
    std.mem.swap(
        usize,
        &input.glyph_cluster_indices.items[a],
        &input.glyph_cluster_indices.items[b],
    );
    std.mem.swap(
        bool,
        &input.glyph_substituted.items[a],
        &input.glyph_substituted.items[b],
    );
    std.mem.swap(
        ligature_provenance.Info,
        &input.ligature_components.infos.items[a],
        &input.ligature_components.infos.items[b],
    );
}

fn isArabicModifier(codepoint: u21) bool {
    return switch (codepoint) {
        0x0654,
        0x0655,
        0x0658,
        0x06dc,
        0x06e3,
        0x06e7,
        0x06e8,
        0x08ca,
        0x08cb,
        0x08cd,
        0x08ce,
        0x08cf,
        0x08d3,
        0x08f3,
        => true,
        else => false,
    };
}

fn sortClass(source_index: usize, codepoints: []const u21) u8 {
    if (source_index >= codepoints.len) return 0;
    return unicode.modifiedCombiningClassForShaping(codepoints[source_index]);
}

test "mark reorder merges explicit monotone clusters" {
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 1, 2 });
    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1 });
    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 2 });
    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(
        std.testing.allocator,
        &.{ false, false },
    );
    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.appendSlice(
        std.testing.allocator,
        &.{ .{}, .{} },
    );
    const codepoints = [_]u21{ 0x05bc, 0x05c1 };

    reorderRun(.{
        .glyph_ids = &glyphs,
        .glyph_source_indices = &sources,
        .glyph_cluster_indices = &clusters,
        .glyph_substituted = &substituted,
        .ligature_components = &ligatures,
        .codepoints = &codepoints,
    }, 0, 2, .monotone_characters);

    try std.testing.expectEqualSlices(
        usize,
        &.{ 1, 0 },
        sources.items,
    );
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 0 },
        clusters.items,
    );
}
