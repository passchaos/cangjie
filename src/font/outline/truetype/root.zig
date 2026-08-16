//! Runtime TrueType outline materialization primitives.
//!
//! Table ownership, recursive glyph lookup, and public revalidation policy stay
//! in `Font`; these modules operate only on concrete values, pointers, and
//! borrowed slices.

pub const compound = @import("compound.zig");
pub const simple = @import("simple.zig");
pub const variation = @import("variation.zig");
