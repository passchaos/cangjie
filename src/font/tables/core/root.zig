//! Mandatory SFNT core table types, decoders, and validators.

pub const head = @import("head.zig");
pub const maxp = @import("maxp.zig");
pub const types = @import("types.zig");

pub const Format = types.Format;
pub const HeaderInfo = head.Info;
pub const MaxProfileInfo = maxp.Info;
