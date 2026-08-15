//! Shared COLR v1 Paint byte-grammar records.

pub const Error = error{BadSfnt} || error{EndOfStream};

pub const Table = struct {
    offset: usize,
    length: usize,
};

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
