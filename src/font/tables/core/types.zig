//! Shared value types for mandatory SFNT core tables.

/// Outline stack selected from the SFNT flavor and complete table topology.
pub const Format = enum {
    truetype,
    opentype_cff,
};
