//! cmap format dispatch and platform/encoding policy validation.

const policy = @import("../policy.zig");
const formats = @import("formats.zig");
pub const format14 = @import("format14.zig");

pub const Error = policy.ParseError;

pub fn validate(
    data: []const u8,
    offset: usize,
    length: usize,
    format: u16,
    platform_id: u16,
    encoding_id: u16,
) Error!void {
    try policy.validateEncodingCompatibility(platform_id, encoding_id, format);
    const unicode_scalars = policy.usesUnicodeScalars(platform_id, encoding_id);
    if (format == 14) {
        try format14.validate(data, offset, length);
    } else {
        try formats.validate(data, offset, length, format, unicode_scalars);
    }
    try policy.validateLanguageField(data, offset, length, format, platform_id);
}
