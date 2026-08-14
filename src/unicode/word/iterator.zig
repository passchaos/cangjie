//! Unicode 17.0 default word-boundary iterator (UAX #29, WB1–WB999).
//!
//! The iterator reports every boundary segment. `is_word` is an orthogonal
//! editor-facing classification: punctuation and whitespace remain observable
//! to conformance callers, while compatibility collectors can retain only
//! segments that contain a selectable letter, number, connector, Katakana, or
//! ideographic scalar.

const std = @import("std");

const data = @embedFile("data.bin");
const test_data = @embedFile("conformance.bin");

pub const unicode_version = [3]u8{ 17, 0, 0 };
pub const Error = error{InvalidUtf8};

pub const Segment = struct {
    byte_start: usize,
    byte_len: usize,
    is_word: bool,
};

const Class = enum(u5) {
    other,
    cr,
    lf,
    newline,
    extend,
    format,
    katakana,
    a_letter,
    mid_letter,
    mid_num,
    mid_num_let,
    numeric,
    extend_num_let,
    regional_indicator,
    hebrew_letter,
    single_quote,
    double_quote,
    zwj,
    wseg_space,
};

const Properties = packed struct(u8) {
    class: Class,
    extended_pictographic: bool,
    word_anchor: bool,
    reserved: bool,
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

    pub fn next(self: *Iterator) ?Segment {
        if (self.cursor >= self.text.len) return null;

        const start = self.cursor;
        const first = decode(self.text, start) orelse unreachable;
        var end = first.next;
        const first_properties = properties(first.codepoint);
        var is_word = first_properties.word_anchor;
        var regional_indicator_count: usize =
            if (first_properties.class == .regional_indicator) 1 else 0;
        while (end < self.text.len) {
            const should_break = asciiBreaksAt(self.text, end) orelse breaksAt(
                self.text,
                end,
                regional_indicator_count,
            );
            if (should_break) break;
            const current = decode(self.text, end) orelse unreachable;
            const current_properties = properties(current.codepoint);
            is_word = is_word or current_properties.word_anchor;
            if (current_properties.class == .regional_indicator) {
                regional_indicator_count += 1;
            } else if (!isIgnored(current_properties.class)) {
                regional_indicator_count = 0;
            }
            end = current.next;
        }
        self.cursor = end;
        return .{
            .byte_start = start,
            .byte_len = end - start,
            .is_word = is_word,
        };
    }
};

fn asciiBreaksAt(text: []const u8, offset: usize) ?bool {
    const current_byte = text[offset];
    const previous_byte = text[offset - 1];
    if (current_byte >= 0x80 or previous_byte >= 0x80) return null;

    const previous = asciiClass(previous_byte);
    const current = asciiClass(current_byte);
    // WB3–WB3d. No ASCII scalar has WB=Extend/Format/ZWJ, so WB4 needs no
    // special handling in this path.
    if (previous == .cr and current == .lf) return false;
    if (isNewline(previous) or isNewline(current)) return true;
    if (previous == .wseg_space and current == .wseg_space) return false;
    // WB5.
    if (isAhLetter(previous) and isAhLetter(current)) return false;

    const next = if (offset + 1 < text.len) next: {
        if (text[offset + 1] >= 0x80) {
            if (isLetterMid(current) or isNumericMid(current)) return null;
            break :next Class.other;
        }
        break :next asciiClass(text[offset + 1]);
    } else Class.other;
    const previous_previous = if (offset >= 2) previous: {
        if (text[offset - 2] >= 0x80) {
            if (isLetterMid(previous) or isNumericMid(previous)) return null;
            break :previous Class.other;
        }
        break :previous asciiClass(text[offset - 2]);
    } else Class.other;

    // WB6 / WB7.
    if (isAhLetter(previous) and isLetterMid(current) and
        isAhLetter(next)) return false;
    if (isAhLetter(previous_previous) and isLetterMid(previous) and
        isAhLetter(current)) return false;
    // WB8–WB12.
    if (previous == .numeric and current == .numeric) return false;
    if (isAhLetter(previous) and current == .numeric) return false;
    if (previous == .numeric and isAhLetter(current)) return false;
    if (previous_previous == .numeric and isNumericMid(previous) and
        current == .numeric) return false;
    if (previous == .numeric and isNumericMid(current) and
        next == .numeric) return false;
    // WB13a / WB13b.
    if (isExtendNumLetLeft(previous) and current == .extend_num_let) return false;
    if (previous == .extend_num_let and isExtendNumLetRight(current)) return false;
    return true;
}

fn asciiClass(byte: u8) Class {
    return switch (byte) {
        '\r' => .cr,
        '\n' => .lf,
        0x0b, 0x0c => .newline,
        ' ' => .wseg_space,
        '"' => .double_quote,
        '\'' => .single_quote,
        ',', ';' => .mid_num,
        '.' => .mid_num_let,
        ':' => .mid_letter,
        '0'...'9' => .numeric,
        'A'...'Z', 'a'...'z' => .a_letter,
        '_' => .extend_num_let,
        else => .other,
    };
}

pub fn segments(text: []const u8) Error!Iterator {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    return assumeValid(text);
}

pub fn assumeValid(text: []const u8) Iterator {
    std.debug.assert(std.unicode.utf8ValidateSlice(text));
    return .{ .text = text };
}

fn breaksAt(
    text: []const u8,
    offset: usize,
    regional_indicator_count: usize,
) bool {
    const previous_actual = decodeBefore(text, offset) orelse unreachable;
    const current = decode(text, offset) orelse unreachable;
    const previous_actual_properties = properties(previous_actual.codepoint);
    const current_properties = properties(current.codepoint);

    // WB3.
    if (previous_actual_properties.class == .cr and
        current_properties.class == .lf) return false;
    // WB3a / WB3b. These precede WB4: ignored characters immediately after a
    // newline start their own segment instead of attaching to the control.
    if (isNewline(previous_actual_properties.class) or
        isNewline(current_properties.class)) return true;
    // WB3c is intentionally adjacent. ZWJ followed by Extend then an extended
    // pictograph does not match, because WB4 removes that ZWJ from rule input.
    if (previous_actual_properties.class == .zwj and
        current_properties.extended_pictographic) return false;
    // WB3d is also evaluated before ignore replacement.
    if (previous_actual_properties.class == .wseg_space and
        current_properties.class == .wseg_space) return false;
    // WB4.
    if (isIgnored(current_properties.class)) return false;

    const previous = previousSignificant(text, offset) orelse return true;
    const previous_properties = properties(previous.codepoint);
    if (isNewline(previous_properties.class)) return true;
    const previous_previous = previousSignificant(text, previous.start);
    const previous_previous_class = if (previous_previous) |decoded|
        properties(decoded.codepoint).class
    else
        Class.other;
    const next = nextSignificant(text, current.next);
    const next_class = if (next) |decoded|
        properties(decoded.codepoint).class
    else
        Class.other;

    // WB5.
    if (isAhLetter(previous_properties.class) and
        isAhLetter(current_properties.class)) return false;
    // WB6 / WB7.
    if (isAhLetter(previous_properties.class) and
        isLetterMid(current_properties.class) and
        isAhLetter(next_class)) return false;
    if (isAhLetter(previous_previous_class) and
        isLetterMid(previous_properties.class) and
        isAhLetter(current_properties.class)) return false;
    // WB7a / WB7b / WB7c.
    if (previous_properties.class == .hebrew_letter and
        current_properties.class == .single_quote) return false;
    if (previous_properties.class == .hebrew_letter and
        current_properties.class == .double_quote and
        next_class == .hebrew_letter) return false;
    if (previous_previous_class == .hebrew_letter and
        previous_properties.class == .double_quote and
        current_properties.class == .hebrew_letter) return false;
    // WB8–WB10.
    if (previous_properties.class == .numeric and
        current_properties.class == .numeric) return false;
    if (isAhLetter(previous_properties.class) and
        current_properties.class == .numeric) return false;
    if (previous_properties.class == .numeric and
        isAhLetter(current_properties.class)) return false;
    // WB11 / WB12.
    if (previous_previous_class == .numeric and
        isNumericMid(previous_properties.class) and
        current_properties.class == .numeric) return false;
    if (previous_properties.class == .numeric and
        isNumericMid(current_properties.class) and
        next_class == .numeric) return false;
    // WB13.
    if (previous_properties.class == .katakana and
        current_properties.class == .katakana) return false;
    // WB13a / WB13b.
    if (isExtendNumLetLeft(previous_properties.class) and
        current_properties.class == .extend_num_let) return false;
    if (previous_properties.class == .extend_num_let and
        isExtendNumLetRight(current_properties.class)) return false;
    // WB15 / WB16.
    if (previous_properties.class == .regional_indicator and
        current_properties.class == .regional_indicator and
        regional_indicator_count % 2 == 1) return false;

    // WB999.
    return true;
}

fn isNewline(class: Class) bool {
    return class == .newline or class == .cr or class == .lf;
}

fn isIgnored(class: Class) bool {
    return class == .extend or class == .format or class == .zwj;
}

fn isAhLetter(class: Class) bool {
    return class == .a_letter or class == .hebrew_letter;
}

fn isMidNumLetQ(class: Class) bool {
    return class == .mid_num_let or class == .single_quote;
}

fn isLetterMid(class: Class) bool {
    return class == .mid_letter or isMidNumLetQ(class);
}

fn isNumericMid(class: Class) bool {
    return class == .mid_num or isMidNumLetQ(class);
}

fn isExtendNumLetLeft(class: Class) bool {
    return isAhLetter(class) or class == .numeric or class == .katakana or
        class == .extend_num_let;
}

fn isExtendNumLetRight(class: Class) bool {
    return isAhLetter(class) or class == .numeric or class == .katakana;
}

const Decoded = struct {
    codepoint: u21,
    start: usize,
    next: usize,
};

fn previousSignificant(text: []const u8, offset: usize) ?Decoded {
    var cursor = offset;
    while (decodeBefore(text, cursor)) |decoded| {
        if (!isIgnored(properties(decoded.codepoint).class)) return decoded;
        cursor = decoded.start;
    }
    return null;
}

fn nextSignificant(text: []const u8, offset: usize) ?Decoded {
    var cursor = offset;
    while (decode(text, cursor)) |decoded| {
        if (!isIgnored(properties(decoded.codepoint).class)) return decoded;
        cursor = decoded.next;
    }
    return null;
}

fn properties(codepoint: u21) Properties {
    const page = @as(usize, codepoint) >> 8;
    const slot = readU16(header.index_offset + page * 2);
    const value = data[
        header.pages_offset + @as(usize, slot) * 256 +
            (@as(usize, codepoint) & 0xff)
    ];
    return @bitCast(value);
}

fn decode(text: []const u8, offset: usize) ?Decoded {
    if (offset >= text.len) return null;
    const sequence_len = std.unicode.utf8ByteSequenceLength(text[offset]) catch return null;
    if (offset + sequence_len > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[offset .. offset + sequence_len]) catch
        return null;
    return .{ .codepoint = codepoint, .start = offset, .next = offset + sequence_len };
}

fn decodeBefore(text: []const u8, offset: usize) ?Decoded {
    if (offset == 0 or offset > text.len) return null;
    var start = offset - 1;
    while (start != 0 and (text[start] & 0xc0) == 0x80) start -= 1;
    const decoded = decode(text, start) orelse return null;
    if (decoded.next != offset) return null;
    return decoded;
}

fn parseHeader() Header {
    if (data.len < 12 or !std.mem.eql(u8, data[0..4], "CJWB") or
        data[4] != 1 or data[5] != unicode_version[0] or
        data[6] != unicode_version[1] or data[7] != unicode_version[2])
    {
        @compileError("invalid word-break data");
    }
    const index_count = readU16(8);
    const page_count = readU16(10);
    const index_offset = 12;
    const pages_offset = index_offset + index_count * 2;
    if (index_count != 0x1100 or
        pages_offset + page_count * 256 != data.len)
    {
        @compileError("invalid word-break data lengths");
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

test "Unicode 17 word-boundary conformance" {
    if (test_data.len < 12 or !std.mem.eql(u8, test_data[0..4], "CJWT") or
        test_data[4] != 1 or test_data[5] != unicode_version[0] or
        test_data[6] != unicode_version[1] or test_data[7] != unicode_version[2])
    {
        return error.InvalidFixture;
    }

    const case_count = std.mem.readInt(u32, test_data[8..12], .little);
    try std.testing.expectEqual(@as(u32, 1944), case_count);
    var offset: usize = 12;
    for (0..case_count) |case_index| {
        const count = test_data[offset];
        offset += 1;
        const expected = test_data[offset..][0 .. @as(usize, count) + 1];
        offset += @as(usize, count) + 1;
        const codepoint_bytes = test_data[offset..][0 .. @as(usize, count) * 4];
        offset += @as(usize, count) * 4;

        var utf8: [128]u8 = undefined;
        var utf8_len: usize = 0;
        var expected_offsets: [32]usize = undefined;
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
                    "word case={d} boundary={d} expected={d} actual={d}\n",
                    .{
                        case_index,
                        actual_count,
                        expected_offsets[actual_count],
                        actual_end,
                    },
                );
                return error.WordBreakConformanceMismatch;
            }
            actual_count += 1;
        }
        try std.testing.expectEqual(expected_count, actual_count);
    }
    try std.testing.expectEqual(test_data.len, offset);
}
