//! ExtensionPos PairPos accelerator integration contracts.

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

test "GPOS ExtensionPos PairPos accelerator preserves device stride and precedence" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

    // One homogeneous ExtensionPos lookup wrapping two ordered PairPos
    // alternatives.
    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 44);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 20);
    // xAdvance plus a nullable xAdvanceDeviceOffset. The latter makes each
    // ValueRecord four bytes rather than two and exercises predecoded strides.
    writeU16Test(&bytes, first_pair + 4, 0x0044);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 12);
    const first_set = first_pair + 12;
    writeU16Test(&bytes, first_set + 0, 1);
    writeU16Test(&bytes, first_set + 2, 7);
    writeI16Test(&bytes, first_set + 4, 0);
    writeU16Test(&bytes, first_set + 6, 0);
    writeCoverage1Test(&bytes, first_pair + 20, 5);

    const second_extension = 44;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 2);
    writeU16Test(&bytes, second_pair + 2, 32);
    writeU16Test(&bytes, second_pair + 4, 0x0044);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 38);
    writeU16Test(&bytes, second_pair + 10, 46);
    writeU16Test(&bytes, second_pair + 12, 2);
    writeU16Test(&bytes, second_pair + 14, 2);
    // Four class matrix records, each xAdvance followed by a null device
    // offset. The final record would apply -40 to class (1, 1).
    for (0..4) |record_index| {
        writeI16Test(&bytes, second_pair + 16 + record_index * 4, if (record_index == 3) -40 else 0);
        writeU16Test(&bytes, second_pair + 18 + record_index * 4, 0);
    }
    writeCoverage1Test(&bytes, second_pair + 32, 5);
    writeClassDef1Test(&bytes, second_pair + 38, 5, 1);
    writeClassDef1Test(&bytes, second_pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expect(accelerator.pair_pos_extension);
    try std.testing.expectEqual(@as(usize, 2), accelerator.pair_pos_subtables.len);
    try std.testing.expectEqual(PairPosAcceleratorKind.format_1_x_advance, accelerator.pair_pos_subtables[0].kind);
    try std.testing.expectEqual(PairPosAcceleratorKind.format_2_dense_x_advance, accelerator.pair_pos_subtables[1].kind);
    const candidates = accelerator_core.glyph_groups.find(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        5,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, candidates);
    try std.testing.expect(accelerator_core.glyph_groups.find(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        6,
    ) == null);

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
    // The first wrapper explicitly handled this pair with zero adjustment.
    // The later class fallback must not override it with -40.
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
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
