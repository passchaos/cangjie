//! ChainContextSubst format-2 class execution surface.

const accelerated = @import("accelerated.zig");
const direct = @import("direct.zig");

pub const subtable = direct.subtable;
pub const at = direct.at;
pub const acceleratedLookup = accelerated.lookup;
pub const acceleratedAt = accelerated.at;
