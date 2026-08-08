const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Anchor = struct {
    x: i16,
    y: i16,
};

pub const GlyphAnchors = struct {
    glyph_id: u16,
    data_offset: usize,
    anchors: []Anchor,
};

pub const Info = struct {
    version: u16,
    flags: u16,
    lookup_format: u16,
    lookup_table_offset: usize,
    glyph_data_table_offset: usize,
    glyphs: []GlyphAnchors,
};

const Header = struct {
    version: u16,
    flags: u16,
    lookup_offset: usize,
    glyph_data_offset: usize,
};

pub fn validate(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    const h = try header(data, offset, length);
    const lookup = try lookupInfo(data, offset, length, h.lookup_offset, glyph_count);
    if (h.glyph_data_offset < lookup.end_offset or h.glyph_data_offset > length) return error.BadSfnt;
    try walkLookup(data, offset, length, h.glyph_data_offset, lookup, glyph_count, null, null);
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!Info {
    const h = try header(data, offset, length);
    const lookup = try lookupInfo(data, offset, length, h.lookup_offset, glyph_count);
    if (h.glyph_data_offset < lookup.end_offset or h.glyph_data_offset > length) return error.BadSfnt;

    var glyphs = try std.ArrayList(GlyphAnchors).initCapacity(allocator, 0);
    errdefer {
        for (glyphs.items) |glyph| allocator.free(glyph.anchors);
        glyphs.deinit(allocator);
    }
    try walkLookup(data, offset, length, h.glyph_data_offset, lookup, glyph_count, allocator, &glyphs);

    return .{
        .version = h.version,
        .flags = h.flags,
        .lookup_format = lookup.format,
        .lookup_table_offset = h.lookup_offset,
        .glyph_data_table_offset = h.glyph_data_offset,
        .glyphs = try glyphs.toOwnedSlice(allocator),
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    for (value.glyphs) |glyph| allocator.free(glyph.anchors);
    allocator.free(value.glyphs);
}

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 12) return error.BadSfnt;
    const version = try bin.readU16At(data, offset);
    const flags = try bin.readU16At(data, offset + 2);
    if (version != 0 or flags != 0) return error.BadSfnt;
    const lookup_offset: usize = @intCast(try bin.readU32At(data, offset + 4));
    const glyph_data_offset: usize = @intCast(try bin.readU32At(data, offset + 8));
    if (lookup_offset < 12 or lookup_offset > length or length - lookup_offset < 2) return error.BadSfnt;
    if (glyph_data_offset < 12 or glyph_data_offset > length) return error.BadSfnt;
    return .{ .version = version, .flags = flags, .lookup_offset = lookup_offset, .glyph_data_offset = glyph_data_offset };
}

const LookupInfo = struct {
    format: u16,
    offset: usize,
    end_offset: usize,
};

fn lookupInfo(data: []const u8, table_offset: usize, table_length: usize, lookup_offset: usize, glyph_count: usize) Error!LookupInfo {
    const start = table_offset + lookup_offset;
    const format = try bin.readU16At(data, start);
    const end_offset = switch (format) {
        0 => try validateLookupFormat0(table_length, lookup_offset, glyph_count),
        2 => try validateSegmentLookup(data, table_offset, table_length, lookup_offset, glyph_count, 6, 2),
        4 => try validateSegmentArrayLookup(data, table_offset, table_length, lookup_offset, glyph_count),
        6 => try validateSingleLookup(data, table_offset, table_length, lookup_offset, glyph_count),
        8 => try validateTrimmedLookup(data, table_offset, table_length, lookup_offset, glyph_count),
        else => return error.BadSfnt,
    };
    return .{ .format = format, .offset = lookup_offset, .end_offset = end_offset };
}

fn validateLookupFormat0(table_length: usize, lookup_offset: usize, glyph_count: usize) Error!usize {
    if (glyph_count > (table_length - lookup_offset - 2) / 2) return error.BadSfnt;
    return lookup_offset + 2 + glyph_count * 2;
}

const SearchHeader = struct {
    unit_size: usize,
    n_units: usize,
    entries_offset: usize,
    entries_end: usize,
};

fn searchHeader(data: []const u8, table_offset: usize, table_length: usize, lookup_offset: usize, min_unit_size: usize) Error!SearchHeader {
    if (table_length - lookup_offset < 12) return error.BadSfnt;
    const header_start = table_offset + lookup_offset + 2;
    const unit_size: usize = @intCast(try bin.readU16At(data, header_start));
    const n_units: usize = @intCast(try bin.readU16At(data, header_start + 2));
    const search_range: usize = @intCast(try bin.readU16At(data, header_start + 4));
    const entry_selector: usize = @intCast(try bin.readU16At(data, header_start + 6));
    const range_shift: usize = @intCast(try bin.readU16At(data, header_start + 8));
    if (unit_size < min_unit_size) return error.BadSfnt;
    try validateSearchParameters(unit_size, n_units, search_range, entry_selector, range_shift);
    if (n_units > (table_length - lookup_offset - 12) / unit_size) return error.BadSfnt;
    return .{
        .unit_size = unit_size,
        .n_units = n_units,
        .entries_offset = lookup_offset + 12,
        .entries_end = lookup_offset + 12 + n_units * unit_size,
    };
}

fn validateSearchParameters(unit_size: usize, n_units: usize, search_range: usize, entry_selector: usize, range_shift: usize) Error!void {
    const power = floorPowerOfTwo(n_units);
    var selector: usize = 0;
    var tmp = power;
    while (tmp > 1) : (tmp >>= 1) selector += 1;
    const expected_search_range = unit_size * power;
    const expected_range_shift = unit_size * (n_units - power);
    if (search_range != expected_search_range or entry_selector != selector or range_shift != expected_range_shift) return error.BadSfnt;
}

fn floorPowerOfTwo(value: usize) usize {
    if (value == 0) return 0;
    var power: usize = 1;
    while (power <= value / 2) power *= 2;
    return power;
}

fn activeUnitCount(data: []const u8, table_offset: usize, search: SearchHeader, termination_word_count: usize) Error!usize {
    if (search.n_units == 0) return 0;
    const last = table_offset + search.entries_offset + (search.n_units - 1) * search.unit_size;
    var terminator = true;
    for (0..termination_word_count) |index| {
        if (try bin.readU16At(data, last + index * 2) != 0xffff) terminator = false;
    }
    return search.n_units - @intFromBool(terminator);
}

fn validateSegmentLookup(data: []const u8, table_offset: usize, table_length: usize, lookup_offset: usize, glyph_count: usize, min_unit_size: usize, termination_word_count: usize) Error!usize {
    const h = try searchHeader(data, table_offset, table_length, lookup_offset, min_unit_size);
    const count = try activeUnitCount(data, table_offset, h, termination_word_count);
    var previous_last: ?u16 = null;
    for (0..count) |index| {
        const entry = table_offset + h.entries_offset + index * h.unit_size;
        const last = try bin.readU16At(data, entry);
        const first = try bin.readU16At(data, entry + 2);
        if (first > last or last >= glyph_count) return error.BadSfnt;
        if (previous_last) |prev| if (first <= prev) return error.BadSfnt;
        previous_last = last;
    }
    return h.entries_end;
}

fn validateSegmentArrayLookup(data: []const u8, table_offset: usize, table_length: usize, lookup_offset: usize, glyph_count: usize) Error!usize {
    const h = try searchHeader(data, table_offset, table_length, lookup_offset, 6);
    const count = try activeUnitCount(data, table_offset, h, 2);
    var previous_last: ?u16 = null;
    var end_offset = h.entries_end;
    for (0..count) |index| {
        const entry = table_offset + h.entries_offset + index * h.unit_size;
        const last = try bin.readU16At(data, entry);
        const first = try bin.readU16At(data, entry + 2);
        const values_offset: usize = @intCast(try bin.readU16At(data, entry + 4));
        if (first > last or last >= glyph_count) return error.BadSfnt;
        if (previous_last) |prev| if (first <= prev) return error.BadSfnt;
        previous_last = last;
        const value_count = @as(usize, last - first) + 1;
        if (values_offset > table_length - lookup_offset or value_count > (table_length - lookup_offset - values_offset) / 2) return error.BadSfnt;
        end_offset = @max(end_offset, lookup_offset + values_offset + value_count * 2);
    }
    return end_offset;
}

fn validateSingleLookup(data: []const u8, table_offset: usize, table_length: usize, lookup_offset: usize, glyph_count: usize) Error!usize {
    const h = try searchHeader(data, table_offset, table_length, lookup_offset, 4);
    const count = try activeUnitCount(data, table_offset, h, 1);
    var previous_glyph: ?u16 = null;
    for (0..count) |index| {
        const entry = table_offset + h.entries_offset + index * h.unit_size;
        const glyph = try bin.readU16At(data, entry);
        if (glyph >= glyph_count) return error.BadSfnt;
        if (previous_glyph) |prev| if (glyph <= prev) return error.BadSfnt;
        previous_glyph = glyph;
    }
    return h.entries_end;
}

fn validateTrimmedLookup(data: []const u8, table_offset: usize, table_length: usize, lookup_offset: usize, glyph_count: usize) Error!usize {
    if (table_length - lookup_offset < 6) return error.BadSfnt;
    const start = table_offset + lookup_offset;
    const first: usize = @intCast(try bin.readU16At(data, start + 2));
    const count: usize = @intCast(try bin.readU16At(data, start + 4));
    if (count != 0 and (first >= glyph_count or count > glyph_count - first)) return error.BadSfnt;
    if (count > (table_length - lookup_offset - 6) / 2) return error.BadSfnt;
    return lookup_offset + 6 + count * 2;
}

fn walkLookup(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_data_offset: usize,
    lookup: LookupInfo,
    glyph_count: usize,
    allocator: ?std.mem.Allocator,
    out: ?*std.ArrayList(GlyphAnchors),
) Error!void {
    const start = table_offset + lookup.offset;
    switch (lookup.format) {
        0 => for (0..glyph_count) |glyph| {
            const value_offset: usize = @intCast(try bin.readU16At(data, start + 2 + glyph * 2));
            try handleGlyph(data, table_offset, table_length, glyph_data_offset, @intCast(glyph), value_offset, allocator, out);
        },
        2 => try walkSegmentLookup(data, table_offset, table_length, glyph_data_offset, lookup.offset, glyph_count, allocator, out),
        4 => try walkSegmentArrayLookup(data, table_offset, table_length, glyph_data_offset, lookup.offset, glyph_count, allocator, out),
        6 => try walkSingleLookup(data, table_offset, table_length, glyph_data_offset, lookup.offset, glyph_count, allocator, out),
        8 => try walkTrimmedLookup(data, table_offset, table_length, glyph_data_offset, lookup.offset, glyph_count, allocator, out),
        else => return error.BadSfnt,
    }
}

fn walkSegmentLookup(data: []const u8, table_offset: usize, table_length: usize, glyph_data_offset: usize, lookup_offset: usize, glyph_count: usize, allocator: ?std.mem.Allocator, out: ?*std.ArrayList(GlyphAnchors)) Error!void {
    const h = try searchHeader(data, table_offset, table_length, lookup_offset, 6);
    const count = try activeUnitCount(data, table_offset, h, 2);
    for (0..count) |index| {
        const entry = table_offset + h.entries_offset + index * h.unit_size;
        const last = try bin.readU16At(data, entry);
        const first = try bin.readU16At(data, entry + 2);
        const value_offset: usize = @intCast(try bin.readU16At(data, entry + 4));
        var glyph = first;
        while (glyph <= last) : (glyph += 1) try handleGlyph(data, table_offset, table_length, glyph_data_offset, glyph, value_offset, allocator, out);
        _ = glyph_count;
    }
}

fn walkSegmentArrayLookup(data: []const u8, table_offset: usize, table_length: usize, glyph_data_offset: usize, lookup_offset: usize, glyph_count: usize, allocator: ?std.mem.Allocator, out: ?*std.ArrayList(GlyphAnchors)) Error!void {
    const h = try searchHeader(data, table_offset, table_length, lookup_offset, 6);
    const count = try activeUnitCount(data, table_offset, h, 2);
    for (0..count) |index| {
        const entry = table_offset + h.entries_offset + index * h.unit_size;
        const last = try bin.readU16At(data, entry);
        const first = try bin.readU16At(data, entry + 2);
        const values_offset: usize = @intCast(try bin.readU16At(data, entry + 4));
        var glyph = first;
        while (glyph <= last) : (glyph += 1) {
            const value_offset: usize = @intCast(try bin.readU16At(data, table_offset + lookup_offset + values_offset + (@as(usize, glyph - first) * 2)));
            try handleGlyph(data, table_offset, table_length, glyph_data_offset, glyph, value_offset, allocator, out);
        }
        _ = glyph_count;
    }
}

fn walkSingleLookup(data: []const u8, table_offset: usize, table_length: usize, glyph_data_offset: usize, lookup_offset: usize, glyph_count: usize, allocator: ?std.mem.Allocator, out: ?*std.ArrayList(GlyphAnchors)) Error!void {
    const h = try searchHeader(data, table_offset, table_length, lookup_offset, 4);
    const count = try activeUnitCount(data, table_offset, h, 1);
    for (0..count) |index| {
        const entry = table_offset + h.entries_offset + index * h.unit_size;
        const glyph = try bin.readU16At(data, entry);
        const value_offset: usize = @intCast(try bin.readU16At(data, entry + 2));
        try handleGlyph(data, table_offset, table_length, glyph_data_offset, glyph, value_offset, allocator, out);
        _ = glyph_count;
    }
}

fn walkTrimmedLookup(data: []const u8, table_offset: usize, table_length: usize, glyph_data_offset: usize, lookup_offset: usize, glyph_count: usize, allocator: ?std.mem.Allocator, out: ?*std.ArrayList(GlyphAnchors)) Error!void {
    const start = table_offset + lookup_offset;
    const first = try bin.readU16At(data, start + 2);
    const count = try bin.readU16At(data, start + 4);
    for (0..count) |index| {
        const glyph: u16 = first + @as(u16, @intCast(index));
        const value_offset: usize = @intCast(try bin.readU16At(data, start + 6 + index * 2));
        try handleGlyph(data, table_offset, table_length, glyph_data_offset, glyph, value_offset, allocator, out);
        _ = glyph_count;
    }
}

fn handleGlyph(data: []const u8, table_offset: usize, table_length: usize, glyph_data_offset: usize, glyph_id: u16, value_offset: usize, allocator: ?std.mem.Allocator, out: ?*std.ArrayList(GlyphAnchors)) Error!void {
    try validateGlyphAnchors(data, table_offset, table_length, glyph_data_offset, value_offset);
    if (out) |records| {
        try appendGlyphAnchors(allocator.?, records, data, table_offset, glyph_data_offset, glyph_id, value_offset);
    }
}

fn validateGlyphAnchors(data: []const u8, table_offset: usize, table_length: usize, glyph_data_offset: usize, value_offset: usize) Error!void {
    if (value_offset > table_length - glyph_data_offset or table_length - glyph_data_offset - value_offset < 4) return error.BadSfnt;
    const entry = table_offset + glyph_data_offset + value_offset;
    const count: usize = @intCast(try bin.readU32At(data, entry));
    if (count > (table_offset + table_length - entry - 4) / 4) return error.BadSfnt;
}

fn appendGlyphAnchors(allocator: std.mem.Allocator, out: *std.ArrayList(GlyphAnchors), data: []const u8, table_offset: usize, glyph_data_offset: usize, glyph_id: u16, value_offset: usize) Error!void {
    const entry = table_offset + glyph_data_offset + value_offset;
    const count: usize = @intCast(try bin.readU32At(data, entry));
    const anchors = try allocator.alloc(Anchor, count);
    errdefer allocator.free(anchors);
    for (anchors, 0..) |*anchor, index| {
        const anchor_offset = entry + 4 + index * 4;
        anchor.* = .{ .x = try bin.readI16At(data, anchor_offset), .y = try bin.readI16At(data, anchor_offset + 2) };
    }
    try out.append(allocator, .{ .glyph_id = glyph_id, .data_offset = value_offset, .anchors = anchors });
}

test "ankr format 6 lookup exposes glyph anchors" {
    var bytes: [52]u8 = .{0} ** 52;
    writeU32(&bytes, 4, 12);
    writeU32(&bytes, 8, 32);
    writeU16(&bytes, 12, 6);
    writeSearchHeader(&bytes, 14, 4, 2, 8, 1, 0);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 0);
    writeU16(&bytes, 28, 2);
    writeU16(&bytes, 30, 12);
    writeU32(&bytes, 32, 2);
    writeI16(&bytes, 36, 10);
    writeI16(&bytes, 38, 20);
    writeI16(&bytes, 40, -5);
    writeI16(&bytes, 42, 7);
    writeU32(&bytes, 44, 1);
    writeI16(&bytes, 48, 100);
    writeI16(&bytes, 50, -50);

    try validate(&bytes, 0, bytes.len, 3);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 3);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u16, 6), parsed.lookup_format);
    try std.testing.expectEqual(@as(usize, 2), parsed.glyphs.len);
    try std.testing.expectEqual(@as(u16, 1), parsed.glyphs[0].glyph_id);
    try std.testing.expectEqual(@as(usize, 2), parsed.glyphs[0].anchors.len);
    try std.testing.expectEqual(Anchor{ .x = 10, .y = 20 }, parsed.glyphs[0].anchors[0]);
    try std.testing.expectEqual(@as(u16, 2), parsed.glyphs[1].glyph_id);
    try std.testing.expectEqual(Anchor{ .x = 100, .y = -50 }, parsed.glyphs[1].anchors[0]);
}

test "ankr rejects out-of-range glyph data offsets" {
    var bytes: [40]u8 = .{0} ** 40;
    writeU32(&bytes, 4, 12);
    writeU32(&bytes, 8, 32);
    writeU16(&bytes, 12, 6);
    writeSearchHeader(&bytes, 14, 4, 1, 4, 0, 0);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 20);
    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 2));
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

fn writeSearchHeader(bytes: []u8, offset: usize, unit_size: u16, n_units: u16, search_range: u16, entry_selector: u16, range_shift: u16) void {
    writeU16(bytes, offset + 0, unit_size);
    writeU16(bytes, offset + 2, n_units);
    writeU16(bytes, offset + 4, search_range);
    writeU16(bytes, offset + 6, entry_selector);
    writeU16(bytes, offset + 8, range_shift);
}
