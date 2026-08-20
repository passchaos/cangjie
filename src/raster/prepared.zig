//! Owned scan geometry prepared for repeated glyph rendering.

const prepared_scanline = @import("prepared_scanline.zig");

pub const PreparedGlyph = struct {
    prepared_fill: prepared_scanline.PreparedFill,
    hint_size: f32,

    /// Whether retained real-font measurements predict a win over direct
    /// rendering in a repeated-render loop.
    ///
    /// Callers should branch once before entering the loop. Tiny straight-sided
    /// glyphs already use the direct stack-local path efficiently; retained
    /// geometry pays off for curve-heavy or multi-contour outlines.
    pub fn recommendedForRepeatedRendering(self: *const PreparedGlyph) bool {
        return self.prepared_fill.lines.len >= 16;
    }

    pub fn deinit(self: *PreparedGlyph) void {
        self.prepared_fill.deinit();
        self.* = undefined;
    }
};
