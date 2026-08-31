//! Shared mutable state attached to one logical GSUB run.
//!
//! Feature stages and cached plans copy `Options`, but mutation generation and
//! shaping limits must remain shared across every lookup in that run.

const limits = @import("limits.zig");
const options = @import("options.zig");
const dispatch = @import("dispatch.zig");

pub const Error = limits.Error;
pub const Options = options.Options;

pub const Storage = struct {
    mutation_generation: usize = 0,
    operations_left: usize = 0,
};

fn withDigestGenerationForPolicy(
    run: Options,
    generation: *usize,
    table_uses_run_digest_cache: bool,
) Options {
    var result = run;
    if (table_uses_run_digest_cache and
        result.glyph_mutation_generation == null)
    {
        result.glyph_mutation_generation = generation;
    }
    return result;
}

/// Prepare one run after optionally binding its accelerator slice to `view`.
/// Foreign or copied sidecars must not control digest-cache lifetime: without
/// exact identity, generic fallback uses uncached necessary-condition checks.
pub inline fn prepareForTable(
    view: dispatch.View,
    run: Options,
    initial_glyph_count: usize,
    storage: *Storage,
) Error!Options {
    const exact_sidecars = dispatch.exactSidecars(view, run);
    const result = withDigestGenerationForPolicy(
        run,
        &storage.mutation_generation,
        dispatch.tableUsesRunDigestCache(exact_sidecars),
    );
    return prepareLimits(result, initial_glyph_count, storage);
}

/// Prepare after the caller already established exact table/slice identity.
/// This avoids repeating the identity tuple comparison in cached-plan and
/// cached-selection boundaries while retaining the same digest policy.
pub inline fn prepareForExactSidecars(
    run: Options,
    exact_sidecars: []const dispatch.Lookup,
    initial_glyph_count: usize,
    storage: *Storage,
) Error!Options {
    const result = withDigestGenerationForPolicy(
        run,
        &storage.mutation_generation,
        dispatch.tableUsesRunDigestCache(exact_sidecars),
    );
    return prepareLimits(result, initial_glyph_count, storage);
}

pub inline fn prepare(
    run: Options,
    initial_glyph_count: usize,
    storage: *Storage,
) Error!Options {
    return prepareLimits(run, initial_glyph_count, storage);
}

fn prepareLimits(
    run: Options,
    initial_glyph_count: usize,
    storage: *Storage,
) Error!Options {
    var result = run;
    if (result.operations_left == null) {
        const run_limits = try limits.Limits.init(initial_glyph_count);
        storage.operations_left = run_limits.operations_left;
        result.operations_left = &storage.operations_left;
        if (result.max_glyph_count == null) {
            result.max_glyph_count = run_limits.max_glyph_count;
        }
    } else if (result.max_glyph_count == null) {
        result.max_glyph_count =
            (try limits.Limits.init(initial_glyph_count)).max_glyph_count;
    }
    return result;
}
