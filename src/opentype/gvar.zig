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

pub const PackedDeltasInfo = struct {
    count: usize,
    bytes_consumed: usize,
    zero_count: usize,
    byte_count: usize,
    word_count: usize,
};

pub const TuplePayloadInfo = struct {
    tuple_data_offset: usize,
    tuple_data_length: usize,
    point_numbers_offset: ?usize = null,
    point_numbers: PointNumbersInfo,
    x_deltas_offset: usize,
    x_deltas: PackedDeltasInfo,
    y_deltas_offset: usize,
    y_deltas: PackedDeltasInfo,
};

pub const PointDelta = struct {
    point: u16,
    x: i32,
    y: i32,
};

pub const ScaledPointDelta = struct {
    point: u16,
    x: f32,
    y: f32,
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

pub fn packedDeltasInfo(data: []const u8, offset: usize, limit: usize, delta_count: usize) Error!PackedDeltasInfo {
    if (offset > data.len or limit > data.len or offset > limit) return error.BadSfnt;
    var cursor = offset;
    var remaining = delta_count;
    var zero_count: usize = 0;
    var byte_count: usize = 0;
    var word_count: usize = 0;
    while (remaining != 0) {
        if (cursor >= limit) return error.BadSfnt;
        const control = data[cursor];
        cursor += 1;
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > remaining) return error.BadSfnt;
        const run_bytes: usize = if ((control & 0x80) != 0) blk: {
            zero_count += run_count;
            break :blk 0;
        } else if ((control & 0x40) != 0) blk: {
            word_count += run_count;
            break :blk run_count * 2;
        } else blk: {
            byte_count += run_count;
            break :blk run_count;
        };
        if (run_bytes > limit - cursor) return error.BadSfnt;
        cursor += run_bytes;
        remaining -= run_count;
    }
    return .{
        .count = delta_count,
        .bytes_consumed = cursor - offset,
        .zero_count = zero_count,
        .byte_count = byte_count,
        .word_count = word_count,
    };
}

pub fn decodePackedDeltas(data: []const u8, offset: usize, limit: usize, out: []i32) Error!usize {
    if (offset > data.len or limit > data.len or offset > limit) return error.BadSfnt;
    var cursor = offset;
    var written: usize = 0;
    while (written < out.len) {
        if (cursor >= limit) return error.BadSfnt;
        const control = data[cursor];
        cursor += 1;
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > out.len - written) return error.BadSfnt;
        if ((control & 0x80) != 0) {
            @memset(out[written .. written + run_count], 0);
        } else if ((control & 0x40) != 0) {
            const run_bytes = run_count * 2;
            if (run_bytes > limit - cursor) return error.BadSfnt;
            for (0..run_count) |index| {
                out[written + index] = std.mem.readInt(i16, data[cursor + index * 2 ..][0..2], .big);
            }
            cursor += run_bytes;
        } else {
            if (run_count > limit - cursor) return error.BadSfnt;
            for (0..run_count) |index| {
                out[written + index] = @as(i8, @bitCast(data[cursor + index]));
            }
            cursor += run_count;
        }
        written += run_count;
    }
    return cursor - offset;
}

const DeltaField = enum { x, y };

fn decodePackedDeltasIntoPointField(data: []const u8, offset: usize, limit: usize, out: []PointDelta, field: DeltaField) Error!usize {
    if (offset > data.len or limit > data.len or offset > limit) return error.BadSfnt;
    var cursor = offset;
    var written: usize = 0;
    while (written < out.len) {
        if (cursor >= limit) return error.BadSfnt;
        const control = data[cursor];
        cursor += 1;
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > out.len - written) return error.BadSfnt;
        if ((control & 0x80) != 0) {
            for (out[written .. written + run_count]) |*delta| setDeltaField(delta, field, 0);
        } else if ((control & 0x40) != 0) {
            const run_bytes = run_count * 2;
            if (run_bytes > limit - cursor) return error.BadSfnt;
            for (0..run_count) |index| {
                setDeltaField(&out[written + index], field, std.mem.readInt(i16, data[cursor + index * 2 ..][0..2], .big));
            }
            cursor += run_bytes;
        } else {
            if (run_count > limit - cursor) return error.BadSfnt;
            for (0..run_count) |index| {
                setDeltaField(&out[written + index], field, @as(i8, @bitCast(data[cursor + index])));
            }
            cursor += run_count;
        }
        written += run_count;
    }
    return cursor - offset;
}

fn setDeltaField(delta: *PointDelta, field: DeltaField, value: i32) void {
    switch (field) {
        .x => delta.x = value,
        .y => delta.y = value,
    }
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

pub fn tuplePayloadInfo(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, all_points_delta_count: ?usize) Error!?TuplePayloadInfo {
    const glyph = (try glyphInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id)) orelse return null;
    const tuple = (try tupleInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph)) orelse return null;
    const table = data[offset .. offset + length];
    var tuple_data_offset = glyph.data_offset + glyph.tuple_data_offset;
    // Walk earlier tuples to find this tuple's serialized payload.
    for (0..tuple_index_in_glyph) |index| {
        const previous = (try tupleInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, index)) orelse return error.BadSfnt;
        tuple_data_offset += previous.variation_data_size;
    }
    const tuple_data_end = tuple_data_offset + tuple.variation_data_size;
    if (tuple_data_end > table.len) return error.BadSfnt;

    var cursor = tuple_data_offset;
    const point_numbers_offset: ?usize = if (tuple.private_point_numbers) cursor else null;
    const points = if (tuple.private_point_numbers) blk: {
        const parsed_points = try packedPointNumbersInfo(table, cursor, tuple_data_end);
        cursor += parsed_points.bytes_consumed;
        break :blk parsed_points;
    } else PointNumbersInfo{ .all_points = true, .count = 0, .max_point = 0, .bytes_consumed = 0 };

    const delta_count = if (points.all_points) (all_points_delta_count orelse return error.BadSfnt) else points.count;
    const x_offset = cursor;
    const x_deltas = try packedDeltasInfo(table, cursor, tuple_data_end, delta_count);
    cursor += x_deltas.bytes_consumed;
    const y_offset = cursor;
    const y_deltas = try packedDeltasInfo(table, cursor, tuple_data_end, delta_count);
    cursor += y_deltas.bytes_consumed;
    if (cursor != tuple_data_end) return error.BadSfnt;

    return .{
        .tuple_data_offset = tuple_data_offset,
        .tuple_data_length = tuple.variation_data_size,
        .point_numbers_offset = point_numbers_offset,
        .point_numbers = points,
        .x_deltas_offset = x_offset,
        .x_deltas = x_deltas,
        .y_deltas_offset = y_offset,
        .y_deltas = y_deltas,
    };
}

pub fn decodeTuplePointDeltas(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, all_points: []const u16, out: []PointDelta) Error!usize {
    const all_points_count: ?usize = if (all_points.len == 0) null else all_points.len;
    const payload = (try tuplePayloadInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, all_points_count)) orelse return 0;
    const count = if (payload.point_numbers.all_points) all_points.len else payload.point_numbers.count;
    if (out.len < count) return error.BadSfnt;
    const table = data[offset .. offset + length];

    if (payload.point_numbers.all_points) {
        for (all_points, 0..) |point, index| out[index].point = point;
    } else {
        try decodePackedPointNumbers(table, payload.point_numbers_offset orelse return error.BadSfnt, payload.x_deltas_offset, out[0..count]);
    }

    _ = try decodePackedDeltasIntoPointField(table, payload.x_deltas_offset, payload.y_deltas_offset, out[0..count], .x);
    _ = try decodePackedDeltasIntoPointField(table, payload.y_deltas_offset, payload.tuple_data_offset + payload.tuple_data_length, out[0..count], .y);
    return count;
}

pub fn decodeTuplePointDeltasForPointCount(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, point_count: usize, out: []PointDelta) Error!usize {
    const payload = (try tuplePayloadInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, point_count)) orelse return 0;
    const count = if (payload.point_numbers.all_points) point_count else payload.point_numbers.count;
    if (out.len < count) return error.BadSfnt;
    const table = data[offset .. offset + length];
    if (payload.point_numbers.all_points) {
        for (0..count) |index| {
            if (index > std.math.maxInt(u16)) return error.BadSfnt;
            out[index].point = @intCast(index);
        }
    } else {
        try decodePackedPointNumbers(table, payload.point_numbers_offset orelse return error.BadSfnt, payload.x_deltas_offset, out[0..count]);
    }
    _ = try decodePackedDeltasIntoPointField(table, payload.x_deltas_offset, payload.y_deltas_offset, out[0..count], .x);
    _ = try decodePackedDeltasIntoPointField(table, payload.y_deltas_offset, payload.tuple_data_offset + payload.tuple_data_length, out[0..count], .y);
    return count;
}

pub fn decodeScaledTuplePointDeltas(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, normalized_coords: []const f32, all_points: []const u16, scratch: []PointDelta, out: []ScaledPointDelta) Error!usize {
    const count = try decodeTuplePointDeltas(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, all_points, scratch);
    if (out.len < count) return error.BadSfnt;
    const scalar = try tupleScalar(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, normalized_coords);
    for (scratch[0..count], 0..) |delta, index| {
        out[index] = .{
            .point = delta.point,
            .x = @as(f32, @floatFromInt(delta.x)) * scalar,
            .y = @as(f32, @floatFromInt(delta.y)) * scalar,
        };
    }
    return count;
}

pub fn decodeScaledTuplePointDeltasForPointCount(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, normalized_coords: []const f32, point_count: usize, scratch: []PointDelta, out: []ScaledPointDelta) Error!usize {
    const count = try decodeTuplePointDeltasForPointCount(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, point_count, scratch);
    if (out.len < count) return error.BadSfnt;
    const scalar = try tupleScalar(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, normalized_coords);
    for (scratch[0..count], 0..) |delta, index| {
        out[index] = .{
            .point = delta.point,
            .x = @as(f32, @floatFromInt(delta.x)) * scalar,
            .y = @as(f32, @floatFromInt(delta.y)) * scalar,
        };
    }
    return count;
}

pub fn accumulateGlyphPointDeltas(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, all_points: []const u16, raw_scratch: []PointDelta, scaled_scratch: []ScaledPointDelta, out: []ScaledPointDelta) Error!usize {
    const glyph = (try glyphInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id)) orelse return 0;
    var out_count: usize = 0;
    if (all_points.len != 0) {
        if (out.len < all_points.len) return error.BadSfnt;
        for (all_points, 0..) |point, index| out[index] = .{ .point = point, .x = 0, .y = 0 };
        out_count = all_points.len;
    }

    for (0..glyph.tuple_count) |tuple_index| {
        const delta_count = try decodeScaledTuplePointDeltas(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index, normalized_coords, all_points, raw_scratch, scaled_scratch);
        for (scaled_scratch[0..delta_count]) |delta| {
            var found: ?usize = null;
            for (out[0..out_count], 0..) |existing, index| {
                if (existing.point == delta.point) {
                    found = index;
                    break;
                }
            }
            const target_index = found orelse blk: {
                if (out_count == out.len) return error.BadSfnt;
                out[out_count] = .{ .point = delta.point, .x = 0, .y = 0 };
                out_count += 1;
                break :blk out_count - 1;
            };
            out[target_index].x += delta.x;
            out[target_index].y += delta.y;
        }
    }
    return out_count;
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

fn decodePackedPointNumbers(data: []const u8, offset: usize, limit: usize, out: []PointDelta) Error!void {
    const points_info = try packedPointNumbersInfo(data, offset, limit);
    if (points_info.all_points or out.len < points_info.count) return error.BadSfnt;
    var cursor = offset;
    const first = data[cursor];
    cursor += 1;
    const point_count: usize = if ((first & 0x80) == 0) first else blk: {
        cursor += 1;
        break :blk points_info.count;
    };
    var remaining = point_count;
    var last_point: usize = 0;
    var out_index: usize = 0;
    while (remaining != 0) {
        const control = data[cursor];
        cursor += 1;
        const run_count = @as(usize, control & 0x7f) + 1;
        const words = (control & 0x80) != 0;
        for (0..run_count) |_| {
            const delta: usize = if (words) blk: {
                const value = readU16(data, cursor);
                cursor += 2;
                break :blk value;
            } else blk: {
                const value = data[cursor];
                cursor += 1;
                break :blk value;
            };
            last_point += delta;
            if (last_point > std.math.maxInt(u16)) return error.BadSfnt;
            out[out_index].point = @intCast(last_point);
            out_index += 1;
        }
        remaining -= run_count;
    }
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

test "gvar packed deltas expose run counts" {
    const parsed = try packedDeltasInfo(&.{ 0x01, 1, 255, 0x80, 0x40, 0, 10 }, 0, 7, 4);
    try std.testing.expectEqual(@as(usize, 4), parsed.count);
    try std.testing.expectEqual(@as(usize, 7), parsed.bytes_consumed);
    try std.testing.expectEqual(@as(usize, 1), parsed.zero_count);
    try std.testing.expectEqual(@as(usize, 2), parsed.byte_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.word_count);
}

test "gvar packed deltas reject truncated runs" {
    try std.testing.expectError(error.BadSfnt, packedDeltasInfo(&.{ 0x41, 0, 1 }, 0, 3, 2));
    try std.testing.expectError(error.BadSfnt, packedDeltasInfo(&.{ 0x02, 1, 2 }, 0, 3, 3));
}

test "gvar packed deltas decode values" {
    var out: [4]i32 = undefined;
    const consumed = try decodePackedDeltas(&.{ 0x01, 1, 255, 0x80, 0x40, 0, 10 }, 0, 7, &out);
    try std.testing.expectEqual(@as(usize, 7), consumed);
    try std.testing.expectEqualSlices(i32, &.{ 1, -1, 0, 10 }, &out);
}

test "gvar packed deltas decode rejects count mismatch" {
    var too_small: [1]i32 = undefined;
    try std.testing.expectError(error.BadSfnt, decodePackedDeltas(&.{ 0x01, 1, 2 }, 0, 3, &too_small));
    var too_large: [3]i32 = undefined;
    try std.testing.expectError(error.BadSfnt, decodePackedDeltas(&.{ 0x01, 1, 2 }, 0, 3, &too_large));
}

test "gvar tuple payload metadata separates point and delta streams" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 9, // offsets: 0, 18.
        0, 1, 0, 10, // GlyphVariationData header.
        0, 7, 0xa0, 0x00, // Tuple header: variationDataSize=7, embedded peak + private points.
        0x40, 0x00, // embedded peak tuple.
        1, 0, 5, // private point numbers: one point, point id 5.
        0, 7, // x delta: +7.
        0, 249, // y delta: -7.
        0, // padding after tuple payload.
    };
    const payload = (try tuplePayloadInfo(&bytes, 0, bytes.len, 1, 1, 0, 0, null)).?;
    try std.testing.expectEqual(@as(usize, 34), payload.tuple_data_offset);
    try std.testing.expectEqual(@as(usize, 7), payload.tuple_data_length);
    try std.testing.expectEqual(@as(?usize, 34), payload.point_numbers_offset);
    try std.testing.expectEqual(@as(usize, 1), payload.point_numbers.count);
    try std.testing.expectEqual(@as(usize, 5), payload.point_numbers.max_point);
    try std.testing.expectEqual(@as(usize, 37), payload.x_deltas_offset);
    try std.testing.expectEqual(@as(usize, 1), payload.x_deltas.byte_count);
    try std.testing.expectEqual(@as(usize, 39), payload.y_deltas_offset);
    try std.testing.expectEqual(@as(usize, 1), payload.y_deltas.byte_count);
}

test "gvar tuple payload decodes point deltas" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 9, // offsets: 0, 18.
        0, 1, 0, 10, // GlyphVariationData header.
        0, 7, 0xa0, 0x00, // Tuple header: variationDataSize=7, embedded peak + private points.
        0x40, 0x00, // embedded peak tuple.
        1, 0, 5, // private point numbers: one point, point id 5.
        0, 7, // x delta: +7.
        0, 249, // y delta: -7.
        0, // padding after tuple payload.
    };
    var out: [1]PointDelta = undefined;
    const count = try decodeTuplePointDeltas(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{}, &out);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u16, 5), out[0].point);
    try std.testing.expectEqual(@as(i32, 7), out[0].x);
    try std.testing.expectEqual(@as(i32, -7), out[0].y);
}

test "gvar tuple payload decodes scaled point deltas" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 9, // offsets: 0, 18.
        0, 1, 0, 10, // GlyphVariationData header.
        0, 7, 0xa0, 0x00, // Tuple header: variationDataSize=7, embedded peak + private points.
        0x40, 0x00, // embedded peak tuple = 1.
        1, 0, 5, // private point numbers: one point, point id 5.
        0, 8, // x delta: +8.
        0, 248, // y delta: -8.
        0, // padding after tuple payload.
    };
    var scratch: [1]PointDelta = undefined;
    var out: [1]ScaledPointDelta = undefined;
    const count = try decodeScaledTuplePointDeltas(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{0.25}, &.{}, &scratch, &out);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u16, 5), out[0].point);
    try std.testing.expectEqual(@as(f32, 2), out[0].x);
    try std.testing.expectEqual(@as(f32, -2), out[0].y);
}

test "gvar accumulates scaled glyph point deltas" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 15, // offsets: 0, 30.
        0, 2, 0, 16, // GlyphVariationData header: two tuples, dataOffset 16.
        0, 7, 0xa0, 0x00, // tuple 0: size 7, embedded peak + private points.
        0x40, 0x00, // peak = 1.
        0, 7, 0xa0, 0x00, // tuple 1: size 7, embedded peak + private points.
        0x40, 0x00, // peak = 1.
        1, 0, 5, 0, 8, 0, 0, // tuple 0 payload: point 5, x +8, y 0.
        1, 0, 5, 0, 4, 0, 2, // tuple 1 payload: point 5, x +4, y +2.
    };
    var raw: [1]PointDelta = undefined;
    var scaled: [1]ScaledPointDelta = undefined;
    var out: [1]ScaledPointDelta = undefined;
    const count = try accumulateGlyphPointDeltas(&bytes, 0, bytes.len, 1, 1, 0, &.{0.5}, &.{}, &raw, &scaled, &out);
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u16, 5), out[0].point);
    try std.testing.expectEqual(@as(f32, 6), out[0].x);
    try std.testing.expectEqual(@as(f32, 1), out[0].y);
}

test "gvar tuple payload decodes contiguous all-point deltas" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 8, // offsets: 0, 16.
        0, 1, 0, 10, // GlyphVariationData header.
        0, 5, 0x80, 0x00, // Tuple header: variationDataSize=5, embedded peak, all points.
        0x40, 0x00, // peak = 1.
        0x02, 1, 2, 3, // x deltas for points 0,1,2.
        0x82, // y deltas zero run for three points.
        0, // padding after tuple payload.
    };
    var raw: [3]PointDelta = undefined;
    var scaled: [3]ScaledPointDelta = undefined;
    const count = try decodeScaledTuplePointDeltasForPointCount(&bytes, 0, bytes.len, 1, 1, 0, 0, &.{0.5}, 3, &raw, &scaled);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u16, 0), scaled[0].point);
    try std.testing.expectEqual(@as(f32, 0.5), scaled[0].x);
    try std.testing.expectEqual(@as(u16, 2), scaled[2].point);
    try std.testing.expectEqual(@as(f32, 1.5), scaled[2].x);
    try std.testing.expectEqual(@as(f32, 0), scaled[2].y);
}
