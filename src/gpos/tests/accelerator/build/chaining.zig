//! Chaining-context accelerator construction contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const coverage_matching =
    @import("../../../runtime/lookup/contextual/chaining/coverage/matching.zig");
const table = @import("../../../table/root.zig");

test "chaining accelerator caches every coverage region" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 44;

    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 20);
    writeU16(&bytes, 6, 2);
    writeU16(&bytes, 8, 26);
    writeU16(&bytes, 10, 32);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 38);
    writeU16(&bytes, 16, 0);
    writeCoverage(&bytes, 20, 2);
    writeCoverage(&bytes, 26, 3);
    writeCoverage(&bytes, 32, 4);
    writeCoverage(&bytes, 38, 5);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const subtable =
        (try build.chaining.coverageSubtable(view, 0, allocator)) orelse
        return error.TestUnexpectedResult;
    defer build.chaining.deinitCoverageSubtableContents(allocator, subtable);

    try std.testing.expectEqual(
        @as(usize, 1),
        subtable.backtrack_coverages.len,
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        subtable.input_coverages.len,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        subtable.lookahead_coverages.len,
    );
    try std.testing.expectEqual(
        @as(?usize, 0),
        subtable.backtrack_coverages[0].index(2),
    );
    try std.testing.expectEqual(
        @as(?usize, 0),
        subtable.input_coverages[0].index(3),
    );
    try std.testing.expectEqual(
        @as(?usize, 0),
        subtable.input_coverages[1].index(4),
    );
    try std.testing.expectEqual(
        @as(?usize, 0),
        subtable.lookahead_coverages[0].index(5),
    );
    try std.testing.expect(subtable.second_input_digest.mayHave(4));

    const glyphs = [_]u16{ 2, 3, 4, 5 };
    try std.testing.expect(try coverage_matching.indices(
        view,
        0,
        &glyphs,
        &.{ 1, 2 },
        subtable.input_offsets_pos,
        subtable.input_coverages,
        0,
    ));
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
