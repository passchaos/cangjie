//! UTF-8 ranged paragraph wrapping policy.
//!
//! A soft boundary is owned by the source scalar immediately preceding it.
//! This mirrors the forward line breaker: a style controls whether text after
//! it may wrap only after one of that style's source atoms has been consumed.
//! Hard Unicode boundaries remain mandatory regardless of ranged policy.

const std = @import("std");

const paragraph_types = @import("../types/paragraph.zig");

pub const Policy = struct {
    wrap_mode: paragraph_types.WrapMode,
    word_break: paragraph_types.WordBreak,
    overflow_wrap: paragraph_types.OverflowWrap,

    pub fn eql(lhs: Policy, rhs: Policy) bool {
        return lhs.wrap_mode == rhs.wrap_mode and
            lhs.word_break == rhs.word_break and
            lhs.overflow_wrap == rhs.overflow_wrap;
    }
};

/// Optional wrapping overrides for one UTF-8 source range.
///
/// Ranges are ordered, non-overlapping, and half-open. Null fields inherit the
/// paragraph default independently, allowing attributed styles to override
/// only the CSS Text axis they actually specify.
pub const Range = struct {
    byte_start: usize,
    byte_len: usize,
    wrap_mode: ?paragraph_types.WrapMode = null,
    word_break: ?paragraph_types.WordBreak = null,
    overflow_wrap: ?paragraph_types.OverflowWrap = null,

    pub fn byteEnd(self: Range) usize {
        return self.byte_start + self.byte_len;
    }

    fn apply(self: Range, defaults: Policy) Policy {
        return .{
            .wrap_mode = self.wrap_mode orelse defaults.wrap_mode,
            .word_break = self.word_break orelse defaults.word_break,
            .overflow_wrap = self.overflow_wrap orelse
                defaults.overflow_wrap,
        };
    }
};

pub fn validate(ranges: []const Range) !void {
    var previous_end: usize = 0;
    for (ranges, 0..) |range, index| {
        if (range.byte_len == 0 or
            range.byte_start > std.math.maxInt(usize) - range.byte_len or
            (range.wrap_mode == null and
                range.word_break == null and
                range.overflow_wrap == null) or
            (index != 0 and range.byte_start < previous_end))
        {
            return error.InvalidParagraphOptions;
        }
        previous_end = range.byteEnd();
    }
}

pub fn validateForText(text: []const u8, ranges: []const Range) !void {
    try validate(ranges);
    for (ranges) |range| {
        if (range.byteEnd() > text.len or
            !isUtf8Boundary(text, range.byte_start) or
            !isUtf8Boundary(text, range.byteEnd()))
        {
            return error.InvalidParagraphOptions;
        }
    }
}

/// Resolve the policy for a source byte known to lie inside one scalar.
pub fn atByte(
    defaults: Policy,
    ranges: []const Range,
    byte_offset: usize,
) Policy {
    for (ranges) |range| {
        if (range.byte_start > byte_offset) break;
        if (byte_offset < range.byteEnd()) return range.apply(defaults);
    }
    return defaults;
}

/// Resolve a candidate boundary from the scalar immediately before it.
pub fn beforeBoundary(
    defaults: Policy,
    ranges: []const Range,
    byte_offset: usize,
) Policy {
    if (byte_offset == 0) return defaults;
    for (ranges) |range| {
        if (range.byte_start >= byte_offset) break;
        if (byte_offset <= range.byteEnd()) return range.apply(defaults);
    }
    return defaults;
}

pub fn requiresOpportunityTailoring(
    defaults: Policy,
    ranges: []const Range,
) bool {
    return ranges.len != 0 or
        defaults.wrap_mode == .no_wrap or
        defaults.word_break != .normal or
        defaults.overflow_wrap == .anywhere;
}

/// Whether any source byte may participate in width-induced wrapping.
pub fn anyWrappingEnabled(
    text_len: usize,
    defaults: Policy,
    ranges: []const Range,
) bool {
    if (text_len == 0) return defaults.wrap_mode != .no_wrap;
    var cursor: usize = 0;
    for (ranges) |range| {
        if (cursor < @min(range.byte_start, text_len) and
            defaults.wrap_mode != .no_wrap)
        {
            return true;
        }
        if (range.byte_start >= text_len) break;
        if (range.apply(defaults).wrap_mode != .no_wrap) return true;
        cursor = @min(text_len, range.byteEnd());
    }
    return cursor < text_len and defaults.wrap_mode != .no_wrap;
}

/// Conservative request-only form used by geometry that has no source slice.
pub fn wrappingMayBeEnabled(
    defaults: Policy,
    ranges: []const Range,
) bool {
    if (defaults.wrap_mode != .no_wrap) return true;
    for (ranges) |range| {
        if (range.apply(defaults).wrap_mode != .no_wrap) return true;
    }
    return false;
}

fn isUtf8Boundary(text: []const u8, byte_offset: usize) bool {
    if (byte_offset > text.len) return false;
    if (byte_offset == 0 or byte_offset == text.len) return true;
    return (text[byte_offset] & 0xc0) != 0x80;
}

test "boundary policy belongs to the preceding source range" {
    const defaults = Policy{
        .wrap_mode = .word,
        .word_break = .normal,
        .overflow_wrap = .break_word,
    };
    const ranges = [_]Range{.{
        .byte_start = 1,
        .byte_len = 2,
        .wrap_mode = .no_wrap,
    }};
    try std.testing.expectEqual(
        paragraph_types.WrapMode.word,
        beforeBoundary(defaults, &ranges, 1).wrap_mode,
    );
    try std.testing.expectEqual(
        paragraph_types.WrapMode.no_wrap,
        beforeBoundary(defaults, &ranges, 2).wrap_mode,
    );
    try std.testing.expectEqual(
        paragraph_types.WrapMode.no_wrap,
        beforeBoundary(defaults, &ranges, 3).wrap_mode,
    );
    try std.testing.expectEqual(
        paragraph_types.WrapMode.word,
        beforeBoundary(defaults, &ranges, 4).wrap_mode,
    );
}
