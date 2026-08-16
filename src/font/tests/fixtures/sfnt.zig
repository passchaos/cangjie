//! Binary helpers shared by integration tests that mutate SFNT fixtures.

const std = @import("std");
const sfnt = @import("../../sfnt/root.zig");

/// Locate one table in a standalone SFNT fixture.
///
/// Integration tests mutate caller-owned table bytes after construction, so
/// they need the physical table offset rather than the public `Font.tableData`
/// view. Validate the directory bounds here to keep malformed test setup from
/// trapping before the parser receives it.
pub fn tableOffset(
    bytes: []const u8,
    comptime tag: *const [4]u8,
) error{BadSfnt}!usize {
    if (bytes.len < 12) return error.BadSfnt;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    if (table_count > (bytes.len - 12) / 16) return error.BadSfnt;

    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (!std.mem.eql(u8, bytes[record_offset..][0..4], tag)) continue;

        const offset = std.mem.readInt(
            u32,
            bytes[record_offset + 8 ..][0..4],
            .big,
        );
        if (offset > bytes.len) return error.BadSfnt;
        return offset;
    }
    return error.BadSfnt;
}

/// Find a canonical name record by NameID and return its absolute SFNT offset.
pub fn nameRecordOffset(
    bytes: []const u8,
    name_offset: usize,
    name_id: u16,
) error{ BadSfnt, InvalidName }!usize {
    if (name_offset > bytes.len or bytes.len - name_offset < 6) {
        return error.BadSfnt;
    }
    const count = std.mem.readInt(
        u16,
        bytes[name_offset + 2 ..][0..2],
        .big,
    );
    if (count > (bytes.len - name_offset - 6) / 12) {
        return error.BadSfnt;
    }
    for (0..count) |index| {
        const record_offset = name_offset + 6 + index * 12;
        const record_name_id = std.mem.readInt(
            u16,
            bytes[record_offset + 6 ..][0..2],
            .big,
        );
        if (record_name_id == name_id) return record_offset;
    }
    return error.InvalidName;
}

/// Refresh one table-directory checksum after deliberately mutating a fixture.
///
/// Most borrowed-lifecycle tests intentionally leave the original checksum in
/// place. Parse-time semantic tests instead need to isolate a table invariant
/// from checksum rejection, so this helper mirrors the production `head`
/// special case while still validating every directory-derived byte range.
pub fn updateTableChecksum(
    bytes: []u8,
    comptime tag: *const [4]u8,
) error{BadSfnt}!void {
    if (bytes.len < 12) return error.BadSfnt;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    if (table_count > (bytes.len - 12) / 16) return error.BadSfnt;

    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (!std.mem.eql(u8, bytes[record_offset..][0..4], tag)) continue;

        const record: sfnt.Record = .{
            .tag = tag.*,
            .checksum = 0,
            .offset = std.mem.readInt(
                u32,
                bytes[record_offset + 8 ..][0..4],
                .big,
            ),
            .length = std.mem.readInt(
                u32,
                bytes[record_offset + 12 ..][0..4],
                .big,
            ),
        };
        const checksum = if (std.mem.eql(u8, tag, "head"))
            try sfnt.checksum.head(bytes, record)
        else
            try sfnt.checksum.table(bytes, record);
        writeU32(bytes, record_offset + 4, checksum);
        return;
    }
    return error.BadSfnt;
}

/// Change one standalone SFNT directory record's declared table length.
///
/// Structural table tests use this to isolate length contracts without
/// duplicating directory walking in each table family.
pub fn setTableLength(
    bytes: []u8,
    comptime tag: *const [4]u8,
    length: u32,
) error{BadSfnt}!void {
    if (bytes.len < 12) return error.BadSfnt;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    if (table_count > (bytes.len - 12) / 16) return error.BadSfnt;

    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (!std.mem.eql(u8, bytes[record_offset..][0..4], tag)) continue;
        writeU32(bytes, record_offset + 12, length);
        return;
    }
    return error.BadSfnt;
}

/// Rename one table record while preserving its payload and checksum.
pub fn setTableTag(
    bytes: []u8,
    comptime old_tag: *const [4]u8,
    comptime new_tag: *const [4]u8,
) error{BadSfnt}!void {
    if (bytes.len < 12) return error.BadSfnt;
    const table_count = std.mem.readInt(u16, bytes[4..6], .big);
    if (table_count > (bytes.len - 12) / 16) return error.BadSfnt;

    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (!std.mem.eql(
            u8,
            bytes[record_offset..][0..4],
            old_tag,
        )) continue;
        @memcpy(bytes[record_offset..][0..4], new_tag);
        return;
    }
    return error.BadSfnt;
}

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
