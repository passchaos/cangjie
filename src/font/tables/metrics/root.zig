//! Modern horizontal and vertical SFNT metric table surface.

pub const header = @import("header.zig");
pub const records = @import("records.zig");
pub const types = @import("types.zig");

pub const Header = types.Header;
pub const Horizontal = types.Horizontal;
pub const Vertical = types.Vertical;

pub const validateHorizontal = records.validateHorizontal;
pub const validateVertical = records.validateVertical;
pub const horizontal = records.horizontal;
pub const vertical = records.vertical;
pub const requiredLength = records.requiredLength;
