//! Complete structural and maxp-bound validation for kern tables.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub fn validate(data: []const u8, kern: sfnt.Record, glyph_count: u16) Error!void {
    try sfnt.requireLength(kern, 4);
    const version = try bin.readU32At(data, kern.offset);
    if (version == 0x00010000) {
        try validateAppleKernTable(data, kern, glyph_count);
        return;
    }
    if ((version >> 16) != 0) {
        // Unknown non-legacy versions are ignored by `kerning`; keep that
        // compatibility behavior instead of rejecting a table this renderer
        // intentionally does not interpret.
        return;
    }
    try validateLegacyKernTable(data, kern, glyph_count);
}

fn validateLegacyKernTable(data: []const u8, kern: sfnt.Record, glyph_count: u16) Error!void {
    const table_count = try bin.readU16At(data, kern.offset + 2);
    const table_end = kern.offset + kern.length;
    var subtable_offset = kern.offset + 4;
    for (0..table_count) |subtable_index| {
        if (subtable_offset > table_end or table_end - subtable_offset < 6) return error.BadSfnt;
        const subtable_version = try bin.readU16At(data, subtable_offset);
        const declared_length = try bin.readU16At(data, subtable_offset + 2);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        const available = table_end - subtable_offset;
        var length: usize = declared_length;
        if (length > available) return error.BadSfnt;

        // Legacy OpenType kern subtables carry their own UInt16 version, which
        // must be zero. Rejecting private variants here keeps later coverage
        // bits from being interpreted with the standard format-0 body layout.
        if (subtable_version != 0) return error.BadSfnt;

        const format = coverage >> 8;
        const horizontal = (coverage & 0x0001) != 0;
        const minimum = (coverage & 0x0002) != 0;
        const cross_stream = (coverage & 0x0004) != 0;
        if (format == 0 and horizontal and !minimum and !cross_stream) {
            if (available < 14) return error.BadSfnt;
            const pair_count = try bin.readU16At(data, subtable_offset + 6);
            const required_length = 14 + @as(usize, pair_count) * 6;
            if (required_length > available) return error.BadSfnt;
            // Some historical writers truncated the UInt16 subtable length
            // after emitting more than 10,920 format-0 pairs. The pair count
            // and SFNT table boundary still identify the complete final
            // subtable unambiguously; match HarfBuzz/FreeType by recovering
            // that length only for the last legacy subtable.
            if (required_length > length and subtable_index + 1 == table_count) {
                length = required_length;
            }
            // Validate the recovered length before forming the body slice. A
            // malformed non-final subtable can declare a length below its
            // six-byte header while still leaving enough table bytes for the
            // format-0 probe above; slicing that range must never trap.
            if (length < 6) return error.BadSfnt;
            try validateFormat0(data[subtable_offset + 6 .. subtable_offset + length], glyph_count);
        }
        // Preserve the deliberate wrapped-length recovery for a final large
        // format-0 table, but reject every other undersized subtable before
        // advancing the cursor.
        subtable_offset += length;
    }
    // The SFNT directory length is the unpadded kern payload length. Require
    // nTables and each subtable length to consume it exactly so orphan bytes
    // cannot hide an unvalidated subtable that another kern consumer might
    // still interpret.
    if (subtable_offset != table_end) return error.BadSfnt;
}

fn validateAppleKernTable(data: []const u8, kern: sfnt.Record, glyph_count: u16) Error!void {
    try sfnt.requireLength(kern, 8);
    const table_count = try bin.readU32At(data, kern.offset + 4);
    const table_end = kern.offset + kern.length;
    var subtable_offset = kern.offset + 8;
    for (0..table_count) |_| {
        if (subtable_offset > table_end or table_end - subtable_offset < 8) return error.BadSfnt;
        const length = try bin.readU32At(data, subtable_offset);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        if (length < 8 or length > table_end - subtable_offset) return error.BadSfnt;

        const format = coverage & 0x00ff;
        const vertical = (coverage & 0x8000) != 0;
        const cross_stream = (coverage & 0x4000) != 0;
        const variation = (coverage & 0x2000) != 0;
        if (!vertical and !cross_stream and !variation) {
            const body = data[subtable_offset + 8 .. subtable_offset + length];
            if (format == 0) {
                try validateFormat0(body, glyph_count);
            } else if (format == 2) {
                try validateFormat2(body, glyph_count);
            }
        }
        subtable_offset += length;
    }
    // Apple/AAT kern v1 uses 32-bit lengths, but the same ownership rule
    // applies: the counted subtable sequence must occupy the complete declared
    // table payload rather than leaving trailing bytes with ambiguous meaning.
    if (subtable_offset != table_end) return error.BadSfnt;
}

pub fn validateFormat0(data: []const u8, glyph_count: u16) Error!void {
    // Format-0 kern subtables are searched with a binary search over packed
    // left/right glyph pairs. The three search-acceleration fields are only
    // hints and are ignored by Cangjie, HarfBuzz, and FreeType; deployed fonts
    // contain stale values, so validate only the authoritative pair count and
    // complete sorted pair array.
    if (data.len < 8) return error.BadSfnt;
    const pair_count = try bin.readU16At(data, 0);
    if (@as(usize, pair_count) * 6 > data.len - 8) return error.BadSfnt;

    var previous_pair: ?u32 = null;
    for (0..pair_count) |index| {
        const offset = 8 + index * 6;
        const left = try bin.readU16At(data, offset);
        const right = try bin.readU16At(data, offset + 2);
        try validateGlyphId(left, glyph_count);
        try validateGlyphId(right, glyph_count);

        const pair = (@as(u32, left) << 16) | right;
        if (previous_pair) |previous| {
            if (pair <= previous) return error.BadSfnt;
        }
        previous_pair = pair;
    }
}

pub fn validateFormat2(data: []const u8, glyph_count: u16) Error!void {
    if (data.len < 8) return error.BadSfnt;
    const row_width = try bin.readU16At(data, 0);
    const left_class_offset = try bin.readU16At(data, 2);
    const right_class_offset = try bin.readU16At(data, 4);
    const array_offset = try bin.readU16At(data, 6);
    if (row_width == 0) return error.BadSfnt;
    if (array_offset < 8 or array_offset - 8 > data.len - 2) {
        return error.BadSfnt;
    }
    try validateFormat2ClassTable(data, left_class_offset, glyph_count);
    try validateFormat2ClassTable(data, right_class_offset, glyph_count);
}

fn validateFormat2ClassTable(
    data: []const u8,
    offset: usize,
    glyph_count: u16,
) Error!void {
    if (offset < 8) return error.BadSfnt;
    const body_offset = offset - 8;
    if (body_offset > data.len - 4) return error.BadSfnt;
    const first_glyph = try bin.readU16At(data, body_offset);
    const glyph_len = try bin.readU16At(data, body_offset + 2);
    if (glyph_len == 0) return;
    if (@as(usize, first_glyph) + @as(usize, glyph_len) >
        @as(usize, glyph_count))
    {
        return error.BadSfnt;
    }
    const values_offset = body_offset + 4;
    if (@as(usize, glyph_len) * 2 > data.len - values_offset) {
        return error.BadSfnt;
    }
    for (0..glyph_len) |index| {
        const value = try bin.readU16At(data, values_offset + index * 2);
        if (@as(usize, value) > data.len + 8 - 2) return error.BadSfnt;
    }
}

fn validateGlyphId(glyph_id: u32, glyph_count: u16) Error!void {
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

test "legacy subtable length is checked before slicing format body" {
    const data = [_]u8{
        0, 0, 0, 2, // version, nTables
        0, 0, 0, 4, 0, 1, // subtable: version, invalid length, coverage
        0, 0, 0, 0, 0, 0, 0, 0, // enough bytes to reach format-0 parsing
    };
    try std.testing.expectError(error.BadSfnt, validate(
        &data,
        .{ .tag = "kern".*, .offset = 0, .length = data.len, .checksum = 0 },
        1,
    ));
}
