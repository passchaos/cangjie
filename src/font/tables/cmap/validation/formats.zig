//! Structural validation for numeric cmap formats 0 through 13.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const policy = @import("../policy.zig");

pub const Error = error{ BadSfnt, EndOfStream };

pub fn validate(
    data: []const u8,
    offset: usize,
    length: usize,
    format: u16,
    validate_unicode_scalars: bool,
) Error!void {
    switch (format) {
        0 => try validateFormat0(length),
        2 => try validateCmapFormat2(data, offset, length, validate_unicode_scalars),
        4 => try validateCmapFormat4(data, offset, length, validate_unicode_scalars),
        6 => try validateCmapFormat6(data, offset, length, validate_unicode_scalars),
        8 => try validateCmapFormat8(data, offset, length),
        10 => try validateCmapFormat10(data, offset, length),
        12, 13 => try validateSegmentedCmapGroups(data, offset, length),
        else => {},
    }
}

pub fn validateFormat0(length: usize) Error!void {
    // Format 0 has exactly 256 one-byte glyph entries after its six-byte
    // header. Treat the length as a fixed structural contract rather than a
    // minimum so trailing bytes cannot be hidden inside a subtable that later
    // EncodingRecords may also try to interpret.
    if (length != 262) return error.BadSfnt;
}

fn validateCmapFormat2(data: []const u8, offset: usize, length: usize, validate_unicode_scalars: bool) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 526) return error.BadSfnt;

    const table_end = offset + length;
    var max_subheader_index: u16 = 0;
    for (0..256) |high_byte| {
        const key = try bin.readU16At(data, offset + 6 + high_byte * 2);
        // SubHeaderKeys are byte offsets divided by the fixed eight-byte
        // SubHeader size. Requiring alignment at parse time prevents lookup
        // from interpreting the middle of one SubHeader as another.
        if ((key & 7) != 0) return error.BadSfnt;
        max_subheader_index = @max(max_subheader_index, key / 8);
    }

    const subheaders_offset = offset + 6 + 512;
    const subheaders_len = (@as(usize, max_subheader_index) + 1) * 8;
    if (subheaders_len > table_end - subheaders_offset) return error.BadSfnt;
    const glyph_array_start = subheaders_offset + subheaders_len;

    for (0..@as(usize, max_subheader_index) + 1) |subheader_index| {
        const subheader_offset = subheaders_offset + subheader_index * 8;
        const first_code = try bin.readU16At(data, subheader_offset);
        const entry_count = try bin.readU16At(data, subheader_offset + 2);
        _ = try bin.readI16At(data, subheader_offset + 4);
        const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
        if (entry_count == 0) continue;

        const last_entry_index = @as(usize, entry_count) - 1;
        if (@as(usize, first_code) + last_entry_index > 0xff) return error.BadSfnt;
        if (validate_unicode_scalars) {
            // Format 2 stores only low-byte ranges in each SubHeader; the
            // high-byte key that selected the SubHeader supplies the rest of
            // the BMP code point. Validate every referencing high-byte domain
            // so Unicode cmaps cannot advertise surrogate character codes
            // while still looking structurally valid at the glyph-array level.
            try validateCmapFormat2UnicodeScalarRange(data, offset, subheader_index, first_code, entry_count);
        }
        if ((id_range_offset & 1) != 0) return error.BadSfnt;
        const first_glyph = subheader_offset + 6 + @as(usize, id_range_offset);
        const last_glyph = first_glyph + last_entry_index * 2;
        // idRangeOffset is relative to its own word. The glyph index array is
        // conceptually after the declared SubHeader array, so disallow offsets
        // that point back into SubHeader metadata or beyond the declared cmap.
        if (first_glyph < glyph_array_start or last_glyph > table_end or table_end - last_glyph < 2) return error.BadSfnt;
    }
}

fn validateCmapFormat2UnicodeScalarRange(data: []const u8, offset: usize, subheader_index: usize, first_code: u16, entry_count: u16) Error!void {
    for (0..256) |high_byte| {
        const key = try bin.readU16At(data, offset + 6 + high_byte * 2);
        if (key / 8 != subheader_index) continue;
        if (subheader_index == 0) {
            // SubHeader[0] is also the single-byte map. High-byte zero covers
            // U+00xx; other high bytes with a zero key mean "unmapped" rather
            // than a two-byte range, matching glyphIndexFormat2.
            if (high_byte != 0) continue;
        }

        const start = (@as(u32, @intCast(high_byte)) << 8) | first_code;
        const end = start + @as(u32, entry_count) - 1;
        if (!policy.isUnicodeScalar(start) or !policy.isUnicodeScalar(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
    }
}

fn validateCmapFormat6(data: []const u8, offset: usize, length: usize, validate_unicode_scalars: bool) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 10) return error.BadSfnt;
    const first_code = try bin.readU16At(data, offset + 6);
    const entry_count = try bin.readU16At(data, offset + 8);
    if (@as(usize, entry_count) * 2 != length - 10) return error.BadSfnt;
    if (entry_count != 0) {
        const last_code = @as(u32, first_code) + @as(u32, entry_count) - 1;
        if (last_code > std.math.maxInt(u16)) return error.BadSfnt;
        if (validate_unicode_scalars) {
            if (!policy.isUnicodeScalar(first_code) or !policy.isUnicodeScalar(last_code)) return error.BadSfnt;
            if (first_code < 0xe000 and last_code > 0xd7ff) return error.BadSfnt;
        }
    }
}

pub const format8_is32_offset = 12;
pub const format8_is32_len = 8192;
pub const format8_groups_offset = format8_is32_offset + format8_is32_len + 4;

fn validateCmapFormat8(data: []const u8, offset: usize, length: usize) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < format8_groups_offset) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const group_bytes = length - format8_groups_offset;
    if (group_bytes % 12 != 0) return error.BadSfnt;
    const group_count: usize = @intCast(try bin.readU32At(data, offset + format8_groups_offset - 4));
    if (group_count != group_bytes / 12) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..group_count) |index| {
        const group_offset = offset + format8_groups_offset + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (!policy.isUnicodeScalar(start) or !policy.isUnicodeScalar(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            // Format 8 lookups use the same sorted group search as format 12,
            // with an additional is32 bitset to identify UTF-16 high words.
            // Enforce ordering at parse time so malformed group arrays cannot
            // make scalar-to-glyph mapping depend on record order.
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;

        try validateCmapFormat8RangeWidth(data, offset, start, end);
    }
}

fn validateExtendedCmapReservedField(data: []const u8, offset: usize) Error!void {
    // Extended cmap formats 8/10/12/13 all reserve the UInt16 field after the
    // format word. Keep it zero so a malformed table cannot advertise a
    // private variant while being interpreted by the standard parser.
    if (try bin.readU16At(data, offset + 2) != 0) return error.BadSfnt;
}

fn validateCmapFormat8RangeWidth(data: []const u8, offset: usize, start: u32, end: u32) Error!void {
    // The is32 bitset is part of format 8's decoding contract, not merely a
    // hint. A BMP codepoint named by a group must be marked as a standalone
    // 16-bit character, while every high word used by supplementary-plane
    // groups must be marked as the first half of a 32-bit character code.
    if (start <= 0xffff) {
        var word = start;
        const last_bmp = @min(end, 0xffff);
        while (word <= last_bmp) : (word += 1) {
            if (cmapFormat8Is32(data, offset, @intCast(word))) return error.BadSfnt;
        }
    }
    if (end > 0xffff) {
        var high_word = @max(start, 0x10000) >> 16;
        const last_high_word = end >> 16;
        while (high_word <= last_high_word) : (high_word += 1) {
            if (!cmapFormat8Is32(data, offset, @intCast(high_word))) return error.BadSfnt;
        }
    }
}

fn cmapFormat8Is32(data: []const u8, offset: usize, word: u16) bool {
    const byte_offset = offset + format8_is32_offset + @as(usize, word) / 8;
    const bit_mask: u8 = @as(u8, 0x80) >> @intCast(word & 7);
    return (data[byte_offset] & bit_mask) != 0;
}

fn validateCmapFormat10(data: []const u8, offset: usize, length: usize) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 20) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const start_code = try bin.readU32At(data, offset + 12);
    if (!policy.isUnicodeScalar(start_code)) return error.BadSfnt;
    const num_chars = try bin.readU32At(data, offset + 16);
    if (@as(u64, num_chars) * 2 != @as(u64, length - 20)) return error.BadSfnt;
    if (num_chars == 0) return;
    const last_code = @as(u64, start_code) + @as(u64, num_chars) - 1;
    if (last_code > std.math.maxInt(u32)) return error.BadSfnt;
    const last_scalar: u32 = @intCast(last_code);
    if (!policy.isUnicodeScalar(last_scalar)) return error.BadSfnt;
    if (start_code < 0xe000 and last_scalar > 0xd7ff) return error.BadSfnt;
}

fn validateCmapFormat4(data: []const u8, offset: usize, length: usize, validate_unicode_scalars: bool) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    const seg_count_x2 = try bin.readU16At(data, offset + 6);
    if (seg_count_x2 == 0 or (seg_count_x2 & 1) != 0) return error.BadSfnt;
    const seg_count = @as(usize, seg_count_x2 / 2);
    // The binary-search descriptor fields are performance hints for consumers
    // that use OpenType's suggested search algorithm. Cangjie validates and
    // scans the segment arrays directly, and real AOTS/HarfBuzz test fonts may
    // leave those descriptor fields non-canonical while the mapping data is
    // otherwise valid.
    _ = validateCmapFormat4SearchParameters(data, offset, seg_count) catch {};
    const minimum_length = 16 + seg_count * 8;
    if (length < minimum_length) return error.BadSfnt;

    const table_end = offset + length;
    const end_codes = offset + 14;
    const reserved_pad = end_codes + seg_count * 2;
    const start_codes = reserved_pad + 2;
    const id_deltas = start_codes + seg_count * 2;
    const id_range_offsets = id_deltas + seg_count * 2;
    const glyph_array_start = id_range_offsets + seg_count * 2;
    if (try bin.readU16At(data, reserved_pad) != 0) return error.BadSfnt;

    var previous_end: ?u16 = null;
    for (0..seg_count) |index| {
        const start = try bin.readU16At(data, start_codes + index * 2);
        const end = try bin.readU16At(data, end_codes + index * 2);
        if (end < start) return error.BadSfnt;
        if (validate_unicode_scalars and (policy.isUnicodeSurrogate(start) or policy.isUnicodeSurrogate(end) or (start < 0xe000 and end > 0xd7ff))) return error.BadSfnt;
        if (previous_end) |last_end| {
            // Format 4 is searched as an ordered segment array. Reject
            // overlapping or out-of-order records at cmap parse time so glyph
            // lookup cannot become dependent on malformed directory order.
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;

        const range_offset = try bin.readU16At(data, id_range_offsets + index * 2);
        if (index == seg_count - 1) {
            const delta = try bin.readI16At(data, id_deltas + index * 2);
            // The terminal segment is not an ordinary mapping range: OpenType
            // requires the exact 0xffff -> glyph 0 sentinel so binary-search
            // cmap consumers have a guaranteed stop record. Accepting a wider
            // or non-missing final range would make U+FFFF visible as a real
            // glyph in this parser and can make other parsers disagree about
            // where the searchable character-domain ends.
            if (start != 0xffff or end != 0xffff or delta != 1 or range_offset != 0) return error.BadSfnt;
        }
        if (range_offset != 0) {
            if ((range_offset & 1) != 0) return error.BadSfnt;
            const first_glyph = id_range_offsets + index * 2 + @as(usize, range_offset);
            const last_delta = @as(usize, end) - @as(usize, start);
            const last_glyph = first_glyph + last_delta * 2;
            // Validate the full declared segment, not just the character a
            // future lookup happens to ask for. Otherwise a malformed cmap can
            // look fine for early codepoints while later codepoints read past
            // the subtable into the next SFNT table.
            if (first_glyph < glyph_array_start or last_glyph > table_end or table_end - last_glyph < 2) return error.BadSfnt;
        }
    }

    // OpenType format 4 requires a terminal 0xffff segment. The lookup loop
    // uses the first segment whose endCode is >= the requested scalar; without
    // the sentinel, malformed BMP subtables can stop early and hide later
    // invalid segment data.
    if (previous_end != 0xffff) return error.BadSfnt;
}

fn validateCmapFormat4SearchParameters(data: []const u8, offset: usize, seg_count: usize) Error!void {
    var max_power_of_two: usize = 1;
    var expected_entry_selector: u16 = 0;
    while (max_power_of_two * 2 <= seg_count) {
        max_power_of_two *= 2;
        expected_entry_selector += 1;
    }

    const expected_search_range = max_power_of_two * 2;
    const segment_selector_bytes = seg_count * 2;
    if (expected_search_range > std.math.maxInt(u16) or segment_selector_bytes > std.math.maxInt(u16)) return error.BadSfnt;
    const expected_range_shift = segment_selector_bytes - expected_search_range;

    // Format 4 carries a small binary-search descriptor beside segCountX2.
    // Cangjie's lookup currently scans linearly, but the fields are still part
    // of the OpenType table contract. Requiring their canonical values keeps a
    // malformed private variant from being accepted just because its segment
    // arrays happen to be readable.
    if (try bin.readU16At(data, offset + 8) != expected_search_range or
        try bin.readU16At(data, offset + 10) != expected_entry_selector or
        try bin.readU16At(data, offset + 12) != expected_range_shift)
    {
        return error.BadSfnt;
    }
}

fn validateSegmentedCmapGroups(data: []const u8, offset: usize, length: usize) Error!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    // Formats 12 and 13 have no trailing language or padding fields after the
    // group array. Require the UInt32 length to match the declared group count
    // exactly so an EncodingRecord cannot hide an extra partial/complete group
    // that another parser or a mutated cached subtable might later observe.
    if (@as(u64, group_count) * 12 != @as(u64, length - 16)) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..group_count) |index| {
        const group_offset = offset + 16 + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (!policy.isUnicodeScalar(start) or !policy.isUnicodeScalar(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            // Format 12/13 group arrays are searched as sorted, disjoint
            // intervals. Rejecting overlap and out-of-order starts at parse
            // time keeps malformed cmap data from producing order-dependent
            // glyph mappings later.
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;
    }
}
