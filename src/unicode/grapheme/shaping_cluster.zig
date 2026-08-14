//! Shaping-cluster boundaries used to initialize OpenType source ownership.
//!
//! These boundaries intentionally remain separate from public UAX #29
//! graphemes. HarfBuzz's default `monotone_graphemes` level uses category and
//! shaper tailoring that is not a caret-boundary contract; changing it whenever
//! Cangjie updates Unicode data would alter GSUB cluster provenance.

const std = @import("std");
const unicode = @import("../../unicode.zig");

pub const Cluster = struct {
    byte_start: usize,
    byte_len: usize,
};

const Decoded = struct {
    codepoint: u21,
    next: usize,
};

pub const Iterator = struct {
    text: []const u8,
    cursor: usize = 0,
    pending: ?Decoded = null,

    pub fn next(self: *Iterator) ?Cluster {
        if (self.cursor >= self.text.len) return null;

        const start = self.cursor;
        const first = self.pending orelse decode(self.text, self.cursor) orelse unreachable;
        self.pending = null;
        self.cursor = first.next;

        var previous = first.codepoint;
        var last_non_extend: ?u21 =
            if (isExtend(first.codepoint) or first.codepoint == 0x200d)
                null
            else
                first.codepoint;
        var zwj_after_extended_pictographic = false;
        var zwj_after_indic_virama = false;
        var regional_indicator_count: usize =
            if (isRegionalIndicator(first.codepoint)) 1 else 0;

        // Ordinary ASCII is its own shaping cluster except for CRLF. Keeping
        // this fast path avoids property work in word-list shaping.
        if (first.codepoint < 0x80 and self.cursor < self.text.len and
            self.text[self.cursor] < 0x80 and
            !(first.codepoint == '\r' and self.text[self.cursor] == '\n'))
        {
            return .{ .byte_start = start, .byte_len = self.cursor - start };
        }

        while (self.cursor < self.text.len) {
            const current = decode(self.text, self.cursor) orelse unreachable;
            if (!extendsCluster(
                previous,
                current.codepoint,
                regional_indicator_count,
                zwj_after_extended_pictographic,
                zwj_after_indic_virama,
            )) {
                self.pending = current;
                break;
            }

            self.cursor = current.next;
            if (current.codepoint == 0x200d) {
                zwj_after_extended_pictographic = if (last_non_extend) |last|
                    isExtendedPictographic(last)
                else
                    false;
                zwj_after_indic_virama = isIndicVirama(previous);
            } else {
                zwj_after_extended_pictographic = false;
                zwj_after_indic_virama = false;
                if (!isExtend(current.codepoint)) last_non_extend = current.codepoint;
            }
            previous = current.codepoint;
            if (isRegionalIndicator(current.codepoint)) {
                regional_indicator_count += 1;
            } else if (current.codepoint != 0x200d) {
                regional_indicator_count = 0;
            }
        }

        return .{ .byte_start = start, .byte_len = self.cursor - start };
    }
};

pub fn clusters(text: []const u8) error{InvalidUtf8}!Iterator {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    return .{ .text = text };
}

pub fn itemize(allocator: std.mem.Allocator, text: []const u8) ![]Cluster {
    var result = std.ArrayList(Cluster).empty;
    errdefer result.deinit(allocator);
    var iterator = try clusters(text);
    while (iterator.next()) |cluster| try result.append(allocator, cluster);
    return try result.toOwnedSlice(allocator);
}

fn extendsCluster(
    previous: u21,
    current: u21,
    regional_indicator_count: usize,
    zwj_after_extended_pictographic: bool,
    zwj_after_indic_virama: bool,
) bool {
    if (previous == '\r' and current == '\n') return true;
    if (isControl(previous) or isControl(current)) return false;
    if (isPrepend(previous)) return true;
    if (current == 0x200d) return true;
    if (extendsHangul(previous, current)) return true;
    if (isRegionalIndicator(previous) and isRegionalIndicator(current) and
        regional_indicator_count % 2 == 1) return true;
    if (isExtend(current)) return true;
    if (previous == 0x17d2 and current >= 0x1780 and current <= 0x17a2) return true;
    if (previous == 0x11442 and current >= 0x1140e and current <= 0x11434) return true;
    if (previous == 0xa8c4 and current >= 0xa892 and current <= 0xa8b3) return true;
    if (previous == 0x1134d and isGranthaConsonant(current)) return true;
    if (previous == 0x111c0 and current >= 0x11191 and current <= 0x111b2) return true;
    if (previous == 0x200d) {
        return (zwj_after_extended_pictographic and isExtendedPictographic(current)) or
            (zwj_after_indic_virama and isIndicConsonant(current));
    }
    return false;
}

const HangulClass = enum { other, l, v, t, lv, lvt };

fn extendsHangul(previous: u21, current: u21) bool {
    const previous_class = hangulClass(previous);
    const current_class = hangulClass(current);
    return switch (previous_class) {
        .l => current_class == .l or current_class == .v or
            current_class == .lv or current_class == .lvt,
        .v, .lv => current_class == .v or current_class == .t,
        .t, .lvt => current_class == .t,
        .other => false,
    };
}

fn hangulClass(codepoint: u21) HangulClass {
    if ((codepoint >= 0x1100 and codepoint <= 0x115f) or
        (codepoint >= 0xa960 and codepoint <= 0xa97c)) return .l;
    if ((codepoint >= 0x1160 and codepoint <= 0x11a7) or
        (codepoint >= 0xd7b0 and codepoint <= 0xd7c6)) return .v;
    if ((codepoint >= 0x11a8 and codepoint <= 0x11ff) or
        (codepoint >= 0xd7cb and codepoint <= 0xd7fb)) return .t;
    if (codepoint >= 0xac00 and codepoint <= 0xd7a3) {
        return if ((codepoint - 0xac00) % 28 == 0) .lv else .lvt;
    }
    return .other;
}

fn isExtend(codepoint: u21) bool {
    return codepoint == 0x200c or
        unicode.isUnicodeMarkCodepoint(codepoint) or
        isLegacySpacingMarkOverride(codepoint) or
        unicode.isVariationSelector(codepoint) or
        (codepoint >= 0x1f3fb and codepoint <= 0x1f3ff) or
        (codepoint >= 0xe0020 and codepoint <= 0xe007f);
}

fn isLegacySpacingMarkOverride(codepoint: u21) bool {
    // These visible shaping signs were part of Cangjie's established source
    // ownership before Unicode 17 data replaced the compact grapheme table.
    // Most have GCB=Other, so they belong here rather than in public UAX #29.
    return switch (codepoint) {
        0x0c3d,
        0x0cbd,
        0x102b...0x102c,
        0x1038,
        0x1062...0x1064,
        0x1067...0x106d,
        0x1083,
        0x1087...0x108c,
        0x108f,
        0x109a...0x109c,
        0x1a61,
        0x1a63...0x1a64,
        0xaa7b,
        0xaa7d,
        0xabeb,
        => true,
        else => false,
    };
}

fn isControl(codepoint: u21) bool {
    return codepoint <= 0x001f or
        (codepoint >= 0x007f and codepoint <= 0x009f) or
        codepoint == 0x00ad or codepoint == 0x061c or codepoint == 0x180e or
        codepoint == 0x200b or (codepoint >= 0x200e and codepoint <= 0x200f) or
        codepoint == 0x2028 or codepoint == 0x2029 or
        (codepoint >= 0x202a and codepoint <= 0x202e) or
        (codepoint >= 0x2060 and codepoint <= 0x206f) or
        codepoint == 0xfeff or (codepoint >= 0xfff0 and codepoint <= 0xfff8);
}

fn isPrepend(codepoint: u21) bool {
    return (codepoint >= 0x0600 and codepoint <= 0x0605) or
        codepoint == 0x06dd or codepoint == 0x070f or
        (codepoint >= 0x0890 and codepoint <= 0x0891) or
        codepoint == 0x08e2 or codepoint == 0x0d4e or
        codepoint == 0x110bd or codepoint == 0x110cd;
}

fn isExtendedPictographic(codepoint: u21) bool {
    return codepoint == 0x00a9 or codepoint == 0x00ae or
        codepoint == 0x203c or codepoint == 0x2049 or codepoint == 0x2122 or
        codepoint == 0x2139 or (codepoint >= 0x2194 and codepoint <= 0x21aa) or
        codepoint == 0x231a or codepoint == 0x231b or codepoint == 0x2328 or
        codepoint == 0x23cf or (codepoint >= 0x23e9 and codepoint <= 0x23f3) or
        (codepoint >= 0x23f8 and codepoint <= 0x23fa) or codepoint == 0x24c2 or
        codepoint == 0x25aa or codepoint == 0x25ab or codepoint == 0x25b6 or
        codepoint == 0x25c0 or (codepoint >= 0x25fb and codepoint <= 0x25fe) or
        (codepoint >= 0x2600 and codepoint <= 0x27bf) or
        codepoint == 0x2934 or codepoint == 0x2935 or
        (codepoint >= 0x2b05 and codepoint <= 0x2b55) or
        codepoint == 0x3030 or codepoint == 0x303d or
        codepoint == 0x3297 or codepoint == 0x3299 or
        (codepoint >= 0x1f000 and codepoint <= 0x1faff);
}

fn isIndicVirama(codepoint: u21) bool {
    return switch (codepoint) {
        0x094d,
        0x0acd,
        0x0b4d,
        0x0a4d,
        0x0c4d,
        0x0ccd,
        0x0d4d,
        0x11046,
        0x110b9,
        0x11133,
        0x11442,
        0xa8c4,
        0x1134d,
        0x111c0,
        0x11070,
        => true,
        else => false,
    };
}

fn isIndicConsonant(codepoint: u21) bool {
    return (codepoint >= 0x0915 and codepoint <= 0x0939) or
        (codepoint >= 0x0958 and codepoint <= 0x095f) or
        (codepoint >= 0x0a95 and codepoint <= 0x0ab9) or
        (codepoint >= 0x0b15 and codepoint <= 0x0b39) or
        codepoint == 0x0b5c or codepoint == 0x0b5d or codepoint == 0x0b5f or
        (codepoint >= 0x0a15 and codepoint <= 0x0a39) or
        (codepoint >= 0x0a59 and codepoint <= 0x0a5e) or
        (codepoint >= 0x0a72 and codepoint <= 0x0a74) or
        (codepoint >= 0x0c15 and codepoint <= 0x0c39) or
        codepoint == 0x0c58 or codepoint == 0x0c59 or
        (codepoint >= 0x0c95 and codepoint <= 0x0cb9) or
        (codepoint >= 0x0d15 and codepoint <= 0x0d3a) or
        (codepoint >= 0x11013 and codepoint <= 0x11037) or
        (codepoint >= 0x1108d and codepoint <= 0x110af) or
        (codepoint >= 0x11107 and codepoint <= 0x11126) or
        codepoint == 0x11144 or codepoint == 0x11147 or
        (codepoint >= 0x1140e and codepoint <= 0x11434) or
        (codepoint >= 0xa892 and codepoint <= 0xa8b3) or
        isGranthaConsonant(codepoint) or
        (codepoint >= 0x11191 and codepoint <= 0x111b2);
}

fn isGranthaConsonant(codepoint: u21) bool {
    return (codepoint >= 0x11315 and codepoint <= 0x11328) or
        (codepoint >= 0x1132a and codepoint <= 0x11330) or
        (codepoint >= 0x11332 and codepoint <= 0x11333) or
        (codepoint >= 0x11335 and codepoint <= 0x11339);
}

fn isRegionalIndicator(codepoint: u21) bool {
    return codepoint >= 0x1f1e6 and codepoint <= 0x1f1ff;
}

fn decode(text: []const u8, offset: usize) ?Decoded {
    if (offset >= text.len) return null;
    const sequence_len = std.unicode.utf8ByteSequenceLength(text[offset]) catch return null;
    if (offset + sequence_len > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[offset .. offset + sequence_len]) catch
        return null;
    return .{ .codepoint = codepoint, .next = offset + sequence_len };
}

test "shaping clusters preserve tailored source ownership" {
    const allocator = std.testing.allocator;
    const samples = [_]struct { text: []const u8, expected: []const Cluster }{
        .{
            .text = "ᨽ᩠ᨽᩣ",
            .expected = &.{
                .{ .byte_start = 0, .byte_len = 6 },
                .{ .byte_start = 6, .byte_len = 6 },
            },
        },
        .{
            .text = "ൎക്കെ",
            .expected = &.{
                .{ .byte_start = 0, .byte_len = 9 },
                .{ .byte_start = 9, .byte_len = 6 },
            },
        },
    };
    for (samples) |sample| {
        const actual = try itemize(allocator, sample.text);
        defer allocator.free(actual);
        try std.testing.expectEqualSlices(Cluster, sample.expected, actual);
    }
}
