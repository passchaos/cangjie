//! Ligature provenance and cluster metadata prepared before glyph commit.

const std = @import("std");
const filtering = @import("../../../runtime/filtering.zig");
const Options = @import("../../../runtime/options.zig").Options;
const ligature_provenance = @import("../../../../ligature_provenance.zig");
const model = @import("model.zig");
const shaping_metadata = @import("../../../../shaping_metadata.zig");
const unicode = @import("../../../../unicode.zig");

pub fn componentInfo(
    allocator: std.mem.Allocator,
    run: Options,
    glyph_index: usize,
    match: model.Match,
) std.mem.Allocator.Error!ligature_provenance.Info {
    const store = run.ligature_components orelse return .{};
    const matched_count = @min(
        match.component_count,
        ligature_provenance.max_components,
    );
    if (matched_count <= 1) return .{};

    var all_sources: [ligature_provenance.max_components]usize = undefined;
    var all_source_count: usize = 0;
    var logical_sources: [ligature_provenance.max_components]usize = undefined;
    var logical_count: usize = 0;
    appendSources(
        &all_sources,
        &all_source_count,
        &logical_sources,
        &logical_count,
        run,
        glyph_index,
    );
    var synthetic_base =
        glyph_index < store.infos.items.len and
        store.infos.items[glyph_index].flags.synthetic_base;
    for (1..matched_count) |component_index| {
        const matched_index =
            glyph_index + match.component_offsets[component_index];
        appendSources(
            &all_sources,
            &all_source_count,
            &logical_sources,
            &logical_count,
            run,
            matched_index,
        );
        if (matched_index < store.infos.items.len) {
            synthetic_base = synthetic_base or
                store.infos.items[matched_index].flags.synthetic_base;
        }
    }
    std.debug.assert(logical_count != 0);

    var info = if (all_source_count > 1)
        try store.addLigatureWithSources(
            allocator,
            all_sources[0..all_source_count],
            logical_sources[0..logical_count],
        )
    else
        ligature_provenance.Info{
            .component_count = @intCast(logical_count),
            .flags = .{ .ligated = true },
        };
    info.flags.synthetic_base = synthetic_base;
    info.flags.base_mark_ligature = isBaseWithMarks(
        run,
        glyph_index,
        match,
        matched_count,
    );
    return info;
}

pub fn mergeClusters(
    run: Options,
    glyph_index: usize,
    match: model.Match,
) void {
    const clusters = run.glyph_cluster_indices orelse return;
    if (glyph_index >= clusters.items.len) return;
    if (run.cluster_level.isMonotone()) {
        shaping_metadata.mergeMonotoneClusters(
            clusters.items,
            glyph_index,
            glyph_index + match.match_end,
        );
    }
    mergeFollowingMarks(run, glyph_index, match);
}

fn mergeFollowingMarks(
    run: Options,
    glyph_index: usize,
    match: model.Match,
) void {
    const clusters = run.glyph_cluster_indices orelse return;
    const sources = run.glyph_source_indices orelse return;
    if (glyph_index >= clusters.items.len or
        glyph_index >= sources.items.len or
        match.component_count <= 1)
    {
        return;
    }

    const last_component =
        glyph_index + match.component_offsets[match.component_count - 1];
    if (last_component >= clusters.items.len or
        last_component >= sources.items.len)
    {
        return;
    }
    const last_source = sources.items[last_component];
    const merged_cluster = clusters.items[glyph_index];
    var index = glyph_index + match.match_end;
    while (index < clusters.items.len and index < sources.items.len) : (index += 1) {
        if (sources.items[index] != last_source or
            clusters.items[index] != last_source)
        {
            break;
        }
        clusters.items[index] = merged_cluster;
    }
}

fn appendSources(
    all_sources: []usize,
    all_count: *usize,
    logical_sources: []usize,
    logical_count: *usize,
    run: Options,
    glyph_index: usize,
) void {
    if (all_count.* >= all_sources.len) return;
    var contributes_component = true;
    if (run.ligature_components) |store| {
        if (glyph_index < store.infos.items.len) {
            const info = store.infos.items[glyph_index];
            // Non-first MultipleSubst pieces retain source history but have
            // zero component weight in a later ligature.
            contributes_component =
                !info.flags.multiplied or
                info.flags.multiple_component == 0;
        }
    }
    insertSorted(
        all_sources,
        all_count.*,
        filtering.sourceForGlyph(run, glyph_index),
    );
    all_count.* += 1;
    if (contributes_component and logical_count.* < logical_sources.len) {
        insertSorted(
            logical_sources,
            logical_count.*,
            filtering.sourceForGlyph(run, glyph_index),
        );
        logical_count.* += 1;
    }
}

fn insertSorted(sources: []usize, end: usize, source: usize) void {
    var index = end;
    while (index > 0 and source < sources[index - 1]) : (index -= 1) {
        sources[index] = sources[index - 1];
    }
    sources[index] = source;
}

fn isBaseWithMarks(
    run: Options,
    glyph_index: usize,
    match: model.Match,
    component_count: usize,
) bool {
    const codepoints = run.source_codepoints orelse return false;
    const first_source = filtering.sourceForGlyph(run, glyph_index);
    if (first_source >= codepoints.len or
        unicode.isUnicodeMarkCodepoint(codepoints[first_source]))
    {
        return false;
    }
    for (1..component_count) |component_index| {
        const source = filtering.sourceForGlyph(
            run,
            glyph_index + match.component_offsets[component_index],
        );
        if (source >= codepoints.len or
            !unicode.isUnicodeMarkCodepoint(codepoints[source]))
        {
            return false;
        }
    }
    return true;
}
