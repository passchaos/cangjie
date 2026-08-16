//! ContextPos execution for whole-run and nested-target paths.
//!
//! PosLookupRecord execution remains owned by the root lookup dispatcher
//! because it can recurse into every lookup kind. The concrete executor is
//! supplied at comptime, preserving static calls without an erased context.

const std = @import("std");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const contextual_matching = @import("matching.zig");
const run_matching = @import("../../matching.zig");
const model = @import("model.zig");
const output = @import("../../output/root.zig");
const positioning = @import("../../../positioning/root.zig");
const rules = @import("rules.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = model.Adjustment;
pub const Error = model.Error;
pub const Options = model.Options;
pub const Result = model.Result;
pub const View = table.View;
pub const ApplyRecordsFn = model.ApplyRecordsFn;

pub fn collect(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!void {
    switch (try positioning.lookup.contextual.parseContext(
        view,
        subtable_offset,
    )) {
        .glyph => |subtable| {
            var position: usize = 0;
            while (position < glyphs.len) {
                var next_position = position + 1;
                defer position = next_position;
                if (run_matching.matchSkipsGlyph(
                    lookup_flag,
                    run,
                    glyphs,
                    position,
                )) continue;
                const coverage = try table.coverage.index(
                    view,
                    subtable.coverage_offset,
                    glyphs[position],
                ) orelse continue;
                if (coverage >= subtable.sets.count) continue;
                const set =
                    try subtable.sets.resolve(view, coverage) orelse continue;
                const result = try rules.collectGlyphSet(
                    view,
                    set,
                    glyphs,
                    position,
                    adjustments,
                    allocator,
                    lookup_flag,
                    run,
                    applyRecords,
                );
                if (result.matched) {
                    next_position = @max(next_position, result.next_pos);
                }
            }
        },
        .class => |subtable| try collectClass(
            view,
            subtable,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
        .coverage => |subtable| try collectCoverage(
            view,
            subtable,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
    }
}

pub fn collectAt(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!bool {
    if (position >= glyphs.len) return false;
    return switch (try positioning.lookup.contextual.parseContext(
        view,
        subtable_offset,
    )) {
        .glyph => |subtable| blk: {
            if (run_matching.matchSkipsGlyph(
                lookup_flag,
                run,
                glyphs,
                position,
            )) break :blk false;
            const coverage = try table.coverage.index(
                view,
                subtable.coverage_offset,
                glyphs[position],
            ) orelse break :blk false;
            if (coverage >= subtable.sets.count) break :blk false;
            const set =
                try subtable.sets.resolve(view, coverage) orelse break :blk false;
            break :blk (try rules.collectGlyphSet(
                view,
                set,
                glyphs,
                position,
                adjustments,
                allocator,
                lookup_flag,
                run,
                applyRecords,
            )).matched;
        },
        .class => |subtable| try collectClassAt(
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
        .coverage => |subtable| (try collectCoverageAt(
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        )).matched,
    };
}

fn collectClass(
    view: View,
    subtable: positioning.lookup.contextual.ContextClass,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.len) {
        var next_position = position + 1;
        defer position = next_position;
        if (run_matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            position,
        )) continue;
        if (try table.coverage.index(
            view,
            subtable.coverage_offset,
            glyphs[position],
        ) == null) continue;
        const class = try table.class_def.value(
            view,
            subtable.class_def_offset,
            glyphs[position],
        );
        if (class >= subtable.sets.count) continue;
        const set =
            try subtable.sets.resolve(view, class) orelse continue;
        const result = try rules.collectClassSet(
            view,
            set,
            subtable.class_def_offset,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        );
        if (result.matched) {
            next_position = @max(next_position, result.next_pos);
        }
    }
}

fn collectClassAt(
    view: View,
    subtable: positioning.lookup.contextual.ContextClass,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!bool {
    if (position >= glyphs.len) return false;
    if (run_matching.matchSkipsGlyph(lookup_flag, run, glyphs, position)) {
        return false;
    }
    if (try table.coverage.index(
        view,
        subtable.coverage_offset,
        glyphs[position],
    ) == null) return false;
    const class = try table.class_def.value(
        view,
        subtable.class_def_offset,
        glyphs[position],
    );
    if (class >= subtable.sets.count) return false;
    const set = try subtable.sets.resolve(view, class) orelse return false;
    return (try rules.collectClassSet(
        view,
        set,
        subtable.class_def_offset,
        glyphs,
        position,
        adjustments,
        allocator,
        lookup_flag,
        run,
        applyRecords,
    )).matched;
}

fn collectCoverage(
    view: View,
    subtable: positioning.lookup.contextual.ContextCoverage,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!void {
    var position: usize = 0;
    while (position < glyphs.len) {
        const result = try collectCoverageAt(
            view,
            subtable,
            glyphs,
            position,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        );
        position = if (result.matched)
            @max(position + 1, result.next_pos)
        else
            position + 1;
    }
}

fn collectCoverageAt(
    view: View,
    subtable: positioning.lookup.contextual.ContextCoverage,
    glyphs: []const GlyphId,
    position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!Result {
    if (position >= glyphs.len) return .{};
    if (run_matching.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs[position],
    )) return .{};
    const glyph_count = subtable.records.input_count;
    if (glyph_count == 0) return .{};
    var input_indices_buffer: [64]usize = undefined;
    if (glyph_count > input_indices_buffer.len) {
        return error.UnsupportedGpos;
    }
    const input_indices = input_indices_buffer[0..glyph_count];
    if (!contextual_matching.forward(
        glyphs,
        position,
        lookup_flag,
        run,
        input_indices,
    )) return .{};

    for (input_indices, 0..) |glyph_index, input_index| {
        const coverage =
            try subtable.input_coverages.coverageOffset(view, input_index);
        if (!try table.coverage.contains(
            view,
            coverage,
            glyphs[glyph_index],
            .membership,
        )) return .{};
    }
    try output.safety.markContext(allocator, &run, input_indices);
    try applyRecords(
        view,
        subtable.records.records_pos,
        subtable.records.count,
        input_indices,
        glyphs,
        adjustments,
        allocator,
        run,
    );
    return .{
        .matched = true,
        .next_pos = input_indices[glyph_count - 1] + 1,
    };
}
