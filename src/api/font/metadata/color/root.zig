//! Modern COLR/CPAL, SVG, and embedded bitmap glyph records.

const font = @import("../../../../font.zig");

pub const Layer = font.ColorLayer;
pub const Paint = font.ColorPaint;
pub const ClipBox = font.ColorClipBox;
pub const Affine = font.ColorAffine;
pub const PaletteColor = font.PaletteColor;
pub const Palette = font.PaletteInfo;

pub const SvgDocument = font.SvgGlyphDocument;
pub const ResolvedSvgDocument = font.ResolvedSvgGlyphDocument;
pub const BitmapPng = font.BitmapGlyphPng;
pub const BitmapBgra = font.BitmapGlyphBgra;
pub const BitmapMask = font.BitmapGlyphMask;
pub const BitmapData = font.BitmapGlyphData;
pub const OwnedBitmapData = font.OwnedBitmapGlyphData;
pub const BitmapGlyph = font.BitmapGlyphInfo;
pub const BitmapStrike = font.BitmapStrikeInfo;
pub const BitmapStrikeSource = font.BitmapStrikeSource;

pub const Inspection = @import("inspection.zig").View;
pub const inspect = @import("inspection.zig").inspect;
