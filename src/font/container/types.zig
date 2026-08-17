//! Shared font-container contracts.

pub const Error = error{
    InvalidContainer,
    OutputTooLarge,
    UnsupportedContainer,
    Woff2RuntimeUnavailable,
};

pub const Format = enum { sfnt, dfont, woff1, woff2 };

pub const default_max_decoded_size = 64 * 1024 * 1024;

pub fn isSupportedSfntFlavor(flavor: u32) bool {
    return switch (flavor) {
        0x00010000, 0x74727565, 0x4f54544f => true,
        else => false,
    };
}
