//! Scalar-to-glyph lookup for cmap formats 0, 2, 4, 6, 8, 10, 12, and 13.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const formats = @import("../validation/formats.zig");

pub const GlyphId = u16;
pub const Error = error{ BadSfnt, EndOfStream, UnsupportedCmap };

pub fn glyph(
    data: []const u8,
    subtable: @import("../types.zig").Subtable,
    codepoint: u21,
) Error!GlyphId {
    if (subtable.offset > data.len or
        subtable.length > data.len - subtable.offset or
        subtable.length < 2)
    {
        return error.BadSfnt;
    }
    if (try bin.readU16At(data, subtable.offset) != subtable.format) {
        return error.BadSfnt;
    }
    return switch (subtable.format) {
        0 => format0(data, subtable.offset, codepoint),
        2 => format2(data, subtable.offset, subtable.length, codepoint),
        4 => format4(data, subtable.offset, codepoint),
        6 => format6(data, subtable.offset, codepoint),
        8 => format8(data, subtable.offset, subtable.length, codepoint),
        10 => format10(data, subtable.offset, subtable.length, codepoint),
        12 => format12(data, subtable.offset, subtable.length, codepoint),
        13 => format13(data, subtable.offset, subtable.length, codepoint),
        else => error.UnsupportedCmap,
    };
}

fn format0(data: []const u8, offset: usize, codepoint: u21) Error!GlyphId {
    if (codepoint > 0xff) return 0;
    const length = try bin.readU16At(data, offset + 2);
    try formats.validateFormat0(length);
    return data[offset + 6 + @as(usize, codepoint)];
}

fn format2(data: []const u8, offset: usize, length: usize, codepoint: u21) Error!GlyphId {
    if (codepoint > 0xffff) return 0;
    // Public glyphIndex has already rejected surrogate Unicode scalars. The
    // lazy structural recheck here intentionally keeps the scalar-domain flag
    // off because the platform/encoding record is validated by
    // validateCmapLookupSubtable before this format-specific lookup runs.
    try formats.validate(data, offset, length, 2, false);

    const high_byte: u8 = @intCast((codepoint >> 8) & 0xff);
    const low_byte: u8 = @intCast(codepoint & 0xff);
    const key = try bin.readU16At(data, offset + 6 + @as(usize, high_byte) * 2);
    const subheader_index = key / 8;
    const subheader_offset = offset + 6 + 512 + @as(usize, subheader_index) * 8;

    // The first subheader also maps one-byte character codes. For non-zero
    // high bytes, only a referenced subheader is valid; an absent high-byte
    // key means the two-byte character is unmapped rather than falling through
    // the single-byte table.
    if (high_byte != 0 and subheader_index == 0) return 0;

    const first_code = try bin.readU16At(data, subheader_offset);
    const entry_count = try bin.readU16At(data, subheader_offset + 2);
    const id_delta = try bin.readI16At(data, subheader_offset + 4);
    const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
    const char_code = @as(u16, low_byte);
    if (char_code < first_code) return 0;
    const entry_index = @as(usize, char_code - first_code);
    if (entry_index >= entry_count) return 0;

    const glyph_offset = subheader_offset + 6 + @as(usize, id_range_offset) + entry_index * 2;
    const glyph_id = try bin.readU16At(data, glyph_offset);
    if (glyph_id == 0) return 0;
    return @intCast(
        @as(u16, @bitCast(@as(i16, @bitCast(glyph_id)) +% id_delta)),
    );
}

fn format4(data: []const u8, offset: usize, codepoint: u21) Error!GlyphId {
    if (codepoint > 0xffff) return 0;
    if (offset > data.len or data.len - offset < 8) return error.BadSfnt;
    const length = try bin.readU16At(data, offset + 2);
    if (length > data.len - offset) return error.BadSfnt;

    const seg_count_x2 = try bin.readU16At(data, offset + 6);
    if (seg_count_x2 == 0 or (seg_count_x2 & 1) != 0) return error.BadSfnt;
    const seg_count = @as(usize, seg_count_x2 / 2);
    const minimum_length = 16 + seg_count * 8;
    if (length < minimum_length) return error.BadSfnt;

    const table_end = offset + @as(usize, length);
    const end_codes = offset + 14;
    const start_codes = end_codes + @as(usize, seg_count) * 2 + 2;
    const id_deltas = start_codes + @as(usize, seg_count) * 2;
    const id_range_offsets = id_deltas + @as(usize, seg_count) * 2;
    const cp: u16 = @intCast(codepoint);
    for (0..seg_count) |i| {
        const end = try bin.readU16At(data, end_codes + i * 2);
        if (cp > end) continue;
        const start = try bin.readU16At(data, start_codes + i * 2);
        if (cp < start) return 0;
        const delta = try bin.readI16At(data, id_deltas + i * 2);
        const range_offset = try bin.readU16At(data, id_range_offsets + i * 2);
        if (range_offset == 0) {
            return @intCast(@as(u16, @bitCast(@as(i16, @bitCast(cp)) +% delta)));
        }
        const glyph_offset = id_range_offsets + i * 2 + range_offset + (@as(usize, cp - start) * 2);
        // idRangeOffset addresses are relative to the idRangeOffset word, but
        // the resolved glyph id still belongs to this format-4 subtable. Do
        // not let malformed cmaps read arbitrary bytes from the containing SFNT
        // when the subtable's declared length ends before the glyph array.
        if (glyph_offset + 2 > table_end) return error.BadSfnt;
        const glyph_id = try bin.readU16At(data, glyph_offset);
        if (glyph_id == 0) return 0;
        return @intCast(
            @as(u16, @bitCast(@as(i16, @bitCast(glyph_id)) +% delta)),
        );
    }
    return 0;
}

fn format6(data: []const u8, offset: usize, codepoint: u21) Error!GlyphId {
    if (codepoint > 0xffff) return 0;
    const length = try bin.readU16At(data, offset + 2);
    try formats.validate(data, offset, length, 6, false);
    const first_code = try bin.readU16At(data, offset + 6);
    const entry_count = try bin.readU16At(data, offset + 8);
    const cp: u16 = @intCast(codepoint);
    if (cp < first_code) return 0;
    const index = @as(usize, cp - first_code);
    if (index >= entry_count) return 0;
    return try bin.readU16At(data, offset + 10 + index * 2);
}

fn format8(data: []const u8, offset: usize, length: usize, codepoint: u21) Error!GlyphId {
    try formats.validate(data, offset, length, 8, true);
    return try sequentialMapGroups(
        data,
        offset,
        formats.format8_groups_offset,
        length,
        codepoint,
    );
}

fn format10(data: []const u8, offset: usize, length: usize, codepoint: u21) Error!GlyphId {
    try formats.validate(data, offset, length, 10, true);
    const start_code = try bin.readU32At(data, offset + 12);
    const num_chars = try bin.readU32At(data, offset + 16);
    if (codepoint < start_code) return 0;
    const index = @as(usize, codepoint - start_code);
    if (index >= num_chars) return 0;
    return try bin.readU16At(data, offset + 20 + index * 2);
}

fn format12(data: []const u8, offset: usize, length: usize, codepoint: u21) Error!GlyphId {
    return try sequentialMapGroups(data, offset, 16, length, codepoint);
}

fn format13(data: []const u8, offset: usize, length: usize, codepoint: u21) Error!GlyphId {
    // Format 13 shares the segmented 32-bit group layout with format 12, but
    // each group maps every scalar in the range to the same glyph id. This is
    // how last-resort fonts cover huge Unicode ranges without carrying per-code
    // point glyph indices.
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    const groups = try bin.readU32At(data, offset + 12);
    if (@as(u64, groups) * 12 != @as(u64, length - 16)) return error.BadSfnt;

    var lo: usize = 0;
    var hi: usize = @intCast(groups);
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const group_offset = offset + 16 + mid * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (codepoint < start) {
            hi = mid;
        } else if (codepoint > end) {
            lo = mid + 1;
        } else {
            const glyph_id = try bin.readU32At(data, group_offset + 8);
            if (glyph_id > std.math.maxInt(GlyphId)) return error.BadSfnt;
            return @intCast(glyph_id);
        }
    }
    return 0;
}

fn sequentialMapGroups(data: []const u8, offset: usize, groups_offset: usize, length: usize, codepoint: u21) Error!GlyphId {
    // SequentialMapGroup records are sorted by startCharCode. Binary search
    // avoids a linear scan through very large CJK fonts with thousands of
    // ranges and is shared by format 8 and format 12.
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (groups_offset < 4 or groups_offset > length) return error.BadSfnt;
    const groups = try bin.readU32At(data, offset + groups_offset - 4);
    if (@as(u64, groups) * 12 != @as(u64, length - groups_offset)) return error.BadSfnt;

    var lo: usize = 0;
    var hi: usize = @intCast(groups);
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const group_offset = offset + groups_offset + mid * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (codepoint < start) {
            hi = mid;
        } else if (codepoint > end) {
            lo = mid + 1;
        } else {
            const first = try bin.readU32At(data, group_offset + 8);
            const delta = @as(u32, codepoint) - start;
            if (first > std.math.maxInt(u32) - delta) return error.BadSfnt;
            const glyph_id = first + delta;
            if (glyph_id > std.math.maxInt(GlyphId)) return error.BadSfnt;
            return @intCast(glyph_id);
        }
    }
    return 0;
}
