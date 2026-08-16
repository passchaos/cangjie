//! Complete FeatureList and ScriptList activation-graph contracts.

const std = @import("std");
const fixture = @import("fixture.zig");
const unicode = @import("../../../../unicode.zig");
const validation = @import("../../../validation/root.zig");

test "font validation checks FeatureList lookup indexes" {
    var bytes = [_]u8{0} ** 56;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 54);
    fixture.writeU16(&bytes, 6, 10);
    fixture.writeU16(&bytes, 8, 24);

    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU32(&bytes, 12, unicode.tag("kern"));
    fixture.writeU16(&bytes, 16, 8);
    fixture.writeU16(&bytes, 20, 1);
    fixture.writeU16(&bytes, 22, 1); // LookupList only contains index 0.

    fixture.writeU16(&bytes, 24, 1);
    fixture.writeU16(&bytes, 26, 4);
    fixture.writeSinglePositionLookup(&bytes, 28, 1, 0, 0);
    fixture.writeU16(&bytes, 54, 0);

    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );

    fixture.writeU16(&bytes, 22, 0);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);
}

test "font validation checks LangSys feature indexes" {
    var bytes = [_]u8{0} ** 86;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 10);
    fixture.writeU16(&bytes, 6, 40);
    fixture.writeU16(&bytes, 8, 56);

    fixture.writeU16(&bytes, 10, 1);
    fixture.writeU32(
        &bytes,
        12,
        @intFromEnum(unicode.OpenTypeScriptTag.dflt),
    );
    fixture.writeU16(&bytes, 16, 8);

    fixture.writeU16(&bytes, 18, 4);
    fixture.writeU16(&bytes, 20, 0);
    fixture.writeU16(&bytes, 22, 0);
    fixture.writeU16(&bytes, 24, 0xffff);
    fixture.writeU16(&bytes, 26, 1);
    fixture.writeU16(&bytes, 28, 1); // FeatureList only contains index 0.

    fixture.writeU16(&bytes, 40, 1);
    fixture.writeFeatureRecord(&bytes, 42, unicode.tag("kern"), 8);
    fixture.writeFeature(&bytes, 50, 0);

    fixture.writeU16(&bytes, 56, 1);
    fixture.writeU16(&bytes, 58, 4);
    fixture.writeSinglePositionLookup(&bytes, 60, 1, 0, 0);

    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );

    fixture.writeU16(&bytes, 28, 0);
    try validation.font.glyphBounds(&bytes, 0, bytes.len, 4);

    fixture.writeU16(&bytes, 24, 1); // ReqFeatureIndex is checked too.
    try std.testing.expectError(
        error.BadGpos,
        validation.font.glyphBounds(&bytes, 0, bytes.len, 4),
    );
}
