//! Apple/OpenType `sbix` strike parsing and duplicate-glyph resolution.

const std = @import("std");

const bin = @import("../../../binary.zig");
const glyph = @import("../../../glyph.zig");
const png = @import("png.zig");
const types = @import("types.zig");

pub const Strike = struct {
    ppem: u16,
    ppi: u16,
    offset: usize,
    length: usize,
    bitmap_data_offset: usize,
};

const GlyphRecord = struct {
    glyph_start: usize,
    origin_offset_x: i16,
    origin_offset_y: i16,
    graphic_type: [4]u8,
    payload: []const u8,
};

pub const DupeNode = struct {
    target: ?glyph.GlyphId = null,
    state: enum(u2) {
        unseen,
        active,
        resolved,
    } = .unseen,
};

pub fn strikeCount(
    data: []const u8,
    table: types.Table,
) types.Error!usize {
    if (table.length < 8) return error.BadSfnt;
    const version = try bin.readU16At(data, table.offset);
    if (version != 1) return error.BadSfnt;
    const count = try bin.readU32At(data, table.offset + 4);
    if (@as(usize, count) * 4 > table.length - 8) return error.BadSfnt;
    return @intCast(count);
}

pub fn strike(
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
    strike_index: usize,
) types.Error!Strike {
    const strike_count = try strikeCount(data, table);
    if (strike_index >= strike_count) return error.BadSfnt;
    const offset =
        try bin.readU32At(data, table.offset + 8 + strike_index * 4);
    // A strike target inside the header/offset array would reinterpret table
    // metadata as ppem, ppi, and per-glyph offsets.
    const minimum_strike_offset = 8 + strike_count * 4;
    if (offset < minimum_strike_offset or offset >= table.length) {
        return error.BadSfnt;
    }
    const next_offset = if (strike_index + 1 < strike_count)
        try bin.readU32At(data, table.offset + 8 + (strike_index + 1) * 4)
    else
        @as(u32, @intCast(table.length));
    if (next_offset < offset or next_offset > table.length) {
        return error.BadSfnt;
    }

    const absolute = table.offset + offset;
    const length = @as(usize, next_offset - offset);
    const offsets_len = (@as(usize, glyph_count) + 1) * 4;
    if (length < 4 + offsets_len) return error.BadSfnt;
    return .{
        .ppem = try bin.readU16At(data, absolute),
        .ppi = try bin.readU16At(data, absolute + 2),
        .offset = absolute,
        .length = length,
        .bitmap_data_offset = 4 + offsets_len,
    };
}

pub fn glyphInfo(
    data: []const u8,
    selected_strike: Strike,
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!?types.GlyphInfo {
    const record =
        (try resolveGlyphRecord(data, selected_strike, glyph_id, glyph_count)) orelse
        return null;
    const is_png = bin.tagEq(record.graphic_type, "png ");
    const dimensions = if (is_png)
        try png.validate(record.payload)
    else
        png.Dimensions{ .width = 0, .height = 0 };
    return .{
        .source = .sbix,
        .glyph_id = glyph_id,
        .ppem = selected_strike.ppem,
        .ppi = selected_strike.ppi,
        // A `dupe` selects the target image record in full. FreeType and
        // HarfBuzz therefore use that final record's placement as well.
        .origin_offset_x = record.origin_offset_x,
        .origin_offset_y = record.origin_offset_y,
        .width = dimensions.width,
        .height = dimensions.height,
        .data_offset = record.glyph_start + 8,
        .data_length = record.payload.len,
        .is_png = is_png,
    };
}

pub fn glyphPng(
    data: []const u8,
    selected_strike: Strike,
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!?types.GlyphPng {
    const record =
        (try resolveGlyphRecord(data, selected_strike, glyph_id, glyph_count)) orelse
        return null;
    if (!bin.tagEq(record.graphic_type, "png ")) return null;
    return try png.glyph(
        record.payload,
        .sbix,
        selected_strike.ppem,
        selected_strike.ppi,
        record.origin_offset_x,
        record.origin_offset_y,
    );
}

pub fn glyphPngAfterProof(
    data: []const u8,
    selected_strike: Strike,
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!?types.GlyphPng {
    const record =
        (try resolveGlyphRecord(data, selected_strike, glyph_id, glyph_count)) orelse
        return null;
    if (!bin.tagEq(record.graphic_type, "png ")) return null;
    const dimensions = try png.dimensionsAfterProof(record.payload);
    return png.glyphAfterProof(
        record.payload,
        .sbix,
        selected_strike.ppem,
        selected_strike.ppi,
        record.origin_offset_x,
        record.origin_offset_y,
        dimensions.width,
        dimensions.height,
    );
}

pub fn validate(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: types.Table,
    glyph_count: u16,
) types.Error!void {
    const strike_count = try strikeCount(data, table);
    for (0..strike_count) |strike_index| {
        const current = try strike(data, table, glyph_count, strike_index);
        try validateStrikeGlyphOffsets(data, current, glyph_count);
        try validateStrikeBitmapPayloads(
            allocator,
            data,
            current,
            glyph_count,
        );
    }
}

fn glyphRecord(
    data: []const u8,
    selected_strike: Strike,
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!?GlyphRecord {
    if (glyph_id >= glyph_count) return error.BadSfnt;
    const glyph_offset_pos =
        selected_strike.offset + 4 + @as(usize, glyph_id) * 4;
    const start = try bin.readU32At(data, glyph_offset_pos);
    const end = try bin.readU32At(data, glyph_offset_pos + 4);
    if (start < selected_strike.bitmap_data_offset or
        end < selected_strike.bitmap_data_offset)
    {
        return error.BadSfnt;
    }
    if (end < start or end > selected_strike.length) return error.BadSfnt;
    if (end == start) return null;
    if (end - start < 8) return error.BadSfnt;

    const glyph_start = selected_strike.offset + start;
    const glyph_end = selected_strike.offset + end;
    return .{
        .glyph_start = glyph_start,
        .origin_offset_x = try bin.readI16At(data, glyph_start),
        .origin_offset_y = try bin.readI16At(data, glyph_start + 2),
        .graphic_type = try bin.readTagAt(data, glyph_start + 4),
        .payload = data[glyph_start + 8 .. glyph_end],
    };
}

fn resolveGlyphRecord(
    data: []const u8,
    selected_strike: Strike,
    glyph_id: glyph.GlyphId,
    glyph_count: u16,
) types.Error!?GlyphRecord {
    var current = glyph_id;
    var remaining: usize = glyph_count;
    while (true) {
        const record =
            (try glyphRecord(data, selected_strike, current, glyph_count)) orelse
            return null;
        if (!bin.tagEq(record.graphic_type, "dupe")) return record;

        // `dupe` is exactly one big-endian glyph ID; trailing bytes are not a
        // private extension grammar.
        if (record.payload.len != 2) return error.BadSfnt;
        current = try bin.readU16At(record.payload, 0);
        if (current >= glyph_count) return error.BadSfnt;

        // Following more than glyph_count edges in this finite functional graph
        // proves that an active node repeated.
        if (remaining == 0) return error.BadSfnt;
        remaining -= 1;
    }
}

fn validateStrikeGlyphOffsets(
    data: []const u8,
    selected_strike: Strike,
    glyph_count: u16,
) types.Error!void {
    var previous = try bin.readU32At(data, selected_strike.offset + 4);
    if (previous < selected_strike.bitmap_data_offset or
        previous > selected_strike.length)
    {
        return error.BadSfnt;
    }

    for (0..glyph_count) |glyph_index| {
        const offset_pos =
            selected_strike.offset + 4 + (glyph_index + 1) * 4;
        const current = try bin.readU32At(data, offset_pos);
        // Prove the complete monotonic boundary array, including glyphs that a
        // caller may never request.
        if (current < previous) return error.BadSfnt;
        if (current < selected_strike.bitmap_data_offset or
            current > selected_strike.length)
        {
            return error.BadSfnt;
        }
        if (current != previous and current - previous < 8) {
            return error.BadSfnt;
        }
        previous = current;
    }
}

fn validateStrikeBitmapPayloads(
    allocator: std.mem.Allocator,
    data: []const u8,
    selected_strike: Strike,
    glyph_count: u16,
) types.Error!void {
    // Direct images dominate real fonts. Allocate graph scratch only after the
    // first `dupe`, preserving an allocation-free ordinary validation path.
    var maybe_dupe_nodes: ?[]DupeNode = null;
    defer if (maybe_dupe_nodes) |nodes| allocator.free(nodes);

    for (0..glyph_count) |glyph_index| {
        const record = (try glyphRecord(
            data,
            selected_strike,
            @intCast(glyph_index),
            glyph_count,
        )) orelse continue;
        if (bin.tagEq(record.graphic_type, "png ")) {
            _ = try png.validate(record.payload);
        } else if (bin.tagEq(record.graphic_type, "dupe")) {
            if (record.payload.len != 2) return error.BadSfnt;
            const target = try bin.readU16At(record.payload, 0);
            if (target >= glyph_count) return error.BadSfnt;
            if (maybe_dupe_nodes == null) {
                const nodes = try allocator.alloc(DupeNode, glyph_count);
                @memset(nodes, .{});
                maybe_dupe_nodes = nodes;
            }
            maybe_dupe_nodes.?[glyph_index].target = target;
        }
    }

    if (maybe_dupe_nodes) |nodes| try validateDupeGraph(nodes);
}

pub fn validateDupeGraph(nodes: []DupeNode) types.Error!void {
    // State and edge share one array. Because this is a functional graph,
    // replaying a chain can resolve it without a second O(glyph_count) stack.
    for (nodes, 0..) |_, start_index| {
        if (nodes[start_index].state == .resolved) continue;
        var current: glyph.GlyphId = @intCast(start_index);
        while (true) {
            if (nodes[current].state == .resolved) break;
            if (nodes[current].state == .active) return error.BadSfnt;
            nodes[current].state = .active;
            current = nodes[current].target orelse break;
        }

        current = @intCast(start_index);
        while (nodes[current].state == .active) {
            nodes[current].state = .resolved;
            current = nodes[current].target orelse break;
        }
    }
}

test "sbix offsets cannot overlap table or strike metadata" {
    var table_overlap: [32]u8 = .{0} ** 32;
    writeU16(&table_overlap, 0, 1); // version
    writeU32(&table_overlap, 4, 1); // one strike offset follows
    writeU32(&table_overlap, 8, 8); // Points at the strike-offset array.
    const sbix = types.Table{ .offset = 0, .length = table_overlap.len };
    try std.testing.expectError(error.BadSfnt, strike(&table_overlap, sbix, 1, 0));

    var glyph_overlap: [48]u8 = .{0} ** 48;
    writeU16(&glyph_overlap, 0, 1); // version
    writeU32(&glyph_overlap, 4, 1);
    writeU32(&glyph_overlap, 8, 12); // First strike begins after sbix metadata.
    writeU16(&glyph_overlap, 12, 16); // ppem
    writeU16(&glyph_overlap, 14, 72); // ppi
    writeU32(&glyph_overlap, 16, 4); // Non-empty glyph points back into the offset array.
    writeU32(&glyph_overlap, 20, 20);

    const selected_strike = try strike(&glyph_overlap, sbix, 1, 0);
    try std.testing.expectError(error.BadSfnt, glyphPng(&glyph_overlap, selected_strike, 0, 1));
}

test "sbix parse validation checks every strike glyph offset" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1); // sbix version
    writeU32(&bytes, 4, 1); // one strike
    writeU32(&bytes, 8, 12); // strike data starts after the strike-offset array
    writeU16(&bytes, 12, 16); // ppem
    writeU16(&bytes, 14, 72); // ppi

    const sbix = types.Table{ .offset = 0, .length = bytes.len };

    // Two glyphs require three offsets. The second glyph is "unused" for many
    // runtime lookups, but parse-time validation must still reject its
    // decreasing boundary so malformed payloads cannot hide behind glyph choice.
    writeU32(&bytes, 16, 24);
    writeU32(&bytes, 20, 32);
    writeU32(&bytes, 24, 28);
    try std.testing.expectError(error.BadSfnt, validate(std.testing.allocator, &bytes, sbix, 2));

    writeU32(&bytes, 24, 36); // Non-empty glyph payload is shorter than the sbix origin+type header.
    try std.testing.expectError(error.BadSfnt, validate(std.testing.allocator, &bytes, sbix, 2));

    writeU32(&bytes, 24, 40);
    try validate(std.testing.allocator, &bytes, sbix, 2);
}

test "sbix dupe graph accepts shared chains and rejects cycles" {
    // Longer than HarfBuzz's current retry cap: a finite, acyclic chain is
    // valid regardless of depth and should not be rejected arbitrarily.
    var valid = [_]DupeNode{
        .{ .target = 2 },
        .{ .target = 2 },
        .{ .target = 3 },
        .{ .target = 4 },
        .{ .target = 5 },
        .{ .target = 6 },
        .{ .target = 7 },
        .{ .target = 8 },
        .{ .target = 9 },
        .{ .target = 10 },
        .{ .target = 11 },
        .{},
    };
    try validateDupeGraph(&valid);

    var self_cycle = [_]DupeNode{.{ .target = 0 }};
    try std.testing.expectError(error.BadSfnt, validateDupeGraph(&self_cycle));

    var indirect_cycle = [_]DupeNode{ .{ .target = 1 }, .{ .target = 2 }, .{ .target = 0 } };
    try std.testing.expectError(error.BadSfnt, validateDupeGraph(&indirect_cycle));
}

test "sbix dupe records require one in-range glyph id" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 4, 1);
    writeU32(&bytes, 8, 12);
    writeU16(&bytes, 12, 16);
    writeU16(&bytes, 14, 72);
    writeU32(&bytes, 16, 16);
    writeU32(&bytes, 20, 26);
    writeU32(&bytes, 24, 36);
    writeTag(&bytes, 28 + 4, "dupe");
    writeU16(&bytes, 28 + 8, 1);
    writeTag(&bytes, 38 + 4, "dupe");
    writeU16(&bytes, 38 + 8, 0);

    const sbix = types.Table{ .offset = 0, .length = 52 };
    try std.testing.expectError(error.BadSfnt, validate(std.testing.allocator, &bytes, sbix, 2));

    // Break the cycle, but make the remaining reference out of range.
    writeTag(&bytes, 38 + 4, "jpg ");
    writeU16(&bytes, 28 + 8, 2);
    try std.testing.expectError(error.BadSfnt, validate(std.testing.allocator, &bytes, sbix, 2));

    // A dupe payload must not carry ignored trailing bytes.
    writeU16(&bytes, 28 + 8, 1);
    writeU32(&bytes, 20, 28);
    writeU32(&bytes, 24, 38);
    try std.testing.expectError(error.BadSfnt, validate(std.testing.allocator, &bytes, sbix, 2));
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeTag(bytes: []u8, offset: usize, value: []const u8) void {
    @memcpy(bytes[offset .. offset + 4], value[0..4]);
}
