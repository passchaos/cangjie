//! Pure bidi/reordering policy for shaping and paragraph orchestration.

const std = @import("std");

const plan = @import("root.zig");
const pipeline_types = @import("../pipeline/types.zig");
const unicode = @import("../../unicode.zig");

pub fn shouldReorderShapedRun(
    text: []const u8,
    options: plan.ShapeOptions,
    all_ascii: bool,
) bool {
    if (!options.reorder_bidi) return false;
    if (options.writing_mode.isVertical()) return false;
    if (options.direction == .rtl) return true;
    // No ASCII scalar has a strong RTL class. Property resolution can pass its
    // existing proof to avoid a second Unicode scan for common UI text.
    if (all_ascii) return false;
    return hasRtl(text);
}

pub fn paragraphNeedsReorder(
    text: []const u8,
    direction: pipeline_types.TextDirection,
) bool {
    return direction == .rtl or hasRtl(text);
}

pub fn hasRtl(text: []const u8) bool {
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint <= 0x7f) continue;
        if (unicode.bidiClassForCodepoint(codepoint) == .rtl) return true;
    }
    return false;
}

test "ASCII proof rejects visual reorder without hiding RTL scripts" {
    try std.testing.expect(!hasRtl("ASCII 123 ()"));
    try std.testing.expect(hasRtl("ASCII \u{05d0}"));
    try std.testing.expect(hasRtl("فارسی"));
    try std.testing.expect(!shouldReorderShapedRun(
        "ASCII 123 ()",
        .{},
        true,
    ));
    // Explicit RTL remains authoritative even when source is all ASCII.
    try std.testing.expect(shouldReorderShapedRun(
        "ASCII",
        .{ .direction = .rtl },
        true,
    ));
}
