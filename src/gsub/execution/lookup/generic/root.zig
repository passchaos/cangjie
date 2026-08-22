//! Defensive GSUB Lookup preparation and execution.
//!
//! This path accepts untrusted detached tables as well as validated font-owned
//! tables which lack a complete accelerator strategy. It validates the whole
//! lookup before mutation and retains detailed glyph-window profiling.

const std = @import("std");
const execute = @import("execute.zig");
const filtering = @import("../../../runtime/filtering.zig");
const options = @import("../../../runtime/options.zig");
const prefilter = @import("../../../runtime/prefilter/root.zig");
const profile = @import("../profile.zig");
const runtime_dispatch = @import("../../../runtime/dispatch.zig");
const table = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const RunDigestCache = prefilter.Cache;
pub const View = table.View;

pub noinline fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: ?*RunDigestCache,
) Error!void {
    const trace = try profile.Detailed.begin(
        allocator,
        run,
        lookup_index,
        glyphs.items,
    );
    defer trace.finish(allocator, glyphs.items);

    // Untrusted/detached lookups still prove the fixed header here. A
    // font-owned table with an exact accelerator sidecar already established
    // the same header while building the cache, including lookups whose payload
    // capability intentionally falls through to this generic executor.
    const has_exact_header_proof =
        runtime_dispatch.exact(view, lookup_offset, lookup_index, run) != null;
    if (!has_exact_header_proof) {
        // ExtensionSubst validation walks every wrapper and wrapped payload
        // before dispatch, preserving lookup-level atomicity for mixed wrappers.
        _ = try validation.lookup.validateHeader(
            Executor,
            view,
            lookup_offset,
        );
    }
    const resolved = try runtime_dispatch.header(
        view,
        lookup_offset,
        lookup_index,
        run,
    );
    profile.recordKind(run.shape_profile, resolved.lookup_type);

    if (!view.assume_validated) {
        try validation.lookup.validateSubtables(
            Executor,
            view,
            lookup_offset,
            resolved.lookup_type,
            resolved.subtable_count,
            .strict,
        );
    }

    var lookup_run = run;
    if ((resolved.lookup_flag & 0x0010) != 0) {
        lookup_run.active_mark_filtering_set =
            resolved.mark_filtering_set;
        try filtering.validateMarkFilteringSetIndex(lookup_run);
    }
    lookup_run.match_source_syllable =
        runtime_dispatch.matchesSourceSyllable(lookup_index, run);

    return execute.apply(
        Executor,
        view,
        lookup_offset,
        lookup_index,
        resolved.lookup_type,
        resolved.lookup_flag,
        resolved.subtable_count,
        glyphs,
        allocator,
        lookup_run,
        run_digest_cache,
    );
}
