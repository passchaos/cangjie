//! Contextual class-definition and set-boundary validation contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const positioning = @import("../../../positioning/root.zig");
const runtime_lookup = @import("../../../runtime/lookup/root.zig");
const table_core = @import("../../../table/root.zig");
const validation = @import("../../../validation/root.zig");

const Adjustment = positioning.Adjustment;
const Table = table_core.View;
const collectPairAdjustment = runtime_lookup.pair.generic.collect;
const ensureContextPositionSubtableWithin = validation.lookup.contextSubtable;
const ensureChainingContextPositionSubtableWithin = validation.lookup.chainingSubtable;
const writeCoverage1Test = fixture.writeCoverage1;
const writeI16Test = fixture.writeI16;
const writeU16Test = fixture.writeU16;

test "GPOS contextual class subtables allow covered class indexes outside set arrays" {
    var context_bytes = [_]u8{0} ** 32;
    writeU16Test(&context_bytes, 0, 2); // ContextPos format 2.
    writeU16Test(&context_bytes, 2, 12); // Coverage.
    writeU16Test(&context_bytes, 4, 18); // ClassDef.
    writeU16Test(&context_bytes, 6, 1); // Only class 0 has a PosClassSet slot.
    writeU16Test(&context_bytes, 8, 0); // Nullable class-0 PosClassSet.
    writeCoverage1Test(&context_bytes, 12, 5);
    writeU16Test(&context_bytes, 18, 1); // ClassDef format 1.
    writeU16Test(&context_bytes, 20, 5);
    writeU16Test(&context_bytes, 22, 1);
    writeU16Test(&context_bytes, 24, 1); // Covered glyph indexes past PosClassSetCount.

    var table = Table{ .data = &context_bytes, .offset = 0, .length = context_bytes.len };
    try ensureContextPositionSubtableWithin(table, 0, 0);

    writeU16Test(&context_bytes, 24, 0);
    try ensureContextPositionSubtableWithin(table, 0, 0);

    var chaining_bytes = [_]u8{0} ** 48;
    writeU16Test(&chaining_bytes, 0, 2); // ChainingContextPos format 2.
    writeU16Test(&chaining_bytes, 2, 16); // Coverage.
    writeU16Test(&chaining_bytes, 4, 22); // BacktrackClassDef.
    writeU16Test(&chaining_bytes, 6, 30); // InputClassDef.
    writeU16Test(&chaining_bytes, 8, 38); // LookaheadClassDef.
    writeU16Test(&chaining_bytes, 10, 1); // Only class 0 has a ChainPosClassSet slot.
    writeU16Test(&chaining_bytes, 12, 0); // Nullable class-0 ChainPosClassSet.
    writeCoverage1Test(&chaining_bytes, 16, 5);
    writeU16Test(&chaining_bytes, 22, 1);
    writeU16Test(&chaining_bytes, 24, 0);
    writeU16Test(&chaining_bytes, 26, 1);
    writeU16Test(&chaining_bytes, 28, 0);
    writeU16Test(&chaining_bytes, 30, 1);
    writeU16Test(&chaining_bytes, 32, 5);
    writeU16Test(&chaining_bytes, 34, 1);
    writeU16Test(&chaining_bytes, 36, 1); // Covered input glyph indexes past ChainPosClassSetCount.
    writeU16Test(&chaining_bytes, 38, 1);
    writeU16Test(&chaining_bytes, 40, 0);
    writeU16Test(&chaining_bytes, 42, 1);
    writeU16Test(&chaining_bytes, 44, 0);

    table = .{ .data = &chaining_bytes, .offset = 0, .length = chaining_bytes.len };
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);

    writeU16Test(&chaining_bytes, 36, 0);
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
}
test "GPOS class-based positioning applies contextual ClassDef nullability" {
    const allocator = std.testing.allocator;

    var pair_bytes = [_]u8{0} ** 40;
    writeU16Test(&pair_bytes, 0, 2); // PairPos format 2.
    writeU16Test(&pair_bytes, 2, 34); // Coverage.
    writeU16Test(&pair_bytes, 4, 0x0004); // ValueFormat1: xAdvance.
    writeU16Test(&pair_bytes, 6, 0); // Empty ValueFormat2.
    writeU16Test(&pair_bytes, 8, 0); // Invalid: ClassDef1 offsets are required.
    writeU16Test(&pair_bytes, 10, 26); // ClassDef2.
    writeU16Test(&pair_bytes, 12, 1); // Class1Count.
    writeU16Test(&pair_bytes, 14, 1); // Class2Count.
    writeI16Test(&pair_bytes, 16, -15); // Single matrix ValueRecord.
    writeU16Test(&pair_bytes, 18, 1);
    writeU16Test(&pair_bytes, 20, 10);
    writeU16Test(&pair_bytes, 22, 1);
    writeU16Test(&pair_bytes, 24, 0);
    writeU16Test(&pair_bytes, 26, 1);
    writeU16Test(&pair_bytes, 28, 11);
    writeU16Test(&pair_bytes, 30, 1);
    writeU16Test(&pair_bytes, 32, 0);
    writeCoverage1Test(&pair_bytes, 34, 10);

    var table = Table{ .data = &pair_bytes, .offset = 0, .length = pair_bytes.len };
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(error.BadGpos, collectPairAdjustment(table, 0, &.{ 10, 11 }, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&pair_bytes, 8, 18);
    writeU16Test(&pair_bytes, 10, 0); // ClassDef2 is required too.
    try std.testing.expectError(error.BadGpos, positioning.lookup.pair.validate(table, 0));

    writeU16Test(&pair_bytes, 10, 26);
    try positioning.lookup.pair.validate(table, 0);
    try collectPairAdjustment(table, 0, &.{ 10, 11 }, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -15), adjustments.items[0].x_advance);
    adjustments.clearRetainingCapacity();

    var context_bytes = [_]u8{0} ** 26;
    writeU16Test(&context_bytes, 0, 2); // ContextPos format 2.
    writeU16Test(&context_bytes, 2, 12); // Coverage.
    writeU16Test(&context_bytes, 4, 0); // Invalid: ClassDef offsets are required.
    writeU16Test(&context_bytes, 6, 1); // One nullable PosClassSet slot.
    writeU16Test(&context_bytes, 8, 0);
    writeCoverage1Test(&context_bytes, 12, 5);
    writeU16Test(&context_bytes, 18, 1);
    writeU16Test(&context_bytes, 20, 5);
    writeU16Test(&context_bytes, 22, 1);
    writeU16Test(&context_bytes, 24, 0);

    table = .{ .data = &context_bytes, .offset = 0, .length = context_bytes.len };
    try std.testing.expectError(error.BadGpos, ensureContextPositionSubtableWithin(table, 0, 0));
    try std.testing.expectError(error.BadGpos, runtime_lookup.nested.contextCollect(table, 0, &.{5}, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&context_bytes, 4, 18);
    try ensureContextPositionSubtableWithin(table, 0, 0);
    try runtime_lookup.nested.contextCollect(table, 0, &.{5}, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    var chaining_bytes = [_]u8{0} ** 46;
    writeU16Test(&chaining_bytes, 0, 2); // ChainingContextPos format 2.
    writeU16Test(&chaining_bytes, 2, 16); // Coverage.
    writeU16Test(&chaining_bytes, 4, 22); // BacktrackClassDef.
    writeU16Test(&chaining_bytes, 6, 30); // InputClassDef.
    writeU16Test(&chaining_bytes, 8, 38); // LookaheadClassDef.
    writeU16Test(&chaining_bytes, 10, 1); // One nullable ChainPosClassSet slot.
    writeU16Test(&chaining_bytes, 12, 0);
    writeCoverage1Test(&chaining_bytes, 16, 5);
    writeU16Test(&chaining_bytes, 22, 1);
    writeU16Test(&chaining_bytes, 24, 0);
    writeU16Test(&chaining_bytes, 26, 1);
    writeU16Test(&chaining_bytes, 28, 0);
    writeU16Test(&chaining_bytes, 30, 1);
    writeU16Test(&chaining_bytes, 32, 5);
    writeU16Test(&chaining_bytes, 34, 1);
    writeU16Test(&chaining_bytes, 36, 0);
    writeU16Test(&chaining_bytes, 38, 1);
    writeU16Test(&chaining_bytes, 40, 0);
    writeU16Test(&chaining_bytes, 42, 1);
    writeU16Test(&chaining_bytes, 44, 0);

    table = .{ .data = &chaining_bytes, .offset = 0, .length = chaining_bytes.len };
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);

    // Chaining format 2 permits null backtrack/lookahead ClassDefs. Missing
    // definitions assign every glyph to class zero; InputClassDef remains
    // required because it selects the ChainPosClassSet.
    writeU16Test(&chaining_bytes, 4, 0);
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
    const no_backtrack = try positioning.lookup.contextual.parseChaining(
        table,
        0,
    );
    try std.testing.expectEqual(
        table_core.class_def.empty_offset,
        no_backtrack.class.backtrack_class_def,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try table_core.class_def.value(
            table,
            no_backtrack.class.backtrack_class_def,
            5,
        ),
    );
    try runtime_lookup.nested.chainingCollect(table, 0, &.{5}, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&chaining_bytes, 6, 0);
    try std.testing.expectError(error.BadGpos, ensureChainingContextPositionSubtableWithin(table, 0, 0));
    try std.testing.expectError(error.BadGpos, runtime_lookup.nested.chainingCollect(table, 0, &.{5}, &adjustments, allocator, 0, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
    writeU16Test(&chaining_bytes, 6, 30);

    writeU16Test(&chaining_bytes, 8, 0);
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
    const no_lookahead = try positioning.lookup.contextual.parseChaining(
        table,
        0,
    );
    try std.testing.expectEqual(
        table_core.class_def.empty_offset,
        no_lookahead.class.lookahead_class_def,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        try table_core.class_def.value(
            table,
            no_lookahead.class.lookahead_class_def,
            5,
        ),
    );
    try runtime_lookup.nested.chainingCollect(table, 0, &.{5}, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);

    writeU16Test(&chaining_bytes, 4, 22);
    writeU16Test(&chaining_bytes, 8, 38);
    try ensureChainingContextPositionSubtableWithin(table, 0, 0);
    try runtime_lookup.nested.chainingCollect(table, 0, &.{5}, &adjustments, allocator, 0, .{});
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}
