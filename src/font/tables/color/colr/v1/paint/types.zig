//! Shared COLR v1 Paint byte-grammar records.

const colr = @import("../types.zig");

// Paint parsing lives below the COLR v1 module but consumes the same byte
// domain and error contract. Keeping these as aliases avoids subtly distinct
// table descriptors at every boundary between directories, walkers, readers,
// and validators.
pub const Error = colr.Error;
pub const Table = colr.Table;

pub const Kind = enum {
    terminal,
    colr_layers,
    solid,
    glyph,
    colr_glyph,
    color_line,
    single_child,
    composite,
};

pub const FormatInfo = struct {
    min_size: usize,
    kind: Kind,
};

pub const Range = struct {
    start: usize,
    end: usize,
};
