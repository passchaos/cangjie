//! CBLC/EBLC IndexSubTableArray and index formats 1 through 5.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const glyph = @import("../../../../glyph.zig");
const types = @import("../types.zig");
const cblc_types = @import("types.zig");

const Strike = cblc_types.Strike;
const GlyphLocation = cblc_types.GlyphLocation;

pub fn glyphLocation(
    data: []const u8,
    selected_strike: Strike,
    glyph_id: glyph.GlyphId,
) types.Error!?GlyphLocation {
    const SelectedIndexSubtable = struct {
        first: glyph.GlyphId,
        last: glyph.GlyphId,
        offset: usize,
    };
    var selected: ?SelectedIndexSubtable = null;
    var previous_last: ?glyph.GlyphId = null;
    for (0..selected_strike.table_count) |table_index| {
        const record = selected_strike.offset + table_index * 8;
        if (record + 8 > data.len or
            record + 8 >
                selected_strike.offset + selected_strike.index_tables_size)
        {
            return error.BadSfnt;
        }
        const first = try bin.readU16At(data, record);
        const last = try bin.readU16At(data, record + 2);
        const subtable_offset = try bin.readU32At(data, record + 4);
        if (first > last or
            first < selected_strike.start_glyph or
            last > selected_strike.end_glyph)
        {
            return error.BadSfnt;
        }
        if (previous_last) |previous| {
            // Array ranges are sorted and non-overlapping. Enforcing the whole
            // directory keeps lookup independent of the requested glyph.
            if (first <= previous) return error.BadSfnt;
        }
        previous_last = last;
        const subtable_data_start =
            @as(usize, selected_strike.table_count) * 8;
        if (subtable_offset < subtable_data_start or
            subtable_offset >= selected_strike.index_tables_size)
        {
            return error.BadSfnt;
        }
        if (glyph_id >= first and glyph_id <= last) {
            selected = .{
                .first = first,
                .last = last,
                .offset = subtable_offset,
            };
        }
    }
    const entry = selected orelse return null;
    const subtable = selected_strike.offset + entry.offset;
    if (subtable + 8 > data.len or
        subtable + 8 >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }
    const index_format = try bin.readU16At(data, subtable);
    const image_format = try bin.readU16At(data, subtable + 2);
    const image_data_offset = try bin.readU32At(data, subtable + 4);
    if (image_data_offset > std.math.maxInt(usize)) return error.BadSfnt;
    const image_base: usize = @intCast(image_data_offset);
    const local_index: usize = glyph_id - entry.first;
    return switch (index_format) {
        1 => try glyphLocationFormat1Or3(
            data,
            selected_strike,
            subtable + 8,
            entry.first,
            entry.last,
            local_index,
            image_format,
            image_base,
            4,
        ),
        2 => try glyphLocationFormat2(
            data,
            selected_strike,
            subtable + 8,
            entry.first,
            entry.last,
            local_index,
            image_format,
            image_base,
        ),
        3 => try glyphLocationFormat1Or3(
            data,
            selected_strike,
            subtable + 8,
            entry.first,
            entry.last,
            local_index,
            image_format,
            image_base,
            2,
        ),
        4 => try glyphLocationFormat4(
            data,
            selected_strike,
            subtable + 8,
            glyph_id,
            image_format,
            image_base,
        ),
        5 => try glyphLocationFormat5(
            data,
            selected_strike,
            subtable + 8,
            entry.first,
            entry.last,
            glyph_id,
            image_format,
            image_base,
        ),
        else => null,
    };
}

pub fn imageLocation(
    image_format: u16,
    image_base: usize,
    start: usize,
    end: usize,
    shared_metrics: ?types.Metrics,
) types.Error!?GlyphLocation {
    if (end < start) return error.BadSfnt;
    if (end == start) return null;
    if (start > std.math.maxInt(usize) - image_base) return error.BadSfnt;
    const offset = image_base + start;
    const length = end - start;
    // Prove the later CBDT slice addition now, while the location is built.
    if (length > std.math.maxInt(usize) - offset) return error.BadSfnt;
    return .{
        .image_format = image_format,
        .offset = offset,
        .length = length,
        .shared_metrics = shared_metrics,
    };
}

pub fn glyphLocationFormat1Or3(
    data: []const u8,
    selected_strike: Strike,
    offsets_offset: usize,
    first: glyph.GlyphId,
    last: glyph.GlyphId,
    local_index: usize,
    image_format: u16,
    image_base: usize,
    offset_size: usize,
) types.Error!?GlyphLocation {
    const glyphs = @as(usize, last - first) + 1;
    const offsets_len = (glyphs + 1) * offset_size;
    if (offsets_offset + offsets_len > data.len or
        offsets_offset + offsets_len >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }
    const start = try readOffset(
        data,
        offsets_offset + local_index * offset_size,
        offset_size,
    );
    const end = try readOffset(
        data,
        offsets_offset + (local_index + 1) * offset_size,
        offset_size,
    );
    // Equal adjacent offsets encode a missing glyph; decreasing offsets are
    // corruption and must not be silently treated as absence.
    return try imageLocation(image_format, image_base, start, end, null);
}

pub fn glyphLocationFormat2(
    data: []const u8,
    selected_strike: Strike,
    body_offset: usize,
    first: glyph.GlyphId,
    last: glyph.GlyphId,
    local_index: usize,
    image_format: u16,
    image_base: usize,
) types.Error!?GlyphLocation {
    if (body_offset + 12 > data.len or
        body_offset + 12 >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }
    const image_size = try bin.readU32At(data, body_offset);
    if (image_size == 0) return error.BadSfnt;
    const shared_metrics = try types.readBigMetrics(data, body_offset + 4);

    // Validate the terminal dense image as well as the requested one so range
    // multiplication overflow is caught while parsing the index.
    const glyphs = @as(usize, last - first) + 1;
    const last_start = try checkedImageStart(glyphs - 1, image_size);
    _ = try checkedImageEnd(last_start, image_size);

    const start = try checkedImageStart(local_index, image_size);
    const end = try checkedImageEnd(start, image_size);
    return try imageLocation(
        image_format,
        image_base,
        start,
        end,
        shared_metrics,
    );
}

pub fn glyphLocationFormat4(
    data: []const u8,
    selected_strike: Strike,
    body_offset: usize,
    glyph_id: glyph.GlyphId,
    image_format: u16,
    image_base: usize,
) types.Error!?GlyphLocation {
    if (body_offset + 4 > data.len or
        body_offset + 4 >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }
    const pair_count = try bin.readU32At(data, body_offset);
    const pairs_offset = body_offset + 4;
    const pairs_len = try checkedPairArrayLength(pair_count);
    if (pairs_len > std.math.maxInt(usize) - pairs_offset) {
        return error.BadSfnt;
    }
    const pairs_end = pairs_offset + pairs_len;
    if (pairs_end > data.len or
        pairs_end >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }
    var previous_glyph: ?glyph.GlyphId = null;
    var match: ?GlyphLocation = null;
    for (0..pair_count) |index| {
        const pair = pairs_offset + @as(usize, index) * 4;
        const current_glyph = try bin.readU16At(data, pair);
        const start = try bin.readU16At(data, pair + 2);
        const end = try bin.readU16At(data, pair + 6);
        // Sparse pairs remain sorted and scoped to the enclosing range. Check
        // all records before returning a match.
        if (current_glyph < selected_strike.start_glyph or
            current_glyph > selected_strike.end_glyph)
        {
            return error.BadSfnt;
        }
        if (previous_glyph) |previous| {
            if (current_glyph <= previous) return error.BadSfnt;
        }
        previous_glyph = current_glyph;
        const location =
            try imageLocation(image_format, image_base, start, end, null);
        if (current_glyph == glyph_id) match = location;
    }
    return match;
}

pub fn glyphLocationFormat5(
    data: []const u8,
    selected_strike: Strike,
    body_offset: usize,
    first: glyph.GlyphId,
    last: glyph.GlyphId,
    glyph_id: glyph.GlyphId,
    image_format: u16,
    image_base: usize,
) types.Error!?GlyphLocation {
    if (body_offset + 16 > data.len or
        body_offset + 16 >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }
    const image_size = try bin.readU32At(data, body_offset);
    const shared_metrics = try types.readBigMetrics(data, body_offset + 4);
    const glyph_count = try bin.readU32At(data, body_offset + 12);
    if (glyph_count == 0 or image_size == 0) return error.BadSfnt;

    const range_glyphs = @as(usize, last - first) + 1;
    if (@as(usize, glyph_count) > range_glyphs) return error.BadSfnt;
    const glyphs_offset = body_offset + 16;
    if (glyphs_offset + @as(usize, glyph_count) * 2 > data.len or
        glyphs_offset + @as(usize, glyph_count) * 2 >
            selected_strike.offset + selected_strike.index_tables_size)
    {
        return error.BadSfnt;
    }

    var previous: ?glyph.GlyphId = null;
    var match_index: ?usize = null;
    for (0..glyph_count) |index| {
        const current_glyph =
            try bin.readU16At(data, glyphs_offset + @as(usize, index) * 2);
        if (current_glyph < first or current_glyph > last) {
            return error.BadSfnt;
        }
        if (previous) |value| {
            if (current_glyph <= value) return error.BadSfnt;
        }
        previous = current_glyph;
        if (current_glyph == glyph_id) match_index = @intCast(index);
    }

    const index = match_index orelse return null;
    const start = try checkedImageStart(index, image_size);
    const end = try checkedImageEnd(start, image_size);
    return try imageLocation(
        image_format,
        image_base,
        start,
        end,
        shared_metrics,
    );
}

pub fn checkedImageStart(
    index: usize,
    image_size: u32,
) types.Error!usize {
    const size: usize = @intCast(image_size);
    if (index != 0 and size > std.math.maxInt(usize) / index) {
        return error.BadSfnt;
    }
    return index * size;
}

pub fn checkedImageEnd(
    start: usize,
    image_size: u32,
) types.Error!usize {
    const size: usize = @intCast(image_size);
    if (size > std.math.maxInt(usize) - start) return error.BadSfnt;
    return start + size;
}

fn readOffset(
    data: []const u8,
    offset: usize,
    size: usize,
) types.Error!usize {
    return switch (size) {
        2 => try bin.readU16At(data, offset),
        4 => try bin.readU32At(data, offset),
        else => error.BadSfnt,
    };
}

fn checkedPairArrayLength(pair_count: u32) types.Error!usize {
    if (@as(u64, pair_count) >= @as(u64, std.math.maxInt(usize))) {
        return error.BadSfnt;
    }
    const entries = @as(usize, @intCast(pair_count)) + 1;
    if (entries > std.math.maxInt(usize) / 4) return error.BadSfnt;
    return entries * 4;
}

test "CBLC bitmap index subtables reject decreasing image offsets" {
    const strike = Strike{
        .ppem_x = 16,
        .ppem = 16,
        .ppi = 0,
        .bit_depth = 1,
        .flags = 1,
        .offset = 0,
        .index_tables_size = 0,
        .table_count = 0,
        .start_glyph = 1,
        .end_glyph = 1,
    };

    var format3_offsets: [4]u8 = .{0} ** 4;
    writeU16(&format3_offsets, 0, 10);
    writeU16(&format3_offsets, 2, 4);
    var format3_strike = strike;
    format3_strike.index_tables_size = format3_offsets.len;
    try std.testing.expectError(error.BadSfnt, glyphLocationFormat1Or3(
        &format3_offsets,
        format3_strike,
        0,
        1,
        1,
        0,
        17,
        0,
        2,
    ));

    var format4_pairs: [12]u8 = .{0} ** 12;
    writeU32(&format4_pairs, 0, 1);
    writeU16(&format4_pairs, 4, 1);
    writeU16(&format4_pairs, 6, 10);
    writeU16(&format4_pairs, 8, 2);
    writeU16(&format4_pairs, 10, 4);
    var format4_strike = strike;
    format4_strike.index_tables_size = format4_pairs.len;
    try std.testing.expectError(error.BadSfnt, glyphLocationFormat4(&format4_pairs, format4_strike, 0, 1, 17, 0));
}

test "CBLC index subtable array validates ordering before returning a location" {
    const strike = Strike{
        .ppem_x = 16,
        .ppem = 16,
        .ppi = 0,
        .bit_depth = 1,
        .flags = 1,
        .offset = 0,
        .index_tables_size = 40,
        .table_count = 2,
        .start_glyph = 1,
        .end_glyph = 4,
    };

    var overlapping: [40]u8 = .{0} ** 40;
    writeU16(&overlapping, 0, 1);
    writeU16(&overlapping, 2, 2);
    writeU32(&overlapping, 4, 16);
    writeU16(&overlapping, 8, 2); // Overlaps the previous inclusive range.
    writeU16(&overlapping, 10, 3);
    writeU32(&overlapping, 12, 28);
    try std.testing.expectError(error.BadSfnt, glyphLocation(&overlapping, strike, 1));

    var subtable_overlap = overlapping;
    writeU16(&subtable_overlap, 8, 3); // Repair ordering.
    writeU16(&subtable_overlap, 10, 4);
    writeU32(&subtable_overlap, 12, 4); // Points into IndexSubTableArray records.
    try std.testing.expectError(error.BadSfnt, glyphLocation(&subtable_overlap, strike, 1));
}

test "CBLC format 4 sparse pairs validate every glyph record" {
    const strike = Strike{
        .ppem_x = 16,
        .ppem = 16,
        .ppi = 0,
        .bit_depth = 1,
        .flags = 1,
        .offset = 0,
        .index_tables_size = 24,
        .table_count = 1,
        .start_glyph = 1,
        .end_glyph = 4,
    };

    var data: [24]u8 = .{0} ** 24;
    writeU32(&data, 0, 2); // Two codeOffsetPair records plus a terminal offset.
    writeU16(&data, 4, 1);
    writeU16(&data, 6, 0);
    writeU16(&data, 8, 2);
    writeU16(&data, 10, 4);
    writeU16(&data, 12, 3);
    writeU16(&data, 14, 8);

    const location = (try glyphLocationFormat4(&data, strike, 0, 1, 17, 0)).?;
    try std.testing.expectEqual(@as(usize, 0), location.offset);
    try std.testing.expectEqual(@as(usize, 4), location.length);

    writeU16(&data, 8, 1); // Duplicate/decreasing glyph code after a valid match.
    try std.testing.expectError(error.BadSfnt, glyphLocationFormat4(&data, strike, 0, 1, 17, 0));

    writeU16(&data, 8, 5); // Outside the enclosing IndexSubTableArray range.
    try std.testing.expectError(error.BadSfnt, glyphLocationFormat4(&data, strike, 0, 1, 17, 0));
}

test "CBLC image locations reject arithmetic overflow before CBDT slicing" {
    const max = std.math.maxInt(usize);

    try std.testing.expectError(error.BadSfnt, imageLocation(17, max - 4, 8, 12, null));
    try std.testing.expectError(error.BadSfnt, imageLocation(17, max - 4, 2, 8, null));
    try std.testing.expectError(error.BadSfnt, checkedImageStart(max / 2 + 1, 2));
    try std.testing.expectError(error.BadSfnt, checkedImageEnd(max - 1, 2));

    const missing = try imageLocation(17, 10, 4, 4, null);
    try std.testing.expectEqual(@as(?GlyphLocation, null), missing);

    const location = (try imageLocation(17, 10, 4, 8, null)).?;
    try std.testing.expectEqual(@as(usize, 14), location.offset);
    try std.testing.expectEqual(@as(usize, 4), location.length);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
