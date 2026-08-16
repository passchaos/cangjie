//! fvar type identity, normalization, parse, and name-reference contracts.

const std = @import("std");
const font_mod = @import("../../../../font.zig");
const fvar = @import("../../../tables/variations/fvar/root.zig");
const name = @import("../../../../opentype/name.zig");
const sfnt = @import("../../../sfnt/root.zig");
const test_font = @import("../../../../test_font.zig");
const fixture = @import("../../fixtures/sfnt.zig");
const support = @import("../support.zig");

const Font = font_mod.Font;

test "public fvar values alias concrete module types" {
    try std.testing.expect(font_mod.VariationAxis == fvar.Axis);
    try std.testing.expect(font_mod.VariationCoordinate == fvar.Coordinate);
    try std.testing.expect(font_mod.VariationInstance == fvar.Instance);
}

test "normalized variation coordinates quantize final locations to F2Dot14" {
    try std.testing.expectEqual(
        @as(f32, -0.33331298828125),
        fvar.quantizeNormalized(-1.0 / 3.0),
    );
    try std.testing.expectEqual(
        @as(f32, 0.4000244140625),
        fvar.quantizeNormalized(0.4),
    );
    try std.testing.expectEqual(
        @as(f32, 0.10003662109375),
        fvar.quantizeNormalized(0.1),
    );
    try std.testing.expectEqual(@as(f32, -1.0), fvar.quantizeNormalized(-1.0));
    try std.testing.expectEqual(@as(f32, 1.0), fvar.quantizeNormalized(1.0));
}

test "fvar axis metadata is validated at parse time" {
    const allocator = std.testing.allocator;

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }
    inline for (.{
        struct {
            fn mutate(bytes: []u8, offset: usize) void {
                fixture.writeU16(bytes, offset + 6, 3);
            }
        }.mutate,
        struct {
            fn mutate(bytes: []u8, offset: usize) void {
                @memcpy(bytes[offset + 36 ..][0..4], "wght");
            }
        }.mutate,
        struct {
            fn mutate(bytes: []u8, offset: usize) void {
                fixture.writeU16(bytes, offset + 32, 0x0002);
            }
        }.mutate,
        struct {
            fn mutate(bytes: []u8, offset: usize) void {
                support.writeF16Dot16(bytes, offset + 20, 950.0);
            }
        }.mutate,
    }) |mutate| {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        mutate(bytes, try fixture.tableOffset(bytes, "fvar"));
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "fvar axis normalization clamps around the default design coordinate" {
    const axis = fvar.Axis{
        .tag = .{ 'w', 'g', 'h', 't' },
        .min_value = 100.0,
        .default_value = 400.0,
        .max_value = 900.0,
        .flags = 0,
        .name_id = 256,
    };
    try std.testing.expectEqual(@as(f32, -1.0), axis.normalize(0.0));
    try std.testing.expectEqual(@as(f32, -0.5), axis.normalize(250.0));
    try std.testing.expectEqual(@as(f32, 0.0), axis.normalize(400.0));
    try std.testing.expectEqual(@as(f32, 0.5), axis.normalize(650.0));
    try std.testing.expectEqual(@as(f32, 1.0), axis.normalize(1000.0));

    const collapsed_lower = fvar.Axis{
        .tag = .{ 'o', 'p', 's', 'z' },
        .min_value = 12.0,
        .default_value = 12.0,
        .max_value = 72.0,
        .flags = 0,
        .name_id = 257,
    };
    try std.testing.expectEqual(@as(f32, 0.0), collapsed_lower.normalize(12.0));
}

test "fvar instance name IDs resolve through name table" {
    var bytes: [46]u8 = .{0} ** 46;
    support.writeFvarHeader(&bytes, 1);
    fixture.writeU16(&bytes, 12, 1);
    fixture.writeU16(&bytes, 14, 10);
    support.writeAxis(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    fixture.writeU16(&bytes, 36, 300);
    support.writeF16Dot16(&bytes, 40, 400.0);
    fixture.writeU16(&bytes, 44, 301);

    const record = fvarRecord(bytes.len);
    const names = name.NameIdIndex.initForTest(&.{ 256, 300, 301 });
    try fvar.validateNameReferences(&bytes, record, &names);

    var missing_subfamily = bytes;
    fixture.writeU16(&missing_subfamily, 36, 400);
    try fvar.validateAxisNameReferences(&missing_subfamily, record, &names);
    try std.testing.expectError(
        error.InvalidName,
        fvar.validateNameReferences(&missing_subfamily, record, &names),
    );

    var missing_postscript = bytes;
    fixture.writeU16(&missing_postscript, 44, 400);
    try std.testing.expectError(
        error.InvalidName,
        fvar.validateNameReferences(&missing_postscript, record, &names),
    );

    var omitted_postscript = bytes;
    fixture.writeU16(&omitted_postscript, 44, 0xffff);
    try fvar.validateNameReferences(&omitted_postscript, record, &names);
}

fn fvarRecord(length: usize) sfnt.Record {
    return .{
        .tag = .{ 'f', 'v', 'a', 'r' },
        .checksum = 0,
        .offset = 0,
        .length = length,
    };
}
