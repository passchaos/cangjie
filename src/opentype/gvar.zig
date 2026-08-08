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

pub const Point = struct {
    x: f32,
    y: f32,
};

pub const PhantomPointDeltas = struct {
    /// Horizontal origin-side phantom delta (`pp1` in FreeType terminology).
    left: Point,
    /// Horizontal advance-side phantom delta (`pp2`).
    right: Point,
    /// Vertical origin-side phantom delta (`pp3`).
    top: Point,
    /// Vertical advance-side phantom delta (`pp4`).
    bottom: Point,

    pub fn horizontalAdvanceDelta(self: PhantomPointDeltas) f32 {
        return self.right.x - self.left.x;
    }

    pub fn verticalAdvanceDelta(self: PhantomPointDeltas) f32 {
        return self.top.y - self.bottom.y;
    }
};

pub const GlyfMetricTarget = union(enum) {
    /// The requested glyph owns its metric phantom points; the payload is the
    /// real simple-point count or compound-component count before the four
    /// phantom points.
    self: usize,
    /// A compound glyph delegates metrics to the last USE_MY_METRICS component.
    component: u16,
};

pub fn glyfVariationPointCount(glyph_data: []const u8) Error!usize {
    if (glyph_data.len == 0) return 0;
    if (glyph_data.len < 10) return error.BadSfnt;
    const contour_count = readI16(glyph_data, 0);
    return if (contour_count >= 0)
        try simpleGlyfPointCount(glyph_data, @intCast(contour_count))
    else
        try compoundGlyfComponentCount(glyph_data);
}

pub fn glyfMetricTarget(glyph_data: []const u8, glyph_count: usize) Error!GlyfMetricTarget {
    if (glyph_data.len == 0) return .{ .self = 0 };
    if (glyph_data.len < 10) return error.BadSfnt;
    const contour_count = readI16(glyph_data, 0);
    if (contour_count >= 0) return .{ .self = try simpleGlyfPointCount(glyph_data, @intCast(contour_count)) };

    const metrics = try compoundGlyfMetricsInfo(glyph_data, glyph_count);
    if (metrics.metrics_glyph) |component| return .{ .component = component };
    return .{ .self = metrics.component_count };
}

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

pub fn interpolateContourDeltas(original: []const Point, has_delta: []const bool, deltas: []Point) Error!void {
    if (original.len != has_delta.len or original.len != deltas.len) return error.BadSfnt;
    if (original.len == 0) return;
    var first_delta: ?usize = null;
    for (has_delta, 0..) |has, index| {
        if (has) {
            first_delta = index;
            break;
        }
    }
    const first = first_delta orelse return;
    var current = first;
    var index = (first + 1) % original.len;
    while (index != first) : (index = (index + 1) % original.len) {
        if (has_delta[index]) {
            interpolateDeltaRun(original, deltas, current, index);
            current = index;
        }
    }
    if (current == first) {
        for (deltas, 0..) |*delta, point_index| {
            if (point_index != first) delta.* = deltas[first];
        }
    } else {
        interpolateDeltaRun(original, deltas, current, first);
    }
}

pub fn interpolateContourScaledDeltas(original: []const Point, has_delta: []const bool, deltas: []ScaledPointDelta) Error!void {
    if (original.len != has_delta.len or original.len != deltas.len) return error.BadSfnt;
    if (original.len == 0) return;
    var first_delta: ?usize = null;
    for (has_delta, 0..) |has, index| {
        if (has) {
            first_delta = index;
            break;
        }
    }
    const first = first_delta orelse return;
    var current = first;
    var index = (first + 1) % original.len;
    while (index != first) : (index = (index + 1) % original.len) {
        if (has_delta[index]) {
            interpolateScaledDeltaRun(original, deltas, current, index);
            current = index;
        }
    }
    if (current == first) {
        for (deltas, 0..) |*delta, point_index| {
            if (point_index != first) {
                delta.x = deltas[first].x;
                delta.y = deltas[first].y;
            }
        }
    } else {
        interpolateScaledDeltaRun(original, deltas, current, first);
    }
}

fn interpolateDeltaRun(original: []const Point, deltas: []Point, left_ref: usize, right_ref: usize) void {
    var index = (left_ref + 1) % original.len;
    while (index != right_ref) : (index = (index + 1) % original.len) {
        deltas[index].x = interpolateAxis(original[index].x, original[left_ref].x, original[right_ref].x, deltas[left_ref].x, deltas[right_ref].x);
        deltas[index].y = interpolateAxis(original[index].y, original[left_ref].y, original[right_ref].y, deltas[left_ref].y, deltas[right_ref].y);
    }
}

fn interpolateScaledDeltaRun(original: []const Point, deltas: []ScaledPointDelta, left_ref: usize, right_ref: usize) void {
    var index = (left_ref + 1) % original.len;
    while (index != right_ref) : (index = (index + 1) % original.len) {
        deltas[index].x = interpolateAxis(original[index].x, original[left_ref].x, original[right_ref].x, deltas[left_ref].x, deltas[right_ref].x);
        deltas[index].y = interpolateAxis(original[index].y, original[left_ref].y, original[right_ref].y, deltas[left_ref].y, deltas[right_ref].y);
    }
}

fn interpolateAxis(coord: f32, ref1_coord: f32, ref2_coord: f32, ref1_delta: f32, ref2_delta: f32) f32 {
    var in1 = ref1_coord;
    var in2 = ref2_coord;
    var d1 = ref1_delta;
    var d2 = ref2_delta;
    if (in1 > in2) {
        std.mem.swap(f32, &in1, &in2);
        std.mem.swap(f32, &d1, &d2);
    }
    if (in1 == in2 and d1 != d2) return 0;
    if (coord <= in1) return d1;
    if (coord >= in2) return d2;
    if (in1 == in2) return d1;
    return d1 + (coord - in1) * ((d2 - d1) / (in2 - in1));
}

pub fn applyPointDeltas(points: []Point, deltas: []const ScaledPointDelta) Error!void {
    for (deltas) |delta| {
        if (delta.point >= points.len) return error.BadSfnt;
        points[delta.point].x += delta.x;
        points[delta.point].y += delta.y;
    }
}

/// Extract the four TrueType phantom-point deltas from an accumulated `gvar`
/// delta set. `point_count` is the number of real simple-glyph points or,
/// for compound glyphs, component records; the phantom points immediately
/// follow at `[point_count, point_count + 4)`.
pub fn phantomPointDeltas(point_count: usize, deltas: []const ScaledPointDelta) Error!PhantomPointDeltas {
    if (point_count > std.math.maxInt(u16) - 3) return error.BadSfnt;
    const left_index: u16 = @intCast(point_count);
    const right_index = left_index + 1;
    const top_index = left_index + 2;
    const bottom_index = left_index + 3;
    var result = PhantomPointDeltas{
        .left = .{ .x = 0, .y = 0 },
        .right = .{ .x = 0, .y = 0 },
        .top = .{ .x = 0, .y = 0 },
        .bottom = .{ .x = 0, .y = 0 },
    };

    for (deltas) |delta| {
        const target = if (delta.point == left_index)
            &result.left
        else if (delta.point == right_index)
            &result.right
        else if (delta.point == top_index)
            &result.top
        else if (delta.point == bottom_index)
            &result.bottom
        else
            continue;
        target.x += delta.x;
        target.y += delta.y;
    }
    return result;
}

pub fn validate(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize) Error!void {
    _ = try info(data, offset, length, expected_glyph_count, expected_axis_count);
}

pub fn glyphInfo(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize) Error!?GlyphInfo {
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    return try glyphInfoFromParsed(data[offset .. offset + length], parsed, glyph_id);
}

fn glyphInfoFromParsed(table: []const u8, parsed: Info, glyph_id: usize) Error!?GlyphInfo {
    if (glyph_id >= parsed.glyph_count) return error.BadSfnt;
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
    return try tuplePayloadInfoFromTuple(table, tuple, tuple_data_offset, all_points_delta_count);
}

fn tuplePayloadInfoFromTuple(table: []const u8, tuple: TupleInfo, tuple_data_offset: usize, all_points_delta_count: ?usize) Error!TuplePayloadInfo {
    if (tuple_data_offset > table.len or tuple.variation_data_size > table.len - tuple_data_offset) return error.BadSfnt;
    const tuple_data_end = tuple_data_offset + tuple.variation_data_size;

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
    const table = data[offset .. offset + length];
    return try decodeTuplePointDeltasForPointCountFromPayload(table, payload, point_count, out);
}

fn decodeTuplePointDeltasForPointCountFromTuple(table: []const u8, tuple: TupleInfo, tuple_data_offset: usize, point_count: usize, out: []PointDelta) Error!usize {
    const payload = try tuplePayloadInfoFromTuple(table, tuple, tuple_data_offset, point_count);
    return try decodeTuplePointDeltasForPointCountFromPayload(table, payload, point_count, out);
}

fn decodeTuplePointDeltasForPointCountFromPayload(table: []const u8, payload: TuplePayloadInfo, point_count: usize, out: []PointDelta) Error!usize {
    const count = if (payload.point_numbers.all_points) point_count else payload.point_numbers.count;
    if (out.len < count) return error.BadSfnt;
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
    const scalar = try tupleScalar(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, normalized_coords);
    return try scalePointDeltas(scratch[0..count], scalar, out);
}

pub fn decodeScaledTuplePointDeltasForPointCount(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, normalized_coords: []const f32, point_count: usize, scratch: []PointDelta, out: []ScaledPointDelta) Error!usize {
    const count = try decodeTuplePointDeltasForPointCount(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, point_count, scratch);
    const scalar = try tupleScalar(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph, normalized_coords);
    return try scalePointDeltas(scratch[0..count], scalar, out);
}

fn scalePointDeltas(deltas: []const PointDelta, scalar: f32, out: []ScaledPointDelta) Error!usize {
    if (out.len < deltas.len) return error.BadSfnt;
    for (deltas, 0..) |delta, index| {
        out[index] = .{
            .point = delta.point,
            .x = @as(f32, @floatFromInt(delta.x)) * scalar,
            .y = @as(f32, @floatFromInt(delta.y)) * scalar,
        };
    }
    return deltas.len;
}

pub fn accumulateGlyphPointDeltas(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, all_points: []const u16, raw_scratch: []PointDelta, scaled_scratch: []ScaledPointDelta, out: []ScaledPointDelta) Error!usize {
    return try accumulateGlyphPointDeltasWithFlags(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, all_points, raw_scratch, scaled_scratch, out, null);
}

pub fn accumulateGlyphPointDeltasForPointCount(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, scaled_scratch: []ScaledPointDelta, out: []ScaledPointDelta) Error!usize {
    _ = scaled_scratch;
    return try accumulateGlyphPointDeltasForPointCountRawScratchWithFlags(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, point_count, raw_scratch, out, null);
}

pub fn accumulateGlyphPointDeltasForPointCountRawScratch(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, out: []ScaledPointDelta) Error!usize {
    return try accumulateGlyphPointDeltasForPointCountRawScratchWithFlags(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, point_count, raw_scratch, out, null);
}

pub fn accumulateGlyphPointDeltasForPointCountRawScratchWithFlags(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, out: []ScaledPointDelta, has_delta: ?[]bool) Error!usize {
    return try accumulateGlyphPointDeltasForPointCountWithFlagsMode(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, point_count, raw_scratch, out, has_delta, .decode_all);
}

/// Accumulate point-count deltas for a table that has already been structurally
/// validated, skipping tuple payload decoding when the tuple scalar is zero.
/// Public defensive readers should use `accumulateGlyphPointDeltasForPointCount`
/// so inactive malformed payloads are still caught at the API boundary; raster
/// hot paths can use this variant after `Font.parse` has validated the table.
pub fn accumulateGlyphPointDeltasForPointCountSkippingInactiveWithFlags(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, scaled_scratch: []ScaledPointDelta, out: []ScaledPointDelta, has_delta: ?[]bool) Error!usize {
    _ = scaled_scratch;
    return try accumulateGlyphPointDeltasForPointCountSkippingInactiveRawScratchWithFlags(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, point_count, raw_scratch, out, has_delta);
}

pub fn accumulateGlyphPointDeltasForPointCountSkippingInactiveRawScratchWithFlags(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, out: []ScaledPointDelta, has_delta: ?[]bool) Error!usize {
    return try accumulateGlyphPointDeltasForPointCountWithFlagsMode(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, point_count, raw_scratch, out, has_delta, .skip_inactive);
}

pub fn accumulateGlyphPointDeltasWithFlags(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, all_points: []const u16, raw_scratch: []PointDelta, scaled_scratch: []ScaledPointDelta, out: []ScaledPointDelta, has_delta: ?[]bool) Error!usize {
    const glyph = (try glyphInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id)) orelse return 0;
    var out_count: usize = 0;
    if (all_points.len != 0) {
        if (out.len < all_points.len) return error.BadSfnt;
        if (has_delta) |flags| {
            if (flags.len < all_points.len) return error.BadSfnt;
            @memset(flags[0..all_points.len], false);
        }
        for (all_points, 0..) |point, index| out[index] = .{ .point = point, .x = 0, .y = 0 };
        out_count = all_points.len;
    }

    for (0..glyph.tuple_count) |tuple_index| {
        const delta_count = try decodeScaledTuplePointDeltas(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index, normalized_coords, all_points, raw_scratch, scaled_scratch);
        for (scaled_scratch[0..delta_count]) |delta| {
            const target_index = accumulationTargetIndex(out, out_count, all_points, delta.point) orelse blk: {
                if (out_count == out.len) return error.BadSfnt;
                out[out_count] = .{ .point = delta.point, .x = 0, .y = 0 };
                out_count += 1;
                break :blk out_count - 1;
            };
            out[target_index].x += delta.x;
            out[target_index].y += delta.y;
            if (has_delta) |flags| {
                if (target_index >= flags.len) return error.BadSfnt;
                flags[target_index] = true;
            }
        }
    }
    return out_count;
}

pub fn accumulateGlyphPointDeltasForPointCountWithFlags(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, scaled_scratch: []ScaledPointDelta, out: []ScaledPointDelta, has_delta: ?[]bool) Error!usize {
    _ = scaled_scratch;
    return try accumulateGlyphPointDeltasForPointCountRawScratchWithFlags(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, normalized_coords, point_count, raw_scratch, out, has_delta);
}

const PointCountAccumulationMode = enum {
    decode_all,
    skip_inactive,
};

const RawDeltaRun = struct {
    raw_count: usize,
    scalar: f32,
};

fn accumulateGlyphPointDeltasForPointCountWithFlagsMode(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, normalized_coords: []const f32, point_count: usize, raw_scratch: []PointDelta, out: []ScaledPointDelta, has_delta: ?[]bool, mode: PointCountAccumulationMode) Error!usize {
    if (point_count > @as(usize, std.math.maxInt(u16)) + 1) return error.BadSfnt;
    if (has_delta) |flags| {
        if (flags.len < point_count) return error.BadSfnt;
        @memset(flags[0..point_count], false);
    }
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    const table = data[offset .. offset + length];
    const glyph = (try glyphInfoFromParsed(table, parsed, glyph_id)) orelse return 0;
    if (out.len < point_count) return error.BadSfnt;

    var initialized_out = false;
    if (mode == .decode_all) {
        initializeDensePointDeltas(out, point_count);
        initialized_out = true;
    }

    var header_offset = glyph.data_offset + 4;
    const tuple_data_base = glyph.data_offset + glyph.tuple_data_offset;
    var tuple_data_bytes: usize = 0;
    for (0..glyph.tuple_count) |tuple_index| {
        const tuple = try readTupleInfo(table, parsed, glyph, header_offset, tuple_index, tuple_data_bytes);
        if (tuple_data_bytes > std.math.maxInt(usize) - tuple_data_base) return error.BadSfnt;
        const tuple_data_offset = tuple_data_base + tuple_data_bytes;
        const delta_count = switch (mode) {
            .decode_all => blk: {
                const raw_count = try decodeTuplePointDeltasForPointCountFromTuple(table, tuple, tuple_data_offset, point_count, raw_scratch);
                const scalar = try tupleScalarFromTuple(table, parsed, tuple, normalized_coords);
                break :blk RawDeltaRun{ .raw_count = raw_count, .scalar = scalar };
            },
            .skip_inactive => blk: {
                const scalar = try tupleScalarFromTuple(table, parsed, tuple, normalized_coords);
                if (scalar == 0) break :blk RawDeltaRun{ .raw_count = 0, .scalar = scalar };
                if (!initialized_out) {
                    initializeDensePointDeltas(out, point_count);
                    initialized_out = true;
                }
                const raw_count = try decodeTuplePointDeltasForPointCountFromTuple(table, tuple, tuple_data_offset, point_count, raw_scratch);
                break :blk RawDeltaRun{ .raw_count = raw_count, .scalar = scalar };
            },
        };
        try accumulateRawPointDeltas(out, point_count, raw_scratch[0..delta_count.raw_count], delta_count.scalar, has_delta);
        header_offset += tuple.header_size;
        tuple_data_bytes += tuple.variation_data_size;
    }
    return if (initialized_out) point_count else 0;
}

fn accumulateRawPointDeltas(out: []ScaledPointDelta, point_count: usize, deltas: []const PointDelta, scalar: f32, has_delta: ?[]bool) Error!void {
    for (deltas) |delta| {
        const target_index: usize = delta.point;
        if (target_index >= point_count) return error.BadSfnt;
        out[target_index].x += @as(f32, @floatFromInt(delta.x)) * scalar;
        out[target_index].y += @as(f32, @floatFromInt(delta.y)) * scalar;
        if (has_delta) |flags| flags[target_index] = true;
    }
}

fn initializeDensePointDeltas(out: []ScaledPointDelta, point_count: usize) void {
    for (0..point_count) |point| {
        out[point] = .{ .point = @intCast(point), .x = 0, .y = 0 };
    }
}

fn accumulationTargetIndex(out: []const ScaledPointDelta, out_count: usize, all_points: []const u16, point: u16) ?usize {
    // The hot outline-at-coords path asks for a dense all-points vector
    // containing 0...target_count-1.  In that common case the gvar point number
    // is already the output index, avoiding an O(points) scan for every tuple
    // delta while preserving the generic sparse/allocation-free decoder API.
    if (all_points.len != 0) {
        const candidate: usize = point;
        if (candidate < all_points.len and all_points[candidate] == point) return candidate;
    }
    for (out[0..out_count], 0..) |existing, index| {
        if (existing.point == point) return index;
    }
    return null;
}

pub fn tupleScalar(data: []const u8, offset: usize, length: usize, expected_glyph_count: usize, expected_axis_count: usize, glyph_id: usize, tuple_index_in_glyph: usize, normalized_coords: []const f32) Error!f32 {
    const parsed = try info(data, offset, length, expected_glyph_count, expected_axis_count);
    const tuple = (try tupleInfo(data, offset, length, expected_glyph_count, expected_axis_count, glyph_id, tuple_index_in_glyph)) orelse return error.BadSfnt;
    const table = data[offset .. offset + length];
    return try tupleScalarFromTuple(table, parsed, tuple, normalized_coords);
}

fn tupleScalarFromTuple(table: []const u8, parsed: Info, tuple: TupleInfo, normalized_coords: []const f32) Error!f32 {
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

fn readI16(data: []const u8, offset: usize) i16 {
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) usize {
    return @intCast(std.mem.readInt(u32, data[offset..][0..4], .big));
}

fn simpleGlyfPointCount(glyph_data: []const u8, contour_count: u16) Error!usize {
    if (contour_count == 0) return 0;
    const last_end_offset = 10 + (@as(usize, contour_count) - 1) * 2;
    if (last_end_offset + 2 > glyph_data.len) return error.BadSfnt;
    return @as(usize, readU16(glyph_data, last_end_offset)) + 1;
}

fn compoundGlyfComponentCount(glyph_data: []const u8) Error!usize {
    return (try compoundGlyfMetricsInfo(glyph_data, null)).component_count;
}

const CompoundGlyfMetricsInfo = struct {
    component_count: usize,
    metrics_glyph: ?u16,
};

fn compoundGlyfMetricsInfo(glyph_data: []const u8, glyph_count: ?usize) Error!CompoundGlyfMetricsInfo {
    var offset: usize = 10; // numberOfContours + x/y bounds.
    var component_count: usize = 0;
    var metrics_glyph: ?u16 = null;
    while (true) {
        if (offset + 4 > glyph_data.len) return error.BadSfnt;
        const flags = readU16(glyph_data, offset);
        const component_glyph = readU16(glyph_data, offset + 2);
        if (glyph_count) |count| {
            if (component_glyph >= count) return error.BadSfnt;
        }
        offset += 4;
        component_count += 1;
        if ((flags & 0x0200) != 0) metrics_glyph = component_glyph;

        const argument_bytes: usize = if ((flags & 0x0001) != 0) 4 else 2;
        if (argument_bytes > glyph_data.len - offset) return error.BadSfnt;
        offset += argument_bytes;

        const has_scale = (flags & 0x0008) != 0;
        const has_xy_scale = (flags & 0x0040) != 0;
        const has_two_by_two = (flags & 0x0080) != 0;
        const scale_bytes: usize = if (has_scale) 2 else if (has_xy_scale) 4 else if (has_two_by_two) 8 else 0;
        if (scale_bytes > glyph_data.len - offset) return error.BadSfnt;
        offset += scale_bytes;

        if ((flags & 0x0020) == 0) return .{ .component_count = component_count, .metrics_glyph = metrics_glyph };
    }
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

test "glyf metric targets count phantom point starts" {
    var simple: [16]u8 = .{0} ** 16;
    std.mem.writeInt(i16, simple[0..2], 1, .big);
    std.mem.writeInt(u16, simple[10..12], 2, .big);
    try std.testing.expectEqual(@as(usize, 3), try glyfVariationPointCount(&simple));
    try std.testing.expectEqual(GlyfMetricTarget{ .self = 3 }, try glyfMetricTarget(&simple, 3));

    var compound: [22]u8 = .{0} ** 22;
    std.mem.writeInt(i16, compound[0..2], -1, .big);
    // First component has USE_MY_METRICS, but the second flagged component wins
    // per FreeType/fontations and the OpenType gvar composite-glyph rules.
    std.mem.writeInt(u16, compound[10..12], 0x0020 | 0x0200 | 0x0002, .big);
    std.mem.writeInt(u16, compound[12..14], 1, .big);
    std.mem.writeInt(u16, compound[16..18], 0x0200 | 0x0002, .big);
    std.mem.writeInt(u16, compound[18..20], 2, .big);
    try std.testing.expectEqual(@as(usize, 2), try glyfVariationPointCount(&compound));
    try std.testing.expectEqual(GlyfMetricTarget{ .component = 2 }, try glyfMetricTarget(&compound, 3));
    try std.testing.expectError(error.BadSfnt, glyfMetricTarget(&compound, 2));
}

test "phantom point deltas derive metric deltas" {
    const deltas = [_]ScaledPointDelta{
        .{ .point = 0, .x = 99, .y = 99 },
        .{ .point = 3, .x = 1, .y = 0 },
        .{ .point = 4, .x = 10, .y = 0 },
        .{ .point = 5, .x = 0, .y = 4 },
        .{ .point = 6, .x = 0, .y = -2 },
    };
    const phantom = try phantomPointDeltas(3, &deltas);
    try std.testing.expectEqual(@as(f32, 1), phantom.left.x);
    try std.testing.expectEqual(@as(f32, 10), phantom.right.x);
    try std.testing.expectEqual(@as(f32, 9), phantom.horizontalAdvanceDelta());
    try std.testing.expectEqual(@as(f32, 6), phantom.verticalAdvanceDelta());
}

test "gvar accumulation target index uses dense point ids directly" {
    const out = [_]ScaledPointDelta{
        .{ .point = 0, .x = 0, .y = 0 },
        .{ .point = 1, .x = 0, .y = 0 },
        .{ .point = 2, .x = 0, .y = 0 },
    };
    try std.testing.expectEqual(@as(?usize, 2), accumulationTargetIndex(&out, out.len, &.{ 0, 1, 2 }, 2));
    // Non-dense caller-provided point lists are still supported by falling back
    // to the generic search over accumulated outputs.
    try std.testing.expectEqual(@as(?usize, 1), accumulationTargetIndex(&out, out.len, &.{ 2, 0, 1 }, 1));
    try std.testing.expect(accumulationTargetIndex(&out, out.len, &.{ 0, 1, 2 }, 9) == null);
}

test "gvar point-count accumulation keeps dense outputs and flags" {
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
    var out: [3]ScaledPointDelta = undefined;
    var has_delta = [_]bool{ false, false, false };
    const count = try accumulateGlyphPointDeltasForPointCountWithFlags(&bytes, 0, bytes.len, 1, 1, 0, &.{0.5}, 3, &raw, &scaled, &out, &has_delta);
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqual(@as(u16, 0), out[0].point);
    try std.testing.expectEqual(@as(f32, 0.5), out[0].x);
    try std.testing.expectEqual(@as(u16, 2), out[2].point);
    try std.testing.expectEqual(@as(f32, 1.5), out[2].x);
    try std.testing.expectEqualSlices(bool, &.{ true, true, true }, &has_delta);
}

test "gvar point-count accumulation clears flags for absent glyph data" {
    const bytes = [_]u8{
        0, 1, 0, 0, // version.
        0, 1, // axisCount.
        0, 0, // sharedTupleCount.
        0, 0, 0, 0, // sharedTupleOffset.
        0, 1, // glyphCount.
        0, 0, // short offsets.
        0, 0, 0, 24, // glyphVariationDataArrayOffset.
        0, 0, 0, 0, // offsets: 0, 0.
    };
    var raw: [3]PointDelta = undefined;
    var scaled: [3]ScaledPointDelta = undefined;
    var out: [3]ScaledPointDelta = undefined;
    var has_delta = [_]bool{ true, true, true };
    const count = try accumulateGlyphPointDeltasForPointCountWithFlags(&bytes, 0, bytes.len, 1, 1, 0, &.{0.5}, 3, &raw, &scaled, &out, &has_delta);
    try std.testing.expectEqual(@as(usize, 0), count);
    try std.testing.expectEqualSlices(bool, &.{ false, false, false }, &has_delta);
}

test "gvar point-count accumulation can skip inactive tuple payloads" {
    var bytes = [_]u8{
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
        0x40, 0x00, // peak = 1; normalized coord 0 makes this tuple inactive.
        0x02, 1, 2, 3, // x deltas for points 0,1,2.
        0x82, // y deltas zero run for three points.
        0, // padding after tuple payload.
    };
    // Corrupt the X-delta run. Defensive accumulation decodes inactive payloads
    // and catches the malformed run; parsed-font raster paths may skip payload
    // decoding once tupleScalar() proves the tuple cannot contribute.
    bytes[34] = 0x03;

    var raw: [3]PointDelta = undefined;
    var scaled: [3]ScaledPointDelta = undefined;
    var out: [3]ScaledPointDelta = undefined;
    var has_delta = [_]bool{ true, true, true };
    try std.testing.expectError(error.BadSfnt, accumulateGlyphPointDeltasForPointCountWithFlags(&bytes, 0, bytes.len, 1, 1, 0, &.{0.0}, 3, &raw, &scaled, &out, &has_delta));

    const count = try accumulateGlyphPointDeltasForPointCountSkippingInactiveWithFlags(&bytes, 0, bytes.len, 1, 1, 0, &.{0.0}, 3, &raw, &scaled, &out, &has_delta);
    try std.testing.expectEqual(@as(usize, 0), count);
    try std.testing.expectEqualSlices(bool, &.{ false, false, false }, &has_delta);
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

test "gvar applies accumulated deltas to points" {
    var points = [_]Point{
        .{ .x = 10, .y = 20 },
        .{ .x = 30, .y = 40 },
        .{ .x = 50, .y = 60 },
    };
    try applyPointDeltas(&points, &.{
        .{ .point = 0, .x = 1.5, .y = -2.5 },
        .{ .point = 2, .x = -10, .y = 5 },
    });
    try std.testing.expectEqual(@as(f32, 11.5), points[0].x);
    try std.testing.expectEqual(@as(f32, 17.5), points[0].y);
    try std.testing.expectEqual(@as(f32, 40), points[2].x);
    try std.testing.expectEqual(@as(f32, 65), points[2].y);
    try std.testing.expectError(error.BadSfnt, applyPointDeltas(&points, &.{.{ .point = 3, .x = 1, .y = 1 }}));
}

test "gvar IUP shifts contour with one explicit delta" {
    const original = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 20, .y = 0 } };
    const has = [_]bool{ false, true, false };
    var deltas = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 5, .y = -2 }, .{ .x = 0, .y = 0 } };
    try interpolateContourDeltas(&original, &has, &deltas);
    try std.testing.expectEqual(@as(f32, 5), deltas[0].x);
    try std.testing.expectEqual(@as(f32, -2), deltas[2].y);
}

test "gvar IUP interpolates between explicit deltas" {
    const original = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 5, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 15, .y = 0 } };
    const has = [_]bool{ true, false, true, false };
    var deltas = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 0, .y = 0 } };
    try interpolateContourDeltas(&original, &has, &deltas);
    try std.testing.expectEqual(@as(f32, 5), deltas[1].x);
    try std.testing.expectEqual(@as(f32, 10), deltas[3].x);
}

test "gvar IUP interpolates scaled dense deltas in place" {
    const original = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 5, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 15, .y = 0 } };
    const has = [_]bool{ true, false, true, false };
    var deltas = [_]ScaledPointDelta{
        .{ .point = 0, .x = 0, .y = 0 },
        .{ .point = 1, .x = 0, .y = 0 },
        .{ .point = 2, .x = 10, .y = 0 },
        .{ .point = 3, .x = 0, .y = 0 },
    };
    try interpolateContourScaledDeltas(&original, &has, &deltas);
    try std.testing.expectEqual(@as(f32, 5), deltas[1].x);
    try std.testing.expectEqual(@as(f32, 10), deltas[3].x);
    try std.testing.expectEqual(@as(u16, 1), deltas[1].point);
    try std.testing.expectEqual(@as(u16, 3), deltas[3].point);
}
