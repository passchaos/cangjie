//! PairPos xAdvance-only accelerator construction.

const std = @import("std");
const GlyphId = @import("../../glyph.zig").GlyphId;
const model = @import("model.zig");
const positioning = @import("../positioning/root.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

const max_class_glyphs = 16_384;
const max_class_matrix = 16_384;
pub const max_dense_class_entries = 8_192;
const min_dense_pair_sets = 64;

pub const DenseRanges = struct {
    coverage_base: GlyphId,
    coverage_len: usize,
    class_2_base: GlyphId,
    class_2_len: usize,
};

pub fn append(
    view: View,
    subtable_offset: usize,
    records: *std.ArrayList(model.PairPositionRecord),
    coverage_classes: *std.ArrayList(model.PairClassEntry),
    class_entries: *std.ArrayList(model.PairClassEntry),
    class_matrix: *std.ArrayList(i16),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.PairPositionSubtable {
    const pos_format = try view.readU16(subtable_offset);
    const value_format_1 = try view.readU16(subtable_offset + 4);
    const value_format_2 = try view.readU16(subtable_offset + 6);
    // Device/VariationIndex fields follow the scalar payload and are validated
    // elsewhere, so xAdvance plus nullable device fields remains predecodable.
    if ((value_format_1 & 0x000f) != 0x0004 or
        (value_format_1 & 0xff00) != 0 or
        value_format_2 != 0)
    {
        return .{};
    }
    const value_size = try positioning.value_record.size(value_format_1);
    return switch (pos_format) {
        1 => appendFormat1(
            view,
            subtable_offset,
            value_size,
            records,
            coverage_classes,
            allocator,
        ),
        2 => appendFormat2(
            view,
            subtable_offset,
            value_size,
            coverage_classes,
            class_entries,
            class_matrix,
            allocator,
        ),
        else => .{},
    };
}

pub fn appendFormat1(
    view: View,
    subtable_offset: usize,
    value_size: usize,
    records: *std.ArrayList(model.PairPositionRecord),
    dense_ranges: *std.ArrayList(model.PairClassEntry),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.PairPositionSubtable {
    const coverage_offset = try requiredOffset(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const pair_set_count = try view.readU16(subtable_offset + 8);
    const coverage_count = try table.coverage.glyphCount(view, coverage_offset);
    // Trailing PairSets beyond Coverage are unreachable and intentionally
    // ignored, matching HarfBuzz and deployed TestGPOSTwo-style fonts.
    const reachable_count = @min(@as(usize, pair_set_count), coverage_count);
    const record_start = records.items.len;
    const first_glyph = if (reachable_count != 0)
        (try table.coverage.glyphAt(view, coverage_offset, 0)).?
    else
        0;
    const last_glyph = if (reachable_count != 0)
        (try table.coverage.glyphAt(
            view,
            coverage_offset,
            reachable_count - 1,
        )).?
    else
        0;
    const dense_len = if (reachable_count != 0 and last_glyph >= first_glyph)
        @as(usize, last_glyph) - first_glyph + 1
    else
        0;
    const dense_start = dense_ranges.items.len;
    const build_dense = shouldBuildDenseFormat1(
        reachable_count,
        dense_len,
    );
    if (build_dense) {
        try dense_ranges.resize(allocator, dense_start + dense_len);
        @memset(
            dense_ranges.items[dense_start..],
            .{ .glyph = 0, .class = 0 },
        );
    }
    var dense_offsets_fit = build_dense;
    for (0..reachable_count) |set_index| {
        const first = (try table.coverage.glyphAt(
            view,
            coverage_offset,
            set_index,
        )).?;
        const pair_set = try requiredOffset(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 10 + set_index * 2),
        );
        const pair_count = try view.readU16(pair_set);
        const set_record_start = records.items.len;
        for (0..pair_count) |pair_index| {
            const record = pair_set + 2 + pair_index * (2 + value_size);
            try records.append(allocator, .{
                .first = first,
                .second = try view.readU16(record),
                .x_advance = try view.readI16(record + 2),
            });
        }
        const relative_start = set_record_start - record_start;
        if (dense_offsets_fit and relative_start <= std.math.maxInt(u16)) {
            dense_ranges.items[
                dense_start + first - first_glyph
            ] = .{
                // In a dense format-1 map, these two compact fields store the
                // record offset and count; the array index owns glyph identity.
                .glyph = @intCast(relative_start),
                .class = pair_count,
            };
        } else {
            dense_offsets_fit = false;
        }
    }
    if (!dense_offsets_fit and build_dense) {
        dense_ranges.shrinkRetainingCapacity(dense_start);
    }
    return .{
        .kind = if (dense_offsets_fit)
            .format_1_dense_x_advance
        else
            .format_1_x_advance,
        .record_start = record_start,
        .record_len = records.items.len - record_start,
        .coverage_start = dense_start,
        .coverage_len = if (dense_offsets_fit) dense_len else 0,
        .class_2_start = first_glyph,
    };
}

pub fn appendFormat2(
    view: View,
    subtable_offset: usize,
    value_size: usize,
    coverage_classes: *std.ArrayList(model.PairClassEntry),
    class_entries: *std.ArrayList(model.PairClassEntry),
    class_matrix: *std.ArrayList(i16),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!model.PairPositionSubtable {
    const coverage_offset = try requiredOffset(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const class_def_1 = try requiredOffset(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 8),
    );
    const class_def_2 = try requiredOffset(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 10),
    );
    const class_1_count = try view.readU16(subtable_offset + 12);
    const class_2_count = try view.readU16(subtable_offset + 14);
    const matrix_len = @as(usize, class_1_count) * class_2_count;
    if (matrix_len > max_class_matrix) return .{};

    const coverage_start = coverage_classes.items.len;
    const coverage_count =
        try table.coverage.glyphCount(view, coverage_offset);
    if (coverage_count > max_class_glyphs) return .{};
    for (0..coverage_count) |coverage_index| {
        const glyph =
            (try table.coverage.glyphAt(
                view,
                coverage_offset,
                coverage_index,
            )) orelse return error.BadGpos;
        const class = try table.class_def.value(view, class_def_1, glyph);
        if (class >= class_1_count) return error.BadGpos;
        try coverage_classes.append(
            allocator,
            .{ .glyph = glyph, .class = class },
        );
    }

    const class_2_start = class_entries.items.len;
    if (!(try appendClassDefEntries(
        view,
        class_def_2,
        class_entries,
        allocator,
    ))) {
        coverage_classes.shrinkRetainingCapacity(coverage_start);
        return .{};
    }
    const coverage_entries = coverage_classes.items[coverage_start..];
    const class_2_entries = class_entries.items[class_2_start..];
    const ranges = denseRanges(coverage_entries, class_2_entries);
    var dense = false;
    if (ranges) |dense_ranges| {
        if (shouldBuildDense(dense_ranges) and
            entriesFitDenseRanges(
                coverage_entries,
                class_2_entries,
                dense_ranges,
            ))
        {
            try replaceWithDenseCoverage(
                coverage_classes,
                coverage_start,
                dense_ranges,
                allocator,
            );
            try replaceWithDenseClasses(
                class_entries,
                class_2_start,
                dense_ranges,
                allocator,
            );
            dense = true;
        }
    }

    const matrix_start = class_matrix.items.len;
    for (0..matrix_len) |record_index| {
        try class_matrix.append(
            allocator,
            try view.readI16(
                subtable_offset + 16 + record_index * value_size,
            ),
        );
    }
    return .{
        .kind = if (dense)
            .format_2_dense_x_advance
        else
            .format_2_x_advance,
        .record_start = if (dense) ranges.?.coverage_base else 0,
        .record_len = if (dense) ranges.?.class_2_base else 0,
        .coverage_start = coverage_start,
        .coverage_len = coverage_classes.items.len - coverage_start,
        .class_2_start = class_2_start,
        .class_2_len = class_entries.items.len - class_2_start,
        .class_1_count = class_1_count,
        .class_2_count = class_2_count,
        .matrix_start = matrix_start,
    };
}

pub fn denseRanges(
    coverage: []const model.PairClassEntry,
    class_2: []const model.PairClassEntry,
) ?DenseRanges {
    if (coverage.len == 0) return null;
    const coverage_base = coverage[0].glyph;
    const coverage_end = coverage[coverage.len - 1].glyph;
    if (coverage_end < coverage_base) return null;
    const class_2_base = if (class_2.len != 0) class_2[0].glyph else 0;
    const class_2_end =
        if (class_2.len != 0) class_2[class_2.len - 1].glyph else 0;
    if (class_2_end < class_2_base) return null;
    return .{
        .coverage_base = coverage_base,
        .coverage_len = @as(usize, coverage_end) - coverage_base + 1,
        .class_2_base = class_2_base,
        .class_2_len = if (class_2.len != 0)
            @as(usize, class_2_end) - class_2_base + 1
        else
            0,
    };
}

pub fn entriesFitDenseRanges(
    coverage: []const model.PairClassEntry,
    class_2: []const model.PairClassEntry,
    ranges: DenseRanges,
) bool {
    const coverage_end = @as(usize, ranges.coverage_base) + ranges.coverage_len;
    for (coverage) |entry| {
        if (entry.glyph < ranges.coverage_base or
            entry.glyph >= coverage_end)
        {
            return false;
        }
    }
    const class_2_end = @as(usize, ranges.class_2_base) + ranges.class_2_len;
    for (class_2) |entry| {
        if (entry.glyph < ranges.class_2_base or entry.glyph >= class_2_end) {
            return false;
        }
    }
    return true;
}

pub fn shouldBuildDense(ranges: DenseRanges) bool {
    return ranges.coverage_len <= max_dense_class_entries and
        ranges.class_2_len <= max_dense_class_entries - ranges.coverage_len;
}

pub fn shouldBuildDenseFormat1(
    reachable_pair_sets: usize,
    dense_glyph_span: usize,
) bool {
    return reachable_pair_sets >= min_dense_pair_sets and
        dense_glyph_span != 0 and
        dense_glyph_span <= max_dense_class_entries;
}

fn appendClassDefEntries(
    view: View,
    class_def_offset: usize,
    entries: *std.ArrayList(model.PairClassEntry),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!bool {
    const start_len = entries.items.len;
    switch (try view.readU16(class_def_offset)) {
        1 => {
            const start = try view.readU16(class_def_offset + 2);
            const count = try view.readU16(class_def_offset + 4);
            if (count > max_class_glyphs) return false;
            for (0..count) |index| {
                const class =
                    try view.readU16(class_def_offset + 6 + index * 2);
                if (class == 0) continue;
                try entries.append(allocator, .{
                    .glyph = @intCast(@as(usize, start) + index),
                    .class = class,
                });
            }
        },
        2 => {
            const range_count = try view.readU16(class_def_offset + 2);
            for (0..range_count) |range_index| {
                const range = class_def_offset + 4 + range_index * 6;
                const start = try view.readU16(range);
                const end = try view.readU16(range + 2);
                const class = try view.readU16(range + 4);
                if (class == 0) continue;
                const len = @as(usize, end) - @as(usize, start) + 1;
                if (entries.items.len - start_len + len > max_class_glyphs) {
                    entries.shrinkRetainingCapacity(start_len);
                    return false;
                }
                for (0..len) |index| {
                    try entries.append(allocator, .{
                        .glyph = @intCast(@as(usize, start) + index),
                        .class = class,
                    });
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
    return true;
}

fn replaceWithDenseCoverage(
    entries: *std.ArrayList(model.PairClassEntry),
    start: usize,
    ranges: DenseRanges,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    const dense = try allocator.alloc(model.PairClassEntry, ranges.coverage_len);
    defer allocator.free(dense);
    for (dense, 0..) |*entry, index| {
        entry.* = .{
            .glyph = @intCast(@as(usize, ranges.coverage_base) + index),
            // Class1Count cannot admit this value, so it is an uncovered
            // sentinel distinct from valid covered class zero.
            .class = std.math.maxInt(u16),
        };
    }
    for (entries.items[start..]) |entry| {
        dense[entry.glyph - ranges.coverage_base] = entry;
    }
    entries.shrinkRetainingCapacity(start);
    try entries.appendSlice(allocator, dense);
}

fn replaceWithDenseClasses(
    entries: *std.ArrayList(model.PairClassEntry),
    start: usize,
    ranges: DenseRanges,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!void {
    const dense = try allocator.alloc(model.PairClassEntry, ranges.class_2_len);
    defer allocator.free(dense);
    for (dense, 0..) |*entry, index| {
        entry.* = .{
            .glyph = @intCast(@as(usize, ranges.class_2_base) + index),
            .class = 0,
        };
    }
    for (entries.items[start..]) |entry| {
        dense[entry.glyph - ranges.class_2_base] = entry;
    }
    entries.shrinkRetainingCapacity(start);
    try entries.appendSlice(allocator, dense);
}

fn requiredOffset(view: View, base: usize, relative: u16) Error!usize {
    return table.offset.required16(view, base, relative);
}
