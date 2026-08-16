//! GSUB ScriptList and LangSys selection contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const table = @import("../../table/root.zig");
const unicode = @import("../../../unicode.zig");

test "Script selection keeps first duplicate and falls back to DFLT" {
    var bytes = [_]u8{0} ** 64;
    writeU16(&bytes, 0, 3);
    writeU32(&bytes, 2, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(&bytes, 6, 20);
    writeU32(&bytes, 8, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16(&bytes, 12, 24);
    writeU32(&bytes, 14, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16(&bytes, 18, 28);

    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(?usize, 24),
        try feature.selection.script(view, 0, .latn),
    );
    try std.testing.expectEqual(
        @as(?usize, 20),
        try feature.selection.script(view, 0, .arab),
    );
}

test "LangSys selection prefers requested language and rejects duplicates" {
    var bytes = [_]u8{0} ** 48;
    writeU16(&bytes, 0, 16); // DefaultLangSys.
    writeU16(&bytes, 2, 2);
    writeU32(&bytes, 4, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16(&bytes, 8, 24);
    writeU32(&bytes, 10, @intFromEnum(unicode.OpenTypeLanguageTag.zhs));
    writeU16(&bytes, 14, 32);

    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(
        @as(?usize, 24),
        try feature.selection.languageSystem(view, 0, .jan),
    );
    try std.testing.expectEqual(
        @as(?usize, 16),
        try feature.selection.languageSystem(view, 0, .ara),
    );

    writeU32(&bytes, 10, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    try std.testing.expectError(
        error.BadGsub,
        feature.selection.languageSystem(view, 0, .jan),
    );
}

test "LangSys collection merges required duplicates in fixed storage" {
    var bytes = [_]u8{0} ** 144;
    writeU16(&bytes, 0, 0);
    writeU16(&bytes, 2, 7);
    writeU16(&bytes, 4, 3);
    writeU16(&bytes, 6, 7);
    writeU16(&bytes, 8, 9);
    writeU16(&bytes, 10, 9);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    var stack: [64]feature.selection.Item = undefined;
    var stack_len: usize = 0;
    var owned = std.ArrayList(feature.selection.Item).empty;
    defer owned.deinit(std.testing.allocator);
    try feature.selection.collectLanguageStackFirst(
        view,
        0,
        &stack,
        &stack_len,
        &owned,
        std.testing.allocator,
    );
    try std.testing.expectEqual(@as(usize, 0), owned.items.len);
    try std.testing.expectEqualSlices(
        feature.selection.Item,
        &.{
            .{ .index = 7, .required = true },
            .{ .index = 9 },
        },
        stack[0..stack_len],
    );
}

test "LangSys collection falls back to owned storage without truncation" {
    var bytes = [_]u8{0} ** 144;
    writeU16(&bytes, 2, 0xffff);
    writeU16(&bytes, 4, 65);
    for (0..65) |index| writeU16(&bytes, 6 + index * 2, @intCast(index));
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    var stack: [64]feature.selection.Item = undefined;
    var stack_len: usize = 0;
    var owned = std.ArrayList(feature.selection.Item).empty;
    defer owned.deinit(std.testing.allocator);
    try feature.selection.collectLanguageStackFirst(
        view,
        0,
        &stack,
        &stack_len,
        &owned,
        std.testing.allocator,
    );
    try std.testing.expectEqual(@as(usize, 0), stack_len);
    try std.testing.expectEqual(@as(usize, 65), owned.items.len);
    try std.testing.expectEqual(@as(u16, 64), owned.items[64].index);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
