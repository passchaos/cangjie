//! MarkBasePos execution and cached backward base search.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const output = @import("../../output/root.zig");
const positioning = @import("../../../positioning/root.zig");
const attachment_output = @import("output.zig");
const search = @import("search.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const Options = options.Options;
pub const Parsed = accelerator.model.MarkToBaseSubtable;
pub const View = table.View;

const SearchState = struct {
    last_candidate: ?usize = null,
    last_candidate_until: usize = 0,
};

pub fn build(
    view: View,
    subtable_offset: usize,
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!Parsed {
    var parsed =
        try positioning.lookup.marks.parseMarkToBase(view, subtable_offset);
    errdefer {
        if (parsed.mark_coverage) |coverage| coverage.deinit(allocator);
    }
    parsed.mark_coverage = try accelerator.coverage.Owned.build(
        view,
        parsed.mark_coverage_offset,
        allocator,
    );
    parsed.base_coverage = try accelerator.coverage.Owned.build(
        view,
        parsed.base_coverage_offset,
        allocator,
    );
    return parsed;
}

pub fn deinit(allocator: std.mem.Allocator, subtables: []const Parsed) void {
    accelerator.model.deinitMarkToBaseSubtables(subtables, allocator);
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
        try positioning.lookup.marks.parseMarkToBase(view, subtable_offset),
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn collectParsed(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (subtable.class_count == 0 or glyphs.len < 2) return;

    const attached_marks = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(attached_marks);
    @memset(attached_marks, false);

    var search_state: SearchState = .{};
    for (0..glyphs.len) |glyph_index| {
        if (try collectAtParsed(
            view,
            subtable,
            glyphs,
            glyph_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
            attached_marks,
            &search_state,
        )) {
            attached_marks[glyph_index] = true;
        }
    }
}

/// Apply one nested MarkBasePos target without positioning every covered mark.
pub fn collectAt(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    mark_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    attached_marks: []const bool,
) (Error || std.mem.Allocator.Error)!bool {
    return collectAtParsed(
        view,
        try positioning.lookup.marks.parseMarkToBase(view, subtable_offset),
        glyphs,
        mark_position,
        adjustments,
        allocator,
        lookup_flag,
        run,
        attached_marks,
        null,
    );
}

pub fn collectAtParsed(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    mark_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    attached_marks: []const bool,
    search_state: ?*SearchState,
) (Error || std.mem.Allocator.Error)!bool {
    if (mark_position >= glyphs.len) return false;
    const glyph = glyphs[mark_position];
    if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
    if (subtable.class_count == 0 or glyphs.len < 2) return false;

    const mark_index = if (subtable.mark_coverage) |coverage|
        coverage.index(glyph) orelse return false
    else
        try table.coverage.index(
            view,
            subtable.mark_coverage_offset,
            glyph,
        ) orelse return false;
    const base_position = (if (search_state) |state|
        try previousBaseCached(
            view,
            subtable,
            glyphs,
            mark_position,
            attached_marks,
            lookup_flag,
            run,
            state,
        )
    else
        try previousBase(
            view,
            subtable,
            glyphs,
            mark_position,
            attached_marks,
            lookup_flag,
            run,
        )) orelse return false;
    const base_glyph = glyphs[base_position];
    const base_index = if (subtable.base_coverage) |coverage|
        coverage.index(base_glyph) orelse return false
    else
        try table.coverage.index(
            view,
            subtable.base_coverage_offset,
            base_glyph,
        ) orelse return false;
    const mark_record = subtable.mark_array_offset + 2 + mark_index * 4;
    const mark_class = try view.readU16(mark_record);
    if (mark_class >= subtable.class_count) return false;
    const mark_anchor = try positioning.anchor.read(
        view,
        try table.offset.required16(
            view,
            subtable.mark_array_offset,
            try view.readU16(mark_record + 2),
        ),
        anchorOptions(run),
    );
    const base_anchor_record = subtable.base_array_offset + 2 +
        (base_index * subtable.class_count + mark_class) * 2;
    const base_anchor_relative = try view.readU16(base_anchor_record);
    if (base_anchor_relative == 0) return false;
    const base_anchor = try positioning.anchor.read(
        view,
        subtable.base_array_offset + base_anchor_relative,
        anchorOptions(run),
    );
    try output.safety.markPair(
        allocator,
        &run,
        base_position,
        mark_position,
    );
    try attachment_output.append(
        adjustments,
        allocator,
        mark_position,
        base_position,
        base_anchor.x - mark_anchor.x,
        base_anchor.y - mark_anchor.y,
        run.vertical,
    );
    return true;
}

fn previousBaseCached(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    mark_index: usize,
    attached_marks: []const bool,
    lookup_flag: u16,
    run: Options,
    state: *SearchState,
) Error!?usize {
    if (state.last_candidate_until > mark_index) state.* = .{};

    var candidate = state.last_candidate;
    var glyph_index = mark_index;
    while (glyph_index > state.last_candidate_until) {
        glyph_index -= 1;
        if (try skipsBaseSearchGlyph(
            view,
            subtable,
            glyphs,
            glyph_index,
            attached_marks,
            lookup_flag,
            run,
        )) continue;
        candidate = glyph_index;
        break;
    }
    state.last_candidate = candidate;
    state.last_candidate_until = mark_index;
    return candidate;
}

fn previousBase(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    mark_index: usize,
    attached_marks: []const bool,
    lookup_flag: u16,
    run: Options,
) Error!?usize {
    var glyph_index = mark_index;
    while (glyph_index > 0) {
        glyph_index -= 1;
        if (try skipsBaseSearchGlyph(
            view,
            subtable,
            glyphs,
            glyph_index,
            attached_marks,
            lookup_flag,
            run,
        )) continue;
        return glyph_index;
    }
    return null;
}

fn skipsBaseSearchGlyph(
    view: View,
    subtable: Parsed,
    glyphs: []const GlyphId,
    glyph_index: usize,
    attached_marks: []const bool,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    if (glyph_index < attached_marks.len and attached_marks[glyph_index]) {
        return true;
    }
    if (matching.matchSkipsGlyph(
        lookup_flag,
        run,
        glyphs,
        glyph_index,
    )) return true;

    // The nearest participating non-mark blocks an older base even when it is
    // outside BaseCoverage. Marks and MultipleSubst continuations are
    // transparent for stacked-mark clusters.
    const base_covered = if (subtable.base_coverage) |coverage|
        coverage.index(glyphs[glyph_index]) != null
    else
        try table.coverage.index(
            view,
            subtable.base_coverage_offset,
            glyphs[glyph_index],
        ) != null;
    if (base_covered) return false;
    return search.skipsNonCoveredGlyphParsed(
        view,
        subtable,
        glyphs,
        glyph_index,
        run,
    );
}

fn anchorOptions(run: Options) positioning.anchor.Options {
    return .{
        .normalized_coords = run.normalized_variation_coords,
        .variation_store = run.gdef_variation_store,
    };
}
