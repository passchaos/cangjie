//! PairPos accelerator construction contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const table = @import("../../table/root.zig");

test "format 1 ignores PairSets unreachable from Coverage" {
    var bytes = [_]u8{0} ** 42;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 30);
    writeU16(&bytes, 4, 0x0004);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 2);
    writeU16(&bytes, 10, 14);
    writeU16(&bytes, 12, 22);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 7);
    writeI16(&bytes, 18, -30);
    writeU16(&bytes, 22, 1);
    writeU16(&bytes, 24, 7);
    writeI16(&bytes, 26, 200);
    writeCoverage1(&bytes, 30, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var records = std.ArrayList(accelerator.model.PairPositionRecord).empty;
    defer records.deinit(std.testing.allocator);

    const parsed = try accelerator.pair.appendFormat1(
        view,
        0,
        2,
        &records,
        std.testing.allocator,
    );
    try std.testing.expectEqual(@as(usize, 1), parsed.record_len);
    try std.testing.expectEqual(
        accelerator.model.PairPositionRecord{
            .first = 5,
            .second = 7,
            .x_advance = -30,
        },
        records.items[0],
    );
}

test "format 2 builds dense class maps and matrix" {
    var bytes = [_]u8{0} ** 64;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 32);
    writeU16(&bytes, 4, 0x0004);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 38);
    writeU16(&bytes, 10, 46);
    writeU16(&bytes, 12, 2);
    writeU16(&bytes, 14, 2);
    writeI16(&bytes, 16, 0);
    writeI16(&bytes, 18, 0);
    writeI16(&bytes, 20, -15);
    writeI16(&bytes, 22, -35);
    writeCoverage1(&bytes, 32, 5);
    writeClassDef1(&bytes, 38, 5, 1);
    writeClassDef1(&bytes, 46, 7, 1);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var records = std.ArrayList(accelerator.model.PairPositionRecord).empty;
    defer records.deinit(std.testing.allocator);
    var coverage = std.ArrayList(accelerator.model.PairClassEntry).empty;
    defer coverage.deinit(std.testing.allocator);
    var classes = std.ArrayList(accelerator.model.PairClassEntry).empty;
    defer classes.deinit(std.testing.allocator);
    var matrix = std.ArrayList(i16).empty;
    defer matrix.deinit(std.testing.allocator);

    const parsed = try accelerator.pair.append(
        view,
        0,
        &records,
        &coverage,
        &classes,
        &matrix,
        std.testing.allocator,
    );
    try std.testing.expectEqual(
        accelerator.model.PairPositionKind.format_2_dense_x_advance,
        parsed.kind,
    );
    try std.testing.expectEqualSlices(i16, &.{ 0, 0, -15, -35 }, matrix.items);
    try std.testing.expectEqual(
        accelerator.model.PairClassEntry{ .glyph = 5, .class = 1 },
        coverage.items[0],
    );
}

test "dense class ranges enforce the shared total cap" {
    try std.testing.expect(accelerator.pair.shouldBuildDense(.{
        .coverage_base = 0,
        .coverage_len = accelerator.pair.max_dense_class_entries - 1,
        .class_2_base = 0,
        .class_2_len = 1,
    }));
    try std.testing.expect(!accelerator.pair.shouldBuildDense(.{
        .coverage_base = 0,
        .coverage_len = accelerator.pair.max_dense_class_entries,
        .class_2_base = 0,
        .class_2_len = 1,
    }));
    try std.testing.expect(!accelerator.pair.shouldBuildDense(.{
        .coverage_base = 0,
        .coverage_len = accelerator.pair.max_dense_class_entries + 1,
        .class_2_base = 0,
        .class_2_len = 0,
    }));
}

test "dense class ranges reject entries outside endpoint spans" {
    try std.testing.expect(accelerator.pair.denseRanges(
        &.{
            .{ .glyph = 20, .class = 1 },
            .{ .glyph = 5, .class = 0 },
            .{ .glyph = 12, .class = 2 },
        },
        &.{
            .{ .glyph = 100, .class = 1 },
            .{ .glyph = 7, .class = 2 },
        },
    ) == null);

    const ranges = accelerator.pair.DenseRanges{
        .coverage_base = 5,
        .coverage_len = 16,
        .class_2_base = 7,
        .class_2_len = 94,
    };
    try std.testing.expect(!accelerator.pair.entriesFitDenseRanges(
        &.{
            .{ .glyph = 5, .class = 0 },
            .{ .glyph = 30, .class = 1 },
            .{ .glyph = 20, .class = 2 },
        },
        &.{.{ .glyph = 7, .class = 1 }},
        ranges,
    ));
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    glyph: u16,
    class: u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, glyph);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, class);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
