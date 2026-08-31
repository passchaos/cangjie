//! Cached GPOS lookup dispatch identity contracts.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const runtime = @import("../../runtime/root.zig");
const table = @import("../../table/root.zig");

test "runtime dispatch requires exact table and sidecar identity" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeSinglePositionTable(&bytes);
    const accelerators = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, accelerators);

    const validated = view(&bytes, 0, bytes.len, true);
    const run: runtime.Options = .{ .lookup_accelerators = accelerators };
    try std.testing.expect(runtime.dispatch.exactSidecars(validated, run) != null);
    try std.testing.expect(runtime.dispatch.exact(
        validated,
        14,
        1,
        1,
        0,
        run,
    ) != null);

    try std.testing.expect(runtime.dispatch.exactSidecars(
        view(&bytes, 0, bytes.len, false),
        run,
    ) == null);

    // Equal contents in unrelated storage do not identify the table whose
    // decoded offsets and payloads are held by the sidecars.
    var foreign_bytes = bytes;
    try std.testing.expect(runtime.dispatch.exactSidecars(
        view(&foreign_bytes, 0, foreign_bytes.len, true),
        run,
    ) == null);

    // Identity deliberately does not hash contents. Mutation violates the
    // accelerator API contract, but remains the same allocation/range; callers
    // cannot use this check as a mutation detector or lifetime guard.
    bytes[29] ^= 1;
    try std.testing.expect(runtime.dispatch.exactSidecars(validated, run) != null);
    bytes[29] ^= 1;

    // A shallow copy retains the identity pointer but not the allocation
    // address to which that identity was bound during construction.
    const copied = try allocator.dupe(accelerator.Lookup, accelerators);
    defer allocator.free(copied);
    try std.testing.expect(runtime.dispatch.exactSidecars(
        validated,
        .{ .lookup_accelerators = copied },
    ) == null);

    try std.testing.expect(runtime.dispatch.exactSidecars(
        view(&bytes, 1, bytes.len - 1, true),
        run,
    ) == null);
    try std.testing.expect(runtime.dispatch.exact(
        validated,
        15,
        1,
        1,
        0,
        run,
    ) == null);
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

fn view(
    bytes: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool,
) table.View {
    return .{
        .data = bytes,
        .offset = offset,
        .length = length,
        .assume_validated = assume_validated,
    };
}

fn writeSinglePositionTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 38); // Empty ScriptList.
    writeU16(bytes, 6, 40); // Empty FeatureList.
    writeU16(bytes, 8, 10); // LookupList.
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 4);
    writeU16(bytes, 14, 1); // SinglePos lookup.
    writeU16(bytes, 18, 1);
    writeU16(bytes, 20, 8);
    writeU16(bytes, 22, 1); // SinglePos format 1.
    writeU16(bytes, 24, 8);
    writeU16(bytes, 26, 0x0001);
    writeU16(bytes, 28, 7);
    writeU16(bytes, 30, 1); // Coverage format 1.
    writeU16(bytes, 32, 1);
    writeU16(bytes, 34, 5);
    writeU16(bytes, 38, 0);
    writeU16(bytes, 40, 0);
}
