//! ContextSubst format-1/2 class accelerator builder contracts.

const std = @import("std");
const build = @import("../../../../accelerator/build/root.zig");
const class_context = @import("../../../../../opentype/class_context.zig");
const class_first = @import("../../../../accelerator/index/class_first.zig");
const ownership = @import("../../../../accelerator/ownership.zig");
const table = @import("../../../../table/root.zig");

test "direct and extension context class builders share first-group indexes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 112;
    writeDirectAndExtensionLookups(&bytes, 32, 5);

    const context = 32;
    writeU16(&bytes, context, 2);
    writeU16(&bytes, context + 2, 30);
    writeU16(&bytes, context + 4, 36);
    writeU16(&bytes, context + 6, 2);
    writeU16(&bytes, context + 8, 0);
    writeU16(&bytes, context + 10, 12);
    const set = context + 12;
    writeU16(&bytes, set, 1);
    writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(&bytes, rule, 1);
    writeU16(&bytes, rule + 2, 0);
    writeCoverage1(&bytes, context + 30, 5);
    writeClassDef1(&bytes, context + 36, 5, 1);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const direct = try build.class_context.context.build(
        view,
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitContextClassSubtables(allocator, direct);
    const extension = try build.class_context.context.build(
        view,
        8,
        1,
        .extension,
        allocator,
    );
    defer ownership.deinitContextClassSubtables(allocator, extension);

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
}

test "context glyph builders preserve arbitrary substitution records" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 144;
    writeDirectAndExtensionLookups(&bytes, 32, 5);

    const context = 32;
    writeU16(&bytes, context, 1);
    writeU16(&bytes, context + 2, 32);
    writeU16(&bytes, context + 4, 1);
    writeU16(&bytes, context + 6, 8);
    const set = context + 8;
    writeU16(&bytes, set, 1);
    writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(&bytes, rule, 2);
    writeU16(&bytes, rule + 2, 2);
    writeU16(&bytes, rule + 4, 7);
    writeU16(&bytes, rule + 6, 0);
    writeU16(&bytes, rule + 8, 3);
    writeU16(&bytes, rule + 10, 1);
    writeU16(&bytes, rule + 12, 4);
    writeCoverage1(&bytes, context + 32, 5);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const direct = try build.class_context.context.build(
        view,
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitContextClassSubtables(allocator, direct);
    const extension = try build.class_context.context.build(
        view,
        8,
        1,
        .extension,
        allocator,
    );
    defer ownership.deinitContextClassSubtables(allocator, extension);

    try std.testing.expectEqual(@as(usize, 1), direct.len);
    try std.testing.expectEqual(@as(usize, 1), extension.len);
    try std.testing.expectEqual(table.class_def.empty_offset, direct[0].class_def);
    try std.testing.expectEqualSlices(
        class_context.Rule,
        direct[0].rules,
        extension[0].rules,
    );
    try std.testing.expectEqual(@as(u16, 2), direct[0].rules[0].subst_count);
    try std.testing.expectEqual(
        @as(u32, @intCast(rule + 6)),
        direct[0].rules[0].records_offset,
    );
    try std.testing.expectEqualSlices(u16, &.{7}, direct[0].classes[0..1]);

    // Overlapping format-2 Coverage records select RuleSets by coverage index,
    // so the exact-glyph index deliberately declines that uncommon topology.
    writeU16(&bytes, context + 32, 2);
    const unsupported = try build.class_context.context.build(
        view,
        0,
        1,
        .direct,
        allocator,
    );
    defer ownership.deinitContextClassSubtables(allocator, unsupported);
    try std.testing.expectEqual(@as(usize, 0), unsupported.len);
}

test "context builder releases partial ownership on every allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildContextWithTwoSubtables,
        .{},
    );
}

fn buildContextWithTwoSubtables(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 96;
    writeU16(&bytes, 0, 5);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 48);
    writeContextGlyphSubtable(&bytes, 10, 1);
    writeContextGlyphSubtable(&bytes, 48, 2);

    const subtables = try build.class_context.context.build(
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
    defer ownership.deinitContextClassSubtables(allocator, subtables);
    try std.testing.expectEqual(@as(usize, 2), subtables.len);
}

fn writeContextGlyphSubtable(
    bytes: []u8,
    offset: usize,
    glyph: u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 18);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 4);
    writeU16(bytes, offset + 12, 1);
    writeU16(bytes, offset + 14, 0);
    writeCoverage1(bytes, offset + 18, glyph);
}

fn writeDirectAndExtensionLookups(
    bytes: []u8,
    payload_offset: u16,
    wrapped_type: u16,
) void {
    writeU16(bytes, 0, wrapped_type);
    writeU16(bytes, 4, 1);
    writeU16(bytes, 6, payload_offset);
    writeU16(bytes, 8, 7);
    writeU16(bytes, 12, 1);
    writeU16(bytes, 14, 8);
    writeU16(bytes, 16, 1);
    writeU16(bytes, 18, wrapped_type);
    writeU32(bytes, 20, payload_offset - 16);
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
