//! Ordered direct-subtable and shaping-policy contracts.

const std = @import("std");
const support = @import("support.zig");
const validation = @import("../../../validation/root.zig");

test "lookup validation requires real direct subtable children" {
    var bytes = [_]u8{0} ** 32;
    support.writeLookup(&bytes, 1, 0, &.{0});
    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.validateSubtables(
            support.Validator,
            support.view(&bytes),
            0,
            1,
            1,
            .strict,
        ),
    );

    support.writeLookup(&bytes, 1, 0, &.{8});
    support.writeSingle(&bytes, 8, 1, 1);
    try validation.lookup.validateSubtables(
        support.Validator,
        support.view(&bytes),
        0,
        1,
        1,
        .strict,
    );
}

test "lookup shaping mode relaxes only supported authored-child policy" {
    var bytes = [_]u8{0} ** 32;
    support.writeLookup(&bytes, 4, 0, &.{8});
    // LigatureSubst with a valid Coverage but a missing authored LigatureSet.
    support.writeU16(&bytes, 8, 1);
    support.writeU16(&bytes, 10, 8);
    support.writeU16(&bytes, 12, 1);
    support.writeU16(&bytes, 14, 0);
    support.writeCoverage1(&bytes, 16, &.{1});

    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.validateSubtables(
            support.Validator,
            support.view(&bytes),
            0,
            4,
            1,
            .strict,
        ),
    );
    try validation.lookup.validateSubtables(
        support.Validator,
        support.view(&bytes),
        0,
        4,
        1,
        .shaping,
    );
}

test "lookup validation preflights every ordered alternative" {
    var bytes = [_]u8{0} ** 40;
    support.writeLookup(&bytes, 1, 0, &.{ 10, 24 });
    support.writeSingle(&bytes, 10, 1, 1);
    support.writeU16(&bytes, 24, 1);
    support.writeU16(&bytes, 26, 6);
    support.writeU16(&bytes, 28, 1);
    // Coverage declares two glyphs but only one fits in the table.
    support.writeU16(&bytes, 30, 1);
    support.writeU16(&bytes, 32, 4);
    support.writeU16(&bytes, 34, 1);

    try std.testing.expectError(
        error.BadGsub,
        validation.lookup.validateSubtables(
            support.Validator,
            support.view(&bytes),
            0,
            1,
            2,
            .strict,
        ),
    );
}
