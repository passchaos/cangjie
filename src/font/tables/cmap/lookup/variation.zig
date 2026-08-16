//! Pure cmap format-14 variation-sequence lookup.

const bin = @import("../../../../binary.zig");
const policy = @import("../policy.zig");
const format14 = @import("../validation/format14.zig");
const glyphs = @import("../validation/glyphs.zig");

pub const GlyphId = u16;
pub const Error = error{ BadSfnt, EndOfStream };

/// A format-14 lookup cannot resolve a Default UVS without the base cmap.
///
/// Returning this explicit result keeps the table module independent from
/// `Font`; the facade performs its normal selected-cmap lookup only for
/// `use_default`.
pub const Result = union(enum) {
    none,
    explicit_glyph: GlyphId,
    use_default,
};

pub fn lookup(
    data: []const u8,
    offset: usize,
    length: usize,
    codepoint: u21,
    variation_selector: u21,
    glyph_count: u16,
) Error!Result {
    if (variation_selector > 0xffffff or codepoint > 0xffffff) return .none;
    if (offset > data.len or length > data.len - offset) {
        return error.BadSfnt;
    }

    try format14.validate(data, offset, length);
    try glyphs.validate(data, offset, length, 14, glyph_count);

    const table_end = offset + length;
    const record_count: usize =
        @intCast(try bin.readU32At(data, offset + 6));
    const records_end = try format14.recordsEnd(length, record_count);
    const selector: u32 = variation_selector;

    var previous_selector: ?u32 = null;
    for (0..record_count) |index| {
        const record = offset + 10 + index * 11;
        const record_selector = try policy.readU24(data, record);
        if (!policy.isVariationSelector(record_selector)) {
            return error.BadSfnt;
        }
        if (previous_selector) |previous| {
            if (record_selector <= previous) return error.BadSfnt;
        }
        previous_selector = record_selector;
        if (selector < record_selector) return .none;
        if (selector > record_selector) continue;

        const default_offset = try bin.readU32At(data, record + 3);
        const non_default_offset = try bin.readU32At(data, record + 7);
        if (non_default_offset != 0) {
            const child = try format14.payloadOffset(
                non_default_offset,
                records_end,
                length,
            );
            if (try nonDefault(
                data,
                offset + child,
                table_end,
                codepoint,
            )) |glyph_id| {
                return .{ .explicit_glyph = glyph_id };
            }
        }
        if (default_offset != 0) {
            const child = try format14.payloadOffset(
                default_offset,
                records_end,
                length,
            );
            if (try defaultContains(
                data,
                offset + child,
                table_end,
                codepoint,
            )) {
                return .use_default;
            }
        }
        return .none;
    }
    return .none;
}

fn defaultContains(
    data: []const u8,
    offset: usize,
    table_end: usize,
    codepoint: u21,
) Error!bool {
    if (offset > table_end or table_end - offset < 4) return error.BadSfnt;
    const range_count = try bin.readU32At(data, offset);
    if (@as(usize, range_count) * 4 > table_end - (offset + 4)) {
        return error.BadSfnt;
    }
    const cp: u32 = codepoint;
    for (0..range_count) |index| {
        const range = offset + 4 + index * 4;
        const start = try policy.readU24(data, range);
        const end = start + data[range + 3];
        if (cp >= start and cp <= end) return true;
    }
    return false;
}

fn nonDefault(
    data: []const u8,
    offset: usize,
    table_end: usize,
    codepoint: u21,
) Error!?GlyphId {
    if (offset > table_end or table_end - offset < 4) return error.BadSfnt;
    const mapping_count = try bin.readU32At(data, offset);
    if (@as(usize, mapping_count) * 5 > table_end - (offset + 4)) {
        return error.BadSfnt;
    }
    const cp: u32 = codepoint;
    for (0..mapping_count) |index| {
        const mapping = offset + 4 + index * 5;
        const unicode_value = try policy.readU24(data, mapping);
        if (cp < unicode_value) return null;
        if (cp > unicode_value) continue;
        return try bin.readU16At(data, mapping + 3);
    }
    return null;
}
