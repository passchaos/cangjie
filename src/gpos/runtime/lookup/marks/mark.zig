//! MarkMarkPos execution.

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
pub const Parsed = positioning.lookup.marks.MarkToMark;
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
    const parsed = try positioning.lookup.marks.parseMarkToMark(
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
    mark_1_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    return collectAtParsed(
        view,
        try positioning.lookup.marks.parseMarkToMark(view, subtable_offset),
        glyphs,
        mark_1_position,
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
    mark_1_position: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    if (mark_1_position >= glyphs.len) return false;
    const glyph = glyphs[mark_1_position];
    if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
    if (parsed.class_count == 0 or glyphs.len < 2) return false;

    const mark_1_index = try table.coverage.index(
        view,
        parsed.mark_1_coverage_offset,
        glyph,
    ) orelse return false;
    const mark_2_position = try search.previousUnignoredCoveredGlyph(
        view,
        parsed.mark_2_coverage_offset,
        glyphs,
        mark_1_position,
        lookup_flag,
        run,
    ) orelse return false;
    if (!try search.shareLigatureComponent(
        view,
        parsed.mark_1_coverage_offset,
        glyphs,
        mark_1_position,
        mark_2_position,
        lookup_flag,
        run,
    )) return false;
    const mark_2_index = try table.coverage.index(
        view,
        parsed.mark_2_coverage_offset,
        glyphs[mark_2_position],
    ) orelse return false;
    const mark_1_record =
        parsed.mark_1_array_offset + 2 + mark_1_index * 4;
    const mark_class = try view.readU16(mark_1_record);
    if (mark_class >= parsed.class_count) return false;
    const mark_1_anchor = try positioning.anchor.read(
        view,
        try table.offset.required16(
            view,
            parsed.mark_1_array_offset,
            try view.readU16(mark_1_record + 2),
        ),
        anchorOptions(run),
    );
    const mark_2_anchor_record = parsed.mark_2_array_offset + 2 +
        (mark_2_index * parsed.class_count + mark_class) * 2;
    const mark_2_anchor_relative = try view.readU16(mark_2_anchor_record);
    if (mark_2_anchor_relative == 0) return false;
    const mark_2_anchor = try positioning.anchor.read(
        view,
        parsed.mark_2_array_offset + mark_2_anchor_relative,
        anchorOptions(run),
    );
    try runtime_output.safety.markPair(
        allocator,
        &run,
        mark_2_position,
        mark_1_position,
    );
    try attachment_output.append(
        adjustments,
        allocator,
        mark_1_position,
        mark_2_position,
        mark_2_anchor.x - mark_1_anchor.x,
        mark_2_anchor.y - mark_1_anchor.y,
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
