//! CPU raster targets and renderer-facing glyph draw lists.

const bridge = @import("../../render_bridge.zig");
const raster = @import("../../raster.zig");

pub const GrayTarget = raster.RenderTarget;
pub const ColorTarget = raster.ColorRenderTarget;
pub const Rgba = raster.Rgba;
pub const Rasterizer = raster.Rasterizer;
pub const PreparedGlyph = raster.PreparedGlyph;

pub const BridgeOptions = bridge.BridgeOptions;
pub const ColorGlyphPaint = bridge.ColorGlyphPaint;
pub const ColorGlyphDrawCommand = bridge.ColorGlyphDrawCommand;
pub const ColorGlyphLayerCommand = bridge.ColorGlyphLayerCommand;
pub const GlyphAtlasCacheKey = bridge.GlyphAtlasCacheKey;
pub const GlyphAtlasContent = bridge.GlyphAtlasContent;
pub const GlyphAtlasRequest = bridge.GlyphAtlasRequest;
pub const GlyphDrawList = bridge.GlyphDrawList;
pub const GlyphPathCacheKey = bridge.GlyphPathCacheKey;
pub const GlyphPathRequest = bridge.GlyphPathRequest;
pub const GlyphPathSource = bridge.GlyphPathSource;
pub const GlyphRenderMode = bridge.GlyphRenderMode;
pub const GlyphRunDrawCommand = bridge.GlyphRunDrawCommand;
pub const PositionedGlyph = bridge.PositionedGlyph;
pub const CursorGeometry = bridge.TextCursorGeometry;
pub const SelectionGeometry = bridge.TextSelectionGeometry;

pub const buildGlyphDrawList = bridge.buildGlyphDrawList;
