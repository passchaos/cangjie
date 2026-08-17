//! WOFF1 validation, decompression, and SFNT reconstruction.

const std = @import("std");
const binary = @import("binary.zig");
const types = @import("types.zig");

const WoffTableEntry = struct {
    tag: [4]u8,
    offset: u32,
    compressed_len: u32,
    original_len: u32,
    checksum: u32,
};

pub fn decodeAlloc(
    allocator: std.mem.Allocator,
    woff: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    if (woff.len < 44 or binary.readU32(woff, 0) != 0x774f4646) {
        return error.InvalidContainer;
    }
    const flavor = binary.readU32(woff, 4);
    // WOFF1 wraps one SFNT face, not a collection. Restrict reconstruction to
    // the same modern outline flavors accepted by Font.parse so this public
    // decoder cannot manufacture an allegedly supported but unusable SFNT.
    if (!types.isSupportedSfntFlavor(flavor)) return error.InvalidContainer;
    const advertised_len: usize = binary.readU32(woff, 8);
    if (advertised_len != woff.len) return error.InvalidContainer;
    const table_count = binary.readU16(woff, 12);
    if (table_count == 0 or binary.readU16(woff, 14) != 0) {
        return error.InvalidContainer;
    }
    const advertised_sfnt_size: usize = binary.readU32(woff, 16);
    if (advertised_sfnt_size > max_decoded_size) return error.OutputTooLarge;

    const directory_len = std.math.mul(usize, @as(usize, table_count), 20) catch
        return error.InvalidContainer;
    if (directory_len > woff.len - 44) return error.InvalidContainer;
    const minimum_data_offset = 44 + directory_len;
    const metadata_range = try validateMetadataRange(
        woff.len,
        minimum_data_offset,
        binary.readU32(woff, 24),
        binary.readU32(woff, 28),
        binary.readU32(woff, 32),
    );
    const private_range = try validateOptionalBlockRange(
        woff.len,
        minimum_data_offset,
        binary.readU32(woff, 36),
        binary.readU32(woff, 40),
    );

    const entries = try allocator.alloc(WoffTableEntry, table_count);
    defer allocator.free(entries);
    const payload_order = try allocator.alloc(usize, table_count);
    defer allocator.free(payload_order);
    for (entries, 0..) |*entry, index| {
        const base = 44 + index * 20;
        entry.* = .{
            .tag = woff[base..][0..4].*,
            .offset = binary.readU32(woff, base + 4),
            .compressed_len = binary.readU32(woff, base + 8),
            .original_len = binary.readU32(woff, base + 12),
            .checksum = binary.readU32(woff, base + 16),
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

    binary.writeU32(out, 0, flavor);
    binary.writeU16(out, 4, table_count);
    const search = try sfntSearchParameters(table_count);
    binary.writeU16(out, 6, search.search_range);
    binary.writeU16(out, 8, search.entry_selector);
    binary.writeU16(out, 10, search.range_shift);

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
        binary.writeU32(out, record + 4, entry.checksum);
        binary.writeU32(out, record + 8, @intCast(table_offset));
        binary.writeU32(out, record + 12, entry.original_len);

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
        table_offset += try binary.align4(original_len);
    }
    return out;
}
fn inflateWoffTable(out: []u8, compressed: []const u8) types.Error!void {
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
) types.Error!?WoffByteRange {
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
) types.Error!?WoffByteRange {
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
) types.Error!void {
    const offset: usize = entry.offset;
    const len: usize = entry.compressed_len;
    if (offset < minimum_data_offset or offset > file_len or len > file_len - offset) {
        return error.InvalidContainer;
    }
    if ((try binary.align4(len)) > file_len - offset) return error.InvalidContainer;
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
        expected = start + try binary.align4(entry.compressed_len);
    }
    if (metadata) |range| {
        if (range.start != expected) return error.InvalidContainer;
        expected = range.end;
    }
    if (private) |range| {
        expected = try binary.align4(expected);
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

fn validateTableTag(tag: [4]u8) types.Error!void {
    for (tag) |byte| {
        if (byte < 0x20 or byte > 0x7e) return error.InvalidContainer;
    }
}

fn sfntSize(entries: []const WoffTableEntry) types.Error!usize {
    var total = std.math.add(
        usize,
        12,
        std.math.mul(usize, entries.len, 16) catch return error.InvalidContainer,
    ) catch return error.InvalidContainer;
    for (entries) |entry| {
        total = std.math.add(usize, total, try binary.align4(entry.original_len)) catch
            return error.InvalidContainer;
    }
    return total;
}

const SfntSearchParameters = struct {
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};

fn sfntSearchParameters(table_count: u16) types.Error!SfntSearchParameters {
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
