//! Public value types for legacy OpenType and Apple kern tables.

pub const Dialect = enum {
    legacy,
    apple,
    unsupported,
};

pub const Subtable = struct {
    offset: usize,
    length: usize,
    format: u16,
    coverage: u16,
    horizontal: bool,
    minimum: bool,
    cross_stream: bool,
    variation: bool = false,
    override: bool = false,
    tuple_index: ?u16 = null,
    pair_count: ?u16 = null,
};

pub const Info = struct {
    dialect: Dialect,
    version: u32,
    subtables: []Subtable,
};
