//! ExtensionPos wrapper and nested-target contracts.

const std = @import("std");
const extension =
    @import("../../../../runtime/lookup/extension/root.zig");
const table = @import("../../../../table/root.zig");

test "ExtensionPos rejects payloads outside or inside its wrapper header" {
    var bytes = [_]u8{0} ** 8;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 1);
    writeU32(&bytes, 4, 0xffff_fffe);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(extension.model.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try std.testing.expectError(
        error.BadGpos,
        extension.wrapper.collect(
            view,
            0,
            &.{5},
            &adjustments,
            std.testing.allocator,
            0,
            .{},
            rejectCollect,
            rejectCollect,
        ),
    );
    try std.testing.expectError(
        error.BadGpos,
        extension.nested.collectAt(
            view,
            0,
            &.{5},
            0,
            &adjustments,
            std.testing.allocator,
            0,
            .{},
            rejectCollectAt,
            rejectCollectAt,
        ),
    );

    writeU32(&bytes, 4, 4);
    try std.testing.expectError(
        error.BadGpos,
        extension.wrapper.collect(
            view,
            0,
            &.{5},
            &adjustments,
            std.testing.allocator,
            0,
            .{},
            rejectCollect,
            rejectCollect,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "ExtensionPos preserves the outer lookup flag" {
    var bytes = [_]u8{0} ** 24;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 1);
    writeU32(&bytes, 4, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 8);
    writeU16(&bytes, 12, 0x0001);
    writeI16(&bytes, 14, 50);
    writeCoverage(&bytes, 16, 3);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(extension.model.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try extension.wrapper.collect(
        view,
        0,
        &.{3},
        &adjustments,
        std.testing.allocator,
        0x0008,
        .{ .glyph_classes = &.{ 0, 0, 0, 3 } },
        rejectCollect,
        rejectCollect,
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

fn rejectCollect(
    _: table.View,
    _: usize,
    _: []const u16,
    _: *std.ArrayList(extension.model.Adjustment),
    _: std.mem.Allocator,
    _: u16,
    _: extension.model.Options,
) extension.model.Error!void {
    return error.InvalidShapingInput;
}

fn rejectCollectAt(
    _: table.View,
    _: usize,
    _: []const u16,
    _: usize,
    _: *std.ArrayList(extension.model.Adjustment),
    _: std.mem.Allocator,
    _: u16,
    _: extension.model.Options,
) extension.model.Error!bool {
    return error.InvalidShapingInput;
}

fn writeCoverage(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
