const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{
    BadSfnt,
} || std.mem.Allocator.Error || error{EndOfStream};

pub const TupleInfo = struct {
    variation_data_size: u16,
    tuple_index: u16,
    peak_coordinates: []i16,
    intermediate_start_coordinates: []i16,
    intermediate_end_coordinates: []i16,

    pub fn hasPrivatePointNumbers(self: TupleInfo) bool {
        return (self.tuple_index & private_point_numbers_flag) != 0;
    }

    pub fn hasIntermediateRegion(self: TupleInfo) bool {
        return (self.tuple_index & intermediate_region_flag) != 0;
    }
};

pub const Info = struct {
    version: u32,
    tuple_count: u16,
    uses_shared_point_numbers: bool,
    data_offset: usize,
    tuples: []TupleInfo,
};

const Header = struct {
    version: u32,
    tuple_count: usize,
    uses_shared_point_numbers: bool,
    data_offset: usize,
    headers_end: usize,
};

const PointSelection = union(enum) {
    all_points,
    explicit: struct { count: usize, max_point: usize },
};

const TupleHeader = struct {
    variation_data_size: usize,
    tuple_index: u16,
    header_offset: usize,
    header_size: usize,

    fn hasPrivatePointNumbers(self: TupleHeader) bool {
        return (self.tuple_index & private_point_numbers_flag) != 0;
    }
};

const shared_point_numbers_flag: u16 = 0x8000;
const embedded_peak_tuple_flag: u16 = 0x8000;
const intermediate_region_flag: u16 = 0x4000;
const private_point_numbers_flag: u16 = 0x2000;
const reserved_tuple_index_flag: u16 = 0x1000;
const tuple_count_mask: u16 = 0x0fff;

pub fn validate(data: []const u8, offset: usize, length: usize, axis_count: usize, cvt_value_count: usize) Error!void {
    const h = try header(data, offset, length, axis_count);
    var headers_cursor: usize = 8;
    var data_cursor = h.data_offset;

    const shared_points: ?PointSelection = if (h.uses_shared_point_numbers) blk: {
        const points = try validatePackedPointNumbers(data, offset, length, &data_cursor, cvt_value_count);
        break :blk points;
    } else null;

    for (0..h.tuple_count) |_| {
        const tuple = try readTupleHeader(data, offset, length, headers_cursor, axis_count);
        headers_cursor += tuple.header_size;
        if (headers_cursor > h.data_offset) return error.BadSfnt;

        if (tuple.variation_data_size > length - data_cursor) return error.BadSfnt;
        const tuple_end = data_cursor + tuple.variation_data_size;
        var payload_cursor = data_cursor;
        const points = if (tuple.hasPrivatePointNumbers())
            try validatePackedPointNumbers(data, offset, length, &payload_cursor, cvt_value_count)
        else
            shared_points orelse PointSelection.all_points;
        const delta_count = deltaCount(points, cvt_value_count);
        try validatePackedDeltas(data, offset, &payload_cursor, tuple_end, delta_count);
        if (payload_cursor != tuple_end) return error.BadSfnt;
        data_cursor = tuple_end;
    }
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, axis_count: usize) Error!Info {
    const h = try header(data, offset, length, axis_count);
    const tuples = try allocator.alloc(TupleInfo, h.tuple_count);
    var initialized: usize = 0;
    errdefer {
        freeTupleContents(allocator, tuples[0..initialized]);
        allocator.free(tuples);
    }

    var cursor: usize = 8;
    for (tuples) |*tuple| {
        tuple.* = try tupleInfoAt(allocator, data, offset, length, cursor, axis_count);
        initialized += 1;
        const tuple_header = try readTupleHeader(data, offset, length, cursor, axis_count);
        cursor += tuple_header.header_size;
    }

    return .{
        .version = h.version,
        .tuple_count = @intCast(h.tuple_count),
        .uses_shared_point_numbers = h.uses_shared_point_numbers,
        .data_offset = h.data_offset,
        .tuples = tuples,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeTupleContents(allocator, value.tuples);
    allocator.free(value.tuples);
}

fn freeTupleContents(allocator: std.mem.Allocator, tuples: []TupleInfo) void {
    for (tuples) |tuple| {
        allocator.free(tuple.peak_coordinates);
        allocator.free(tuple.intermediate_start_coordinates);
        allocator.free(tuple.intermediate_end_coordinates);
    }
}

fn header(data: []const u8, offset: usize, length: usize, axis_count: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 8) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const raw_tuple_count = try bin.readU16At(data, offset + 4);
    if ((raw_tuple_count & 0x7000) != 0) return error.BadSfnt;
    const tuple_count: usize = @intCast(raw_tuple_count & tuple_count_mask);
    if (tuple_count == 0) return error.BadSfnt;
    const data_offset: usize = @intCast(try bin.readU16At(data, offset + 6));
    if (data_offset < 8 or data_offset > length) return error.BadSfnt;

    var cursor: usize = 8;
    for (0..tuple_count) |_| {
        const tuple = try readTupleHeader(data, offset, length, cursor, axis_count);
        cursor += tuple.header_size;
        if (cursor > data_offset) return error.BadSfnt;
    }
    return .{
        .version = (@as(u32, major) << 16) | @as(u32, minor),
        .tuple_count = tuple_count,
        .uses_shared_point_numbers = (raw_tuple_count & shared_point_numbers_flag) != 0,
        .data_offset = data_offset,
        .headers_end = cursor,
    };
}

fn readTupleHeader(data: []const u8, table_offset: usize, table_length: usize, relative_offset: usize, axis_count: usize) Error!TupleHeader {
    if (relative_offset > table_length or table_length - relative_offset < 4) return error.BadSfnt;
    const start = table_offset + relative_offset;
    const variation_data_size: usize = @intCast(try bin.readU16At(data, start));
    const tuple_index = try bin.readU16At(data, start + 2);
    if ((tuple_index & reserved_tuple_index_flag) != 0) return error.BadSfnt;

    // Unlike gvar, cvar has no shared tuple records. OpenType therefore
    // requires every cvar TupleVariationHeader to carry an embedded peak tuple.
    if ((tuple_index & embedded_peak_tuple_flag) == 0) return error.BadSfnt;

    var header_size: usize = 4 + axis_count * 2;
    if ((tuple_index & intermediate_region_flag) != 0) header_size += axis_count * 4;
    if (header_size > table_length - relative_offset) return error.BadSfnt;
    try validateTupleCoordinates(data, table_offset + relative_offset, axis_count, tuple_index);
    return .{
        .variation_data_size = variation_data_size,
        .tuple_index = tuple_index,
        .header_offset = relative_offset,
        .header_size = header_size,
    };
}

fn tupleInfoAt(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, relative_offset: usize, axis_count: usize) Error!TupleInfo {
    const tuple = try readTupleHeader(data, table_offset, table_length, relative_offset, axis_count);
    const peak = try readCoordinates(allocator, data, table_offset + relative_offset + 4, axis_count);
    errdefer allocator.free(peak);
    const start_offset = table_offset + relative_offset + 4 + axis_count * 2;
    const has_intermediate = (tuple.tuple_index & intermediate_region_flag) != 0;
    const intermediate_start = if (has_intermediate) try readCoordinates(allocator, data, start_offset, axis_count) else try allocator.alloc(i16, 0);
    errdefer allocator.free(intermediate_start);
    const intermediate_end = if (has_intermediate) try readCoordinates(allocator, data, start_offset + axis_count * 2, axis_count) else try allocator.alloc(i16, 0);
    errdefer allocator.free(intermediate_end);
    return .{
        .variation_data_size = @intCast(tuple.variation_data_size),
        .tuple_index = tuple.tuple_index,
        .peak_coordinates = peak,
        .intermediate_start_coordinates = intermediate_start,
        .intermediate_end_coordinates = intermediate_end,
    };
}

fn readCoordinates(allocator: std.mem.Allocator, data: []const u8, offset: usize, axis_count: usize) Error![]i16 {
    const values = try allocator.alloc(i16, axis_count);
    errdefer allocator.free(values);
    for (values, 0..) |*value, index| value.* = try readNormalizedCoordinate(data, offset + index * 2);
    return values;
}

fn validateTupleCoordinates(data: []const u8, tuple_start: usize, axis_count: usize, tuple_index: u16) Error!void {
    const peak_offset = tuple_start + 4;
    for (0..axis_count) |axis_index| {
        _ = try readNormalizedCoordinate(data, peak_offset + axis_index * 2);
    }

    if ((tuple_index & intermediate_region_flag) == 0) return;
    const start_offset = peak_offset + axis_count * 2;
    const end_offset = start_offset + axis_count * 2;
    for (0..axis_count) |axis_index| {
        const start = try readNormalizedCoordinate(data, start_offset + axis_index * 2);
        const peak = try readNormalizedCoordinate(data, peak_offset + axis_index * 2);
        const end = try readNormalizedCoordinate(data, end_offset + axis_index * 2);
        if (start > peak or peak > end) return error.BadSfnt;
        if (start < 0 and end > 0 and peak != 0) return error.BadSfnt;
    }
}

fn readNormalizedCoordinate(data: []const u8, offset: usize) Error!i16 {
    const value = bin.readI16At(data, offset) catch return error.BadSfnt;
    if (value < -0x4000 or value > 0x4000) return error.BadSfnt;
    return value;
}

fn validatePackedPointNumbers(data: []const u8, table_offset: usize, table_length: usize, cursor: *usize, cvt_value_count: usize) Error!PointSelection {
    if (cursor.* >= table_length) return error.BadSfnt;
    const first = data[table_offset + cursor.*];
    cursor.* += 1;
    if (first == 0) return .all_points;

    const point_count: usize = if ((first & 0x80) == 0) first else blk: {
        if (cursor.* >= table_length) return error.BadSfnt;
        const second = data[table_offset + cursor.*];
        cursor.* += 1;
        break :blk (@as(usize, first & 0x7f) << 8) | second;
    };

    var remaining = point_count;
    var last_point: usize = 0;
    var saw_point = false;
    while (remaining != 0) {
        if (cursor.* >= table_length) return error.BadSfnt;
        const control = data[table_offset + cursor.*];
        cursor.* += 1;
        const run_count = @as(usize, control & 0x7f) + 1;
        if (run_count > remaining) return error.BadSfnt;
        const words = (control & 0x80) != 0;
        for (0..run_count) |_| {
            const delta: usize = if (words) blk: {
                if (cursor.* > table_length or 2 > table_length - cursor.*) return error.BadSfnt;
                const value = try bin.readU16At(data, table_offset + cursor.*);
                cursor.* += 2;
                break :blk value;
            } else blk: {
                if (cursor.* >= table_length) return error.BadSfnt;
                const value = data[table_offset + cursor.*];
                cursor.* += 1;
                break :blk value;
            };
            if (delta > std.math.maxInt(usize) - last_point) return error.BadSfnt;
            last_point += delta;
            saw_point = true;
        }
        remaining -= run_count;
    }

    if (saw_point and last_point >= cvt_value_count) return error.BadSfnt;
    return .{ .explicit = .{ .count = point_count, .max_point = if (saw_point) last_point else 0 } };
}

fn deltaCount(points: PointSelection, cvt_value_count: usize) usize {
    return switch (points) {
        .all_points => cvt_value_count,
        .explicit => |explicit| explicit.count,
    };
}

fn validatePackedDeltas(data: []const u8, table_offset: usize, cursor: *usize, limit: usize, delta_count: usize) Error!void {
    var remaining = delta_count;
    while (remaining != 0) {
        if (cursor.* >= limit) return error.BadSfnt;
        const control = data[table_offset + cursor.*];
        cursor.* += 1;
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > remaining) return error.BadSfnt;

        const run_bytes: usize = if ((control & 0x80) != 0)
            0
        else if ((control & 0x40) != 0)
            run_count * 2
        else
            run_count;
        if (run_bytes > limit - cursor.*) return error.BadSfnt;
        cursor.* += run_bytes;
        remaining -= run_count;
    }
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

test "cvar validates embedded tuple headers and packed CVT deltas" {
    var bytes: [19]u8 = .{0} ** 19;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 14);
    writeU16Test(&bytes, 8, 5);
    writeU16Test(&bytes, 10, embedded_peak_tuple_flag);
    writeI16Test(&bytes, 12, 0x4000);
    bytes[14] = 3;
    bytes[15] = 1;
    bytes[16] = 2;
    bytes[17] = 3;
    bytes[18] = 4;

    try validate(&bytes, 0, bytes.len, 1, 4);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 1);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u16, 1), parsed.tuple_count);
    try std.testing.expectEqual(@as(usize, 14), parsed.data_offset);
    try std.testing.expectEqual(@as(usize, 1), parsed.tuples[0].peak_coordinates.len);
    try std.testing.expectEqual(@as(i16, 0x4000), parsed.tuples[0].peak_coordinates[0]);

    var missing_peak = bytes;
    writeU16Test(&missing_peak, 10, 0);
    try std.testing.expectError(error.BadSfnt, validate(&missing_peak, 0, missing_peak.len, 1, 4));
}

test "cvar rejects explicit CVT point indexes outside cvt table" {
    var bytes: [19]u8 = .{0} ** 19;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 14);
    writeU16Test(&bytes, 8, 5);
    writeU16Test(&bytes, 10, embedded_peak_tuple_flag | private_point_numbers_flag);
    writeI16Test(&bytes, 12, 0x4000);
    bytes[14] = 1; // one explicit point.
    bytes[15] = 0; // one run of byte deltas.
    bytes[16] = 4; // point index 4 is outside a four-entry cvt table.
    bytes[17] = 0; // one delta byte.
    bytes[18] = 7;

    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 1, 4));
}
