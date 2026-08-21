//! Caller-supplied OpenType GSUB values scoped to UTF-8 byte ranges.
//!
//! HarfBuzz keys feature ranges by the input buffer's cluster values. Cangjie's
//! public clusters are UTF-8 byte offsets, so retaining the same coordinate
//! system keeps substring shaping and cardinality-changing GSUB stable without
//! converting ranges to transient source-array indexes.

const std = @import("std");

pub const Range = struct {
    tag: u32,
    value: u32,
    byte_start: usize,
    byte_end: usize,

    pub fn contains(self: Range, byte_offset: usize) bool {
        return byte_offset >= self.byte_start and byte_offset < self.byte_end;
    }
};

/// One distinct feature value, preserving the caller's first-seen order.
pub const TagValue = struct {
    tag: u32,
    value: u32,
};

pub fn valueAt(
    ranges: []const Range,
    tag: u32,
    byte_offset: usize,
) ?u32 {
    // Match hb_shape(): when equal tags overlap, the feature with the higher
    // caller-supplied index wins. Reverse traversal also keeps the common
    // no-match case allocation-free and requires no range normalization.
    var index = ranges.len;
    while (index > 0) {
        index -= 1;
        const range = ranges[index];
        if (range.tag == tag and range.contains(byte_offset)) {
            return range.value;
        }
    }
    return null;
}

pub fn hasTag(ranges: []const Range, tag: u32) bool {
    for (ranges) |range| {
        if (range.tag == tag) return true;
    }
    return false;
}

pub fn globalValueForTag(
    overrides: anytype,
    tag: u32,
) ?u32 {
    for (overrides) |override| {
        if (override.tag == tag) return override.effectiveValue();
    }
    return null;
}

pub fn effectiveValueAt(
    ranges: []const Range,
    overrides: anytype,
    tag: u32,
    byte_offset: usize,
) u32 {
    return valueAt(ranges, tag, byte_offset) orelse
        globalValueForTag(overrides, tag) orelse
        defaultValue(tag);
}

pub fn appendDistinctEffectiveValues(
    out: []TagValue,
    ranges: []const Range,
    overrides: anytype,
) usize {
    var count: usize = 0;
    for (ranges) |range| {
        var tag_seen = false;
        for (out[0..count]) |existing| {
            if (existing.tag == range.tag) {
                tag_seen = true;
                break;
            }
        }
        if (tag_seen) continue;
        for (ranges) |candidate| {
            if (candidate.tag != range.tag) continue;
            appendDistinctTagValue(out, &count, .{
                .tag = candidate.tag,
                .value = candidate.value,
            });
        }
        appendDistinctTagValue(out, &count, .{
            .tag = range.tag,
            .value = globalValueForTag(overrides, range.tag) orelse
                defaultValue(range.tag),
        });
    }
    return count;
}

fn appendDistinctTagValue(out: []TagValue, count: *usize, value: TagValue) void {
    for (out[0..count.*]) |existing| {
        if (existing.tag == value.tag and existing.value == value.value) return;
    }
    std.debug.assert(count.* < out.len);
    out[count.*] = value;
    count.* += 1;
}

pub fn defaultValue(tag: u32) u32 {
    // These are the global default-on GSUB features in HarfBuzz's common
    // shaping plan and Cangjie's generic shaper. Directional and automatic
    // fraction defaults are rejected by the first ranged API rather than
    // guessed here.
    return if (tag == openTypeTag("ccmp") or
        tag == openTypeTag("locl") or
        tag == openTypeTag("rvrn") or
        tag == openTypeTag("rlig") or
        tag == openTypeTag("liga") or
        tag == openTypeTag("clig") or
        tag == openTypeTag("calt") or
        tag == openTypeTag("rclt"))
        1
    else
        0;
}

pub fn isSupportedGenericTag(tag: u32) bool {
    return tag != openTypeTag("rand") and
        tag != openTypeTag("frac") and
        tag != openTypeTag("numr") and
        tag != openTypeTag("dnom");
}

pub fn fillEffectiveValues(
    values: []u32,
    source_byte_starts: []const usize,
    ranges: []const Range,
    overrides: anytype,
    tag: u32,
) bool {
    if (values.len != source_byte_starts.len) return false;
    for (source_byte_starts, values) |byte, *value| {
        value.* = effectiveValueAt(ranges, overrides, tag, byte);
    }
    return true;
}

fn openTypeTag(comptime bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

test "later overlapping feature ranges take precedence" {
    const tag = @as(u32, 't') << 24 |
        @as(u32, 'e') << 16 |
        @as(u32, 's') << 8 |
        @as(u32, 't');
    const ranges = [_]Range{
        .{ .tag = tag, .value = 1, .byte_start = 1, .byte_end = 6 },
        .{ .tag = tag, .value = 3, .byte_start = 4, .byte_end = 5 },
    };
    try std.testing.expectEqual(@as(?u32, null), valueAt(&ranges, tag, 0));
    try std.testing.expectEqual(@as(?u32, 1), valueAt(&ranges, tag, 2));
    try std.testing.expectEqual(@as(?u32, 3), valueAt(&ranges, tag, 4));
    try std.testing.expectEqual(@as(?u32, null), valueAt(&ranges, tag, 6));
}
