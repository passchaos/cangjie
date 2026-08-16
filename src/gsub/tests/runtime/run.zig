//! Whole-run and cached-selection orchestration contracts.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");
const run = @import("../../runtime/run/root.zig");
const table = @import("../../table/root.zig");

const Executor = struct {
    pub fn applyLookup(
        _: table.View,
        _: usize,
        _: u16,
        glyphs: *std.ArrayList(u16),
        _: std.mem.Allocator,
        options: run.Options,
        _: *@import("../../runtime/prefilter/root.zig").Cache,
    ) run.Error!void {
        glyphs.items[0] += @intCast(options.active_feature_value);
    }
};

test "whole GSUB run carries selected feature value into lookup execution" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 56;
    writeMinimalFeatureTable(&bytes);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);

    try run.apply(
        Executor,
        &bytes,
        0,
        bytes.len,
        &glyphs,
        allocator,
        .{ .script_tag = .dflt },
    );
    try std.testing.expectEqualSlices(u16, &.{11}, glyphs.items);
}

test "cached GSUB run declines foreign identity before mutation" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 16;
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 10);
    var operations: usize = 8;
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 1,
    }};
    const accepted = try run.cached.apply(
        Executor,
        &bytes,
        0,
        16,
        &glyphs,
        allocator,
        .{
            .selected_lookups = &.{0},
            .lookup_accelerators = &sidecars,
            .operations_left = &operations,
            .max_glyph_count = 32,
            .assume_validated = true,
        },
    );
    try std.testing.expect(!accepted);
    try std.testing.expectEqualSlices(u16, &.{10}, glyphs.items);
}

fn writeMinimalFeatureTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 30);
    writeU16(bytes, 8, 44);
    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(@import("../../../unicode.zig").OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, 1);
    writeU32(bytes, 32, @import("../../../unicode.zig").tag("liga"));
    writeU16(bytes, 36, 8);
    writeU16(bytes, 38, 0);
    writeU16(bytes, 40, 1);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 4);
    // Lookup offset only needs identity for this synthetic executor.
    writeU16(bytes, 48, 0);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
