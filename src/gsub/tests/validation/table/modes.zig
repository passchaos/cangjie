//! Whole-table strict and shaping validation contracts.

const std = @import("std");
const fixture = @import("../lookup/support.zig");
const table_validation = @import("../../../validation/table/root.zig");

test "whole-table validation keeps shaping SingleSubst delta compatibility" {
    var bytes = [_]u8{0} ** 48;
    fixture.writeU32(&bytes, 0, 0x00010000);
    fixture.writeU16(&bytes, 4, 10);
    fixture.writeU16(&bytes, 6, 12);
    fixture.writeU16(&bytes, 8, 14);
    fixture.writeU16(&bytes, 10, 0);
    fixture.writeU16(&bytes, 12, 0);
    fixture.writeU16(&bytes, 14, 1);
    fixture.writeU16(&bytes, 16, 4);
    fixture.writeLookup(bytes[18..], 1, 0, &.{8});
    fixture.writeSingle(&bytes, 26, 3, 1);

    try std.testing.expectError(
        error.BadGsub,
        table_validation.glyphBounds(
            fixture.Validator,
            &bytes,
            0,
            bytes.len,
            4,
            .strict,
        ),
    );
    try table_validation.glyphBounds(
        fixture.Validator,
        &bytes,
        0,
        bytes.len,
        4,
        .shaping,
    );
}
