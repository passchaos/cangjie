//! HarfBuzz-compatible safety limits shared across one logical GSUB run.

const std = @import("std");

const max_glyph_count_factor = 256;
const min_max_glyph_count = 65536;
const max_operations_factor = 4096;
const min_max_operations = 65536;

pub const Error = error{ShapingLimitExceeded};

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

fn scaled(initial_glyph_count: usize, factor: usize, minimum: usize) Error!usize {
    const value = std.math.mul(
        usize,
        initial_glyph_count,
        factor,
    ) catch return error.ShapingLimitExceeded;
    return @max(value, minimum);
}
