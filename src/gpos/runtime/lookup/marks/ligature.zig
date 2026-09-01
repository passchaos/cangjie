//! MarkLigPos execution.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const runtime_output = @import("../../output/root.zig");
const attachment_output = @import("output.zig");
const positioning = @import("../../../positioning/root.zig");
const search = @import("search.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error =
    table.view.Error || error{ UnsupportedGpos, InvalidShapingInput };
pub const Options = options.Options;
pub const Parsed = accelerator.model.MarkToLigatureSubtable;
pub const View = table.View;

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
        try positioning.lookup.marks.parseMarkToLigature(
            view,
            subtable_offset,
        ),
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
    if (parsed.class_count == 0 or glyphs.len < 2) return;
    // The prepared mark Coverage is normally far smaller than the run. Scan
    // only its glyph IDs, then recover authored run order with one bounded
    // pass; this avoids paying an owned-coverage lookup for every non-mark.
    const mark_coverage = parsed.mark_coverage orelse {
        for (0..glyphs.len) |glyph_index| {
            _ = try collectAtParsed(
                view,
                parsed,
                glyphs,
                glyph_index,
                adjustments,
                allocator,
                lookup_flag,
                run,
            );
        }
        return;
    };
    for (glyphs, 0..) |glyph, glyph_index| {
        if (mark_coverage.index(glyph) == null) continue;
        _ = try collectAtParsed(
            view,
            parsed,
            glyphs,
            glyph_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        );
    }
}

pub fn collectAt(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    mark_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    return collectAtParsed(
        view,
        try positioning.lookup.marks.parseMarkToLigature(
            view,
            subtable_offset,
        ),
        glyphs,
        mark_position,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn collectAtParsed(
    view: View,
    parsed: Parsed,
    glyphs: []const GlyphId,
    mark_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    return collectAtPrepared(
        view,
        parsed,
        glyphs,
        mark_position,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

fn collectAtPrepared(
    view: View,
    parsed: Parsed,
    glyphs: []const GlyphId,
    mark_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    if (mark_position >= glyphs.len) return false;
    const glyph = glyphs[mark_position];
    if (parsed.class_count == 0 or glyphs.len < 2) return false;

    const mark_index = if (parsed.mark_coverage) |coverage| accelerated: {
        // Prepared coverages are immutable and validated. Reject the common
        // non-covered glyph before potentially consulting GDEF mark filters.
        const index = coverage.index(glyph) orelse return false;
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
        break :accelerated index;
    } else unaccelerated: {
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
        break :unaccelerated try table.coverage.index(
            view,
            parsed.mark_coverage_offset,
            glyph,
        ) orelse return false;
    };
    const ligature_position = if (parsed.mark_coverage != null)
        try search.previousCoveredLigatureParsed(
            view,
            parsed,
            glyphs,
            mark_position,
            lookup_flag,
            run,
        ) orelse return false
    else
        try search.previousCoveredLigature(
            view,
            parsed.mark_coverage_offset,
            glyphs,
            mark_position,
            lookup_flag,
            run,
        ) orelse return false;
    const ligature_glyph = glyphs[ligature_position];
    const ligature_index = if (parsed.ligature_coverage) |coverage|
        coverage.index(ligature_glyph) orelse return false
    else
        try table.coverage.index(
            view,
            parsed.ligature_coverage_offset,
            ligature_glyph,
        ) orelse return false;
    const mark_record = parsed.mark_array_offset + 2 + mark_index * 4;
    const mark_class = try view.readU16(mark_record);
    if (mark_class >= parsed.class_count) return false;
    const mark_anchor = try positioning.anchor.read(
        view,
        try table.offset.required16(
            view,
            parsed.mark_array_offset,
            try view.readU16(mark_record + 2),
        ),
        anchorOptions(run),
    );
    const ligature_attach = try table.offset.required16(
        view,
        parsed.ligature_array_offset,
        try view.readU16(
            parsed.ligature_array_offset + 2 + ligature_index * 2,
        ),
    );
    const component_count = try view.readU16(ligature_attach);
    if (component_count == 0) return false;
    const component_index = if (parsed.mark_coverage != null)
        try search.ligatureComponentIndexParsed(
            view,
            parsed,
            glyphs,
            ligature_position,
            mark_position,
            component_count,
            lookup_flag,
            run,
        )
    else
        try search.ligatureComponentIndex(
            view,
            parsed.mark_coverage_offset,
            glyphs,
            ligature_position,
            mark_position,
            component_count,
            lookup_flag,
            run,
        );
    const anchor_record = ligature_attach + 2 +
        (component_index * parsed.class_count + mark_class) * 2;
    const ligature_anchor_relative = try view.readU16(anchor_record);
    if (ligature_anchor_relative == 0) return false;
    const ligature_anchor = try positioning.anchor.read(
        view,
        ligature_attach + ligature_anchor_relative,
        anchorOptions(run),
    );
    try runtime_output.safety.markPair(
        allocator,
        &run,
        ligature_position,
        mark_position,
    );
    try attachment_output.append(
        adjustments,
        allocator,
        mark_position,
        ligature_position,
        ligature_anchor.x - mark_anchor.x,
        ligature_anchor.y - mark_anchor.y,
        run.vertical,
    );
    return true;
}

fn anchorOptions(run: Options) positioning.anchor.Options {
    return .{
        .normalized_coords = run.normalized_variation_coords,
        .variation_store = run.gdef_variation_store,
    };
}
