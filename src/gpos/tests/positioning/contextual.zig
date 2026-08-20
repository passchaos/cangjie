//! ContextPos and ChainContextPos grammar contracts.

const std = @import("std");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

const contextual = positioning.lookup.contextual;

test "ContextPos format 1 exposes nullable sets and rule payloads" {
    var bytes = [_]u8{0} ** 34;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 12);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 0);
    writeU16(&bytes, 8, 18);
    writeCoverage1(&bytes, 12, 5);
    writeU16(&bytes, 18, 1);
    writeU16(&bytes, 20, 4);
    writeU16(&bytes, 22, 2);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 6);
    writeU16(&bytes, 28, 1);
    writeU16(&bytes, 30, 3);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    const parsed = try contextual.parseContextForValidation(view, 0);
    const glyph = switch (parsed) {
        .glyph => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 12), glyph.coverage_offset);
    try std.testing.expectEqual(@as(?usize, null), try glyph.sets.resolve(view, 0));
    const set_offset = (try glyph.sets.resolve(view, 1)).?;
    try std.testing.expectEqual(@as(usize, 18), set_offset);

    const set = try contextual.parseRuleSetForValidation(view, set_offset);
    const rule = try contextual.parseContextRuleForValidation(
        view,
        try set.ruleOffset(view, 0),
    );
    try std.testing.expectEqual(@as(u16, 2), rule.input_count);
    try std.testing.expectEqual(@as(usize, 26), rule.input_values_pos);
    const record = try rule.records.record(view, 0);
    try std.testing.expectEqual(@as(u16, 1), record.sequence_index);
    try std.testing.expectEqual(@as(u16, 3), record.lookup_index);
}

test "ContextPos format 3 rejects empty input and bad sequence indexes" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 12);
    writeU16(&bytes, 8, 0);
    writeU16(&bytes, 10, 7);
    writeCoverage1(&bytes, 12, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expect(
        switch (try contextual.parseContextForValidation(view, 0)) {
            .coverage => true,
            else => false,
        },
    );
    writeU16(&bytes, 8, 1);
    try std.testing.expectError(
        error.BadGpos,
        contextual.parseContextForValidation(view, 0),
    );
    writeU16(&bytes, 2, 0);
    try std.testing.expectError(
        error.BadGpos,
        contextual.parseContextForValidation(view, 0),
    );
}

test "ChainContextPos format 3 exposes all coverage regions" {
    var bytes = [_]u8{0} ** 44;
    writeU16(&bytes, 0, 3);
    writeU16(&bytes, 2, 1);
    writeU16(&bytes, 4, 26);
    writeU16(&bytes, 6, 2);
    writeU16(&bytes, 8, 32);
    writeU16(&bytes, 10, 38);
    writeU16(&bytes, 12, 0);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 9);
    writeCoverage1(&bytes, 26, 4);
    writeCoverage1(&bytes, 32, 5);
    writeCoverage1(&bytes, 38, 6);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const parsed = try contextual.parseChainingForValidation(view, 0);
    const coverage = switch (parsed) {
        .coverage => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u16, 1), coverage.backtrack_coverages.count);
    try std.testing.expectEqual(@as(u16, 2), coverage.input_coverages.count);
    try std.testing.expectEqual(@as(u16, 0), coverage.lookahead_coverages.count);
    try std.testing.expectEqual(@as(usize, 16), coverage.records.records_pos);
    try std.testing.expectEqual(
        @as(usize, 38),
        try coverage.input_coverages.coverageOffset(view, 1),
    );
}

test "chaining rule cursor keeps implicit first input out of payload" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 3);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 2);
    writeU16(&bytes, 8, 7);
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 9);
    writeU16(&bytes, 14, 4);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 1);
    writeU16(&bytes, 20, 8);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    const rule = try contextual.parseChainingRuleForValidation(view, 0);
    try std.testing.expectEqual(@as(u16, 2), rule.backtrack_count);
    try std.testing.expectEqual(@as(usize, 2), rule.backtrack_values_pos);
    try std.testing.expectEqual(@as(u16, 2), rule.input_count);
    try std.testing.expectEqual(@as(usize, 8), rule.input_values_pos);
    try std.testing.expectEqual(@as(usize, 12), rule.lookahead_values_pos);
    try std.testing.expectEqual(@as(usize, 18), rule.records.records_pos);

    writeU16(&bytes, 6, 0);
    try std.testing.expectError(
        error.BadGpos,
        contextual.parseChainingRuleForValidation(view, 0),
    );
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
