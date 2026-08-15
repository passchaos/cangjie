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
    dfont,
    woff1,
    woff2,
};

/// Conservative default shared with `FontDatabase` convenience loaders.
/// Explicit APIs can raise this for unusually large, trusted collections.
pub const default_max_decoded_size = 64 * 1024 * 1024;

/// Owns decoded SFNT bytes together with a `Face` that borrows those bytes.
///
/// `Face.parse` intentionally remains a zero-copy API for callers that already
/// own SFNT data. Container loading needs a separate owner because WOFF input
/// is reconstructed into a new SFNT allocation whose address must remain valid
/// for the complete lifetime of `face`.
pub const OwnedFace = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    face: Font,

    pub fn load(
        allocator: std.mem.Allocator,
        data: []const u8,
        max_decoded_size: usize,
    ) !OwnedFace {
        return loadFace(allocator, data, 0, max_decoded_size);
    }

    pub fn loadFace(
        allocator: std.mem.Allocator,
        data: []const u8,
        face_index: usize,
        max_decoded_size: usize,
    ) !OwnedFace {
        const bytes = try decodeFontContainerAlloc(allocator, data, max_decoded_size);
        errdefer allocator.free(bytes);
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .face = try Font.parseFace(allocator, bytes, face_index),
        };
    }

    pub fn deinit(self: *OwnedFace) void {
        self.face.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub fn detectFormat(data: []const u8) Error!Format {
    if (data.len < 4) return error.InvalidContainer;
    const signature = readU32Be(data, 0);
    return switch (signature) {
        0x00010000, // TrueType outlines.
        0x74727565, // "true", accepted by the SFNT parser.
        0x4f54544f, // "OTTO", CFF/CFF2 outlines.
        0x74746366, // "ttcf", TrueType/OpenType collection.
        => .sfnt,
        0x00000100 => .dfont, // Apple data-fork resource container.
        0x774f4646 => .woff1, // "wOFF"
        0x774f4632 => .woff2, // "wOF2"
        else => {
            // Flattened resource forks need not use dfont's conventional
            // 256-byte data offset. Classify only structurally plausible
            // disjoint data/map headers here; the decoder performs the full
            // map and `sfnt` resource validation.
            if (data.len >= 16) {
                const data_start: usize = signature;
                const map_start: usize = readU32Be(data, 4);
                const data_len: usize = readU32Be(data, 8);
                const map_len: usize = readU32Be(data, 12);
                if (data_start <= data.len and
                    data_len <= data.len - data_start and
                    map_start <= data.len and
                    map_len <= data.len - map_start and
                    data_len != 0 and map_len >= 28 and
                    !rangesOverlapContainer(
                        data_start,
                        data_start + data_len,
                        map_start,
                        map_start + map_len,
                    ))
                {
                    return .dfont;
                }
            }
            return error.UnsupportedContainer;
        },
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
        .dfont => try decodeDfontToSfntAlloc(allocator, data, max_decoded_size),
        .woff1 => try decodeWoff1ToSfntAlloc(allocator, data, max_decoded_size),
        .woff2 => try decodeWoff2ToSfntAlloc(allocator, data, max_decoded_size),
    };
}

const DfontResource = struct {
    payload_offset: usize,
    payload_len: usize,
};

/// Reconstruct the `sfnt` resources in an Apple data-fork resource container.
///
/// A one-face dfont returns that standalone SFNT unchanged. Multiple resources
/// become a TTC in resource-map order, which is the face order used by
/// QuickDraw, FreeType, and HarfBuzz. Resource SFNT table offsets are local to
/// each resource; TTC records require absolute offsets from the collection
/// start, so reconstruction rebases every table record after copying.
fn decodeDfontToSfntAlloc(
    allocator: std.mem.Allocator,
    dfont: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    const resources = try dfontSfntResources(allocator, dfont);
    defer allocator.free(resources);

    if (resources.len == 1) {
        const resource = resources[0];
        if (resource.payload_len > max_decoded_size) return error.OutputTooLarge;
        return try allocator.dupe(
            u8,
            dfont[resource.payload_offset..][0..resource.payload_len],
        );
    }

    const header_unaligned = std.math.add(
        usize,
        12,
        std.math.mul(usize, resources.len, 4) catch
            return error.InvalidContainer,
    ) catch return error.InvalidContainer;
    const header_len = try align4(header_unaligned);
    var total_len = header_len;
    for (resources) |resource| {
        total_len = std.math.add(
            usize,
            total_len,
            try align4(resource.payload_len),
        ) catch return error.InvalidContainer;
        if (total_len > max_decoded_size) return error.OutputTooLarge;
    }

    const out = try allocator.alloc(u8, total_len);
    errdefer allocator.free(out);
    @memset(out, 0);
    @memcpy(out[0..4], "ttcf");
    writeU32Be(out, 4, 0x00010000);
    if (resources.len > std.math.maxInt(u32)) return error.InvalidContainer;
    writeU32Be(out, 8, @intCast(resources.len));

    var face_offset = header_len;
    for (resources, 0..) |resource, face_index| {
        if (face_offset > std.math.maxInt(u32)) return error.InvalidContainer;
        writeU32Be(out, 12 + face_index * 4, @intCast(face_offset));
        const face = dfont[resource.payload_offset..][0..resource.payload_len];
        @memcpy(out[face_offset..][0..face.len], face);
        try rebaseDfontSfntTableOffsets(
            out[face_offset..][0..face.len],
            face_offset,
        );
        face_offset += try align4(face.len);
    }
    return out;
}

fn dfontSfntResources(
    allocator: std.mem.Allocator,
    dfont: []const u8,
) ![]DfontResource {
    if (dfont.len < 16) {
        return error.InvalidContainer;
    }
    const data_start: usize = readU32Be(dfont, 0);
    const map_start: usize = readU32Be(dfont, 4);
    const data_len: usize = readU32Be(dfont, 8);
    const map_len: usize = readU32Be(dfont, 12);
    const data_end = try checkedContainerEnd(data_start, data_len, dfont.len);
    const map_end = try checkedContainerEnd(map_start, map_len, dfont.len);
    if (data_len == 0 or map_len < 28 or
        rangesOverlapContainer(data_start, data_end, map_start, map_end))
    {
        return error.InvalidContainer;
    }

    // Classic resource forks repeat their header in the map. A dfont uses 16
    // zero bytes instead; accepting either also permits a flattened resource
    // fork with the same safe grammar.
    const map_header = dfont[map_start..][0..16];
    if (!allZero(map_header) and !std.mem.eql(u8, map_header, dfont[0..16])) {
        return error.InvalidContainer;
    }

    const type_list_rel: usize = readU16Be(dfont, map_start + 24);
    const name_list_rel: usize = readU16Be(dfont, map_start + 26);
    if (type_list_rel < 28 or type_list_rel >= map_len or
        name_list_rel < 28 or name_list_rel > map_len)
    {
        return error.InvalidContainer;
    }
    const type_list = map_start + type_list_rel;
    const name_list = map_start + name_list_rel;
    if (type_list > map_end - 2 or type_list >= name_list) {
        return error.InvalidContainer;
    }

    const type_count = @as(usize, readU16Be(dfont, type_list)) + 1;
    if (type_count > 4079) return error.InvalidContainer;
    const type_bytes = std.math.mul(usize, type_count, 8) catch
        return error.InvalidContainer;
    const type_records_end = std.math.add(
        usize,
        type_list + 2,
        type_bytes,
    ) catch return error.InvalidContainer;
    if (type_records_end > name_list) return error.InvalidContainer;

    var sfnt_resources = std.ArrayList(DfontResource).empty;
    defer sfnt_resources.deinit(allocator);
    var found_sfnt_type = false;
    for (0..type_count) |type_index| {
        const type_record = type_list + 2 + type_index * 8;
        const tag = dfont[type_record..][0..4];
        const resource_count = @as(usize, readU16Be(dfont, type_record + 4)) + 1;
        if (resource_count > 2727) return error.InvalidContainer;
        const references_rel: usize = readU16Be(dfont, type_record + 6);
        const references = std.math.add(
            usize,
            type_list,
            references_rel,
        ) catch return error.InvalidContainer;
        const reference_bytes = std.math.mul(
            usize,
            resource_count,
            12,
        ) catch return error.InvalidContainer;
        const references_end = std.math.add(
            usize,
            references,
            reference_bytes,
        ) catch return error.InvalidContainer;
        if (references < type_records_end or references_end > name_list) {
            return error.InvalidContainer;
        }

        const is_sfnt = std.mem.eql(u8, tag, "sfnt");
        if (is_sfnt and found_sfnt_type) return error.InvalidContainer;
        found_sfnt_type = found_sfnt_type or is_sfnt;
        for (0..resource_count) |resource_index| {
            const reference = references + resource_index * 12;
            if (readU32Be(dfont, reference + 8) != 0) {
                return error.InvalidContainer;
            }
            try validateDfontResourceName(
                dfont,
                map_end,
                name_list,
                readU16Be(dfont, reference + 2),
            );
            const attributes_and_offset = readU32Be(dfont, reference + 4);
            const data_relative = @as(usize, attributes_and_offset & 0x00ffffff);
            const resource_start = std.math.add(
                usize,
                data_start,
                data_relative,
            ) catch return error.InvalidContainer;
            if (resource_start < data_start or resource_start > data_end - 4) {
                return error.InvalidContainer;
            }
            const payload_len: usize = readU32Be(dfont, resource_start);
            const payload_offset = resource_start + 4;
            if (payload_len > data_end - payload_offset) {
                return error.InvalidContainer;
            }
            if (is_sfnt) {
                for (sfnt_resources.items) |existing| {
                    if (rangesOverlapContainer(
                        payload_offset,
                        payload_offset + payload_len,
                        existing.payload_offset,
                        existing.payload_offset + existing.payload_len,
                    )) {
                        return error.InvalidContainer;
                    }
                }
                try validateDfontSfnt(
                    dfont[payload_offset..][0..payload_len],
                );
                try sfnt_resources.append(allocator, .{
                    .payload_offset = payload_offset,
                    .payload_len = payload_len,
                });
            }
        }
    }
    if (sfnt_resources.items.len == 0) return error.InvalidContainer;
    return try sfnt_resources.toOwnedSlice(allocator);
}

fn validateDfontResourceName(
    dfont: []const u8,
    map_end: usize,
    name_list: usize,
    name_offset_raw: u16,
) !void {
    if (name_offset_raw == 0xffff) return;
    const name_offset = std.math.add(
        usize,
        name_list,
        name_offset_raw,
    ) catch return error.InvalidContainer;
    if (name_offset >= map_end) return error.InvalidContainer;
    const name_len: usize = dfont[name_offset];
    if (name_len > map_end - name_offset - 1) return error.InvalidContainer;
}

fn validateDfontSfnt(sfnt: []const u8) !void {
    if (sfnt.len < 12 or !isSupportedSfntFlavor(readU32Be(sfnt, 0))) {
        return error.InvalidContainer;
    }
    const table_count = readU16Be(sfnt, 4);
    if (table_count == 0) return error.InvalidContainer;
    const directory_len = std.math.mul(
        usize,
        table_count,
        16,
    ) catch return error.InvalidContainer;
    if (directory_len > sfnt.len - 12) return error.InvalidContainer;
    for (0..table_count) |table_index| {
        const record = 12 + table_index * 16;
        const offset: usize = readU32Be(sfnt, record + 8);
        const len: usize = readU32Be(sfnt, record + 12);
        if ((offset & 3) != 0 or offset > sfnt.len or len > sfnt.len - offset) {
            return error.InvalidContainer;
        }
    }
}

fn rebaseDfontSfntTableOffsets(face: []u8, face_offset: usize) !void {
    try validateDfontSfnt(face);
    const table_count = readU16Be(face, 4);
    for (0..table_count) |table_index| {
        const record = 12 + table_index * 16;
        const old_offset: usize = readU32Be(face, record + 8);
        const new_offset = std.math.add(
            usize,
            face_offset,
            old_offset,
        ) catch return error.InvalidContainer;
        if (new_offset > std.math.maxInt(u32)) return error.InvalidContainer;
        writeU32Be(face, record + 8, @intCast(new_offset));
    }
}

fn checkedContainerEnd(start: usize, len: usize, file_len: usize) !usize {
    if (start > file_len or len > file_len - start) {
        return error.InvalidContainer;
    }
    return start + len;
}

fn rangesOverlapContainer(
    first_start: usize,
    first_end: usize,
    second_start: usize,
    second_end: usize,
) bool {
    return first_start < second_end and second_start < first_end;
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
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

fn buildDfontForTest(
    allocator: std.mem.Allocator,
    faces: []const []const u8,
) ![]u8 {
    if (faces.len == 0 or faces.len > std.math.maxInt(u16) + 1) {
        return error.TestUnexpectedResult;
    }
    const data_start: usize = 256;
    var data_len: usize = 0;
    for (faces) |face| {
        data_len = std.math.add(usize, data_len, 4 + face.len) catch
            return error.OutOfMemory;
    }
    const map_start = data_start + data_len;
    const type_list_rel: usize = 28;
    const references_rel: usize = 10;
    const map_len = 28 + 2 + 8 + faces.len * 12;
    const bytes = try allocator.alloc(u8, map_start + map_len);
    @memset(bytes, 0);

    writeU32Be(bytes, 0, @intCast(data_start));
    writeU32Be(bytes, 4, @intCast(map_start));
    writeU32Be(bytes, 8, @intCast(data_len));
    writeU32Be(bytes, 12, @intCast(map_len));
    writeU16Be(bytes, map_start + 24, @intCast(type_list_rel));
    writeU16Be(bytes, map_start + 26, @intCast(map_len));

    const type_list = map_start + type_list_rel;
    writeU16Be(bytes, type_list, 0); // One resource type, encoded count - 1.
    @memcpy(bytes[type_list + 2 ..][0..4], "sfnt");
    writeU16Be(bytes, type_list + 6, @intCast(faces.len - 1));
    writeU16Be(bytes, type_list + 8, @intCast(references_rel));

    var resource_offset: usize = 0;
    for (faces, 0..) |face, face_index| {
        const resource = data_start + resource_offset;
        writeU32Be(bytes, resource, @intCast(face.len));
        @memcpy(bytes[resource + 4 ..][0..face.len], face);

        const reference = type_list + references_rel + face_index * 12;
        writeU16Be(bytes, reference, @intCast(face_index + 128));
        writeU16Be(bytes, reference + 2, 0xffff);
        writeU32Be(bytes, reference + 4, @intCast(resource_offset));
        resource_offset += 4 + face.len;
    }
    return bytes;
}

pub const testing = struct {
    pub const buildWoff1 = buildWoffForTest;
    pub const buildDfont = buildDfontForTest;
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
    var loaded = try OwnedFace.load(allocator, woff, sfnt.len);
    defer loaded.deinit();
    try std.testing.expectEqualSlices(u8, sfnt, loaded.bytes);
    var name_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "WOFF Demo",
        (try loaded.face.familyName(&name_buffer)) orelse
            return error.TestUnexpectedResult,
    );
    try std.testing.expectError(
        error.OutputTooLarge,
        decodeFontContainerAlloc(allocator, woff, sfnt.len - 1),
    );
}

test "font container decodes dfont resources and collections" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");
    const first = try test_font.buildNamedTtfWithNames(
        allocator,
        "DFont One",
        "Regular",
        "DFont One Regular",
    );
    defer allocator.free(first);
    const second = try test_font.buildNamedTtfWithNames(
        allocator,
        "DFont Two",
        "Regular",
        "DFont Two Regular",
    );
    defer allocator.free(second);

    const single = try buildDfontForTest(allocator, &.{first});
    defer allocator.free(single);
    try std.testing.expectEqual(Format.dfont, try detectFormat(single));
    const decoded_single = try decodeFontContainerAlloc(
        allocator,
        single,
        first.len,
    );
    defer allocator.free(decoded_single);
    try std.testing.expectEqualSlices(u8, first, decoded_single);

    const collection = try buildDfontForTest(allocator, &.{ first, second });
    defer allocator.free(collection);
    const decoded = try decodeFontContainerAlloc(
        allocator,
        collection,
        std.math.maxInt(usize),
    );
    defer allocator.free(decoded);
    try std.testing.expectEqual(@as(usize, 2), try Font.faceCount(decoded));
    var second_face = try Font.parseFace(allocator, decoded, 1);
    defer second_face.deinit();
    var name_buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "DFont Two",
        (try second_face.familyName(&name_buffer)) orelse
            return error.TestUnexpectedResult,
    );
    try std.testing.expectError(
        error.OutputTooLarge,
        decodeFontContainerAlloc(allocator, collection, decoded.len - 1),
    );
}

test "font container rejects malformed dfont resource maps" {
    const allocator = std.testing.allocator;
    const sfnt = try @import("test_font.zig").buildMinimalTtf(allocator);
    defer allocator.free(sfnt);
    const dfont = try buildDfontForTest(allocator, &.{sfnt});
    defer allocator.free(dfont);

    const bad_map = try allocator.dupe(u8, dfont);
    defer allocator.free(bad_map);
    writeU32Be(bad_map, 4, @intCast(bad_map.len - 8));
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(allocator, bad_map, std.math.maxInt(usize)),
    );

    const bad_resource = try allocator.dupe(u8, dfont);
    defer allocator.free(bad_resource);
    writeU32Be(bad_resource, 256, std.math.maxInt(u32));
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(
            allocator,
            bad_resource,
            std.math.maxInt(usize),
        ),
    );

    const nonzero_handle = try allocator.dupe(u8, dfont);
    defer allocator.free(nonzero_handle);
    const map_start: usize = readU32Be(nonzero_handle, 4);
    const type_list = map_start + readU16Be(nonzero_handle, map_start + 24);
    const reference = type_list + readU16Be(nonzero_handle, type_list + 8);
    writeU32Be(nonzero_handle, reference + 8, 1);
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(
            allocator,
            nonzero_handle,
            std.math.maxInt(usize),
        ),
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
