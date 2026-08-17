//! Repository-owned container fixture builders.

const std = @import("std");
const binary = @import("binary.zig");

const TestSfntTable = struct {
    tag: [4]u8,
    checksum: u32,
    length: u32,
    data: []const u8,
};

pub fn buildWoff1(
    allocator: std.mem.Allocator,
    sfnt: []const u8,
    compress_tables: bool,
) ![]u8 {
    if (sfnt.len < 12) return error.TestUnexpectedResult;
    const flavor = binary.readU32(sfnt, 0);
    const table_count = binary.readU16(sfnt, 4);
    const directory_len = @as(usize, table_count) * 16;
    if (directory_len > sfnt.len - 12) return error.TestUnexpectedResult;

    const tables = try allocator.alloc(TestSfntTable, table_count);
    defer allocator.free(tables);
    for (tables, 0..) |*table, index| {
        const record = 12 + index * 16;
        const offset: usize = binary.readU32(sfnt, record + 8);
        const len: usize = binary.readU32(sfnt, record + 12);
        if (offset > sfnt.len or len > sfnt.len - offset) {
            return error.TestUnexpectedResult;
        }
        table.* = .{
            .tag = sfnt[record..][0..4].*,
            .checksum = binary.readU32(sfnt, record + 4),
            .length = @intCast(len),
            .data = sfnt[offset..][0..len],
        };
    }

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.splatByteAll(0, 44 + @as(usize, table_count) * 20);
    var compressed_any = false;
    for (tables, 0..) |table, index| {
        var payload = table.data;
        var compressed_owned: ?[]u8 = null;
        if (compress_tables) {
            const compressed = try zlibCompressForTest(allocator, table.data);
            if (compressed.len < table.data.len) {
                compressed_owned = compressed;
                payload = compressed;
                compressed_any = true;
            } else {
                allocator.free(compressed);
            }
        }
        defer if (compressed_owned) |owned| allocator.free(owned);

        while ((out.writer.end & 3) != 0) try out.writer.writeByte(0);
        const payload_offset = out.writer.end;
        try out.writer.writeAll(payload);
        while ((out.writer.end & 3) != 0) try out.writer.writeByte(0);

        const entry = 44 + index * 20;
        out.writer.buffer[entry..][0..4].* = table.tag;
        binary.writeU32(out.writer.buffer, entry + 4, @intCast(payload_offset));
        binary.writeU32(out.writer.buffer, entry + 8, @intCast(payload.len));
        binary.writeU32(out.writer.buffer, entry + 12, table.length);
        binary.writeU32(out.writer.buffer, entry + 16, table.checksum);
    }
    if (compress_tables and !compressed_any) return error.TestUnexpectedResult;

    const bytes = std.Io.Writer.buffered(&out.writer);
    binary.writeU32(bytes, 0, 0x774f4646);
    binary.writeU32(bytes, 4, flavor);
    binary.writeU32(bytes, 8, @intCast(bytes.len));
    binary.writeU16(bytes, 12, table_count);
    binary.writeU16(bytes, 14, 0);
    binary.writeU32(bytes, 16, @intCast(try sfntSizeForTest(tables)));
    binary.writeU16(bytes, 20, 1);
    binary.writeU16(bytes, 22, 0);
    binary.writeU32(bytes, 24, 0);
    binary.writeU32(bytes, 28, 0);
    binary.writeU32(bytes, 32, 0);
    binary.writeU32(bytes, 36, 0);
    binary.writeU32(bytes, 40, 0);
    return try out.toOwnedSlice();
}

fn sfntSizeForTest(tables: []const TestSfntTable) !usize {
    var total = 12 + tables.len * 16;
    for (tables) |table| total += try binary.align4(table.length);
    return total;
}

fn zlibCompressForTest(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var out = try std.Io.Writer.Allocating.initCapacity(allocator, data.len + 64);
    errdefer out.deinit();
    var scratch: [std.compress.flate.max_window_len]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(
        &out.writer,
        &scratch,
        .zlib,
        .fastest,
    );
    try compressor.writer.writeAll(data);
    try compressor.finish();
    return try out.toOwnedSlice();
}

pub fn reverseWoffPayloadOrder(
    allocator: std.mem.Allocator,
    woff: []const u8,
) ![]u8 {
    const table_count = binary.readU16(woff, 12);
    const first_payload = 44 + @as(usize, table_count) * 20;
    if (first_payload > woff.len) return error.TestUnexpectedResult;
    const reversed = try allocator.dupe(u8, woff);
    errdefer allocator.free(reversed);
    var destination = first_payload;
    var reverse_index: usize = table_count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const record = 44 + reverse_index * 20;
        const source: usize = binary.readU32(woff, record + 4);
        const compressed_len: usize = binary.readU32(woff, record + 8);
        const padded_len = try binary.align4(compressed_len);
        if (source > woff.len or padded_len > woff.len - source) {
            return error.TestUnexpectedResult;
        }
        @memcpy(
            reversed[destination..][0..padded_len],
            woff[source..][0..padded_len],
        );
        binary.writeU32(reversed, record + 4, @intCast(destination));
        destination += padded_len;
    }
    if (destination != woff.len) return error.TestUnexpectedResult;
    return reversed;
}

pub fn findWoffTablePayload(woff: []const u8, tag: *const [4]u8) !usize {
    const table_count = binary.readU16(woff, 12);
    for (0..table_count) |index| {
        const record = 44 + index * 20;
        if (std.mem.eql(u8, woff[record..][0..4], tag)) {
            const offset: usize = binary.readU32(woff, record + 4);
            const compressed_len = binary.readU32(woff, record + 8);
            const original_len = binary.readU32(woff, record + 12);
            if (compressed_len != original_len or offset > woff.len) {
                return error.TestUnexpectedResult;
            }
            return offset;
        }
    }
    return error.TestUnexpectedResult;
}

pub fn sfntChecksum(sfnt: []const u8) !u32 {
    if ((sfnt.len & 3) != 0) return error.TestUnexpectedResult;
    var checksum: u32 = 0;
    var offset: usize = 0;
    while (offset < sfnt.len) : (offset += 4) {
        checksum +%= binary.readU32(sfnt, offset);
    }
    return checksum;
}

pub fn buildDfont(
    allocator: std.mem.Allocator,
    faces: []const []const u8,
) ![]u8 {
    if (faces.len == 0 or faces.len > std.math.maxInt(u16) + 1) {
        return error.TestUnexpectedResult;
    }
    const data_start: usize = 256;
    var data_len: usize = 0;
    for (faces) |face| {
        data_len = std.math.add(usize, data_len, 4 + face.len) catch
            return error.OutOfMemory;
    }
    const map_start = data_start + data_len;
    const type_list_rel: usize = 28;
    const references_rel: usize = 10;
    const map_len = 28 + 2 + 8 + faces.len * 12;
    const bytes = try allocator.alloc(u8, map_start + map_len);
    @memset(bytes, 0);

    binary.writeU32(bytes, 0, @intCast(data_start));
    binary.writeU32(bytes, 4, @intCast(map_start));
    binary.writeU32(bytes, 8, @intCast(data_len));
    binary.writeU32(bytes, 12, @intCast(map_len));
    binary.writeU16(bytes, map_start + 24, @intCast(type_list_rel));
    binary.writeU16(bytes, map_start + 26, @intCast(map_len));

    const type_list = map_start + type_list_rel;
    binary.writeU16(bytes, type_list, 0); // One resource type, encoded count - 1.
    @memcpy(bytes[type_list + 2 ..][0..4], "sfnt");
    binary.writeU16(bytes, type_list + 6, @intCast(faces.len - 1));
    binary.writeU16(bytes, type_list + 8, @intCast(references_rel));

    var resource_offset: usize = 0;
    for (faces, 0..) |face, face_index| {
        const resource = data_start + resource_offset;
        binary.writeU32(bytes, resource, @intCast(face.len));
        @memcpy(bytes[resource + 4 ..][0..face.len], face);

        const reference = type_list + references_rel + face_index * 12;
        binary.writeU16(bytes, reference, @intCast(face_index + 128));
        binary.writeU16(bytes, reference + 2, 0xffff);
        binary.writeU32(bytes, reference + 4, @intCast(resource_offset));
        resource_offset += 4 + face.len;
    }
    return bytes;
}
