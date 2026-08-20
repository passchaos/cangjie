//! ContextSubst format grammar and child-reference contracts.

const std = @import("std");
const support = @import("support.zig");
const validation = @import("../../../validation/root.zig");

test "context validation covers glyph class and coverage formats" {
    var bytes = [_]u8{0} ** 256;
    support.installLookupList(&bytes, 220, 230);

    // Format 1: one glyph rule with one nested lookup record.
    const glyph_subtable = 20;
    support.writeU16(&bytes, glyph_subtable, 1);
    support.writeU16(&bytes, glyph_subtable + 2, 40);
    support.writeU16(&bytes, glyph_subtable + 4, 1);
    support.writeU16(&bytes, glyph_subtable + 6, 8);
    support.writeU16(&bytes, glyph_subtable + 8, 1);
    support.writeU16(&bytes, glyph_subtable + 10, 4);
    support.writeU16(&bytes, glyph_subtable + 12, 1);
    support.writeU16(&bytes, glyph_subtable + 14, 1);
    support.writeRecord(&bytes, glyph_subtable + 16, 0, 0);
    support.writeCoverage1(&bytes, glyph_subtable + 40, &.{1});
    try validation.contextual.context.validate(
        support.Validator,
        support.validatedView(&bytes),
        glyph_subtable,
    );

    // Format 2 shares the rule grammar but requires a real ClassDef.
    const class_subtable = 80;
    support.writeU16(&bytes, class_subtable, 2);
    support.writeU16(&bytes, class_subtable + 2, 50);
    support.writeU16(&bytes, class_subtable + 4, 56);
    support.writeU16(&bytes, class_subtable + 6, 2);
    support.writeU16(&bytes, class_subtable + 8, 0);
    support.writeU16(&bytes, class_subtable + 10, 12);
    support.writeU16(&bytes, class_subtable + 12, 1);
    support.writeU16(&bytes, class_subtable + 14, 4);
    support.writeU16(&bytes, class_subtable + 16, 1);
    support.writeU16(&bytes, class_subtable + 18, 0);
    support.writeCoverage1(&bytes, class_subtable + 50, &.{1});
    support.writeClassDef1(&bytes, class_subtable + 56, 1, &.{1});
    try validation.contextual.context.validate(
        support.Validator,
        support.validatedView(&bytes),
        class_subtable,
    );

    // Format 3 validates every required input Coverage and record reference.
    const coverage_subtable = 160;
    support.writeU16(&bytes, coverage_subtable, 3);
    support.writeU16(&bytes, coverage_subtable + 2, 1);
    support.writeU16(&bytes, coverage_subtable + 4, 1);
    support.writeU16(&bytes, coverage_subtable + 6, 12);
    support.writeRecord(&bytes, coverage_subtable + 8, 0, 0);
    support.writeCoverage1(&bytes, coverage_subtable + 12, &.{1});
    try validation.contextual.context.validate(
        support.Validator,
        support.validatedView(&bytes),
        coverage_subtable,
    );
}

test "context validation rejects null rules class definitions and lookups" {
    var bytes = [_]u8{0} ** 224;
    support.installLookupList(&bytes, 190, 200);
    const glyph_subtable = 20;
    support.writeU16(&bytes, glyph_subtable, 1);
    support.writeU16(&bytes, glyph_subtable + 2, 30);
    support.writeU16(&bytes, glyph_subtable + 4, 1);
    support.writeU16(&bytes, glyph_subtable + 6, 8);
    support.writeU16(&bytes, glyph_subtable + 8, 1);
    support.writeU16(&bytes, glyph_subtable + 10, 0);
    support.writeCoverage1(&bytes, glyph_subtable + 30, &.{1});
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.context.validate(
            support.Validator,
            support.validatedView(&bytes),
            glyph_subtable,
        ),
    );

    const class_subtable = 70;
    support.writeU16(&bytes, class_subtable, 2);
    support.writeU16(&bytes, class_subtable + 2, 20);
    support.writeU16(&bytes, class_subtable + 4, 0);
    support.writeU16(&bytes, class_subtable + 6, 0);
    support.writeCoverage1(&bytes, class_subtable + 20, &.{1});
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.context.validate(
            support.Validator,
            support.validatedView(&bytes),
            class_subtable,
        ),
    );

    const coverage_subtable = 120;
    support.writeU16(&bytes, coverage_subtable, 3);
    support.writeU16(&bytes, coverage_subtable + 2, 1);
    support.writeU16(&bytes, coverage_subtable + 4, 1);
    support.writeU16(&bytes, coverage_subtable + 6, 12);
    support.writeRecord(&bytes, coverage_subtable + 8, 0, 1);
    support.writeCoverage1(&bytes, coverage_subtable + 12, &.{1});
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.context.validate(
            support.Validator,
            support.validatedView(&bytes),
            coverage_subtable,
        ),
    );
}
