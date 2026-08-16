//! GPOS feature-selection contracts independent of lookup execution.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const table = @import("../../table/root.zig");
const unicode = @import("../../../unicode.zig");

test "GPOS selection keeps required features and preserves authored lookups" {
    var bytes = [_]u8{0} ** 72;
    writeRequiredFeatureTable(
        &bytes,
        unicode.tag("kern"),
        unicode.tag("mark"),
    );
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    var lookups = try feature.selection.lookupIndices(
        view,
        std.testing.allocator,
        .{
            .overrides = &.{
                .{ .tag = unicode.tag("kern"), .enabled = false },
                .{ .tag = unicode.tag("mark"), .enabled = false },
            },
        },
    );
    defer lookups.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, &.{0}, lookups.items);
}

test "GPOS selection falls back to DFLT and validates language ordering" {
    var bytes = [_]u8{0} ** 64;
    writeU16(&bytes, 0, 3);
    writeU32(&bytes, 2, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(&bytes, 6, 20);
    writeU32(&bytes, 8, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16(&bytes, 12, 24);
    writeU32(&bytes, 14, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16(&bytes, 18, 28);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    try std.testing.expectEqual(
        @as(?usize, 24),
        try feature.selection.script(view, 0, .latn),
    );
    try std.testing.expectEqual(
        @as(?usize, 20),
        try feature.selection.script(view, 0, .arab),
    );

    @memset(&bytes, 0);
    writeU16(&bytes, 0, 16);
    writeU16(&bytes, 2, 2);
    writeU32(&bytes, 4, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16(&bytes, 8, 24);
    writeU32(&bytes, 10, @intFromEnum(unicode.OpenTypeLanguageTag.zhs));
    writeU16(&bytes, 14, 32);
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
        error.BadGpos,
        feature.selection.languageSystem(view, 0, .jan),
    );
}

test "GPOS feature defaults distinguish shaping features from opt-in tags" {
    try std.testing.expect(
        feature.selection.enabled(unicode.tag("kern"), &.{}),
    );
    try std.testing.expect(
        feature.selection.enabled(unicode.tag("mark"), &.{}),
    );
    try std.testing.expect(
        !feature.selection.enabled(unicode.tag("ordn"), &.{}),
    );
    try std.testing.expect(
        feature.selection.enabled(
            unicode.tag("ordn"),
            &.{.{ .tag = unicode.tag("ordn"), .enabled = true }},
        ),
    );
}

test "GPOS run selection sorts and deduplicates active lookups" {
    var bytes = [_]u8{0} ** 78;
    writeRepeatedLookupTable(&bytes, unicode.tag("kern"));
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var lookups = try feature.run_selection.lookupIndices(
        view,
        std.testing.allocator,
        .{ .script_tag = .dflt },
    );
    defer lookups.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, lookups.items);

    writeRepeatedLookupTable(&bytes, unicode.tag("ordn"));
    var disabled = try feature.run_selection.lookupIndices(
        view,
        std.testing.allocator,
        .{ .script_tag = .dflt },
    );
    defer disabled.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), disabled.items.len);
}

test "GPOS run selection skips direct and extension mark lookups" {
    var bytes = [_]u8{0} ** 104;
    writeMarkLookupTable(&bytes);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };

    var unmarked = try feature.run_selection.lookupIndices(
        view,
        std.testing.allocator,
        .{
            .script_tag = .dflt,
            .run_may_have_mark_attachments = false,
        },
    );
    defer unmarked.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, &.{0}, unmarked.items);

    var marked = try feature.run_selection.lookupIndices(
        view,
        std.testing.allocator,
        .{
            .script_tag = .dflt,
            .run_may_have_mark_attachments = true,
        },
    );
    defer marked.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 2 }, marked.items);
}

fn writeRequiredFeatureTable(
    bytes: []u8,
    required_tag: u32,
    optional_tag: u32,
) void {
    const required_first = required_tag < optional_tag;
    const required_index: u16 = if (required_first) 0 else 1;
    const optional_index: u16 = if (required_first) 1 else 0;

    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 60);

    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, required_index);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, optional_index);

    writeU16(bytes, 34, 2);
    if (required_first) {
        writeFeatureRecord(bytes, 36, required_tag, 14);
        writeFeatureRecord(bytes, 42, optional_tag, 20);
    } else {
        writeFeatureRecord(bytes, 36, optional_tag, 20);
        writeFeatureRecord(bytes, 42, required_tag, 14);
    }
    writeFeature(bytes, 48, 0);
    writeFeature(bytes, 54, 1);

    writeU16(bytes, 60, 2);
    writeU16(bytes, 62, 0);
    writeU16(bytes, 64, 0);
}

fn writeFeatureRecord(
    bytes: []u8,
    offset: usize,
    tag: u32,
    feature_offset: u16,
) void {
    writeU32(bytes, offset, tag);
    writeU16(bytes, offset + 4, feature_offset);
}

fn writeFeature(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, lookup_index);
}

fn writeFeatureList(
    bytes: []u8,
    offset: usize,
    lookups: []const u16,
) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, @intCast(lookups.len));
    for (lookups, 0..) |lookup_index, index| {
        writeU16(bytes, offset + 4 + index * 2, lookup_index);
    }
}

fn writeRepeatedLookupTable(bytes: []u8, feature_tag: u32) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 66);
    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 2);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 34, 2);
    writeFeatureRecord(bytes, 36, feature_tag, 14);
    writeFeatureRecord(bytes, 42, feature_tag, 24);
    writeFeatureList(bytes, 48, &.{ 3, 1, 3 });
    writeFeatureList(bytes, 58, &.{ 2, 1 });
    writeU16(bytes, 66, 4);
}

fn writeMarkLookupTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 66);
    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 2);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 34, 2);
    writeFeatureRecord(bytes, 36, unicode.tag("kern"), 14);
    writeFeatureRecord(bytes, 42, unicode.tag("mark"), 20);
    writeFeatureList(bytes, 48, &.{0});
    writeFeatureList(bytes, 54, &.{ 1, 2 });
    writeU16(bytes, 66, 3);
    writeU16(bytes, 68, 8);
    writeU16(bytes, 70, 14);
    writeU16(bytes, 72, 20);
    writeU16(bytes, 74, 2);
    writeU16(bytes, 80, 4);
    writeU16(bytes, 86, 9);
    writeU16(bytes, 90, 1);
    writeU16(bytes, 92, 8);
    writeU16(bytes, 94, 1);
    writeU16(bytes, 96, 5);
    writeU32(bytes, 98, 8);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
