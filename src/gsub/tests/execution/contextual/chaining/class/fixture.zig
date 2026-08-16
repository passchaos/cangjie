//! Compact ChainContextSubst format-2 class fixtures.

const std = @import("std");
const base_fixture = @import("../../context/fixture.zig");
const table = @import("../../../../../table/root.zig");

pub const ClassMap = struct {
    start: u16,
    values: []const u16,
};

pub const Record = struct {
    sequence_index: u16,
    lookup_index: u16,
};

pub const Rule = struct {
    backtrack: []const u16 = &.{},
    /// Includes the first input class selected by ChainSubClassSet.
    input: []const u16,
    lookahead: []const u16 = &.{},
    records: []const Record,
};

pub fn writeLookupWithSubtable(
    bytes: []u8,
    first_glyph: u16,
    backtrack_map: ?ClassMap,
    input_map: ClassMap,
    lookahead_map: ?ClassMap,
    rules: []const Rule,
) usize {
    const subtable = 8;
    base_fixture.writeLookup(bytes, 6, &.{8});
    writeSubtable(
        bytes,
        subtable,
        first_glyph,
        backtrack_map,
        input_map,
        lookahead_map,
        rules,
    );
    return subtable;
}

pub fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}

fn writeSubtable(
    bytes: []u8,
    base: usize,
    first_glyph: u16,
    backtrack_map: ?ClassMap,
    input_map: ClassMap,
    lookahead_map: ?ClassMap,
    rules: []const Rule,
) void {
    std.debug.assert(rules.len != 0);
    const first_class = classForGlyph(input_map, first_glyph);
    for (rules) |rule| {
        std.debug.assert(rule.input.len != 0);
        std.debug.assert(rule.input[0] == first_class);
    }

    const set_count = @as(usize, first_class) + 1;
    const set = base + 12 + set_count * 2;
    var cursor = set + 2 + rules.len * 2;
    base_fixture.writeU16(bytes, base, 2);
    base_fixture.writeU16(bytes, base + 10, @intCast(set_count));
    for (0..set_count) |index| {
        base_fixture.writeU16(bytes, base + 12 + index * 2, 0);
    }
    base_fixture.writeU16(
        bytes,
        base + 12 + @as(usize, first_class) * 2,
        @intCast(set - base),
    );
    base_fixture.writeU16(bytes, set, @intCast(rules.len));

    for (rules, 0..) |rule, rule_index| {
        base_fixture.writeU16(
            bytes,
            set + 2 + rule_index * 2,
            @intCast(cursor - set),
        );
        cursor = writeRule(bytes, cursor, rule);
    }

    base_fixture.writeU16(bytes, base + 2, @intCast(cursor - base));
    base_fixture.writeCoverage1(bytes, cursor, first_glyph);
    cursor += 6;
    cursor = writeOptionalClassMap(bytes, base, base + 4, cursor, backtrack_map);
    cursor = writeClassMap(bytes, base, base + 6, cursor, input_map);
    _ = writeOptionalClassMap(
        bytes,
        base,
        base + 8,
        cursor,
        lookahead_map,
    );
}

fn writeRule(bytes: []u8, offset: usize, rule: Rule) usize {
    var cursor = offset;
    base_fixture.writeU16(bytes, cursor, @intCast(rule.backtrack.len));
    cursor += 2;
    cursor = writeValues(bytes, cursor, rule.backtrack);
    base_fixture.writeU16(bytes, cursor, @intCast(rule.input.len));
    cursor += 2;
    cursor = writeValues(bytes, cursor, rule.input[1..]);
    base_fixture.writeU16(bytes, cursor, @intCast(rule.lookahead.len));
    cursor += 2;
    cursor = writeValues(bytes, cursor, rule.lookahead);
    base_fixture.writeU16(bytes, cursor, @intCast(rule.records.len));
    cursor += 2;
    for (rule.records) |record| {
        base_fixture.writeRecord(
            bytes,
            cursor,
            record.sequence_index,
            record.lookup_index,
        );
        cursor += 4;
    }
    return cursor;
}

fn writeValues(bytes: []u8, offset: usize, values: []const u16) usize {
    var cursor = offset;
    for (values) |value| {
        base_fixture.writeU16(bytes, cursor, value);
        cursor += 2;
    }
    return cursor;
}

fn writeOptionalClassMap(
    bytes: []u8,
    base: usize,
    field: usize,
    cursor: usize,
    class_map: ?ClassMap,
) usize {
    const map = class_map orelse {
        base_fixture.writeU16(bytes, field, 0);
        return cursor;
    };
    return writeClassMap(bytes, base, field, cursor, map);
}

fn writeClassMap(
    bytes: []u8,
    base: usize,
    field: usize,
    cursor: usize,
    class_map: ClassMap,
) usize {
    base_fixture.writeU16(bytes, field, @intCast(cursor - base));
    base_fixture.writeClassDef1(
        bytes,
        cursor,
        class_map.start,
        class_map.values,
    );
    return cursor + 6 + class_map.values.len * 2;
}

fn classForGlyph(class_map: ClassMap, glyph: u16) u16 {
    if (glyph < class_map.start) return 0;
    const index = @as(usize, glyph - class_map.start);
    if (index >= class_map.values.len) return 0;
    return class_map.values[index];
}
