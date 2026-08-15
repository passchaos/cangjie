//! Incremental Font Transfer and patch metadata.

const font = @import("../../../../font.zig");

pub const PatchMap = font.IftPatchMapInfo;
pub const TablePatch = font.IftTableKeyedPatchInfo;
pub const GlyphPatch = font.IftGlyphKeyedPatchInfo;
