//! Font container decoding and malformed-input regression tests.

const std = @import("std");
const container = @import("root.zig");
const binary = @import("binary.zig");
const test_support = @import("test_support.zig");
const Font = @import("../../font.zig").Font;
const test_font = @import("../../test_font.zig");

const Format = container.Format;
const OwnedFace = container.OwnedFace;
const decodeFontContainerAlloc = container.decodeFontContainerAlloc;
const detectFormat = container.detectFormat;

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
    const sfnt = try test_font.buildNamedTtfWithNames(
        allocator,
        "WOFF Demo",
        "Regular",
        "WOFF Demo Regular",
    );
    defer allocator.free(sfnt);
    const woff = try test_support.buildWoff1(allocator, sfnt, true);
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

    const single = try test_support.buildDfont(allocator, &.{first});
    defer allocator.free(single);
    try std.testing.expectEqual(Format.dfont, try detectFormat(single));
    const decoded_single = try decodeFontContainerAlloc(
        allocator,
        single,
        first.len,
    );
    defer allocator.free(decoded_single);
    try std.testing.expectEqualSlices(u8, first, decoded_single);

    const collection = try test_support.buildDfont(allocator, &.{ first, second });
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
    const sfnt = try @import("../../test_font.zig").buildMinimalTtf(allocator);
    defer allocator.free(sfnt);
    const dfont = try test_support.buildDfont(allocator, &.{sfnt});
    defer allocator.free(dfont);

    const bad_map = try allocator.dupe(u8, dfont);
    defer allocator.free(bad_map);
    binary.writeU32(bad_map, 4, @intCast(bad_map.len - 8));
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(allocator, bad_map, std.math.maxInt(usize)),
    );

    const bad_resource = try allocator.dupe(u8, dfont);
    defer allocator.free(bad_resource);
    binary.writeU32(bad_resource, 256, std.math.maxInt(u32));
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
    const map_start: usize = binary.readU32(nonzero_handle, 4);
    const type_list = map_start + binary.readU16(nonzero_handle, map_start + 24);
    const reference = type_list + binary.readU16(nonzero_handle, type_list + 8);
    binary.writeU32(nonzero_handle, reference + 8, 1);
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
    const sfnt = try @import("../../test_font.zig").buildMinimalTtf(allocator);
    defer allocator.free(sfnt);
    const woff = try test_support.buildWoff1(allocator, sfnt, false);
    defer allocator.free(woff);

    const malformed = try allocator.dupe(u8, woff);
    defer allocator.free(malformed);
    // Make table 1 overlap table 0 while preserving aligned offsets.
    const first_offset = binary.readU32(malformed, 44 + 4);
    binary.writeU32(malformed, 44 + 20 + 4, first_offset);
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(allocator, malformed, sfnt.len),
    );

    const metadata_overlap = try allocator.dupe(u8, woff);
    defer allocator.free(metadata_overlap);
    const table_offset = binary.readU32(metadata_overlap, 44 + 4);
    binary.writeU32(metadata_overlap, 24, table_offset);
    binary.writeU32(metadata_overlap, 28, 4);
    binary.writeU32(metadata_overlap, 32, 4);
    try std.testing.expectError(
        error.InvalidContainer,
        decodeFontContainerAlloc(allocator, metadata_overlap, sfnt.len),
    );
}

test "font container preserves WOFF1 physical table order" {
    const allocator = std.testing.allocator;
    const sfnt = try @import("../../test_font.zig").buildMinimalTtf(allocator);
    defer allocator.free(sfnt);
    const tag_order_woff = try test_support.buildWoff1(allocator, sfnt, false);
    defer allocator.free(tag_order_woff);
    const woff = try test_support.reverseWoffPayloadOrder(
        allocator,
        tag_order_woff,
    );
    defer allocator.free(woff);

    // Make checkSumAdjustment describe the physically reversed SFNT encoded by
    // this fixture. The head table's directory checksum deliberately treats
    // these bytes as zero, so no table checksum needs to be changed.
    const head_offset = try test_support.findWoffTablePayload(woff, "head");
    if (head_offset > woff.len or woff.len - head_offset < 12) {
        return error.TestUnexpectedResult;
    }
    binary.writeU32(woff, head_offset + 8, 0);
    const unadjusted = try decodeFontContainerAlloc(allocator, woff, sfnt.len);
    defer allocator.free(unadjusted);
    const adjustment = 0xb1b0afba -% try test_support.sfntChecksum(unadjusted);
    binary.writeU32(woff, head_offset + 8, adjustment);

    const decoded = try decodeFontContainerAlloc(allocator, woff, sfnt.len);
    defer allocator.free(decoded);
    try std.testing.expectEqual(
        @as(u32, 0xb1b0afba),
        try test_support.sfntChecksum(decoded),
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
