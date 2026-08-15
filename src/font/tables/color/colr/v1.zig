//! COLR v1 top-level directories and ClipList/ClipBox records.

const clip = @import("v1/clip.zig");
const directories = @import("v1/directories.zig");
const types = @import("v1/types.zig");

pub const paint = @import("v1/paint/root.zig");
pub const bases = @import("v1/bases.zig");
pub const layers = @import("v1/layers.zig");
pub const validation = @import("v1/validate/root.zig");
pub const variation = @import("v1/variation/root.zig");

pub const Error = types.Error;
pub const Table = types.Table;
pub const Range = types.Range;
pub const ClipList = types.ClipList;
pub const ClipBox = types.ClipBox;

pub const validateTopLevel = directories.validateTopLevel;
pub const baseGlyphListRange = directories.baseGlyphListRange;
pub const layerListRange = directories.layerListRange;
pub const clipListRange = directories.clipListRange;
pub const overlaps = directories.overlaps;

pub const validateClipList = clip.validate;
pub const clipListDirectory = clip.directory;
pub const clipBoxForGlyph = clip.boxForGlyph;
pub const clipBoxAtIndex = clip.boxAtIndex;
