//! ReverseChainSingleSubst exact-context builder contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const model = @import("../../../accelerator/model.zig");
const runtime = @import("../../../runtime/root.zig");
const table = @import("../../../table/root.zig");

test "reverse builder appends singleton format 1 and 2 contexts" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 44;
    // Offsets are relative to subtable zero.
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 14);
    writeU16(&bytes, 4, 24);
    writeU16(&bytes, 6, 30);
    writeCoverage1(&bytes, 8, 2);
    writeCoverage2Singleton(&bytes, 14, 1);
    writeCoverage1(&bytes, 24, 3);
    writeCoverage2Singleton(&bytes, 30, 4);
    writeU16(&bytes, 40, 9);

    const parsed = model.ReverseChainingSingleSubtable{
        .subtable_offset = 0,
        .coverage_offset = 8,
        .backtrack_offsets_pos = 2,
        .backtrack_count = 1,
        .lookahead_offsets_pos = 4,
        .lookahead_count = 2,
        .glyph_count = 1,
        .substitutes_pos = 40,
    };
    var contexts = std.ArrayList(model.ReverseChainingContextEntry).empty;
    defer contexts.deinit(allocator);
    try build.reverse.appendExact(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, parsed, 3, &contexts, allocator);

    try std.testing.expectEqual(@as(usize, 1), contexts.items.len);
    try std.testing.expectEqual(model.ReverseChainingContextKey{
        .target = 2,
        .backtrack = 1,
        .lookahead_0 = 3,
        .lookahead_1 = 4,
    }, contexts.items[0].key);
    try std.testing.expectEqual(@as(u16, 9), contexts.items[0].substitute);
}

test "reverse builder sorts equal keys by subtable index" {
    const allocator = std.testing.allocator;
    var contexts = [_]model.ReverseChainingContextEntry{
        .{ .key = key(4), .subtable_index = 5, .substitute = 50 },
        .{ .key = key(2), .subtable_index = 7, .substitute = 20 },
        .{ .key = key(2), .subtable_index = 1, .substitute = 10 },
    };
    const sorted = try build.reverse.finish(&contexts, allocator);
    defer allocator.free(sorted);

    try std.testing.expectEqual(@as(u16, 1), sorted[0].subtable_index);
    try std.testing.expectEqual(@as(u16, 7), sorted[1].subtable_index);
    try std.testing.expectEqual(@as(u16, 5), sorted[2].subtable_index);
    try std.testing.expectEqual(
        @as(u16, 10),
        runtime.reverse_context.find(sorted, key(2)).?.substitute,
    );
    try std.testing.expect(runtime.reverse_context.find(sorted, key(9)) == null);
}

test "reverse builder leaves non-exact shapes on generic path" {
    var contexts = std.ArrayList(model.ReverseChainingContextEntry).empty;
    defer contexts.deinit(std.testing.allocator);
    const bytes = [_]u8{0} ** 2;
    try build.reverse.appendExact(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, .{ .backtrack_count = 2 }, 0, &contexts, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), contexts.items.len);
}

fn key(target: u16) model.ReverseChainingContextKey {
    return .{
        .target = target,
        .backtrack = 1,
        .lookahead_0 = 3,
        .lookahead_1 = 4,
    };
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeCoverage2Singleton(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 2);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
    writeU16(bytes, offset + 6, glyph);
    writeU16(bytes, offset + 8, 0);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
