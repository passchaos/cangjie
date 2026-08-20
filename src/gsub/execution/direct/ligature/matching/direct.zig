//! Table-backed LigatureSet matching in authored preference order.

const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const model = @import("../model.zig");
const traversal = @import("traversal.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const View = table.View;

pub fn find(
    view: View,
    set_offset: usize,
    glyphs: []const GlyphId,
    glyph_base: usize,
    lookup_flag: u16,
    run: Options,
    component_offsets: *[model.max_components]usize,
) Error!?model.Match {
    const ligature_count = try view.readU16(set_offset);
    const anchor_syllable = filtering.ligatureAnchorSyllable(run, glyph_base);
    for (0..ligature_count) |ligature_index| {
        const ligature_offset = table.offset.required16(
            view,
            set_offset,
            try view.readU16(set_offset + 2 + ligature_index * 2),
        ) catch continue;
        const ligature = try view.readU16(ligature_offset);
        const component_count = try view.readU16(ligature_offset + 2);
        if (component_count == 0 or
            component_count > model.max_components)
        {
            continue;
        }
        component_offsets[0] = 0;
        var cursor: usize = 1;
        var matched = true;
        for (1..component_count) |component_index| {
            const expected = try view.readU16(
                ligature_offset + 4 + (component_index - 1) * 2,
            );
            cursor = traversal.nextVisibleOffset(
                glyphs,
                glyph_base,
                cursor,
                lookup_flag,
                run,
                anchor_syllable,
            ) orelse {
                matched = false;
                break;
            };
            if (glyphs[cursor] != expected) {
                matched = false;
                break;
            }
            component_offsets[component_index] = cursor;
            cursor += 1;
        }
        if (matched) {
            return .{
                .ligature = ligature,
                .component_count = component_count,
                .component_offsets = component_offsets,
                .match_end = cursor,
            };
        }
    }
    return null;
}
