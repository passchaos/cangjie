const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const TopDictInfo = struct {
    charstrings_offset: ?usize = null,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
    vstore_offset: ?usize = null,
};

pub const IndexInfo = struct {
    offset: usize,
    count: u32,
    off_size: u8,
    data_offset: usize,
    data_length: usize,
};

pub const Info = struct {
    major_version: u8,
    minor_version: u8,
    header_size: u8,
    top_dict_length: u16,
    top_dict_data: []const u8,
    trailing_data: []const u8,
    top_dict: TopDictInfo,
    charstrings_index: ?IndexInfo = null,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    _ = try infoView(data, offset, length);
}

pub fn info(data: []const u8, offset: usize, length: usize) Error!Info {
    return try infoView(data, offset, length);
}

pub fn charStringData(data: []const u8, offset: usize, length: usize, glyph_id: usize) Error!?[]const u8 {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    const index = parsed.charstrings_index orelse return null;
    if (glyph_id >= index.count) return null;
    return try indexObject(table, index, glyph_id);
}

fn infoView(data: []const u8, offset: usize, length: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 5) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const major = table[0];
    const minor = table[1];
    const header_size = table[2];
    if (major != 2 or minor != 0) return error.BadSfnt;
    if (header_size < 5 or header_size > table.len) return error.BadSfnt;
    const top_dict_length = std.mem.readInt(u16, table[3..5], .big);
    if (@as(usize, top_dict_length) > table.len - header_size) return error.BadSfnt;
    const top_start: usize = header_size;
    const top_end = top_start + @as(usize, top_dict_length);
    const top_dict_data = table[top_start..top_end];
    const top_dict = try parseTopDict(top_dict_data, table.len);
    const charstrings_index = if (top_dict.charstrings_offset) |charstrings_offset| try indexInfo(table, charstrings_offset) else null;
    return .{
        .major_version = major,
        .minor_version = minor,
        .header_size = header_size,
        .top_dict_length = top_dict_length,
        .top_dict_data = top_dict_data,
        .trailing_data = table[top_end..],
        .top_dict = top_dict,
        .charstrings_index = charstrings_index,
    };
}

const DictParser = struct {
    data: []const u8,
    offset: usize = 0,
    operands: [48]i32 = undefined,
    operand_count: usize = 0,

    fn next(self: *DictParser) Error!?struct { op: u16, operands: []const i32 } {
        while (self.offset < self.data.len) {
            const b = self.data[self.offset];
            self.offset += 1;
            switch (b) {
                0...21, 24 => {
                    const op: u16 = if (b == 12) blk: {
                        if (self.offset >= self.data.len) return error.BadSfnt;
                        const escaped = self.data[self.offset];
                        self.offset += 1;
                        break :blk @as(u16, 0x0c00) | escaped;
                    } else b;
                    const operands = self.operands[0..self.operand_count];
                    self.operand_count = 0;
                    return .{ .op = op, .operands = operands };
                },
                28 => {
                    if (self.offset + 2 > self.data.len) return error.BadSfnt;
                    try self.push(@as(i16, @bitCast(std.mem.readInt(u16, self.data[self.offset..][0..2], .big))));
                    self.offset += 2;
                },
                29 => {
                    if (self.offset + 4 > self.data.len) return error.BadSfnt;
                    try self.push(std.mem.readInt(i32, self.data[self.offset..][0..4], .big));
                    self.offset += 4;
                },
                30 => return error.BadSfnt, // real numbers are not offsets and are unnecessary for metadata.
                32...246 => try self.push(@as(i32, b) - 139),
                247...250 => {
                    if (self.offset >= self.data.len) return error.BadSfnt;
                    const value = (@as(i32, b) - 247) * 256 + self.data[self.offset] + 108;
                    self.offset += 1;
                    try self.push(value);
                },
                251...254 => {
                    if (self.offset >= self.data.len) return error.BadSfnt;
                    const value = -((@as(i32, b) - 251) * 256 + self.data[self.offset] + 108);
                    self.offset += 1;
                    try self.push(value);
                },
                255 => {
                    if (self.offset + 4 > self.data.len) return error.BadSfnt;
                    const fixed = std.mem.readInt(i32, self.data[self.offset..][0..4], .big);
                    self.offset += 4;
                    try self.push(fixed >> 16);
                },
                else => return error.BadSfnt,
            }
        }
        if (self.operand_count != 0) return error.BadSfnt;
        return null;
    }

    fn push(self: *DictParser, value: i32) Error!void {
        if (self.operand_count == self.operands.len) return error.BadSfnt;
        self.operands[self.operand_count] = value;
        self.operand_count += 1;
    }
};

fn parseTopDict(data: []const u8, table_len: usize) Error!TopDictInfo {
    var parser = DictParser{ .data = data };
    var result = TopDictInfo{};
    while (try parser.next()) |entry| {
        switch (entry.op) {
            17 => result.charstrings_offset = try readOffsetOperand(entry.operands),
            24 => result.vstore_offset = try readOffsetOperand(entry.operands),
            0x0c24 => result.fd_array_offset = try readOffsetOperand(entry.operands),
            0x0c25 => result.fd_select_offset = try readOffsetOperand(entry.operands),
            else => {},
        }
    }
    inline for (.{ result.charstrings_offset, result.fd_array_offset, result.fd_select_offset, result.vstore_offset }) |maybe_offset| {
        if (maybe_offset) |value| {
            if (value >= table_len) return error.BadSfnt;
        }
    }
    return result;
}

fn indexInfo(table: []const u8, offset: usize) Error!IndexInfo {
    if (offset > table.len or table.len - offset < 5) return error.BadSfnt;
    const count = std.mem.readInt(u32, table[offset..][0..4], .big);
    const off_size = table[offset + 4];
    if (off_size < 1 or off_size > 4) return error.BadSfnt;
    const offset_array_len = (@as(usize, count) + 1) * @as(usize, off_size);
    if (offset_array_len > table.len - offset - 5) return error.BadSfnt;
    const offsets_start = offset + 5;
    const data_start = offsets_start + offset_array_len;
    var previous: usize = 1;
    for (0..@as(usize, count) + 1) |index| {
        const value = readSizedOffset(table, offsets_start + index * @as(usize, off_size), off_size);
        if (value < previous) return error.BadSfnt;
        if (value - 1 > table.len - data_start) return error.BadSfnt;
        previous = value;
    }
    return .{
        .offset = offset,
        .count = count,
        .off_size = off_size,
        .data_offset = data_start,
        .data_length = previous - 1,
    };
}

fn indexObject(table: []const u8, index: IndexInfo, object_index: usize) Error![]const u8 {
    if (object_index >= index.count) return error.BadSfnt;
    const offsets_start = index.offset + 5;
    const start = readSizedOffset(table, offsets_start + object_index * @as(usize, index.off_size), index.off_size);
    const end = readSizedOffset(table, offsets_start + (object_index + 1) * @as(usize, index.off_size), index.off_size);
    if (start > end or start == 0) return error.BadSfnt;
    const object_start = index.data_offset + start - 1;
    const object_end = index.data_offset + end - 1;
    if (object_end > table.len) return error.BadSfnt;
    return table[object_start..object_end];
}

fn readSizedOffset(table: []const u8, offset: usize, size: usize) usize {
    var value: usize = 0;
    for (0..size) |index| value = (value << 8) | table[offset + index];
    return value;
}

fn readOffsetOperand(operands: []const i32) Error!usize {
    if (operands.len == 0) return error.BadSfnt;
    const value = operands[operands.len - 1];
    if (value < 0) return error.BadSfnt;
    return @intCast(value);
}

test "CFF2 header exposes top dict and trailing data" {
    const bytes = [_]u8{ 2, 0, 5, 0, 10, 154, 17, 162, 12, 36, 168, 12, 37, 170, 24, 0, 0, 0, 1, 1, 1, 2, 14, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x01, 0x02, 0x03 };
    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(u8, 2), parsed.major_version);
    try std.testing.expectEqual(@as(u8, 5), parsed.header_size);
    try std.testing.expectEqual(@as(u16, 10), parsed.top_dict_length);
    try std.testing.expectEqual(@as(?usize, 15), parsed.top_dict.charstrings_offset);
    try std.testing.expectEqual(@as(?usize, 23), parsed.top_dict.fd_array_offset);
    try std.testing.expectEqual(@as(?usize, 29), parsed.top_dict.fd_select_offset);
    try std.testing.expectEqual(@as(?usize, 31), parsed.top_dict.vstore_offset);
    const charstrings = parsed.charstrings_index.?;
    try std.testing.expectEqual(@as(u32, 1), charstrings.count);
    try std.testing.expectEqual(@as(u8, 1), charstrings.off_size);
    try std.testing.expectEqual(@as(usize, 22), charstrings.data_offset);
    try std.testing.expectEqual(@as(usize, 1), charstrings.data_length);
    try std.testing.expectEqualSlices(u8, &.{14}, (try charStringData(&bytes, 0, bytes.len, 0)).?);
    try std.testing.expect((try charStringData(&bytes, 0, bytes.len, 1)) == null);
}

test "CFF2 rejects bad versions and oversized top dicts" {
    try std.testing.expectError(error.BadSfnt, validate(&.{ 1, 0, 5, 0, 0 }, 0, 5));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 2, 0, 4, 0, 0 }, 0, 5));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 2, 0, 5, 0, 1 }, 0, 5));
}
