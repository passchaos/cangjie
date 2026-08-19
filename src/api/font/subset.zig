//! Deterministic, bounded font-program subsetting.

const implementation = @import("../../font/subset/root.zig");

pub const GlyphId = implementation.GlyphId;
pub const Options = implementation.Options;
pub const Result = implementation.Result;
pub const trueTypeAlloc = implementation.trueTypeAlloc;
