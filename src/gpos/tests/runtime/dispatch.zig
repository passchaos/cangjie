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

test "runtime dispatch carries cached flags only for validated identity" {
    var bytes = [_]u8{0} ** 12;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0x0010);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 10);
    writeU16(&bytes, 8, 0xffff);
    const accelerators = [_]accelerator.Lookup{.{
        .lookup_offset = 0,
        .lookup_type = 8,
        .lookup_flag = 0,
        .subtable_count = 4,
        .mark_filtering_set = 7,
    }};

    const cached = try runtime.dispatch.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, 0, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 8), cached.lookup_type);
    try std.testing.expectEqual(@as(u16, 4), cached.subtable_count);
    try std.testing.expectEqual(@as(?u16, 7), cached.mark_filtering_set);

    const parsed = try runtime.dispatch.header(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    }, 0, 0, .{ .lookup_accelerators = &accelerators });
    try std.testing.expectEqual(@as(u16, 1), parsed.lookup_type);
    try std.testing.expectEqual(@as(u16, 0x0010), parsed.lookup_flag);
    try std.testing.expectEqual(@as(?u16, 0xffff), parsed.mark_filtering_set);
}

test "runtime ExtensionPos type cache requires validated lookup identity" {
    var bytes = [_]u8{0} ** 28;
    writeU16(&bytes, 0, 9);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 2);
    writeU32(&bytes, 12, 8);
    writeU16(&bytes, 16, 1);

    const accelerators = [_]accelerator.Lookup{.{
        .lookup_offset = 0,
        .lookup_type = 9,
        .subtable_count = 1,
        .extension_lookup_type = 2,
    }};
    const validated = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    try std.testing.expectEqual(
        @as(?u16, 2),
        try runtime.dispatch.resolvedExtensionType(
            validated,
            0,
            9,
            1,
            0,
            .{ .lookup_accelerators = &accelerators },
        ),
    );

    writeU16(&bytes, 10, 1);
    const unvalidated = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
    };
    try std.testing.expectEqual(
        @as(?u16, 1),
        try runtime.dispatch.resolvedExtensionType(
            unvalidated,
            0,
            9,
            1,
            0,
            .{ .lookup_accelerators = &accelerators },
        ),
    );
    var stale = accelerators;
    stale[0].lookup_offset = 2;
    try std.testing.expectEqual(
        @as(?u16, 1),
        try runtime.dispatch.resolvedExtensionType(
            validated,
            0,
            9,
            1,
            0,
            .{ .lookup_accelerators = &stale },
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
