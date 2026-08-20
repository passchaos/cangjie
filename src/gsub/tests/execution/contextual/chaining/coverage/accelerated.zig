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

test "accelerated first-input proof and generic matching have equal output" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 56;
    writeChainingSubtable(&bytes, 0, &.{}, &.{ 2, 3 }, &.{}, 0, 2);
    const view = validatedView(&bytes);
    const parsed = (try accelerator.build.chaining_coverage.parser.parse(
        view,
        0,
    )).?;

    var generic = std.ArrayList(u16).empty;
    defer generic.deinit(allocator);
    try generic.appendSlice(allocator, &.{ 2, 3 });
    _ = try chaining.at(
        Executor,
        view,
        parsed,
        &generic,
        0,
        allocator,
        0,
        .{},
    );

    var accelerated = std.ArrayList(u16).empty;
    defer accelerated.deinit(allocator);
    try accelerated.appendSlice(allocator, &.{ 2, 3 });
    _ = try chaining.acceleratedAt(
        Executor,
        view,
        parsed,
        &accelerated,
        0,
        allocator,
        0,
        .{},
    );
    try std.testing.expectEqualSlices(u16, generic.items, accelerated.items);
}

test "no-context fast path resolves up to three prefiltered inputs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeChainingSubtable(&bytes, 0, &.{}, &.{ 1, 2, 3 }, &.{}, 2, 4);
    const view = validatedView(&bytes);
    var parsed = (try accelerator.build.chaining_coverage.parser.parse(
        view,
        0,
    )).?;
    parsed.second_input_coverage_offset =
        try table.offset.required16(view, 0, try view.readU16(
            parsed.input_offsets_pos + 2,
        ));
    parsed.third_input_coverage_offset =
        try table.offset.required16(view, 0, try view.readU16(
            parsed.input_offsets_pos + 4,
        ));
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2, 3 });
    const result = try chaining.acceleratedNoContextAt(
        Executor,
        view,
        parsed,
        &glyphs,
        0,
        1,
        2,
        allocator,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 17 }, glyphs.items);
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
