//! ChainContextSubst format-3 parser and builder contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const ownership = @import("../../../accelerator/ownership.zig");
const table = @import("../../../table/root.zig");

test "chaining coverage parser exposes all cursor regions" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 16);
    writeU16(&bytes, 6, 2);
    writeU16(&bytes, 8, 18);
    writeU16(&bytes, 10, 20);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 22);
    writeU16(&bytes, 16, 0);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    const parsed = (try build.chaining_coverage.parser.parse(view, 0)).?;
    try std.testing.expectEqual(@as(u16, 1), parsed.backtrack_count);
    try std.testing.expectEqual(@as(u16, 2), parsed.input_count);
    try std.testing.expectEqual(@as(u16, 1), parsed.lookahead_count);
    try std.testing.expectEqual(@as(usize, 8), parsed.input_offsets_pos);
    try std.testing.expectEqual(
        @as(?usize, 18),
        try build.chaining_coverage.parser.firstInputCoverage(view, 0),
    );
}

test "chaining coverage builder records adjacent requirements" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 68;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 8, 10);
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 4);
    const lookup = 14;
    writeU16(&bytes, lookup, 6);
    writeU16(&bytes, lookup + 4, 1);
    writeU16(&bytes, lookup + 6, 8);
    const chain = lookup + 8;

    writeU16(&bytes, chain, 3);
    writeU16(&bytes, chain + 2, 1);
    writeU16(&bytes, chain + 4, 16);
    writeU16(&bytes, chain + 6, 1);
    writeU16(&bytes, chain + 8, 22);
    writeU16(&bytes, chain + 10, 1);
    writeU16(&bytes, chain + 12, 28);
    writeU16(&bytes, chain + 14, 0);
    writeCoverage1(&bytes, chain + 16, 3);
    writeCoverage1(&bytes, chain + 22, 1);
    writeCoverage1(&bytes, chain + 28, 4);

    const accelerator = try build.chaining_coverage.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, lookup, 1, false, .{}, null, allocator);
    defer ownership.deinitContents(allocator, &.{accelerator});

    try std.testing.expect(!accelerator.chaining_needs_second_input);
    try std.testing.expect(accelerator.chaining_needs_backtrack);
    try std.testing.expect(accelerator.chaining_needs_single_input_lookahead);
    try std.testing.expect(
        accelerator.chaining_subtables[0].first_backtrack_digest.mayHave(3),
    );
    try std.testing.expect(
        accelerator.chaining_subtables[0].first_lookahead_digest.mayHave(4),
    );
}

test "chaining coverage kind proof handles direct and extension wrappers" {
    var direct = [_]u8{0} ** 10;
    writeU16(&direct, 4, 1);
    writeU16(&direct, 6, 8);
    writeU16(&direct, 8, 3);
    try std.testing.expect(try build.chaining_coverage.lookupUsesCoverageOnly(
        .{ .data = &direct, .offset = 0, .length = direct.len },
        0,
        1,
        false,
    ));

    var extension = [_]u8{0} ** 18;
    writeU16(&extension, 4, 1);
    writeU16(&extension, 6, 8);
    writeU16(&extension, 8, 1);
    writeU16(&extension, 10, 6);
    writeU32(&extension, 12, 8);
    writeU16(&extension, 16, 3);
    try std.testing.expect(try build.chaining_coverage.lookupUsesCoverageOnly(
        .{ .data = &extension, .offset = 0, .length = extension.len },
        0,
        1,
        true,
    ));
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
