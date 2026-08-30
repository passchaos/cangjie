//! Chaining-class builder second-input digest contracts.

const std = @import("std");
const build = @import("../../../../accelerator/build/root.zig");
const ownership = @import("../../../../accelerator/ownership.zig");

test "chaining class builder creates group-local second-input digests" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 512;

    const chain = 8;
    writeU16(&bytes, 0, 6);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, chain);
    writeU16(&bytes, chain, 2);
    writeU16(&bytes, chain + 2, 300);
    writeU16(&bytes, chain + 4, 0);
    writeU16(&bytes, chain + 6, 320);
    writeU16(&bytes, chain + 8, 0);
    writeU16(&bytes, chain + 10, 2);
    writeU16(&bytes, chain + 12, 16);
    writeU16(&bytes, chain + 14, 160);

    // Both groups are large and equal-shaped, satisfying the existing
    // profitability proof for indexed matching. Keeping their class sets
    // separate proves that the digest is local to a RuleGroup rather than a
    // coarse summary of the entire subtable.
    // A nonzero backtrack class guards the sidecar layout invariant: the
    // second input follows the entire backtrack prefix in `classes`.
    writeTwoInputRuleSet(&bytes, chain + 16, 4, 1, 8);
    setTwoInputRuleClass(&bytes, chain + 16, 7, 9);
    writeTwoInputRuleSet(&bytes, chain + 160, null, 6, 8);
    writeCoverage1(&bytes, chain + 300, 5);
    writeClassDef1(&bytes, chain + 320, 5, 0);

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
    try std.testing.expectEqual(@as(usize, 2), subtables[0].groups.len);
    try std.testing.expectEqual(
        @as(u8, 1 << 1),
        subtables[0].groups[0].second_input_class_digest,
    );
    try std.testing.expectEqual(
        @as(u8, 1 << 6),
        subtables[0].groups[1].second_input_class_digest,
    );
}

test "second-input class digest collisions remain conservative" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 512;

    const chain = 8;
    writeU16(&bytes, 0, 6);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, chain);
    writeU16(&bytes, chain, 2);
    writeU16(&bytes, chain + 2, 300);
    writeU16(&bytes, chain + 4, 0);
    writeU16(&bytes, chain + 6, 320);
    writeU16(&bytes, chain + 8, 0);
    writeU16(&bytes, chain + 10, 1);
    writeU16(&bytes, chain + 12, 14);
    writeTwoInputRuleSet(&bytes, chain + 14, null, 1, 8);
    writeCoverage1(&bytes, chain + 300, 5);
    writeClassDef1(&bytes, chain + 320, 5, 0);

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

    const digest = subtables[0].groups[0].second_input_class_digest;
    // Classes 1 and 9 intentionally alias in the eight-bit filter. The
    // digest must admit both; exact rule matching remains authoritative.
    try std.testing.expect(classDigestMayHave(digest, 1));
    try std.testing.expect(classDigestMayHave(digest, 9));
    try std.testing.expect(!classDigestMayHave(digest, 2));
}

test "one-input alternative disables second-input class digest" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 512;

    const chain = 8;
    writeU16(&bytes, 0, 6);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, chain);
    writeU16(&bytes, chain, 2);
    writeU16(&bytes, chain + 2, 300);
    writeU16(&bytes, chain + 4, 0);
    writeU16(&bytes, chain + 6, 320);
    writeU16(&bytes, chain + 8, 0);
    writeU16(&bytes, chain + 10, 1);
    writeU16(&bytes, chain + 12, 14);
    writeMixedInputRuleSet(&bytes, chain + 14, 3);
    writeCoverage1(&bytes, chain + 300, 5);
    writeClassDef1(&bytes, chain + 320, 5, 0);

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

    const group = subtables[0].groups[0];
    try std.testing.expect(group.hash_sorted);
    try std.testing.expectEqual(@as(u16, 1), group.min_input_count);
    try std.testing.expectEqual(@as(u8, 0), group.second_input_class_digest);
}

fn writeTwoInputRuleSet(
    bytes: []u8,
    offset: usize,
    backtrack_class: ?u16,
    second_class: u16,
    rule_count: u16,
) void {
    writeU16(bytes, offset, rule_count);
    const rules_start = offset + 2 + @as(usize, rule_count) * 2;
    const rule_size: usize = if (backtrack_class == null) 12 else 14;
    for (0..rule_count) |rule_index| {
        const rule_offset = rules_start + rule_index * rule_size;
        writeU16(bytes, offset + 2 + rule_index * 2, @intCast(rule_offset - offset));
        writeU16(bytes, rule_offset, @intFromBool(backtrack_class != null));
        var cursor = rule_offset + 2;
        if (backtrack_class) |class| {
            writeU16(bytes, cursor, class);
            cursor += 2;
        }
        writeU16(bytes, cursor, 2);
        writeU16(bytes, cursor + 2, second_class);
        writeU16(bytes, cursor + 4, 0);
        writeU16(bytes, cursor + 6, 0);
    }
}

fn setTwoInputRuleClass(
    bytes: []u8,
    set_offset: usize,
    rule_index: usize,
    second_class: u16,
) void {
    const rule_offset = set_offset +
        std.mem.readInt(u16, bytes[set_offset + 2 + rule_index * 2 ..][0..2], .big);
    const backtrack_count = std.mem.readInt(
        u16,
        bytes[rule_offset..][0..2],
        .big,
    );
    writeU16(
        bytes,
        rule_offset + 4 + @as(usize, backtrack_count) * 2,
        second_class,
    );
}

fn writeMixedInputRuleSet(
    bytes: []u8,
    offset: usize,
    second_class: u16,
) void {
    const rule_count: u16 = 8;
    writeU16(bytes, offset, rule_count);
    const rules_start = offset + 2 + @as(usize, rule_count) * 2;
    for (0..rule_count) |rule_index| {
        const one_input = rule_index == 0;
        const rule_offset = rules_start + if (one_input)
            0
        else
            10 + (rule_index - 1) * 12;
        writeU16(bytes, offset + 2 + rule_index * 2, @intCast(rule_offset - offset));
        writeU16(bytes, rule_offset, 0);
        writeU16(bytes, rule_offset + 2, if (one_input) 1 else 2);
        var cursor = rule_offset + 4;
        if (!one_input) {
            writeU16(bytes, cursor, second_class);
            cursor += 2;
        }
        writeU16(bytes, cursor, 0);
        writeU16(bytes, cursor + 2, 0);
    }
}

fn classDigestMayHave(digest: u8, class: u16) bool {
    const bit: u3 = @truncate(class);
    return (digest & (@as(u8, 1) << bit)) != 0;
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
