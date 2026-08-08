const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const Info = struct {
    major_version: u16,
    minor_version: u16,
    axis_count: u16,
    shared_tuple_count: u16,
    shared_tuple_offset: usize,
    glyph_count: u16,
    flags: u16,
    glyph_data_offset: usize,
    offset_size: u8,
    glyph_variation_data_count: usize,
};

pub const GlyphInfo = struct {
    glyph_id: u16,
    data_offset: usize,
    data_length: usize,
    tuple_count: u16,
    uses_shared_point_numbers: bool,
    tuple_data_offset: usize,
};

pub const TupleInfo = struct {
    glyph_id: u16,
    tuple_index_in_glyph: u16,
    header_offset: usize,
    header_size: usize,
    variation_data_size: usize,
    raw_tuple_index: u16,
    embedded_peak_tuple: bool,
    intermediate_region: bool,
    private_point_numbers: bool,
    shared_tuple_index: ?u16 = null,
};

pub const PointNumbersInfo = struct {
    all_points: bool,
    count: usize,
    max_point: usize,
    bytes_consumed: usize,
};

pub fn packedPointNumbersInfo(data: []const u8, offset: usize, limit: usize) Error!PointNumbersInfo {
    if (offset > data.len or limit > data.len or offset >= limit) return error.BadSfnt;
    var cursor = offset;
    const first = data[cursor];
    cursor += 1;
    if (first == 0) return .{ .all_points = true, .count = 0, .max_point = 0, .bytes_consumed = cursor - offset };

    const point_count: usize = if ((first & 0x80) == 0) first else blk: {
        if (cursor >= limit) return error.BadSfnt;
        const second = data[cursor];
        cursor += 1;
        break :blk (@as(usize, first & 0x7f) << 8) | second;
    };

    var remaining = point_count;
    var last_point: usize = 0;
    var saw_point = false;
    while (remaining != 0) {
        if (cursor >= limit) return error.BadSfnt;
        const control = data[cursor];
        cursor += 1;
        const run_count = @as(usize, control & 0x7f) + 1;
        if (run_count > remaining) return error.BadSfnt;
        const words = (control & 0x80) != 0;
        for (0..run_count) |_| {
            const delta: usize = if (words) blk: {
                if (cursor > limit or 2 > limit - cursor) return error.BadSfnt;
                const value = readU16(data, cursor);
                cursor += 2;
                break :blk value;
            } else blk: {
                if (cursor >= limit) return error.BadSfnt;
                const value = data[cursor];
                cursor += 1;
                break :blk value;
            };
            if (delta > std.math.maxInt(usize) - last_point) return error.BadSfnt;
            last_point += delta;
            saw_point = true;
        }
        remaining -= run_count;
    }

    return .{
        .all_points = false,
        .count = point_count,
        .max_point = if (saw_point) last_point else 0,
        .bytes_consumed = cursor - offset,
    };
}

pub fn validate(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize) Error!void {
    _ = try info(data, offset, length, expected_glyph_count, expected_axis_count);
}

pub fn glyphInfo(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize) Error!?GlyphInfo {
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    if (glyph_id >= parsed.glyph_count) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const glyph_data_limit = table.len - parsed.glyph_data_offset;
    const start = try glyphDataOffset(table, 20 + glyph_id * @as(usize, parsed.offset_size), parsed.offset_size, glyph_data_limit);
    const end = try glyphDataOffset(table, 20 + (glyph_id + 1) * @as(usize, parsed.offset_size), parsed.offset_size, glyph_data_limit);
    if (end < start) return error.BadSfnt;
    if (end == start) return null;
    const data_start = parsed.glyph_data_offset + start;
    const data_length = end - start;
    if (data_length < 4 or data_length > table.len - data_start) return error.BadSfnt;
    const raw_tuple_count = readU16(table, data_start);
    if ((raw_tuple_count & 0x7000) != 0) return error.BadSfnt;
    const tuple_count = raw_tuple_count & 0x0fff;
    if (tuple_count == 0) return error.BadSfnt;
    const tuple_data_offset = readU16(table, data_start + 2);
    if (tuple_data_offset < 4 or tuple_data_offset > data_length) return error.BadSfnt;
    return .{
        .glyph_id = @intCast(glyph_id),
        .data_offset = data_start,
        .data_length = data_length,
        .tuple_count = tuple_count,
        .uses_shared_point_numbers = (raw_tuple_count & 0x8000) != 0,
        .tuple_data_offset = tuple_data_offset,
    };
}

pub fn tupleInfo(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize) Error!?TupleInfo {
    const glyph = (try glyphInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id)) orelse return null;
    if (tuple_index_in_glyph >= glyph.tuple_count) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    var header_offset = glyph.data_offset + 4;
    var tuple_data_bytes: usize = 0;
    for (0..glyph.tuple_count) |index| {
        const tuple = try readTupleInfo(table, parsed, glyph, header_offset, index, tuple_data_bytes);
        if (index == tuple_index_in_glyph) return tuple;
        header_offset += tuple.header_size;
        tuple_data_bytes += tuple.variation_data_size;
    }
    return error.BadSfnt;
}

pub fn tupleScalar(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, normalized_coords: []const f32) Error!f32 {
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    const tuple = (try tupleInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph)) orelse return error.BadSfnt;
    const table = data[offset .. offset + length];
    var result: f32 = 1.0;
    for (0..parsed.axis_count) |axis| {
        const peak = try tuplePeakCoordinate(table, parsed, tuple, axis);
        if (peak == 0) continue;
        const coord = if (axis < normalized_coords.len) normalized_coords[axis] else 0;
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) return error.BadSfnt;
        if (coord == 0) return 0;
        if (coord == peak) continue;
        if (tuple.intermediate_region) {
            const start = try tupleIntermediateCoordinate(table, parsed, tuple, axis, .start);
            const end = try tupleIntermediateCoordinate(table, parsed, tuple, axis, .end);
            if (start > peak or peak > end or (start < 0 and end > 0 and peak != 0)) continue;
            if (coord < start or coord > end) return 0;
            if (coord < peak) {
                if (peak != start) result *= (coord - start) / (peak - start);
            } else if (peak != end) {
                result *= (end - coord) / (end - peak);
            }
        } else {
            if (coord < @min(peak, 0) or coord > @max(peak, 0)) return 0;
            result *= coord / peak;
        }
    }
    return result;
}

pub fn info(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 20) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const major = readU16(table, 0);
    const minor = readU16(table, 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const axis_count = readU16(table, 4);
    const shared_tuple_count = readU16(table, 6);
    const shared_tuple_offset = readU32(table, 8);
    const glyph_count = readU16(table, 12);
    const flags = readU16(table, 14);
    const glyph_data_offset = readU32(table, 16);
    if (axis_count != expected_axis_count or glyph_count != expected_glyph_count) return error.BadSfnt;
    if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;

    const offset_size: u8 = if ((flags & 0x0001) != 0) 4 else 2;
    const offsets_len = (@as(usize, glyph_count) + 1) * @as(usize, offset_size);
    if (offsets_len > table.len - 20) return error.BadSfnt;
    const minimum_glyph_data_offset = 20 + offsets_len;
    if (glyph_data_offset < minimum_glyph_data_offset or glyph_data_offset > table.len) return error.BadSfnt;

    if (shared_tuple_count != 0) {
        if (shared_tuple_offset < minimum_glyph_data_offset or shared_tuple_offset > glyph_data_offset) return error.BadSfnt;
        const tuple_bytes = @as(usize, shared_tuple_count) * @as(usize, axis_count) * 2;
        if (tuple_bytes > glyph_data_offset - shared_tuple_offset) return error.BadSfnt;
    }

    const glyph_data_limit = table.len - glyph_data_offset;
    var previous = try glyphDataOffset(table, 20, offset_size, glyph_data_limit);
    var variation_data_count: usize = 0;
    for (0..glyph_count) |glyph_index| {
        const current = try glyphDataOffset(table, 20 + (@as(usize, glyph_index) + 1) * @as(usize, offset_size), offset_size, glyph_data_limit);
        if (current < previous) return error.BadSfnt;
        if (current > previous) variation_data_count += 1;
        previous = current;
    }

    return .{
        .major_version = major,
        .minor_version = minor,
        .axis_count = axis_count,
        .shared_tuple_count = shared_tuple_count,
        .shared_tuple_offset = shared_tuple_offset,
        .glyph_count = glyph_count,
        .flags = flags,
        .glyph_data_offset = glyph_data_offset,
        .offset_size = offset_size,
        .glyph_variation_data_count = variation_data_count,
    };
}

fn readTupleInfo(table: []const u8, parsed: Info, glyph: GlyphInfo, header_offset: usize, tuple_index_in_glyph: usize, preceding_tuple_data_bytes: usize) Error!TupleInfo {
    if (header_offset < glyph.data_offset or header_offset > glyph.data_offset + glyph.tuple_data_offset) return error.BadSfnt;
    if (header_offset > table.len or table.len - header_offset < 4) return error.BadSfnt;
    const variation_data_size = readU16(table, header_offset);
    const raw_tuple_index = readU16(table, header_offset + 2);
    if ((raw_tuple_index & 0x1000) != 0) return error.BadSfnt;
    const embedded_peak_tuple = (raw_tuple_index & 0x8000) != 0;
    const intermediate_region = (raw_tuple_index & 0x4000) != 0;
    const private_point_numbers = (raw_tuple_index & 0x2000) != 0;
    const shared_tuple_index: ?u16 = if (embedded_peak_tuple) null else raw_tuple_index & 0x0fff;
    if (shared_tuple_index) |shared| {
        if (shared >= parsed.shared_tuple_count) return error.BadSfnt;
    }
    var header_size: usize = 4;
    if (embedded_peak_tuple) header_size += @as(usize, parsed.axis_count) * 2;
    if (intermediate_region) header_size += @as(usize, parsed.axis_count) * 4;
    if (header_size > glyph.data_offset + glyph.tuple_data_offset - header_offset) return error.BadSfnt;
    if (variation_data_size > glyph.data_length - glyph.tuple_data_offset - preceding_tuple_data_bytes) return error.BadSfnt;
    return .{
        .glyph_id = glyph.glyph_id,
        .tuple_index_in_glyph = @intCast(tuple_index_in_glyph),
        .header_offset = header_offset,
        .header_size = header_size,
        .variation_data_size = variation_data_size,
        .raw_tuple_index = raw_tuple_index,
        .embedded_peak_tuple = embedded_peak_tuple,
        .intermediate_region = intermediate_region,
        .private_point_numbers = private_point_numbers,
        .shared_tuple_index = shared_tuple_index,
    };
}

const IntermediateKind = enum { start, end };

fn tuplePeakCoordinate(table: []const u8, parsed: Info, tuple: TupleInfo, axis: usize) Error!f32 {
    if (axis >= parsed.axis_count) return error.BadSfnt;
    const coord_offset = if (tuple.embedded_peak_tuple) blk: {
        break :blk tuple.header_offset + 4 + axis * 2;
    } else blk: {
        const shared = tuple.shared_tuple_index orelse return error.BadSfnt;
        break :blk parsed.shared_tuple_offset + @as(usize, shared) * @as(usize, parsed.axis_count) * 2 + axis * 2;
    };
    return try readNormalizedF2Dot14(table, coord_offset);
}

fn tupleIntermediateCoordinate(table: []const u8, parsed: Info, tuple: TupleInfo, axis: usize, kind: IntermediateKind) Error!f32 {
    if (!tuple.intermediate_region or axis >= parsed.axis_count) return error.BadSfnt;
    var base = tuple.header_offset + 4;
    if (tuple.embedded_peak_tuple) base += @as(usize, parsed.axis_count) * 2;
    if (kind == .end) base += @as(usize, parsed.axis_count) * 2;
    return try readNormalizedF2Dot14(table, base + axis * 2);
}

fn readNormalizedF2Dot14(data: []const u8, offset: usize) Error!f32 {
    if (offset > data.len or data.len - offset < 2) return error.BadSfnt;
    const value = std.mem.readInt(i16, data[offset..][0..2], .big);
    if (value < -0x4000 or value > 0x4000) return error.BadSfnt;
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

fn glyphDataOffset(table: []const u8, offset: usize, size: u8, limit: usize) Error!usize {
    if (offset > table.len or size > table.len - offset) return error.BadSfnt;
    const raw = switch (size) {
        2 => @as(usize, readU16(table, offset)) * 2,
        4 => readU32(table, offset),
        else => return error.BadSfnt,
    };
    if (raw > limit) return error.BadSfnt;
    return raw;
}

fn readU16(data: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) usize {
    return @intCast(std.mem.readInt(u32, data[offset..][0..4], .big));
}

test "gvar metadata parses offset arrays" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 2, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 26, // glyphVariationDataArrayOffset.
        0, 0, 0, 1, 0, 1, // offsets: 0, 2, 2.
        0, 0, // two bytes of glyph variation data for glyph 0.
    };
    const parsed = try info(&bytes, 0, bytes.len, 2, 1);
    try std.testing.expectEqual(@as(u16, 1), parsed.axis_count);
    try std.testing.expectEqual(@as(u16, 2), parsed.glyph_count);
    try std.testing.expectEqual(@as(u8, 2), parsed.offset_size);
    try std.testing.expectEqual(@as(usize, 1), parsed.glyph_variation_data_count);
}

test "gvar glyph metadata exposes tuple headers" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 2, // offsets: 0, 4.
        0, 1, 0, 4, // GlyphVariationData header: one tuple, dataOffset 4.
    };
    const parsed = (try glyphInfo(&bytes, 0, bytes.len, 1, 1, 0)).?;
    try std.testing.expectEqual(@as(u16, 0), parsed.glyph_id);
    try std.testing.expectEqual(@as(usize, 24), parsed.data_offset);
    try std.testing.expectEqual(@as(usize, 4), parsed.data_length);
    try std.testing.expectEqual(@as(u16, 1), parsed.tuple_count);
    try std.testing.expectEqual(@as(usize, 4), parsed.tuple_data_offset);
    try std.testing.expect(!parsed.uses_shared_point_numbers);
}

test "gvar tuple metadata exposes tuple flags" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 6, // offsets: 0, 12.
        0, 1, 0, 10, // GlyphVariationData header.
        0, 2, 0xa0, 0x00, // Tuple header: variationDataSize=2, embedded peak + private points.
        0x40, 0x00, // embedded peak tuple.
        0, 0, // two bytes tuple data.
    };
    const tuple = (try tupleInfo(&bytes, 0, bytes.len, 1, 1, 0, 0)).?;
    try std.testing.expectEqual(@as(u16, 0), tuple.glyph_id);
    try std.testing.expectEqual(@as(usize, 28), tuple.header_offset);
    try std.testing.expectEqual(@as(usize, 6), tuple.header_size);
    try std.testing.expectEqual(@as(usize, 2), tuple.variation_data_size);
    try std.testing.expect(tuple.embedded_peak_tuple);
    try std.testing.expect(tuple.private_point_numbers);
    try std.testing.expect(!tuple.intermediate_region);
    try std.testing.expect(tuple.shared_tuple_index == null);
}

test "gvar tuple scalar uses embedded peak" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 6, // offsets: 0, 12.
        0, 2, 0, 10, // GlyphVariationData header.
        0, 2, 0x80, 0x00, // embedded peak.
        0x40, 0x00, // peak = 1.
        0, 0, // tuple data.
    };
    try std.testing.expectEqual(@as(f32, 0), try tupleScalar(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{}));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), try tupleScalar(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{0.5}), 0.001);
    try std.testing.expectEqual(@as(f32, 1), try tupleScalar(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{1}));
}

test "gvar tuple scalar uses intermediate region" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 8, // offsets: 0, 16.
        0, 2, 0, 14, // GlyphVariationData header.
        0, 2, 0xc0, 0x00, // embedded peak + intermediate.
        0x20, 0x00, // peak = 0.5.
        0, 0, // start = 0.
        0x40, 0x00, // end = 1.
        0, 0, // tuple data.
    };
    try std.testing.expectEqual(@as(f32, 0), try tupleScalar(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{0}));
    try std.testing.expectEqual(@as(f32, 1), try tupleScalar(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{0.5}));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), try tupleScalar(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{0.75}), 0.001);
}

test "gvar packed point numbers expose counts" {
    const all_points = try packedPointNumbersInfo(&.{0}, 0, 1);
    try std.testing.expect(all_points.all_points);
    try std.testing.expectEqual(@as(usize, 1), all_points.bytes_consumed);

    const explicit = try packedPointNumbersInfo(&.{ 3, 2, 1, 2, 3 }, 0, 5);
    try std.testing.expect(!explicit.all_points);
    try std.testing.expectEqual(@as(usize, 3), explicit.count);
    try std.testing.expectEqual(@as(usize, 6), explicit.max_point);
    try std.testing.expectEqual(@as(usize, 5), explicit.bytes_consumed);
}

test "gvar packed point numbers support word deltas" {
    const parsed = try packedPointNumbersInfo(&.{ 3, 0x82, 0, 1, 0, 2, 0, 3 }, 0, 8);
    try std.testing.expectEqual(@as(usize, 3), parsed.count);
    try std.testing.expectEqual(@as(usize, 6), parsed.max_point);
    try std.testing.expectEqual(@as(usize, 8), parsed.bytes_consumed);
    try std.testing.expectError(error.BadSfnt, packedPointNumbersInfo(&.{ 2, 2, 1 }, 0, 3));
}
