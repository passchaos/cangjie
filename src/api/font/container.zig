//! Modern web-font and collection container decoding.

const impl = @import("../../font_container.zig");

pub const Error = impl.Error;
pub const Format = impl.Format;
pub const OwnedFace = impl.OwnedFace;
pub const default_max_decoded_size = impl.default_max_decoded_size;

pub const decodeAlloc = impl.decodeFontContainerAlloc;
pub const detectFormat = impl.detectFormat;
