//! ChainContextSubst format-3 direct and accelerated execution contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const chaining =
    @import("../../../../../execution/contextual/chaining/coverage/root.zig");
const model = @import("../../../../../execution/contextual/model.zig");
const fixture = @import("../../context/fixture.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const table = @import("../../../../../table/root.zig");

const Executor = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        _: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        glyphs.items[target] += @as(u16, lookup_index) + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "chaining coverage matches backtrack input lookahead and ignored glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeChainingSubtable(
        &bytes,
        0,
        &.{1},
        &.{ 2, 3 },
        &.{4},
        1,
        5,
    );
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 9, 2, 9, 3, 9, 4 });
    const classes = [_]u16{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 3 };
    const result = try chaining.at(
        Executor,
        validatedView(&bytes),
        (try accelerator.build.chaining_coverage.parser.parse(
            validatedView(&bytes),
            0,
        )).?,
        &glyphs,
        2,
        allocator,
        0x0008,
        .{ .glyph_classes = &classes },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 9, 2, 9, 18, 9, 4 },
        glyphs.items,
    );
}

fn writeChainingSubtable(
    bytes: []u8,
    base: usize,
    backtrack: []const u16,
    input: []const u16,
    lookahead: []const u16,
    sequence_index: u16,
    lookup_index: u16,
) void {
    fixture.writeU16(bytes, base, 3);
    var cursor = base + 2;
    fixture.writeU16(bytes, cursor, @intCast(backtrack.len));
    cursor += 2;
    const backtrack_offsets = cursor;
    cursor += backtrack.len * 2;
    fixture.writeU16(bytes, cursor, @intCast(input.len));
    cursor += 2;
    const input_offsets = cursor;
    cursor += input.len * 2;
    fixture.writeU16(bytes, cursor, @intCast(lookahead.len));
    cursor += 2;
    const lookahead_offsets = cursor;
    cursor += lookahead.len * 2;
    fixture.writeU16(bytes, cursor, 1);
    fixture.writeRecord(bytes, cursor + 2, sequence_index, lookup_index);
    cursor += 6;

    for (backtrack, 0..) |glyph, index| {
        fixture.writeU16(
            bytes,
            backtrack_offsets + index * 2,
            @intCast(cursor - base),
        );
        fixture.writeCoverage1(bytes, cursor, glyph);
        cursor += 6;
    }
    for (input, 0..) |glyph, index| {
        fixture.writeU16(
            bytes,
            input_offsets + index * 2,
            @intCast(cursor - base),
        );
        fixture.writeCoverage1(bytes, cursor, glyph);
        cursor += 6;
    }
    for (lookahead, 0..) |glyph, index| {
        fixture.writeU16(
            bytes,
            lookahead_offsets + index * 2,
            @intCast(cursor - base),
        );
        fixture.writeCoverage1(bytes, cursor, glyph);
        cursor += 6;
    }
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
