//! Concrete executor and authored record-order contracts.

const std = @import("std");
const model = @import("../../../../execution/contextual/model.zig");
const records = @import("../../../../execution/contextual/records/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

const Executor = struct {
    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        allocator: std.mem.Allocator,
        _: Options,
    ) std.mem.Allocator.Error!model.Change {
        switch (lookup_index) {
            0 => {
                try glyphs.replaceRange(
                    allocator,
                    target,
                    1,
                    &.{ 20, 21 },
                );
                return .{ .removed_len = 1, .inserted_len = 2 };
            },
            1 => {
                glyphs.items[target] += 10;
                return .{};
            },
            else => unreachable,
        }
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "records extend the map and apply a newly valid sequence index" {
    const allocator = std.testing.allocator;
    // More than the bounded SingleSubst batch forces the generic concrete
    // executor path. The remaining records use an unreachable SequenceIndex.
    var bytes = [_]u8{0} ** (65 * 4);
    writeRecord(&bytes, 0, 0, 0);
    writeRecord(&bytes, 4, 1, 1);
    for (2..65) |record_index| {
        writeRecord(&bytes, record_index * 4, 63, 1);
    }

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    try records.apply(
        Executor,
        validatedView(&bytes),
        &glyphs,
        0,
        65,
        &.{0},
        allocator,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{ 20, 31 }, glyphs.items);
}

test "zero records do not instantiate or invoke the nested executor" {
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 7);
    try records.apply(
        Executor,
        validatedView(&.{}),
        &glyphs,
        0,
        0,
        &.{0},
        std.testing.allocator,
        .{},
    );
    try std.testing.expectEqualSlices(u16, &.{7}, glyphs.items);
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}

fn writeRecord(
    bytes: []u8,
    offset: usize,
    sequence_index: u16,
    lookup_index: u16,
) void {
    std.mem.writeInt(
        u16,
        bytes[offset..][0..2],
        sequence_index,
        .big,
    );
    std.mem.writeInt(
        u16,
        bytes[offset + 2 ..][0..2],
        lookup_index,
        .big,
    );
}
