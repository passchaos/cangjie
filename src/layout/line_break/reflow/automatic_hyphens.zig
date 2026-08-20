//! Selection-side construction for automatic line-end hyphens.
//!
//! Generic glyph/run/line insertion lives in `hyphen_insertions.zig`; this
//! module adds automatic-hyphen glyph semantics and pending-index repair.

const std = @import("std");

const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const hyphen_insertions = @import("hyphen_insertions.zig");

pub const Selected = hyphen_insertions.Selected;
pub const materialize = hyphen_insertions.materialize;
pub const materializeAssumeCapacity =
    hyphen_insertions.materializeAssumeCapacity;
pub const shiftAfterReplacement =
    hyphen_insertions.shiftAfterReplacement;

pub fn appendSelected(
    selected: *std.ArrayList(Selected),
    allocator: std.mem.Allocator,
    line_index: usize,
    insert_index: usize,
    candidate: @import("opportunities.zig").AutomaticHyphen,
) !void {
    try selected.append(allocator, .{
        .line_index = line_index,
        .insert_index = insert_index,
        .run_index = candidate.run_index,
        .glyph = discretionary_hyphen.synthetic(
            candidate.resolved,
            candidate.byte_offset,
            candidate.orientation,
        ),
    });
}
