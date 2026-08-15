//! OpenType SVG directory, glyph range, and byte ownership validation.

const std = @import("std");

const svg = @import("../root.zig");

test "SVG document glyph ranges stay within maxp glyph count" {
    var bytes: [30]u8 = .{0} ** 30;
    writeU16(&bytes, 0, 0); // SVG table version.
    writeU32(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16(&bytes, 12, 1); // startGlyphID.
    writeU16(&bytes, 14, 2); // endGlyphID is invalid when maxp.numGlyphs == 2.
    writeU32(&bytes, 16, 14); // document data starts after the record array.
    writeU32(&bytes, 20, 6);
    @memcpy(bytes[24..30], "<svg/>");

    const table = svg.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &bytes, table, 2));

    writeU16(&bytes, 14, 1);
    try svg.validate(std.testing.allocator, &bytes, table, 2);
}

test "SVG document glyph ranges must be sorted and disjoint" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 0); // SVG table version.
    writeU32(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16(&bytes, 10, 2); // two SVGDocumentRecords.
    writeU16(&bytes, 12, 1); // first record covers glyph 1.
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 26); // document data starts after both records.
    writeU32(&bytes, 20, 6);
    writeU16(&bytes, 24, 2); // second record covers glyphs 2 and 3.
    writeU16(&bytes, 26, 3);
    writeU32(&bytes, 28, 32);
    writeU32(&bytes, 32, 6);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..48], "<svg/>");

    const table = svg.Table{ .offset = 0, .length = bytes.len };
    try svg.validate(std.testing.allocator, &bytes, table, 4);

    var overlapping = bytes;
    writeU16(&overlapping, 24, 1); // Overlaps glyph 1 from the first range.
    writeU16(&overlapping, 26, 2);
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &overlapping, table, 4));

    var unsorted = bytes;
    writeU16(&unsorted, 12, 2);
    writeU16(&unsorted, 14, 2);
    writeU16(&unsorted, 24, 1); // Disjoint, but out of ascending glyph order.
    writeU16(&unsorted, 26, 1);
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &unsorted, table, 4));
}

test "SVG document byte ranges reject partial overlaps" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16(&bytes, 0, 0); // SVG table version.
    writeU32(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16(&bytes, 10, 2); // two SVGDocumentRecords.
    writeU16(&bytes, 12, 0); // first record covers glyph 0.
    writeU16(&bytes, 14, 0);
    writeU32(&bytes, 16, 32); // Byte ranges need not follow glyph order.
    writeU32(&bytes, 20, 6);
    writeU16(&bytes, 24, 1); // second record covers glyph 1.
    writeU16(&bytes, 26, 1);
    writeU32(&bytes, 28, 26);
    writeU32(&bytes, 32, 6);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..48], "<svg/>");

    const table = svg.Table{ .offset = 0, .length = bytes.len };
    try svg.validate(std.testing.allocator, &bytes, table, 2);

    var shared_document = bytes;
    writeU32(&shared_document, 16, 26);
    writeU32(&shared_document, 20, 6);
    writeU32(&shared_document, 28, 26);
    writeU32(&shared_document, 32, 6);
    try svg.validate(std.testing.allocator, &shared_document, table, 2);

    var partial_overlap: [53]u8 = .{0} ** 53;
    writeU16(&partial_overlap, 0, 0);
    writeU32(&partial_overlap, 2, 10);
    writeU16(&partial_overlap, 10, 2);
    writeU16(&partial_overlap, 12, 0);
    writeU16(&partial_overlap, 14, 0);
    writeU32(&partial_overlap, 16, 26);
    writeU32(&partial_overlap, 20, 17);
    writeU16(&partial_overlap, 24, 1);
    writeU16(&partial_overlap, 26, 1);
    writeU32(&partial_overlap, 28, 31); // Points at the nested <svg/> inside the first document.
    writeU32(&partial_overlap, 32, 6);
    @memcpy(partial_overlap[36..53], "<svg><svg/></svg>");
    const overlap_svg = svg.Table{ .offset = 0, .length = partial_overlap.len };
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &partial_overlap, overlap_svg, 2));
}

test "SVG document payload must have a single svg root" {
    var bytes: [44]u8 = .{0} ** 44;
    writeU16(&bytes, 0, 0); // SVG table version.
    writeU32(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 14);
    writeU32(&bytes, 20, 20);

    const table = svg.Table{ .offset = 0, .length = bytes.len };
    @memcpy(bytes[24..44], "<svg><g></g></svg>  ");
    try svg.validate(std.testing.allocator, &bytes, table, 2);

    @memcpy(bytes[24..44], "<g></g>             ");
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &bytes, table, 2));

    @memcpy(bytes[24..44], "<svg></g>           ");
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &bytes, table, 2));

    @memcpy(bytes[24..44], "<svg/><svg/>        ");
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &bytes, table, 2));
}

test "SVG document offsets cannot overlap table metadata" {
    var header_overlap: [18]u8 = .{0} ** 18;
    writeU16(&header_overlap, 0, 0);
    writeU32(&header_overlap, 2, 6); // Points into the SVG table header's reserved field.
    try std.testing.expectError(
        error.BadSfnt,
        svg.validate(std.testing.allocator, &header_overlap, .{ .offset = 0, .length = header_overlap.len }, 2),
    );

    var record_overlap: [28]u8 = .{0} ** 28;
    writeU16(&record_overlap, 0, 0);
    writeU32(&record_overlap, 2, 10);
    writeU16(&record_overlap, 10, 1);
    writeU16(&record_overlap, 12, 1);
    writeU16(&record_overlap, 14, 1);
    writeU32(&record_overlap, 16, 2); // Points at the SVGDocumentRecord array.
    writeU32(&record_overlap, 20, 4);
    @memcpy(record_overlap[24..28], "<svg");

    try std.testing.expectError(
        error.BadSfnt,
        svg.validate(std.testing.allocator, &record_overlap, .{ .offset = 0, .length = record_overlap.len }, 2),
    );
}

test "SVG table header reserved field must be zero" {
    var bytes: [30]u8 = .{0} ** 30;
    writeU16(&bytes, 0, 0); // SVG table version.
    writeU32(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU32(&bytes, 6, 1); // Reserved; OpenType requires zero.
    writeU16(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 14);
    writeU32(&bytes, 20, 6);
    @memcpy(bytes[24..30], "<svg/>");

    const table = svg.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &bytes, table, 2));
}

test "SVG document length must be non-zero" {
    var bytes: [30]u8 = .{0} ** 30;
    writeU16(&bytes, 0, 0); // SVG table version.
    writeU32(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 1);
    writeU32(&bytes, 16, 24);
    writeU32(&bytes, 20, 0); // Empty documents cannot contain an SVG root.
    @memcpy(bytes[24..30], "<svg/>");

    const table = svg.Table{ .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, svg.validate(std.testing.allocator, &bytes, table, 2));
}
fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
