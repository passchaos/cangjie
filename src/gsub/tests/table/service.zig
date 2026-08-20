//! Whole-table GSUB topology and feature query contracts.

const std = @import("std");
const service = @import("../../table/service.zig");
const unicode = @import("../../../unicode.zig");

test "GSUB table service distinguishes empty topology and feature records" {
    var bytes = [_]u8{0} ** 32;
    writeU32(&bytes, 0, 0x00010000);
    var view = try service.view(&bytes, 0, bytes.len, false);
    try std.testing.expect(try service.isEmpty(view));
    try std.testing.expect(!(try service.hasFeature(
        view,
        unicode.tag("liga"),
    )));

    writeU16(&bytes, 4, 10);
    writeU16(&bytes, 6, 12);
    writeU16(&bytes, 8, 28);
    writeU16(&bytes, 10, 0);
    writeU16(&bytes, 12, 1);
    writeU32(&bytes, 14, unicode.tag("liga"));
    writeU16(&bytes, 18, 8);
    writeU16(&bytes, 28, 0);
    view = try service.view(&bytes, 0, bytes.len, false);
    try std.testing.expect(!(try service.isEmpty(view)));
    try std.testing.expect(try service.hasFeature(view, unicode.tag("liga")));
}

test "GSUB table service requires supported bounded tables" {
    var bytes = [_]u8{0} ** 10;
    writeU32(&bytes, 0, 0x00020000);
    try std.testing.expectError(
        error.UnsupportedGsub,
        service.view(&bytes, 0, bytes.len, false),
    );
    try std.testing.expectError(
        error.BadGsub,
        service.view(&bytes, 1, bytes.len, false),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
