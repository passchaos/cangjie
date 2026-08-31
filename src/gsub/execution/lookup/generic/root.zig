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
    exact_sidecar: ?*const runtime_dispatch.Lookup,
) Error!void {
    const trace = try profile.Detailed.begin(
        allocator,
        run,
        lookup_index,
        glyphs.items,
    );
    defer trace.finish(allocator, glyphs.items);

    const resolved = if (exact_sidecar != null)
        try runtime_dispatch.header(view, lookup_offset, exact_sidecar)
    else parsed: {
        // A font-owned view may still arrive with no sidecars, copied sidecars,
        // or sidecars for another table. Without an exact identity proof, the
        // generic path must re-establish the complete structural proof from
        // bytes. Clearing this optimization bit is particularly important for
        // ExtensionSubst: validateHeader then walks every wrapper and wrapped
        // payload before any mutation.
        var validation_view = view;
        validation_view.assume_validated = false;
        _ = try validation.lookup.validateHeader(
            Executor,
            validation_view,
            lookup_offset,
        );
        const parsed_header = try runtime_dispatch.header(
            view,
            lookup_offset,
            null,
        );
        try validation.lookup.validateSubtables(
            Executor,
            validation_view,
            lookup_offset,
            parsed_header.lookup_type,
            parsed_header.subtable_count,
            .strict,
        );
        break :parsed parsed_header;
    };
    profile.recordKind(run.shape_profile, resolved.lookup_type);

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
        resolved.lookup_type,
        resolved.lookup_flag,
        resolved.subtable_count,
        glyphs,
        allocator,
        lookup_run,
        run_digest_cache,
        exact_sidecar,
    );
}

/// Defensive lookup execution after a cached plan proved the exact validated
/// sidecar identity. This keeps unsupported accelerator payloads on the
/// generic semantic path without parsing or re-indexing their fixed header.
pub noinline fn applyAfterPlanProof(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: *RunDigestCache,
    sidecar: *const runtime_dispatch.Lookup,
) Error!void {
    std.debug.assert(view.assume_validated);
    std.debug.assert(run.shape_profile == null);
    var lookup_run = run;
    if ((sidecar.lookup_flag & 0x0010) != 0) {
        lookup_run.active_mark_filtering_set = sidecar.mark_filtering_set;
        try filtering.validateMarkFilteringSetIndex(lookup_run);
    }
    lookup_run.match_source_syllable =
        runtime_dispatch.matchesSourceSyllable(lookup_index, run);
    return execute.apply(
        Executor,
        view,
        lookup_offset,
        sidecar.lookup_type,
        sidecar.lookup_flag,
        sidecar.subtable_count,
        glyphs,
        allocator,
        lookup_run,
        run_digest_cache,
        sidecar,
    );
}
