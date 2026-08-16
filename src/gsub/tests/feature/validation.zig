//! GSUB FeatureList and ScriptList activation-graph validation contracts.

const std = @import("std");
const feature = @import("../../feature/root.zig");
const table = @import("../../table/root.zig");
const unicode = @import("../../../unicode.zig");

test "FeatureList validation rejects lookup indexes outside LookupList" {
    var bytes = [_]u8{0} ** 36;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 6, 14);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, unicode.tag("liga"));
    writeU16(&bytes, 20, 8);
    writeU16(&bytes, 22, 0);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 1);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(
        error.BadGsub,
        feature.validation.lookupReferences(view, 1),
    );
    writeU16(&bytes, 26, 0);
    try std.testing.expectEqual(
        @as(u16, 1),
        try feature.validation.lookupReferences(view, 1),
    );
}

test "Script validation checks optional and required feature indexes" {
    var bytes = [_]u8{0} ** 48;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 4, 14);
    writeU16(&bytes, 14, 1);
    writeU32(
        &bytes,
        16,
        @intFromEnum(unicode.OpenTypeScriptTag.dflt),
    );
    writeU16(&bytes, 20, 8);
    writeU16(&bytes, 22, 4);
    writeU16(&bytes, 24, 0);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 0xffff);
    writeU16(&bytes, 30, 1);
    writeU16(&bytes, 32, 1);
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(
        error.BadGsub,
        feature.validation.scriptReferences(view, 1),
    );
    writeU16(&bytes, 32, 0);
    try feature.validation.scriptReferences(view, 1);

    writeU16(&bytes, 28, 1);
    try std.testing.expectError(
        error.BadGsub,
        feature.validation.scriptReferences(view, 1),
    );
}

test "activation graph rejects null required child offsets" {
    var bytes = [_]u8{0} ** 32;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 6, 14);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, unicode.tag("liga"));
    writeU16(&bytes, 20, 0); // FeatureRecord.Feature offset is required.
    const view = table.View{ .data = &bytes, .offset = 0, .length = bytes.len };

    try std.testing.expectError(
        error.BadGsub,
        feature.validation.lookupReferences(view, 1),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
