//! Public records and validated layout for OpenType `CPAL`.

const name = @import("../../../../opentype/name.zig");

pub const Error = name.Error || error{EndOfStream};

/// Minimal table view that keeps SFNT directory and checksum ownership in
/// `Font` while allowing this module to own CPAL-relative offsets.
pub const Table = struct {
    offset: usize,
    length: usize,
};

pub const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const Palette = struct {
    first_color_index: u16,
    color_count: u16,
    palette_type: u32 = 0,
    label_name_id: ?u16 = null,
};

/// Parsed offsets are retained only after whole-table structural validation.
/// Read helpers consume this proof so public Font methods can revalidate
/// borrowed bytes once without independently reproducing CPAL layout math.
pub const Layout = struct {
    version: u16,
    palette_entries: u16,
    palette_count: u16,
    color_count: u16,
    color_records_offset: usize,
    palette_types_offset: usize = 0,
    palette_labels_offset: usize = 0,
    palette_entry_labels_offset: usize = 0,
};
