const std = @import("std");
const glyph_mod = @import("glyph.zig");

/// CFF support covers the Compact Font Format structures needed for OpenType
/// CFF outlines: INDEX tables, top/private dictionaries, subroutines, and Type2
/// charstrings. Unsupported operators fail explicitly instead of producing a
/// partial outline.
pub const CffError = error{
    BadCff,
    UnsupportedCff,
    InvalidGlyph,
    StackOverflow,
    StackUnderflow,
    EndOfStream,
} || std.mem.Allocator.Error;

pub const Info = struct {
    charstrings_offset: usize,
    charstrings_count: u16,
    global_subrs_offset: usize,
    charset_offset: usize = 0,
    fd_array_offset: usize = 0,
    fd_select_offset: usize = 0,
    private_offset: usize = 0,
    private_size: usize = 0,
    local_subrs_offset: usize = 0,
    default_width_x: f32 = 0,
    nominal_width_x: f32 = 0,
};

pub const Parsed = struct {
    info: Info,
    charstrings: Index,
    global_subrs: Index,
    local_subrs: ?Index,
    fd_array: ?Index,
    fd_select: ?FdSelect,
};

pub const FdSelect = struct {
    offset: usize,
    format: u8,
};

/// Parse the CFF header and the small amount of top/private DICT state needed
/// to locate CharStrings and subroutine indexes.
pub fn parseInfo(data: []const u8) CffError!Info {
    if (data.len < 4) return error.BadCff;
    const major = data[0];
    const minor = data[1];
    const header_size = data[2];
    const header_off_size = data[3];
    if (major != 1 or minor != 0) return error.BadCff;
    if (header_size < 4) return error.BadCff;
    if (header_off_size == 0 or header_off_size > 4) return error.BadCff;
    if (header_size > data.len) return error.BadCff;
    const name_index = try readIndex(data, header_size);
    const top_index = try readIndex(data, name_index.end);
    if (top_index.count != 1) return error.BadCff;
    const top_dict = try top_index.object(data, 0);
    var info = try parseTopDict(top_dict);
    const string_index = try readIndex(data, top_index.end);
    info.global_subrs_offset = string_index.end;
    _ = try readIndex(data, info.global_subrs_offset);
    if (info.charstrings_offset >= data.len) return error.BadCff;
    const charstrings = try readIndex(data, info.charstrings_offset);
    info.charstrings_count = charstrings.count;
    if (info.private_size > 0) {
        if (info.private_offset > data.len or info.private_size > data.len - info.private_offset) return error.BadCff;
        try parsePrivateDict(data[info.private_offset .. info.private_offset + info.private_size], &info);
        if (info.local_subrs_offset != 0) {
            // The Private DICT's Subrs operand points to a complete Local
            // Subrs INDEX relative to the beginning of the Private DICT, not
            // to bytes inside the dictionary itself. Validate the child INDEX
            // while parsing face metadata so a malformed font is rejected
            // before an outline lookup tries to recurse through arbitrary CFF
            // bytes as subroutines.
            const private_end = info.private_offset + info.private_size;
            if (info.local_subrs_offset < private_end or info.local_subrs_offset >= data.len) return error.BadCff;
            _ = try readIndex(data, info.local_subrs_offset);
        }
    }
    return info;
}

pub fn parse(data: []const u8) CffError!Parsed {
    return try prepare(data, try parseInfo(data));
}

pub fn prepare(data: []const u8, info: Info) CffError!Parsed {
    const fd_array = if (info.fd_array_offset != 0) try readIndex(data, info.fd_array_offset) else null;
    const fd_select = if (info.fd_select_offset != 0) try readFdSelect(data, info.fd_select_offset) else null;
    if ((fd_array == null) != (fd_select == null)) return error.BadCff;
    if (fd_array) |array| {
        if (array.count == 0 or array.count > 256) return error.BadCff;
        try validateFdSelect(data, fd_select.?, info.charstrings_count, array.count);
        // Prove every Font DICT and its Private/Subrs graph once. Runtime
        // outline lookup then selects one already-bounded record by glyph id.
        for (0..array.count) |font_dict_index| {
            _ = try parseCidFontDict(data, array, font_dict_index);
        }
    }
    return .{
        .info = info,
        .charstrings = try readIndex(data, info.charstrings_offset),
        .global_subrs = try readIndex(data, info.global_subrs_offset),
        .local_subrs = if (info.local_subrs_offset != 0) try readIndex(data, info.local_subrs_offset) else null,
        .fd_array = fd_array,
        .fd_select = fd_select,
    };
}

/// Interpret one Type2 charstring into the shared GlyphOutline representation.
pub fn appendGlyphOutline(allocator: std.mem.Allocator, data: []const u8, info: Info, outline: *glyph_mod.GlyphOutline, glyph_id: glyph_mod.GlyphId) CffError!void {
    try appendGlyphOutlinePrepared(allocator, data, try prepare(data, info), outline, glyph_id);
}

pub fn appendGlyphOutlinePrepared(allocator: std.mem.Allocator, data: []const u8, parsed: Parsed, outline: *glyph_mod.GlyphOutline, glyph_id: glyph_mod.GlyphId) CffError!void {
    return try appendGlyphOutlinePreparedAt(allocator, data, parsed, outline, glyph_id, .{ .x = 0, .y = 0 }, 0);
}

fn appendGlyphOutlinePreparedAt(allocator: std.mem.Allocator, data: []const u8, parsed: Parsed, outline: *glyph_mod.GlyphOutline, glyph_id: glyph_mod.GlyphId, origin: glyph_mod.Point, seac_depth: u8) CffError!void {
    if (seac_depth > 2) return error.BadCff;
    if (glyph_id >= parsed.charstrings.count) return error.InvalidGlyph;
    const bytes = try parsed.charstrings.object(data, glyph_id);
    const private = if (parsed.fd_array) |fd_array| blk: {
        const fd_index = try fdSelectValue(data, parsed.fd_select.?, glyph_id, parsed.charstrings.count, fd_array.count);
        break :blk try parseCidFontDict(data, fd_array, fd_index);
    } else parsed.info;
    var interpreter = Type2Interpreter{
        .allocator = allocator,
        .outline = outline,
        .nominal_width_x = private.nominal_width_x,
        .default_width_x = private.default_width_x,
        .cff_data = data,
        .global_subrs = parsed.global_subrs,
        .local_subrs = if (private.local_subrs_offset != 0) try readIndex(data, private.local_subrs_offset) else null,
        .x = origin.x,
        .y = origin.y,
    };
    try interpreter.run(bytes);
    if (interpreter.seac) |seac| {
        const base = try standardCodeToGlyph(data, parsed.info, seac.base_code);
        const accent = try standardCodeToGlyph(data, parsed.info, seac.accent_code);
        try appendGlyphOutlinePreparedAt(allocator, data, parsed, outline, base, origin, seac_depth + 1);
        try appendGlyphOutlinePreparedAt(allocator, data, parsed, outline, accent, .{
            .x = origin.x + seac.adx,
            .y = origin.y + seac.ady,
        }, seac_depth + 1);
    }
}

pub const Index = struct {
    count: u16,
    off_size: u8,
    offsets_pos: usize,
    object_base: usize,
    end: usize,

    fn object(self: Index, data: []const u8, index: usize) CffError![]const u8 {
        if (index >= self.count) return error.InvalidGlyph;
        const start = try readOffset(data, self.offsets_pos + index * self.off_size, self.off_size);
        const end = try readOffset(data, self.offsets_pos + (index + 1) * self.off_size, self.off_size);
        if (start == 0 or end < start) return error.BadCff;
        const abs_start = self.object_base + start - 1;
        const abs_end = self.object_base + end - 1;
        if (abs_start > self.end or abs_end > self.end or abs_end > data.len) return error.BadCff;
        return data[abs_start..abs_end];
    }
};

fn readIndex(data: []const u8, offset: usize) CffError!Index {
    // CFF INDEX offsets are 1-based relative to object_base. Store the resolved
    // object_base/end once so individual object slices only need bounds checks.
    if (offset + 2 > data.len) return error.EndOfStream;
    const count = std.mem.readInt(u16, data[offset..][0..2], .big);
    if (count == 0) return .{ .count = 0, .off_size = 0, .offsets_pos = offset + 2, .object_base = offset + 2, .end = offset + 2 };
    if (offset + 3 > data.len) return error.EndOfStream;
    const off_size = data[offset + 2];
    if (off_size == 0 or off_size > 4) return error.BadCff;
    const offsets_pos = offset + 3;
    const offset_bytes = (@as(usize, count) + 1) * @as(usize, off_size);
    if (offset_bytes > data.len - offsets_pos) return error.EndOfStream;

    const object_base = offsets_pos + offset_bytes;
    const last = try validateIndexOffsets(data, offsets_pos, count, off_size);
    if (last - 1 > data.len - object_base) return error.BadCff;
    const end = object_base + last - 1;
    return .{ .count = count, .off_size = off_size, .offsets_pos = offsets_pos, .object_base = object_base, .end = end };
}

fn validateIndexOffsets(data: []const u8, offsets_pos: usize, count: u16, off_size: u8) CffError!usize {
    // INDEX offsets are 1-based and scoped to the INDEX object's declared data
    // block. Validate the complete array when the INDEX is parsed; otherwise a
    // later lookup of only object 0 could follow a non-monotonic offset into the
    // next CFF structure without ever consulting the final, smaller offset.
    const first = try readOffset(data, offsets_pos, off_size);
    if (first != 1) return error.BadCff;

    var previous = first;
    for (1..@as(usize, count) + 1) |index| {
        const current = try readOffset(data, offsets_pos + index * @as(usize, off_size), off_size);
        if (current < previous) return error.BadCff;
        previous = current;
    }
    return previous;
}

fn readOffset(data: []const u8, offset: usize, size: u8) CffError!usize {
    // INDEX offset arrays come from untrusted CFF bytes. Validate the bounds in
    // subtraction form so a corrupt caller-supplied offset near maxInt(usize)
    // reports a parser error instead of overflowing during `offset + size`.
    if (offset > data.len or size > data.len - offset) return error.EndOfStream;
    var value: usize = 0;
    for (0..size) |i| value = (value << 8) | data[offset + i];
    return value;
}

test "CFF offset reads reject overflowing absolute offsets" {
    const empty: []const u8 = &.{};
    try std.testing.expectError(error.EndOfStream, readOffset(empty, std.math.maxInt(usize), 1));

    const bytes = [_]u8{ 0xaa, 0xbb };
    try std.testing.expectEqual(@as(usize, 0xaabb), try readOffset(&bytes, 0, 2));
    try std.testing.expectError(error.EndOfStream, readOffset(&bytes, 1, 2));
}

fn subrBias(count: u16) i32 {
    // Type2 subroutine operands are biased by the subroutine count. These
    // thresholds are defined by the CFF specification.
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
}

fn parseTopDict(dict: []const u8) CffError!Info {
    var info = Info{ .charstrings_offset = 0, .charstrings_count = 0, .global_subrs_offset = 0 };
    var parser = DictParser.init(dict);
    while (try parser.next()) |entry| {
        switch (entry.operator) {
            15 => info.charset_offset = try dictOffsetOperand(entry.operands, 0),
            17 => info.charstrings_offset = try dictOffsetOperand(entry.operands, 0),
            18 => {
                if (entry.operands.len < 2) return error.BadCff;
                info.private_size = try dictOffsetOperand(entry.operands, 0);
                info.private_offset = try dictOffsetOperand(entry.operands, 1);
            },
            1236 => info.fd_array_offset = try dictOffsetOperand(entry.operands, 0),
            1237 => info.fd_select_offset = try dictOffsetOperand(entry.operands, 0),
            else => {},
        }
    }
    if (info.charstrings_offset == 0) return error.BadCff;
    if ((info.fd_array_offset == 0) != (info.fd_select_offset == 0)) return error.BadCff;
    return info;
}

fn parseCidFontDict(data: []const u8, fd_array: Index, font_dict_index: usize) CffError!Info {
    const dict = try fd_array.object(data, font_dict_index);
    var parser = DictParser.init(dict);
    var info = Info{ .charstrings_offset = 0, .charstrings_count = 0, .global_subrs_offset = 0 };
    while (try parser.next()) |entry| {
        switch (entry.operator) {
            18 => {
                if (entry.operands.len < 2) return error.BadCff;
                info.private_size = try dictOffsetOperand(entry.operands, 0);
                info.private_offset = try dictOffsetOperand(entry.operands, 1);
            },
            else => {},
        }
    }
    if (info.private_size == 0) return error.BadCff;
    if (info.private_offset > data.len or info.private_size > data.len - info.private_offset) return error.BadCff;
    try parsePrivateDict(data[info.private_offset .. info.private_offset + info.private_size], &info);
    if (info.local_subrs_offset != 0) {
        const private_end = info.private_offset + info.private_size;
        if (info.local_subrs_offset < private_end or info.local_subrs_offset >= data.len) return error.BadCff;
        _ = try readIndex(data, info.local_subrs_offset);
    }
    return info;
}

fn readFdSelect(data: []const u8, offset: usize) CffError!FdSelect {
    if (offset >= data.len) return error.BadCff;
    const format = data[offset];
    if (format != 0 and format != 3) return error.UnsupportedCff;
    return .{ .offset = offset, .format = format };
}

fn validateFdSelect(data: []const u8, fd_select: FdSelect, glyph_count: usize, fd_count: usize) CffError!void {
    if (glyph_count == 0 or fd_count == 0) return error.BadCff;
    for (0..glyph_count) |glyph_id| {
        _ = try fdSelectValue(data, fd_select, glyph_id, glyph_count, fd_count);
    }
}

fn fdSelectValue(data: []const u8, fd_select: FdSelect, glyph_id: usize, glyph_count: usize, fd_count: usize) CffError!usize {
    if (glyph_id >= glyph_count) return error.InvalidGlyph;
    return switch (fd_select.format) {
        0 => blk: {
            if (glyph_count > data.len - fd_select.offset - 1) return error.EndOfStream;
            const value: usize = data[fd_select.offset + 1 + glyph_id];
            if (value >= fd_count) return error.BadCff;
            break :blk value;
        },
        3 => try fdSelectFormat3Value(data, fd_select.offset + 1, glyph_id, glyph_count, fd_count),
        else => error.UnsupportedCff,
    };
}

fn fdSelectFormat3Value(data: []const u8, offset: usize, glyph_id: usize, glyph_count: usize, fd_count: usize) CffError!usize {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    const range_count: usize = std.mem.readInt(u16, data[offset..][0..2], .big);
    const records_start = offset + 2;
    if (range_count == 0 or range_count > (data.len - records_start) / 3) return error.BadCff;
    const sentinel_offset = records_start + range_count * 3;
    if (sentinel_offset > data.len or data.len - sentinel_offset < 2) return error.EndOfStream;
    if (std.mem.readInt(u16, data[sentinel_offset..][0..2], .big) != glyph_count) return error.BadCff;

    var previous_first: ?usize = null;
    var selected: ?usize = null;
    for (0..range_count) |index| {
        const record = records_start + index * 3;
        const first: usize = std.mem.readInt(u16, data[record..][0..2], .big);
        const fd: usize = data[record + 2];
        if (first >= glyph_count or fd >= fd_count) return error.BadCff;
        if (previous_first) |previous| {
            if (first <= previous) return error.BadCff;
        } else if (first != 0) return error.BadCff;
        previous_first = first;
        if (glyph_id >= first) selected = fd;
    }
    return selected orelse error.BadCff;
}

fn standardCodeToGlyph(data: []const u8, info: Info, code: u8) CffError!glyph_mod.GlyphId {
    const sid = standardEncodingSid(code);
    if (sid == 0) return error.InvalidGlyph;
    return try charsetGlyphForSid(data, info, sid);
}

fn charsetGlyphForSid(data: []const u8, info: Info, sid: u16) CffError!glyph_mod.GlyphId {
    if (info.charset_offset <= 2) {
        // ISOAdobe's predefined charset maps glyph id directly to SID for the
        // 0...228 standard-string range. Expert charsets are not valid seac
        // sources because StandardEncoding cannot name their private SIDs.
        if (info.charset_offset != 0 or sid >= info.charstrings_count) return error.InvalidGlyph;
        return sid;
    }
    var cursor = info.charset_offset;
    if (cursor >= data.len) return error.EndOfStream;
    const format = data[cursor];
    cursor += 1;
    var glyph: usize = 1;
    switch (format) {
        0 => while (glyph < info.charstrings_count) : (glyph += 1) {
            if (cursor > data.len or data.len - cursor < 2) return error.EndOfStream;
            const current = std.mem.readInt(u16, data[cursor..][0..2], .big);
            cursor += 2;
            if (current == sid) return @intCast(glyph);
        },
        1, 2 => while (glyph < info.charstrings_count) {
            if (cursor > data.len or data.len - cursor < 2) return error.EndOfStream;
            const first = std.mem.readInt(u16, data[cursor..][0..2], .big);
            cursor += 2;
            const left: usize = if (format == 1) blk: {
                if (cursor >= data.len) return error.EndOfStream;
                const value = data[cursor];
                cursor += 1;
                break :blk value;
            } else blk: {
                if (cursor > data.len or data.len - cursor < 2) return error.EndOfStream;
                const value = std.mem.readInt(u16, data[cursor..][0..2], .big);
                cursor += 2;
                break :blk value;
            };
            const run_len = left + 1;
            if (run_len > info.charstrings_count - glyph) return error.BadCff;
            if (sid >= first and @as(usize, sid - first) < run_len) return @intCast(glyph + sid - first);
            glyph += run_len;
        },
        else => return error.UnsupportedCff,
    }
    return error.InvalidGlyph;
}

fn standardEncodingSid(code: u8) u16 {
    // seac uses Adobe StandardEncoding character codes. The CFF standard SID
    // sequence is contiguous for ASCII 32...126; the only high-byte entries
    // needed by ordinary composites are spacing accents and punctuation.
    if (code >= 32 and code <= 126) return code - 31;
    return switch (code) {
        161 => 96,
        162 => 97,
        163 => 98,
        164 => 99,
        165 => 100,
        166 => 101,
        167 => 102,
        168 => 103,
        169 => 104,
        170 => 105,
        171 => 106,
        172 => 107,
        173 => 108,
        174 => 109,
        175 => 110,
        177 => 111,
        178 => 112,
        179 => 113,
        180 => 114,
        182 => 115,
        183 => 116,
        184 => 117,
        185 => 118,
        186 => 119,
        187 => 120,
        188 => 121,
        189 => 122,
        191 => 123,
        193 => 124,
        194 => 125,
        195 => 126,
        196 => 127,
        197 => 128,
        198 => 129,
        199 => 130,
        200 => 131,
        202 => 132,
        203 => 133,
        205 => 134,
        206 => 135,
        207 => 136,
        208 => 137,
        225 => 138,
        227 => 139,
        232 => 140,
        233 => 141,
        234 => 142,
        235 => 143,
        241 => 144,
        245 => 145,
        248 => 146,
        249 => 147,
        250 => 148,
        251 => 149,
        else => 0,
    };
}

fn seacCode(value: f32) CffError!u8 {
    if (!std.math.isFinite(value) or value != @trunc(value) or value < 0 or value > 255) return error.BadCff;
    return @intFromFloat(value);
}

fn parsePrivateDict(dict: []const u8, info: *Info) CffError!void {
    var parser = DictParser.init(dict);
    while (try parser.next()) |entry| {
        switch (entry.operator) {
            19 => {
                if (entry.operands.len < 1) return error.BadCff;
                const relative_offset = try dictOffsetOperand(entry.operands, 0);
                if (relative_offset > std.math.maxInt(usize) - info.private_offset) return error.BadCff;
                info.local_subrs_offset = info.private_offset + relative_offset;
            },
            20 => {
                if (entry.operands.len < 1) return error.BadCff;
                info.default_width_x = entry.operands[0];
            },
            21 => {
                if (entry.operands.len < 1) return error.BadCff;
                info.nominal_width_x = entry.operands[0];
            },
            else => {},
        }
    }
}

fn dictOffsetOperand(operands: []const f32, index: usize) CffError!usize {
    if (index >= operands.len) return error.BadCff;
    const value = operands[index];
    // CFF offsets and sizes are encoded as DICT numbers, but the fields that
    // address other CFF structures have an integer, non-negative contract.
    // Validate that contract before converting so malformed real/negative
    // operands fail as BadCff instead of trapping in @intFromFloat or wrapping
    // into an unrelated table location.
    if (!std.math.isFinite(value) or value < 0 or value != @trunc(value)) return error.BadCff;
    const widened: f64 = value;
    if (widened > 4294967295.0) return error.BadCff;
    return @intFromFloat(widened);
}

const DictEntry = struct {
    operator: u16,
    operands: []const f32,
};

const DictParser = struct {
    data: []const u8,
    offset: usize = 0,
    stack: [48]f32 = undefined,
    stack_len: usize = 0,

    fn init(data: []const u8) DictParser {
        return .{ .data = data };
    }

    fn next(self: *DictParser) CffError!?DictEntry {
        // DICT data is an operand stack followed by an operator. Returning the
        // stack slice at each operator mirrors how Top DICT and Private DICT
        // keys are encoded.
        self.stack_len = 0;
        while (self.offset < self.data.len) {
            const b = self.data[self.offset];
            self.offset += 1;
            if (b <= 21) {
                const op: u16 = if (b == 12) blk: {
                    if (self.offset >= self.data.len) return error.EndOfStream;
                    const escaped = self.data[self.offset];
                    self.offset += 1;
                    break :blk 1200 + @as(u16, escaped);
                } else b;
                return .{ .operator = op, .operands = self.stack[0..self.stack_len] };
            }
            try self.push(try readNumber(self.data, &self.offset, b));
        }
        // DICT operands are meaningful only as the argument stack for a
        // following operator. Treating a trailing operand run as harmless would
        // let malformed Top/Private DICT data append unreachable bytes that
        // another CFF consumer might preserve or interpret differently.
        if (self.stack_len != 0) return error.BadCff;
        return null;
    }

    fn push(self: *DictParser, value: f32) CffError!void {
        if (self.stack_len >= self.stack.len) return error.StackOverflow;
        self.stack[self.stack_len] = value;
        self.stack_len += 1;
    }
};

fn readNumber(data: []const u8, offset: *usize, first: u8) CffError!f32 {
    // CFF numbers use compact variable-width encodings. Charstrings and DICTs
    // share most integer encodings, so this helper is used by both parsers.
    if (first >= 32 and first <= 246) return @floatFromInt(@as(i32, first) - 139);
    if (first >= 247 and first <= 250) {
        if (offset.* >= data.len) return error.EndOfStream;
        const b1 = data[offset.*];
        offset.* += 1;
        return @floatFromInt((@as(i32, first) - 247) * 256 + b1 + 108);
    }
    if (first >= 251 and first <= 254) {
        if (offset.* >= data.len) return error.EndOfStream;
        const b1 = data[offset.*];
        offset.* += 1;
        return @floatFromInt(-(@as(i32, first) - 251) * 256 - b1 - 108);
    }
    if (first == 28) {
        if (offset.* + 2 > data.len) return error.EndOfStream;
        const value: i16 = @bitCast(std.mem.readInt(u16, data[offset.*..][0..2], .big));
        offset.* += 2;
        return @floatFromInt(value);
    }
    if (first == 29) {
        if (offset.* + 4 > data.len) return error.EndOfStream;
        const value: i32 = @bitCast(std.mem.readInt(u32, data[offset.*..][0..4], .big));
        offset.* += 4;
        return @floatFromInt(value);
    }
    if (first == 255) {
        // Type 2 charstrings encode 16.16 fixed-point operands with byte 255.
        // STIX Two Math uses this form in global subroutines, so rejecting it
        // prevents the whole OpenType MATH face from being rasterized.
        if (offset.* + 4 > data.len) return error.EndOfStream;
        const fixed: i32 = @bitCast(std.mem.readInt(u32, data[offset.*..][0..4], .big));
        offset.* += 4;
        return @as(f32, @floatFromInt(fixed)) / 65536.0;
    }
    if (first == 30) return try readRealNumber(data, offset);
    return error.UnsupportedCff;
}

fn readRealNumber(data: []const u8, offset: *usize) CffError!f32 {
    // DICT real numbers are BCD-encoded nibbles terminated by 0xf. They appear
    // in real-world OpenType CFF math fonts such as Latin Modern Math private
    // dictionaries. Type2 charstrings do not use this encoding, but accepting it
    // here keeps the shared number reader useful for both DICT and outline code.
    var buf: [64]u8 = undefined;
    var len: usize = 0;
    while (offset.* < data.len) {
        const byte = data[offset.*];
        offset.* += 1;
        const nibbles = [_]u4{ @intCast(byte >> 4), @intCast(byte & 0x0f) };
        for (nibbles) |nibble| {
            switch (nibble) {
                0...9 => {
                    if (len >= buf.len) return error.UnsupportedCff;
                    buf[len] = '0' + @as(u8, @intCast(nibble));
                    len += 1;
                },
                0x0a => {
                    if (len >= buf.len) return error.UnsupportedCff;
                    buf[len] = '.';
                    len += 1;
                },
                0x0b => {
                    if (len >= buf.len) return error.UnsupportedCff;
                    buf[len] = 'E';
                    len += 1;
                },
                0x0c => {
                    if (len + 1 >= buf.len) return error.UnsupportedCff;
                    buf[len] = 'E';
                    buf[len + 1] = '-';
                    len += 2;
                },
                0x0d => return error.UnsupportedCff,
                0x0e => {
                    if (len >= buf.len) return error.UnsupportedCff;
                    buf[len] = '-';
                    len += 1;
                },
                0x0f => {
                    if (len == 0) return error.BadCff;
                    return std.fmt.parseFloat(f32, buf[0..len]) catch error.BadCff;
                },
            }
        }
    }
    return error.EndOfStream;
}

test "CFF DICT real numbers decode BCD nibble form" {
    var offset: usize = 1;
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), try readNumber(&.{ 30, 0x1a, 0x25, 0xff }, &offset, 30), 0.0001);
    try std.testing.expectEqual(@as(usize, 4), offset);

    offset = 1;
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), try readNumber(&.{ 30, 0xea, 0x5f }, &offset, 30), 0.0001);
}

test "CFF Type2 16.16 fixed-point operands decode byte 255 form" {
    var offset: usize = 1;
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.5),
        try readNumber(&.{ 255, 0x00, 0x01, 0x80, 0x00 }, &offset, 255),
        0.0001,
    );
    try std.testing.expectEqual(@as(usize, 5), offset);

    offset = 1;
    try std.testing.expectApproxEqAbs(
        @as(f32, -0.5),
        try readNumber(&.{ 255, 0xff, 0xff, 0x80, 0x00 }, &offset, 255),
        0.0001,
    );
}

test "CFF INDEX offsets stay inside declared object data" {
    const valid = [_]u8{
        0x00, 0x02, // count
        0x01, // offSize
        0x01, 0x01, 0x03, // empty object, then "OK"
        'O',  'K',
    };
    const index = try readIndex(&valid, 0);
    try std.testing.expectEqualSlices(u8, &.{}, try index.object(&valid, 0));
    try std.testing.expectEqualStrings("OK", try index.object(&valid, 1));

    const first_offset_gap = [_]u8{
        0x00, 0x01, // count
        0x01, // offSize
        0x02, 0x03, // first offset must be 1, not a gap into object data
        0xaa, 0xbb,
    };
    try std.testing.expectError(error.BadCff, readIndex(&first_offset_gap, 0));

    const borrows_next_structure = [_]u8{
        0x00, 0x02, // count
        0x01, // offSize
        0x01, 0x06, 0x03, // object 0 would borrow bytes past the final offset
        'n',  'a',  'm',
        'e',  's',
    };
    try std.testing.expectError(error.BadCff, readIndex(&borrows_next_structure, 0));
}

test "CFF header and Top DICT INDEX describe a CFF 1.0 single-font set" {
    const valid_single_font = [_]u8{
        0x01, 0x00, 0x04, 0x01, // CFF 1.0 header, hdrSize=4, offSize=1.
        0x00, 0x01, 0x01, 0x01, 0x01, // Name INDEX: one empty test name.
        0x00, 0x01, 0x01, 0x01, 0x03, 159, 17, // Top DICT: CharStrings at byte 20.
        0x00, 0x00, // String INDEX.
        0x00, 0x00, // Global Subrs INDEX.
        0x00, 0x01, 0x01, 0x01, 0x02, 0x0e, // CharStrings INDEX: one endchar.
    };
    const info = try parseInfo(&valid_single_font);
    try std.testing.expectEqual(@as(usize, 20), info.charstrings_offset);
    try std.testing.expectEqual(@as(u16, 1), info.charstrings_count);

    var bad_major = valid_single_font;
    bad_major[0] = 2;
    try std.testing.expectError(error.BadCff, parseInfo(&bad_major));

    var short_header = valid_single_font;
    short_header[2] = 3;
    try std.testing.expectError(error.BadCff, parseInfo(&short_header));

    var bad_header_off_size = valid_single_font;
    bad_header_off_size[3] = 0;
    try std.testing.expectError(error.BadCff, parseInfo(&bad_header_off_size));

    const multi_font_set = [_]u8{
        0x01, 0x00, 0x04, 0x01,
        0x00, 0x01, 0x01, 0x01,
        0x01,
        // OpenType embeds only single-font CFF data. A multi-entry Top DICT
        // INDEX is a valid CFF FontSet shape in isolation, but it cannot be
        // mapped to one SFNT face without choosing an arbitrary dictionary.
        0x00, 0x02, 0x01,
        0x01, 0x03, 0x05, 159,
        17,   159,  17,
    };
    try std.testing.expectError(error.BadCff, parseInfo(&multi_font_set));
}

test "CFF DICT offsets reject missing fractional and negative operands" {
    try std.testing.expectError(error.BadCff, parseTopDict(&.{17}));
    try std.testing.expectError(error.BadCff, parseTopDict(&.{ 30, 0x1a, 0x5f, 17 }));
    try std.testing.expectError(error.BadCff, parseTopDict(&.{ 138, 17 }));
    try std.testing.expectError(error.BadCff, parseTopDict(&.{ 159, 17, 138, 159, 18 }));

    var info = Info{ .charstrings_offset = 20, .charstrings_count = 0, .global_subrs_offset = 0, .private_offset = 10 };
    try std.testing.expectError(error.BadCff, parsePrivateDict(&.{ 30, 0x1a, 0x5f, 19 }, &info));
}

test "CFF DICT data rejects trailing operands without an operator" {
    try std.testing.expectError(error.BadCff, parseTopDict(&.{ 159, 17, 139 }));

    var info = Info{ .charstrings_offset = 20, .charstrings_count = 0, .global_subrs_offset = 0, .private_offset = 10 };
    try parsePrivateDict(&.{ 140, 20 }, &info);
    try std.testing.expectEqual(@as(f32, 1), info.default_width_x);

    // A second operand after the final operator cannot contribute to any DICT
    // key. Reject it rather than accepting non-canonical bytes after otherwise
    // valid Private DICT metadata.
    try std.testing.expectError(error.BadCff, parsePrivateDict(&.{ 140, 20, 139 }, &info));
}

test "CFF Private DICT Subrs offset resolves to a Local Subrs INDEX" {
    const valid_local_subrs = [_]u8{
        0x01, 0x00, 0x04, 0x01, // CFF 1.0 header.
        0x00, 0x01, 0x01, 0x01, 0x01, // Name INDEX.
        // Top DICT: CharStrings at 27, Private DICT size 2 at 23.
        0x00, 0x01, 0x01, 0x01, 0x06,
        166,  17,   141,  162,  18,
        0x00, 0x00, // String INDEX.
        0x00, 0x00, // Global Subrs INDEX.
        141, 19, // Private DICT: Subrs offset 2, immediately after dict.
        0x00, 0x00, // Local Subrs INDEX.
        0x00, 0x01, 0x01, 0x01, 0x02, 0x0e, // CharStrings INDEX.
    };
    const info = try parseInfo(&valid_local_subrs);
    try std.testing.expectEqual(@as(usize, 25), info.local_subrs_offset);

    var subrs_points_into_private_dict = valid_local_subrs;
    subrs_points_into_private_dict[23] = 139; // Subrs offset 0 aliases Private DICT bytes.
    try std.testing.expectError(error.BadCff, parseInfo(&subrs_points_into_private_dict));
}

test "CFF Type2 hvcurveto and vhcurveto keep their implicit last axis" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    var interpreter = testInterpreter(&outline);
    interpreter.stack[0] = 10;
    interpreter.stack[1] = 20;
    interpreter.stack[2] = 30;
    interpreter.stack[3] = 40;
    interpreter.stack_len = 4;
    try interpreter.hvcurveto();
    try std.testing.expectEqual(@as(usize, 1), outline.commands.items.len);
    switch (outline.commands.items[0]) {
        .cubic_to => |curve| {
            try std.testing.expectApproxEqAbs(@as(f32, 10), curve.c0.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 0), curve.c0.y, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 30), curve.c1.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 30), curve.c1.y, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 30), curve.end.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 70), curve.end.y, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }

    outline.commands.clearRetainingCapacity();
    interpreter = testInterpreter(&outline);
    interpreter.stack[0] = 10;
    interpreter.stack[1] = 20;
    interpreter.stack[2] = 30;
    interpreter.stack[3] = 40;
    interpreter.stack_len = 4;
    try interpreter.vhcurveto();
    try std.testing.expectEqual(@as(usize, 1), outline.commands.items.len);
    switch (outline.commands.items[0]) {
        .cubic_to => |curve| {
            try std.testing.expectApproxEqAbs(@as(f32, 0), curve.c0.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 10), curve.c0.y, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 20), curve.c1.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 40), curve.c1.y, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 60), curve.end.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 40), curve.end.y, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "CFF Type2 flex operators expand to cubic outline segments" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    var interpreter = testInterpreter(&outline);
    const operands = [_]f32{ 10, 0, 20, 10, 30, -10, 40, 0, 50, 10, 60, -10, 5 };
    @memcpy(interpreter.stack[0..operands.len], &operands);
    interpreter.stack_len = operands.len;
    try interpreter.escapedOperator(35);
    try std.testing.expectEqual(@as(usize, 2), outline.commands.items.len);
    switch (outline.commands.items[1]) {
        .cubic_to => |curve| {
            try std.testing.expectApproxEqAbs(@as(f32, 210), curve.end.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 0), curve.end.y, 0.001);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "CFF Type2 charstrings require explicit endchar" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    var interpreter = testInterpreter(&outline);
    try interpreter.run(&.{0x0e}); // A complete empty glyph is still valid.
    interpreter = testInterpreter(&outline);
    interpreter.nominal_width_x = 500;
    try interpreter.run(&.{ 149, 14 }); // width=510 followed by endchar.
    try std.testing.expectEqual(@as(f32, 510), interpreter.width);
    try std.testing.expect(interpreter.width_seen);
    try std.testing.expectError(error.BadCff, interpreter.run(&.{}));
    try std.testing.expectError(error.BadCff, interpreter.run(&.{139})); // Operand stack without an endchar.
}

test "CFF Type2 endchar records validated seac operands" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    var interpreter = testInterpreter(&outline);
    // adx=-14, ady=15, bchar='A', achar=grave.
    try interpreter.run(&.{ 125, 154, 204, 247, 85, 14 });
    try std.testing.expectEqual(@as(?Type2Interpreter.Seac, .{
        .adx = -14,
        .ady = 15,
        .base_code = 65,
        .accent_code = 193,
    }), interpreter.seac);

    interpreter = testInterpreter(&outline);
    try std.testing.expectError(error.BadCff, interpreter.run(&.{ 139, 139, 255, 0, 65, 128, 0, 247, 85, 14 }));
}

test "CFF StandardEncoding and custom charsets resolve seac components" {
    try std.testing.expectEqual(@as(u16, 34), standardEncodingSid('A'));
    try std.testing.expectEqual(@as(u16, 124), standardEncodingSid(193));
    try std.testing.expectEqual(@as(u16, 127), standardEncodingSid(196));
    try std.testing.expectEqual(@as(u16, 0), standardEncodingSid(0));

    // Format 0 lists one SID per glyph after .notdef.
    const format_0 = [_]u8{ 0, 0, 34, 0, 54, 0, 174, 0, 195, 0, 124, 0, 127 };
    const info_0 = Info{
        .charstrings_offset = 1,
        .charstrings_count = 229,
        .global_subrs_offset = 1,
        .charset_offset = 0,
    };
    var custom_0 = info_0;
    custom_0.charset_offset = 0; // Predefined ISOAdobe: gid == SID.
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 34), try charsetGlyphForSid(&.{}, custom_0, 34));

    var wrapped_0: [20]u8 = .{0} ** 20;
    @memcpy(wrapped_0[5 .. 5 + format_0.len], &format_0);
    custom_0.charset_offset = 5;
    custom_0.charstrings_count = 7;
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 5), try charsetGlyphForSid(&wrapped_0, custom_0, 124));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 6), try charsetGlyphForSid(&wrapped_0, custom_0, 127));

    // Formats 1 and 2 encode SID ranges with u8/u16 left counts.
    const format_1 = [_]u8{ 1, 0, 34, 2, 0, 124, 1 };
    var wrapped_1: [16]u8 = .{0} ** 16;
    @memcpy(wrapped_1[4 .. 4 + format_1.len], &format_1);
    var range_info = info_0;
    range_info.charstrings_count = 6;
    range_info.charset_offset = 4;
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 4), try charsetGlyphForSid(&wrapped_1, range_info, 124));

    const format_2 = [_]u8{ 2, 0, 34, 0, 2, 0, 124, 0, 1 };
    var wrapped_2: [16]u8 = .{0} ** 16;
    @memcpy(wrapped_2[4 .. 4 + format_2.len], &format_2);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 5), try charsetGlyphForSid(&wrapped_2, range_info, 125));
}

test "CFF FDSelect formats 0 and 3 select bounded Font DICTs" {
    const format_0 = [_]u8{ 0, 0, 1, 2, 2 };
    try std.testing.expectEqual(@as(usize, 0), try fdSelectValue(&format_0, .{ .offset = 0, .format = 0 }, 0, 4, 3));
    try std.testing.expectEqual(@as(usize, 2), try fdSelectValue(&format_0, .{ .offset = 0, .format = 0 }, 3, 4, 3));

    const format_3 = [_]u8{
        3,
        0, 2, // nRanges
        0, 0, 0, // glyph 0 -> FD 0
        0, 2, 1, // glyph 2 -> FD 1
        0, 5, // sentinel glyph count
    };
    const select = FdSelect{ .offset = 0, .format = 3 };
    try validateFdSelect(&format_3, select, 5, 2);
    try std.testing.expectEqual(@as(usize, 0), try fdSelectValue(&format_3, select, 1, 5, 2));
    try std.testing.expectEqual(@as(usize, 1), try fdSelectValue(&format_3, select, 4, 5, 2));
}

test "CFF Type2 drawing operators reject empty operand stacks" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    var interpreter = testInterpreter(&outline);
    try std.testing.expectError(error.StackUnderflow, interpreter.run(&.{ 5, 14 })); // rlineto
    try std.testing.expectError(error.StackUnderflow, interpreter.run(&.{ 6, 14 })); // hlineto
    try std.testing.expectError(error.StackUnderflow, interpreter.run(&.{ 7, 14 })); // vlineto
    try std.testing.expectError(error.StackUnderflow, interpreter.run(&.{ 8, 14 })); // rrcurveto
}

test "CFF Type2 subroutines require explicit return or endchar" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    const valid_subrs_data = [_]u8{
        0x00, 0x01, // count
        0x01, // offSize
        0x01, 0x02, // one-byte subroutine object
        0x0b, // return
    };
    var valid_interpreter = testInterpreter(&outline);
    valid_interpreter.cff_data = &valid_subrs_data;
    valid_interpreter.local_subrs = try readIndex(&valid_subrs_data, 0);
    try valid_interpreter.run(&.{ 32, 10, 14 }); // -107 selects subr 0 for a one-entry INDEX, then endchar.

    const truncated_subrs_data = [_]u8{
        0x00, 0x01, // count
        0x01, // offSize
        0x01,
        0x02,
        139, // pushes 0 and then falls off the end without return/endchar
    };
    var truncated_interpreter = testInterpreter(&outline);
    truncated_interpreter.cff_data = &truncated_subrs_data;
    truncated_interpreter.local_subrs = try readIndex(&truncated_subrs_data, 0);
    try std.testing.expectError(error.BadCff, truncated_interpreter.run(&.{ 32, 10, 14 }));
}

test "CFF Type2 subroutine indexes reject fractional operands" {
    var outline = glyph_mod.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 0,
        .y_min = 0,
        .x_max = 100,
        .y_max = 100,
    }, 100, 0);
    defer outline.deinit();

    const subrs_data = [_]u8{
        0x00, 0x01, // count
        0x01, // offSize
        0x01,
        0x02,
        0x0b, // return
    };
    var interpreter = testInterpreter(&outline);
    interpreter.cff_data = &subrs_data;
    interpreter.local_subrs = try readIndex(&subrs_data, 0);

    // Byte 255 encodes a 16.16 number in Type2 charstrings. A fractional
    // subroutine operand must be rejected rather than truncated to an adjacent
    // valid subroutine index.
    try std.testing.expectError(error.BadCff, interpreter.run(&.{ 255, 0xff, 0x95, 0x80, 0x00, 10, 14 }));
}

fn testInterpreter(outline: *glyph_mod.GlyphOutline) Type2Interpreter {
    return .{
        .allocator = std.testing.allocator,
        .outline = outline,
        .nominal_width_x = 0,
        .default_width_x = 0,
        .cff_data = &.{},
        .global_subrs = .{ .count = 0, .off_size = 0, .offsets_pos = 0, .object_base = 0, .end = 0 },
        .local_subrs = null,
    };
}

const Type2Interpreter = struct {
    allocator: std.mem.Allocator,
    outline: *glyph_mod.GlyphOutline,
    stack: [96]f32 = undefined,
    stack_len: usize = 0,
    x: f32 = 0,
    y: f32 = 0,
    contour_open: bool = false,
    width_seen: bool = false,
    width: f32 = 0,
    stem_count: usize = 0,
    nominal_width_x: f32,
    default_width_x: f32,
    cff_data: []const u8,
    global_subrs: Index,
    local_subrs: ?Index,
    seac: ?Seac = null,

    const Seac = struct {
        adx: f32,
        ady: f32,
        base_code: u8,
        accent_code: u8,
    };

    fn run(self: *Type2Interpreter, bytes: []const u8) CffError!void {
        self.width = self.default_width_x;
        if (try self.runCharString(bytes, 0) != .endchar) return error.BadCff;
    }

    const Type2Termination = enum {
        endchar,
        @"return",
    };

    fn runCharString(self: *Type2Interpreter, bytes: []const u8, depth: u8) CffError!Type2Termination {
        // Type2 charstrings are a compact stack machine. Operators consume the
        // current stack, update the current point, and append path commands.
        // Subroutines recurse through the same interpreter state. Reaching the
        // byte stream end without `endchar` or `return` is malformed: otherwise
        // a truncated charstring can be accepted as a valid empty/silent glyph.
        if (depth > 16) return error.UnsupportedCff;
        var offset: usize = 0;
        while (offset < bytes.len) {
            const b = bytes[offset];
            offset += 1;
            if (b == 28 or b >= 32) {
                try self.push(try readNumber(bytes, &offset, b));
                continue;
            }
            switch (b) {
                1, 3, 18, 23 => self.readStems(),
                12 => {
                    if (offset >= bytes.len) return error.EndOfStream;
                    const escaped = bytes[offset];
                    offset += 1;
                    try self.escapedOperator(escaped);
                },
                4 => try self.vmoveto(),
                5 => try self.rlineto(),
                6 => try self.hlineto(),
                7 => try self.vlineto(),
                8 => try self.rrcurveto(),
                10 => if (try self.callSubr(self.local_subrs orelse return error.UnsupportedCff, depth + 1) == .endchar) return .endchar,
                11 => return .@"return",
                19, 20 => try self.readHintMask(bytes, &offset),
                24 => try self.rcurveline(),
                25 => try self.rlinecurve(),
                26 => try self.vvcurveto(),
                27 => try self.hhcurveto(),
                14 => {
                    try self.readEndcharSeac();
                    if (self.contour_open) try self.close();
                    self.stack_len = 0;
                    return .endchar;
                },
                21 => try self.rmoveto(),
                22 => try self.hmoveto(),
                29 => if (try self.callSubr(self.global_subrs, depth + 1) == .endchar) return .endchar,
                30 => try self.vhcurveto(),
                31 => try self.hvcurveto(),
                else => return error.UnsupportedCff,
            }
        }
        return error.BadCff;
    }

    fn readEndcharSeac(self: *Type2Interpreter) CffError!void {
        if (self.stack_len == 0) return;
        // A lone operand is the optional width of an ordinary endchar, not an
        // incomplete seac. CFF math fonts use this compact form for otherwise
        // empty or fully subroutine-drawn glyphs.
        if (!self.width_seen and self.stack_len == 1) {
            self.width = self.nominal_width_x + self.stack[0];
            self.width_seen = true;
            return;
        }
        var start: usize = 0;
        // Type2 permits an optional width before the four seac operands.
        if (!self.width_seen and self.stack_len == 5) {
            self.width = self.nominal_width_x + self.stack[0];
            self.width_seen = true;
            start = 1;
        }
        if (self.stack_len - start != 4) return error.BadCff;
        const base = try seacCode(self.stack[start + 2]);
        const accent = try seacCode(self.stack[start + 3]);
        self.seac = .{
            .adx = self.stack[start],
            .ady = self.stack[start + 1],
            .base_code = base,
            .accent_code = accent,
        };
    }

    fn escapedOperator(self: *Type2Interpreter, op: u8) CffError!void {
        // Type 2 charstrings keep the compatibility "flex" operators behind
        // the escaped operator byte. Latin Modern Math and STIX Math use these
        // in ordinary letters, digits, and math symbols; treating byte 12 as an
        // unknown operator made whole glyphs disappear from Zui formula text.
        // Flex depth and hinting decisions are rasterizer quality hints for
        // very small sizes, so this outline extractor expands them into the two
        // cubic curves they describe and leaves antialiasing to the renderer.
        switch (op) {
            0 => self.stack_len = 0, // dotsection: deprecated Type 1 hint.
            34 => try self.hflex(),
            35 => try self.flex(),
            36 => try self.hflex1(),
            37 => try self.flex1(),
            else => return error.UnsupportedCff,
        }
    }

    fn push(self: *Type2Interpreter, value: f32) CffError!void {
        if (self.stack_len >= self.stack.len) return error.StackOverflow;
        self.stack[self.stack_len] = value;
        self.stack_len += 1;
    }

    fn popInteger(self: *Type2Interpreter) CffError!i32 {
        if (self.stack_len == 0) return error.StackUnderflow;
        self.stack_len -= 1;
        const value = self.stack[self.stack_len];
        // callsubr/callgsubr operands are biased integer indexes. Type2's
        // general operand encoding can also represent 16.16 fixed values; do
        // not silently truncate those or let rounded/out-of-range f32 values
        // reach @intFromFloat and trap under safety checks.
        if (!std.math.isFinite(value) or value != @trunc(value)) return error.BadCff;
        const widened: f64 = value;
        if (widened < @as(f64, @floatFromInt(std.math.minInt(i32))) or widened > @as(f64, @floatFromInt(std.math.maxInt(i32)))) return error.BadCff;
        return @intFromFloat(widened);
    }

    fn callSubr(self: *Type2Interpreter, index: Index, depth: u8) CffError!Type2Termination {
        // The operand names a biased subroutine index, not a direct array index.
        const operand = try self.popInteger();
        const biased = @as(i64, operand) + @as(i64, subrBias(index.count));
        if (biased < 0 or biased >= @as(i64, index.count)) return error.InvalidGlyph;
        const subr = try index.object(self.cff_data, @intCast(biased));
        return try self.runCharString(subr, depth);
    }

    fn takeWidth(self: *Type2Interpreter, expected_without_width: usize) void {
        // Many drawing operators can optionally carry an initial width operand.
        // Once detected, remove it from the operand stack before geometry reads.
        if (!self.width_seen and self.stack_len == expected_without_width + 1) {
            self.width = self.nominal_width_x + self.stack[0];
            std.mem.copyForwards(f32, self.stack[0 .. self.stack_len - 1], self.stack[1..self.stack_len]);
            self.stack_len -= 1;
        }
        self.width_seen = true;
    }

    fn readStems(self: *Type2Interpreter) void {
        // Stem hints affect rasterization quality, but this outline extractor
        // only needs to count them so hintmask/cntrmask byte lengths are known.
        if (!self.width_seen and (self.stack_len & 1) == 1) {
            self.width = self.nominal_width_x + self.stack[0];
            std.mem.copyForwards(f32, self.stack[0 .. self.stack_len - 1], self.stack[1..self.stack_len]);
            self.stack_len -= 1;
        }
        self.stem_count += self.stack_len / 2;
        self.width_seen = true;
        self.stack_len = 0;
    }

    fn readHintMask(self: *Type2Interpreter, bytes: []const u8, offset: *usize) CffError!void {
        self.readStems();
        const mask_len = (self.stem_count + 7) / 8;
        if (mask_len > bytes.len - offset.*) return error.EndOfStream;
        offset.* += mask_len;
    }

    fn rmoveto(self: *Type2Interpreter) CffError!void {
        self.takeWidth(2);
        if (self.stack_len < 2) return error.StackUnderflow;
        if (self.contour_open) try self.close();
        self.x += self.stack[0];
        self.y += self.stack[1];
        try self.moveTo();
        self.stack_len = 0;
    }

    fn hmoveto(self: *Type2Interpreter) CffError!void {
        self.takeWidth(1);
        if (self.stack_len < 1) return error.StackUnderflow;
        if (self.contour_open) try self.close();
        self.x += self.stack[0];
        try self.moveTo();
        self.stack_len = 0;
    }

    fn vmoveto(self: *Type2Interpreter) CffError!void {
        self.takeWidth(1);
        if (self.stack_len < 1) return error.StackUnderflow;
        if (self.contour_open) try self.close();
        self.y += self.stack[0];
        try self.moveTo();
        self.stack_len = 0;
    }

    fn rlineto(self: *Type2Interpreter) CffError!void {
        if (self.stack_len < 2 or (self.stack_len & 1) != 0) return error.StackUnderflow;
        var i: usize = 0;
        while (i < self.stack_len) : (i += 2) {
            self.x += self.stack[i];
            self.y += self.stack[i + 1];
            try self.lineTo();
        }
        self.stack_len = 0;
    }

    fn hlineto(self: *Type2Interpreter) CffError!void {
        if (self.stack_len == 0) return error.StackUnderflow;
        var horizontal = true;
        for (self.stack[0..self.stack_len]) |delta| {
            if (horizontal) self.x += delta else self.y += delta;
            try self.lineTo();
            horizontal = !horizontal;
        }
        self.stack_len = 0;
    }

    fn vlineto(self: *Type2Interpreter) CffError!void {
        if (self.stack_len == 0) return error.StackUnderflow;
        var vertical = true;
        for (self.stack[0..self.stack_len]) |delta| {
            if (vertical) self.y += delta else self.x += delta;
            try self.lineTo();
            vertical = !vertical;
        }
        self.stack_len = 0;
    }

    fn rrcurveto(self: *Type2Interpreter) CffError!void {
        if (self.stack_len < 6 or self.stack_len % 6 != 0) return error.StackUnderflow;
        var i: usize = 0;
        while (i < self.stack_len) : (i += 6) {
            try self.curveByDeltas(self.stack[i], self.stack[i + 1], self.stack[i + 2], self.stack[i + 3], self.stack[i + 4], self.stack[i + 5]);
        }
        self.stack_len = 0;
    }

    fn hflex(self: *Type2Interpreter) CffError!void {
        self.takeWidth(7);
        if (self.stack_len != 7) return error.StackUnderflow;
        const dx1 = self.stack[0];
        const dx2 = self.stack[1];
        const dy2 = self.stack[2];
        const dx3 = self.stack[3];
        const dx4 = self.stack[4];
        const dx5 = self.stack[5];
        const dx6 = self.stack[6];
        try self.curveByDeltas(dx1, 0, dx2, dy2, dx3, 0);
        try self.curveByDeltas(dx4, 0, dx5, -dy2, dx6, 0);
        self.stack_len = 0;
    }

    fn flex(self: *Type2Interpreter) CffError!void {
        self.takeWidth(13);
        if (self.stack_len != 13) return error.StackUnderflow;
        try self.curveByDeltas(self.stack[0], self.stack[1], self.stack[2], self.stack[3], self.stack[4], self.stack[5]);
        try self.curveByDeltas(self.stack[6], self.stack[7], self.stack[8], self.stack[9], self.stack[10], self.stack[11]);
        // stack[12] is flex depth. It selects hinted flex rendering in legacy
        // rasterizers and does not affect the outline geometry.
        self.stack_len = 0;
    }

    fn hflex1(self: *Type2Interpreter) CffError!void {
        self.takeWidth(9);
        if (self.stack_len != 9) return error.StackUnderflow;
        const dx1 = self.stack[0];
        const dy1 = self.stack[1];
        const dx2 = self.stack[2];
        const dy2 = self.stack[3];
        const dx3 = self.stack[4];
        const dx4 = self.stack[5];
        const dx5 = self.stack[6];
        const dy5 = self.stack[7];
        const dx6 = self.stack[8];
        try self.curveByDeltas(dx1, dy1, dx2, dy2, dx3, 0);
        try self.curveByDeltas(dx4, 0, dx5, dy5, dx6, -(dy1 + dy2 + dy5));
        self.stack_len = 0;
    }

    fn flex1(self: *Type2Interpreter) CffError!void {
        self.takeWidth(11);
        if (self.stack_len != 11) return error.StackUnderflow;
        const dx1 = self.stack[0];
        const dy1 = self.stack[1];
        const dx2 = self.stack[2];
        const dy2 = self.stack[3];
        const dx3 = self.stack[4];
        const dy3 = self.stack[5];
        const dx4 = self.stack[6];
        const dy4 = self.stack[7];
        const dx5 = self.stack[8];
        const dy5 = self.stack[9];
        const d6 = self.stack[10];
        const dx_total = dx1 + dx2 + dx3 + dx4 + dx5;
        const dy_total = dy1 + dy2 + dy3 + dy4 + dy5;
        const dx6: f32 = if (@abs(dx_total) > @abs(dy_total)) d6 else -dx_total;
        const dy6: f32 = if (@abs(dx_total) > @abs(dy_total)) -dy_total else d6;
        try self.curveByDeltas(dx1, dy1, dx2, dy2, dx3, dy3);
        try self.curveByDeltas(dx4, dy4, dx5, dy5, dx6, dy6);
        self.stack_len = 0;
    }

    fn rcurveline(self: *Type2Interpreter) CffError!void {
        if (self.stack_len < 8 or ((self.stack_len - 2) % 6) != 0) return error.StackUnderflow;
        var i: usize = 0;
        while (i + 2 < self.stack_len) : (i += 6) {
            try self.curveByDeltas(self.stack[i], self.stack[i + 1], self.stack[i + 2], self.stack[i + 3], self.stack[i + 4], self.stack[i + 5]);
        }
        self.x += self.stack[self.stack_len - 2];
        self.y += self.stack[self.stack_len - 1];
        try self.lineTo();
        self.stack_len = 0;
    }

    fn rlinecurve(self: *Type2Interpreter) CffError!void {
        if (self.stack_len < 8 or ((self.stack_len - 6) & 1) != 0) return error.StackUnderflow;
        var i: usize = 0;
        while (i + 6 < self.stack_len) : (i += 2) {
            self.x += self.stack[i];
            self.y += self.stack[i + 1];
            try self.lineTo();
        }
        try self.curveByDeltas(self.stack[i], self.stack[i + 1], self.stack[i + 2], self.stack[i + 3], self.stack[i + 4], self.stack[i + 5]);
        self.stack_len = 0;
    }

    fn vvcurveto(self: *Type2Interpreter) CffError!void {
        var i: usize = 0;
        var dx1: f32 = 0;
        if ((self.stack_len & 1) != 0) {
            dx1 = self.stack[0];
            i = 1;
        }
        if (self.stack_len - i < 4 or ((self.stack_len - i) % 4) != 0) return error.StackUnderflow;
        while (i < self.stack_len) : (i += 4) {
            try self.curveByDeltas(dx1, self.stack[i], self.stack[i + 1], self.stack[i + 2], 0, self.stack[i + 3]);
            dx1 = 0;
        }
        self.stack_len = 0;
    }

    fn hhcurveto(self: *Type2Interpreter) CffError!void {
        var i: usize = 0;
        var dy1: f32 = 0;
        if ((self.stack_len & 1) != 0) {
            dy1 = self.stack[0];
            i = 1;
        }
        if (self.stack_len - i < 4 or ((self.stack_len - i) % 4) != 0) return error.StackUnderflow;
        while (i < self.stack_len) : (i += 4) {
            try self.curveByDeltas(self.stack[i], dy1, self.stack[i + 1], self.stack[i + 2], self.stack[i + 3], 0);
            dy1 = 0;
        }
        self.stack_len = 0;
    }

    fn vhcurveto(self: *Type2Interpreter) CffError!void {
        try self.alternatingCurve(false);
    }

    fn hvcurveto(self: *Type2Interpreter) CffError!void {
        try self.alternatingCurve(true);
    }

    fn alternatingCurve(self: *Type2Interpreter, horizontal_first: bool) CffError!void {
        // hvcurveto/vhcurveto alternate omitted dy/dx components. A final odd
        // operand supplies the missing component of the last curve.
        if (self.stack_len < 4) return error.StackUnderflow;
        var i: usize = 0;
        var horizontal = horizontal_first;
        while (i + 4 <= self.stack_len) {
            const last_curve = self.stack_len - i == 5;
            const d6 = if (last_curve) self.stack[i + 4] else 0;
            if (horizontal) {
                try self.curveByDeltas(self.stack[i], 0, self.stack[i + 1], self.stack[i + 2], if (last_curve) d6 else 0, self.stack[i + 3]);
            } else {
                try self.curveByDeltas(0, self.stack[i], self.stack[i + 1], self.stack[i + 2], self.stack[i + 3], if (last_curve) d6 else 0);
            }
            i += if (last_curve) 5 else 4;
            horizontal = !horizontal;
        }
        if (i != self.stack_len) return error.StackUnderflow;
        self.stack_len = 0;
    }

    fn curveByDeltas(self: *Type2Interpreter, dx1: f32, dy1: f32, dx2: f32, dy2: f32, dx3: f32, dy3: f32) CffError!void {
        // Cubic control points are relative deltas from the current point; the
        // endpoint becomes the new current point for the next operator.
        const c0 = glyph_mod.Point{ .x = self.x + dx1, .y = self.y + dy1 };
        const c1 = glyph_mod.Point{ .x = c0.x + dx2, .y = c0.y + dy2 };
        self.x = c1.x + dx3;
        self.y = c1.y + dy3;
        try self.outline.commands.append(self.allocator, .{ .cubic_to = .{
            .c0 = c0,
            .c1 = c1,
            .end = .{ .x = self.x, .y = self.y },
        } });
    }

    fn moveTo(self: *Type2Interpreter) CffError!void {
        try self.outline.commands.append(self.allocator, .{ .move_to = .{ .x = self.x, .y = self.y } });
        self.contour_open = true;
    }

    fn lineTo(self: *Type2Interpreter) CffError!void {
        try self.outline.commands.append(self.allocator, .{ .line_to = .{ .x = self.x, .y = self.y } });
    }

    fn close(self: *Type2Interpreter) CffError!void {
        try self.outline.commands.append(self.allocator, .close);
        self.contour_open = false;
    }
};
