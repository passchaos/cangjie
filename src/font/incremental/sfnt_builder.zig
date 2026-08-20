//! Canonical standalone SFNT reconstruction for Incremental Font Transfer.
//!
//! Patches replace/drop tables rather than bytes at stable offsets. Rebuilding
//! one canonical SFNT keeps the directory tag-sorted, table payloads aligned,
//! per-table checksums current, and `head.checkSumAdjustment` authoritative.

const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const Table = struct {
    tag: [4]u8,
    data: []const u8,
};

pub fn build(
    allocator: std.mem.Allocator,
    scaler: u32,
    tables_input: []const Table,
    max_output_size: usize,
) Error![]u8 {
    if (tables_input.len == 0 or tables_input.len > std.math.maxInt(u16)) {
        return error.BadSfnt;
    }
    const tables = try allocator.dupe(Table, tables_input);
    defer allocator.free(tables);
    std.mem.sort(Table, tables, {}, tableLessThan);
    for (tables, 0..) |table, index| {
        try validateTag(table.tag);
        if (index != 0 and std.mem.eql(u8, &tables[index - 1].tag, &table.tag)) {
            return error.BadSfnt;
        }
    }

    const directory_len = std.math.add(
        usize,
        12,
        std.math.mul(usize, tables.len, 16) catch return error.BadSfnt,
    ) catch return error.BadSfnt;
    var total_len = directory_len;
    for (tables) |table| {
        total_len = align4(total_len) catch return error.BadSfnt;
        total_len = std.math.add(usize, total_len, table.data.len) catch
            return error.BadSfnt;
    }
    total_len = align4(total_len) catch return error.BadSfnt;
    if (total_len > max_output_size or total_len > std.math.maxInt(u32)) {
        return error.BadSfnt;
    }

    const output = try allocator.alloc(u8, total_len);
    errdefer allocator.free(output);
    @memset(output, 0);
    writeU32(output, 0, scaler);
    writeU16(output, 4, @intCast(tables.len));
    const search = try searchParameters(tables.len);
    writeU16(output, 6, search.range);
    writeU16(output, 8, search.selector);
    writeU16(output, 10, search.shift);

    var payload_offset = directory_len;
    var head_offset: ?usize = null;
    for (tables, 0..) |table, index| {
        payload_offset = align4(payload_offset) catch return error.BadSfnt;
        const record = 12 + index * 16;
        @memcpy(output[record .. record + 4], &table.tag);
        writeU32(output, record + 4, tableChecksum(table.tag, table.data));
        writeU32(output, record + 8, @intCast(payload_offset));
        writeU32(output, record + 12, @intCast(table.data.len));
        @memcpy(output[payload_offset..][0..table.data.len], table.data);
        if (std.mem.eql(u8, &table.tag, "head")) {
            if (table.data.len < 12) return error.BadSfnt;
            @memset(output[payload_offset + 8 .. payload_offset + 12], 0);
            head_offset = payload_offset;
        }
        payload_offset += table.data.len;
    }
    if (head_offset) |offset| {
        writeU32(output, offset + 8, 0xb1b0afba -% checksum(output));
    }
    return output;
}

fn tableLessThan(_: void, a: Table, b: Table) bool {
    return std.mem.order(u8, &a.tag, &b.tag) == .lt;
}

fn validateTag(tag: [4]u8) Error!void {
    for (tag) |byte| if (byte < 0x20 or byte > 0x7e) return error.BadSfnt;
}

fn tableChecksum(tag: [4]u8, data: []const u8) u32 {
    var sum: u32 = 0;
    var cursor: usize = 0;
    while (cursor < data.len) : (cursor += 4) {
        var word: u32 = 0;
        for (0..4) |byte_index| {
            word <<= 8;
            const index = cursor + byte_index;
            if (index < data.len and
                (!std.mem.eql(u8, &tag, "head") or index < 8 or index >= 12))
            {
                word |= data[index];
            }
        }
        sum +%= word;
    }
    return sum;
}

fn checksum(data: []const u8) u32 {
    var sum: u32 = 0;
    var cursor: usize = 0;
    while (cursor < data.len) : (cursor += 4) {
        sum +%= std.mem.readInt(u32, data[cursor..][0..4], .big);
    }
    return sum;
}

fn align4(value: usize) error{Overflow}!usize {
    return (try std.math.add(usize, value, 3)) & ~@as(usize, 3);
}

const Search = struct { range: u16, selector: u16, shift: u16 };

fn searchParameters(count: usize) Error!Search {
    var power: usize = 1;
    var selector: u16 = 0;
    while (power * 2 <= count) {
        power *= 2;
        selector += 1;
    }
    const range = power * 16;
    const bytes = count * 16;
    if (bytes > std.math.maxInt(u16)) return error.BadSfnt;
    return .{
        .range = @intCast(range),
        .selector = selector,
        .shift = @intCast(bytes - range),
    };
}

fn writeU16(data: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, data[offset..][0..2], value, .big);
}

fn writeU32(data: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, data[offset..][0..4], value, .big);
}

test "SFNT builder sorts tables and refreshes whole-font checksum" {
    var head = [_]u8{0} ** 54;
    const output = try build(
        std.testing.allocator,
        0x00010000,
        &.{
            .{ .tag = "zzzz".*, .data = "z" },
            .{ .tag = "head".*, .data = &head },
            .{ .tag = "aaaa".*, .data = "a" },
        },
        1024,
    );
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("aaaa", output[12..16]);
    try std.testing.expectEqualStrings("head", output[28..32]);
    try std.testing.expectEqual(@as(u32, 0xb1b0afba), checksum(output));
}
