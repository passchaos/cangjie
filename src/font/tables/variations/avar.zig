//! OpenType avar v1 validation and normalized-coordinate mapping.

const std = @import("std");
const bin = @import("../../../binary.zig");
const sfnt = @import("../../sfnt/root.zig");
const fvar = @import("fvar/root.zig");

pub const Error = sfnt.Error || error{EndOfStream};

pub fn validate(
    data: []const u8,
    record: sfnt.Record,
    fvar_record: ?sfnt.Record,
) Error!void {
    _ = try walk(data, record, fvar_record, null, 0);
}

pub fn map(
    data: []const u8,
    record: sfnt.Record,
    fvar_record: ?sfnt.Record,
    axis_index: usize,
    normalized: f32,
) Error!f32 {
    if (!std.math.isFinite(normalized) or normalized < -1.0 or normalized > 1.0) {
        return error.BadSfnt;
    }
    return try walk(data, record, fvar_record, axis_index, normalized);
}

fn walk(
    data: []const u8,
    record: sfnt.Record,
    fvar_record: ?sfnt.Record,
    requested_axis: ?usize,
    normalized: f32,
) Error!f32 {
    if (record.offset > data.len or record.length > data.len - record.offset or
        record.length < 8)
    {
        return error.BadSfnt;
    }
    const table = data[record.offset .. record.offset + record.length];
    if (try bin.readU16At(table, 0) != 1 or
        try bin.readU16At(table, 2) != 0 or
        try bin.readU16At(table, 4) != 0)
    {
        return error.BadSfnt;
    }
    const axis_count: usize = @intCast(try bin.readU16At(table, 6));
    if (fvar_record) |fvar_table| {
        if (axis_count != (try fvar.info(data, fvar_table)).axis_count) {
            return error.BadSfnt;
        }
    } else if (axis_count != 0) {
        // Segment maps use fvar's axis order. Non-empty avar without fvar has
        // no authoritative mapping between array index and design axis.
        return error.BadSfnt;
    }
    if (requested_axis) |index| {
        if (index >= axis_count) return error.BadSfnt;
    }

    var offset: usize = 8;
    var mapped = normalized;
    for (0..axis_count) |axis_index| {
        if (offset > table.len or table.len - offset < 2) {
            return error.BadSfnt;
        }
        const pair_count: usize = @intCast(try bin.readU16At(table, offset));
        offset += 2;
        const pair_bytes = pair_count * 4;
        if (pair_bytes > table.len - offset) return error.BadSfnt;
        const segment = table[offset .. offset + pair_bytes];
        try validateSegment(segment);
        if (requested_axis) |selected| {
            if (selected == axis_index) {
                mapped = try mapSegment(segment, normalized);
            }
        }
        offset += pair_bytes;
    }
    // Validate every declared map, including maps after the selected axis, and
    // reject trailing bytes that no avar v1 field owns.
    if (offset != table.len) return error.BadSfnt;
    return mapped;
}

fn validateSegment(data: []const u8) Error!void {
    const pair_count = data.len / 4;
    if (pair_count < 3) return error.BadSfnt;

    var has_minus_one = false;
    var has_zero = false;
    var has_plus_one = false;
    var previous_from: ?i16 = null;
    var previous_to: ?i16 = null;
    for (0..pair_count) |index| {
        const offset = index * 4;
        const from = try bin.readI16At(data, offset);
        const to = try bin.readI16At(data, offset + 2);
        if (!isNormalized(from) or !isNormalized(to)) return error.BadSfnt;
        if (previous_from) |last| {
            if (from <= last) return error.BadSfnt;
        }
        if (previous_to) |last| {
            if (to < last) return error.BadSfnt;
        }
        if (from == -0x4000 and to == -0x4000) has_minus_one = true;
        if (from == 0 and to == 0) has_zero = true;
        if (from == 0x4000 and to == 0x4000) has_plus_one = true;
        previous_from = from;
        previous_to = to;
    }
    // Every map preserves the normalized endpoints and default coordinate.
    if (!has_minus_one or !has_zero or !has_plus_one) return error.BadSfnt;
}

fn mapSegment(data: []const u8, normalized: f32) Error!f32 {
    const pair_count = data.len / 4;
    var previous_from = f2dot14(try bin.readI16At(data, 0));
    var previous_to = f2dot14(try bin.readI16At(data, 2));
    if (normalized <= previous_from) return previous_to;
    for (1..pair_count) |index| {
        const offset = index * 4;
        const current_from = f2dot14(try bin.readI16At(data, offset));
        const current_to = f2dot14(try bin.readI16At(data, offset + 2));
        if (normalized <= current_from) {
            const t = (normalized - previous_from) /
                (current_from - previous_from);
            return previous_to + t * (current_to - previous_to);
        }
        previous_from = current_from;
        previous_to = current_to;
    }
    return previous_to;
}

fn isNormalized(value: i16) bool {
    return value >= -0x4000 and value <= 0x4000;
}

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}
