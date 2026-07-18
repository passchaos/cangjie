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
    global_subrs_offset: usize,
    private_offset: usize = 0,
    private_size: usize = 0,
    local_subrs_offset: usize = 0,
    default_width_x: f32 = 0,
    nominal_width_x: f32 = 0,
};

/// Parse the CFF header and the small amount of top/private DICT state needed
/// to locate CharStrings and subroutine indexes.
pub fn parseInfo(data: []const u8) CffError!Info {
    if (data.len < 4) return error.BadCff;
    const header_size = data[2];
    if (header_size > data.len) return error.BadCff;
    const name_index = try readIndex(data, header_size);
    const top_index = try readIndex(data, name_index.end);
    if (top_index.count == 0) return error.BadCff;
    const top_dict = try top_index.object(data, 0);
    var info = try parseTopDict(top_dict);
    const string_index = try readIndex(data, top_index.end);
    info.global_subrs_offset = string_index.end;
    _ = try readIndex(data, info.global_subrs_offset);
    if (info.charstrings_offset >= data.len) return error.BadCff;
    if (info.private_size > 0) {
        if (info.private_offset > data.len or info.private_size > data.len - info.private_offset) return error.BadCff;
        try parsePrivateDict(data[info.private_offset .. info.private_offset + info.private_size], &info);
    }
    return info;
}

/// Interpret one Type2 charstring into the shared GlyphOutline representation.
pub fn appendGlyphOutline(allocator: std.mem.Allocator, data: []const u8, info: Info, outline: *glyph_mod.GlyphOutline, glyph_id: glyph_mod.GlyphId) CffError!void {
    const charstrings = try readIndex(data, info.charstrings_offset);
    if (glyph_id >= charstrings.count) return error.InvalidGlyph;
    const bytes = try charstrings.object(data, glyph_id);
    var interpreter = Type2Interpreter{
        .allocator = allocator,
        .outline = outline,
        .nominal_width_x = info.nominal_width_x,
        .default_width_x = info.default_width_x,
        .cff_data = data,
        .global_subrs = try readIndex(data, info.global_subrs_offset),
        .local_subrs = if (info.local_subrs_offset != 0) try readIndex(data, info.local_subrs_offset) else null,
    };
    try interpreter.run(bytes);
}

const Index = struct {
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
    if (offset + size > data.len) return error.EndOfStream;
    var value: usize = 0;
    for (0..size) |i| value = (value << 8) | data[offset + i];
    return value;
}

fn subrBias(count: u16) i32 {
    // Type2 subroutine operands are biased by the subroutine count. These
    // thresholds are defined by the CFF specification.
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
}

fn parseTopDict(dict: []const u8) CffError!Info {
    var info = Info{ .charstrings_offset = 0, .global_subrs_offset = 0 };
    var parser = DictParser.init(dict);
    while (try parser.next()) |entry| {
        switch (entry.operator) {
            17 => info.charstrings_offset = @intFromFloat(entry.operands[0]),
            18 => {
                if (entry.operands.len < 2) return error.BadCff;
                info.private_size = @intFromFloat(entry.operands[0]);
                info.private_offset = @intFromFloat(entry.operands[1]);
            },
            else => {},
        }
    }
    if (info.charstrings_offset == 0) return error.BadCff;
    return info;
}

fn parsePrivateDict(dict: []const u8, info: *Info) CffError!void {
    var parser = DictParser.init(dict);
    while (try parser.next()) |entry| {
        switch (entry.operator) {
            19 => {
                if (entry.operands.len < 1) return error.BadCff;
                info.local_subrs_offset = info.private_offset + @as(usize, @intFromFloat(entry.operands[0]));
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

    fn run(self: *Type2Interpreter, bytes: []const u8) CffError!void {
        self.width = self.default_width_x;
        try self.runCharString(bytes, 0);
    }

    fn runCharString(self: *Type2Interpreter, bytes: []const u8, depth: u8) CffError!void {
        // Type2 charstrings are a compact stack machine. Operators consume the
        // current stack, update the current point, and append path commands.
        // Subroutines recurse through the same interpreter state.
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
                10 => try self.callSubr(self.local_subrs orelse return error.UnsupportedCff, depth + 1),
                11 => return,
                19, 20 => try self.readHintMask(bytes, &offset),
                24 => try self.rcurveline(),
                25 => try self.rlinecurve(),
                26 => try self.vvcurveto(),
                27 => try self.hhcurveto(),
                14 => {
                    if (self.contour_open) try self.close();
                    self.stack_len = 0;
                    return;
                },
                21 => try self.rmoveto(),
                22 => try self.hmoveto(),
                29 => try self.callSubr(self.global_subrs, depth + 1),
                30 => try self.vhcurveto(),
                31 => try self.hvcurveto(),
                else => return error.UnsupportedCff,
            }
        }
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

    fn popInt(self: *Type2Interpreter) CffError!i32 {
        if (self.stack_len == 0) return error.StackUnderflow;
        self.stack_len -= 1;
        return @intFromFloat(self.stack[self.stack_len]);
    }

    fn callSubr(self: *Type2Interpreter, index: Index, depth: u8) CffError!void {
        // The operand names a biased subroutine index, not a direct array index.
        const operand = try self.popInt();
        const biased = operand + subrBias(index.count);
        if (biased < 0) return error.InvalidGlyph;
        const subr = try index.object(self.cff_data, @intCast(biased));
        try self.runCharString(subr, depth);
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
        if ((self.stack_len & 1) != 0) return error.StackUnderflow;
        var i: usize = 0;
        while (i < self.stack_len) : (i += 2) {
            self.x += self.stack[i];
            self.y += self.stack[i + 1];
            try self.lineTo();
        }
        self.stack_len = 0;
    }

    fn hlineto(self: *Type2Interpreter) CffError!void {
        var horizontal = true;
        for (self.stack[0..self.stack_len]) |delta| {
            if (horizontal) self.x += delta else self.y += delta;
            try self.lineTo();
            horizontal = !horizontal;
        }
        self.stack_len = 0;
    }

    fn vlineto(self: *Type2Interpreter) CffError!void {
        var vertical = true;
        for (self.stack[0..self.stack_len]) |delta| {
            if (vertical) self.y += delta else self.x += delta;
            try self.lineTo();
            vertical = !vertical;
        }
        self.stack_len = 0;
    }

    fn rrcurveto(self: *Type2Interpreter) CffError!void {
        if (self.stack_len % 6 != 0) return error.StackUnderflow;
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
