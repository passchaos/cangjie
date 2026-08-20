//! Compact ChainContextSubst format-1 fixtures.

const std = @import("std");
const context_fixture = @import("../../context/fixture.zig");
const table = @import("../../../../../table/root.zig");

pub const Record = struct {
    sequence_index: u16,
    lookup_index: u16,
};

pub const Rule = struct {
    /// Full input glyph sequence. The first glyph is selected by Coverage and
    /// is therefore omitted from the encoded ChainSubRule input array.
    input: []const u16,
    backtrack: []const u16 = &.{},
    lookahead: []const u16 = &.{},
    records: []const Record = &.{},
};

pub fn writeSubtable(
    bytes: []u8,
    base: usize,
    first_glyph: u16,
    rules: []const Rule,
) void {
    const set_offset = base + 8;
    var cursor = set_offset + 2 + rules.len * 2;

    context_fixture.writeU16(bytes, base, 1);
    context_fixture.writeU16(bytes, base + 4, 1);
    context_fixture.writeU16(bytes, base + 6, @intCast(set_offset - base));
    context_fixture.writeU16(bytes, set_offset, @intCast(rules.len));

    for (rules, 0..) |rule, rule_index| {
        std.debug.assert(rule.input.len != 0);
        std.debug.assert(rule.input[0] == first_glyph);
        context_fixture.writeU16(
            bytes,
            set_offset + 2 + rule_index * 2,
            @intCast(cursor - set_offset),
        );
        cursor = writeRule(bytes, cursor, rule);
    }

    context_fixture.writeU16(bytes, base + 2, @intCast(cursor - base));
    context_fixture.writeCoverage1(bytes, cursor, first_glyph);
}

pub fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}

fn writeRule(bytes: []u8, offset: usize, rule: Rule) usize {
    var cursor = offset;
    context_fixture.writeU16(bytes, cursor, @intCast(rule.backtrack.len));
    cursor += 2;
    for (rule.backtrack) |glyph| {
        context_fixture.writeU16(bytes, cursor, glyph);
        cursor += 2;
    }

    context_fixture.writeU16(bytes, cursor, @intCast(rule.input.len));
    cursor += 2;
    for (rule.input[1..]) |glyph| {
        context_fixture.writeU16(bytes, cursor, glyph);
        cursor += 2;
    }

    context_fixture.writeU16(bytes, cursor, @intCast(rule.lookahead.len));
    cursor += 2;
    for (rule.lookahead) |glyph| {
        context_fixture.writeU16(bytes, cursor, glyph);
        cursor += 2;
    }

    context_fixture.writeU16(bytes, cursor, @intCast(rule.records.len));
    cursor += 2;
    for (rule.records) |record| {
        context_fixture.writeRecord(
            bytes,
            cursor,
            record.sequence_index,
            record.lookup_index,
        );
        cursor += 4;
    }
    return cursor;
}
