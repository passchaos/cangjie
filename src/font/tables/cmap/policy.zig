//! cmap platform policy, public scalar contracts, and selection metadata.

const bin = @import("../../../binary.zig");
const types = @import("types.zig");

pub const ParseError = error{ BadSfnt, EndOfStream };
pub const PublicError = error{InvalidCodepoint};

pub fn validateEncodingCompatibility(
    platform_id: u16,
    encoding_id: u16,
    format: u16,
) ParseError!void {
    const valid = switch (platform_id) {
        0 => switch (encoding_id) {
            // Deprecated Unicode encodings are still Unicode character maps, but
            // their historical fonts predate the modern BMP/full-repertoire
            // split. Keep accepting numeric mapping formats while still keeping
            // the format-13/14 special-purpose encodings exclusive below.
            0, 1, 2 => isGeneralCharacterCmapFormat(format),
            3 => isUnicodeBmpCmapFormat(format),
            4 => isUnicodeFullRepertoireCmapFormat(format),
            5 => format == 14,
            6 => format == 13,
            // Unknown Unicode encoding IDs occur in otherwise valid, subsetted
            // fonts. Treat ordinary mapping formats as Unicode scalar maps and
            // keep validating their structure, but do not let an unrecognized
            // optional EncodingRecord invalidate standard sibling records.
            // Formats 13/14 remain restricted to their registered encodings.
            else => isGeneralCharacterCmapFormat(format),
        },
        1 => isLegacyByteOrBmpCmapFormat(format),
        2 => encoding_id <= 2 and isGeneralCharacterCmapFormat(format),
        3 => switch (encoding_id) {
            0, 1 => format == 4,
            // Windows CJK code-page cmaps are not Unicode scalar maps; both the
            // mixed-byte format 2 and segmented format 4 encodings are seen in
            // legacy fonts.
            2, 3, 4, 5, 6 => format == 2 or format == 4,
            10 => format == 12 or format == 13,
            else => false,
        },
        // Custom and user-defined platforms can use the ordinary character-code
        // mapping formats, but format 13 and 14 have Unicode-platform-only
        // contracts: last-resort scalar ranges and variation sequences.
        4, 240...255 => isCustomPlatformCmapFormat(format),
        else => false,
    };
    if (!valid) return error.BadSfnt;
}

fn isLegacyByteOrBmpCmapFormat(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6 => true,
        else => false,
    };
}

fn isGeneralCharacterCmapFormat(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6, 8, 10, 12 => true,
        else => false,
    };
}

fn isUnicodeBmpCmapFormat(format: u16) bool {
    return format == 4 or format == 6;
}

fn isUnicodeFullRepertoireCmapFormat(format: u16) bool {
    return format == 8 or format == 10 or format == 12;
}

fn isCustomPlatformCmapFormat(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6, 8, 10, 12 => true,
        else => false,
    };
}

pub fn usesUnicodeScalars(platform_id: u16, encoding_id: u16) bool {
    return switch (platform_id) {
        // The Unicode platform and the Windows Unicode BMP/full-repertoire
        // encodings describe Unicode scalar values. Legacy symbol/code-page
        // cmaps can use the same binary formats for non-Unicode character
        // codes, so surrogate filtering below is only applied to true Unicode
        // encoding records.
        0 => true,
        3 => encoding_id == 1 or encoding_id == 10,
        else => false,
    };
}

pub fn validateLanguageField(
    data: []const u8,
    offset: usize,
    length: usize,
    format: u16,
    platform_id: u16,
) ParseError!void {
    // The legacy language field is only meaningful for Macintosh cmap
    // subtables. Unicode, Windows, ISO, and custom cmap records must keep it
    // zero; otherwise the same mapping bytes can be interpreted as a
    // platform-private language variant by one parser and as an ordinary
    // Unicode mapping by another.
    if (platform_id == 1) return;
    switch (format) {
        0, 2, 4, 6 => {
            if (length < 6) return error.BadSfnt;
            if (try bin.readU16At(data, offset + 4) != 0) return error.BadSfnt;
        },
        8, 10, 12, 13 => {
            if (length < 12) return error.BadSfnt;
            if (try bin.readU32At(data, offset + 8) != 0) return error.BadSfnt;
        },
        else => {},
    }
}

pub fn isUnicodeScalar(value: u32) bool {
    return value <= 0x10ffff and !isUnicodeSurrogate(value);
}

pub fn isUnicodeSurrogate(value: u32) bool {
    return value >= 0xd800 and value <= 0xdfff;
}

pub fn isVariationSelector(value: u32) bool {
    return (value >= 0xfe00 and value <= 0xfe0f) or (value >= 0xe0100 and value <= 0xe01ef);
}

pub fn validatePublicScalar(codepoint: u21) PublicError!void {
    // Public cmap APIs accept Unicode scalar values, not arbitrary 21-bit
    // integers. Validate the boundary before scanning font tables so surrogate
    // code points cannot be reported as ordinary unmapped text or fed into a
    // default-UVS fallback lookup.
    if (!isUnicodeScalar(codepoint)) return error.InvalidCodepoint;
}

pub fn validatePublicVariationSelector(codepoint: u21) PublicError!void {
    // Format-14 cmap records are keyed only by standardized Unicode variation
    // selectors. Treating an arbitrary scalar as "no UVS record" masks caller
    // bugs and can accidentally fall back through glyphIndexWithVariation as if
    // a malformed text stream were valid base text.
    if (!isVariationSelector(codepoint)) return error.InvalidCodepoint;
}

pub fn supportsGlyphLookup(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6, 8, 10, 12, 13 => true,
        else => false,
    };
}

pub fn language(
    data: []const u8,
    offset: usize,
    length: usize,
    format: u16,
) ParseError!?u32 {
    return switch (format) {
        0, 2, 4, 6 => blk: {
            if (length < 6) return error.BadSfnt;
            break :blk @as(u32, try bin.readU16At(data, offset + 4));
        },
        8, 10, 12, 13 => blk: {
            if (length < 12) return error.BadSfnt;
            break :blk try bin.readU32At(data, offset + 8);
        },
        else => null,
    };
}

pub fn isMacintoshRoman(subtable: types.Subtable) bool {
    return subtable.platform_id == 1 and subtable.encoding_id == 0;
}

pub fn score(subtable: types.Subtable) u8 {
    if (subtable.format == 12 and subtable.platform_id == 3 and subtable.encoding_id == 10) return 8;
    if (subtable.format == 12 and subtable.platform_id == 0) return 7;
    if (subtable.format == 8 and subtable.platform_id == 0 and subtable.encoding_id == 4) return 6;
    if (subtable.format == 4 and subtable.platform_id == 3 and subtable.encoding_id == 1) return 5;
    if (subtable.format == 4 and subtable.platform_id == 0) return 4;
    if (subtable.format == 13 and ((subtable.platform_id == 0 and subtable.encoding_id == 6) or (subtable.platform_id == 3 and subtable.encoding_id == 10))) return 2;
    if (subtable.format == 10 and subtable.platform_id == 0 and subtable.encoding_id == 4) return 2;
    if (subtable.format == 2 and (subtable.platform_id == 0 or subtable.platform_id == 3)) return 1;
    if (subtable.format == 6 and (subtable.platform_id == 0 or subtable.platform_id == 3)) return 1;
    if (subtable.format == 0) return 1;
    return 0;
}

pub fn readU24(data: []const u8, offset: usize) ParseError!u32 {
    if (offset > data.len or data.len - offset < 3) return error.BadSfnt;
    return (@as(u32, data[offset]) << 16) |
        (@as(u32, data[offset + 1]) << 8) |
        data[offset + 2];
}
