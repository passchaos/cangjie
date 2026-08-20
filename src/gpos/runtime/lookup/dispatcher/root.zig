//! Top-level GPOS lookup preparation and execution.

const std = @import("std");
pub const execute = @import("execute.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const lookup_order = @import("../../../../opentype/lookup_order.zig");
const options = @import("../../options.zig");
const positioning = @import("../../../positioning/root.zig");
pub const prepare = @import("prepare.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const DigestCache = execute.DigestCache;
pub const Error = execute.Error;
pub const Options = options.Options;
pub const View = table.View;

/// Execute a detached Lookup without an accelerator index or shared digest.
///
/// This is primarily useful to validation tests and low-level table tooling;
/// full shaping runs should use `collectWithIndex` to retain cache identity.
pub fn collect(
    view: View,
    lookup_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    return collectWithIndex(
        view,
        lookup_offset,
        null,
        glyphs,
        adjustments,
        allocator,
        run,
        null,
    );
}

pub fn collectWithIndex(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    run: Options,
    run_digest_cache: ?*DigestCache,
) Error!void {
    if (lookup_index) |index| {
        if (lookup_order.contains(run.disabled_lookups, index)) return;
    }
    const lookup_start = profileNow(run);
    defer {
        if (run.shape_profile) |profile| {
            profile.recordGposLookupTime(
                lookup_index,
                profileElapsed(lookup_start, run),
            );
        }
    }

    // The public Font path validates and checksums GPOS before setting
    // assume_validated. Preparation therefore reads only fixed Lookup header
    // state; untrusted payload preflight remains in the executor.
    const resolved = try prepare.header(
        view,
        lookup_offset,
        lookup_index,
        run,
    );
    if (try prepare.markFilteringOptions(resolved, run)) |customized| {
        return execute.collect(
            view,
            lookup_offset,
            lookup_index,
            glyphs,
            adjustments,
            allocator,
            customized,
            run_digest_cache,
            resolved,
        );
    }
    return execute.collect(
        view,
        lookup_offset,
        lookup_index,
        glyphs,
        adjustments,
        allocator,
        run,
        run_digest_cache,
        resolved,
    );
}

fn profileNow(run: Options) i128 {
    return if (run.shape_profile != null)
        std.Io.Clock.now(.awake, run.profile_io.?).nanoseconds
    else
        0;
}

fn profileElapsed(start: i128, run: Options) i128 {
    return std.Io.Clock.now(.awake, run.profile_io.?).nanoseconds - start;
}
