//! Concrete executor and authored record-order contracts.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const fixture = @import("ligature_fixture.zig");
const model = @import("../../../../execution/contextual/model.zig");
const records = @import("../../../../execution/contextual/records/root.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");

const Executor = struct {
    pub const enable_fast_single = false;

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

const FastExecutor = struct {
    pub fn applyNested(
        _: table.View,
        _: *std.ArrayList(u16),
        _: usize,
        _: u16,
        _: std.mem.Allocator,
        _: Options,
    ) error{BadGsub}!model.Change {
        return error.BadGsub;
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "records extend the map and apply a newly valid sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 8;
    writeRecord(&bytes, 0, 0, 0);
    writeRecord(&bytes, 4, 1, 1);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 1);
    try records.apply(
        Executor,
        validatedView(&bytes),
        &glyphs,
        0,
        2,
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

test "accelerated single records obey the nested operation budget" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 4;
    writeRecord(&bytes, 0, 0, 0);
    const lookups = [_]accelerator.Lookup{.{
        .single_subst = .{
            .enabled = true,
            .single_mapping = true,
            .single_from = 5,
            .single_to = 9,
        },
    }};

    var exhausted_glyphs = std.ArrayList(u16).empty;
    defer exhausted_glyphs.deinit(allocator);
    try exhausted_glyphs.append(allocator, 5);
    var exhausted: usize = 0;
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        records.apply(
            FastExecutor,
            validatedView(&bytes),
            &exhausted_glyphs,
            0,
            1,
            &.{0},
            allocator,
            .{
                .lookup_accelerators = &lookups,
                .operations_left = &exhausted,
            },
        ),
    );
    try std.testing.expectEqualSlices(u16, &.{5}, exhausted_glyphs.items);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    var operations_left: usize = 1;
    try records.apply(
        FastExecutor,
        validatedView(&bytes),
        &glyphs,
        0,
        1,
        &.{0},
        allocator,
        .{
            .lookup_accelerators = &lookups,
            .operations_left = &operations_left,
        },
    );
    try std.testing.expectEqualSlices(u16, &.{9}, glyphs.items);
    try std.testing.expectEqual(@as(usize, 0), operations_left);
}

test "parsed single records obey the nested operation budget" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 44;
    fixture.writeLookupList(&bytes, &.{4});
    fixture.writeSingleLookup(&bytes, 14, 5, 4);
    fixture.writeRecord(&bytes, 40, 0, 0);

    var exhausted_glyphs = std.ArrayList(u16).empty;
    defer exhausted_glyphs.deinit(allocator);
    try exhausted_glyphs.append(allocator, 5);
    var exhausted: usize = 0;
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        records.apply(
            FastExecutor,
            validatedView(&bytes),
            &exhausted_glyphs,
            40,
            1,
            &.{0},
            allocator,
            .{ .operations_left = &exhausted },
        ),
    );
    try std.testing.expectEqualSlices(u16, &.{5}, exhausted_glyphs.items);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    var operations_left: usize = 1;
    try records.apply(
        FastExecutor,
        validatedView(&bytes),
        &glyphs,
        40,
        1,
        &.{0},
        allocator,
        .{ .operations_left = &operations_left },
    );
    try std.testing.expectEqualSlices(u16, &.{9}, glyphs.items);
    try std.testing.expectEqual(@as(usize, 0), operations_left);
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
