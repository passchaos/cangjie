//! Cached GPOS lookup dispatch identity contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const runtime = @import("../../runtime/root.zig");
const table = @import("../../table/root.zig");

test "runtime dispatch trusts only matching validated sidecars" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 10);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerators = [_]accelerator.Lookup{.{
        .lookup_offset = 0,
        .lookup_type = 8,
        .subtable_count = 4,
    }};

    const cached = try runtime.dispatch.header(
        view,
        0,
        0,
        .{ .lookup_accelerators = &accelerators },
    );
    try std.testing.expectEqual(@as(u16, 8), cached.lookup_type);

    var stale = accelerators;
    stale[0].lookup_offset = 2;
    const parsed = try runtime.dispatch.header(
        view,
        0,
        0,
        .{ .lookup_accelerators = &stale },
    );
    try std.testing.expectEqual(@as(u16, 1), parsed.lookup_type);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
