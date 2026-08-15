//! Source-scoped numerator, fraction, and denominator masks.

const unicode = @import("../../../unicode.zig");

pub const Stage = enum {
    numerator,
    fraction,
    denominator,
};

const Run = struct {
    start: usize,
    slash: usize,
    end: usize,
};

pub fn hasRunnable(codepoints: []const u21) bool {
    return firstRunFrom(codepoints, 0) != null;
}

pub fn mark(
    source_features: []u32,
    codepoints: []const u21,
    stage: Stage,
) bool {
    @memset(source_features, 0);
    var any = false;
    var search_start: usize = 0;
    const Range = struct {
        start: usize,
        end: usize,
        tag: u32,
    };
    while (firstRunFrom(codepoints, search_start)) |run| {
        const range: Range = switch (stage) {
            .numerator => .{
                .start = run.start,
                .end = run.slash,
                .tag = unicode.tag("numr"),
            },
            .fraction => .{
                .start = run.start,
                .end = run.end,
                .tag = unicode.tag("frac"),
            },
            .denominator => .{
                .start = run.slash + 1,
                .end = run.end,
                .tag = unicode.tag("dnom"),
            },
        };
        for (range.start..range.end) |index| {
            source_features[index] = range.tag;
        }
        any = true;
        search_start = run.end;
    }
    return any;
}

fn firstRunFrom(codepoints: []const u21, start_index: usize) ?Run {
    var index = start_index;
    while (index < codepoints.len) : (index += 1) {
        if (codepoints[index] != 0x2044) continue;
        var start = index;
        while (start > 0 and isDecimal(codepoints[start - 1])) start -= 1;
        var end = index + 1;
        while (end < codepoints.len and isDecimal(codepoints[end])) end += 1;
        if (start == index or end == index + 1) continue;
        return .{ .start = start, .slash = index, .end = end };
    }
    return null;
}

fn isDecimal(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669);
}
