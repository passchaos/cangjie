//! SingleSubst accelerator construction.

const std = @import("std");
const model = @import("../model.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error;
pub const Entry = model.SingleEntry;
pub const Single = model.SingleSubstitution;
pub const View = table.View;

pub fn compact(view: View, subtable_offset: usize) Error!Single {
    const format = try view.readU16(subtable_offset);
    const coverage = try requiredCoverage(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    switch (format) {
        1 => {
            const delta = try view.readI16(subtable_offset + 4);
            var result = Single{
                .enabled = true,
                .subst_format = format,
                .coverage_offset = coverage,
                .delta = delta,
            };
            try fillSingleton(view, coverage, delta, null, &result);
            return result;
        },
        2 => {
            const glyph_count = try view.readU16(subtable_offset + 4);
            var result = Single{
                .enabled = true,
                .subst_format = format,
                .coverage_offset = coverage,
                .glyph_count = glyph_count,
                .substitutes_pos = subtable_offset + 6,
            };
            try fillSingleton(
                view,
                coverage,
                0,
                subtable_offset + 6,
                &result,
            );
            return result;
        },
        else => return .{},
    }
}

pub fn entries(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)![]Entry {
    const format = try view.readU16(subtable_offset);
    const coverage = try requiredCoverage(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const count = try table.coverage.glyphCount(view, coverage);
    const result = try allocator.alloc(Entry, count);
    errdefer allocator.free(result);

    switch (format) {
        1 => {
            const delta = try view.readI16(subtable_offset + 4);
            for (result, 0..) |*entry, index| {
                const from = (try table.coverage.glyphAt(
                    view,
                    coverage,
                    index,
                )) orelse return error.BadGsub;
                entry.* = .{
                    .from = from,
                    .to = @bitCast(@as(i16, @bitCast(from)) +% delta),
                };
            }
        },
        2 => {
            if (try view.readU16(subtable_offset + 4) != count) {
                return error.BadGsub;
            }
            for (result, 0..) |*entry, index| {
                entry.* = .{
                    .from = (try table.coverage.glyphAt(
                        view,
                        coverage,
                        index,
                    )) orelse return error.BadGsub,
                    .to = try view.readU16(
                        subtable_offset + 6 + index * 2,
                    ),
                };
            }
        },
        else => return error.UnsupportedGsub,
    }
    return result;
}

fn fillSingleton(
    view: View,
    coverage: usize,
    delta: i16,
    substitutes_pos: ?usize,
    result: *Single,
) Error!void {
    const glyph = switch (try view.readU16(coverage)) {
        1 => glyph: {
            const count = try view.readU16(coverage + 2);
            if (count != 1) return;
            try table.coverage.validateFormat1Order(view, coverage, count);
            break :glyph try view.readU16(coverage + 4);
        },
        2 => glyph: {
            const count = try view.readU16(coverage + 2);
            if (count != 1) return;
            try table.coverage.validateFormat2Ranges(view, coverage, count);
            const start = try view.readU16(coverage + 4);
            if (start != try view.readU16(coverage + 6)) return;
            break :glyph start;
        },
        else => return,
    };
    result.single_mapping = true;
    result.single_from = glyph;
    result.single_to = if (substitutes_pos) |position|
        try view.readU16(position)
    else
        @bitCast(@as(i16, @bitCast(glyph)) +% delta);
}

fn requiredCoverage(
    view: View,
    subtable_offset: usize,
    relative: u16,
) Error!usize {
    return table.offset.required16(view, subtable_offset, relative);
}
