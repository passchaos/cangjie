//! Prepared top-level GPOS Lookup execution.
//!
//! This module owns whole-run lookup-kind selection. Nested PosLookupRecord
//! dispatch remains in `nested.zig` because nested targets have different
//! precedence and target-index semantics.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const contextual = @import("../contextual/root.zig");
const cursive = @import("../cursive.zig");
const extension_strategy = @import("execute/extension.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const marks = @import("../marks/root.zig");
const nested = @import("../nested.zig");
const options = @import("../../options.zig");
const pair_strategy = @import("execute/pair.zig");
const positioning = @import("../../../positioning/root.zig");
const prefilter = @import("../prefilter.zig");
const runtime_dispatch = @import("../../dispatch.zig");
const runtime_matching = @import("../../matching.zig");
const single = @import("../single.zig");
const table = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const DigestCache = prefilter.DigestCache;
pub const Error =
    table.view.Error ||
    error{ UnsupportedGpos, InvalidShapingInput } ||
    std.mem.Allocator.Error;
pub const Header = runtime_dispatch.Header;
pub const Options = options.Options;
pub const View = table.View;

/// Execute a Lookup after its header and lookup-local options are prepared.
///
/// Supported direct subtables are preflighted before output is appended, so a
/// malformed later subtable cannot expose partial adjustments from an earlier
/// one. Validated font-owned tables skip that repeated structural walk.
pub noinline fn collect(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: ?*DigestCache,
    resolved: Header,
    prepared_accelerator: ?*const accelerator.Lookup,
) Error!void {
    const lookup_type = resolved.lookup_type;
    const lookup_flag = resolved.lookup_flag;
    const subtable_count = resolved.subtable_count;

    if (!view.assume_validated) {
        try validation.lookup.lookupSubtables(
            view,
            lookup_offset,
            lookup_type,
            subtable_count,
        );
    }
    // Whole-run traversal has already selected the exact sidecar while
    // resolving the LookupList offset. Detached callers still derive it from
    // the optional index, but the hot font-owned path must not index the large
    // accelerator array a second time for coverage and parsed subtables.
    const lookup_accelerator = if (prepared_accelerator) |prepared|
        if (prepared.coverage_digest.isEmpty()) null else prepared
    else
        runtime_dispatch.acceleratorWithCoverage(lookup_index, run);
    if (lookup_accelerator) |active_accelerator| {
        const run_digest = if (run_digest_cache) |cache|
            cache.get(glyphs, lookup_flag, run)
        else
            prefilter.runDigest(glyphs, lookup_flag, run);
        if (run_digest.isEmpty() or
            !active_accelerator.coverage_digest.mayIntersect(run_digest))
        {
            return;
        }
        // Coverage-only chaining already performs this exact group lookup for
        // every glyph. A whole-run preflight would duplicate its first scan.
        if (!active_accelerator.chaining_coverage_only and
            active_accelerator.coverage_groups.len != 0 and
            !prefilter.groupsMayMatchRun(
                active_accelerator.coverage_groups,
                active_accelerator.coverage_group_slots,
                active_accelerator.coverage_group_direct,
                glyphs,
                lookup_flag,
                run,
            ))
        {
            return;
        }
    }

    switch (lookup_type) {
        1 => return single.collectLookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        2 => return pair_strategy.collect(
            view,
            lookup_offset,
            lookup_index,
            subtable_count,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        9 => return extension_strategy.collect(
            view,
            lookup_offset,
            lookup_index,
            subtable_count,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        else => {},
    }

    if (lookup_type == 8) {
        if (lookup_accelerator) |active_accelerator| {
            if (active_accelerator.chaining_coverage_only) {
                return contextual.chaining.coverage.lookup.collect(
                    view,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                    active_accelerator,
                    nested.records,
                    nested.apply,
                );
            }
        }
    }

    for (0..subtable_count) |subtable_index| {
        const subtable_offset = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        switch (lookup_type) {
            // SinglePos and PairPos require whole-lookup ordered-alternative
            // semantics and are handled before this per-subtable loop.
            1, 2 => unreachable,
            3 => if (lookup_accelerator) |active_accelerator| {
                if (subtable_index < active_accelerator.cursive_subtables.len) {
                    try cursive.collectParsed(
                        view,
                        active_accelerator.cursive_subtables[subtable_index],
                        glyphs,
                        adjustments,
                        allocator,
                        lookup_flag,
                        run,
                    );
                    continue;
                }
                try cursive.collect(
                    view,
                    subtable_offset,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                );
            } else try cursive.collect(
                view,
                subtable_offset,
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
            ),
            4 => if (runtime_matching.runMayHaveMarkAttachments(glyphs, run)) {
                if (lookup_accelerator) |active_accelerator| {
                    if (subtable_index <
                        active_accelerator.mark_to_base_subtables.len)
                    {
                        try marks.base.collectParsed(
                            view,
                            active_accelerator.mark_to_base_subtables[subtable_index],
                            glyphs,
                            adjustments,
                            allocator,
                            lookup_flag,
                            run,
                        );
                        continue;
                    }
                }
                try marks.base.collect(
                    view,
                    subtable_offset,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                );
            },
            5 => if (runtime_matching.runMayHaveMarkAttachments(glyphs, run)) {
                try marks.ligature.collect(
                    view,
                    subtable_offset,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                );
            },
            6 => if (runtime_matching.runMayHaveMarkAttachments(glyphs, run)) {
                if (lookup_accelerator) |accelerator_value| {
                    if (subtable_index < accelerator_value.mark_to_mark_subtables.len) {
                        const parsed = accelerator_value.mark_to_mark_subtables[subtable_index];
                        for (0..glyphs.len) |glyph_index| {
                            _ = try marks.mark.collectAtParsed(
                                view,
                                parsed,
                                glyphs,
                                glyph_index,
                                adjustments,
                                allocator,
                                lookup_flag,
                                run,
                            );
                        }
                        continue;
                    }
                }
                try marks.mark.collect(
                    view,
                    subtable_offset,
                    glyphs,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                );
            },
            7 => try nested.contextCollect(
                view,
                subtable_offset,
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
            ),
            8 => try nested.chainingCollect(
                view,
                subtable_offset,
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
            ),
            9 => unreachable,
            else => {},
        }
    }
}
