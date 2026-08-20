//! Physical block-axis metrics for one vertical column.

const geometry = @import("../line_break/reflow/geometry.zig");
const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const inline_object = @import("../inline_object/root.zig");
const paragraph_options = @import("options.zig");
const CascadeRun = @import("../types/runs.zig").CascadeRun;

pub const Result = struct {
    line_info: geometry.LineRunInfo,
    block_size: f32,
};

pub fn resolve(
    runs: []const CascadeRun,
    glyphs: []const GlyphPosition,
    options: paragraph_options.Options,
    default_metrics: geometry.BaselineMetrics,
    glyph_start: usize,
    glyph_end: usize,
) !Result {
    const info = geometry.resolvedLineInfo(
        runs,
        glyphs,
        // Inline-object baselines describe horizontal line boxes. Vertical
        // columns use physical object width as block extent instead.
        &.{},
        glyph_start,
        glyph_end,
        default_metrics,
        options.line_height,
        null,
    );
    var block_size = info.metrics.lineHeight();
    for (glyphs[glyph_start..glyph_end]) |glyph| {
        if (!glyph.isInlineObject()) continue;
        const object = inline_object.find(
            options.inline_objects,
            glyph.cluster,
        ) orelse return error.InvalidInlineObjects;
        if (object.kind == .in_flow) {
            block_size = @max(block_size, object.width);
        }
    }
    return .{ .line_info = info, .block_size = block_size };
}
