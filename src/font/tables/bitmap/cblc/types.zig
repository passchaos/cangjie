//! Shared CBLC index and CBDT payload records.

const glyph = @import("../../../../glyph.zig");
const bitmap = @import("../types.zig");

pub const Strike = struct {
    ppem: u16,
    ppi: u16,
    bit_depth: u8,
    offset: usize,
    index_tables_size: usize,
    table_count: usize,
    start_glyph: glyph.GlyphId,
    end_glyph: glyph.GlyphId,
};

pub const GlyphLocation = struct {
    image_format: u16,
    offset: usize,
    length: usize,
    /// Index formats 2 and 5 store one BigGlyphMetrics record shared by all
    /// images. CBDT image format 19 has no inline metrics and consumes it.
    shared_metrics: ?bitmap.Metrics = null,
};

pub const SelectedGlyph = struct {
    strike: Strike,
    location: GlyphLocation,
};
