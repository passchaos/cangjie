//! HarfBuzz-compatible safety limits shared across one logical GSUB run.

const std = @import("std");
const options_module = @import("options.zig");

const max_glyph_count_factor = 256;
const min_max_glyph_count = 65536;
const max_operations_factor = 4096;
const min_max_operations = 65536;

/// Maximum number of SequenceLookupRecord edges in one contextual call stack.
/// This deliberately caps nested GSUB calls at sixteen rather than relying on
/// the much larger operation budget as an accidental stack-depth limit.
pub const max_context_depth: usize = 16;

pub const Error = error{
    InvalidShapingInput,
    ShapingLimitExceeded,
};
pub const Options = options_module.Options;

pub const Limits = struct {
    operations_left: usize,
    max_glyph_count: usize,

    pub fn init(initial_glyph_count: usize) Error!Limits {
        return .{
            .operations_left = try scaled(
                initial_glyph_count,
                max_operations_factor,
                min_max_operations,
            ),
            .max_glyph_count = try scaled(
                initial_glyph_count,
                max_glyph_count_factor,
                min_max_glyph_count,
            ),
        };
    }

    /// Attach this run-owned budget to a concrete options value.
    ///
    /// `anytype` keeps the limits module independent of the large GSUB
    /// executor while still requiring the caller's source type to expose the
    /// two explicit fields at compile time. No erased or opaque context is
    /// involved.
    pub fn applyTo(self: *Limits, options: anytype) void {
        options.operations_left = &self.operations_left;
        options.max_glyph_count = self.max_glyph_count;
    }
};

/// Preflight one cardinality-changing substitution.
///
/// The glyph-count ceiling is independent from the operation budget, matching
/// HarfBuzz's split guards. A failed preflight does not consume an operation.
pub fn consumeMutation(
    run: Options,
    current_glyph_count: usize,
    removed_len: usize,
    inserted_len: usize,
) Error!void {
    if (removed_len > current_glyph_count) {
        return error.InvalidShapingInput;
    }
    const retained = current_glyph_count - removed_len;
    const new_glyph_count = std.math.add(
        usize,
        retained,
        inserted_len,
    ) catch return error.ShapingLimitExceeded;
    if (run.max_glyph_count) |limit| {
        if (new_glyph_count > limit) return error.ShapingLimitExceeded;
    }
    const operations_left = run.operations_left orelse return;
    if (operations_left.* == 0) return error.ShapingLimitExceeded;
    operations_left.* -= 1;
}

/// Charge one nested contextual lookup before it can recurse.
pub fn consumeNested(run: Options) Error!void {
    const operations_left = run.operations_left orelse return;
    if (operations_left.* == 0) return error.ShapingLimitExceeded;
    operations_left.* -= 1;
}

/// Enter one nested contextual lookup without permitting the operations
/// budget's much larger bound to become an accidental recursion limit.
pub fn enterContext(run: Options) Error!Options {
    if (run.context_depth >= max_context_depth) {
        return error.ShapingLimitExceeded;
    }
    var nested = run;
    nested.context_depth = run.context_depth + 1;
    return nested;
}

fn scaled(initial_glyph_count: usize, factor: usize, minimum: usize) Error!usize {
    const value = std.math.mul(
        usize,
        initial_glyph_count,
        factor,
    ) catch return error.ShapingLimitExceeded;
    return @max(value, minimum);
}
