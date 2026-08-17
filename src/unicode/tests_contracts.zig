//! Unicode contract tests migrated from the former aggregate root.

const std = @import("std");
const unicode = @import("../unicode.zig");

test "vertical orientation distinguishes upright scripts rotated Latin and transformed punctuation" {
    try std.testing.expectEqual(unicode.VerticalOrientation.upright, unicode.verticalOrientationForCodepoint('中'));
    try std.testing.expectEqual(unicode.VerticalOrientation.upright, unicode.verticalOrientationForCodepoint('あ'));
    try std.testing.expectEqual(unicode.VerticalOrientation.upright, unicode.verticalOrientationForCodepoint(0x1F600));
    try std.testing.expectEqual(unicode.VerticalOrientation.rotated, unicode.verticalOrientationForCodepoint('A'));
    try std.testing.expectEqual(unicode.VerticalOrientation.transformed_upright, unicode.verticalOrientationForCodepoint(0x3001));
    try std.testing.expectEqual(unicode.VerticalOrientation.transformed_rotated, unicode.verticalOrientationForCodepoint(0x3008));
}

test "vertical presentation fallback maps CJK punctuation forms" {
    try std.testing.expectEqual(@as(?u21, 0xfe3f), unicode.verticalPresentationCodepoint(0x3008));
    try std.testing.expectEqual(@as(?u21, 0xfe40), unicode.verticalPresentationCodepoint(0x3009));
    try std.testing.expectEqual(@as(?u21, 0xfe35), unicode.verticalPresentationCodepoint(0xff08));
    try std.testing.expectEqual(@as(?u21, null), unicode.verticalPresentationCodepoint('A'));
}

test "default-ignorable shaping fast path preserves the lowest boundary" {
    for (0..0x00ad) |codepoint| {
        try std.testing.expect(!unicode.isDefaultIgnorableForShaping(@intCast(codepoint)));
    }
    try std.testing.expect(unicode.isDefaultIgnorableForShaping(0x00ad));
    try std.testing.expect(!unicode.isDefaultIgnorableForShaping(0x00ae));
    try std.testing.expect(unicode.isDefaultIgnorableForShaping(0x034f));
    try std.testing.expect(unicode.isDefaultIgnorableForShaping(0xe0100));
}

test "modified combining class fast path preserves its lower boundary and overrides" {
    try std.testing.expectEqual(@as(u8, 0), unicode.modifiedCombiningClassForShaping(0x02ff));
    try std.testing.expectEqual(@as(u8, 230), unicode.modifiedCombiningClassForShaping(0x0300));
    try std.testing.expectEqual(@as(u8, 254), unicode.modifiedCombiningClassForShaping(0x1a60));
    try std.testing.expectEqual(@as(u8, 127), unicode.modifiedCombiningClassForShaping(0x0f39));
}
