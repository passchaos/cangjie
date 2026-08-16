//! CFF/CFF2 outline value conversion independent of font-table ownership.

const cff2 = @import("../../opentype/cff2.zig");
const glyph = @import("../../glyph.zig");
const numeric = @import("numeric.zig");

pub fn boundsFromCff2(bounds: cff2.CharStringBoundsInfo) glyph.Bounds {
    if (!bounds.has_bounds) {
        return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
    }
    // HarfBuzz and FreeType round each design coordinate to the nearest FUnit
    // with OpenType's +infinity tie rule. Expanding minima with floor and
    // maxima with ceil makes every fractional outline one unit too large.
    return .{
        .x_min = numeric.clampF32ToI16(numeric.roundOpenType(bounds.x_min)),
        .y_min = numeric.clampF32ToI16(numeric.roundOpenType(bounds.y_min)),
        .x_max = numeric.clampF32ToI16(numeric.roundOpenType(bounds.x_max)),
        .y_max = numeric.clampF32ToI16(numeric.roundOpenType(bounds.y_max)),
    };
}
