//! Contextual first-glyph compact-index contracts.

const std = @import("std");
const class_first = @import("../../../accelerator/index/class_first.zig");
const class_context = @import("../../../../opentype/class_context.zig");

test "class first index deduplicates overlap and skips absent groups" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;
    // Coverage format 2 overlaps at glyph 11.
    writeU16(&bytes, 0, 2);
    writeU16(&bytes, 2, 2);
    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 11);
    writeU16(&bytes, 8, 0);
    writeU16(&bytes, 10, 11);
    writeU16(&bytes, 12, 12);
    writeU16(&bytes, 14, 2);
    // Class 2 has a group; class 3 remains an exact miss.
    writeU16(&bytes, 20, 1);
    writeU16(&bytes, 22, 10);
    writeU16(&bytes, 24, 3);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 2);
    writeU16(&bytes, 30, 3);

    const groups = [_]class_context.RuleGroup{group(2, 0)};
    var classes = std.ArrayList(u16).empty;
    defer classes.deinit(allocator);
    const start = try class_first.appendClassIndex(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, 20, &groups, &classes, allocator);

    try std.testing.expectEqual(@as(u16, 2), class_first.find(
        classes.items,
        start,
        &groups,
        10,
    ).?.class_set);
    try std.testing.expectEqual(@as(u16, 2), class_first.find(
        classes.items,
        start,
        &groups,
        11,
    ).?.class_set);
    try std.testing.expect(class_first.find(
        classes.items,
        start,
        &groups,
        12,
    ) == null);
}

test "class first hash preserves exact hits and misses" {
    const allocator = std.testing.allocator;
    var entries: [class_first.min_entries_for_hash]class_first.Entry = undefined;
    var groups: [class_first.min_entries_for_hash]class_context.RuleGroup =
        undefined;
    for (&entries, &groups, 0..) |*entry, *item, index| {
        entry.* = .{
            .glyph = @intCast(10 + index * 17),
            .group_index = @intCast(index),
        };
        item.* = group(@intCast(20 + index), index);
    }
    var classes = std.ArrayList(u16).empty;
    defer classes.deinit(allocator);
    const start = try class_first.appendPrepared(
        &entries,
        &classes,
        allocator,
    );

    for (entries, 0..) |entry, index| {
        try std.testing.expectEqual(
            @as(u16, @intCast(20 + index)),
            class_first.find(
                classes.items,
                start,
                &groups,
                entry.glyph,
            ).?.class_set,
        );
    }
    try std.testing.expect(class_first.find(
        classes.items,
        start,
        &groups,
        9,
    ) == null);
    try std.testing.expect(class_first.find(
        classes.items,
        start,
        &groups,
        0xffff,
    ) == null);
}

fn group(class_set: u16, start: usize) class_context.RuleGroup {
    return .{
        .class_set = class_set,
        .start = start,
        .len = 1,
        .max_input_count = 1,
        .max_lookahead_count = 0,
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
