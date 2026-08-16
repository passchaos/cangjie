//! ReverseChainSingleSubst exact-context sidecar construction.

const std = @import("std");
const model = @import("../model.zig");
const table = @import("../../table/root.zig");

pub const Entry = model.ReverseChainingContextEntry;
pub const Error = table.coverage.Error;
pub const Parsed = model.ReverseChainingSingleSubtable;
pub const View = table.View;

/// Append one exact Gulzar-style context when every relevant coverage is a
/// singleton. Other shapes remain on the generic grouped-coverage path.
pub fn appendExact(
    view: View,
    subtable: Parsed,
    subtable_index: u16,
    contexts: *std.ArrayList(Entry),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    if (subtable.backtrack_count != 1 or
        subtable.lookahead_count != 2 or
        subtable.glyph_count != 1)
    {
        return;
    }
    const target =
        try singletonCoverageGlyph(view, subtable.coverage_offset) orelse return;
    const backtrack_coverage = try requiredCoverageAt(
        view,
        subtable,
        subtable.backtrack_offsets_pos,
    );
    const backtrack =
        try singletonCoverageGlyph(view, backtrack_coverage) orelse return;
    const lookahead_0_coverage = try requiredCoverageAt(
        view,
        subtable,
        subtable.lookahead_offsets_pos,
    );
    const lookahead_0 =
        try singletonCoverageGlyph(view, lookahead_0_coverage) orelse return;
    const lookahead_1_coverage = try requiredCoverageAt(
        view,
        subtable,
        subtable.lookahead_offsets_pos + 2,
    );
    const lookahead_1 =
        try singletonCoverageGlyph(view, lookahead_1_coverage) orelse return;

    try contexts.append(allocator, .{
        .key = .{
            .target = target,
            .backtrack = backtrack,
            .lookahead_0 = lookahead_0,
            .lookahead_1 = lookahead_1,
        },
        .subtable_index = subtable_index,
        .substitute = try view.readU16(subtable.substitutes_pos),
    });
}

pub fn finish(
    contexts: []Entry,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error![]Entry {
    if (contexts.len == 0) return allocator.alloc(Entry, 0);
    std.sort.heap(Entry, contexts, {}, lessEntry);
    return allocator.dupe(Entry, contexts);
}

fn requiredCoverageAt(
    view: View,
    subtable: Parsed,
    offset_position: usize,
) Error!usize {
    return table.offset.required16(
        view,
        subtable.subtable_offset,
        try view.readU16(offset_position),
    );
}

fn singletonCoverageGlyph(
    view: View,
    coverage_offset: usize,
) Error!?u16 {
    switch (try view.readU16(coverage_offset)) {
        1 => {
            if (try view.readU16(coverage_offset + 2) != 1) return null;
            return @as(?u16, try view.readU16(coverage_offset + 4));
        },
        2 => {
            if (try view.readU16(coverage_offset + 2) != 1) return null;
            const start = try view.readU16(coverage_offset + 4);
            if (start != try view.readU16(coverage_offset + 6)) return null;
            return @as(?u16, start);
        },
        else => return error.UnsupportedGsub,
    }
}

fn lessEntry(_: void, lhs: Entry, rhs: Entry) bool {
    return lhs.key.lessThan(rhs.key) or
        (lhs.key.eql(rhs.key) and lhs.subtable_index < rhs.subtable_index);
}
