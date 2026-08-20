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
pub const Attributes = face.Attributes;
pub const Stretch = face.Stretch;
pub const Style = face.Style;
pub const Weight = face.Weight;
pub const Glyphs = face.Glyphs;
pub const GlyphSession = face.GlyphSession;
pub const Metrics = face.Metrics;
pub const GlobalMetrics = @import("../../font/face/views/metrics.zig").Global;
pub const Names = face.Names;
pub const NameId = font_mod.NameId;
pub const LocalizedName = font_mod.LocalizedName;
pub const Variations = face.Variations;
pub const Color = face.Color;
pub const Error = font_mod.FontError;
pub const Format = font_mod.FontFormat;
pub const HintingInstance = font_mod.TrueTypeHintingInstance;
pub const HintingTarget = font_mod.TrueTypeHintingTarget;
pub const HintingInterpreter = font_mod.TrueTypeHintingInterpreter;
pub const HintingOptions = font_mod.TrueTypeHintingOptions;
pub const HintingError = font_mod.TrueTypeHintingError;
/// Interpreter-bound glyf point owner with atomic simple/compound execution.
pub const HintingPointTransaction = font_mod.TrueTypePointTransaction;
/// Path coordinates are pixels and must not be scaled by units-per-em again.
pub const PixelOutline = font_mod.TrueTypePixelOutline;
pub const Type2HintingInstance = font_mod.Type2HintingInstance;
pub const Type2HintingError = font_mod.Type2HintingError;

pub const GlyphId = glyph.GlyphId;
pub const Bounds = glyph.Bounds;
pub const Outline = glyph.GlyphOutline;
pub const OutlineBuilder = glyph.OutlineBuilder;
pub const OutlineCommand = glyph.PathCommand;
pub const OutlinePoint = glyph.Point;
pub const LigatureCaret = font_mod.LigatureCaret;
pub const AttachmentPoint = font_mod.AttachmentPoint;

/// An ordered list of faces used for cluster-safe fallback.
pub const Cascade = face.Cascade;

pub const metadata = @import("metadata.zig");
pub const container = @import("container.zig");
pub const database = @import("database.zig");
