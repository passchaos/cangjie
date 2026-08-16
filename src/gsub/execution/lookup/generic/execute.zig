//! Prepared defensive GSUB lookup-kind execution.
//!
//! Header parsing, structural preflight, and lookup-local options belong to
//! `root.zig`. This module chooses direct, contextual, extension, and fallback
//! strategies only after those proofs have completed.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const contextual_context =
    @import("../../contextual/context/root.zig");
const contextual_chaining_class =
    @import("../../contextual/chaining/class/root.zig");
const direct_alternate = @import("../../direct/alternate/root.zig");
const direct_ligature = @import("../../direct/ligature/root.zig");
const direct_multiple = @import("../../direct/multiple/root.zig");
const direct_reverse = @import("../../direct/reverse/root.zig");
const direct_single = @import("../../direct/single/root.zig");
const extension = @import("extension.zig");
const options = @import("../../../runtime/options.zig");
const prefilter = @import("../../../runtime/prefilter/root.zig");
const runtime_dispatch = @import("../../../runtime/dispatch.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const RunDigestCache = prefilter.Cache;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    lookup_type: u16,
    lookup_flag: u16,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: ?*RunDigestCache,
) Error!void {
    switch (lookup_type) {
        1 => {
            if (runtime_dispatch.singleEntries(
                lookup_index,
                run,
            )) |entries| {
                direct_single.entries(entries, glyphs, lookup_flag, run);
            } else {
                try direct_single.lookup(
                    view,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            }
            return;
        },
        2 => {
            if (runtime_dispatch.multiple(
                lookup_index,
                run,
            )) |sidecar| {
                try direct_multiple.accelerated(
                    view,
                    sidecar.*,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            } else {
                try direct_multiple.lookup(
                    view,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            }
            return;
        },
        3 => return direct_alternate.lookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        5 => return applyContext(
            Executor,
            view,
            lookup_offset,
            lookup_index,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        6 => return applyChaining(
            Executor,
            view,
            lookup_offset,
            lookup_index,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
            run_digest_cache,
        ),
        7 => if (try extension.apply(
            Executor,
            view,
            lookup_offset,
            lookup_index,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
        )) return,
        else => {},
    }

    if (lookup_type == 4 and subtable_count == 1) {
        if (runtime_dispatch.ligature(
            lookup_index,
            run,
        )) |sidecar| {
            if (run_digest_cache) |cache| {
                const digest = cache.digestForRun(
                    glyphs.items,
                    lookup_flag,
                    run,
                );
                if (digest.isEmpty() or
                    !sidecar.first_component_digest.mayIntersect(digest))
                {
                    return;
                }
            }
            if (sidecar.prefilter_second) {
                try direct_ligature.acceleratedPrefiltered(
                    sidecar.*,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            } else if (sidecar.required_second_len != 0) {
                @branchHint(.unlikely);
                try direct_ligature.acceleratedRequiredSecond(
                    sidecar.*,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            } else {
                try direct_ligature.accelerated(
                    sidecar.*,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            }
            return;
        }
    }

    for (0..subtable_count) |subtable_index| {
        const subtable_offset = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        switch (lookup_type) {
            // These kinds require whole-lookup ordered-alternative semantics
            // and have already returned above.
            1, 2, 3 => unreachable,
            4 => try direct_ligature.subtable(
                view,
                subtable_offset,
                glyphs,
                allocator,
                lookup_flag,
                run,
            ),
            5, 6 => unreachable,
            7 => try Executor.applyExtensionSubtable(
                view,
                subtable_offset,
                glyphs,
                allocator,
                lookup_flag,
                run,
            ),
            // ReverseChainSingleSubst is position-major across the complete
            // lookup and is therefore handled after the loop.
            8 => {},
            else => {},
        }
    }
    if (lookup_type == 8) {
        try direct_reverse.lookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            lookup_flag,
            run,
        );
    }
}

fn applyContext(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    if (runtime_dispatch.contextClass(
        lookup_index,
        run,
    )) |sidecar| {
        return contextual_context.acceleratedClassLookup(
            Executor,
            view,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
            sidecar,
        );
    }
    if (runtime_dispatch.contextCoverage(
        lookup_index,
        run,
    )) |sidecar| {
        return contextual_context.acceleratedCoverageLookup(
            Executor,
            view,
            glyphs,
            allocator,
            lookup_flag,
            run,
            sidecar,
        );
    }
    return contextual_context.lookup(
        Executor,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

fn applyChaining(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    run_digest_cache: ?*RunDigestCache,
) Error!void {
    if (runtime_dispatch.chainingClass(
        lookup_index,
        run,
    )) |sidecar| {
        return contextual_chaining_class.acceleratedLookup(
            Executor,
            view,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
            sidecar,
        );
    }
    if (runtime_dispatch.chainingCoverage(
        lookup_index,
        run,
    )) |sidecar| {
        const digest = if (run_digest_cache) |cache|
            cache.digestForRun(glyphs.items, lookup_flag, run)
        else
            prefilter.digest(glyphs.items, lookup_flag, run);
        if (digest.isEmpty() or
            !sidecar.chaining_input_digest.mayIntersect(digest))
        {
            return;
        }
        return Executor.applyChainingLookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
            sidecar,
        );
    }
    if (try accelerator.build.chaining_coverage.lookupUsesCoverageOnly(
        view,
        lookup_offset,
        subtable_count,
        false,
    )) {
        if (!try prefilter.chainingCoverageLookupMayMatch(
            view,
            lookup_offset,
            subtable_count,
            glyphs.items,
            lookup_flag,
            run,
        )) return;
    }
    // Mixed glyph/class/coverage lookups still require position-major
    // dispatch: subtables are alternatives for one candidate rather than
    // independent whole-run passes.
    return Executor.applyChainingLookup(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
        null,
    );
}
