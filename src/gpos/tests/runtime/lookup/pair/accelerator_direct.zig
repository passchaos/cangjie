//! Direct PairPos accelerator integration contracts.

const std = @import("std");
const accelerator_core = @import("../../../../accelerator/root.zig");
const lookup_dispatcher = @import("../../../../runtime/lookup/dispatcher/root.zig");
const pair_runtime = @import("../../../../runtime/lookup/pair/root.zig");
const positioning = @import("../../../../positioning/root.zig");
const table_core = @import("../../../../table/root.zig");

const Adjustment = positioning.Adjustment;
const LookupAccelerator = accelerator_core.model.Lookup;
const PairPosAcceleratorKind = accelerator_core.model.PairPositionKind;
const Table = table_core.View;
const buildLookupAccelerator = accelerator_core.build.lookup.one;
const collectLookupWithIndex = lookup_dispatcher.collectWithIndex;
const deinitLookupAcceleratorContents = accelerator_core.build.lookup.deinitContents;
const pairPosSubtablesHaveNativeData = pair_runtime.accelerated.hasNativeData;
const writeClassDef1Test = writeClassDef1;
const writeCoverage1Test = writeCoverage1;
const writeI16Test = writeI16;
const writeU16Test = writeU16;
const writeU32Test = writeU32;

test "GPOS simple PairPos accelerator preserves zero adjustment precedence" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    // Lookup with two PairPos alternatives.
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 40);

    // First format-1 subtable explicitly handles (5, 7) with xAdvance=0.
    const first = 10;
    writeU16Test(&bytes, first + 0, 1);
    writeU16Test(&bytes, first + 2, 20);
    writeU16Test(&bytes, first + 4, 0x0004);
    writeU16Test(&bytes, first + 6, 0);
    writeU16Test(&bytes, first + 8, 1);
    writeU16Test(&bytes, first + 10, 12);
    const pair_set = first + 12;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 7);
    writeI16Test(&bytes, pair_set + 4, 0);
    writeCoverage1Test(&bytes, first + 20, 5);

    // Later format-2 fallback would kern the same pair by -40 if precedence is
    // lost. It remains generic in the accelerator.
    const second = 40;
    writeU16Test(&bytes, second + 0, 2);
    writeU16Test(&bytes, second + 2, 24);
    writeU16Test(&bytes, second + 4, 0x0004);
    writeU16Test(&bytes, second + 6, 0);
    writeU16Test(&bytes, second + 8, 30);
    writeU16Test(&bytes, second + 10, 38);
    writeU16Test(&bytes, second + 12, 2);
    writeU16Test(&bytes, second + 14, 2);
    writeI16Test(&bytes, second + 16, 0);
    writeI16Test(&bytes, second + 18, 0);
    writeI16Test(&bytes, second + 20, 0);
    writeI16Test(&bytes, second + 22, -40);
    writeCoverage1Test(&bytes, second + 24, 5);
    writeClassDef1Test(&bytes, second + 30, 5, 1);
    writeClassDef1Test(&bytes, second + 38, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 1), accelerator.pair_pos_records.len);
    try std.testing.expectEqual(@as(i16, 0), accelerator.pair_pos_records[0].x_advance);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{ .lookup_accelerators = &accelerators },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
}
test "GPOS pure class PairPos lookup activates native matrix without format 1 records" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 2); // PairPos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    const pair = 8;
    writeU16Test(&bytes, pair + 0, 2);
    writeU16Test(&bytes, pair + 2, 32);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0);
    writeU16Test(&bytes, pair + 8, 38);
    writeU16Test(&bytes, pair + 10, 46);
    writeU16Test(&bytes, pair + 12, 2);
    writeU16Test(&bytes, pair + 14, 2);
    writeI16Test(&bytes, pair + 16, 0);
    writeI16Test(&bytes, pair + 18, 0);
    writeI16Test(&bytes, pair + 20, 0);
    writeI16Test(&bytes, pair + 22, -31);
    writeCoverage1Test(&bytes, pair + 32, 5);
    writeClassDef1Test(&bytes, pair + 38, 5, 1);
    writeClassDef1Test(&bytes, pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 0), accelerator.pair_pos_records.len);
    try std.testing.expect(pairPosSubtablesHaveNativeData(accelerator.pair_pos_subtables));
    // Distinguish actual native-matrix dispatch from a generic parser that
    // happens to produce the same result. Public Font shaping would reject
    // this post-proof mutation by checksum; this detached test deliberately
    // mutates only the borrowed matrix after the accelerator copied `-31`.
    writeI16Test(&bytes, pair + 22, 99);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = false,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -31), adjustments.items[0].x_advance);
}
fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeClassDef1(bytes: []u8, offset: usize, glyph: u16, class: u16) void {
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

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
