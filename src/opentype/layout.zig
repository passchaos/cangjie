const std = @import("std");

pub const GlyphId = u16;

pub const GlyphRangeRecord = struct {
    start: GlyphId,
    end: GlyphId,
    value: u16,
};

const LayoutError = error{
    EndOfStream,
};

pub fn findSortedGlyphRangeRecord(data: []const u8, records_offset: usize, range_count: u16, glyph: GlyphId) LayoutError!?GlyphRangeRecord {
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

fn readU16(data: []const u8, offset: usize) LayoutError!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
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

fn writeRangeRecordTest(bytes: []u8, offset: usize, start: GlyphId, end: GlyphId, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], start, .big);
    std.mem.writeInt(u16, bytes[offset + 2 ..][0..2], end, .big);
    std.mem.writeInt(u16, bytes[offset + 4 ..][0..2], value, .big);
}
