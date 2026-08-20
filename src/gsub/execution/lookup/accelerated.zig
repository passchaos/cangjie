//! Trusted GSUB lookup dispatch through parsed accelerator sidecars.
//!
//! The caller proves exact table identity before entering this module. A
//! capability miss returns `false` so the defensive generic dispatcher can
//! preserve complete lookup-kind support without duplicating it here.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const contextual_context =
    @import("../contextual/context/root.zig");
const direct_ligature = @import("../direct/ligature/root.zig");
const filtering = @import("../../runtime/filtering.zig");
const options = @import("../../runtime/options.zig");
const prefilter = @import("../../runtime/prefilter/root.zig");
const profile = @import("profile.zig");
const runtime_dispatch = @import("../../runtime/dispatch.zig");
const table = @import("../../table/root.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Lookup = accelerator.Lookup;
pub const Options = options.Options;
pub const RunDigestCache = prefilter.Cache;
pub const View = table.View;

/// Execute an accelerated lookup when its sidecar has a complete strategy.
///
/// `Executor.applyChainingLookup` is comptime-bound because coverage chaining
/// can recursively execute contextual records. This keeps the module boundary
/// source-level and statically dispatched: no erased context or runtime
/// function pointer is introduced to break the dependency graph.
pub fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: ?*RunDigestCache,
) Error!bool {
    const sidecar =
        runtime_dispatch.any(lookup_index, run) orelse return false;
    if (sidecar.lookup_offset != lookup_offset or sidecar.lookup_type == 0) {
        return false;
    }
    const lookup_start = profile.now(run.shape_profile, run.profile_io);
    const glyph_count_before =
        if (run.shape_profile != null) glyphs.items.len else 0;

    const scoped_syllable =
        runtime_dispatch.matchesSourceSyllable(lookup_index, run);
    if (runtime_dispatch.needsCustomizedOptions(
        sidecar.lookup_flag,
        scoped_syllable,
        run,
    )) {
        // Options owns all source-parallel shaping metadata and is deliberately
        // large. Copy it only for the exceptional lookup-local overrides.
        var customized = run;
        if ((sidecar.lookup_flag & 0x0010) != 0) {
            customized.active_mark_filtering_set =
                sidecar.mark_filtering_set;
            try filtering.validateMarkFilteringSetIndex(customized);
        }
        customized.match_source_syllable = scoped_syllable;
        return applyPrepared(
            Executor,
            view,
            lookup_offset,
            lookup_index,
            glyphs,
            allocator,
            customized,
            run_digest_cache,
            sidecar,
            lookup_start,
            glyph_count_before,
        );
    }
    return applyPrepared(
        Executor,
        view,
        lookup_offset,
        lookup_index,
        glyphs,
        allocator,
        run,
        run_digest_cache,
        sidecar,
        lookup_start,
        glyph_count_before,
    );
}

noinline fn applyPrepared(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: ?*RunDigestCache,
    sidecar: *const Lookup,
    lookup_start: i128,
    glyph_count_before: usize,
) Error!bool {
    switch (sidecar.lookup_type) {
        4 => {
            if (sidecar.subtable_count != 1 or
                sidecar.ligature_subst.sets.len == 0)
            {
                return false;
            }
            if (run_digest_cache) |cache| {
                const digest = cache.digestForRun(
                    glyphs.items,
                    sidecar.lookup_flag,
                    run,
                );
                if (digest.isEmpty() or
                    !sidecar.ligature_subst.first_component_digest
                        .mayIntersect(digest))
                {
                    record(
                        run,
                        lookup_index,
                        sidecar.lookup_type,
                        lookup_start,
                        glyph_count_before,
                        glyphs.items.len,
                    );
                    return true;
                }
            }
            if (sidecar.ligature_subst.prefilter_second) {
                try direct_ligature.acceleratedPrefiltered(
                    sidecar.ligature_subst,
                    glyphs,
                    allocator,
                    sidecar.lookup_flag,
                    run,
                );
            } else if (sidecar.ligature_subst.required_second_len != 0) {
                @branchHint(.unlikely);
                try direct_ligature.acceleratedRequiredSecond(
                    sidecar.ligature_subst,
                    glyphs,
                    allocator,
                    sidecar.lookup_flag,
                    run,
                );
            } else {
                try direct_ligature.accelerated(
                    sidecar.ligature_subst,
                    glyphs,
                    allocator,
                    sidecar.lookup_flag,
                    run,
                );
            }
        },
        5 => {
            if (sidecar.context_class_subtables.len != 0) {
                try contextual_context.acceleratedClassLookup(
                    Executor,
                    view,
                    sidecar.subtable_count,
                    glyphs,
                    allocator,
                    sidecar.lookup_flag,
                    run,
                    sidecar,
                );
            } else if (sidecar.context_coverage_subtables.len != 0) {
                try contextual_context.acceleratedCoverageLookup(
                    Executor,
                    view,
                    glyphs,
                    allocator,
                    sidecar.lookup_flag,
                    run,
                    sidecar,
                );
            } else {
                return false;
            }
        },
        6 => {
            if (!sidecar.chaining_coverage_only) return false;
            const digest = if (run_digest_cache) |cache|
                cache.digestForRun(glyphs.items, sidecar.lookup_flag, run)
            else
                prefilter.digest(glyphs.items, sidecar.lookup_flag, run);
            if (!digest.isEmpty() and
                sidecar.chaining_input_digest.mayIntersect(digest))
            {
                try Executor.applyChainingLookup(
                    view,
                    lookup_offset,
                    sidecar.subtable_count,
                    glyphs,
                    allocator,
                    sidecar.lookup_flag,
                    run,
                    sidecar,
                );
            }
        },
        else => return false,
    }

    record(
        run,
        lookup_index,
        sidecar.lookup_type,
        lookup_start,
        glyph_count_before,
        glyphs.items.len,
    );
    return true;
}

fn record(
    run: Options,
    lookup_index: ?u16,
    lookup_type: u16,
    lookup_start: i128,
    glyph_count_before: usize,
    glyph_count_after: usize,
) void {
    profile.recordAccelerated(
        run,
        lookup_index,
        lookup_type,
        lookup_start,
        glyph_count_before,
        glyph_count_after,
    );
}
