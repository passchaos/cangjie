const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;

pub const Error = error{BadSfnt} || error{EndOfStream};

pub const class_end_of_text: u16 = 0;
pub const class_out_of_bounds: u16 = 1;
pub const class_deleted_glyph: u16 = 2;
pub const dont_advance: u16 = 0x4000;

pub const Entry = struct {
    new_state: usize,
    flags: u16,
    payload: u16,
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
    if (class >= class_count or entry_size < 4) return error.BadSfnt;
    const state_row = std.math.mul(usize, state_index, class_count) catch return error.BadSfnt;
    const state_cell = std.math.add(usize, state_row, class) catch return error.BadSfnt;
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

/// Reads the AAT lookup formats used by current `morx` executors.
///
/// Format 6 covers sparse glyph/value pairs and format 8 covers trimmed
/// contiguous arrays. Unsupported formats are deliberately reported as no
/// mapping so an otherwise valid subtable can be skipped conservatively.
pub fn lookupGlyphValue(data: []const u8, offset: usize, length: usize, glyph: GlyphId) Error!?u16 {
    const format = try readU16(data, offset);
    switch (format) {
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
            if (glyph_index < first_glyph or glyph_index >= first_glyph + count) return null;
            const value_offset = offset + 6 + (glyph_index - first_glyph) * 2;
            if (value_offset > offset + length or offset + length - value_offset < 2) return error.BadSfnt;
            return try readU16(data, value_offset);
        },
        else => return null,
    }
}

pub fn readU16(data: []const u8, offset: usize) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

pub fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}
