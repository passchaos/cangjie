//! ExtensionPos whole-lookup precedence contracts.

const std = @import("std");
const extension =
    @import("../../../../runtime/lookup/extension/root.zig");
const output = @import("../../../../runtime/output/root.zig");
const table = @import("../../../../table/root.zig");

test "wrapped SinglePos subtables are ordered alternatives" {
    var bytes = [_]u8{0} ** 54;
    writeU16(&bytes, 0, 9);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 2);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 32);
    writeWrappedSingle(&bytes, 10, 5, 20);
    writeWrappedSingle(&bytes, 32, 5, 50);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var adjustments = std.ArrayList(extension.model.Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);

    try extension.lookup.collectSingle(
        view,
        0,
        2,
        &.{5},
        &adjustments,
        std.testing.allocator,
        0,
        .{},
    );
    try std.testing.expectEqual(
        @as(i16, 20),
        output.adjustments.find(adjustments.items, 0).?.x_placement,
    );
}

fn writeWrappedSingle(
    bytes: []u8,
    wrapper: usize,
    glyph: u16,
    placement: i16,
) void {
    writeU16(bytes, wrapper, 1);
    writeU16(bytes, wrapper + 2, 1);
    writeU32(bytes, wrapper + 4, 8);
    const payload = wrapper + 8;
    writeU16(bytes, payload, 1);
    writeU16(bytes, payload + 2, 8);
    writeU16(bytes, payload + 4, 0x0001);
    writeI16(bytes, payload + 6, placement);
    writeU16(bytes, payload + 8, 1);
    writeU16(bytes, payload + 10, 1);
    writeU16(bytes, payload + 12, glyph);
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
