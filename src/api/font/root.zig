//! Font loading, inspection, outlines, and glyph identity.
//!
//! The namespace keeps the normal face API small. Less frequently used table
//! records live under `metadata`, container decoding under `container`, and
//! collection/fallback discovery under `database`.

const font_mod = @import("../../font.zig");
const glyph = @import("../../glyph.zig");

pub const Face = font_mod.Font;
pub const Error = font_mod.FontError;
pub const Format = font_mod.FontFormat;

pub const GlyphId = glyph.GlyphId;
pub const Bounds = glyph.Bounds;
pub const Outline = glyph.GlyphOutline;
pub const OutlineBuilder = glyph.OutlineBuilder;

/// An ordered list of faces used for cluster-safe fallback.
pub const Cascade = @import("../../layout.zig").FontCascade;

pub const metadata = @import("metadata.zig");
pub const container = @import("container.zig");
pub const database = @import("database.zig");
