//! Shared executor and binary helpers for chaining-class tests.

const std = @import("std");
const model = @import("../../../../../execution/contextual/model.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const table = @import("../../../../../table/root.zig");

pub const Executor = struct {
    // Synthetic tests use lookup indexes as observable operations rather than
    // encoding full SingleSubst lookup tables for the production fast path.
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        _: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        glyphs.items[target] += lookup_index + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

pub fn classDigestBit(class: u16) u8 {
    const bit: u3 = @truncate(class);
    return @as(u8, 1) << bit;
}

pub fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    start: u16,
    classes: []const u16,
) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], 1, .big);
    std.mem.writeInt(u16, bytes[offset + 2 ..][0..2], start, .big);
    std.mem.writeInt(
        u16,
        bytes[offset + 4 ..][0..2],
        @intCast(classes.len),
        .big,
    );
    for (classes, 0..) |class, index| {
        std.mem.writeInt(
            u16,
            bytes[offset + 6 + index * 2 ..][0..2],
            class,
            .big,
        );
    }
}

pub fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
