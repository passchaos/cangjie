const std = @import("std");

const data = @embedFile("data.bin");
const test_data = @embedFile("conformance.bin");

pub const unicode_version = [3]u8{ 17, 0, 0 };

pub const Cluster = struct {
    byte_start: usize,
    byte_len: usize,
};

pub const Error = error{InvalidUtf8};

const Class = enum(u4) {
    other,
    cr,
    lf,
    control,
    extend,
    zwj,
    regional_indicator,
    prepend,
    spacing_mark,
    l,
    v,
    t,
    lv,
    lvt,
};

const InCb = enum(u2) {
    none,
    consonant,
    extend,
    linker,
};

const Properties = packed struct(u8) {
    class: Class,
    incb: InCb,
    extended_pictographic: bool,
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
    pending: ?Decoded = null,

    pub fn next(self: *Iterator) ?Cluster {
        if (self.cursor >= self.text.len) return null;
        const start = self.cursor;
        const first = self.pending orelse decode(self.text, self.cursor) orelse unreachable;
        self.pending = null;
        self.cursor = first.next;

        var previous = properties(first.codepoint);
        var regional_indicator_count: usize =
            if (previous.class == .regional_indicator) 1 else 0;
        var saw_extended_pictographic = previous.extended_pictographic;
        var zwj_after_extended_pictographic = false;
        var incb_consonant = previous.incb == .consonant;
        var incb_linker = false;

        // GB3 is the sole multi-byte ASCII cluster.
        if (first.codepoint < 0x80 and self.cursor < self.text.len and
            self.text[self.cursor] < 0x80 and
            !(first.codepoint == '\r' and self.text[self.cursor] == '\n'))
        {
            return .{ .byte_start = start, .byte_len = self.cursor - start };
        }

        while (self.cursor < self.text.len) {
            const current = decode(self.text, self.cursor) orelse unreachable;
            const current_properties = properties(current.codepoint);
            const current_incb = if (current_properties.incb == .linker or
                legacyInCbLinker(current.codepoint))
                InCb.linker
            else
                current_properties.incb;
            if (breaksBetween(
                previous,
                current_properties,
                current_incb,
                regional_indicator_count,
                zwj_after_extended_pictographic,
                incb_consonant,
                incb_linker,
            )) {
                self.pending = current;
                break;
            }
            self.cursor = current.next;

            const current_completes_incb_chain = incb_consonant and
                incb_linker and current_incb == .consonant;
            const continuing_incb_chain = incb_consonant and
                (current_incb == .extend or current_incb == .linker or
                    current_incb == .consonant);
            if (current_properties.class == .zwj) {
                zwj_after_extended_pictographic = saw_extended_pictographic;
            } else if (current_properties.class != .extend) {
                zwj_after_extended_pictographic = false;
                saw_extended_pictographic = current_properties.extended_pictographic;
            } else if (current_properties.extended_pictographic) {
                saw_extended_pictographic = true;
            }

            if (current_completes_incb_chain) {
                // GB9c consumed the following consonant. A later linker starts
                // a new chain only if this consonant itself is a valid anchor.
                incb_consonant = true;
                incb_linker = false;
            } else if (continuing_incb_chain) {
                if (current_incb == .linker) incb_linker = true;
            } else {
                incb_consonant = current_incb == .consonant;
                incb_linker = false;
            }

            if (current_properties.class == .regional_indicator) {
                regional_indicator_count += 1;
            } else {
                regional_indicator_count = 0;
            }
            previous = current_properties;
        }
        return .{ .byte_start = start, .byte_len = self.cursor - start };
    }
};

pub fn clusters(text: []const u8) Error!Iterator {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    return assumeValid(text);
}

pub fn assumeValid(text: []const u8) Iterator {
    std.debug.assert(std.unicode.utf8ValidateSlice(text));
    return .{ .text = text };
}

fn breaksBetween(
    previous: Properties,
    current: Properties,
    current_incb: InCb,
    regional_indicator_count: usize,
    zwj_after_extended_pictographic: bool,
    incb_consonant: bool,
    incb_linker: bool,
) bool {
    // GB3.
    if (previous.class == .cr and current.class == .lf) return false;
    // GB4 / GB5.
    if (isControl(previous.class) or isControl(current.class)) return true;
    // GB6..GB8.
    if (previous.class == .l and
        (current.class == .l or current.class == .v or current.class == .lv or
            current.class == .lvt)) return false;
    if ((previous.class == .lv or previous.class == .v) and
        (current.class == .v or current.class == .t)) return false;
    if ((previous.class == .lvt or previous.class == .t) and
        current.class == .t) return false;
    // GB9, GB9a, GB9b.
    if (current.class == .extend or current.class == .zwj) return false;
    if (current.class == .spacing_mark) return false;
    if (previous.class == .prepend) return false;
    // GB9c.
    if (incb_consonant and incb_linker and current_incb == .consonant) return false;
    // GB11.
    if (previous.class == .zwj and zwj_after_extended_pictographic and
        current.extended_pictographic) return false;
    // GB12 / GB13.
    if (previous.class == .regional_indicator and
        current.class == .regional_indicator and
        regional_indicator_count % 2 == 1) return false;
    return true;
}

fn isControl(class: Class) bool {
    return class == .control or class == .cr or class == .lf;
}

fn legacyInCbLinker(codepoint: u21) bool {
    // Unicode 17's InCB table intentionally narrows Linker to scripts covered
    // by the default GB9c derivation. Cangjie's existing script/fallback
    // contract also treats these canonical viramas as conjunct linkers. Keeping
    // them here preserves established caret atoms while still sourcing every
    // scalar property from generated data.
    return switch (codepoint) {
        0x0a4d, 0x0ccd, 0x11046, 0x110b9, 0x11442 => true,
        else => false,
    };
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

const Decoded = struct {
    codepoint: u21,
    next: usize,
};

fn decode(text: []const u8, offset: usize) ?Decoded {
    if (offset >= text.len) return null;
    const first = text[offset];
    const sequence_len = std.unicode.utf8ByteSequenceLength(first) catch return null;
    if (offset + sequence_len > text.len) return null;
    const codepoint = std.unicode.utf8Decode(text[offset .. offset + sequence_len]) catch
        return null;
    return .{ .codepoint = codepoint, .next = offset + sequence_len };
}

fn parseHeader() Header {
    if (data.len < 12 or !std.mem.eql(u8, data[0..4], "CJGB") or
        data[4] != 1 or data[5] != unicode_version[0] or
        data[6] != unicode_version[1] or data[7] != unicode_version[2])
    {
        @compileError("invalid grapheme data");
    }
    const index_count = readU16(8);
    const page_count = readU16(10);
    const index_offset = 12;
    const pages_offset = index_offset + index_count * 2;
    if (index_count != 0x1100 or
        pages_offset + page_count * 256 != data.len)
    {
        @compileError("invalid grapheme data lengths");
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

test "Unicode 17 grapheme conformance" {
    if (test_data.len < 12 or !std.mem.eql(u8, test_data[0..4], "CJGT") or
        test_data[4] != 1 or test_data[5] != unicode_version[0] or
        test_data[6] != unicode_version[1] or test_data[7] != unicode_version[2])
    {
        return error.InvalidFixture;
    }
    const case_count = std.mem.readInt(u32, test_data[8..12], .little);
    var offset: usize = 12;
    for (0..case_count) |case_index| {
        const count = test_data[offset];
        offset += 1;
        const expected = test_data[offset..][0 .. @as(usize, count) + 1];
        offset += @as(usize, count) + 1;
        const codepoint_bytes = test_data[offset..][0 .. @as(usize, count) * 4];
        offset += @as(usize, count) * 4;

        var utf8: [1024]u8 = undefined;
        var utf8_len: usize = 0;
        var expected_offsets: [256]usize = undefined;
        var expected_count: usize = 0;
        if (expected[0] != 0) {
            expected_offsets[expected_count] = 0;
            expected_count += 1;
        }
        for (0..count) |index| {
            const cp: u21 = @intCast(std.mem.readInt(
                u32,
                codepoint_bytes[index * 4 ..][0..4],
                .little,
            ));
            utf8_len += try std.unicode.utf8Encode(cp, utf8[utf8_len..]);
            if (expected[index + 1] != 0) {
                expected_offsets[expected_count] = utf8_len;
                expected_count += 1;
            }
        }

        var iterator = assumeValid(utf8[0..utf8_len]);
        var actual_count: usize = 1;
        var actual_end: usize = 0;
        while (iterator.next()) |cluster| {
            actual_end = cluster.byte_start + cluster.byte_len;
            if (expected_offsets[actual_count] != actual_end) {
                std.debug.print(
                    "grapheme case={d} boundary={d} expected={d} actual={d}\n",
                    .{
                        case_index,
                        actual_count,
                        expected_offsets[actual_count],
                        actual_end,
                    },
                );
                return error.GraphemeConformanceMismatch;
            }
            actual_count += 1;
        }
        try std.testing.expectEqual(expected_count, actual_count);
    }
    try std.testing.expectEqual(test_data.len, offset);
}
