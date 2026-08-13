const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;

pub const Error = error{BadSfnt} || error{EndOfStream};

pub const class_end_of_text: u16 = 0;
pub const class_out_of_bounds: u16 = 1;
pub const class_deleted_glyph: u16 = 2;
pub const dont_advance: u16 = 0x4000;
pub const max_operations_factor = 4096;
pub const min_operations = 65536;

pub const Entry = struct {
    new_state: usize,
    flags: u16,
    payload: u16,
    payload_2: u16,
};

/// Reads one extended AAT state-machine entry.
///
/// `morx` state rows contain entry indices rather than byte offsets. The
/// checked arithmetic is intentionally centralized here because every
/// state-machine subtable must reject wrapped state or entry indices before
/// dereferencing borrowed font bytes.
pub fn entry(
    data: []const u8,
    offset: usize,
    length: usize,
    state_array_offset: usize,
    entry_table_offset: usize,
    class_count: usize,
    state_index: usize,
    class: u16,
    entry_size: usize,
) Error!Entry {
    if (class_count < 4 or entry_size < 4) return error.BadSfnt;
    const bounded_class: usize = if (class < class_count) class else class_out_of_bounds;
    const state_row = std.math.mul(usize, state_index, class_count) catch return error.BadSfnt;
    const state_cell = std.math.add(usize, state_row, bounded_class) catch return error.BadSfnt;
    const state_byte = std.math.mul(usize, state_cell, 2) catch return error.BadSfnt;
    const state_relative = std.math.add(usize, state_array_offset, state_byte) catch return error.BadSfnt;
    if (state_relative > length or length - state_relative < 2) return error.BadSfnt;

    const entry_index: usize = @intCast(try readU16(data, offset + state_relative));
    const entry_byte = std.math.mul(usize, entry_index, entry_size) catch return error.BadSfnt;
    const entry_relative = std.math.add(usize, entry_table_offset, entry_byte) catch return error.BadSfnt;
    if (entry_relative > length or length - entry_relative < entry_size) return error.BadSfnt;
    const entry_offset = offset + entry_relative;
    return .{
        .new_state = @intCast(try readU16(data, entry_offset)),
        .flags = try readU16(data, entry_offset + 2),
        .payload = if (entry_size >= 6) try readU16(data, entry_offset + 4) else 0,
        .payload_2 = if (entry_size >= 8) try readU16(data, entry_offset + 6) else 0,
    };
}

pub fn classForGlyph(
    data: []const u8,
    offset: usize,
    length: usize,
    class_table_offset: usize,
    glyph: GlyphId,
) Error!u16 {
    if (glyph == 0xffff) return class_deleted_glyph;
    if (class_table_offset > length) return error.BadSfnt;
    const lookup = offset + class_table_offset;
    return (try lookupGlyphValue(data, lookup, length - class_table_offset, glyph)) orelse class_out_of_bounds;
}

/// Reads one value from a complete AAT lookup table.
pub fn lookupGlyphValue(data: []const u8, offset: usize, length: usize, glyph: GlyphId) Error!?u16 {
    return lookupGlyphValueBounded(data, offset, length, glyph, null);
}

/// Reads one AAT lookup value while optionally bounding format 0 by the
/// containing font's glyph count.
///
/// Formats 6 and 8 are the compact forms used by all retained `morx`
/// fixtures. Contextual substitution additionally needs format 0 because its
/// per-action lookup has no internal length; the validated `maxp` count gives
/// that dense array an exact bound.
pub fn lookupGlyphValueBounded(data: []const u8, offset: usize, length: usize, glyph: GlyphId, glyph_count: ?usize) Error!?u16 {
    const format = try readU16(data, offset);
    switch (format) {
        0 => {
            const count = glyph_count orelse return null;
            const glyph_index: usize = glyph;
            if (count > (length -| 2) / 2) return error.BadSfnt;
            if (glyph_index >= count) return null;
            return try readU16(data, offset + 2 + glyph_index * 2);
        },
        2 => {
            if (length < 12) return error.BadSfnt;
            const unit_size: usize = try readU16(data, offset + 2);
            const count: usize = @intCast(try readU16(data, offset + 4));
            if (unit_size < 6 or count > (length - 12) / unit_size) return error.BadSfnt;
            const entries_offset = offset + 12;
            for (0..count) |index| {
                const current = entries_offset + index * unit_size;
                const last = try readU16(data, current);
                const first = try readU16(data, current + 2);
                if (glyph >= first and glyph <= last) return try readU16(data, current + 4);
            }
            return null;
        },
        4 => {
            if (length < 12) return error.BadSfnt;
            const unit_size: usize = try readU16(data, offset + 2);
            const count: usize = @intCast(try readU16(data, offset + 4));
            if (unit_size < 6 or count > (length - 12) / unit_size) return error.BadSfnt;
            const entries_offset = offset + 12;
            for (0..count) |index| {
                const current = entries_offset + index * unit_size;
                const last = try readU16(data, current);
                const first = try readU16(data, current + 2);
                if (first > last) return error.BadSfnt;
                if (glyph < first or glyph > last) continue;
                const values_offset: usize = @intCast(try readU16(data, current + 4));
                const value_index = std.math.sub(usize, glyph, first) catch return error.BadSfnt;
                const value_delta = std.math.mul(usize, value_index, 2) catch return error.BadSfnt;
                const value_relative = std.math.add(usize, values_offset, value_delta) catch return error.BadSfnt;
                if (value_relative > length or length - value_relative < 2) return error.BadSfnt;
                return try readU16(data, offset + value_relative);
            }
            return null;
        },
        6 => {
            if (length < 12) return error.BadSfnt;
            const unit_size = try readU16(data, offset + 2);
            const count: usize = @intCast(try readU16(data, offset + 4));
            if (unit_size < 4) return error.BadSfnt;
            const entries_offset = offset + 12;
            if (count > (length - 12) / unit_size) return error.BadSfnt;
            var lo: usize = 0;
            var hi: usize = count;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                const current = entries_offset + mid * unit_size;
                const entry_glyph = try readU16(data, current);
                if (glyph < entry_glyph) {
                    hi = mid;
                } else if (glyph > entry_glyph) {
                    lo = mid + 1;
                } else {
                    return try readU16(data, current + 2);
                }
            }
            return null;
        },
        8 => {
            if (length < 6) return error.BadSfnt;
            const first_glyph: usize = @intCast(try readU16(data, offset + 2));
            const count: usize = @intCast(try readU16(data, offset + 4));
            const glyph_index: usize = glyph;
            const glyph_end = std.math.add(usize, first_glyph, count) catch return error.BadSfnt;
            if (glyph_index < first_glyph or glyph_index >= glyph_end) return null;
            const value_offset = offset + 6 + (glyph_index - first_glyph) * 2;
            if (value_offset > offset + length or offset + length - value_offset < 2) return error.BadSfnt;
            return try readU16(data, value_offset);
        },
        10 => {
            if (length < 8) return error.BadSfnt;
            const unit_size: usize = try readU16(data, offset + 2);
            if (unit_size != 1 and unit_size != 2 and unit_size != 4) return error.BadSfnt;
            const first_glyph: usize = @intCast(try readU16(data, offset + 4));
            const count: usize = @intCast(try readU16(data, offset + 6));
            const values_len = std.math.mul(usize, count, unit_size) catch return error.BadSfnt;
            if (values_len > length - 8) return error.BadSfnt;
            const glyph_end = std.math.add(usize, first_glyph, count) catch return error.BadSfnt;
            const glyph_index: usize = glyph;
            if (glyph_index < first_glyph or glyph_index >= glyph_end) return null;
            const value_index = glyph_index - first_glyph;
            const value_offset = offset + 8 + value_index * unit_size;
            return switch (unit_size) {
                1 => data[value_offset],
                2 => try readU16(data, value_offset),
                // AAT Lookup<u16> deliberately truncates format-10's optional
                // 32-bit storage, matching both HarfBuzz and read-fonts.
                4 => @truncate(try readU32(data, value_offset)),
                else => unreachable,
            };
        },
        else => return null,
    }
}

/// Exhaustively validate one AAT lookup whose public value type is `u16`.
///
/// The lookup formats do not carry a common byte length. Callers therefore
/// provide the enclosing subtable suffix and its maxp glyph bound; reading
/// every reachable glyph proves both dense payloads and sparse record offsets
/// before a shaping hot path starts trusting individual lookup results.
pub fn validateLookupU16(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    if (glyph_count > @as(usize, std.math.maxInt(GlyphId)) + 1) return error.BadSfnt;
    const format = try readU16(data, offset);
    switch (format) {
        0 => {
            if (glyph_count > (length -| 2) / 2) return error.BadSfnt;
        },
        2, 4 => {
            if (length < 12) return error.BadSfnt;
            const unit_size: usize = try readU16(data, offset + 2);
            const unit_count: usize = @intCast(try readU16(data, offset + 4));
            if (unit_size < 6 or unit_count > (length - 12) / unit_size) return error.BadSfnt;
            var previous_last: ?u16 = null;
            for (0..unit_count) |index| {
                const record = offset + 12 + index * unit_size;
                const last = try readU16(data, record);
                const first = try readU16(data, record + 2);
                if (first == 0xffff and last == 0xffff) {
                    if (index + 1 != unit_count) return error.BadSfnt;
                    continue;
                }
                if (first > last or last >= glyph_count) return error.BadSfnt;
                if (previous_last) |previous| if (first <= previous) return error.BadSfnt;
                previous_last = last;
                if (format == 4) {
                    const values_offset: usize = @intCast(try readU16(data, record + 4));
                    const value_count = @as(usize, last) - first + 1;
                    const value_bytes = std.math.mul(usize, value_count, 2) catch return error.BadSfnt;
                    if (values_offset > length or value_bytes > length - values_offset) return error.BadSfnt;
                }
            }
        },
        6 => {
            if (length < 12) return error.BadSfnt;
            const unit_size: usize = try readU16(data, offset + 2);
            const unit_count: usize = @intCast(try readU16(data, offset + 4));
            if (unit_size < 4 or unit_count > (length - 12) / unit_size) return error.BadSfnt;
            var previous_glyph: ?u16 = null;
            for (0..unit_count) |index| {
                const record = offset + 12 + index * unit_size;
                const glyph = try readU16(data, record);
                if (glyph == 0xffff) {
                    if (index + 1 != unit_count) return error.BadSfnt;
                    continue;
                }
                if (glyph >= glyph_count) return error.BadSfnt;
                if (previous_glyph) |previous| if (glyph <= previous) return error.BadSfnt;
                previous_glyph = glyph;
            }
        },
        8 => {
            if (length < 6) return error.BadSfnt;
            const first_glyph: usize = @intCast(try readU16(data, offset + 2));
            const count: usize = @intCast(try readU16(data, offset + 4));
            const glyph_end = std.math.add(usize, first_glyph, count) catch return error.BadSfnt;
            if (glyph_end > glyph_count or count > (length - 6) / 2) return error.BadSfnt;
        },
        10 => {
            if (length < 8) return error.BadSfnt;
            const unit_size: usize = try readU16(data, offset + 2);
            if (unit_size != 1 and unit_size != 2 and unit_size != 4) return error.BadSfnt;
            const first_glyph: usize = @intCast(try readU16(data, offset + 4));
            const count: usize = @intCast(try readU16(data, offset + 6));
            const glyph_end = std.math.add(usize, first_glyph, count) catch return error.BadSfnt;
            const value_bytes = std.math.mul(usize, count, unit_size) catch return error.BadSfnt;
            if (glyph_end > glyph_count or value_bytes > length - 8) return error.BadSfnt;
        },
        else => return error.BadSfnt,
    }
}

pub fn operationBudget(glyph_count: usize) Error!usize {
    const scaled = std.math.mul(usize, glyph_count, max_operations_factor) catch return error.BadSfnt;
    return @max(scaled, min_operations);
}

pub fn readU16(data: []const u8, offset: usize) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

pub fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "AAT lookup formats 0, 2, and 4 return bounded glyph values" {
    const dense = [_]u8{
        0x00, 0x00, // format 0
        0x00, 0x07,
        0x00, 0x08,
        0x00, 0x09,
    };
    try std.testing.expectEqual(
        @as(?u16, 8),
        try lookupGlyphValueBounded(&dense, 0, dense.len, 1, 3),
    );
    try std.testing.expectEqual(
        @as(?u16, null),
        try lookupGlyphValueBounded(&dense, 0, dense.len, 3, 3),
    );
    try std.testing.expectError(
        error.BadSfnt,
        lookupGlyphValueBounded(dense[0..6], 0, 6, 1, 3),
    );

    const segments = [_]u8{
        0x00, 0x02, // format 2
        0x00, 0x06, // unit size
        0x00, 0x01, // one segment
        0x00, 0x06, // binary-search metadata is not needed by the reader
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x04, // last glyph
        0x00, 0x02, // first glyph
        0x00, 0x0b, // shared value
    };
    try std.testing.expectEqual(
        @as(?u16, 11),
        try lookupGlyphValueBounded(&segments, 0, segments.len, 3, null),
    );
    try std.testing.expectEqual(
        @as(?u16, null),
        try lookupGlyphValueBounded(&segments, 0, segments.len, 5, null),
    );

    const segment_arrays = [_]u8{
        0x00, 0x04, // format 4
        0x00, 0x06, // unit size
        0x00, 0x01, // one segment
        0x00, 0x06,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x04, // last glyph
        0x00, 0x02, // first glyph
        0x00, 0x12, // values start at byte 18
        0x00, 0x15,
        0x00, 0x16,
        0x00, 0x17,
    };
    try std.testing.expectEqual(
        @as(?u16, 22),
        try lookupGlyphValueBounded(&segment_arrays, 0, segment_arrays.len, 3, null),
    );
    try std.testing.expectEqual(
        @as(?u16, null),
        try lookupGlyphValueBounded(&segment_arrays, 0, segment_arrays.len, 5, null),
    );
}

test "AAT lookup format 10 supports byte word and truncated long values" {
    const byte_values = [_]u8{
        0x00, 0x0a, // format 10
        0x00, 0x01, // unit size
        0x00, 0x02, // first glyph
        0x00, 0x03, // glyph count
        0x07, 0x08, 0x09,
    };
    try std.testing.expectEqual(@as(?u16, 8), try lookupGlyphValue(&byte_values, 0, byte_values.len, 3));
    try std.testing.expectEqual(@as(?u16, null), try lookupGlyphValue(&byte_values, 0, byte_values.len, 5));

    const word_values = [_]u8{
        0x00, 0x0a, 0x00, 0x02, 0x00, 0x01, 0x00, 0x02,
        0x12, 0x34, 0xab, 0xcd,
    };
    try std.testing.expectEqual(@as(?u16, 0xabcd), try lookupGlyphValue(&word_values, 0, word_values.len, 2));

    const long_values = [_]u8{
        0x00, 0x0a, 0x00, 0x04, 0x00, 0x04, 0x00, 0x01,
        0x12, 0x34, 0xab, 0xcd,
    };
    try std.testing.expectEqual(@as(?u16, 0xabcd), try lookupGlyphValue(&long_values, 0, long_values.len, 4));

    var malformed = byte_values;
    malformed[3] = 3;
    try std.testing.expectError(error.BadSfnt, lookupGlyphValue(&malformed, 0, malformed.len, 3));
}
