//! Focused avar version, axis-count, segment-map, and parse contracts.

const std = @import("std");
const font_mod = @import("../../../../font.zig");
const avar = @import("../../../tables/variations/avar.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("../support.zig");

const Font = font_mod.Font;

test "avar validates every declared segment map before returning a coordinate" {
    var bytes: [20]u8 = .{0} ** 20;
    writeHeader(&bytes, 0, 2);
    fixture.writeU16(&bytes, 8, 2);
    support.writeF2Dot14(&bytes, 10, -1.0);
    support.writeF2Dot14(&bytes, 12, -1.0);
    support.writeF2Dot14(&bytes, 14, 1.0);
    support.writeF2Dot14(&bytes, 16, 1.0);
    fixture.writeU16(&bytes, 18, 1); // Truncated second map.

    try std.testing.expectError(
        error.BadSfnt,
        avar.map(&bytes, avarRecord(0, bytes.len), null, 0, 0.0),
    );
}

test "avar axis count must match fvar axis count when both tables exist" {
    var bytes: [46]u8 = .{0} ** 46;
    support.writeFvarHeader(&bytes, 1);
    support.writeAxis(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeHeader(&bytes, 36, 2);
    fixture.writeU16(&bytes, 44, 3);

    try std.testing.expectError(
        error.BadSfnt,
        avar.validate(
            &bytes,
            avarRecord(36, bytes.len - 36),
            fvarRecord(36),
        ),
    );
}

test "avar segment maps are fully validated at parse time" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    const Mutation = enum {
        reserved,
        missing_anchor,
        unsorted_from,
        shifted_default,
        decreasing_to,
        truncated,
    };
    inline for (std.enums.values(Mutation)) |mutation| {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const offset = try fixture.tableOffset(bytes, "avar");
        switch (mutation) {
            .reserved => fixture.writeU16(bytes, offset + 4, 1),
            .missing_anchor => fixture.writeU16(bytes, offset + 8, 2),
            .unsorted_from => support.writeF2Dot14(bytes, offset + 18, -0.25),
            .shifted_default => support.writeF2Dot14(bytes, offset + 16, 0.25),
            .decreasing_to => support.writeF2Dot14(bytes, offset + 20, -0.25),
            .truncated => try fixture.setTableLength(
                bytes,
                "avar",
                @intCast(try tableLength(bytes, "avar") - 2),
            ),
        }
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

fn writeHeader(
    bytes: []u8,
    offset: usize,
    axis_count: u16,
) void {
    fixture.writeU16(bytes, offset, 1);
    fixture.writeU16(bytes, offset + 2, 0);
    fixture.writeU16(bytes, offset + 4, 0);
    fixture.writeU16(bytes, offset + 6, axis_count);
}

fn avarRecord(offset: usize, length: usize) @import(
    "../../../sfnt/root.zig",
).Record {
    return .{
        .tag = .{ 'a', 'v', 'a', 'r' },
        .checksum = 0,
        .offset = offset,
        .length = length,
    };
}

fn fvarRecord(length: usize) @import("../../../sfnt/root.zig").Record {
    return .{
        .tag = .{ 'f', 'v', 'a', 'r' },
        .checksum = 0,
        .offset = 0,
        .length = length,
    };
}

fn tableLength(
    bytes: []const u8,
    comptime tag: *const [4]u8,
) error{BadSfnt}!u32 {
    if (bytes.len < 12) return error.BadSfnt;
    const count = std.mem.readInt(u16, bytes[4..6], .big);
    if (count > (bytes.len - 12) / 16) return error.BadSfnt;
    for (0..count) |index| {
        const record = 12 + index * 16;
        if (std.mem.eql(u8, bytes[record..][0..4], tag)) {
            return std.mem.readInt(u32, bytes[record + 12 ..][0..4], .big);
        }
    }
    return error.BadSfnt;
}
