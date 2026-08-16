//! MarkLigPos execution.

const std = @import("std");
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
pub const Parsed = positioning.lookup.marks.MarkToLigature;
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
    const parsed = try positioning.lookup.marks.parseMarkToLigature(
        view,
        subtable_offset,
    );
    if (parsed.class_count == 0 or glyphs.len < 2) return;
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

fn collectAtParsed(
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
    if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
    if (parsed.class_count == 0 or glyphs.len < 2) return false;

    const mark_index = try table.coverage.index(
        view,
        parsed.mark_coverage_offset,
        glyph,
    ) orelse return false;
    const ligature_position = try search.previousCoveredLigature(
        view,
        parsed.mark_coverage_offset,
        glyphs,
        mark_position,
        lookup_flag,
        run,
    ) orelse return false;
    const ligature_index = try table.coverage.index(
        view,
        parsed.ligature_coverage_offset,
        glyphs[ligature_position],
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
    const component_index = try search.ligatureComponentIndex(
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
