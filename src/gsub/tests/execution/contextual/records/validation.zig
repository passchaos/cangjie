//! Contextual record reference and MarkFilteringSet preflight contracts.

const std = @import("std");
const records = @import("../../../../execution/contextual/records/root.zig");
const table = @import("../../../../table/root.zig");

const Validator = struct {
    pub const enable_fast_single = false;

    pub fn validateNested(_: table.View, lookup_offset: usize) !void {
        if (lookup_offset != 14) return error.BadGsub;
    }

    pub fn applyNested(
        _: table.View,
        _: *std.ArrayList(u16),
        _: usize,
        _: u16,
        _: std.mem.Allocator,
        _: @import("../../../../runtime/options.zig").Options,
    ) error{BadGsub}!@import("../../../../execution/contextual/model.zig").Change {
        return error.BadGsub;
    }
};

test "record validation accepts out-of-range sequence indexes but not lookups" {
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 8, 10); // LookupList.
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 4); // Lookup 0 at 14.
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0);
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 24, 99); // SequenceIndex is ignored safely.
    writeU16(&bytes, 26, 0);

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try records.validateReferences(Validator, view, 24, 1);

    writeU16(&bytes, 26, 1);
    try std.testing.expectError(
        error.BadGsub,
        records.validateReferences(Validator, view, 24, 1),
    );
}

test "record application validates nested mark filtering sets before execution" {
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 8, 10);
    writeU16(&bytes, 10, 1);
    writeU16(&bytes, 12, 4);
    writeU16(&bytes, 14, 1);
    writeU16(&bytes, 16, 0x0010); // UseMarkFilteringSet.
    writeU16(&bytes, 18, 0);
    writeU16(&bytes, 20, 1); // Invalid when only set zero exists.
    writeU16(&bytes, 24, 0);
    writeU16(&bytes, 26, 0);
    const mark_sets = [_][]const u16{&.{3}};
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 3);

    try std.testing.expectError(
        error.BadGsub,
        records.apply(
            Validator,
            .{ .data = &bytes, .offset = 0, .length = bytes.len },
            &glyphs,
            24,
            1,
            &.{0},
            std.testing.allocator,
            .{ .mark_filtering_sets = &mark_sets },
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
