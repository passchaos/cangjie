//! Unicode 17.0 default sentence-boundary iterator (UAX #29, SB1–SB998).
//!
//! The iterator owns no allocation and returns every segment, including
//! segments containing only separators or formatting controls. Higher-level
//! collectors may filter blank segments, but they must not alter the boundary
//! state machine.

const std = @import("std");

const data = @embedFile("data.bin");
const test_data = @embedFile("conformance.bin");

pub const unicode_version = [3]u8{ 17, 0, 0 };
pub const Error = error{InvalidUtf8};

pub const Segment = struct {
    byte_start: usize,
    byte_len: usize,
};

const Class = enum(u4) {
    other,
    cr,
    lf,
    sep,
    extend,
    format,
    space,
    lower,
    upper,
    other_letter,
    numeric,
    a_term,
    s_term,
    close,
    s_continue,
};

const Header = struct {
    index_count: usize,
    page_count: usize,
    index_offset: usize,
    pages_offset: usize,
};

const header = parseHeader();

pub const Iterator = struct {
    text: []const u8,
    cursor: usize = 0,
    /// SB8 can inspect beyond the next candidate boundary. Candidate offsets
    /// only move forward, so one cached decision interval makes all such
    /// lookahead linear even for adversarial repeated-terminator input.
    lower_scan_end: usize = 0,
    lower_scan_result: bool = false,

    pub fn next(self: *Iterator) ?Segment {
        if (self.cursor >= self.text.len) return null;
        const start = self.cursor;
        const first = decode(self.text, start) orelse unreachable;
        var state = BoundaryState{};
        state.consume(classForCodepoint(first.codepoint));

        var end = first.next;
        while (end < self.text.len) {
            const current = decode(self.text, end) orelse unreachable;
            const current_class = classForCodepoint(current.codepoint);
            if (self.breaksAt(end, current_class, state)) break;
            state.consume(current_class);
            end = current.next;
        }
        self.cursor = end;
        return .{ .byte_start = start, .byte_len = end - start };
    }

    fn breaksAt(
        self: *Iterator,
        offset: usize,
        current: Class,
        state: BoundaryState,
    ) bool {
        // SB3.
        if (state.previous_actual == .cr and current == .lf) return false;
        // SB4 is evaluated before ignore replacement. Starting a fresh state
        // after this boundary prevents leading Extend/Format characters from
        // seeing the separator in the previous segment.
        if (isParagraphSeparator(state.previous_actual)) return true;
        // SB5.
        if (isIgnored(current)) return false;
        // SB6.
        if (state.last_significant == .a_term and current == .numeric) {
            return false;
        }
        // SB7.
        if ((state.previous_significant == .upper or
            state.previous_significant == .lower) and
            state.last_significant == .a_term and current == .upper)
        {
            return false;
        }

        const terminator = state.terminator orelse return false; // SB998.
        // SB8. The cached forward query ignores Extend/Format and stops at the
        // first Lower or a class that the rule explicitly excludes.
        if (terminator.class == .a_term and self.lowerFollows(offset)) {
            return false;
        }
        // SB8a.
        if (current == .s_continue or isSentenceTerminator(current)) {
            return false;
        }
        // SB9 / SB10.
        if (current == .close and !terminator.saw_space) return false;
        if (current == .space or isParagraphSeparator(current)) return false;
        // SB11.
        return true;
    }

    fn lowerFollows(self: *Iterator, offset: usize) bool {
        if (offset <= self.lower_scan_end) return self.lower_scan_result;

        var cursor = offset;
        while (decode(self.text, cursor)) |decoded| {
            const class = classForCodepoint(decoded.codepoint);
            if (class == .lower) {
                self.lower_scan_end = decoded.start;
                self.lower_scan_result = true;
                return true;
            }
            if (class == .other_letter or class == .upper or
                isParagraphSeparator(class))
            {
                self.lower_scan_end = decoded.start;
                self.lower_scan_result = false;
                return false;
            }
            cursor = decoded.next;
        }
        self.lower_scan_end = self.text.len;
        self.lower_scan_result = false;
        return false;
    }
};

const TerminatorContext = struct {
    class: Class,
    saw_space: bool = false,
};

const BoundaryState = struct {
    previous_actual: Class = .other,
    previous_significant: Class = .other,
    last_significant: Class = .other,
    terminator: ?TerminatorContext = null,

    fn consume(self: *BoundaryState, class: Class) void {
        self.previous_actual = class;
        if (isIgnored(class)) return;

        self.previous_significant = self.last_significant;
        self.last_significant = class;
        if (isSentenceTerminator(class)) {
            self.terminator = .{ .class = class };
            return;
        }
        if (self.terminator) |*terminator| {
            if (class == .close and !terminator.saw_space) return;
            if (class == .space) {
                terminator.saw_space = true;
                return;
            }
        }
        self.terminator = null;
    }
};

pub fn segments(text: []const u8) Error!Iterator {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    return assumeValid(text);
}

pub fn assumeValid(text: []const u8) Iterator {
    std.debug.assert(std.unicode.utf8ValidateSlice(text));
    return .{ .text = text };
}

fn isIgnored(class: Class) bool {
    return class == .extend or class == .format;
}

fn isParagraphSeparator(class: Class) bool {
    return class == .sep or class == .cr or class == .lf;
}

fn isSentenceTerminator(class: Class) bool {
    return class == .a_term or class == .s_term;
}

const Decoded = struct {
    codepoint: u21,
    start: usize,
    next: usize,
};

fn classForCodepoint(codepoint: u21) Class {
    const page = @as(usize, codepoint) >> 8;
    const slot = readU16(header.index_offset + page * 2);
    return @enumFromInt(data[
        header.pages_offset + @as(usize, slot) * 256 +
            (@as(usize, codepoint) & 0xff)
    ]);
}

fn decode(text: []const u8, offset: usize) ?Decoded {
    if (offset >= text.len) return null;
    const sequence_len = std.unicode.utf8ByteSequenceLength(text[offset]) catch
        return null;
    if (offset + sequence_len > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[offset .. offset + sequence_len]) catch
        return null;
    return .{ .codepoint = codepoint, .start = offset, .next = offset + sequence_len };
}

fn parseHeader() Header {
    if (data.len < 12 or !std.mem.eql(u8, data[0..4], "CJSB") or
        data[4] != 1 or data[5] != unicode_version[0] or
        data[6] != unicode_version[1] or data[7] != unicode_version[2])
    {
        @compileError("invalid sentence-break data");
    }
    const index_count = readU16(8);
    const page_count = readU16(10);
    const index_offset = 12;
    const pages_offset = index_offset + index_count * 2;
    if (index_count != 0x1100 or
        pages_offset + page_count * 256 != data.len)
    {
        @compileError("invalid sentence-break data lengths");
    }
    return .{
        .index_count = index_count,
        .page_count = page_count,
        .index_offset = index_offset,
        .pages_offset = pages_offset,
    };
}

fn readU16(offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

test "Unicode 17 sentence-boundary conformance" {
    if (test_data.len < 12 or !std.mem.eql(u8, test_data[0..4], "CJST") or
        test_data[4] != 1 or test_data[5] != unicode_version[0] or
        test_data[6] != unicode_version[1] or test_data[7] != unicode_version[2])
    {
        return error.InvalidFixture;
    }
    const case_count = std.mem.readInt(u32, test_data[8..12], .little);
    try std.testing.expectEqual(@as(u32, 512), case_count);

    var offset: usize = 12;
    for (0..case_count) |case_index| {
        const count = test_data[offset];
        offset += 1;
        const expected = test_data[offset..][0 .. @as(usize, count) + 1];
        offset += @as(usize, count) + 1;
        const codepoint_bytes = test_data[offset..][0 .. @as(usize, count) * 4];
        offset += @as(usize, count) * 4;

        var utf8: [256]u8 = undefined;
        var utf8_len: usize = 0;
        var expected_offsets: [64]usize = undefined;
        var expected_count: usize = 0;
        if (expected[0] != 0) {
            expected_offsets[expected_count] = 0;
            expected_count += 1;
        }
        for (0..count) |index| {
            const codepoint: u21 = @intCast(std.mem.readInt(
                u32,
                codepoint_bytes[index * 4 ..][0..4],
                .little,
            ));
            utf8_len += try std.unicode.utf8Encode(codepoint, utf8[utf8_len..]);
            if (expected[index + 1] != 0) {
                expected_offsets[expected_count] = utf8_len;
                expected_count += 1;
            }
        }

        var iterator = assumeValid(utf8[0..utf8_len]);
        var actual_count: usize = 1;
        while (iterator.next()) |segment| {
            const actual_end = segment.byte_start + segment.byte_len;
            if (actual_count >= expected_count or
                expected_offsets[actual_count] != actual_end)
            {
                std.debug.print(
                    "sentence case={d} boundary={d} expected={d} actual={d}\n",
                    .{
                        case_index,
                        actual_count,
                        if (actual_count < expected_count)
                            expected_offsets[actual_count]
                        else
                            std.math.maxInt(usize),
                        actual_end,
                    },
                );
                return error.SentenceBreakConformanceMismatch;
            }
            actual_count += 1;
        }
        try std.testing.expectEqual(expected_count, actual_count);
    }
    try std.testing.expectEqual(test_data.len, offset);
}
