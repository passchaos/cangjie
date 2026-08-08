//! Unicode line breaking (UAX #14).
//!
//! This module deliberately owns only font-independent boundary analysis.
//! Shaping and paragraph layout consume the iterator but do not participate in
//! its state machine. The structure follows unicode-linebreak 0.1.5: Unicode
//! properties come from a generated compact trie, and UAX #14 rules are encoded
//! as a pair-state table. Both tables are embedded in `line_break_data.bin`.

const std = @import("std");

const data_blob = @embedFile("line_break_data.bin");

pub const unicode_version = std.SemanticVersion{
    .major = data_blob[5],
    .minor = data_blob[6],
    .patch = data_blob[7],
};

pub const BreakClass = enum(u8) {
    mandatory,
    carriage_return,
    line_feed,
    combining_mark,
    next_line,
    surrogate,
    word_joiner,
    zero_width_space,
    non_breaking_glue,
    space,
    zero_width_joiner,
    before_and_after,
    after,
    before,
    hyphen,
    contingent,
    close_punctuation,
    close_parenthesis,
    exclamation,
    inseparable,
    nonstarter,
    open_punctuation,
    quotation,
    infix_separator,
    numeric,
    postfix,
    prefix,
    symbol,
    ambiguous,
    alphabetic,
    conditional_japanese_starter,
    emoji_base,
    emoji_modifier,
    hangul_lv_syllable,
    hangul_lvt_syllable,
    hebrew_letter,
    ideographic,
    hangul_l_jamo,
    hangul_v_jamo,
    hangul_t_jamo,
    regional_indicator,
    complex_context,
    unknown,
};

pub const BreakKind = enum {
    soft,
    hard,
};

pub const Break = struct {
    /// UTF-8 byte offset of the character following the break.
    byte_offset: usize,
    kind: BreakKind,
};

pub const Error = error{InvalidUtf8};

const format_version = 1;
const header_len = 24;
const trie_high_start_u32 = readLeU32(8);
const trie_index_count: usize = readLeU32(12);
const trie_data_count: usize = readLeU32(16);
const pair_rows: usize = readLeU16(20);
const pair_columns: usize = readLeU16(22);
const trie_index_offset = header_len;
const trie_data_offset = trie_index_offset + trie_index_count * 2;
const pair_table_offset = trie_data_offset + trie_data_count;
const trie_index = decodeTrieIndex();

const bmp_limit: u32 = 0x10000;
const shift_3: u5 = 4;
const shift_2: u5 = 9;
const shift_1: u5 = 14;
const bmp_shift: u5 = 6;
const index_2_block_length: u32 = 1 << (shift_1 - shift_2);
const index_3_block_length: u32 = 1 << (shift_2 - shift_3);
const small_data_block_length: u32 = 1 << shift_3;
const bmp_data_block_length: u32 = 1 << bmp_shift;

const allowed_break_bit: u8 = 0x80;
const mandatory_break_bit: u8 = 0x40;
const end_of_text: u8 = 43;
const start_of_text: u8 = 44;

comptime {
    if (!std.mem.eql(u8, data_blob[0..4], "CJLB")) {
        @compileError("invalid Unicode line-break data magic");
    }
    if (data_blob[4] != format_version) {
        @compileError("unsupported Unicode line-break data format");
    }
    if (pair_rows != 53 or pair_columns != 44) {
        @compileError("invalid Unicode line-break pair table dimensions");
    }
    if (pair_table_offset + pair_rows * pair_columns != data_blob.len) {
        @compileError("invalid Unicode line-break data length");
    }
    if (trie_high_start_u32 > std.math.maxInt(u21)) {
        @compileError("Unicode line-break trie high start exceeds Unicode range");
    }
}

/// Return the Unicode Line_Break property for a scalar value.
pub inline fn classForCodepoint(codepoint: u21) BreakClass {
    const cp: u32 = codepoint;
    const data_pos: usize = if (cp < bmp_limit) pos: {
        const index_pos: usize = @intCast(cp >> bmp_shift);
        break :pos @as(usize, trie_index[index_pos]) +
            @as(usize, @intCast(cp & (bmp_data_block_length - 1)));
    } else if (cp < trie_high_start_u32) pos: {
        const bmp_index_len = bmp_limit >> bmp_shift;
        const omitted_bmp_index_1_len = bmp_limit >> shift_1;
        const index_1 = cp >> shift_1;
        const index_2_base = trie_index[
            index_1 + bmp_index_len - omitted_bmp_index_1_len
        ];
        const index_2 = @as(usize, index_2_base) +
            @as(usize, @intCast((cp >> shift_2) & (index_2_block_length - 1)));
        const index_3_block = trie_index[index_2];
        const index_3_pos = (cp >> shift_3) & (index_3_block_length - 1);
        const data_block = trie_index[@as(usize, index_3_block) + index_3_pos];
        break :pos @as(usize, data_block) +
            @as(usize, @intCast(cp & (small_data_block_length - 1)));
    } else {
        return .unknown;
    };
    return @enumFromInt(data_blob[trie_data_offset + data_pos]);
}

/// Zero-allocation iterator over UAX #14 line-break opportunities.
///
/// Like unicode-linebreak, the iterator emits a mandatory break at the end of
/// non-empty text; empty text has no opportunities. Construct iterators with
/// `breaks`, which validates UTF-8 once before entering this hot loop.
pub const Iterator = struct {
    text: []const u8,
    cursor: usize = 0,
    state: u8 = start_of_text,
    previous_was_zwj: bool = false,
    emitted_end: bool = false,

    fn initAssumeValid(text: []const u8) Iterator {
        return .{ .text = text };
    }

    pub fn next(self: *Iterator) ?Break {
        while (!self.emitted_end) {
            const byte_offset: usize, const class: u8 = if (self.cursor < self.text.len) decoded: {
                const start = self.cursor;
                const byte_len = std.unicode.utf8ByteSequenceLength(self.text[start]) catch unreachable;
                const end = start + byte_len;
                const codepoint = std.unicode.utf8Decode(self.text[start..end]) catch unreachable;
                self.cursor = end;
                break :decoded .{ start, @intFromEnum(classForCodepoint(codepoint)) };
            } else end: {
                self.emitted_end = true;
                break :end .{ self.text.len, end_of_text };
            };

            const value = pairValue(self.state, class);
            const mandatory = value & mandatory_break_bit != 0;
            const allowed = value & allowed_break_bit != 0;
            const should_break = allowed and (!self.previous_was_zwj or mandatory);
            self.state = value & ~(allowed_break_bit | mandatory_break_bit);
            self.previous_was_zwj = class == @intFromEnum(BreakClass.zero_width_joiner);

            if (should_break) {
                return .{
                    .byte_offset = byte_offset,
                    .kind = if (mandatory) .hard else .soft,
                };
            }
        }
        return null;
    }
};

/// Validate `text` and create a reconstructible line-break iterator.
///
/// Keeping validation at the constructor matches Rust's `&str` contract and
/// avoids carrying malformed-input branches through every iteration step.
pub fn breaks(text: []const u8) Error!Iterator {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    return breaksAssumeValid(text);
}

/// Create an iterator for text already validated by an enclosing pipeline.
///
/// This is exposed only through the internal module used by paragraph layout;
/// the package root exports the checked `breaks` constructor.
pub fn breaksAssumeValid(text: []const u8) Iterator {
    return .initAssumeValid(text);
}

inline fn pairValue(state: u8, class: u8) u8 {
    return data_blob[
        pair_table_offset +
            @as(usize, state) * pair_columns +
            @as(usize, class)
    ];
}

fn readLeU16(comptime offset: usize) u16 {
    return @as(u16, data_blob[offset]) |
        (@as(u16, data_blob[offset + 1]) << 8);
}

fn readLeU32(comptime offset: usize) u32 {
    return @as(u32, data_blob[offset]) |
        (@as(u32, data_blob[offset + 1]) << 8) |
        (@as(u32, data_blob[offset + 2]) << 16) |
        (@as(u32, data_blob[offset + 3]) << 24);
}

fn decodeTrieIndex() [trie_index_count]u16 {
    @setEvalBranchQuota(10_000);
    var result: [trie_index_count]u16 = undefined;
    for (&result, 0..) |*value, i| {
        const offset = trie_index_offset + i * 2;
        value.* = @as(u16, data_blob[offset]) |
            (@as(u16, data_blob[offset + 1]) << 8);
    }
    return result;
}

test "line break iterator handles spaces, CRLF, ZWJ, and end of text" {
    var empty = try breaks("");
    try std.testing.expect(empty.next() == null);

    var iterator = try breaks("A B\r\nC");
    try std.testing.expectEqual(Break{ .byte_offset = 2, .kind = .soft }, iterator.next().?);
    try std.testing.expectEqual(Break{ .byte_offset = 5, .kind = .hard }, iterator.next().?);
    try std.testing.expectEqual(Break{ .byte_offset = 6, .kind = .hard }, iterator.next().?);
    try std.testing.expect(iterator.next() == null);

    var joined = try breaks("\u{1f469}\u{200d}\u{1f4bb}");
    try std.testing.expectEqual(
        Break{ .byte_offset = "\u{1f469}\u{200d}\u{1f4bb}".len, .kind = .hard },
        joined.next().?,
    );
    try std.testing.expect(joined.next() == null);
}

test "line break property table covers representative classes" {
    try std.testing.expectEqual(BreakClass.line_feed, classForCodepoint('\n'));
    try std.testing.expectEqual(BreakClass.space, classForCodepoint(' '));
    try std.testing.expectEqual(BreakClass.regional_indicator, classForCodepoint(0x1f1e6));
    try std.testing.expectEqual(BreakClass.emoji_modifier, classForCodepoint(0x1f3fb));
}

test "line break iterator rejects malformed UTF-8" {
    try std.testing.expectError(error.InvalidUtf8, breaks("A\xff"));
}

test "Unicode 15.0 UAX #14 default line breaking conformance" {
    const test_data_blob = @embedFile("line_break_test_data.bin");
    const test_header_len = 12;
    const test_format_version = 1;
    try std.testing.expectEqualStrings("CJLT", test_data_blob[0..4]);
    try std.testing.expectEqual(test_format_version, test_data_blob[4]);
    try std.testing.expectEqual(unicode_version.major, test_data_blob[5]);
    try std.testing.expectEqual(unicode_version.minor, test_data_blob[6]);
    try std.testing.expectEqual(unicode_version.patch, test_data_blob[7]);

    const case_count = testDataLeU32(test_data_blob, 8);
    var data_cursor: usize = test_header_len;
    var case_index: u32 = 0;
    while (case_index < case_count) : (case_index += 1) {
        try std.testing.expect(data_cursor < test_data_blob.len);
        const codepoint_count = test_data_blob[data_cursor];
        data_cursor += 1;

        var text: [255 * 4]u8 = undefined;
        var expected_offsets: [255]usize = undefined;
        var text_len: usize = 0;
        var expected_count: usize = 0;
        for (0..codepoint_count) |_| {
            try std.testing.expect(data_cursor + 5 <= test_data_blob.len);
            const raw_codepoint = testDataLeU32(test_data_blob, data_cursor);
            data_cursor += 4;
            const break_after = test_data_blob[data_cursor] != 0;
            data_cursor += 1;

            const codepoint: u21 = @intCast(raw_codepoint);
            text_len += try std.unicode.utf8Encode(codepoint, text[text_len..]);
            if (break_after) {
                expected_offsets[expected_count] = text_len;
                expected_count += 1;
            }
        }

        var iterator = try breaks(text[0..text_len]);
        var actual_count: usize = 0;
        while (iterator.next()) |opportunity| {
            try std.testing.expect(actual_count < expected_count);
            try std.testing.expectEqual(expected_offsets[actual_count], opportunity.byte_offset);
            actual_count += 1;
        }
        try std.testing.expectEqual(expected_count, actual_count);
    }
    try std.testing.expectEqual(test_data_blob.len, data_cursor);
}

fn testDataLeU32(test_data: []const u8, offset: usize) u32 {
    return @as(u32, test_data[offset]) |
        (@as(u32, test_data[offset + 1]) << 8) |
        (@as(u32, test_data[offset + 2]) << 16) |
        (@as(u32, test_data[offset + 3]) << 24);
}
