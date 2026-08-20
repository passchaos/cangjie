//! ChainContextSubst format and strict/shaping coverage contracts.

const std = @import("std");
const support = @import("support.zig");
const validation = @import("../../../validation/root.zig");

test "chaining validation covers glyph and optional-class formats" {
    var bytes = [_]u8{0} ** 256;
    support.installLookupList(&bytes, 220, 230);

    // Format 1 minimal ChainSubRule.
    const glyph_subtable = 20;
    support.writeU16(&bytes, glyph_subtable, 1);
    support.writeU16(&bytes, glyph_subtable + 2, 40);
    support.writeU16(&bytes, glyph_subtable + 4, 1);
    support.writeU16(&bytes, glyph_subtable + 6, 8);
    support.writeU16(&bytes, glyph_subtable + 8, 1);
    support.writeU16(&bytes, glyph_subtable + 10, 4);
    support.writeU16(&bytes, glyph_subtable + 12, 0);
    support.writeU16(&bytes, glyph_subtable + 14, 1);
    support.writeU16(&bytes, glyph_subtable + 16, 0);
    support.writeU16(&bytes, glyph_subtable + 18, 0);
    support.writeCoverage1(&bytes, glyph_subtable + 40, &.{1});
    try validation.contextual.chaining.validate(
        support.Validator,
        support.validatedView(&bytes),
        glyph_subtable,
        .strict,
    );

    // Format 2 permits absent backtrack/lookahead ClassDef but requires input.
    const class_subtable = 90;
    support.writeU16(&bytes, class_subtable, 2);
    support.writeU16(&bytes, class_subtable + 2, 50);
    support.writeU16(&bytes, class_subtable + 4, 0);
    support.writeU16(&bytes, class_subtable + 6, 56);
    support.writeU16(&bytes, class_subtable + 8, 0);
    support.writeU16(&bytes, class_subtable + 10, 2);
    support.writeU16(&bytes, class_subtable + 12, 0);
    support.writeU16(&bytes, class_subtable + 14, 16);
    support.writeU16(&bytes, class_subtable + 16, 1);
    support.writeU16(&bytes, class_subtable + 18, 4);
    support.writeU16(&bytes, class_subtable + 20, 0);
    support.writeU16(&bytes, class_subtable + 22, 1);
    support.writeU16(&bytes, class_subtable + 24, 0);
    support.writeU16(&bytes, class_subtable + 26, 0);
    support.writeCoverage1(&bytes, class_subtable + 50, &.{1});
    support.writeClassDef1(&bytes, class_subtable + 56, 1, &.{1});
    try validation.contextual.chaining.validate(
        support.Validator,
        support.validatedView(&bytes),
        class_subtable,
        .strict,
    );
}

test "chaining coverage strict and shaping modes differ only on membership order" {
    var bytes = [_]u8{0} ** 128;
    support.installLookupList(&bytes, 100, 110);
    const subtable = 20;
    support.writeU16(&bytes, subtable, 3);
    support.writeU16(&bytes, subtable + 2, 1);
    support.writeU16(&bytes, subtable + 4, 18);
    support.writeU16(&bytes, subtable + 6, 1);
    support.writeU16(&bytes, subtable + 8, 28);
    support.writeU16(&bytes, subtable + 10, 0);
    support.writeU16(&bytes, subtable + 12, 0);
    support.writeU16(&bytes, subtable + 14, 0);
    support.writeU16(&bytes, subtable + 16, 0);
    support.writeCoverage1(&bytes, subtable + 18, &.{ 7, 7 });
    support.writeCoverage1(&bytes, subtable + 28, &.{8});

    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.chaining.validate(
            support.Validator,
            support.validatedView(&bytes),
            subtable,
            .strict,
        ),
    );
    try validation.contextual.chaining.validate(
        support.Validator,
        support.validatedView(&bytes),
        subtable,
        .shaping,
    );
}

test "chaining validation rejects null rules required input class and records" {
    var bytes = [_]u8{0} ** 256;
    support.installLookupList(&bytes, 220, 230);

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
        validation.contextual.chaining.validate(
            support.Validator,
            support.validatedView(&bytes),
            glyph_subtable,
            .strict,
        ),
    );

    const class_subtable = 80;
    support.writeU16(&bytes, class_subtable, 2);
    support.writeU16(&bytes, class_subtable + 2, 30);
    support.writeU16(&bytes, class_subtable + 4, 0);
    support.writeU16(&bytes, class_subtable + 6, 0);
    support.writeU16(&bytes, class_subtable + 8, 0);
    support.writeU16(&bytes, class_subtable + 10, 0);
    support.writeCoverage1(&bytes, class_subtable + 30, &.{1});
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.chaining.validate(
            support.Validator,
            support.validatedView(&bytes),
            class_subtable,
            .strict,
        ),
    );

    const coverage_subtable = 140;
    support.writeU16(&bytes, coverage_subtable, 3);
    support.writeU16(&bytes, coverage_subtable + 2, 0);
    support.writeU16(&bytes, coverage_subtable + 4, 1);
    support.writeU16(&bytes, coverage_subtable + 6, 18);
    support.writeU16(&bytes, coverage_subtable + 8, 0);
    support.writeU16(&bytes, coverage_subtable + 10, 1);
    support.writeRecord(&bytes, coverage_subtable + 12, 0, 1);
    support.writeCoverage1(&bytes, coverage_subtable + 18, &.{1});
    try std.testing.expectError(
        error.BadGsub,
        validation.contextual.chaining.validate(
            support.Validator,
            support.validatedView(&bytes),
            coverage_subtable,
            .strict,
        ),
    );
}
