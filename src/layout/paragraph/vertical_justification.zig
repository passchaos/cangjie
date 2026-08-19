//! Generic spacing expansion along the vertical positive-down inline axis.
//!
//! Vertical column selection records targets only for non-terminal soft wraps.
//! This presentation pass runs after line limiting/ellipsis and before
//! punctuation compression or bidi, so source-order space/CJK opportunities
//! update the same y advances consumed by carets, selection, objects, and the
//! renderer.

const inline_justification = @import("../justification/inline.zig");
const paragraph_options = @import("options.zig");
const vertical_inline_region = @import("vertical_inline_region.zig");

pub fn apply(
    buffer: anytype,
    options: paragraph_options.Options,
) void {
    for (buffer.lines.items) |*line| {
        const target = line.justification_target orelse continue;
        const glyph_end = line.glyph_start + line.glyph_len;
        const glyphs = buffer.glyphs.items[line.glyph_start..glyph_end];
        var natural_size: f32 = 0;
        for (glyphs) |glyph| natural_size += glyph.y_advance;

        line.height = inline_justification.apply(
            glyphs,
            natural_size,
            target,
            options.writing_mode,
        );
        line.y = vertical_inline_region.origin(
            line.*,
            options,
            line.height,
        );
        line.justification_target = null;
    }
}
