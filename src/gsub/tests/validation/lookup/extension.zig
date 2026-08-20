//! ExtensionSubst recursion, payload bounds, and body preflight contracts.

const std = @import("std");
const support = @import("support.zig");
const validation = @import("../../../validation/root.zig");

test "extension validation rejects recursive and escaping payloads" {
    var bytes = [_]u8{0} ** 32;
    support.writeU16(&bytes, 0, 1);
    support.writeU16(&bytes, 2, 7);
    support.writeU32(&bytes, 4, 8);
    try std.testing.expectError(
        error.UnsupportedGsub,
        validation.lookup.extension.validate(
            support.Validator,
            support.view(&bytes),
            0,
        ),
    );

    support.writeU16(&bytes, 2, 1);
    support.writeU32(&bytes, 4, 0xffff_ffff);
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.extension.validate(
            support.Validator,
            support.view(&bytes),
            0,
        ),
    );
}

test "extension validation checks the complete wrapped body" {
    var bytes = [_]u8{0} ** 24;
    support.writeU16(&bytes, 0, 1);
    support.writeU16(&bytes, 2, 1);
    support.writeU32(&bytes, 4, 8);
    support.writeU16(&bytes, 8, 1);
    support.writeU16(&bytes, 10, 6);
    support.writeU16(&bytes, 12, 1);
    support.writeU16(&bytes, 14, 1);
    support.writeU16(&bytes, 16, 4);
    support.writeU16(&bytes, 18, 1);

    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.extension.validate(
            support.Validator,
            support.view(&bytes),
            0,
        ),
    );

    support.writeCoverage1(&bytes, 14, &.{1});
    try validation.lookup.extension.validate(
        support.Validator,
        support.view(&bytes),
        0,
    );
}
