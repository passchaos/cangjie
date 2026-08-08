const std = @import("std");
const charstring_mod = @import("cff2/charstring.zig");
const variation_mod = @import("cff2/variation.zig");
const glyph_mod = @import("../glyph.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const TopDictInfo = struct {
    charstrings_offset: ?usize = null,
    fd_array_offset: ?usize = null,
    fd_select_offset: ?usize = null,
    vstore_offset: ?usize = null,
};

pub const IndexInfo = struct {
    offset: usize,
    count: u32,
    off_size: u8,
    data_offset: usize,
    data_length: usize,
};

pub const FdSelectInfo = struct {
    offset: usize,
    format: u8,
};

pub const FontDictInfo = struct {
    index: usize,
    data_offset: usize,
    data_length: usize,
    private_dict: PrivateDictInfo,
};

pub const PrivateDictInfo = struct {
    offset: usize,
    size: usize,
    data: []const u8,
    local_subrs_offset: ?usize = null,
    local_subrs_index: ?IndexInfo = null,
    default_width_x: ?i32 = null,
    nominal_width_x: ?i32 = null,
    variation_store_index: ?u16 = null,
};

pub const CharStringScanInfo = charstring_mod.Info;
pub const CharStringBoundsInfo = charstring_mod.BoundsInfo;

pub const Info = struct {
    major_version: u8,
    minor_version: u8,
    header_size: u8,
    top_dict_length: u16,
    top_dict_data: []const u8,
    trailing_data: []const u8,
    global_subrs_index: IndexInfo,
    top_dict: TopDictInfo,
    charstrings_index: ?IndexInfo = null,
    fd_array_index: ?IndexInfo = null,
    fd_select: ?FdSelectInfo = null,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    _ = try infoView(data, offset, length);
}

pub fn info(data: []const u8, offset: usize, length: usize) Error!Info {
    return try infoView(data, offset, length);
}

pub fn fontDictIndex(data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize) Error!?u16 {
    if (glyph_id >= glyph_count) return error.BadSfnt;
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    return try selectedFontDictIndex(table, parsed, glyph_id, glyph_count);
}

pub fn subrBias(count: u32) i32 {
    // Type2/CFF2 subroutine operands do not directly encode array indexes.
    // The caller adds a count-dependent bias before indexing Global or Local
    // Subrs; exposing the same rule here lets future interpreters and tests
    // share the exact boundary behavior used by FreeType/HarfBuzz/fontations.
    if (count < 1240) return 107;
    if (count < 33900) return 1131;
    return 32768;
}

pub fn subrIndexForOperand(index: IndexInfo, operand: i32) ?usize {
    const biased = @as(i64, operand) + @as(i64, subrBias(index.count));
    if (biased < 0 or biased >= @as(i64, index.count)) return null;
    return @intCast(biased);
}

pub fn fontDictInfo(data: []const u8, offset: usize, length: usize, font_dict_index: usize) Error!?FontDictInfo {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    const fd_array = parsed.fd_array_index orelse return null;
    if (font_dict_index >= fd_array.count) return null;
    return try parseFontDict(table, fd_array, font_dict_index);
}

pub fn globalSubrDataForOperand(data: []const u8, offset: usize, length: usize, operand: i32) Error!?[]const u8 {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    const subr_index = subrIndexForOperand(parsed.global_subrs_index, operand) orelse return null;
    return try indexObject(table, parsed.global_subrs_index, subr_index);
}

pub fn localSubrData(data: []const u8, offset: usize, length: usize, font_dict_index: usize, subr_index: usize) Error!?[]const u8 {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const fd_info = (try fontDictInfo(data, offset, length, font_dict_index)) orelse return null;
    const local_subrs = fd_info.private_dict.local_subrs_index orelse return null;
    if (subr_index >= local_subrs.count) return null;
    return try indexObject(table, local_subrs, subr_index);
}

pub fn localSubrDataForOperand(data: []const u8, offset: usize, length: usize, font_dict_index: usize, operand: i32) Error!?[]const u8 {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const fd_info = (try fontDictInfo(data, offset, length, font_dict_index)) orelse return null;
    const local_subrs = fd_info.private_dict.local_subrs_index orelse return null;
    const subr_index = subrIndexForOperand(local_subrs, operand) orelse return null;
    return try indexObject(table, local_subrs, subr_index);
}

pub fn globalSubrData(data: []const u8, offset: usize, length: usize, subr_index: usize) Error!?[]const u8 {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    if (subr_index >= parsed.global_subrs_index.count) return null;
    return try indexObject(table, parsed.global_subrs_index, subr_index);
}

pub fn charStringData(data: []const u8, offset: usize, length: usize, glyph_id: usize) Error!?[]const u8 {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    const index = parsed.charstrings_index orelse return null;
    if (glyph_id >= index.count) return null;
    return try indexObject(table, index, glyph_id);
}

pub fn charStringScanInfo(data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize) Error!?CharStringScanInfo {
    var execution = (try charStringExecutionContext(data, offset, length, glyph_id, glyph_count, &.{})) orelse return null;
    return try charstring_mod.scan(CharStringScanContext, &execution.context, execution.charstring);
}

pub fn charStringBoundsInfo(data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize) Error!?CharStringBoundsInfo {
    return try charStringBoundsInfoAtCoords(data, offset, length, glyph_id, glyph_count, &.{});
}

pub fn charStringBoundsInfoAtCoords(data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize, normalized_coords: []const f32) Error!?CharStringBoundsInfo {
    var execution = (try charStringExecutionContext(data, offset, length, glyph_id, glyph_count, normalized_coords)) orelse return null;
    return try charstring_mod.bounds(CharStringScanContext, &execution.context, execution.charstring);
}

pub fn appendGlyphOutline(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize, outline: *glyph_mod.GlyphOutline) Error!?CharStringBoundsInfo {
    return try appendGlyphOutlineAtCoords(allocator, data, offset, length, glyph_id, glyph_count, &.{}, outline);
}

pub fn appendGlyphOutlineAtCoords(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize, normalized_coords: []const f32, outline: *glyph_mod.GlyphOutline) Error!?CharStringBoundsInfo {
    var execution = (try charStringExecutionContext(data, offset, length, glyph_id, glyph_count, normalized_coords)) orelse return null;
    return try charstring_mod.appendOutline(CharStringScanContext, &execution.context, allocator, execution.charstring, outline);
}

const CharStringExecutionContext = struct {
    charstring: []const u8,
    context: CharStringScanContext,
};

fn charStringExecutionContext(data: []const u8, offset: usize, length: usize, glyph_id: usize, glyph_count: usize, normalized_coords: []const f32) Error!?CharStringExecutionContext {
    if (glyph_id >= glyph_count) return error.BadSfnt;
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const parsed = try infoView(data, offset, length);
    const index = parsed.charstrings_index orelse return null;
    if (glyph_id >= index.count) return null;
    const charstring = try indexObject(table, index, glyph_id);

    const selected_fd = (try selectedFontDictIndex(table, parsed, glyph_id, glyph_count)) orelse 0;
    const private_dict = if (parsed.fd_array_index) |fd_array| blk: {
        if (selected_fd >= fd_array.count) return error.BadSfnt;
        const font_dict = try parseFontDict(table, fd_array, selected_fd);
        break :blk font_dict.private_dict;
    } else null;

    return .{
        .charstring = charstring,
        .context = .{
            .table = table,
            .vstore_offset = parsed.top_dict.vstore_offset,
            .default_vs_index = if (private_dict) |private| private.variation_store_index else null,
            .normalized_coords = normalized_coords,
            .global_subrs_index = parsed.global_subrs_index,
            .local_subrs_index = if (private_dict) |private| private.local_subrs_index else null,
        },
    };
}

fn selectedFontDictIndex(table: []const u8, parsed: Info, glyph_id: usize, glyph_count: usize) Error!?u16 {
    const fd_count = if (parsed.fd_array_index) |fd_array| @as(usize, @intCast(fd_array.count)) else 1;
    const fd_select = parsed.fd_select orelse {
        // CFF2 permits omitting FDSelect when all glyphs use the sole Font DICT.
        // fontations/skrifa exposes that case as subfont index 0 rather than as
        // missing metadata, so do the same for public queries and execution.
        return if (fd_count == 1) @as(?u16, 0) else error.BadSfnt;
    };
    return try fdSelectValue(table, fd_select.offset, glyph_id, glyph_count, fd_count);
}

const CharStringScanContext = struct {
    table: []const u8,
    vstore_offset: ?usize = null,
    default_vs_index: ?u16 = null,
    normalized_coords: []const f32 = &.{},
    global_subrs_index: IndexInfo,
    local_subrs_index: ?IndexInfo = null,

    pub fn initialVariationStoreIndex(self: *CharStringScanContext) Error!u16 {
        return self.default_vs_index orelse 0;
    }

    pub fn blendRegionCount(self: *CharStringScanContext, vs_index: u16) Error!usize {
        const offset = self.vstore_offset orelse return error.BadSfnt;
        return try variation_mod.regionCount(self.table, offset, vs_index);
    }

    pub fn blendScalar(self: *CharStringScanContext, vs_index: u16, region_index: usize) Error!f32 {
        const offset = self.vstore_offset orelse return error.BadSfnt;
        return try variation_mod.scalar(self.table, offset, vs_index, region_index, self.normalized_coords);
    }

    pub fn globalSubr(self: *CharStringScanContext, operand: i32) Error!?[]const u8 {
        const subr_index = subrIndexForOperand(self.global_subrs_index, operand) orelse return null;
        return try indexObject(self.table, self.global_subrs_index, subr_index);
    }

    pub fn localSubr(self: *CharStringScanContext, operand: i32) Error!?[]const u8 {
        const local_subrs = self.local_subrs_index orelse return null;
        const subr_index = subrIndexForOperand(local_subrs, operand) orelse return null;
        return try indexObject(self.table, local_subrs, subr_index);
    }
};

fn infoView(data: []const u8, offset: usize, length: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 5) return error.BadSfnt;
    const table = data[offset .. offset + length];
    const major = table[0];
    const minor = table[1];
    const header_size = table[2];
    if (major != 2 or minor != 0) return error.BadSfnt;
    if (header_size < 5 or header_size > table.len) return error.BadSfnt;
    const top_dict_length = std.mem.readInt(u16, table[3..5], .big);
    if (@as(usize, top_dict_length) > table.len - header_size) return error.BadSfnt;
    const top_start: usize = header_size;
    const top_end = top_start + @as(usize, top_dict_length);
    const top_dict_data = table[top_start..top_end];
    const top_dict = try parseTopDict(top_dict_data, table.len);
    // CFF2 keeps the Global Subr INDEX directly after the Top DICT. Parse it
    // eagerly because later CFF2 charstring execution needs these bounds before
    // interpreting callgsubr operands.
    const global_subrs_index = try indexInfo(table, top_end);
    const charstrings_index = if (top_dict.charstrings_offset) |charstrings_offset| try indexInfo(table, charstrings_offset) else null;
    const fd_array_index = if (top_dict.fd_array_offset) |fd_array_offset| try indexInfo(table, fd_array_offset) else null;
    const fd_select = if (top_dict.fd_select_offset) |fd_select_offset| try fdSelectInfo(table, fd_select_offset) else null;
    return .{
        .major_version = major,
        .minor_version = minor,
        .header_size = header_size,
        .top_dict_length = top_dict_length,
        .top_dict_data = top_dict_data,
        .trailing_data = table[top_end..],
        .global_subrs_index = global_subrs_index,
        .top_dict = top_dict,
        .charstrings_index = charstrings_index,
        .fd_array_index = fd_array_index,
        .fd_select = fd_select,
    };
}

const DictParser = struct {
    data: []const u8,
    offset: usize = 0,
    operands: [48]i32 = undefined,
    operand_count: usize = 0,

    fn next(self: *DictParser) Error!?struct { op: u16, operands: []const i32 } {
        while (self.offset < self.data.len) {
            const b = self.data[self.offset];
            self.offset += 1;
            switch (b) {
                0...22, 24 => {
                    const op: u16 = if (b == 12) blk: {
                        if (self.offset >= self.data.len) return error.BadSfnt;
                        const escaped = self.data[self.offset];
                        self.offset += 1;
                        break :blk @as(u16, 0x0c00) | escaped;
                    } else b;
                    const operands = self.operands[0..self.operand_count];
                    self.operand_count = 0;
                    return .{ .op = op, .operands = operands };
                },
                28 => {
                    if (self.offset + 2 > self.data.len) return error.BadSfnt;
                    try self.push(@as(i16, @bitCast(std.mem.readInt(u16, self.data[self.offset..][0..2], .big))));
                    self.offset += 2;
                },
                29 => {
                    if (self.offset + 4 > self.data.len) return error.BadSfnt;
                    try self.push(std.mem.readInt(i32, self.data[self.offset..][0..4], .big));
                    self.offset += 4;
                },
                30 => return error.BadSfnt, // real numbers are not offsets and are unnecessary for metadata.
                32...246 => try self.push(@as(i32, b) - 139),
                247...250 => {
                    if (self.offset >= self.data.len) return error.BadSfnt;
                    const value = (@as(i32, b) - 247) * 256 + self.data[self.offset] + 108;
                    self.offset += 1;
                    try self.push(value);
                },
                251...254 => {
                    if (self.offset >= self.data.len) return error.BadSfnt;
                    const value = -((@as(i32, b) - 251) * 256 + self.data[self.offset] + 108);
                    self.offset += 1;
                    try self.push(value);
                },
                255 => {
                    if (self.offset + 4 > self.data.len) return error.BadSfnt;
                    const fixed = std.mem.readInt(i32, self.data[self.offset..][0..4], .big);
                    self.offset += 4;
                    try self.push(fixed >> 16);
                },
                else => return error.BadSfnt,
            }
        }
        if (self.operand_count != 0) return error.BadSfnt;
        return null;
    }

    fn push(self: *DictParser, value: i32) Error!void {
        if (self.operand_count == self.operands.len) return error.BadSfnt;
        self.operands[self.operand_count] = value;
        self.operand_count += 1;
    }
};

fn parseTopDict(data: []const u8, table_len: usize) Error!TopDictInfo {
    var parser = DictParser{ .data = data };
    var result = TopDictInfo{};
    while (try parser.next()) |entry| {
        switch (entry.op) {
            17 => result.charstrings_offset = try readOffsetOperand(entry.operands),
            24 => result.vstore_offset = try readOffsetOperand(entry.operands),
            0x0c24 => result.fd_array_offset = try readOffsetOperand(entry.operands),
            0x0c25 => result.fd_select_offset = try readOffsetOperand(entry.operands),
            else => {},
        }
    }
    inline for (.{ result.charstrings_offset, result.fd_array_offset, result.fd_select_offset, result.vstore_offset }) |maybe_offset| {
        if (maybe_offset) |value| {
            if (value >= table_len) return error.BadSfnt;
        }
    }
    return result;
}

fn parseFontDict(table: []const u8, fd_array: IndexInfo, font_dict_index: usize) Error!FontDictInfo {
    const object = try indexObjectRange(table, fd_array, font_dict_index);
    var parser = DictParser{ .data = object.data };
    var private_dict: ?PrivateDictInfo = null;
    while (try parser.next()) |entry| {
        switch (entry.op) {
            18 => {
                const private_size = try readOffsetOperandAt(entry.operands, 0);
                const private_offset = try readOffsetOperandAt(entry.operands, 1);
                if (private_offset > table.len or private_size > table.len - private_offset) return error.BadSfnt;
                private_dict = try parsePrivateDict(table, private_offset, private_size);
            },
            else => {},
        }
    }
    return .{
        .index = font_dict_index,
        .data_offset = object.start,
        .data_length = object.data.len,
        // CFF2 Font DICTs are the per-FD source of Private DICT metadata.
        // Requiring the link here lets callers fail before a charstring
        // interpreter tries to resolve widths or local subroutines lazily.
        .private_dict = private_dict orelse return error.BadSfnt,
    };
}

fn parsePrivateDict(table: []const u8, offset: usize, size: usize) Error!PrivateDictInfo {
    if (offset > table.len or size > table.len - offset) return error.BadSfnt;
    const dict = table[offset .. offset + size];
    var result = PrivateDictInfo{
        .offset = offset,
        .size = size,
        .data = dict,
    };
    var parser = DictParser{ .data = dict };
    while (try parser.next()) |entry| {
        switch (entry.op) {
            19 => {
                const relative_offset = try readOffsetOperandAt(entry.operands, 0);
                if (relative_offset > std.math.maxInt(usize) - offset) return error.BadSfnt;
                const local_subrs_offset = offset + relative_offset;
                if (local_subrs_offset < offset + size) return error.BadSfnt;
                result.local_subrs_offset = local_subrs_offset;
                result.local_subrs_index = try indexInfo(table, local_subrs_offset);
            },
            20 => result.default_width_x = try readIntegerOperandAt(entry.operands, 0),
            21 => result.nominal_width_x = try readIntegerOperandAt(entry.operands, 0),
            22 => {
                const index = try readOffsetOperandAt(entry.operands, 0);
                if (index > std.math.maxInt(u16)) return error.BadSfnt;
                result.variation_store_index = @intCast(index);
            },
            else => {},
        }
    }
    return result;
}

fn fdSelectValue(table: []const u8, offset: usize, glyph_id: usize, glyph_count: usize, fd_count: usize) Error!u16 {
    const fd_select = try fdSelectInfo(table, offset);
    return switch (fd_select.format) {
        0 => blk: {
            if (glyph_count > table.len - offset - 1) return error.BadSfnt;
            const value = table[offset + 1 + glyph_id];
            if (value >= fd_count) return error.BadSfnt;
            break :blk value;
        },
        3 => try fdSelectRangeValue(table, offset + 1, glyph_id, glyph_count, fd_count, 2, 1),
        4 => try fdSelectRangeValue(table, offset + 1, glyph_id, glyph_count, fd_count, 4, 2),
        else => error.BadSfnt,
    };
}

fn fdSelectRangeValue(table: []const u8, offset: usize, glyph_id: usize, glyph_count: usize, fd_count: usize, glyph_size: usize, fd_size: usize) Error!u16 {
    if (offset > table.len or glyph_size > table.len - offset) return error.BadSfnt;
    const range_count = readSizedOffset(table, offset, glyph_size);
    const record_size = glyph_size + fd_size;
    const records_start = offset + glyph_size;
    if (range_count == 0 or range_count > (table.len - records_start) / record_size) return error.BadSfnt;
    const sentinel_offset = records_start + range_count * record_size;
    if (glyph_size > table.len - sentinel_offset) return error.BadSfnt;
    const sentinel = readSizedOffset(table, sentinel_offset, glyph_size);
    if (sentinel != glyph_count) return error.BadSfnt;

    var previous_first: ?usize = null;
    var selected_fd: ?u16 = null;
    for (0..range_count) |index| {
        const record = records_start + index * record_size;
        const first = readSizedOffset(table, record, glyph_size);
        const fd = readSizedOffset(table, record + glyph_size, fd_size);
        if (first >= glyph_count or fd >= fd_count) return error.BadSfnt;
        if (previous_first) |previous| {
            if (first <= previous) return error.BadSfnt;
        } else if (first != 0) return error.BadSfnt;
        previous_first = first;
        if (glyph_id >= first) selected_fd = @intCast(fd);
    }
    return selected_fd orelse error.BadSfnt;
}

fn fdSelectInfo(table: []const u8, offset: usize) Error!FdSelectInfo {
    if (offset >= table.len) return error.BadSfnt;
    const format = table[offset];
    switch (format) {
        0 => {},
        3 => if (table.len - offset < 4) return error.BadSfnt,
        4 => if (table.len - offset < 6) return error.BadSfnt,
        else => return error.BadSfnt,
    }
    return .{ .offset = offset, .format = format };
}

fn indexInfo(table: []const u8, offset: usize) Error!IndexInfo {
    if (offset > table.len or table.len - offset < 4) return error.BadSfnt;
    const count = std.mem.readInt(u32, table[offset..][0..4], .big);
    if (count == 0) {
        return .{
            .offset = offset,
            .count = 0,
            .off_size = 0,
            .data_offset = offset + 4,
            .data_length = 0,
        };
    }
    if (table.len - offset < 5) return error.BadSfnt;
    const off_size = table[offset + 4];
    if (off_size < 1 or off_size > 4) return error.BadSfnt;
    const offset_array_len = (@as(usize, count) + 1) * @as(usize, off_size);
    if (offset_array_len > table.len - offset - 5) return error.BadSfnt;
    const offsets_start = offset + 5;
    const data_start = offsets_start + offset_array_len;
    var previous: usize = 1;
    for (0..@as(usize, count) + 1) |index| {
        const value = readSizedOffset(table, offsets_start + index * @as(usize, off_size), off_size);
        if (value < previous) return error.BadSfnt;
        if (value - 1 > table.len - data_start) return error.BadSfnt;
        previous = value;
    }
    return .{
        .offset = offset,
        .count = count,
        .off_size = off_size,
        .data_offset = data_start,
        .data_length = previous - 1,
    };
}

const IndexObjectRange = struct {
    start: usize,
    end: usize,
    data: []const u8,
};

fn indexObject(table: []const u8, index: IndexInfo, object_index: usize) Error![]const u8 {
    return (try indexObjectRange(table, index, object_index)).data;
}

fn indexObjectRange(table: []const u8, index: IndexInfo, object_index: usize) Error!IndexObjectRange {
    if (object_index >= index.count) return error.BadSfnt;
    const offsets_start = index.offset + 5;
    const start = readSizedOffset(table, offsets_start + object_index * @as(usize, index.off_size), index.off_size);
    const end = readSizedOffset(table, offsets_start + (object_index + 1) * @as(usize, index.off_size), index.off_size);
    if (start > end or start == 0) return error.BadSfnt;
    const object_start = index.data_offset + start - 1;
    const object_end = index.data_offset + end - 1;
    if (object_end > table.len) return error.BadSfnt;
    return .{
        .start = object_start,
        .end = object_end,
        .data = table[object_start..object_end],
    };
}

fn readSizedOffset(table: []const u8, offset: usize, size: usize) usize {
    var value: usize = 0;
    for (0..size) |index| value = (value << 8) | table[offset + index];
    return value;
}

fn readOffsetOperand(operands: []const i32) Error!usize {
    if (operands.len == 0) return error.BadSfnt;
    const value = operands[operands.len - 1];
    if (value < 0) return error.BadSfnt;
    return @intCast(value);
}

fn readOffsetOperandAt(operands: []const i32, index: usize) Error!usize {
    const value = try readIntegerOperandAt(operands, index);
    if (value < 0) return error.BadSfnt;
    return @intCast(value);
}

fn readIntegerOperandAt(operands: []const i32, index: usize) Error!i32 {
    if (index >= operands.len) return error.BadSfnt;
    return operands[index];
}

test "CFF2 header exposes top dict, global subrs, and trailing data" {
    const bytes = testCff2Table();
    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(u8, 2), parsed.major_version);
    try std.testing.expectEqual(@as(u8, 5), parsed.header_size);
    try std.testing.expectEqual(@as(u16, 10), parsed.top_dict_length);
    const global_subrs = parsed.global_subrs_index;
    try std.testing.expectEqual(@as(usize, 15), global_subrs.offset);
    try std.testing.expectEqual(@as(u32, 1), global_subrs.count);
    try std.testing.expectEqual(@as(u8, 1), global_subrs.off_size);
    try std.testing.expectEqual(@as(usize, 22), global_subrs.data_offset);
    try std.testing.expectEqual(@as(usize, 1), global_subrs.data_length);
    try std.testing.expectEqual(@as(?usize, 23), parsed.top_dict.charstrings_offset);
    try std.testing.expectEqual(@as(?usize, 43), parsed.top_dict.fd_array_offset);
    try std.testing.expectEqual(@as(?usize, 53), parsed.top_dict.fd_select_offset);
    try std.testing.expectEqual(@as(?usize, 70), parsed.top_dict.vstore_offset);
    const charstrings = parsed.charstrings_index.?;
    try std.testing.expectEqual(@as(u32, 1), charstrings.count);
    try std.testing.expectEqual(@as(u8, 1), charstrings.off_size);
    try std.testing.expectEqual(@as(usize, 30), charstrings.data_offset);
    try std.testing.expectEqual(@as(usize, 13), charstrings.data_length);
    try std.testing.expectEqualSlices(u8, &.{11}, (try globalSubrData(&bytes, 0, bytes.len, 0)).?);
    try std.testing.expect((try globalSubrData(&bytes, 0, bytes.len, 1)) == null);
    try std.testing.expectEqualSlices(u8, &.{ 32, 10, 32, 29, 189, 159, 21, 239, 139, 139, 169, 5, 14 }, (try charStringData(&bytes, 0, bytes.len, 0)).?);
    const fd_array = parsed.fd_array_index.?;
    try std.testing.expectEqual(@as(u32, 1), fd_array.count);
    try std.testing.expectEqual(@as(usize, 50), fd_array.data_offset);
    try std.testing.expectEqual(@as(usize, 3), fd_array.data_length);
    const fd_select = parsed.fd_select.?;
    try std.testing.expectEqual(@as(usize, 53), fd_select.offset);
    try std.testing.expectEqual(@as(u8, 0), fd_select.format);
    try std.testing.expectEqual(@as(?u16, 0), try fontDictIndex(&bytes, 0, bytes.len, 0, 2));
    try std.testing.expectEqual(@as(?u16, 0), try fontDictIndex(&bytes, 0, bytes.len, 1, 2));
    try std.testing.expect((try charStringData(&bytes, 0, bytes.len, 1)) == null);
}

test "CFF2 single Font DICT defaults to FD zero without FDSelect" {
    const bytes = testCff2SingleFdNoSelectTable();
    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expect(parsed.fd_select == null);
    try std.testing.expectEqual(@as(u32, 1), parsed.fd_array_index.?.count);
    try std.testing.expectEqual(@as(?u16, 0), try fontDictIndex(&bytes, 0, bytes.len, 0, 2));
    try std.testing.expectEqual(@as(?u16, 0), try fontDictIndex(&bytes, 0, bytes.len, 1, 2));
}

test "CFF2 multiple Font DICTs require FDSelect" {
    var bytes = testCff2SingleFdNoSelectTable();
    // Expand the FDArray count in-place without adding a second object. This is
    // enough to exercise the glyph->FD selection contract before FD parsing.
    std.mem.writeInt(u32, bytes[31..35], 2, .big);
    try std.testing.expectError(error.BadSfnt, fontDictIndex(&bytes, 0, bytes.len, 0, 2));
    try std.testing.expectError(error.BadSfnt, charStringScanInfo(&bytes, 0, bytes.len, 0, 2));
    try std.testing.expectError(error.BadSfnt, charStringBoundsInfo(&bytes, 0, bytes.len, 0, 2));
}

test "CFF2 execution uses Private DICT default vsindex" {
    var bytes = testCff2Table();
    // Private DICT: insert vsindex 0 before Local Subrs. Keep total size 6 by
    // dropping width metadata that is irrelevant for charstring execution here.
    bytes[56] = 139;
    bytes[57] = 22;
    bytes[58] = 145;
    bytes[59] = 19;
    bytes[60] = 139;
    bytes[61] = 20;
    const font_dict = (try fontDictInfo(&bytes, 0, bytes.len, 0)).?;
    try std.testing.expectEqual(@as(?u16, 0), font_dict.private_dict.variation_store_index);
    try std.testing.expect((try charStringBoundsInfo(&bytes, 0, bytes.len, 0, 2)) != null);
}

test "CFF2 exposes Font DICT private metadata and local subrs" {
    const bytes = testCff2Table();
    const font_dict = (try fontDictInfo(&bytes, 0, bytes.len, 0)).?;
    try std.testing.expectEqual(@as(usize, 0), font_dict.index);
    try std.testing.expectEqual(@as(usize, 50), font_dict.data_offset);
    try std.testing.expectEqual(@as(usize, 3), font_dict.data_length);
    const private = font_dict.private_dict;
    try std.testing.expectEqual(@as(usize, 56), private.offset);
    try std.testing.expectEqual(@as(usize, 6), private.size);
    try std.testing.expectEqualSlices(u8, &.{ 146, 20, 119, 21, 145, 19 }, private.data);
    try std.testing.expectEqual(@as(?i32, 7), private.default_width_x);
    try std.testing.expectEqual(@as(?i32, -20), private.nominal_width_x);
    try std.testing.expectEqual(@as(?usize, 62), private.local_subrs_offset);
    const local_subrs = private.local_subrs_index.?;
    try std.testing.expectEqual(@as(usize, 62), local_subrs.offset);
    try std.testing.expectEqual(@as(u32, 1), local_subrs.count);
    try std.testing.expectEqual(@as(usize, 69), local_subrs.data_offset);
    try std.testing.expectEqual(@as(usize, 1), local_subrs.data_length);
    try std.testing.expectEqualSlices(u8, &.{11}, (try localSubrData(&bytes, 0, bytes.len, 0, 0)).?);
    try std.testing.expect((try localSubrData(&bytes, 0, bytes.len, 0, 1)) == null);
    try std.testing.expect((try fontDictInfo(&bytes, 0, bytes.len, 1)) == null);
}

test "CFF2 resolves biased Global and Local Subr operands" {
    const bytes = testCff2Table();
    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(i32, 107), subrBias(0));
    try std.testing.expectEqual(@as(i32, 107), subrBias(1239));
    try std.testing.expectEqual(@as(i32, 1131), subrBias(1240));
    try std.testing.expectEqual(@as(i32, 1131), subrBias(33899));
    try std.testing.expectEqual(@as(i32, 32768), subrBias(33900));
    try std.testing.expectEqual(@as(?usize, 0), subrIndexForOperand(parsed.global_subrs_index, -107));
    try std.testing.expectEqual(@as(?usize, null), subrIndexForOperand(parsed.global_subrs_index, -108));
    try std.testing.expectEqual(@as(?usize, null), subrIndexForOperand(parsed.global_subrs_index, -106));
    try std.testing.expectEqualSlices(u8, &.{11}, (try globalSubrDataForOperand(&bytes, 0, bytes.len, -107)).?);
    try std.testing.expect((try globalSubrDataForOperand(&bytes, 0, bytes.len, -106)) == null);
    try std.testing.expectEqualSlices(u8, &.{11}, (try localSubrDataForOperand(&bytes, 0, bytes.len, 0, -107)).?);
    try std.testing.expect((try localSubrDataForOperand(&bytes, 0, bytes.len, 0, -106)) == null);
}

test "CFF2 charstring bounds accepts normalized variation coordinates" {
    const bytes = testCff2BlendTable();
    const default_bounds = (try charStringBoundsInfoAtCoords(&bytes, 0, bytes.len, 0, 1, &.{})).?;
    try std.testing.expectEqual(@as(f32, 50), default_bounds.x_min);
    try std.testing.expectEqual(@as(f32, 60), default_bounds.x_max);
    const varied_bounds = (try charStringBoundsInfoAtCoords(&bytes, 0, bytes.len, 0, 1, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 60), varied_bounds.x_min);
    try std.testing.expectEqual(@as(f32, 70), varied_bounds.x_max);
}

test "CFF2 scans glyph charstrings through biased subr calls" {
    const bytes = testCff2Table();
    const scanned = (try charStringScanInfo(&bytes, 0, bytes.len, 0, 2)).?;
    try std.testing.expectEqual(@as(usize, 3), scanned.charstring_count);
    try std.testing.expectEqual(@as(usize, 15), scanned.byte_count);
    try std.testing.expectEqual(@as(usize, 8), scanned.number_count);
    try std.testing.expectEqual(@as(usize, 7), scanned.operator_count);
    try std.testing.expectEqual(@as(usize, 1), scanned.local_subr_call_count);
    try std.testing.expectEqual(@as(usize, 1), scanned.global_subr_call_count);
    try std.testing.expectEqual(@as(u8, 1), scanned.max_depth);
    try std.testing.expect(scanned.has_return);
    try std.testing.expect(scanned.has_endchar);
    try std.testing.expect((try charStringScanInfo(&bytes, 0, bytes.len, 1, 2)) == null);
}

test "CFF2 accepts an empty Global Subr INDEX" {
    const bytes = [_]u8{ 2, 0, 5, 0, 0, 0, 0, 0, 0 };
    const parsed = try info(&bytes, 0, bytes.len);
    try std.testing.expectEqual(@as(usize, 5), parsed.global_subrs_index.offset);
    try std.testing.expectEqual(@as(u32, 0), parsed.global_subrs_index.count);
    try std.testing.expectEqual(@as(u8, 0), parsed.global_subrs_index.off_size);
    try std.testing.expectEqual(@as(usize, 9), parsed.global_subrs_index.data_offset);
    try std.testing.expectEqual(@as(usize, 0), parsed.global_subrs_index.data_length);
    try std.testing.expect((try globalSubrData(&bytes, 0, bytes.len, 0)) == null);
}

test "CFF2 rejects bad versions and oversized top dicts" {
    try std.testing.expectError(error.BadSfnt, validate(&.{ 1, 0, 5, 0, 0 }, 0, 5));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 2, 0, 4, 0, 0 }, 0, 5));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 2, 0, 5, 0, 1 }, 0, 5));
}

fn testCff2Table() [71]u8 {
    var bytes = [_]u8{0} ** 71;
    bytes[0] = 2;
    bytes[2] = 5;
    std.mem.writeInt(u16, bytes[3..5], 10, .big);
    bytes[5] = 162; // CharStrings offset 23.
    bytes[6] = 17;
    bytes[7] = 182; // FDArray offset 43.
    bytes[8] = 12;
    bytes[9] = 36;
    bytes[10] = 192; // FDSelect offset 53.
    bytes[11] = 12;
    bytes[12] = 37;
    bytes[13] = 209; // vstore offset 70.
    bytes[14] = 24;

    std.mem.writeInt(u32, bytes[15..19], 1, .big); // Global Subrs INDEX.
    bytes[19] = 1;
    bytes[20] = 1;
    bytes[21] = 2;
    bytes[22] = 11;

    std.mem.writeInt(u32, bytes[23..27], 1, .big); // CharStrings INDEX.
    bytes[27] = 1;
    bytes[28] = 1;
    bytes[29] = 14;
    bytes[30] = 32; // callsubr operand -107.
    bytes[31] = 10;
    bytes[32] = 32; // callgsubr operand -107.
    bytes[33] = 29;
    bytes[34] = 189; // rmoveto dx 50.
    bytes[35] = 159; // rmoveto dy 20.
    bytes[36] = 21;
    bytes[37] = 239; // rlineto dx 100.
    bytes[38] = 139; // rlineto dy 0.
    bytes[39] = 139; // rlineto dx 0.
    bytes[40] = 169; // rlineto dy 30.
    bytes[41] = 5;
    bytes[42] = 14;

    std.mem.writeInt(u32, bytes[43..47], 1, .big); // FDArray INDEX.
    bytes[47] = 1;
    bytes[48] = 1;
    bytes[49] = 4;
    bytes[50] = 145; // Private DICT size 6.
    bytes[51] = 195; // Private DICT offset 56.
    bytes[52] = 18;

    bytes[53] = 0; // FDSelect format 0 for two glyphs.
    bytes[54] = 0;
    bytes[55] = 0;

    bytes[56] = 146; // defaultWidthX 7.
    bytes[57] = 20;
    bytes[58] = 119; // nominalWidthX -20.
    bytes[59] = 21;
    bytes[60] = 145; // Local Subrs offset 6, immediately after Private DICT.
    bytes[61] = 19;

    std.mem.writeInt(u32, bytes[62..66], 1, .big); // Local Subrs INDEX.
    bytes[66] = 1;
    bytes[67] = 1;
    bytes[68] = 2;
    bytes[69] = 11;
    bytes[70] = 0x03;
    return bytes;
}

fn testCff2SingleFdNoSelectTable() [52]u8 {
    var bytes = [_]u8{0} ** 52;
    bytes[0] = 2;
    bytes[2] = 5;
    std.mem.writeInt(u16, bytes[3..5], 7, .big);
    bytes[5] = 159; // CharStrings offset 20.
    bytes[6] = 17;
    bytes[7] = 170; // FDArray offset 31.
    bytes[8] = 12;
    bytes[9] = 36;
    bytes[10] = 190; // vstore offset 51.
    bytes[11] = 24;

    std.mem.writeInt(u32, bytes[12..16], 1, .big); // Global Subrs INDEX.
    bytes[16] = 1;
    bytes[17] = 1;
    bytes[18] = 2;
    bytes[19] = 11;

    std.mem.writeInt(u32, bytes[20..24], 1, .big); // CharStrings INDEX.
    bytes[24] = 1;
    bytes[25] = 1;
    bytes[26] = 6;
    bytes[27] = 139;
    bytes[28] = 139;
    bytes[29] = 21;
    bytes[30] = 14;

    std.mem.writeInt(u32, bytes[31..35], 1, .big); // FDArray INDEX.
    bytes[35] = 1;
    bytes[36] = 1;
    bytes[37] = 4;
    bytes[38] = 145; // Private DICT size 6.
    bytes[39] = 183; // Private DICT offset 44.
    bytes[40] = 18;

    bytes[44] = 146;
    bytes[45] = 20;
    bytes[46] = 119;
    bytes[47] = 21;
    bytes[48] = 145;
    bytes[49] = 19;
    bytes[50] = 0;
    bytes[51] = 0x03;
    return bytes;
}

fn testCff2BlendTable() [98]u8 {
    var bytes = [_]u8{0} ** 98;
    bytes[0] = 2;
    bytes[2] = 5;
    std.mem.writeInt(u16, bytes[3..5], 7, .big);
    bytes[5] = 159; // CharStrings offset 20.
    bytes[6] = 17;
    bytes[7] = 178; // FDArray offset 39.
    bytes[8] = 12;
    bytes[9] = 36;
    bytes[10] = 194; // vstore offset 55.
    bytes[11] = 24;

    std.mem.writeInt(u32, bytes[12..16], 0, .big); // Empty Global Subrs INDEX.

    std.mem.writeInt(u32, bytes[20..24], 1, .big); // CharStrings INDEX.
    bytes[24] = 1;
    bytes[25] = 1;
    bytes[26] = 13;
    bytes[27] = 189; // default x 50.
    bytes[28] = 159; // delta x 20.
    bytes[29] = 140; // blend count 1.
    bytes[30] = 16;
    bytes[31] = 139; // y 0.
    bytes[32] = 21; // rmoveto.
    bytes[33] = 149; // hlineto 10.
    bytes[34] = 6;
    bytes[35] = 14;

    std.mem.writeInt(u32, bytes[39..43], 1, .big); // FDArray INDEX.
    bytes[43] = 1;
    bytes[44] = 1;
    bytes[45] = 4;
    bytes[46] = 140; // Private DICT size 1.
    bytes[47] = 193; // Private DICT offset 54.
    bytes[48] = 18;

    bytes[49] = 0; // FDSelect format 0 for one glyph.
    bytes[50] = 0;

    bytes[54] = 0x0e; // Private DICT object: ignored operator with empty operands.

    bytes[55] = 0;
    bytes[56] = 43; // CFF2 VariationStore length, including this length field.
    bytes[57] = 0;
    bytes[58] = 1; // ItemVariationStore format.
    std.mem.writeInt(u32, bytes[59..63], 20, .big); // VariationRegionList offset.
    bytes[63] = 0;
    bytes[64] = 1; // One ItemVariationData subtable.
    std.mem.writeInt(u32, bytes[65..69], 12, .big); // ItemVariationData offset.
    bytes[69] = 0;
    bytes[70] = 1; // itemCount.
    bytes[71] = 0;
    bytes[72] = 0; // wordDeltaCount.
    bytes[73] = 0;
    bytes[74] = 1; // regionIndexCount.
    bytes[75] = 0;
    bytes[76] = 0; // region index 0.
    bytes[77] = 0;
    bytes[78] = 1; // axisCount.
    bytes[79] = 0;
    bytes[80] = 1; // regionCount.
    bytes[81] = 0;
    bytes[82] = 0; // start 0.
    bytes[83] = 0x40;
    bytes[84] = 0; // peak 1.
    bytes[85] = 0x40;
    bytes[86] = 0; // end 1.
    return bytes;
}
