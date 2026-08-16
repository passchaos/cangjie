//! MultipleSubst accelerator construction.

const std = @import("std");
const model = @import("../model.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Multiple = model.MultipleSubstitution;
pub const Entry = model.MultipleEntry;
pub const View = table.View;

pub fn build(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Multiple {
    if (try view.readU16(subtable_offset) != 1) return .{};
    const coverage = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const sequence_count = try view.readU16(subtable_offset + 4);
    const entries = try allocator.alloc(Entry, sequence_count);
    errdefer allocator.free(entries);

    for (entries, 0..) |*entry, sequence_index| {
        const glyph = (try table.coverage.glyphAt(
            view,
            coverage,
            sequence_index,
        )) orelse {
            allocator.free(entries);
            return .{};
        };
        const sequence = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(
                subtable_offset + 6 + sequence_index * 2,
            ),
        );
        const glyph_count = try view.readU16(sequence);
        entry.* = .{
            .glyph = glyph,
            .sequence_offset = sequence,
            .glyph_count = glyph_count,
            .single_to = if (glyph_count == 1)
                try view.readU16(sequence + 2)
            else
                0,
        };
    }
    std.sort.heap(Entry, entries, {}, lessThan);
    return .{ .entries = entries };
}

fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
    return lhs.glyph < rhs.glyph;
}
