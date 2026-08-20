//! Complete GPOS lookup-sidecar construction contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const table = @import("../../../table/root.zig");

test "lookup builder owns SinglePos sidecars and exact dispatch identity" {
    var bytes = [_]u8{0} ** 36;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 18);
    writeU16(&bytes, 12, 0x0001);
    writeI16(&bytes, 14, 25);
    writeCoverage1(&bytes, 26, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const lookup = try build.lookup.one(view, 0, std.testing.allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(
        std.testing.allocator,
        &owned,
    );
    try std.testing.expectEqual(@as(usize, 0), lookup.lookup_offset);
    try std.testing.expectEqual(@as(u16, 1), lookup.lookup_type);
    try std.testing.expectEqual(@as(usize, 1), lookup.single_pos_subtables.len);
    try std.testing.expectEqual(
        @as(i16, 25),
        lookup.single_pos_subtables[0].value.x_placement,
    );
    try std.testing.expect(lookup.coverage_digest.mayHave(5));
}

test "top-level builder rejects truncated input before allocation escapes" {
    const bytes = [_]u8{0} ** 8;
    try std.testing.expectError(
        error.BadGpos,
        build.lookup.all(
            &bytes,
            0,
            8,
            std.testing.allocator,
        ),
    );
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
