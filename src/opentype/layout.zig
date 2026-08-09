const std = @import("std");

pub const GlyphId = u16;

pub const GlyphRangeRecord = struct {
    start: GlyphId,
    end: GlyphId,
    value: u16,
};

const RangeError = error{
    EndOfStream,
};

const ScriptError = RangeError || error{
    InvalidLayoutTable,
};

pub const ScriptSelection = struct {
    tag: ?u32 = null,
    requested: bool = false,
};

/// Select a ScriptList tag using HarfBuzz's requested/fallback order.
///
/// `requested_tags` is ordered by the Unicode-script mapping (for example
/// `dev3`, `dev2`, `deva`). If none exist, OpenType's conventional fallback
/// tags are tried. The `requested` bit is needed by the shaping planner:
/// selecting `dev3` activates USE, while falling back to DFLT/latn must not.
pub fn selectScriptTag(table: []const u8, requested_tags: []const u32) ScriptError!ScriptSelection {
    if (table.len < 10) return error.InvalidLayoutTable;
    const major = try readU16(table, 0);
    if (major != 1) return error.InvalidLayoutTable;
    const script_list_offset = try readU16(table, 4);
    if (script_list_offset == 0 or script_list_offset > table.len or table.len - script_list_offset < 2) {
        return error.InvalidLayoutTable;
    }
    const script_count = try readU16(table, script_list_offset);
    if (@as(usize, script_count) > (table.len - script_list_offset - 2) / 6) return error.InvalidLayoutTable;

    for (requested_tags) |script_tag| {
        if (try scriptListContains(table, script_list_offset, script_count, script_tag)) {
            return .{ .tag = script_tag, .requested = true };
        }
    }
    for ([_]u32{
        tag("DFLT"),
        tag("dflt"),
        tag("latn"),
    }) |fallback_tag| {
        if (try scriptListContains(table, script_list_offset, script_count, fallback_tag)) {
            return .{ .tag = fallback_tag };
        }
    }
    return .{};
}

fn scriptListContains(table: []const u8, script_list_offset: usize, script_count: u16, target: u32) ScriptError!bool {
    for (0..script_count) |script_i| {
        const record = script_list_offset + 2 + script_i * 6;
        const script_tag = try readU32(table, record);
        const child_offset = try readU16(table, record + 4);
        if (child_offset == 0 or child_offset > table.len - script_list_offset) return error.InvalidLayoutTable;
        if (script_tag == target) return true;
    }
    return false;
}

fn tag(comptime text: *const [4:0]u8) u32 {
    return (@as(u32, text[0]) << 24) |
        (@as(u32, text[1]) << 16) |
        (@as(u32, text[2]) << 8) |
        @as(u32, text[3]);
}

pub fn findSortedGlyphRangeRecord(data: []const u8, records_offset: usize, range_count: u16, glyph: GlyphId) RangeError!?GlyphRangeRecord {
    // Coverage format 2 and ClassDef format 2 both use sorted, non-overlapping
    // glyph ranges with a u16 payload in the third field. Search by range end
    // so inclusive boundaries and adjacent malformed overlaps preserve the old
    // first-match result for callers that incorrectly skip validation.
    var lo: usize = 0;
    var hi: usize = range_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const record_offset = records_offset + mid * 6;
        const end = try readU16(data, record_offset + 2);
        if (glyph <= end) {
            hi = mid;
        } else {
            lo = mid + 1;
        }
    }
    if (lo >= range_count) return null;
    const record_offset = records_offset + lo * 6;
    const record = GlyphRangeRecord{
        .start = try readU16(data, record_offset),
        .end = try readU16(data, record_offset + 2),
        .value = try readU16(data, record_offset + 4),
    };
    return if (glyph >= record.start) record else null;
}

fn readU16(data: []const u8, offset: usize) RangeError!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) RangeError!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "sorted glyph range record search handles boundaries and gaps" {
    var bytes = [_]u8{0} ** (4 * 6);
    writeRangeRecordTest(&bytes, 0, 3, 4, 10);
    writeRangeRecordTest(&bytes, 6, 8, 12, 20);
    writeRangeRecordTest(&bytes, 12, 20, 25, 30);
    writeRangeRecordTest(&bytes, 18, 40, 50, 40);

    try std.testing.expectEqual(@as(?GlyphRangeRecord, .{ .start = 3, .end = 4, .value = 10 }), try findSortedGlyphRangeRecord(&bytes, 0, 4, 3));
    try std.testing.expectEqual(@as(?GlyphRangeRecord, .{ .start = 3, .end = 4, .value = 10 }), try findSortedGlyphRangeRecord(&bytes, 0, 4, 4));
    try std.testing.expectEqual(@as(?GlyphRangeRecord, null), try findSortedGlyphRangeRecord(&bytes, 0, 4, 5));
    try std.testing.expectEqual(@as(?GlyphRangeRecord, .{ .start = 8, .end = 12, .value = 20 }), try findSortedGlyphRangeRecord(&bytes, 0, 4, 12));
    try std.testing.expectEqual(@as(?GlyphRangeRecord, null), try findSortedGlyphRangeRecord(&bytes, 0, 4, 39));
    try std.testing.expectEqual(@as(?GlyphRangeRecord, .{ .start = 40, .end = 50, .value = 40 }), try findSortedGlyphRangeRecord(&bytes, 0, 4, 50));
    try std.testing.expectEqual(@as(?GlyphRangeRecord, null), try findSortedGlyphRangeRecord(&bytes, 0, 4, 51));
}

test "sorted glyph range record search keeps first adjacent overlap" {
    var bytes = [_]u8{0} ** (3 * 6);
    writeRangeRecordTest(&bytes, 0, 10, 12, 1);
    writeRangeRecordTest(&bytes, 6, 12, 14, 2);
    writeRangeRecordTest(&bytes, 12, 20, 18, 3);

    try std.testing.expectEqual(@as(?GlyphRangeRecord, .{ .start = 10, .end = 12, .value = 1 }), try findSortedGlyphRangeRecord(&bytes, 0, 3, 12));
}

test "layout script selection prefers requested generations before fallbacks" {
    var bytes = [_]u8{0} ** 48;
    std.mem.writeInt(u32, bytes[0..4], 0x00010000, .big);
    std.mem.writeInt(u16, bytes[4..6], 10, .big);
    std.mem.writeInt(u16, bytes[10..12], 3, .big);
    const script_tags = [_]u32{ tag("DFLT"), tag("dev2"), tag("dev3") };
    for (script_tags, 0..) |script_tag, index| {
        const record = 12 + index * 6;
        std.mem.writeInt(u32, bytes[record..][0..4], script_tag, .big);
        std.mem.writeInt(u16, bytes[record + 4 ..][0..2], @intCast(20 + index * 4), .big);
    }

    const selected = try selectScriptTag(&bytes, &.{ tag("dev3"), tag("dev2"), tag("deva") });
    try std.testing.expectEqual(@as(?u32, tag("dev3")), selected.tag);
    try std.testing.expect(selected.requested);

    const fallback = try selectScriptTag(&bytes, &.{tag("bng3")});
    try std.testing.expectEqual(@as(?u32, tag("DFLT")), fallback.tag);
    try std.testing.expect(!fallback.requested);
}

fn writeRangeRecordTest(bytes: []u8, offset: usize, start: GlyphId, end: GlyphId, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], start, .big);
    std.mem.writeInt(u16, bytes[offset + 2 ..][0..2], end, .big);
    std.mem.writeInt(u16, bytes[offset + 4 ..][0..2], value, .big);
}
