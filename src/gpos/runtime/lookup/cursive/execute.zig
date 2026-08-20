//! CursivePos table traversal for full and nested lookup execution.

const std = @import("std");
const chain = @import("chain.zig");
const accelerator = @import("../../../accelerator/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const positioning = @import("../../../positioning/root.zig");
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const output = @import("../../output/root.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Anchor = positioning.anchor.Value;
pub const Error = table.view.Error || error{UnsupportedGpos};
pub const Options = options.Options;
pub const Parsed = accelerator.model.CursivePositionSubtable;
pub const View = table.View;

pub fn build(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Parsed {
    var parsed =
        try positioning.lookup.cursive.parse(view, subtable_offset);
    errdefer if (parsed.coverage) |coverage| coverage.deinit(allocator);
    parsed.coverage = try accelerator.coverage.Owned.build(
        view,
        parsed.coverage_offset,
        allocator,
    );
    return parsed;
}

pub fn deinit(
    allocator: std.mem.Allocator,
    subtables: []const Parsed,
) void {
    accelerator.model.deinitCursiveSubtables(subtables, allocator);
}

pub fn collect(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    return collectParsed(
        view,
        try positioning.lookup.cursive.parse(view, subtable_offset),
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn collectParsed(
    view: View,
    parsed: Parsed,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;

    var previous_covered_position: ?usize = null;
    var previous_coverage_index: usize = 0;
    for (glyphs, 0..) |glyph, glyph_index| {
        if (matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        const current_coverage_index = (if (parsed.coverage) |coverage|
            coverage.index(glyph)
        else
            try table.coverage.index(
                view,
                parsed.coverage_offset,
                glyph,
            )) orelse {
            // A non-ignored, non-covered glyph breaks cursive adjacency.
            // LookupFlag-ignored glyphs remain transparent.
            previous_covered_position = null;
            continue;
        };
        if (current_coverage_index >= parsed.entry_exit_count) {
            previous_covered_position = null;
            continue;
        }

        if (previous_covered_position) |previous_position| {
            const entry_relative = try entryOffset(
                view,
                parsed,
                current_coverage_index,
            );
            const exit_relative = try exitOffset(
                view,
                parsed,
                previous_coverage_index,
            );
            if (entry_relative != 0 and exit_relative != 0) {
                const entry = try readAnchor(
                    view,
                    parsed.subtable_offset + entry_relative,
                    run,
                );
                const exit = try readAnchor(
                    view,
                    parsed.subtable_offset + exit_relative,
                    run,
                );
                try output.safety.markPair(
                    allocator,
                    &run,
                    previous_position,
                    glyph_index,
                );
                try chain.appendJoin(
                    adjustments,
                    allocator,
                    previous_position,
                    glyph_index,
                    exit,
                    entry,
                    lookup_flag,
                    run.direction,
                );
            }
        }
        previous_covered_position = glyph_index;
        previous_coverage_index = current_coverage_index;
    }
}

/// Apply one nested CursivePos target without rescanning and positioning every
/// covered join in the run.
pub fn collectAt(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    if (target_index >= glyphs.len) return false;
    const glyph = glyphs[target_index];
    if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;

    const parsed = try positioning.lookup.cursive.parse(
        view,
        subtable_offset,
    );
    const current_index =
        try table.coverage.index(view, parsed.coverage_offset, glyph) orelse
        return false;
    if (current_index >= parsed.entry_exit_count) return false;
    const previous_position = try previousCoveredGlyph(
        view,
        parsed,
        glyphs,
        target_index,
        lookup_flag,
        run,
    ) orelse return false;
    const previous_index = (try table.coverage.index(
        view,
        parsed.coverage_offset,
        glyphs[previous_position],
    )) orelse return false;

    const entry_relative = try entryOffset(view, parsed, current_index);
    const exit_relative = try exitOffset(view, parsed, previous_index);
    if (entry_relative == 0 or exit_relative == 0) return false;

    const entry = try readAnchor(
        view,
        subtable_offset + entry_relative,
        run,
    );
    const exit = try readAnchor(
        view,
        subtable_offset + exit_relative,
        run,
    );
    try output.safety.markPair(
        allocator,
        &run,
        previous_position,
        target_index,
    );
    try chain.appendJoin(
        adjustments,
        allocator,
        previous_position,
        target_index,
        exit,
        entry,
        lookup_flag,
        run.direction,
    );
    return true;
}

fn entryOffset(view: View, parsed: Parsed, coverage_index: usize) Error!u16 {
    return view.readU16(parsed.subtable_offset + 6 + coverage_index * 4);
}

fn exitOffset(view: View, parsed: Parsed, coverage_index: usize) Error!u16 {
    return view.readU16(
        parsed.subtable_offset + 6 + coverage_index * 4 + 2,
    );
}

fn readAnchor(view: View, anchor_offset: usize, run: Options) Error!Anchor {
    return positioning.anchor.read(view, anchor_offset, .{
        .normalized_coords = run.normalized_variation_coords,
        .variation_store = run.gdef_variation_store,
    });
}

fn previousCoveredGlyph(
    view: View,
    parsed: Parsed,
    glyphs: []const GlyphId,
    target_index: usize,
    lookup_flag: u16,
    run: Options,
) Error!?usize {
    var glyph_index = target_index;
    while (glyph_index > 0) {
        glyph_index -= 1;
        if (matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) continue;
        const coverage = try table.coverage.index(
            view,
            parsed.coverage_offset,
            glyphs[glyph_index],
        ) orelse return null;
        return if (coverage < parsed.entry_exit_count) glyph_index else null;
    }
    return null;
}
