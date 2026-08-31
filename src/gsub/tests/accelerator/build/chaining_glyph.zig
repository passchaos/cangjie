//! Bounded ChainContextSubst format-1 accelerator builder contracts.

const std = @import("std");
const build = @import("../../../accelerator/build/root.zig");
const ownership = @import("../../../accelerator/ownership.zig");
const table = @import("../../../table/root.zig");

test "chaining glyph builder preserves subtable order and zero glyphs" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 192;
    writeDirectLookup(&bytes, 0, &.{ 10, 96 });
    writeSparseThreeSetSubtable(
        &bytes,
        10,
        .{
            .second = 0,
            .lookahead = 0,
            .nested_lookup = 4,
        },
        .{
            .second = 10,
            .nested_lookup = 6,
        },
    );
    writeOneSetSubtable(&bytes, 96, 3, .{
        .second = 7,
        .nested_lookup = 8,
    });

    const subtables = try build.chaining_glyph.build(
        view(&bytes),
        0,
        2,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingGlyphSubtables(allocator, subtables);

    try std.testing.expectEqual(@as(usize, 2), subtables.len);
    try std.testing.expectEqual(@as(usize, 10), subtables[0].subtable_offset);
    try std.testing.expectEqual(@as(usize, 96), subtables[1].subtable_offset);

    // Coverage contains first glyphs 0 and 9. Its middle RuleSet is null, so
    // no entry exists for glyph 5. Optional lookahead keeps glyph zero
    // distinct from the absent lookahead on the second subtable.
    try std.testing.expect(subtables[0].find(5) == null);
    const zero = subtables[0].find(0) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 0), zero.first);
    try std.testing.expectEqual(@as(u16, 0), zero.second);
    try std.testing.expectEqual(@as(?u16, 0), zero.lookahead);
    try std.testing.expectEqual(@as(u16, 4), zero.nested_lookup);
    const nine = subtables[0].find(9) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 10), nine.second);
    try std.testing.expectEqual(@as(?u16, null), nine.lookahead);
    try std.testing.expectEqual(@as(u16, 6), nine.nested_lookup);
    const later = subtables[1].find(3) orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(?u16, null), later.lookahead);
    try std.testing.expectEqual(@as(u16, 8), later.nested_lookup);
}

test "lookup builder installs direct and extension chaining glyph sidecars" {
    const allocator = std.testing.allocator;

    var direct_bytes = [_]u8{0} ** 80;
    writeDirectLookup(&direct_bytes, 0, &.{8});
    writeOneSetSubtable(&direct_bytes, 8, 1, .{
        .second = 2,
        .nested_lookup = 3,
    });
    const direct = try build.lookup.one(view(&direct_bytes), 0, allocator);
    defer ownership.deinitContents(allocator, &.{direct});
    try std.testing.expectEqual(@as(usize, 1), direct.chaining_glyph_subtables.len);
    try std.testing.expectEqual(@as(u16, 3), direct.chaining_glyph_subtables[0].find(1).?.nested_lookup);

    var extension_bytes = [_]u8{0} ** 96;
    writeExtensionLookup(&extension_bytes, 0, &.{8}, &.{24});
    writeOneSetSubtable(&extension_bytes, 24, 4, .{
        .second = 5,
        .nested_lookup = 6,
    });
    const extension = try build.lookup.one(
        view(&extension_bytes),
        0,
        allocator,
    );
    defer ownership.deinitContents(allocator, &.{extension});
    try std.testing.expectEqual(@as(?u16, 6), extension.extension_lookup_type);
    try std.testing.expectEqual(
        @as(usize, 1),
        extension.chaining_glyph_subtables.len,
    );
    try std.testing.expectEqual(
        @as(u16, 6),
        extension.chaining_glyph_subtables[0].find(4).?.nested_lookup,
    );
}

test "chaining glyph builder supports homogeneous extension wrappers" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 192;
    writeExtensionLookup(&bytes, 0, &.{ 10, 104 }, &.{ 32, 120 });
    writeOneSetSubtable(&bytes, 32, 12, .{
        .second = 13,
        .nested_lookup = 2,
    });
    writeOneSetSubtable(&bytes, 120, 14, .{
        .second = 15,
        .lookahead = 16,
        .nested_lookup = 3,
    });

    const subtables = try build.chaining_glyph.build(
        view(&bytes),
        0,
        2,
        .extension,
        allocator,
    );
    defer ownership.deinitChainingGlyphSubtables(allocator, subtables);

    try std.testing.expectEqual(@as(usize, 2), subtables.len);
    try std.testing.expectEqual(@as(usize, 32), subtables[0].subtable_offset);
    try std.testing.expectEqual(@as(usize, 120), subtables[1].subtable_offset);
    try std.testing.expectEqual(@as(u16, 2), subtables[0].find(12).?.nested_lookup);
    try std.testing.expectEqual(@as(?u16, 16), subtables[1].find(14).?.lookahead);
}

test "chaining glyph builder supports nonoverlapping format two coverage" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 256;
    writeDirectLookup(&bytes, 0, &.{8});

    // Three contiguous RuleSets are selected by two disjoint Coverage ranges,
    // matching the representation used by the production Devanagari lookup.
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 180);
    writeU16(&bytes, 12, 3);
    writeU16(&bytes, 14, 12);
    writeU16(&bytes, 16, 30);
    writeU16(&bytes, 18, 48);
    var cursor: usize = 20;
    inline for (.{
        Rule{ .second = 7, .nested_lookup = 1 },
        Rule{ .second = 8, .nested_lookup = 2 },
        Rule{ .second = 9, .nested_lookup = 3 },
    }, .{ @as(usize, 20), @as(usize, 38), @as(usize, 56) }) |rule, set| {
        cursor = set + 4;
        writeU16(&bytes, set, 1);
        writeU16(&bytes, set + 2, 4);
        _ = writeRule(&bytes, cursor, rule);
    }
    const coverage: usize = 188;
    writeU16(&bytes, coverage, 2);
    writeU16(&bytes, coverage + 2, 2);
    writeCoverageRange(&bytes, coverage + 4, 10, 11, 0);
    writeCoverageRange(&bytes, coverage + 10, 20, 20, 2);

    const subtables = try build.chaining_glyph.build(
        view(&bytes),
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingGlyphSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 1), subtables.len);
    try std.testing.expectEqual(@as(u16, 1), subtables[0].find(10).?.nested_lookup);
    try std.testing.expectEqual(@as(u16, 2), subtables[0].find(11).?.nested_lookup);
    try std.testing.expectEqual(@as(u16, 3), subtables[0].find(20).?.nested_lookup);
}

test "chaining glyph builder rejects a lookup when any subtable is unsupported" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 160;
    writeDirectLookup(&bytes, 0, &.{ 10, 96 });
    writeOneSetSubtable(&bytes, 10, 1, .{
        .second = 2,
        .nested_lookup = 3,
    });
    writeOneSetSubtable(&bytes, 96, 4, .{
        .second = 5,
        .nested_lookup = 6,
    });
    writeU16(&bytes, 96, 2);

    const subtables = try build.chaining_glyph.build(
        view(&bytes),
        0,
        2,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingGlyphSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 0), subtables.len);

    // Lookup orchestration must not expose the successfully decoded first
    // subtable: accelerated execution owns the whole lookup or none of it.
    const lookup = try build.lookup.one(view(&bytes), 0, allocator);
    defer ownership.deinitContents(allocator, &.{lookup});
    try std.testing.expectEqual(
        @as(usize, 0),
        lookup.chaining_glyph_subtables.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        lookup.chaining_class_subtables.len,
    );
    try std.testing.expect(!lookup.chaining_coverage_only);
}

test "chaining glyph builder declines every out-of-contract rule shape" {
    const allocator = std.testing.allocator;
    const unsupported = [_]RuleShape{
        .{ .rule_count = 2 },
        .{ .backtrack_count = 1 },
        .{ .input_count = 3 },
        .{ .lookahead_count = 2 },
        .{ .subst_count = 2 },
        .{ .sequence_index = 1 },
    };

    for (unsupported) |shape| {
        var bytes = [_]u8{0} ** 192;
        writeDirectLookup(&bytes, 0, &.{8});
        writeOneSetSubtableShape(&bytes, 8, 1, shape);
        const subtables = try build.chaining_glyph.build(
            view(&bytes),
            0,
            1,
            .direct,
            allocator,
        );
        defer ownership.deinitChainingGlyphSubtables(allocator, subtables);
        try std.testing.expectEqual(@as(usize, 0), subtables.len);
    }
}

test "chaining glyph builder rejects truncated unsupported rule shapes" {
    const allocator = std.testing.allocator;
    const Case = struct {
        shape: RuleShape,
        length: usize,
    };
    const cases = [_]Case{
        // Each fixture keeps the parent Coverage complete and truncates the
        // variable structure selected by an unsupported count or record.
        .{ .shape = .{ .rule_count = 2 }, .length = 26 },
        .{ .shape = .{ .backtrack_count = 1 }, .length = 30 },
        .{ .shape = .{ .input_count = 3 }, .length = 32 },
        .{ .shape = .{ .lookahead_count = 2 }, .length = 36 },
        .{ .shape = .{ .subst_count = 2 }, .length = 40 },
        .{ .shape = .{ .sequence_index = 1 }, .length = 40 },
    };

    for (cases) |case| {
        var bytes = [_]u8{0} ** 64;
        writeDirectLookup(&bytes, 0, &.{8});
        writeTruncatedUnsupportedSubtable(&bytes, 8, case.shape);
        try std.testing.expectError(
            error.BadGsub,
            build.chaining_glyph.build(
                view(bytes[0..case.length]),
                0,
                1,
                .direct,
                allocator,
            ),
        );
    }
}

test "chaining glyph builder scans every rule after a capability miss" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeDirectLookup(&bytes, 0, &.{8});

    // The RuleSet's second rule makes its count unsupported. Its first rule
    // is complete, but its second rule ends after a nonzero backtrack count.
    // Returning fallback at either capability check would hide the truncation.
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 8);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 14);
    writeCoverage1(&bytes, 16, &.{1});
    writeU16(&bytes, 22, 2);
    writeU16(&bytes, 24, 6);
    writeU16(&bytes, 26, 20);
    _ = writeRule(&bytes, 28, .{
        .second = 2,
        .nested_lookup = 3,
    });
    writeU16(&bytes, 42, 1);

    try std.testing.expectError(
        error.BadGsub,
        build.chaining_glyph.build(
            view(bytes[0..44]),
            0,
            1,
            .direct,
            allocator,
        ),
    );
}

test "extension chaining glyph builder rejects a truncated unsupported record" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    writeExtensionLookup(&bytes, 0, &.{8}, &.{24});
    writeTruncatedUnsupportedSubtable(
        &bytes,
        24,
        .{ .subst_count = 2 },
    );

    // Both records are required by the unsupported count, but the view ends
    // after the second SequenceIndex and omits its LookupListIndex.
    const truncated = view(bytes[0..60]);
    try std.testing.expectError(
        error.BadGsub,
        build.chaining_glyph.build(
            truncated,
            0,
            1,
            .extension,
            allocator,
        ),
    );
    try std.testing.expectError(
        error.BadGsub,
        build.lookup.one(truncated, 0, allocator),
    );
}

test "unsupported subtable does not hide malformed later subtable" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    writeDirectLookup(&bytes, 0, &.{ 10, 80 });
    writeOneSetSubtableShape(&bytes, 10, 1, .{ .input_count = 3 });
    // The second subtable's fixed header itself is truncated. A first-pass
    // capability miss must not stop the structural scan before reaching it.
    try std.testing.expectError(
        error.BadGsub,
        build.chaining_glyph.build(
            .{ .data = &bytes, .offset = 0, .length = 81 },
            0,
            2,
            .direct,
            allocator,
        ),
    );
}

test "chaining glyph builder rejects overlapping coverage mappings" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;
    writeDirectLookup(&bytes, 0, &.{8});
    writeOneSetSubtable(&bytes, 8, 5, .{
        .second = 6,
        .nested_lookup = 7,
    });
    const coverage = 34;
    writeU16(&bytes, 10, coverage - 8);
    writeU16(&bytes, coverage, 2);
    writeU16(&bytes, coverage + 2, 2);
    writeCoverageRange(&bytes, coverage + 4, 5, 6, 0);
    writeCoverageRange(&bytes, coverage + 10, 6, 7, 2);

    const subtables = try build.chaining_glyph.build(
        view(&bytes),
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingGlyphSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 0), subtables.len);
}

test "chaining glyph builder releases partial ownership on every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildTwoSubtables,
        .{},
    );
}

fn buildTwoSubtables(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 160;
    writeDirectLookup(&bytes, 0, &.{ 10, 88 });
    writeOneSetSubtable(&bytes, 10, 1, .{
        .second = 2,
        .nested_lookup = 3,
    });
    writeOneSetSubtable(&bytes, 88, 4, .{
        .second = 5,
        .lookahead = 6,
        .nested_lookup = 7,
    });
    const subtables = try build.chaining_glyph.build(
        view(&bytes),
        0,
        2,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingGlyphSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 2), subtables.len);
}

const Rule = struct {
    second: u16,
    lookahead: ?u16 = null,
    nested_lookup: u16,
};

const RuleShape = struct {
    rule_count: u16 = 1,
    backtrack_count: u16 = 0,
    input_count: u16 = 2,
    lookahead_count: u16 = 0,
    subst_count: u16 = 1,
    sequence_index: u16 = 0,
};

fn writeDirectLookup(bytes: []u8, offset: usize, subtables: []const u16) void {
    writeU16(bytes, offset, 6);
    writeU16(bytes, offset + 4, @intCast(subtables.len));
    for (subtables, 0..) |subtable, index| {
        writeU16(bytes, offset + 6 + index * 2, subtable - @as(u16, @intCast(offset)));
    }
}

fn writeExtensionLookup(
    bytes: []u8,
    offset: usize,
    wrappers: []const u16,
    payloads: []const u16,
) void {
    writeU16(bytes, offset, 7);
    writeU16(bytes, offset + 4, @intCast(wrappers.len));
    for (wrappers, payloads, 0..) |wrapper, payload, index| {
        writeU16(bytes, offset + 6 + index * 2, wrapper - @as(u16, @intCast(offset)));
        writeU16(bytes, wrapper, 1);
        writeU16(bytes, wrapper + 2, 6);
        writeU32(bytes, wrapper + 4, payload - wrapper);
    }
}

fn writeOneSetSubtable(
    bytes: []u8,
    offset: usize,
    first: u16,
    rule: Rule,
) void {
    const set = offset + 8;
    const rule_offset = set + 4;
    const coverage = writeRule(bytes, rule_offset, rule);
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(coverage - offset));
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, @intCast(set - offset));
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, @intCast(rule_offset - set));
    writeCoverage1(bytes, coverage, &.{first});
}

fn writeOneSetSubtableShape(
    bytes: []u8,
    offset: usize,
    first: u16,
    shape: RuleShape,
) void {
    const set = offset + 8;
    var cursor = set + 2 + @as(usize, shape.rule_count) * 2;
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, @intCast(set - offset));
    writeU16(bytes, set, shape.rule_count);

    for (0..shape.rule_count) |rule_index| {
        writeU16(
            bytes,
            set + 2 + rule_index * 2,
            @intCast(cursor - set),
        );
        cursor = writeRuleShape(bytes, cursor, shape);
    }
    writeU16(bytes, offset + 2, @intCast(cursor - offset));
    writeCoverage1(bytes, cursor, &.{first});
}

fn writeTruncatedUnsupportedSubtable(
    bytes: []u8,
    offset: usize,
    shape: RuleShape,
) void {
    // Keep Coverage before the variable rule data so clipping the View cannot
    // accidentally make the supported parent object the source of failure.
    const coverage = offset + 8;
    const set = coverage + 6;
    const rule = set + 6;
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(coverage - offset));
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, @intCast(set - offset));
    writeCoverage1(bytes, coverage, &.{1});
    writeU16(bytes, set, shape.rule_count);
    writeU16(bytes, set + 2, @intCast(rule - set));
    if (shape.rule_count > 1) {
        // The second required offset itself is truncated by that fixture.
        writeU16(bytes, set + 4, @intCast(rule - set));
    }

    var cursor = rule;
    writeU16(bytes, cursor, shape.backtrack_count);
    cursor += 2;
    for (0..shape.backtrack_count) |index| {
        writeU16(bytes, cursor, @intCast(20 + index));
        cursor += 2;
    }
    writeU16(bytes, cursor, shape.input_count);
    cursor += 2;
    for (1..shape.input_count) |index| {
        writeU16(bytes, cursor, @intCast(30 + index));
        cursor += 2;
    }
    writeU16(bytes, cursor, shape.lookahead_count);
    cursor += 2;
    for (0..shape.lookahead_count) |index| {
        writeU16(bytes, cursor, @intCast(40 + index));
        cursor += 2;
    }
    writeU16(bytes, cursor, shape.subst_count);
    cursor += 2;
    for (0..shape.subst_count) |index| {
        writeU16(bytes, cursor, if (index == 0) shape.sequence_index else 0);
        writeU16(bytes, cursor + 2, @intCast(50 + index));
        cursor += 4;
    }
}

fn writeRuleShape(bytes: []u8, offset: usize, shape: RuleShape) usize {
    var cursor = offset;
    writeU16(bytes, cursor, shape.backtrack_count);
    cursor += 2;
    for (0..shape.backtrack_count) |index| {
        writeU16(bytes, cursor, @intCast(20 + index));
        cursor += 2;
    }

    writeU16(bytes, cursor, shape.input_count);
    cursor += 2;
    for (1..shape.input_count) |index| {
        writeU16(bytes, cursor, @intCast(30 + index));
        cursor += 2;
    }

    writeU16(bytes, cursor, shape.lookahead_count);
    cursor += 2;
    for (0..shape.lookahead_count) |index| {
        writeU16(bytes, cursor, @intCast(40 + index));
        cursor += 2;
    }

    writeU16(bytes, cursor, shape.subst_count);
    cursor += 2;
    for (0..shape.subst_count) |index| {
        writeU16(bytes, cursor, if (index == 0) shape.sequence_index else 0);
        writeU16(bytes, cursor + 2, @intCast(50 + index));
        cursor += 4;
    }
    return cursor;
}

fn writeSparseThreeSetSubtable(
    bytes: []u8,
    offset: usize,
    first_rule_value: Rule,
    last_rule_value: Rule,
) void {
    const first_set = offset + 12;
    const first_rule = first_set + 4;
    const last_set = writeRule(bytes, first_rule, first_rule_value);
    const last_rule = last_set + 4;
    const coverage = writeRule(bytes, last_rule, last_rule_value);
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(coverage - offset));
    writeU16(bytes, offset + 4, 3);
    writeU16(bytes, offset + 6, @intCast(first_set - offset));
    writeU16(bytes, offset + 8, 0);
    writeU16(bytes, offset + 10, @intCast(last_set - offset));
    writeU16(bytes, first_set, 1);
    writeU16(bytes, first_set + 2, @intCast(first_rule - first_set));
    writeU16(bytes, last_set, 1);
    writeU16(bytes, last_set + 2, @intCast(last_rule - last_set));
    writeCoverage1(bytes, coverage, &.{ 0, 5, 9 });
}

fn writeRule(bytes: []u8, offset: usize, rule: Rule) usize {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 2);
    writeU16(bytes, offset + 4, rule.second);
    writeU16(bytes, offset + 6, if (rule.lookahead == null) 0 else 1);
    var cursor = offset + 8;
    if (rule.lookahead) |lookahead| {
        writeU16(bytes, cursor, lookahead);
        cursor += 2;
    }
    writeU16(bytes, cursor, 1);
    writeU16(bytes, cursor + 2, 0);
    writeU16(bytes, cursor + 4, rule.nested_lookup);
    return cursor + 6;
}

fn writeCoverage1(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
}

fn writeCoverageRange(
    bytes: []u8,
    offset: usize,
    start: u16,
    end: u16,
    start_index: u16,
) void {
    writeU16(bytes, offset, start);
    writeU16(bytes, offset + 2, end);
    writeU16(bytes, offset + 4, start_index);
}

fn view(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
