//! Shared COLR v1 Paint grammar, traversal, and validation surface.

const std = @import("std");

const core = @import("core.zig");
const types = @import("types.zig");
const walker = @import("walk.zig");

pub const Table = types.Table;
pub const FormatInfo = types.FormatInfo;
pub const Range = types.Range;

pub const formatInfo = core.formatInfo;
pub const validateRecord = core.validateRecord;
pub const childOffset = core.childOffset;
pub const transformPayloadRange = core.transformPayloadRange;
pub const colorLineRange = core.colorLineRange;
pub const usesVariableColorLine = core.usesVariableColorLine;
pub const colorStopSize = core.colorStopSize;
pub const validateGraph = walker.validate;
pub const walkAll = walker.walkAll;
pub const walkAllWithForbiddenRange = walker.walkAllWithForbiddenRange;

test "format metadata covers every assigned COLR v1 Paint format" {
    try std.testing.expect(formatInfo(0) == null);
    for (1..33) |raw_format| {
        const info = formatInfo(@intCast(raw_format)) orelse
            return error.TestUnexpectedResult;
        try std.testing.expect(info.min_size >= 3);
    }
    try std.testing.expect(formatInfo(33) == null);
}

test "record validation enforces alpha and ColorLine grammar" {
    var solid: [9]u8 = .{0} ** 9;
    solid[0] = 3;
    writeI16(&solid, 3, -1);
    const solid_table = Table{ .offset = 0, .length = solid.len };
    try std.testing.expectError(
        error.BadSfnt,
        validateRecord(&solid, solid_table, 0),
    );
    writeI16(&solid, 3, 0x4000);
    _ = try validateRecord(&solid, solid_table, 0);

    var gradient: [31]u8 = .{0} ** 31;
    gradient[0] = 4;
    writeU24(&gradient, 1, 16);
    gradient[16] = 0;
    writeU16(&gradient, 17, 2);
    writeI16(&gradient, 19, 0x2000);
    writeI16(&gradient, 23, 0x4000);
    writeI16(&gradient, 25, 0x1000); // Decreases from the first stop.
    writeI16(&gradient, 29, 0x4000);
    const gradient_table = Table{ .offset = 0, .length = gradient.len };
    try std.testing.expectError(
        error.BadSfnt,
        validateRecord(&gradient, gradient_table, 0),
    );
    writeI16(&gradient, 25, 0x3000);
    _ = try validateRecord(&gradient, gradient_table, 0);
}

test "record validation preserves typed child payload ownership" {
    var composite: [20]u8 = .{0} ** 20;
    composite[0] = 32;
    writeU24(&composite, 1, 8);
    composite[4] = 3;
    writeU24(&composite, 5, 9);
    composite[8] = 2;
    composite[9] = 2; // Also looks like a partially overlapping PaintSolid.
    const composite_table = Table{ .offset = 0, .length = composite.len };
    try std.testing.expectError(
        error.BadSfnt,
        validateRecord(&composite, composite_table, 0),
    );
    writeU24(&composite, 5, 8); // Exact child sharing is a valid DAG.
    _ = try validateRecord(&composite, composite_table, 0);

    var transform: [36]u8 = .{0} ** 36;
    transform[0] = 12;
    writeU24(&transform, 1, 7);
    writeU24(&transform, 4, 7);
    transform[7] = 2;
    const transform_table = Table{ .offset = 0, .length = transform.len };
    try std.testing.expectError(
        error.BadSfnt,
        validateRecord(&transform, transform_table, 0),
    );
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

test {
    _ = @import("tests/root.zig");
}
