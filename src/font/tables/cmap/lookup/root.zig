//! cmap scalar and variation-sequence lookup surface.

const scalar = @import("scalar.zig");
const variation = @import("variation.zig");

pub const glyph = scalar.glyph;
pub const VariationResult = variation.Result;
pub const variationGlyph = variation.lookup;
