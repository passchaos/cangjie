//! ChainContextSubst format-2 class accelerator builder contracts.

const std = @import("std");
const build = @import("../../../../accelerator/build/root.zig");
const class_context = @import("../../../../../opentype/class_context.zig");
const class_first = @import("../../../../accelerator/index/class_first.zig");
const ownership = @import("../../../../accelerator/ownership.zig");
const shared = @import("../../../../accelerator/build/class_context/shared.zig");
const table = @import("../../../../table/root.zig");

test "sparse chaining shapes retain authored order" {
    const allocator = std.testing.allocator;
    var rules = std.ArrayList(class_context.Rule).empty;
    defer rules.deinit(allocator);
    var groups = std.ArrayList(class_context.RuleGroup).empty;
    defer groups.deinit(allocator);

    // Eight rules make the group eligible for indexing, while four pairs of
    // shapes keep every bucket below the runtime hash threshold. The temporary
    // shape/hash sort must therefore be undone before the linear matcher sees
    // the rules, or overlapping rules can lose OpenType's authored precedence.
    try rules.appendSlice(allocator, &.{
        .{ .class_set = 1, .input_count = 4, .lookahead_count = 0, .hash = 8, .order = 0, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 2, .lookahead_count = 1, .hash = 7, .order = 1, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 3, .lookahead_count = 0, .hash = 6, .order = 2, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 2, .lookahead_count = 0, .hash = 5, .order = 3, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 4, .lookahead_count = 0, .hash = 4, .order = 4, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 2, .lookahead_count = 1, .hash = 3, .order = 5, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 3, .lookahead_count = 0, .hash = 2, .order = 6, .lookup_index = 0, .classes_start = 0 },
        .{ .class_set = 1, .input_count = 2, .lookahead_count = 0, .hash = 1, .order = 7, .lookup_index = 0, .classes_start = 0 },
    });

    try shared.finishChainingRuleGroups(&rules, &groups, allocator);

    try std.testing.expectEqual(@as(usize, 1), groups.items.len);
    try std.testing.expectEqual(@as(usize, 2), groups.items[0].max_shape_len);
    try std.testing.expect(!groups.items[0].hash_sorted);
    for (rules.items, 0..) |rule, index| {
        try std.testing.expectEqual(@as(u32, @intCast(index)), rule.order);
        try std.testing.expectEqual(@as(u16, 0), rule.shape_bucket_len);
    }
}

test "indexed chaining groups retain explicit shape boundaries" {
    const allocator = std.testing.allocator;
    var rules = std.ArrayList(class_context.Rule).empty;
    defer rules.deinit(allocator);
    var groups = std.ArrayList(class_context.RuleGroup).empty;
    defer groups.deinit(allocator);

    for (0..5) |order| {
        try rules.append(allocator, .{
            .class_set = 1,
            .input_count = 2,
            .lookahead_count = 1,
            .hash = @intCast(10 - order),
            .order = @intCast(order),
            .lookup_index = 0,
            .classes_start = 0,
        });
    }
    for (5..8) |order| {
        try rules.append(allocator, .{
            .class_set = 1,
            .input_count = 3,
            .lookahead_count = 0,
            .hash = @intCast(10 - order),
            .order = @intCast(order),
            .lookup_index = 0,
            .classes_start = 0,
        });
    }

    try shared.finishChainingRuleGroups(&rules, &groups, allocator);

    try std.testing.expect(groups.items[0].hash_sorted);
    try std.testing.expectEqual(@as(usize, 5), groups.items[0].max_shape_len);
    try std.testing.expectEqual(@as(u16, 5), rules.items[0].shape_bucket_len);
    try std.testing.expectEqual(@as(u16, 3), rules.items[5].shape_bucket_len);
    for (rules.items[1..5]) |rule| {
        try std.testing.expectEqual(@as(u16, 0), rule.shape_bucket_len);
    }
    for (rules.items[6..]) |rule| {
        try std.testing.expectEqual(@as(u16, 0), rule.shape_bucket_len);
    }
}

test "direct and extension chaining class builders preserve backtrack rules" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    // Direct lookup zero and ExtensionSubst lookup one share the same
    // ChainContextSubst format-2 payload.
    writeU16(&bytes, 0, 6);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 32);
    writeU16(&bytes, 8, 7);
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 8);
    writeU16(&bytes, 16, 1);
    writeU16(&bytes, 18, 6);
    writeU32(&bytes, 20, 16);

    const chain = 32;
    writeU16(&bytes, chain, 2);
    writeU16(&bytes, chain + 2, 44);
    writeU16(&bytes, chain + 4, 66);
    writeU16(&bytes, chain + 6, 50);
    writeU16(&bytes, chain + 8, 58);
    writeU16(&bytes, chain + 10, 2);
    writeU16(&bytes, chain + 12, 0);
    writeU16(&bytes, chain + 14, 16);
    const set = chain + 16;
    writeU16(&bytes, set, 1);
    writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(&bytes, rule, 1);
    writeU16(&bytes, rule + 2, 2);
    writeU16(&bytes, rule + 4, 1);
    writeU16(&bytes, rule + 6, 1);
    writeU16(&bytes, rule + 8, 3);
    writeU16(&bytes, rule + 10, 1);
    writeU16(&bytes, rule + 12, 0);
    writeU16(&bytes, rule + 14, 0);
    writeCoverage1(&bytes, chain + 44, 5);
    writeClassDef1(&bytes, chain + 50, 5, 1);
    writeClassDef1(&bytes, chain + 58, 7, 3);
    writeClassDef1(&bytes, chain + 66, 4, 2);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const direct = try build.class_context.chaining.build(
        view,
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingClassSubtables(allocator, direct);
    const extension = try build.class_context.chaining.build(
        view,
        8,
        1,
        .extension,
        allocator,
    );
    defer ownership.deinitChainingClassSubtables(allocator, extension);

    try std.testing.expectEqual(@as(usize, 1), direct.len);
    try std.testing.expectEqual(@as(usize, 1), extension.len);
    try std.testing.expectEqualSlices(
        class_context.Rule,
        direct[0].rules,
        extension[0].rules,
    );
    try std.testing.expectEqualSlices(u16, direct[0].classes, extension[0].classes);
    try std.testing.expectEqualSlices(
        class_context.RuleGroup,
        direct[0].groups,
        extension[0].groups,
    );
    try std.testing.expectEqual(
        direct[0].first_index_start,
        extension[0].first_index_start,
    );
    try std.testing.expectEqual(
        @as(usize, chain + 66),
        direct[0].backtrack_class_def,
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        direct[0].rules[0].records_offset,
    );
    try std.testing.expectEqual(@as(u16, 1), direct[0].rules[0].backtrack_count);
    try std.testing.expect(!direct[0].rules[0].record_list);
    try std.testing.expectEqualSlices(u16, &.{ 2, 3 }, direct[0].classes[0..2]);
    try std.testing.expectEqualSlices(
        u16,
        &.{ class_first.sorted_encoding, 5, 0 },
        direct[0].classes[direct[0].first_index_start..],
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        (class_first.find(
            direct[0].classes,
            direct[0].first_index_start,
            direct[0].groups,
            5,
        ) orelse return error.TestUnexpectedResult).class_set,
    );
    try std.testing.expect(class_first.find(
        direct[0].classes,
        direct[0].first_index_start,
        direct[0].groups,
        4,
    ) == null);

    // Wider authored record lists retain their table offset instead of
    // falling back to repeated rule parsing. Both direct and extension
    // wrappers must construct the same accelerator representation.
    writeU16(&bytes, rule + 10, 2);
    writeU16(&bytes, rule + 12, 1);
    writeU16(&bytes, rule + 14, 3);
    writeU16(&bytes, rule + 16, 0);
    writeU16(&bytes, rule + 18, 4);
    const direct_multi = try build.class_context.chaining.build(
        view,
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingClassSubtables(allocator, direct_multi);
    const extension_multi = try build.class_context.chaining.build(
        view,
        8,
        1,
        .extension,
        allocator,
    );
    defer ownership.deinitChainingClassSubtables(allocator, extension_multi);
    try std.testing.expectEqual(@as(usize, 1), direct_multi.len);
    try std.testing.expectEqualSlices(
        class_context.Rule,
        direct_multi[0].rules,
        extension_multi[0].rules,
    );
    const multi_rule = direct_multi[0].rules[0];
    try std.testing.expect(multi_rule.record_list);
    try std.testing.expectEqual(@as(u16, 1), multi_rule.backtrack_count);
    try std.testing.expectEqual(@as(u16, 2), multi_rule.subst_count);
    try std.testing.expectEqual(@as(u32, rule + 12), multi_rule.records_offset);
}

test "chaining class builder accepts optional context class definitions" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    writeU16(&bytes, 0, 6);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);

    const chain = 8;
    writeU16(&bytes, chain, 2);
    writeU16(&bytes, chain + 2, 36);
    writeU16(&bytes, chain + 4, 0);
    writeU16(&bytes, chain + 6, 42);
    writeU16(&bytes, chain + 8, 0);
    writeU16(&bytes, chain + 10, 1);
    writeU16(&bytes, chain + 12, 14);
    const set = chain + 14;
    writeU16(&bytes, set, 1);
    writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(&bytes, rule, 0);
    writeU16(&bytes, rule + 2, 1);
    writeU16(&bytes, rule + 4, 0);
    writeU16(&bytes, rule + 6, 1);
    writeU16(&bytes, rule + 8, 0);
    writeU16(&bytes, rule + 10, 0);
    writeCoverage1(&bytes, chain + 36, 5);
    writeClassDef1(&bytes, chain + 42, 5, 0);

    const subtables = try build.class_context.chaining.build(
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingClassSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 1), subtables.len);
    try std.testing.expectEqual(
        table.class_def.empty_offset,
        subtables[0].backtrack_class_def,
    );
    try std.testing.expectEqual(
        table.class_def.empty_offset,
        subtables[0].lookahead_class_def,
    );
}

test "chaining builder releases partial ownership on every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildChainingWithTwoSubtables,
        .{},
    );
}

fn buildChainingWithTwoSubtables(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 128;
    writeU16(&bytes, 0, 6);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 68);
    writeChainingClassSubtable(&bytes, 10, 1);
    writeChainingClassSubtable(&bytes, 68, 2);

    const subtables = try build.class_context.chaining.build(
        .{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        0,
        2,
        .direct,
        allocator,
    );
    defer ownership.deinitChainingClassSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 2), subtables.len);
}

fn writeChainingClassSubtable(
    bytes: []u8,
    offset: usize,
    glyph: u16,
) void {
    writeU16(bytes, offset, 2);
    writeU16(bytes, offset + 2, 30);
    writeU16(bytes, offset + 4, 0);
    writeU16(bytes, offset + 6, 36);
    writeU16(bytes, offset + 8, 0);
    writeU16(bytes, offset + 10, 1);
    writeU16(bytes, offset + 12, 14);
    writeU16(bytes, offset + 14, 1);
    writeU16(bytes, offset + 16, 4);
    writeU16(bytes, offset + 18, 0);
    writeU16(bytes, offset + 20, 1);
    writeU16(bytes, offset + 22, 0);
    writeU16(bytes, offset + 24, 1);
    writeU16(bytes, offset + 26, 0);
    writeU16(bytes, offset + 28, 0);
    writeCoverage1(bytes, offset + 30, glyph);
    writeClassDef1(bytes, offset + 36, glyph, 0);
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

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
