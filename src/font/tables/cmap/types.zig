//! Cached OpenType cmap encoding-record metadata.

/// Public description of one validated cmap EncodingRecord.
pub const Info = struct {
    platform_id: u16,
    encoding_id: u16,
    format: u16,
    offset: usize,
    length: usize,
    /// Legacy formats use a 16-bit language field, extended formats use a
    /// 32-bit field, and format 14 has no language value.
    language: ?u32 = null,
};

/// Internal cached record used by Font lookup dispatch.
pub const Subtable = struct {
    platform_id: u16,
    encoding_id: u16,
    offset: usize,
    length: usize,
    format: u16,
};
