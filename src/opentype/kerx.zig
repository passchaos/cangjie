const std = @import("std");
const bin = @import("../binary.zig");
const aat_lookup = @import("../aat_morx/state_table.zig");

const GlyphId = u16;

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const TupleResolver = struct {
    context: *const anyopaque,
    resolve_fn: *const fn (
        context: *const anyopaque,
        vector: []const u8,
    ) Error!i32,

    pub fn resolve(self: TupleResolver, vector: []const u8) Error!i32 {
        return self.resolve_fn(self.context, vector);
    }
};

pub const Pair = struct {
    left: u16,
    right: u16,
    value: i16,
};

pub const Subtable = struct {
    offset: usize,
    length: usize,
    coverage: u32,
    tuple_count: u32,
    format: u8,
    horizontal: bool,
    cross_stream: bool,
    variation: bool,
    backwards: bool,
    pairs: []Pair,
};

pub const Info = struct {
    version: u16,
    subtables: []Subtable,
};

const Header = struct {
    version: u16,
    table_count: usize,
};

const SubtableHeader = struct {
    offset: usize,
    length: usize,
    coverage: u32,
    tuple_count: u32,
    format: u8,
};

const PairReadMode = enum { validate_only, allocate };

pub fn validate(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    const h = try header(data, offset, length);
    var subtable_offset: usize = 8;
    for (0..h.table_count) |_| {
        var subtable = try subtableHeader(data, offset, length, subtable_offset);
        if (h.version < 4) subtable.tuple_count = 0;
        try validateSubtable(data, offset, length, subtable, glyph_count);
        subtable_offset += subtable.length;
    }
    try validateCoverageFooter(data, offset, length, h, subtable_offset, glyph_count);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!Info {
    const h = try header(data, offset, length);
    const subtables = try allocator.alloc(Subtable, h.table_count);
    var initialized: usize = 0;
    errdefer {
        freeSubtables(allocator, subtables[0..initialized]);
        allocator.free(subtables);
    }

    var subtable_offset: usize = 8;
    for (subtables) |*out| {
        var st = try subtableHeader(data, offset, length, subtable_offset);
        if (h.version < 4) st.tuple_count = 0;
        try validateSubtable(data, offset, length, st, glyph_count);
        const pairs = if (st.format == 0)
            try readFormat0Pairs(allocator, data, offset, st, glyph_count)
        else
            try allocator.alloc(Pair, 0);
        errdefer allocator.free(pairs);
        out.* = .{
            .offset = st.offset,
            .length = st.length,
            .coverage = st.coverage,
            .tuple_count = st.tuple_count,
            .format = st.format,
            .horizontal = (st.coverage & 0x80000000) == 0,
            .cross_stream = (st.coverage & 0x40000000) != 0,
            .variation = (st.coverage & 0x20000000) != 0,
            .backwards = (st.coverage & 0x10000000) != 0,
            .pairs = pairs,
        };
        initialized += 1;
        subtable_offset += st.length;
    }
    try validateCoverageFooter(data, offset, length, h, subtable_offset, glyph_count);
    return .{ .version = h.version, .subtables = subtables };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    freeSubtables(allocator, value.subtables);
    allocator.free(value.subtables);
}

/// Sum applicable same-stream `kerx` values for one adjacent glyph pair.
///
/// This is the hot-path counterpart to `info`: it walks table headers without
/// allocating metadata arrays and supports sorted format-0 pairs plus
/// format-2/6 matrices. Cross-stream values are handled by the ordered executor
/// because format-1 actions between simple subtables can add to or clear them.
pub fn pairKerning(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    left: GlyphId,
    right: GlyphId,
    vertical: bool,
    tuple_resolver: ?TupleResolver,
) Error!i32 {
    if (left >= glyph_count or right >= glyph_count) return error.BadSfnt;
    const h = try header(data, offset, length);
    var subtable_offset: usize = 8;
    var total: i64 = 0;
    for (0..h.table_count) |_| {
        var subtable = try subtableHeader(data, offset, length, subtable_offset);
        if (h.version < 4) subtable.tuple_count = 0;
        try validateSubtable(data, offset, length, subtable, glyph_count);
        const coverage = subtable.coverage;
        const subtable_vertical = (coverage & 0x80000000) != 0;
        const is_cross_stream = (coverage & 0x40000000) != 0;
        const backwards = (coverage & 0x10000000) != 0;
        if (subtable_vertical == vertical and
            !is_cross_stream and
            !backwards)
        {
            total += switch (subtable.format) {
                0 => try format0PairKerning(data, offset, subtable, left, right, tuple_resolver),
                2 => try format2PairKerning(data, offset, subtable, glyph_count, left, right, tuple_resolver),
                6 => try format6PairKerning(data, offset, subtable, glyph_count, left, right, tuple_resolver),
                else => 0,
            };
        }
        subtable_offset += subtable.length;
    }
    try validateCoverageFooter(data, offset, length, h, subtable_offset, glyph_count);
    return @intCast(std.math.clamp(total, std.math.minInt(i32), std.math.maxInt(i32)));
}

/// Resolve one simple format-0/2/6 subtable without folding table order.
///
/// The ordered AAT executor uses this for cross-stream assignments, which can
/// be interleaved with format-1 additive/reset actions. Returning `null`
/// distinguishes a non-simple or inapplicable subtable from a valid zero
/// kerning value.
pub fn simpleSubtableKerning(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    subtable_relative: usize,
    left: GlyphId,
    right: GlyphId,
    tuple_resolver: ?TupleResolver,
) Error!?i32 {
    if (left >= glyph_count or right >= glyph_count) return error.BadSfnt;
    const h = try header(data, offset, length);
    var subtable = try subtableHeader(data, offset, length, subtable_relative);
    if (h.version < 4) subtable.tuple_count = 0;
    try validateSubtable(data, offset, length, subtable, glyph_count);
    return switch (subtable.format) {
        0 => try format0PairKerning(data, offset, subtable, left, right, tuple_resolver),
        2 => try format2PairKerning(data, offset, subtable, glyph_count, left, right, tuple_resolver),
        6 => try format6PairKerning(data, offset, subtable, glyph_count, left, right, tuple_resolver),
        else => null,
    };
}

/// Report whether this axis needs the ordered output-side executor.
///
/// Ordinary same-stream format-0/2/6 fonts stay on the scalar pair fast path
/// and therefore avoid materializing glyph-parallel adjustment sidecars.
pub fn hasOutputSideAdjustments(
    data: []const u8,
    offset: usize,
    length: usize,
    vertical: bool,
    requested_kerning: bool,
) Error!bool {
    const h = try header(data, offset, length);
    var subtable_offset: usize = 8;
    var found = false;
    for (0..h.table_count) |_| {
        var subtable = try subtableHeader(data, offset, length, subtable_offset);
        if (h.version < 4) subtable.tuple_count = 0;
        const coverage = subtable.coverage;
        const axis_matches = ((coverage & 0x80000000) != 0) == vertical;
        const cross_stream = (coverage & 0x40000000) != 0;
        const backwards = (coverage & 0x10000000) != 0;
        const applies = switch (subtable.format) {
            0, 2, 6 => requested_kerning and cross_stream and !backwards,
            1 => requested_kerning or cross_stream,
            4 => true,
            else => false,
        };
        found = found or (axis_matches and applies);
        subtable_offset += subtable.length;
    }
    try validateCoverageFooter(data, offset, length, h, subtable_offset, null);
    return found;
}

fn validateCoverageFooter(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    h: Header,
    footer_relative: usize,
    glyph_count: ?usize,
) Error!void {
    if (h.version < 3) {
        if (footer_relative != table_length) return error.BadSfnt;
        return;
    }
    const offsets_bytes = std.math.mul(usize, h.table_count, 4) catch return error.BadSfnt;
    if (footer_relative > table_length or offsets_bytes > table_length - footer_relative) return error.BadSfnt;
    const footer_start = table_offset + footer_relative;
    const bitfield_bytes = if (glyph_count) |count| (count + 7) / 8 else 0;
    for (0..h.table_count) |index| {
        const coverage_offset: usize = @intCast(try bin.readU32At(data, footer_start + index * 4));
        if (coverage_offset == 0 or coverage_offset == std.math.maxInt(u32)) continue;
        if (coverage_offset < offsets_bytes or coverage_offset > table_length - footer_relative) return error.BadSfnt;
        if (glyph_count != null and bitfield_bytes > table_length - footer_relative - coverage_offset) return error.BadSfnt;
    }
}

test "format 0 pair lookup sums applicable subtables and clamps totals" {
    var bytes = [_]u8{0} ** 88;
    writeU16Test(&bytes, 0, 2);
    writeU32Test(&bytes, 4, 2);
    writeFormat0SubtableTest(&bytes, 8, 0, 1, 2, 20000);
    writeFormat0SubtableTest(&bytes, 48, 0, 1, 2, 20000);

    try validate(&bytes, 0, bytes.len, 3);
    try std.testing.expectEqual(
        @as(i32, 40000),
        try pairKerning(&bytes, 0, bytes.len, 3, 1, 2, false, null),
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        try pairKerning(&bytes, 0, bytes.len, 3, 1, 2, true, null),
    );
    try std.testing.expectEqual(
        @as(i32, 0),
        try pairKerning(&bytes, 0, bytes.len, 3, 2, 1, false, null),
    );

    // Cross-stream subtables do not contribute to same-stream pair results.
    writeU32Test(&bytes, 12, 0x40000000);
    try std.testing.expectEqual(
        @as(i32, 20000),
        try pairKerning(&bytes, 0, bytes.len, 3, 1, 2, false, null),
    );
}

test "format 2 class matrix uses AAT lookup offsets without allocation" {
    var bytes = [_]u8{0} ** 76;
    writeU16Test(&bytes, 0, 2);
    writeU32Test(&bytes, 4, 1);
    writeFormat2SubtableTest(&bytes, 8);

    try validate(&bytes, 0, bytes.len, 4);
    const expected = [_]i16{
        0,  10,  20,  0,
        8,  4,   -2,  8,
        30, -10, -20, 30,
        8,  4,   -2,  8,
    };
    for (0..4) |left| {
        for (0..4) |right| {
            try std.testing.expectEqual(
                expected[left * 4 + right],
                try pairKerning(&bytes, 0, bytes.len, 4, @intCast(left), @intCast(right), false, null),
            );
        }
    }
    try std.testing.expectEqual(@as(i32, 0), try pairKerning(&bytes, 0, bytes.len, 4, 1, 2, true, null));

    // Class lookups are bounded by maxp, and every reachable row/column index
    // must remain inside the declared matrix.
    writeU16Test(&bytes, 38, 9);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 4));
}

test "format 6 sparse matrix supports short and long scalar values" {
    var short_bytes = [_]u8{0} ** 62;
    writeU16Test(&short_bytes, 0, 2);
    writeU32Test(&short_bytes, 4, 1);
    writeFormat6SubtableTest(&short_bytes, 8, false);
    try validate(&short_bytes, 0, short_bytes.len, 2);
    try std.testing.expectEqual(@as(i32, -30), try pairKerning(&short_bytes, 0, short_bytes.len, 2, 1, 1, false, null));
    try std.testing.expectEqual(@as(i32, -30), try pairKerning(&short_bytes, 0, short_bytes.len, 2, 0, 1, false, null));

    var long_bytes = [_]u8{0} ** 76;
    writeU16Test(&long_bytes, 0, 2);
    writeU32Test(&long_bytes, 4, 1);
    writeFormat6SubtableTest(&long_bytes, 8, true);
    try validate(&long_bytes, 0, long_bytes.len, 2);
    try std.testing.expectEqual(@as(i32, -40000), try pairKerning(&long_bytes, 0, long_bytes.len, 2, 1, 1, false, null));

    writeU16Test(&short_bytes, 46, 2); // row index is outside rowCount=1.
    try std.testing.expectError(error.BadSfnt, validate(&short_bytes, 0, short_bytes.len, 2));
}

test "formats 0, 2, and 6 resolve tuple vectors" {
    const resolver = TupleResolver{
        .context = @ptrCast(&[_]u8{}),
        .resolve_fn = testTupleResolver,
    };

    var format0 = [_]u8{0} ** 58;
    writeU16Test(&format0, 0, 4);
    writeU32Test(&format0, 4, 1);
    writeFormat0SubtableTest(&format0, 8, 0x2000_0000, 1, 1, 40);
    writeU32Test(&format0, 8, 46);
    writeU32Test(&format0, 16, 2);
    writeI16Test(&format0, 48, -30);
    writeI16Test(&format0, 50, -20);
    writeU32Test(&format0, 54, std.math.maxInt(u32));
    try validate(&format0, 0, format0.len, 2);
    try std.testing.expectEqual(
        @as(i32, -40),
        try pairKerning(&format0, 0, format0.len, 2, 1, 1, false, resolver),
    );

    var format2 = [_]u8{0} ** 84;
    writeU16Test(&format2, 0, 4);
    writeU32Test(&format2, 4, 1);
    writeFormat2SubtableTest(&format2, 8);
    writeU32Test(&format2, 8, 72);
    writeU32Test(&format2, 12, 0x2000_0002);
    writeU32Test(&format2, 16, 2);
    // Every matrix member is an offset in a variable subtable, including
    // entries that this focused lookup does not query.
    for (0..9) |index| writeI16Test(&format2, 8 + 48 + index * 2, 68);
    writeI16Test(&format2, 8 + 68, -30);
    writeI16Test(&format2, 8 + 70, -20);
    writeU32Test(&format2, 80, std.math.maxInt(u32));
    try validate(&format2, 0, format2.len, 4);
    try std.testing.expectEqual(
        @as(i32, -40),
        try pairKerning(&format2, 0, format2.len, 4, 1, 1, false, resolver),
    );

    var format6 = [_]u8{0} ** 74;
    writeU16Test(&format6, 0, 4);
    writeU32Test(&format6, 4, 1);
    writeFormat6SubtableTest(&format6, 8, false);
    writeU32Test(&format6, 8, 62);
    writeU32Test(&format6, 16, 2);
    writeU32Test(&format6, 8 + 32, 54);
    writeI16Test(&format6, 8 + 52, 0);
    writeI16Test(&format6, 8 + 54, -30);
    writeI16Test(&format6, 8 + 56, -20);
    writeU32Test(&format6, 70, std.math.maxInt(u32));
    try validate(&format6, 0, format6.len, 2);
    try std.testing.expectEqual(
        @as(i32, -40),
        try pairKerning(&format6, 0, format6.len, 2, 1, 1, false, resolver),
    );

    var format6_long = [_]u8{0} ** 84;
    writeU16Test(&format6_long, 0, 4);
    writeU32Test(&format6_long, 4, 1);
    writeFormat6SubtableTest(&format6_long, 8, true);
    writeU32Test(&format6_long, 8, 72);
    writeU32Test(&format6_long, 16, 2);
    writeU32Test(&format6_long, 8 + 32, 68);
    writeU32Test(&format6_long, 8 + 64, 0);
    writeI16Test(&format6_long, 8 + 68, -30);
    writeI16Test(&format6_long, 8 + 70, -20);
    writeU32Test(&format6_long, 80, std.math.maxInt(u32));
    try validate(&format6_long, 0, format6_long.len, 2);
    try std.testing.expectEqual(
        @as(i32, -40),
        try pairKerning(
            &format6_long,
            0,
            format6_long.len,
            2,
            1,
            1,
            false,
            resolver,
        ),
    );
}

fn testTupleResolver(_: *const anyopaque, vector: []const u8) Error!i32 {
    if (vector.len != 4) return error.BadSfnt;
    return @as(i32, std.mem.readInt(i16, vector[0..2], .big)) +
        @divTrunc(@as(i32, std.mem.readInt(i16, vector[2..4], .big)), 2);
}

fn writeFormat0SubtableTest(bytes: []u8, offset: usize, coverage: u32, left: GlyphId, right: GlyphId, value: i16) void {
    writeU32Test(bytes, offset, 40);
    writeU32Test(bytes, offset + 4, coverage);
    writeU32Test(bytes, offset + 12, 1);
    writeU32Test(bytes, offset + 16, 6);
    writeU32Test(bytes, offset + 24, 0);
    writeU16Test(bytes, offset + 28, left);
    writeU16Test(bytes, offset + 30, right);
    std.mem.writeInt(i16, bytes[offset + 32 ..][0..2], value, .big);
}

fn writeFormat2SubtableTest(bytes: []u8, offset: usize) void {
    writeU32Test(bytes, offset, 68);
    writeU32Test(bytes, offset + 4, 2);
    writeU32Test(bytes, offset + 12, 3);
    writeU32Test(bytes, offset + 16, 28);
    writeU32Test(bytes, offset + 20, 38);
    writeU32Test(bytes, offset + 24, 48);

    // Dense lookup format 0 values are matrix indexes: left values are rows
    // pre-multiplied by rowWidth, while right values are columns.
    writeU16Test(bytes, offset + 28, 0);
    for ([_]u16{ 0, 6, 3, 6 }, 0..) |value, index| {
        writeU16Test(bytes, offset + 30 + index * 2, value);
    }
    writeU16Test(bytes, offset + 38, 0);
    for ([_]u16{ 0, 1, 2, 0 }, 0..) |value, index| {
        writeU16Test(bytes, offset + 40 + index * 2, value);
    }
    for ([_]i16{ 0, 10, 20, 30, -10, -20, 8, 4, -2 }, 0..) |value, index| {
        std.mem.writeInt(i16, bytes[offset + 48 + index * 2 ..][0..2], value, .big);
    }
}

fn writeFormat6SubtableTest(bytes: []u8, offset: usize, long_values: bool) void {
    const row_lookup_offset: usize = 36;
    const row_lookup_len: usize = if (long_values) 14 else 8;
    const column_lookup_offset = row_lookup_offset + row_lookup_len;
    const column_lookup_len = row_lookup_len;
    const array_offset = column_lookup_offset + column_lookup_len;
    const value_size: usize = if (long_values) 4 else 2;
    const subtable_length = array_offset + value_size;
    writeU32Test(bytes, offset, @intCast(subtable_length));
    writeU32Test(bytes, offset + 4, 6);
    writeU32Test(bytes, offset + 12, if (long_values) 1 else 0);
    writeU16Test(bytes, offset + 16, 1);
    writeU16Test(bytes, offset + 18, 1);
    writeU32Test(bytes, offset + 20, @intCast(row_lookup_offset));
    writeU32Test(bytes, offset + 24, @intCast(column_lookup_offset));
    writeU32Test(bytes, offset + 28, @intCast(array_offset));
    writeU32Test(bytes, offset + 32, 0);

    // Dense format 0 maps both glyphs to matrix index zero.
    writeU16Test(bytes, offset + row_lookup_offset, 0);
    if (long_values) {
        writeU32Test(bytes, offset + row_lookup_offset + 6, 0);
        writeU32Test(bytes, offset + row_lookup_offset + 10, 0);
    } else {
        writeU16Test(bytes, offset + row_lookup_offset + 6, 0);
    }
    writeU16Test(bytes, offset + column_lookup_offset, 0);
    if (long_values) {
        writeU32Test(bytes, offset + column_lookup_offset + 6, 0);
        writeU32Test(bytes, offset + column_lookup_offset + 10, 0);
    } else {
        writeU16Test(bytes, offset + column_lookup_offset + 6, 0);
    }
    if (long_values) {
        // Long format-8 lookup values are still 16-bit by AAT definition.
        writeI32Test(bytes, offset + array_offset, -40000);
    } else {
        std.mem.writeInt(i16, bytes[offset + array_offset ..][0..2], -30, .big);
    }
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeI32Test(bytes: []u8, offset: usize, value: i32) void {
    std.mem.writeInt(i32, bytes[offset..][0..4], value, .big);
}

fn format0PairKerning(
    data: []const u8,
    table_offset: usize,
    subtable: SubtableHeader,
    left: GlyphId,
    right: GlyphId,
    tuple_resolver: ?TupleResolver,
) Error!i32 {
    const start = table_offset + subtable.offset;
    const pair_count: usize = @intCast(try bin.readU32At(data, start + 12));
    const target = (@as(u32, left) << 16) | right;
    var lo: usize = 0;
    var hi: usize = pair_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const pair_offset = start + 28 + mid * 6;
        const pair_left = try bin.readU16At(data, pair_offset);
        const pair_right = try bin.readU16At(data, pair_offset + 2);
        const pair_key = (@as(u32, pair_left) << 16) | pair_right;
        if (target < pair_key) {
            hi = mid;
        } else if (target > pair_key) {
            lo = mid + 1;
        } else {
            const raw_bits = try bin.readU16At(data, pair_offset + 4);
            return try resolveTupleValue(
                data,
                start,
                subtable.length,
                subtable.tuple_count,
                @as(i16, @bitCast(raw_bits)),
                raw_bits,
                0,
                tuple_resolver,
            );
        }
    }
    return 0;
}

fn format2PairKerning(
    data: []const u8,
    table_offset: usize,
    subtable: SubtableHeader,
    glyph_count: usize,
    left: GlyphId,
    right: GlyphId,
    tuple_resolver: ?TupleResolver,
) Error!i32 {
    const start = table_offset + subtable.offset;
    const left_class_offset: usize = @intCast(try bin.readU32At(data, start + 16));
    const right_class_offset: usize = @intCast(try bin.readU32At(data, start + 20));
    const array_offset: usize = @intCast(try bin.readU32At(data, start + 24));
    const left_offset = try aatLookupValueWithinSubtable(data, start, subtable.length, left_class_offset, glyph_count, left);
    const right_offset = try aatLookupValueWithinSubtable(data, start, subtable.length, right_class_offset, glyph_count, right);
    const value_index = std.math.add(usize, left_offset, right_offset) catch return error.BadSfnt;
    const value_delta = std.math.mul(usize, value_index, 2) catch return error.BadSfnt;
    const value_relative = std.math.add(usize, array_offset, value_delta) catch return error.BadSfnt;
    if (value_relative > subtable.length or subtable.length - value_relative < 2) return error.BadSfnt;
    const raw_bits = try bin.readU16At(data, start + value_relative);
    return try resolveTupleValue(
        data,
        start,
        subtable.length,
        subtable.tuple_count,
        @as(i16, @bitCast(raw_bits)),
        raw_bits,
        0,
        tuple_resolver,
    );
}

fn format6PairKerning(
    data: []const u8,
    table_offset: usize,
    subtable: SubtableHeader,
    glyph_count: usize,
    left: GlyphId,
    right: GlyphId,
    tuple_resolver: ?TupleResolver,
) Error!i32 {
    const start = table_offset + subtable.offset;
    const long_values = (try bin.readU32At(data, start + 12) & 1) != 0;
    const row_lookup_offset: usize = @intCast(try bin.readU32At(data, start + 20));
    const column_lookup_offset: usize = @intCast(try bin.readU32At(data, start + 24));
    const array_offset: usize = @intCast(try bin.readU32At(data, start + 28));
    const vector_offset: usize = @intCast(try bin.readU32At(data, start + 32));
    const row_index = if (long_values)
        try aatLookupU32ValueWithinSubtable(data, start, subtable.length, row_lookup_offset, glyph_count, left)
    else
        try aatLookupValueWithinSubtable(data, start, subtable.length, row_lookup_offset, glyph_count, left);
    const column_index = if (long_values)
        try aatLookupU32ValueWithinSubtable(data, start, subtable.length, column_lookup_offset, glyph_count, right)
    else
        try aatLookupValueWithinSubtable(data, start, subtable.length, column_lookup_offset, glyph_count, right);
    const value_index = std.math.add(usize, row_index, column_index) catch return error.BadSfnt;
    const value_size: usize = if (long_values) 4 else 2;
    const value_delta = std.math.mul(usize, value_index, value_size) catch return error.BadSfnt;
    const value_relative = std.math.add(usize, array_offset, value_delta) catch return error.BadSfnt;
    if (value_relative > subtable.length or subtable.length - value_relative < value_size) return error.BadSfnt;
    const raw_bits: u32 = if (long_values)
        try bin.readU32At(data, start + value_relative)
    else
        try bin.readU16At(data, start + value_relative);
    const raw_scalar: i32 = if (long_values)
        @bitCast(raw_bits)
    else
        @as(i32, @as(i16, @bitCast(@as(u16, @intCast(raw_bits)))));
    return try resolveTupleValue(
        data,
        start,
        subtable.length,
        subtable.tuple_count,
        raw_scalar,
        raw_bits,
        vector_offset,
        tuple_resolver,
    );
}

fn resolveTupleValue(
    data: []const u8,
    subtable_start: usize,
    subtable_length: usize,
    tuple_count: u32,
    raw_scalar: i32,
    raw_vector_offset: u32,
    vector_base: usize,
    resolver: ?TupleResolver,
) Error!i32 {
    if (tuple_count == 0) return raw_scalar;
    const vector = try tupleVector(
        data,
        subtable_start,
        subtable_length,
        tuple_count,
        raw_vector_offset,
        vector_base,
    );
    // HarfBuzz's current implementation and the AAT default-coordinate rule
    // both select the first vector member when no variation resolver exists.
    return if (resolver) |tuple_resolver|
        try tuple_resolver.resolve(vector)
    else
        try bin.readI16At(vector, 0);
}

fn tupleVector(
    data: []const u8,
    subtable_start: usize,
    subtable_length: usize,
    tuple_count: u32,
    raw_vector_offset: u32,
    vector_base: usize,
) Error![]const u8 {
    if (tuple_count == 0 or tuple_count > std.math.maxInt(usize) / 2) return error.BadSfnt;
    const resolved_base = if (vector_base == 0) @as(usize, raw_vector_offset) else vector_base;
    const vector_offset = if (vector_base == 0)
        resolved_base
    else
        std.math.add(usize, resolved_base, @as(usize, raw_vector_offset)) catch return error.BadSfnt;
    const vector_bytes = std.math.mul(usize, @as(usize, @intCast(tuple_count)), 2) catch return error.BadSfnt;
    if (vector_offset > subtable_length or vector_bytes > subtable_length - vector_offset) return error.BadSfnt;
    return data[subtable_start + vector_offset ..][0..vector_bytes];
}

fn aatLookupValueWithinSubtable(data: []const u8, subtable_start: usize, subtable_length: usize, lookup_offset: usize, glyph_count: usize, glyph: GlyphId) Error!u16 {
    if (lookup_offset < 28 or lookup_offset > subtable_length or subtable_length - lookup_offset < 2) return error.BadSfnt;
    return (try aat_lookup.lookupGlyphValueBounded(
        data,
        subtable_start + lookup_offset,
        subtable_length - lookup_offset,
        glyph,
        glyph_count,
    )) orelse 0;
}

fn aatLookupU32ValueWithinSubtable(data: []const u8, subtable_start: usize, subtable_length: usize, lookup_offset: usize, glyph_count: usize, glyph: GlyphId) Error!u32 {
    if (lookup_offset < 36 or lookup_offset > subtable_length or subtable_length - lookup_offset < 2) return error.BadSfnt;
    return (try aat_lookup.lookupGlyphValueU32Bounded(
        data,
        subtable_start + lookup_offset,
        subtable_length - lookup_offset,
        glyph,
        glyph_count,
    )) orelse 0;
}

fn freeSubtables(allocator: std.mem.Allocator, subtables: []Subtable) void {
    for (subtables) |subtable| allocator.free(subtable.pairs);
}

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 8) return error.BadSfnt;
    const version = try bin.readU16At(data, offset);
    if (version < 2 or version > 4) return error.BadSfnt;
    if (try bin.readU16At(data, offset + 2) != 0) return error.BadSfnt;
    const table_count: usize = @intCast(try bin.readU32At(data, offset + 4));
    return .{ .version = version, .table_count = table_count };
}

fn subtableHeader(data: []const u8, table_offset: usize, table_length: usize, offset: usize) Error!SubtableHeader {
    if (offset > table_length or table_length - offset < 12) return error.BadSfnt;
    const start = table_offset + offset;
    const length: usize = @intCast(try bin.readU32At(data, start));
    const coverage = try bin.readU32At(data, start + 4);
    if (length < 12 or length > table_length - offset) return error.BadSfnt;
    if ((coverage & 0x0fffff00) != 0) return error.BadSfnt;
    return .{
        .offset = offset,
        .length = length,
        .coverage = coverage,
        .tuple_count = try bin.readU32At(data, start + 8),
        .format = @intCast(coverage & 0xff),
    };
}

fn validateSubtable(data: []const u8, table_offset: usize, table_length: usize, subtable: SubtableHeader, glyph_count: usize) Error!void {
    _ = table_length;
    switch (subtable.format) {
        0 => _ = try format0Pairs(data, table_offset, subtable, glyph_count, null, .validate_only),
        1 => try validateFormat1(data, table_offset, subtable, glyph_count),
        2 => try validateFormat2(data, table_offset, subtable, glyph_count),
        6 => try validateFormat6(data, table_offset, subtable, glyph_count),
        4 => try validateFormat4(data, table_offset, subtable, glyph_count),
        else => return error.BadSfnt,
    }
}

fn validateFormat1(data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize) Error!void {
    if (subtable.length < 32) return error.BadSfnt;
    const start = table_offset + subtable.offset;
    const machine_start = start + 12;
    const machine_length = subtable.length - 12;
    const class_count: usize = @intCast(try bin.readU32At(data, start + 12));
    const class_table_offset: usize = @intCast(try bin.readU32At(data, start + 16));
    const state_array_offset: usize = @intCast(try bin.readU32At(data, start + 20));
    const entry_table_offset: usize = @intCast(try bin.readU32At(data, start + 24));
    const action_offset: usize = @intCast(try bin.readU32At(data, start + 28));
    if (class_count < 4 or
        class_table_offset < 20 or
        state_array_offset < 20 or
        entry_table_offset < 20 or
        action_offset < 16 or
        class_table_offset >= machine_length or
        state_array_offset >= machine_length or
        entry_table_offset >= machine_length or
        action_offset >= machine_length)
    {
        return error.BadSfnt;
    }
    try aat_lookup.validateLookupU16(data, machine_start + class_table_offset, machine_length - class_table_offset, glyph_count);
    // The complete state/action graph is preflighted by the dedicated format-1
    // executor before it mutates any output-side adjustment.
}

fn validateFormat4(data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize) Error!void {
    if (subtable.length < 32) return error.BadSfnt;
    const start = table_offset + subtable.offset;
    const machine_start = start + 12;
    const machine_length = subtable.length - 12;
    const class_count: usize = @intCast(try bin.readU32At(data, machine_start));
    const class_table_offset: usize = @intCast(try bin.readU32At(data, machine_start + 4));
    const state_array_offset: usize = @intCast(try bin.readU32At(data, machine_start + 8));
    const entry_table_offset: usize = @intCast(try bin.readU32At(data, machine_start + 12));
    const flags = try bin.readU32At(data, machine_start + 16);
    const action_type = flags >> 30;
    const action_offset: usize = @intCast(flags & 0x00ff_ffff);
    if ((flags & 0x3f00_0000) != 0 or
        action_type > 2 or
        class_count < 4 or
        class_table_offset < 20 or
        state_array_offset < 20 or
        entry_table_offset < 20 or
        class_table_offset >= machine_length or
        state_array_offset >= machine_length or
        entry_table_offset >= machine_length or
        action_offset > machine_length)
    {
        return error.BadSfnt;
    }
    try aat_lookup.validateLookupU16(data, machine_start + class_table_offset, machine_length - class_table_offset, glyph_count);
}

fn validateFormat2(data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize) Error!void {
    if (subtable.length < 28) return error.BadSfnt;
    const start = table_offset + subtable.offset;
    const row_width: usize = @intCast(try bin.readU32At(data, start + 12));
    const left_class_offset: usize = @intCast(try bin.readU32At(data, start + 16));
    const right_class_offset: usize = @intCast(try bin.readU32At(data, start + 20));
    const array_offset: usize = @intCast(try bin.readU32At(data, start + 24));
    if (row_width == 0) return error.BadSfnt;
    if (array_offset < 28 or array_offset > subtable.length or subtable.length - array_offset < 2) return error.BadSfnt;
    if (left_class_offset == right_class_offset or
        left_class_offset == array_offset or
        right_class_offset == array_offset)
    {
        return error.BadSfnt;
    }

    try aat_lookup.validateLookupU16(data, start + left_class_offset, subtable.length - left_class_offset, glyph_count);
    try aat_lookup.validateLookupU16(data, start + right_class_offset, subtable.length - right_class_offset, glyph_count);
    var max_left_index: usize = 0;
    var max_right_index: usize = 0;
    var left_stride_gcd: usize = 0;
    for (0..glyph_count) |glyph_index| {
        const glyph: GlyphId = @intCast(glyph_index);
        const left_offset = try aatLookupValueWithinSubtable(data, start, subtable.length, left_class_offset, glyph_count, glyph);
        const right_offset = try aatLookupValueWithinSubtable(data, start, subtable.length, right_class_offset, glyph_count, glyph);
        if (left_offset != 0) left_stride_gcd = std.math.gcd(left_stride_gcd, left_offset);
        max_left_index = @max(max_left_index, left_offset);
        max_right_index = @max(max_right_index, right_offset);
    }
    // rowWidth is expressed in bytes, while the lookup values are indexes into
    // the i16 matrix. Some producers store rowWidth in the logical index space
    // and others use bytes; accepting either relation mirrors the reference
    // engines without rejecting a bounded matrix solely for that convention.
    if (left_stride_gcd != 0 and left_stride_gcd != row_width) {
        const byte_stride = std.math.mul(usize, left_stride_gcd, 2) catch return error.BadSfnt;
        if (byte_stride != row_width) return error.BadSfnt;
    }
    const max_index = std.math.add(usize, max_left_index, max_right_index) catch return error.BadSfnt;
    const max_delta = std.math.mul(usize, max_index, 2) catch return error.BadSfnt;
    const max_relative = std.math.add(usize, array_offset, max_delta) catch return error.BadSfnt;
    if (max_relative > subtable.length or subtable.length - max_relative < 2) return error.BadSfnt;
    if (subtable.tuple_count != 0) {
        for (0..max_index + 1) |index| {
            const raw_offset = try bin.readU16At(data, start + array_offset + index * 2);
            _ = try tupleVector(
                data,
                start,
                subtable.length,
                subtable.tuple_count,
                raw_offset,
                0,
            );
        }
    }
}

fn validateFormat6(data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize) Error!void {
    if (subtable.length < 36) return error.BadSfnt;
    const start = table_offset + subtable.offset;
    const flags = try bin.readU32At(data, start + 12);
    if ((flags & ~@as(u32, 1)) != 0) return error.BadSfnt;
    const long_values = (flags & 1) != 0;
    const row_count: usize = @intCast(try bin.readU16At(data, start + 16));
    const column_count: usize = @intCast(try bin.readU16At(data, start + 18));
    if (row_count == 0 or column_count == 0) return error.BadSfnt;
    const row_lookup_offset: usize = @intCast(try bin.readU32At(data, start + 20));
    const column_lookup_offset: usize = @intCast(try bin.readU32At(data, start + 24));
    const array_offset: usize = @intCast(try bin.readU32At(data, start + 28));
    const vector_offset: usize = @intCast(try bin.readU32At(data, start + 32));
    if (array_offset < 36 or array_offset > subtable.length) return error.BadSfnt;
    if (subtable.tuple_count == 0) {
        // The vector field is structurally present but ignored for scalar
        // matrices. Keep zero as the canonical non-variable encoding.
        if (vector_offset != 0) return error.BadSfnt;
    } else {
        if (vector_offset < 36 or vector_offset > subtable.length or subtable.length - vector_offset < 2) return error.BadSfnt;
    }
    if (row_lookup_offset == column_lookup_offset or
        row_lookup_offset == array_offset or
        column_lookup_offset == array_offset)
    {
        return error.BadSfnt;
    }
    if (long_values) {
        try aat_lookup.validateLookupU32(data, start + row_lookup_offset, subtable.length - row_lookup_offset, glyph_count);
        try aat_lookup.validateLookupU32(data, start + column_lookup_offset, subtable.length - column_lookup_offset, glyph_count);
    } else {
        try aat_lookup.validateLookupU16(data, start + row_lookup_offset, subtable.length - row_lookup_offset, glyph_count);
        try aat_lookup.validateLookupU16(data, start + column_lookup_offset, subtable.length - column_lookup_offset, glyph_count);
    }

    var max_row_index: usize = 0;
    var max_column_index: usize = 0;
    for (0..glyph_count) |glyph_index| {
        const glyph: GlyphId = @intCast(glyph_index);
        const row_index = if (long_values)
            try aatLookupU32ValueWithinSubtable(data, start, subtable.length, row_lookup_offset, glyph_count, glyph)
        else
            try aatLookupValueWithinSubtable(data, start, subtable.length, row_lookup_offset, glyph_count, glyph);
        const column_index = if (long_values)
            try aatLookupU32ValueWithinSubtable(data, start, subtable.length, column_lookup_offset, glyph_count, glyph)
        else
            try aatLookupValueWithinSubtable(data, start, subtable.length, column_lookup_offset, glyph_count, glyph);
        if (row_index % column_count != 0 or row_index / column_count >= row_count) return error.BadSfnt;
        if (column_index >= column_count) return error.BadSfnt;
        max_row_index = @max(max_row_index, row_index);
        max_column_index = @max(max_column_index, column_index);
    }
    const max_index = std.math.add(usize, max_row_index, max_column_index) catch return error.BadSfnt;
    const value_size: usize = if (long_values) 4 else 2;
    const max_delta = std.math.mul(usize, max_index, value_size) catch return error.BadSfnt;
    const max_relative = std.math.add(usize, array_offset, max_delta) catch return error.BadSfnt;
    if (max_relative > subtable.length or subtable.length - max_relative < value_size) return error.BadSfnt;
    if (subtable.tuple_count != 0) {
        for (0..max_index + 1) |index| {
            const raw_offset: u32 = if (long_values)
                try bin.readU32At(data, start + array_offset + index * value_size)
            else
                try bin.readU16At(data, start + array_offset + index * value_size);
            _ = try tupleVector(
                data,
                start,
                subtable.length,
                subtable.tuple_count,
                raw_offset,
                vector_offset,
            );
        }
    }
}

fn readFormat0Pairs(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize) Error![]Pair {
    const pair_count = try format0PairCount(data, table_offset, subtable);
    const pairs = try allocator.alloc(Pair, pair_count);
    errdefer allocator.free(pairs);
    _ = try format0Pairs(data, table_offset, subtable, glyph_count, pairs, .allocate);
    return pairs;
}

fn format0PairCount(data: []const u8, table_offset: usize, subtable: SubtableHeader) Error!usize {
    if (subtable.length < 28) return error.BadSfnt;
    return @intCast(try bin.readU32At(data, table_offset + subtable.offset + 12));
}

fn format0Pairs(data: []const u8, table_offset: usize, subtable: SubtableHeader, glyph_count: usize, out: ?[]Pair, mode: PairReadMode) Error!usize {
    if (subtable.length < 28) return error.BadSfnt;
    const start = table_offset + subtable.offset;
    const pair_count: usize = @intCast(try bin.readU32At(data, start + 12));
    try validateFormat0Search(data, start + 16, pair_count);
    if (pair_count > (subtable.length - 28) / 6) return error.BadSfnt;
    if (mode == .allocate and (out == null or out.?.len != pair_count)) return error.BadSfnt;

    var previous: ?u32 = null;
    for (0..pair_count) |index| {
        const pair_offset = start + 28 + index * 6;
        const left = try bin.readU16At(data, pair_offset);
        const right = try bin.readU16At(data, pair_offset + 2);
        const raw_value = try bin.readU16At(data, pair_offset + 4);
        if (left >= glyph_count or right >= glyph_count) return error.BadSfnt;
        const pair_key = (@as(u32, left) << 16) | right;
        if (previous) |last| if (pair_key <= last) return error.BadSfnt;
        previous = pair_key;
        if (subtable.tuple_count != 0) {
            _ = try tupleVector(
                data,
                start,
                subtable.length,
                subtable.tuple_count,
                raw_value,
                0,
            );
        }
        if (out) |pairs| pairs[index] = .{
            .left = left,
            .right = right,
            // Preserve the on-disk bits for metadata callers. In a variable
            // subtable this field is an unsigned byte offset, not a scalar.
            .value = @bitCast(raw_value),
        };
    }
    return pair_count;
}

fn validateFormat0Search(data: []const u8, offset: usize, pair_count: usize) Error!void {
    const search_range = try bin.readU32At(data, offset);
    const entry_selector = try bin.readU32At(data, offset + 4);
    const range_shift = try bin.readU32At(data, offset + 8);
    const power = floorPowerOfTwo(pair_count);
    var selector: u32 = 0;
    var tmp = power;
    while (tmp > 1) : (tmp >>= 1) selector += 1;
    const expected_search_range = power * 6;
    const expected_range_shift = pair_count * 6 - expected_search_range;
    if (expected_search_range > std.math.maxInt(u32) or expected_range_shift > std.math.maxInt(u32)) return error.BadSfnt;
    if (search_range != expected_search_range or entry_selector != selector or range_shift != expected_range_shift) return error.BadSfnt;
}

fn floorPowerOfTwo(value: usize) usize {
    if (value == 0) return 0;
    var power: usize = 1;
    while (power <= value / 2) power *= 2;
    return power;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

test "kerx format 0 exposes sorted kerning pairs" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 2);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 40);
    writeU32(&bytes, 12, 0);
    writeU32(&bytes, 16, 0);
    writeU32(&bytes, 20, 2);
    writeU32(&bytes, 24, 12);
    writeU32(&bytes, 28, 1);
    writeU32(&bytes, 32, 0);
    writeU16(&bytes, 36, 0);
    writeU16(&bytes, 38, 1);
    writeI16(&bytes, 40, -30);
    writeU16(&bytes, 42, 1);
    writeU16(&bytes, 44, 2);
    writeI16(&bytes, 46, 20);

    try validate(&bytes, 0, bytes.len, 3);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 3);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u16, 2), parsed.version);
    try std.testing.expectEqual(@as(usize, 1), parsed.subtables.len);
    try std.testing.expect(parsed.subtables[0].horizontal);
    try std.testing.expectEqual(@as(u8, 0), parsed.subtables[0].format);
    try std.testing.expectEqual(@as(usize, 2), parsed.subtables[0].pairs.len);
    try std.testing.expectEqual(Pair{ .left = 0, .right = 1, .value = -30 }, parsed.subtables[0].pairs[0]);
    try std.testing.expectEqual(Pair{ .left = 1, .right = 2, .value = 20 }, parsed.subtables[0].pairs[1]);
}

test "kerx format 0 rejects unsorted pairs" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 2);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 40);
    writeU32(&bytes, 20, 2);
    writeU32(&bytes, 24, 12);
    writeU32(&bytes, 28, 1);
    writeU32(&bytes, 32, 0);
    writeU16(&bytes, 36, 1);
    writeU16(&bytes, 38, 2);
    writeI16(&bytes, 40, 20);
    writeU16(&bytes, 42, 0);
    writeU16(&bytes, 44, 1);
    writeI16(&bytes, 46, -30);

    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 3));
}
