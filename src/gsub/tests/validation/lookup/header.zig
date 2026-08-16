//! Lookup fixed-header, flags, and Extension ownership contracts.

const std = @import("std");
const support = @import("support.zig");
const validation = @import("../../../validation/root.zig");

test "lookup header validates flags offset arrays and mark filtering field" {
    var bytes = [_]u8{0} ** 24;
    support.writeLookup(&bytes, 1, 0x00e0, &.{10});
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.header.validate(support.view(&bytes), 0),
    );

    support.writeLookup(&bytes, 1, 0xff10, &.{10});
    support.writeU16(&bytes, 8, 0);
    try std.testing.expectEqual(
        @as(u16, 1),
        try validation.lookup.header.validate(support.view(&bytes), 0),
    );

    // The mark-filtering-set field follows the complete variable offset array.
    support.writeU16(&bytes, 4, 9);
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.header.validate(support.view(&bytes), 0),
    );
}

test "lookup header validation owns extension payload preflight" {
    var bytes = [_]u8{0} ** 32;
    support.writeLookup(&bytes, 7, 0, &.{8});
    support.writeU16(&bytes, 8, 1);
    support.writeU16(&bytes, 10, 1);
    support.writeU32(&bytes, 12, 0xffff_ffff);

    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.validateHeader(
            support.Validator,
            support.view(&bytes),
            0,
        ),
    );

    var trusted = support.view(&bytes);
    trusted.assume_validated = true;
    try std.testing.expectEqual(
        @as(u16, 7),
        try validation.lookup.validateHeader(
            support.Validator,
            trusted,
            0,
        ),
    );
}
