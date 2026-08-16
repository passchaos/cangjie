//! TrueType loca bounds, full-table validation, and glyph offset reads.

const std = @import("std");
const bin = @import("../../../binary.zig");
const sfnt = @import("../../sfnt/root.zig");

pub const Error = sfnt.Error || error{ InvalidLoca, EndOfStream };

pub fn requiredLength(
    last_glyph_index: u32,
    index_to_loc_format: i16,
) Error!usize {
    const entry_count = @as(u64, last_glyph_index) + 1;
    const entry_size: u64 = switch (index_to_loc_format) {
        0 => 2,
        1 => 4,
        else => return error.InvalidLoca,
    };
    const length = entry_count * entry_size;
    if (length > std.math.maxInt(usize)) {
        return error.InvalidLoca;
    }
    return @intCast(length);
}

pub fn validate(
    data: []const u8,
    loca: sfnt.Record,
    glyf: sfnt.Record,
    glyph_count: u16,
    index_to_loc_format: i16,
) Error!void {
    if (loca.offset > data.len or loca.length > data.len - loca.offset) {
        return error.InvalidLoca;
    }
    const required = try requiredLength(glyph_count, index_to_loc_format);
    if (loca.length < required) return error.InvalidLoca;

    // loca is the authoritative glyph-byte map. Prove the complete array now
    // so accepting a face never depends on which glyph happens to be outlined.
    var previous: usize = 0;
    for (0..@as(usize, glyph_count) + 1) |index| {
        const current = try offset(data, loca, index_to_loc_format, index);
        if (current < previous or current > glyf.length) {
            return error.InvalidLoca;
        }
        previous = current;
    }
}

pub fn offset(
    data: []const u8,
    loca: sfnt.Record,
    index_to_loc_format: i16,
    glyph_index: usize,
) Error!usize {
    const byte_offset = switch (index_to_loc_format) {
        0 => glyph_index * 2,
        1 => glyph_index * 4,
        else => return error.InvalidLoca,
    };
    if (byte_offset > loca.length or
        (index_to_loc_format == 0 and loca.length - byte_offset < 2) or
        (index_to_loc_format == 1 and loca.length - byte_offset < 4))
    {
        return error.InvalidLoca;
    }
    if (loca.offset > data.len or byte_offset > data.len - loca.offset) {
        return error.InvalidLoca;
    }
    const absolute = loca.offset + byte_offset;
    return switch (index_to_loc_format) {
        0 => @as(usize, try bin.readU16At(data, absolute)) * 2,
        1 => try bin.readU32At(data, absolute),
        else => unreachable,
    };
}
