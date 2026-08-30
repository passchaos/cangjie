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

test "extension ContextPos class rules build compact two-glyph sidecars" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeU16(&bytes, 0, 9);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 7);
    writeU32(&bytes, 12, 8);

    const context = 16;
    writeU16(&bytes, context, 2);
    writeU16(&bytes, context + 2, 32);
    writeU16(&bytes, context + 4, 38);
    writeU16(&bytes, context + 6, 2);
    writeU16(&bytes, context + 8, 0);
    writeU16(&bytes, context + 10, 12);
    const set = context + 12;
    writeU16(&bytes, set, 1);
    writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(&bytes, rule, 2);
    writeU16(&bytes, rule + 2, 1);
    writeU16(&bytes, rule + 4, 3);
    writeU16(&bytes, rule + 6, 1);
    writeU16(&bytes, rule + 8, 9);
    writeCoverage1(&bytes, context + 32, 5);
    writeClassDef1(&bytes, context + 38, 5, &.{ 1, 3 });

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const lookup = try build.lookup.one(view, 0, allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(allocator, &owned);

    try std.testing.expectEqual(@as(?u16, 7), lookup.extension_lookup_type);
    try std.testing.expectEqual(@as(usize, 1), lookup.context_class_subtables.len);
    const subtable = lookup.context_class_subtables[0];
    try std.testing.expectEqual(@as(?usize, 0), subtable.coverage.?.index(5));
    try std.testing.expectEqual(@as(u16, 3), subtable.rules[0].second_class);
    try std.testing.expectEqual(@as(u16, 1), subtable.rules[0].sequence_index);
    try std.testing.expectEqual(@as(u16, 9), subtable.rules[0].lookup_index);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    start: u16,
    classes: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, @intCast(classes.len));
    for (classes, 0..) |class, index| {
        writeU16(bytes, offset + 6 + index * 2, class);
    }
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
