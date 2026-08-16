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

pub fn withDigestGeneration(
    run: Options,
    generation: *usize,
) Options {
    var result = run;
    if (dispatch.tableUsesRunDigestCache(result.lookup_accelerators) and
        result.glyph_mutation_generation == null)
    {
        result.glyph_mutation_generation = generation;
    }
    return result;
}

pub fn prepare(
    run: Options,
    initial_glyph_count: usize,
    storage: *Storage,
) Error!Options {
    var result = withDigestGeneration(
        run,
        &storage.mutation_generation,
    );
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
