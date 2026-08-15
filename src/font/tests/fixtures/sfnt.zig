//! Binary helpers shared by integration tests that mutate SFNT fixtures.

const std = @import("std");

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

pub fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

pub fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
