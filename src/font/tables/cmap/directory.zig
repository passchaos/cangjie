//! cmap EncodingRecord parsing and borrowed-cache revalidation.

const std = @import("std");
const bin = @import("../../../binary.zig");
const sfnt = @import("../../sfnt/root.zig");
const types = @import("types.zig");
const validation = @import("validation/root.zig");
const glyphs = @import("validation/glyphs.zig");

pub const Error =
    sfnt.Error || error{EndOfStream} || std.mem.Allocator.Error;

pub fn parse(
    allocator: std.mem.Allocator,
    data: []const u8,
    cmap: sfnt.Record,
    glyph_count: u16,
) Error![]types.Subtable {
    if (cmap.length < 4) return error.BadSfnt;
    const version = try bin.readU16At(data, cmap.offset);
    if (version != 0) return error.BadSfnt;
    const count = try bin.readU16At(data, cmap.offset + 2);
    if (@as(usize, count) * 8 > cmap.length - 4) return error.BadSfnt;
    const records_end = 4 + @as(usize, count) * 8;

    var subtables = std.ArrayList(types.Subtable).empty;
    errdefer subtables.deinit(allocator);
    var previous_encoding: ?struct { platform_id: u16, encoding_id: u16 } = null;
    for (0..count) |i| {
        const rec = cmap.offset + 4 + i * 8;
        const platform_id = try bin.readU16At(data, rec);
        const encoding_id = try bin.readU16At(data, rec + 2);
        if (previous_encoding) |previous| {
            // Encoding records are a directory keyed by platform/encoding ID.
            // Enforcing the OpenType sort order also rejects duplicate keys,
            // avoiding ambiguous cmap selection when two records claim the
            // same platform-specific character map.
            if (platform_id < previous.platform_id or (platform_id == previous.platform_id and encoding_id <= previous.encoding_id)) {
                return error.BadSfnt;
            }
        }
        previous_encoding = .{ .platform_id = platform_id, .encoding_id = encoding_id };

        const sub_offset = try bin.readU32At(data, rec + 4);
        // EncodingRecord offsets name complete cmap subtables, not arbitrary
        // byte positions. Requiring child subtables to start after the record
        // directory prevents an offset field or a later EncodingRecord from
        // being reinterpreted as a plausible format-0 header.
        if (sub_offset < records_end or sub_offset > cmap.length - 2) return error.BadSfnt;
        const absolute = cmap.offset + sub_offset;
        const format = try bin.readU16At(data, absolute);
        const length = try subtableLength(data, cmap, @intCast(sub_offset), format);
        try validation.validate(
            data,
            absolute,
            length,
            format,
            platform_id,
            encoding_id,
        );
        try glyphs.validate(data, absolute, length, format, glyph_count);
        try subtables.append(allocator, .{
            .platform_id = platform_id,
            .encoding_id = encoding_id,
            .offset = absolute,
            .length = length,
            .format = format,
        });
    }
    return try subtables.toOwnedSlice(allocator);
}

pub fn relativeOffset(table: sfnt.Record, absolute_offset: usize) Error!usize {
    if (absolute_offset < table.offset) return error.BadSfnt;
    const relative_offset = absolute_offset - table.offset;
    if (relative_offset > table.length) return error.BadSfnt;
    return relative_offset;
}

pub fn validateCachedEncodingRecord(data: []const u8, cmap: sfnt.Record, subtable: types.Subtable, relative_offset: usize) Error!void {
    if (cmap.length < 4) return error.BadSfnt;
    if (try bin.readU16At(data, cmap.offset) != 0) return error.BadSfnt;
    const count = try bin.readU16At(data, cmap.offset + 2);
    if (@as(usize, count) * 8 > cmap.length - 4) return error.BadSfnt;

    var previous_encoding: ?struct { platform_id: u16, encoding_id: u16 } = null;
    for (0..count) |index| {
        const record = cmap.offset + 4 + index * 8;
        const platform_id = try bin.readU16At(data, record);
        const encoding_id = try bin.readU16At(data, record + 2);
        if (previous_encoding) |previous| {
            if (platform_id < previous.platform_id or (platform_id == previous.platform_id and encoding_id <= previous.encoding_id)) {
                return error.BadSfnt;
            }
        }
        previous_encoding = .{ .platform_id = platform_id, .encoding_id = encoding_id };
        if (platform_id != subtable.platform_id or encoding_id != subtable.encoding_id) continue;

        // Font caches cmap EncodingRecords after parse, but the underlying SFNT
        // bytes are borrowed from the caller. Re-check that the same directory
        // key still points at the same child subtable before following cached
        // offsets, so post-parse edits cannot silently redirect or erase the
        // character map while public lookup keeps using the old address.
        const current_offset: usize = @intCast(try bin.readU32At(data, record + 4));
        if (current_offset != relative_offset) return error.BadSfnt;
        return;
    }
    return error.BadSfnt;
}

pub fn subtableLength(data: []const u8, cmap: sfnt.Record, sub_offset: usize, format: u16) Error!usize {
    if (sub_offset > cmap.length) return error.BadSfnt;
    const available = cmap.length - sub_offset;
    const absolute = cmap.offset + sub_offset;
    const length: usize = switch (format) {
        0, 2, 4, 6 => blk: {
            if (available < 4) return error.BadSfnt;
            break :blk try bin.readU16At(data, absolute + 2);
        },
        8, 10, 12, 13 => blk: {
            if (available < 8) return error.BadSfnt;
            break :blk try bin.readU32At(data, absolute + 4);
        },
        14 => blk: {
            if (available < 6) return error.BadSfnt;
            break :blk try bin.readU32At(data, absolute + 2);
        },
        else => available,
    };

    // Cmap offsets are scoped to the declared cmap table, not to the whole
    // SFNT file. Remembering each subtable's own declared length prevents a
    // malformed format 8/10/12/13 table from satisfying its glyph array or group
    // reads with bytes that actually belong to the next SFNT table.
    if (length == 0 or length > available) return error.BadSfnt;
    return length;
}
