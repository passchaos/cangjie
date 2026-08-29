//! Coverage expansion into chaining group and pair-index records.

const std = @import("std");
const model = @import("../../model.zig");
const table = @import("../../../table/root.zig");

pub const Error = table.coverage.Error;
pub const View = table.View;
// A few production Arabic contextual lookups have tens of thousands of
// first/second coverage combinations. Keeping those exact pairs avoids a
// long authored-subtable scan for every glyph; bound the retained sidecar so
// adversarial fonts still cannot force unbounded parse-time allocation.
pub const max_pair_index_pairs = 32768;

pub fn appendFirst(
    view: View,
    coverage: usize,
    subtable_index: u16,
    pairs: *std.ArrayList(model.ChainingPair),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    const count = try table.coverage.glyphCount(view, coverage);
    try pairs.ensureUnusedCapacity(allocator, count);
    for (0..count) |coverage_index| {
        pairs.appendAssumeCapacity(.{
            .glyph = (try table.coverage.glyphAt(
                view,
                coverage,
                coverage_index,
            )) orelse return error.BadGsub,
            .subtable_index = subtable_index,
        });
    }
}

pub fn appendPair(
    view: View,
    first_coverage: usize,
    second_coverage: usize,
    subtable_index: u16,
    pairs: *std.ArrayList(model.ChainingPairEntry),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!bool {
    const first_count = try table.coverage.glyphCount(view, first_coverage);
    const second_count = try table.coverage.glyphCount(view, second_coverage);
    if (first_count == 0 or second_count == 0) return true;
    if (first_count > max_pair_index_pairs / second_count) return false;
    const total = first_count * second_count;
    if (pairs.items.len + total > max_pair_index_pairs) return false;
    try pairs.ensureUnusedCapacity(allocator, total);
    for (0..first_count) |first_index| {
        const first = (try table.coverage.glyphAt(
            view,
            first_coverage,
            first_index,
        )) orelse continue;
        for (0..second_count) |second_index| {
            const second = (try table.coverage.glyphAt(
                view,
                second_coverage,
                second_index,
            )) orelse continue;
            pairs.appendAssumeCapacity(.{
                .first = first,
                .second = second,
                .subtable_index = subtable_index,
            });
        }
    }
    return true;
}
