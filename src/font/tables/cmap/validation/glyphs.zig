//! Cross-table validation of cmap mappings against maxp.numGlyphs.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const formats = @import("formats.zig");

pub const Error = error{ BadSfnt, EndOfStream };

pub fn validate(data: []const u8, offset: usize, length: usize, format: u16, glyph_count: u16) Error!void {
    switch (format) {
        0 => {
            try formats.validateFormat0(length);
            for (data[offset + 6 .. offset + 262]) |glyph_id| {
                try validateCmapGlyphId(glyph_id, glyph_count);
            }
        },
        2 => try validateCmapFormat2GlyphIds(data, offset, length, glyph_count),
        4 => try validateCmapFormat4GlyphIds(data, offset, length, glyph_count),
        6 => {
            const entry_count = try bin.readU16At(data, offset + 8);
            for (0..entry_count) |index| {
                try validateCmapGlyphId(try bin.readU16At(data, offset + 10 + index * 2), glyph_count);
            }
        },
        8 => try validateCmapFormat8GlyphIds(data, offset, length, glyph_count),
        10 => {
            const entry_count: usize = @intCast(try bin.readU32At(data, offset + 16));
            for (0..entry_count) |index| {
                try validateCmapGlyphId(try bin.readU16At(data, offset + 20 + index * 2), glyph_count);
            }
        },
        12 => try validateCmapFormat12GlyphIds(data, offset, length, glyph_count),
        13 => try validateCmapFormat13GlyphIds(data, offset, length, glyph_count),
        14 => try validateCmapFormat14GlyphIds(data, offset, length, glyph_count),
        else => {},
    }
}

fn validateCmapGlyphId(glyph_id: u32, glyph_count: u16) Error!void {
    // cmap data is a cross-table contract: every non-missing mapping names a
    // glyph in the maxp glyph set. Validate the declared mapping space while
    // parsing so later text shaping cannot manufacture out-of-range glyph ids
    // that fail only when metrics or outlines are requested.
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

fn addU16Wrapping(value: u16, delta: i16) u16 {
    return @as(u16, @bitCast(@as(i16, @bitCast(value)) +% delta));
}

fn validateCmapFormat2GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) Error!void {
    const table_end = offset + length;
    var max_subheader_index: u16 = 0;
    for (0..256) |high_byte| {
        const key = try bin.readU16At(data, offset + 6 + high_byte * 2);
        max_subheader_index = @max(max_subheader_index, key / 8);
    }

    const subheaders_offset = offset + 6 + 512;
    for (0..@as(usize, max_subheader_index) + 1) |subheader_index| {
        const subheader_offset = subheaders_offset + subheader_index * 8;
        const entry_count = try bin.readU16At(data, subheader_offset + 2);
        const id_delta = try bin.readI16At(data, subheader_offset + 4);
        const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
        for (0..entry_count) |entry_index| {
            const glyph_offset = subheader_offset + 6 + @as(usize, id_range_offset) + entry_index * 2;
            if (glyph_offset + 2 > table_end) return error.BadSfnt;
            const raw_glyph = try bin.readU16At(data, glyph_offset);
            if (raw_glyph == 0) continue;
            try validateCmapGlyphId(addU16Wrapping(raw_glyph, id_delta), glyph_count);
        }
    }
}

fn validateCmapFormat4GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) Error!void {
    const table_end = offset + length;
    const seg_count = @as(usize, try bin.readU16At(data, offset + 6) / 2);
    const end_codes = offset + 14;
    const start_codes = end_codes + seg_count * 2 + 2;
    const id_deltas = start_codes + seg_count * 2;
    const id_range_offsets = id_deltas + seg_count * 2;

    for (0..seg_count) |segment_index| {
        const start = try bin.readU16At(data, start_codes + segment_index * 2);
        const end = try bin.readU16At(data, end_codes + segment_index * 2);
        const delta = try bin.readI16At(data, id_deltas + segment_index * 2);
        const range_offset = try bin.readU16At(data, id_range_offsets + segment_index * 2);
        var codepoint = start;
        while (true) : (codepoint +%= 1) {
            const glyph_id = if (range_offset == 0) blk: {
                break :blk addU16Wrapping(codepoint, delta);
            } else blk: {
                const glyph_offset = id_range_offsets + segment_index * 2 + @as(usize, range_offset) + (@as(usize, codepoint - start) * 2);
                if (glyph_offset + 2 > table_end) return error.BadSfnt;
                const raw_glyph = try bin.readU16At(data, glyph_offset);
                if (raw_glyph == 0) {
                    if (codepoint == end) break;
                    continue;
                }
                break :blk addU16Wrapping(raw_glyph, delta);
            };
            try validateCmapGlyphId(glyph_id, glyph_count);
            if (codepoint == end) break;
        }
    }
}

fn validateCmapFormat8GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) Error!void {
    const group_count: usize = @intCast(try bin.readU32At(data, offset + formats.format8_groups_offset - 4));
    _ = length;
    for (0..group_count) |index| {
        const group_offset = offset + formats.format8_groups_offset + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        const first_glyph = try bin.readU32At(data, group_offset + 8);
        const span = end - start;
        if (first_glyph > std.math.maxInt(u32) - span) return error.BadSfnt;
        try validateCmapGlyphId(first_glyph + span, glyph_count);
    }
}

fn validateCmapFormat12GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) Error!void {
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    _ = length;
    for (0..group_count) |index| {
        const group_offset = offset + 16 + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        const first_glyph = try bin.readU32At(data, group_offset + 8);
        const span = end - start;
        if (first_glyph > std.math.maxInt(u32) - span) return error.BadSfnt;
        try validateCmapGlyphId(first_glyph + span, glyph_count);
    }
}

fn validateCmapFormat13GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) Error!void {
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    _ = length;
    for (0..group_count) |index| {
        const glyph_id = try bin.readU32At(data, offset + 16 + index * 12 + 8);
        try validateCmapGlyphId(glyph_id, glyph_count);
    }
}

fn validateCmapFormat14GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) Error!void {
    const record_count: usize = @intCast(try bin.readU32At(data, offset + 6));
    const table_end = offset + length;
    for (0..record_count) |record_index| {
        const record = offset + 10 + record_index * 11;
        const non_default_offset = try bin.readU32At(data, record + 7);
        if (non_default_offset == 0) continue;
        const mappings_offset = offset + @as(usize, non_default_offset);
        const mapping_count: usize = @intCast(try bin.readU32At(data, mappings_offset));
        if (mapping_count > (table_end - (mappings_offset + 4)) / 5) return error.BadSfnt;
        for (0..mapping_count) |mapping_index| {
            try validateCmapGlyphId(try bin.readU16At(data, mappings_offset + 4 + mapping_index * 5 + 3), glyph_count);
        }
    }
}
