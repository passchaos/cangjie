//! Shared COLR v1 directory and ClipBox records.

pub const Error = error{BadSfnt} || error{EndOfStream};

pub const Table = struct {
    offset: usize,
    length: usize,
};

pub const Range = struct {
    start: usize,
    end: usize,
};

pub const ClipList = struct {
    offset: usize,
    start: usize,
    count: usize,
    records_start: usize,
    data_start: usize,
};

pub const ClipBox = struct {
    format: u8,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
    var_index_base: ?u32,
    range: Range,
};
