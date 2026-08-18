//! Font loading, inspection, outlines, and glyph identity.
//!
//! The namespace keeps the normal face API small. Less frequently used table
//! records live under `metadata`, container decoding under `container`, and
//! collection/fallback discovery under `database`.

const face = @import("../../font/face/root.zig");
const font_mod = @import("../../font.zig");
const glyph = @import("../../glyph.zig");

pub const Face = face.Face;
pub const Properties = face.Properties;
pub const Glyphs = face.Glyphs;
pub const Metrics = face.Metrics;
pub const Names = face.Names;
pub const Variations = face.Variations;
pub const Color = face.Color;
pub const Error = font_mod.FontError;
pub const Format = font_mod.FontFormat;
pub const HintingInstance = font_mod.TrueTypeHintingInstance;
pub const HintingTarget = font_mod.TrueTypeHintingTarget;
pub const HintingError = font_mod.TrueTypeHintingError;

pub const GlyphId = glyph.GlyphId;
pub const Bounds = glyph.Bounds;
pub const Outline = glyph.GlyphOutline;
pub const OutlineBuilder = glyph.OutlineBuilder;
pub const LigatureCaret = font_mod.LigatureCaret;
pub const AttachmentPoint = font_mod.AttachmentPoint;

/// An ordered list of faces used for cluster-safe fallback.
pub const Cascade = face.Cascade;

pub const metadata = @import("metadata.zig");
pub const container = @import("container.zig");
pub const database = @import("database.zig");
