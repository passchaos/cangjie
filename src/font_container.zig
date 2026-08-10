const std = @import("std");
const builtin = @import("builtin");
const Font = @import("font.zig").Font;

pub const Error = error{
    InvalidContainer,
    OutputTooLarge,
    UnsupportedContainer,
    Woff2RuntimeUnavailable,
};

pub const Format = enum {
    sfnt,
    woff1,
    woff2,
};

/// Conservative default shared with `FontDatabase` convenience loaders.
/// Explicit APIs can raise this for unusually large, trusted collections.
pub const default_max_decoded_size = 64 * 1024 * 1024;

/// Owns decoded SFNT bytes together with a `Font` that borrows those bytes.
///
/// `Font.parse` intentionally remains a zero-copy API for callers that already
/// own SFNT data. Container loading needs a separate owner because WOFF input
/// is reconstructed into a new SFNT allocation whose address must remain valid
/// for the complete lifetime of `font`.
pub const LoadedFont = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    font: Font,

    pub fn load(
        allocator: std.mem.Allocator,
        data: []const u8,
        max_decoded_size: usize,
    ) !LoadedFont {
        return loadFace(allocator, data, 0, max_decoded_size);
    }

    pub fn loadFace(
        allocator: std.mem.Allocator,
        data: []const u8,
        face_index: usize,
        max_decoded_size: usize,
    ) !LoadedFont {
        const bytes = try decodeFontContainerAlloc(allocator, data, max_decoded_size);
        errdefer allocator.free(bytes);
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .font = try Font.parseFace(allocator, bytes, face_index),
        };
    }

    pub fn deinit(self: *LoadedFont) void {
        self.font.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub fn detectFormat(data: []const u8) Error!Format {
    if (data.len < 4) return error.InvalidContainer;
    return switch (readU32Be(data, 0)) {
        0x00010000, // TrueType outlines.
        0x74727565, // "true", accepted by the SFNT parser.
        0x4f54544f, // "OTTO", CFF/CFF2 outlines.
        0x74746366, // "ttcf", TrueType/OpenType collection.
        => .sfnt,
        0x774f4646 => .woff1, // "wOFF"
        0x774f4632 => .woff2, // "wOF2"
        else => error.UnsupportedContainer,
    };
}

fn isSupportedSfntFlavor(flavor: u32) bool {
    return switch (flavor) {
        0x00010000, // TrueType outlines.
        0x74727565, // "true".
        0x4f54544f, // "OTTO", CFF/CFF2 outlines.
        => true,
        else => false,
    };
}

/// Return owned SFNT/TTC bytes for a supported modern font container.
///
/// Plain SFNT input is copied so this function has one ownership contract for
/// all formats. `max_decoded_size` applies to the returned bytes, not merely to
/// the compressed input, which prevents WOFF decompression bombs.
pub fn decodeFontContainerAlloc(
    allocator: std.mem.Allocator,
    data: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    return switch (try detectFormat(data)) {
        .sfnt => {
            if (data.len > max_decoded_size) return error.OutputTooLarge;
            return try allocator.dupe(u8, data);
        },
        .woff1 => try decodeWoff1ToSfntAlloc(allocator, data, max_decoded_size),
        .woff2 => try decodeWoff2ToSfntAlloc(allocator, data, max_decoded_size),
    };
}

const WoffTableEntry = struct {
    tag: [4]u8,
    offset: u32,
    compressed_len: u32,
    original_len: u32,
    checksum: u32,
};

fn decodeWoff1ToSfntAlloc(
    allocator: std.mem.Allocator,
    woff: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    if (woff.len < 44 or readU32Be(woff, 0) != 0x774f4646) {
        return error.InvalidContainer;
    }
    const flavor = readU32Be(woff, 4);
    // WOFF1 wraps one SFNT face, not a collection. Restrict reconstruction to
    // the same modern outline flavors accepted by Font.parse so this public
    // decoder cannot manufacture an allegedly supported but unusable SFNT.
    if (!isSupportedSfntFlavor(flavor)) return error.InvalidContainer;
    const advertised_len: usize = readU32Be(woff, 8);
    if (advertised_len != woff.len) return error.InvalidContainer;
    const table_count = readU16Be(woff, 12);
    if (table_count == 0 or readU16Be(woff, 14) != 0) {
        return error.InvalidContainer;
    }
    const advertised_sfnt_size: usize = readU32Be(woff, 16);
    if (advertised_sfnt_size > max_decoded_size) return error.OutputTooLarge;

    const directory_len = std.math.mul(usize, @as(usize, table_count), 20) catch
        return error.InvalidContainer;
    if (directory_len > woff.len - 44) return error.InvalidContainer;
    const minimum_data_offset = 44 + directory_len;
    const metadata_range = try validateMetadataRange(
        woff.len,
        minimum_data_offset,
        readU32Be(woff, 24),
        readU32Be(woff, 28),
        readU32Be(woff, 32),
    );
    const private_range = try validateOptionalBlockRange(
        woff.len,
        minimum_data_offset,
        readU32Be(woff, 36),
        readU32Be(woff, 40),
    );

    const entries = try allocator.alloc(WoffTableEntry, table_count);
    defer allocator.free(entries);
    const payload_order = try allocator.alloc(usize, table_count);
    defer allocator.free(payload_order);
    for (entries, 0..) |*entry, index| {
        const base = 44 + index * 20;
        entry.* = .{
            .tag = woff[base..][0..4].*,
            .offset = readU32Be(woff, base + 4),
            .compressed_len = readU32Be(woff, base + 8),
            .original_len = readU32Be(woff, base + 12),
            .checksum = readU32Be(woff, base + 16),
        };
        if (entry.compressed_len > entry.original_len or (entry.offset & 3) != 0) {
            return error.InvalidContainer;
        }
        try validateTableTag(entry.tag);
        try validateTableRange(woff.len, minimum_data_offset, entry.*);
        if (index != 0 and std.mem.order(u8, &entries[index - 1].tag, &entry.tag) != .lt) {
            return error.InvalidContainer;
        }
        payload_order[index] = index;
    }
    std.sort.heap(
        usize,
        payload_order,
        entries,
        woffEntryOffsetLessThan,
    );
    try validatePayloadLayout(
        entries,
        payload_order,
        minimum_data_offset,
        woff.len,
        metadata_range,
        private_range,
    );

    const sfnt_len = try sfntSize(entries);
    if (sfnt_len != advertised_sfnt_size or sfnt_len > max_decoded_size) {
        return if (sfnt_len > max_decoded_size)
            error.OutputTooLarge
        else
            error.InvalidContainer;
    }
    const out = try allocator.alloc(u8, sfnt_len);
    errdefer allocator.free(out);
    @memset(out, 0);

    writeU32Be(out, 0, flavor);
    writeU16Be(out, 4, table_count);
    const search = try sfntSearchParameters(table_count);
    writeU16Be(out, 6, search.search_range);
    writeU16Be(out, 8, search.entry_selector);
    writeU16Be(out, 10, search.range_shift);

    var table_offset = 12 + @as(usize, table_count) * 16;
    // A WOFF directory is tag-sorted, but payloads retain the source SFNT's
    // physical table order. Reconstruct in payload order and write each offset
    // back to its tag-sorted directory record. Reordering by tag would leave
    // every table checksum valid while silently invalidating the head table's
    // whole-font checkSumAdjustment.
    for (payload_order) |entry_index| {
        const entry = entries[entry_index];
        const record = 12 + entry_index * 16;
        out[record..][0..4].* = entry.tag;
        writeU32Be(out, record + 4, entry.checksum);
        writeU32Be(out, record + 8, @intCast(table_offset));
        writeU32Be(out, record + 12, entry.original_len);

        const compressed_start: usize = entry.offset;
        const compressed_len: usize = entry.compressed_len;
        const original_len: usize = entry.original_len;
        if (original_len > out.len - table_offset) return error.InvalidContainer;
        const table = out[table_offset..][0..original_len];
        if (entry.compressed_len == entry.original_len) {
            @memcpy(table, woff[compressed_start..][0..compressed_len]);
        } else {
            try inflateWoffTable(table, woff[compressed_start..][0..compressed_len]);
        }
        table_offset += try align4(original_len);
    }
    return out;
}

const Woff2FinalSizeFn = *const fn ([*]const u8, usize) callconv(.c) usize;
const Woff2ConvertFn = *const fn ([*]u8, usize, [*]const u8, usize) callconv(.c) bool;

const Woff2Runtime = struct {
    library: std.DynLib,
    final_size: Woff2FinalSizeFn,
    convert: Woff2ConvertFn,

    fn deinit(self: *Woff2Runtime) void {
        self.library.close();
        self.* = undefined;
    }
};

fn decodeWoff2ToSfntAlloc(
    allocator: std.mem.Allocator,
    woff2: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    var runtime = try openWoff2Runtime();
    defer runtime.deinit();

    const sfnt_len = runtime.final_size(woff2.ptr, woff2.len);
    if (sfnt_len == 0) return error.InvalidContainer;
    if (sfnt_len > max_decoded_size) return error.OutputTooLarge;
    const out = try allocator.alloc(u8, sfnt_len);
    errdefer allocator.free(out);
    if (!runtime.convert(out.ptr, out.len, woff2.ptr, woff2.len)) {
        return error.InvalidContainer;
    }
    return out;
}

fn openWoff2Runtime() !Woff2Runtime {
    if (!supportsWoff2Runtime()) return error.Woff2RuntimeUnavailable;
    const names = [_][:0]const u8{
        "libwoff2dec.so.1.0.2",
        "libwoff2dec.so",
        "libwoff2dec.dylib",
        "/lib/x86_64-linux-gnu/libwoff2dec.so.1.0.2",
        "/usr/lib/x86_64-linux-gnu/libwoff2dec.so.1.0.2",
        "/usr/local/lib/libwoff2dec.so",
        "/opt/homebrew/lib/libwoff2dec.dylib",
        "/usr/local/lib/libwoff2dec.dylib",
    };
    for (names) |name| {
        var library = std.DynLib.openZ(name.ptr) catch continue;
        const final_size = library.lookup(
            Woff2FinalSizeFn,
            "_ZN5woff221ComputeWOFF2FinalSizeEPKhm",
        ) orelse {
            library.close();
            continue;
        };
        const convert = library.lookup(
            Woff2ConvertFn,
            "_ZN5woff217ConvertWOFF2ToTTFEPhmPKhm",
        ) orelse {
            library.close();
            continue;
        };
        return .{
            .library = library,
            .final_size = final_size,
            .convert = convert,
        };
    }
    return error.Woff2RuntimeUnavailable;
}

fn supportsWoff2Runtime() bool {
    return switch (builtin.os.tag) {
        .linux,
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        .freebsd,
        .netbsd,
        .openbsd,
        .dragonfly,
        .illumos,
        => true,
        else => false,
    };
}

fn inflateWoffTable(out: []u8, compressed: []const u8) Error!void {
    var input: std.Io.Reader = .fixed(compressed);
    var output: std.Io.Writer = .fixed(out);
    var decompressor: std.compress.flate.Decompress = .init(&input, .zlib, &.{});
    const written = decompressor.reader.streamRemaining(&output) catch
        return error.InvalidContainer;
    if (written != out.len or output.end != out.len or input.seek != input.end) {
        return error.InvalidContainer;
    }
}

const WoffByteRange = struct {
    start: usize,
    end: usize,
};

fn validateMetadataRange(
    file_len: usize,
    minimum_offset: usize,
    offset_u32: u32,
    len_u32: u32,
    original_len: u32,
) Error!?WoffByteRange {
    if (offset_u32 == 0 and len_u32 == 0 and original_len == 0) return null;
    if (offset_u32 == 0 or len_u32 == 0 or original_len == 0) {
        return error.InvalidContainer;
    }
    return try validateOptionalBlockRange(
        file_len,
        minimum_offset,
        offset_u32,
        len_u32,
    );
}

fn validateOptionalBlockRange(
    file_len: usize,
    minimum_offset: usize,
    offset_u32: u32,
    len_u32: u32,
) Error!?WoffByteRange {
    if (offset_u32 == 0 and len_u32 == 0) return null;
    if (offset_u32 == 0 or len_u32 == 0 or (offset_u32 & 3) != 0) {
        return error.InvalidContainer;
    }
    const offset: usize = offset_u32;
    const len: usize = len_u32;
    if (offset < minimum_offset or offset > file_len or len > file_len - offset) {
        return error.InvalidContainer;
    }
    // Metadata/private data starts on a four-byte boundary, but trailing
    // padding is not part of its advertised length and may be omitted at EOF.
    // Use the physical payload range for overlap checks; a following block's
    // own aligned offset validates any inter-block padding.
    return .{ .start = offset, .end = offset + len };
}

fn validateTableRange(
    file_len: usize,
    minimum_data_offset: usize,
    entry: WoffTableEntry,
) Error!void {
    const offset: usize = entry.offset;
    const len: usize = entry.compressed_len;
    if (offset < minimum_data_offset or offset > file_len or len > file_len - offset) {
        return error.InvalidContainer;
    }
    if ((try align4(len)) > file_len - offset) return error.InvalidContainer;
}

fn validatePayloadLayout(
    entries: []const WoffTableEntry,
    payload_order: []const usize,
    first_payload_offset: usize,
    file_len: usize,
    metadata: ?WoffByteRange,
    private: ?WoffByteRange,
) !void {
    if (payload_order.len != entries.len) return error.InvalidContainer;
    var expected = first_payload_offset;
    for (payload_order) |entry_index| {
        if (entry_index >= entries.len) return error.InvalidContainer;
        const entry = entries[entry_index];
        const start: usize = entry.offset;
        if (start != expected) return error.InvalidContainer;
        expected = start + try align4(entry.compressed_len);
    }
    if (metadata) |range| {
        if (range.start != expected) return error.InvalidContainer;
        expected = range.end;
    }
    if (private) |range| {
        expected = try align4(expected);
        if (range.start != expected) return error.InvalidContainer;
        expected = range.end;
    }
    if (expected != file_len) return error.InvalidContainer;
}

fn woffEntryOffsetLessThan(
    entries: []const WoffTableEntry,
    lhs_index: usize,
    rhs_index: usize,
) bool {
    return entries[lhs_index].offset < entries[rhs_index].offset;
}

fn validateTableTag(tag: [4]u8) Error!void {
    for (tag) |byte| {
        if (byte < 0x20 or byte > 0x7e) return error.InvalidContainer;
    }
}

fn sfntSize(entries: []const WoffTableEntry) Error!usize {
    var total = std.math.add(
        usize,
        12,
        std.math.mul(usize, entries.len, 16) catch return error.InvalidContainer,
    ) catch return error.InvalidContainer;
    for (entries) |entry| {
        total = std.math.add(usize, total, try align4(entry.original_len)) catch
            return error.InvalidContainer;
    }
    return total;
}

const SfntSearchParameters = struct {
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};

fn sfntSearchParameters(table_count: u16) Error!SfntSearchParameters {
    if (table_count == 0) return error.InvalidContainer;
    var power: usize = 1;
    var selector: u16 = 0;
    while (power * 2 <= table_count) {
        power *= 2;
        selector += 1;
    }
    const search_range = power * 16;
    const directory_bytes = @as(usize, table_count) * 16;
    if (search_range > std.math.maxInt(u16) or directory_bytes > std.math.maxInt(u16)) {
        return error.InvalidContainer;
    }
    return .{
        .search_range = @intCast(search_range),
        .entry_selector = selector,
        .range_shift = @intCast(directory_bytes - search_range),
    };
}

fn align4(value: anytype) Error!usize {
    const widened: usize = @intCast(value);
    const sum = std.math.add(usize, widened, 3) catch
        return error.InvalidContainer;
    return sum & ~@as(usize, 3);
}

fn readU16Be(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .big);
}

fn readU32Be(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .big);
}

fn writeU16Be(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32Be(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

const TestSfntTable = struct {
    tag: [4]u8,
    checksum: u32,
    length: u32,
    data: []const u8,
};

fn buildWoffForTest(
    allocator: std.mem.Allocator,
    sfnt: []const u8,
    compress_tables: bool,
) ![]u8 {
    if (sfnt.len < 12) return error.TestUnexpectedResult;
    const flavor = readU32Be(sfnt, 0);
    const table_count = readU16Be(sfnt, 4);
    const directory_len = @as(usize, table_count) * 16;
    if (directory_len > sfnt.len - 12) return error.TestUnexpectedResult;

    const tables = try allocator.alloc(TestSfntTable, table_count);
    defer allocator.free(tables);
    for (tables, 0..) |*table, index| {
        const record = 12 + index * 16;
        const offset: usize = readU32Be(sfnt, record + 8);
        const len: usize = readU32Be(sfnt, record + 12);
        if (offset > sfnt.len or len > sfnt.len - offset) {
            return error.TestUnexpectedResult;
        }
        table.* = .{
            .tag = sfnt[record..][0..4].*,
            .checksum = readU32Be(sfnt, record + 4),
            .length = @intCast(len),
            .data = sfnt[offset..][0..len],
        };
    }

    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();
    try out.writer.splatByteAll(0, 44 + @as(usize, table_count) * 20);
    var compressed_any = false;
    for (tables, 0..) |table, index| {
        var payload = table.data;
        var compressed_owned: ?[]u8 = null;
        if (compress_tables) {
            const compressed = try zlibCompressForTest(allocator, table.data);
            if (compressed.len < table.data.len) {
                compressed_owned = compressed;
                payload = compressed;
                compressed_any = true;
            } else {
                allocator.free(compressed);
            }
        }
        defer if (compressed_owned) |owned| allocator.free(owned);

        while ((out.writer.end & 3) != 0) try out.writer.writeByte(0);
        const payload_offset = out.writer.end;
        try out.writer.writeAll(payload);
        while ((out.writer.end & 3) != 0) try out.writer.writeByte(0);

        const entry = 44 + index * 20;
        out.writer.buffer[entry..][0..4].* = table.tag;
        writeU32Be(out.writer.buffer, entry + 4, @intCast(payload_offset));
        writeU32Be(out.writer.buffer, entry + 8, @intCast(payload.len));
        writeU32Be(out.writer.buffer, entry + 12, table.length);
        writeU32Be(out.writer.buffer, entry + 16, table.checksum);
    }
    if (compress_tables and !compressed_any) return error.TestUnexpectedResult;

    const bytes = std.Io.Writer.buffered(&out.writer);
    writeU32Be(bytes, 0, 0x774f4646);
    writeU32Be(bytes, 4, flavor);
    writeU32Be(bytes, 8, @intCast(bytes.len));
    writeU16Be(bytes, 12, table_count);
    writeU16Be(bytes, 14, 0);
    writeU32Be(bytes, 16, @intCast(try sfntSizeForTest(tables)));
    writeU16Be(bytes, 20, 1);
    writeU16Be(bytes, 22, 0);
    writeU32Be(bytes, 24, 0);
    writeU32Be(bytes, 28, 0);
    writeU32Be(bytes, 32, 0);
    writeU32Be(bytes, 36, 0);
    writeU32Be(bytes, 40, 0);
    return try out.toOwnedSlice();
}

fn sfntSizeForTest(tables: []const TestSfntTable) !usize {
    var total = 12 + tables.len * 16;
    for (tables) |table| total += try align4(table.length);
    return total;
}

fn zlibCompressForTest(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var out = try std.Io.Writer.Allocating.initCapacity(allocator, data.len + 64);
    errdefer out.deinit();
    var scratch: [std.compress.flate.max_window_len]u8 = undefined;
    var compressor = try std.compress.flate.Compress.init(
        &out.writer,
        &scratch,
        .zlib,
        .fastest,
    );
    try compressor.writer.writeAll(data);
    try compressor.finish();
    return try out.toOwnedSlice();
}

fn reverseWoffPayloadOrderForTest(
    allocator: std.mem.Allocator,
    woff: []const u8,
) ![]u8 {
    const table_count = readU16Be(woff, 12);
    const first_payload = 44 + @as(usize, table_count) * 20;
    if (first_payload > woff.len) return error.TestUnexpectedResult;
    const reversed = try allocator.dupe(u8, woff);
    errdefer allocator.free(reversed);
    var destination = first_payload;
    var reverse_index: usize = table_count;
    while (reverse_index != 0) {
        reverse_index -= 1;
        const record = 44 + reverse_index * 20;
        const source: usize = readU32Be(woff, record + 4);
        const compressed_len: usize = readU32Be(woff, record + 8);
        const padded_len = try align4(compressed_len);
        if (source > woff.len or padded_len > woff.len - source) {
            return error.TestUnexpectedResult;
        }
        @memcpy(
            reversed[destination..][0..padded_len],
            woff[source..][0..padded_len],
        );
        writeU32Be(reversed, record + 4, @intCast(destination));
        destination += padded_len;
    }
    if (destination != woff.len) return error.TestUnexpectedResult;
    return reversed;
}

fn findWoffTablePayloadForTest(woff: []const u8, tag: *const [4]u8) !usize {
    const table_count = readU16Be(woff, 12);
    for (0..table_count) |index| {
        const record = 44 + index * 20;
        if (std.mem.eql(u8, woff[record..][0..4], tag)) {
            const offset: usize = readU32Be(woff, record + 4);
            const compressed_len = readU32Be(woff, record + 8);
            const original_len = readU32Be(woff, record + 12);
            if (compressed_len != original_len or offset > woff.len) {
                return error.TestUnexpectedResult;
            }
            return offset;
        }
    }
    return error.TestUnexpectedResult;
}

fn sfntChecksumForTest(sfnt: []const u8) !u32 {
    if ((sfnt.len & 3) != 0) return error.TestUnexpectedResult;
    var checksum: u32 = 0;
    var offset: usize = 0;
    while (offset < sfnt.len) : (offset += 4) {
        checksum +%= readU32Be(sfnt, offset);
    }
    return checksum;
}

pub const testing = struct {
    pub const buildWoff1 = buildWoffForTest;
};

// `buildMinimalTtf` encoded by the reference woff2 encoder. Keeping the fixture
// inline makes decoder tests independent of a separately installed encoder
// while still exercising transformed glyf/loca reconstruction.
const minimal_woff2 = [_]u8{
    0x77, 0x4f, 0x46, 0x32, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0xbc,
    0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x01, 0x78, 0x00, 0x00, 0x00, 0x79,
    0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x2c, 0x0a, 0x18, 0x43, 0x0b, 0x0c, 0x00, 0x01, 0x36, 0x02, 0x24,
    0x03, 0x08, 0x13, 0x18, 0x04, 0x20, 0x1b, 0x08, 0x01, 0xf8, 0x8f, 0xd3,
    0x15, 0xf1, 0xab, 0xfc, 0x4c, 0xc4, 0xf3, 0xf4, 0xf7, 0xda, 0xb9, 0xa9,
    0x7d, 0xfc, 0x8f, 0x07, 0xb0, 0x13, 0xa4, 0x83, 0x47, 0xc3, 0x52, 0x0d,
    0x33, 0xbe, 0xcb, 0xaf, 0x71, 0x30, 0x39, 0xf3, 0x35, 0x47, 0x54, 0xa9,
    0x95, 0x97, 0x06, 0xe0, 0x00, 0x08, 0x76, 0x00, 0x11, 0x75, 0xc1, 0x40,
    0x43, 0x85, 0x86, 0x86, 0x60, 0x5f, 0x8a, 0x2b, 0xe5, 0x2b, 0x00, 0x9a,
    0xa0, 0x87, 0xa0, 0x8e, 0x26, 0x60, 0x00, 0x08, 0x50, 0xcf, 0xf0, 0xe6,
    0x78, 0xd8, 0x0e, 0x50, 0x7b, 0xd6, 0x9e, 0x82, 0x70, 0x7f, 0xb8, 0x3c,
    0x8d, 0x57, 0xff, 0x1d, 0xf5, 0x1f, 0x00, 0x58, 0x90, 0x0e, 0x20, 0xd4,
    0xab, 0x82, 0x82, 0x6a, 0xf9, 0xa3, 0x5e, 0x81, 0x60, 0x21, 0xa2, 0x05,
    0x22, 0x25, 0x41, 0x4d, 0x5d, 0x40, 0x0d, 0x01,
};

test "font container decodes compressed WOFF1 and owns parsed bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const sfnt = try test_font.buildNamedTtfWithNames(
        allocator,
        "WOFF Demo",
        "Regular",
        "WOFF Demo Regular",
    );
    defer allocator.free(sfnt);
    const woff = try buildWoffForTest(allocator, sfnt, true);
    defer allocator.free(woff);

    try std.testing.expectEqual(Format.woff1, try detectFormat(woff));
    var loaded = try LoadedFont.load(allocator, woff, sfnt.len);
    defer loaded.deinit();
    try std.testing.expectEqualSlices(u8, sfnt, loaded.bytes);
    var name_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "WOFF Demo",
        (try loaded.font.familyName(&name_buffer)) orelse
            return error.TestUnexpectedResult,
    );
    try std.testing.expectError(
        error.OutputTooLarge,
        decodeFontContainerAlloc(allocator, woff, sfnt.len - 1),
    );
}

test "font container rejects malformed WOFF1 directory ranges" {
    const allocator = std.testing.allocator;
    const sfnt = try @import("test_font.zig").buildMinimalTtf(allocator);
    defer allocator.free(sfnt);
    const woff = try buildWoffForTest(allocator, sfnt, false);
    defer allocator.free(woff);

    const malformed = try allocator.dupe(u8, woff);
    defer allocator.free(malformed);
    // Make table 1 overlap table 0 while preserving aligned offsets.
    const first_offset = readU32Be(malformed, 44 + 4);
    writeU32Be(malformed, 44 + 20 + 4, first_offset);
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(allocator, malformed, sfnt.len),
    );

    const metadata_overlap = try allocator.dupe(u8, woff);
    defer allocator.free(metadata_overlap);
    const table_offset = readU32Be(metadata_overlap, 44 + 4);
    writeU32Be(metadata_overlap, 24, table_offset);
    writeU32Be(metadata_overlap, 28, 4);
    writeU32Be(metadata_overlap, 32, 4);
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(allocator, metadata_overlap, sfnt.len),
    );
}

test "font container preserves WOFF1 physical table order" {
    const allocator = std.testing.allocator;
    const sfnt = try @import("test_font.zig").buildMinimalTtf(allocator);
    defer allocator.free(sfnt);
    const tag_order_woff = try buildWoffForTest(allocator, sfnt, false);
    defer allocator.free(tag_order_woff);
    const woff = try reverseWoffPayloadOrderForTest(allocator, tag_order_woff);
    defer allocator.free(woff);

    // Make checkSumAdjustment describe the physically reversed SFNT encoded by
    // this fixture. The head table's directory checksum deliberately treats
    // these bytes as zero, so no table checksum needs to be changed.
    const head_offset = try findWoffTablePayloadForTest(woff, "head");
    if (head_offset > woff.len or woff.len - head_offset < 12) {
        return error.TestUnexpectedResult;
    }
    writeU32Be(woff, head_offset + 8, 0);
    const unadjusted = try decodeFontContainerAlloc(allocator, woff, sfnt.len);
    defer allocator.free(unadjusted);
    const adjustment = 0xb1b0afba -% try sfntChecksumForTest(unadjusted);
    writeU32Be(woff, head_offset + 8, adjustment);

    const decoded = try decodeFontContainerAlloc(allocator, woff, sfnt.len);
    defer allocator.free(decoded);
    try std.testing.expectEqual(
        @as(u32, 0xb1b0afba),
        try sfntChecksumForTest(decoded),
    );
    var font = try Font.parse(allocator, decoded);
    defer font.deinit();
}

test "font container WOFF2 runtime round trip" {
    const allocator = std.testing.allocator;
    const woff2 = &minimal_woff2;

    try std.testing.expectEqual(Format.woff2, try detectFormat(woff2));
    const decoded = decodeFontContainerAlloc(
        allocator,
        woff2,
        std.math.maxInt(usize),
    ) catch |err| switch (err) {
        error.Woff2RuntimeUnavailable => return error.SkipZigTest,
        else => return err,
    };
    defer allocator.free(decoded);
    try std.testing.expectError(
        error.OutputTooLarge,
        decodeFontContainerAlloc(allocator, woff2, decoded.len - 1),
    );
    var font = try Font.parse(allocator, decoded);
    defer font.deinit();
    try std.testing.expectEqual(@as(u16, 1000), font.units_per_em);

    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(
            allocator,
            woff2[0 .. woff2.len - 1],
            decoded.len,
        ),
    );
}
