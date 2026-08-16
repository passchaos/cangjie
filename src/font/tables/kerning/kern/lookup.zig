//! Pair lookup after a caller has established the complete table proof.

const std = @import("std");
const bin = @import("../../../../binary.zig");
const sfnt = @import("../../../sfnt/root.zig");
const validation = @import("validation.zig");

pub const GlyphId = u16;
pub const Error = sfnt.Error || error{EndOfStream};

pub fn kerningAfterProof(
    data: []const u8,
    table: sfnt.Record,
    left: GlyphId,
    right: GlyphId,
) Error!i16 {
    if (table.length < 4) return 0;
    const version = try bin.readU32At(data, table.offset);
    if (version == 0x00010000) {
        return appleKerning(data, table, left, right);
    }
    if ((version >> 16) != 0) return 0;
    return legacyKerning(data, table, left, right);
}

fn legacyKerning(data: []const u8, kern: sfnt.Record, left: GlyphId, right: GlyphId) Error!i16 {
    const table_count = try bin.readU16At(data, kern.offset + 2);
    const table_end = kern.offset + kern.length;
    var subtable_offset = kern.offset + 4;
    var total: i32 = 0;
    var saw_matching_pair = false;
    for (0..table_count) |_| {
        if (subtable_offset > table_end or table_end - subtable_offset < 6) return error.BadSfnt;
        const subtable_version = try bin.readU16At(data, subtable_offset);
        const length = try bin.readU16At(data, subtable_offset + 2);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        if (length < 6 or length > table_end - subtable_offset) return error.BadSfnt;
        if (subtable_version != 0) return error.BadSfnt;
        const format = coverage >> 8;
        const horizontal = (coverage & 0x0001) != 0;
        const minimum = (coverage & 0x0002) != 0;
        const cross_stream = (coverage & 0x0004) != 0;
        const override = (coverage & 0x0008) != 0;
        if (format == 0 and horizontal and !minimum and !cross_stream) {
            // OpenType/Windows subtables have a six-byte common header
            // before the format-0 binary-search payload.
            if (try kernFormat0Body(data[subtable_offset + 6 .. subtable_offset + length], left, right)) |value| {
                saw_matching_pair = true;
                if (override) {
                    total = value;
                } else {
                    total += value;
                }
            }
        }
        subtable_offset += length;
    }
    if (!saw_matching_pair) return 0;
    return @intCast(std.math.clamp(total, std.math.minInt(i16), std.math.maxInt(i16)));
}

fn appleKerning(data: []const u8, kern: sfnt.Record, left: GlyphId, right: GlyphId) Error!i16 {
    if (kern.length < 8) return error.BadSfnt;
    const table_count = try bin.readU32At(data, kern.offset + 4);
    const table_end = kern.offset + kern.length;
    var subtable_offset = kern.offset + 8;
    var total: i32 = 0;
    var saw_matching_pair = false;
    for (0..table_count) |_| {
        if (subtable_offset > table_end or table_end - subtable_offset < 8) return error.BadSfnt;
        const length = try bin.readU32At(data, subtable_offset);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        if (length < 8 or length > table_end - subtable_offset) return error.BadSfnt;

        // Apple/AAT version-1 subtables use different coverage bits from
        // the legacy OpenType header: format lives in the low byte, while a
        // clear vertical bit means normal horizontal kerning. Variation and
        // cross-stream tables need extra state this API does not provide, so
        // they are skipped rather than applying incorrect horizontal deltas.
        const format = coverage & 0x00ff;
        const vertical = (coverage & 0x8000) != 0;
        const cross_stream = (coverage & 0x4000) != 0;
        const variation = (coverage & 0x2000) != 0;
        if (!vertical and !cross_stream and !variation) {
            const body = data[subtable_offset + 8 .. subtable_offset + length];
            const value = if (format == 0)
                // AAT subtables have an eight-byte common header (including
                // tupleIndex) before the same format-0 pair-search payload.
                try kernFormat0Body(body, left, right)
            else if (format == 2)
                try kernFormat2Body(body, left, right)
            else
                null;
            if (value) |kern_value| {
                saw_matching_pair = true;
                total += kern_value;
            }
        }
        subtable_offset += length;
    }
    if (!saw_matching_pair) return 0;
    return @intCast(std.math.clamp(total, std.math.minInt(i16), std.math.maxInt(i16)));
}
fn kernFormat0Body(data: []const u8, left: GlyphId, right: GlyphId) Error!?i16 {
    // The format-0 body begins with the binary-search header; the surrounding
    // kern table variant owns the common subtable header length.
    if (data.len < 8) return error.BadSfnt;
    const pair_count = try bin.readU16At(data, 0);
    if (@as(usize, pair_count) * 6 > data.len - 8) return error.BadSfnt;
    const needle = (@as(u32, left) << 16) | right;
    var lo: usize = 0;
    var hi: usize = pair_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const offset = 8 + mid * 6;
        const pair = (@as(u32, try bin.readU16At(data, offset)) << 16) | try bin.readU16At(data, offset + 2);
        if (needle < pair) {
            hi = mid;
        } else if (needle > pair) {
            lo = mid + 1;
        } else {
            return try bin.readI16At(data, offset + 4);
        }
    }
    return null;
}

fn kernFormat2Body(data: []const u8, left: GlyphId, right: GlyphId) Error!?i16 {
    try validation.validateFormat2(data, std.math.maxInt(u16));
    const left_class_offset = try bin.readU16At(data, 2);
    const right_class_offset = try bin.readU16At(data, 4);
    const left_offset = try kernFormat2ClassValue(data, left_class_offset, left);
    const right_offset = try kernFormat2ClassValue(data, right_class_offset, right);
    if (left_offset == 0 or right_offset == 0) return null;
    const combined_offset = @as(usize, left_offset) + @as(usize, right_offset);
    if (combined_offset < 8) return null;
    const value_offset = combined_offset - 8;
    if (value_offset > data.len - 2) return error.BadSfnt;
    const value = try bin.readI16At(data, value_offset);
    return if (value == 0) null else value;
}

fn kernFormat2ClassValue(data: []const u8, class_table_offset: usize, glyph: GlyphId) Error!u16 {
    if (class_table_offset < 8) return error.BadSfnt;
    const body_offset = class_table_offset - 8;
    if (body_offset > data.len - 4) return error.BadSfnt;
    const first_glyph = try bin.readU16At(data, body_offset);
    const glyph_len = try bin.readU16At(data, body_offset + 2);
    if (glyph < first_glyph or glyph >= first_glyph + glyph_len) return 0;
    const value_offset = body_offset + 4 + (@as(usize, glyph - first_glyph) * 2);
    if (value_offset > data.len - 2) return error.BadSfnt;
    return try bin.readU16At(data, value_offset);
}
