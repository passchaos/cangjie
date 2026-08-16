//! TrueType loca/glyf parse-time structural contracts.

const std = @import("std");
const font_mod = @import("../../../font.zig");
const glyf = @import("../../tables/truetype/glyf/root.zig");
const test_font = @import("../../../test_font.zig");
const fixture = @import("../fixtures/sfnt.zig");

const Font = font_mod.Font;

test "simple glyf contours reject non-increasing end points" {
    var glyph: [24]u8 = .{0} ** 24;
    fixture.writeI16(&glyph, 0, 2);
    fixture.writeU16(&glyph, 10, 0);
    fixture.writeU16(&glyph, 12, 0);
    fixture.writeU16(&glyph, 14, 0);
    glyph[16] = 0x31;

    const loca: [4]u8 = .{ 0, 0, 0, 12 };
    var data: [loca.len + glyph.len]u8 = undefined;
    @memcpy(data[0..loca.len], &loca);
    @memcpy(data[loca.len..], &glyph);
    try std.testing.expectError(
        error.InvalidGlyph,
        glyf.validate(
            std.testing.allocator,
            &data,
            record("loca", 0, loca.len),
            record("glyf", loca.len, glyph.len),
            1,
            0,
            .{
                .max_points = 32,
                .max_contours = 32,
                .max_component_elements = 32,
                .max_component_depth = 32,
            },
        ),
    );
}

test "simple glyf programs and coordinate streams validate at parse time" {
    const allocator = std.testing.allocator;
    const Mutation = enum {
        reserved_flag,
        late_overlap,
        repeated_overlap,
        long_program,
        excessive_repeat,
        truncated_coordinates,
    };
    inline for (std.enums.values(Mutation)) |mutation| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const offset = try fixture.tableOffset(bytes, "glyf") + 12;
        switch (mutation) {
            .reserved_flag => bytes[offset + 14] = 0xb1,
            .late_overlap => bytes[offset + 15] = 0x61,
            .repeated_overlap => {
                bytes[offset + 14] = 0x79;
                bytes[offset + 15] = 2;
            },
            .long_program => fixture.writeU16(bytes, offset + 12, 15),
            .excessive_repeat => {
                bytes[offset + 14] = 0x39;
                bytes[offset + 15] = 3;
            },
            .truncated_coordinates => {
                bytes[offset + 14] = 0x01;
                bytes[offset + 15] = 0x01;
                bytes[offset + 16] = 0x01;
            },
        }
        try std.testing.expectError(
            error.InvalidGlyph,
            Font.parse(allocator, bytes),
        );
    }
}

test "loca stays inside its declared table length" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    try fixture.setTableLength(bytes, "loca", 4);
    try std.testing.expectError(error.InvalidLoca, Font.parse(allocator, bytes));
}

test "loca offsets are validated against glyf at parse time" {
    const allocator = std.testing.allocator;
    inline for (.{ @as(u16, 1), @as(u16, 22) }) |last_offset| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const offset = try fixture.tableOffset(bytes, "loca");
        fixture.writeU16(bytes, offset + 4, last_offset);
        try std.testing.expectError(
            error.InvalidLoca,
            Font.parse(allocator, bytes),
        );
    }
}

test "simple glyf summaries must not exceed maxp maxima" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ .offset = @as(usize, 6), .value = @as(u16, 2) },
        .{ .offset = @as(usize, 8), .value = @as(u16, 0) },
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp = try fixture.tableOffset(bytes, "maxp");
        fixture.writeU16(bytes, maxp + case.offset, case.value);
        try fixture.updateTableChecksum(bytes, "maxp");
        try std.testing.expectError(
            error.InvalidGlyph,
            Font.parse(allocator, bytes),
        );
    }
}

test "compound glyf components are validated against maxp at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const glyph = try glyphOneOffset(bytes);
    writeCompound(bytes, glyph, 0x0002, 2);
    try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
}

test "compound glyf component flags reject conflicting transforms" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const glyph = try glyphOneOffset(bytes);
    writeCompound(bytes, glyph, 0x0002 | 0x0008 | 0x0040, 0);
    try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
}

test "compound glyf component flags reject reserved and conflicting offset semantics" {
    const allocator = std.testing.allocator;
    inline for (.{
        @as(u16, 0x0002 | 0x0010),
        @as(u16, 0x0002 | 0x0800 | 0x1000),
        @as(u16, 0x0002 | 0x2000),
    }) |flags| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        writeCompound(bytes, try glyphOneOffset(bytes), flags, 0);
        try std.testing.expectError(
            error.InvalidGlyph,
            Font.parse(allocator, bytes),
        );
    }
}

test "compound glyf permits repeated USE_MY_METRICS flags" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const glyph = try glyphOneOffset(bytes);
    writeCompound(bytes, glyph, 0x0020 | 0x0200 | 0x0002, 0);
    fixture.writeU16(bytes, glyph + 16, 0x0200 | 0x0002);
    fixture.writeU16(bytes, glyph + 18, 0);
    bytes[glyph + 20] = 0;
    bytes[glyph + 21] = 0;
    const maxp = try fixture.tableOffset(bytes, "maxp");
    fixture.writeU16(bytes, maxp + 28, 2);
    fixture.writeU16(bytes, maxp + 30, 1);
    try fixture.updateTableChecksum(bytes, "glyf");
    try fixture.updateTableChecksum(bytes, "maxp");
    var font = try Font.parse(allocator, bytes);
    font.deinit();
}

test "compound glyf point-matching arguments reject out-of-range point numbers" {
    const allocator = std.testing.allocator;
    inline for (.{ @as(u16, 0x0001), @as(u16, 0x0000) }) |flags| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyph = try glyphOneOffset(bytes);
        writeCompound(bytes, glyph, flags, 0);
        bytes[glyph + 14] = 0xff;
        const maxp = try fixture.tableOffset(bytes, "maxp");
        fixture.writeU16(bytes, maxp + 28, 1);
        fixture.writeU16(bytes, maxp + 30, 1);
        try std.testing.expectError(
            error.InvalidGlyph,
            Font.parse(allocator, bytes),
        );
    }
}

test "compound glyf component graph rejects cycles at parse time" {
    const allocator = std.testing.allocator;
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    writeCompound(bytes, try glyphOneOffset(bytes), 0x0002, 1);
    try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
}

test "compound glyf aggregates must not exceed maxp composite limits" {
    const allocator = std.testing.allocator;
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyph = try glyphOneOffset(bytes);
        writeCompound(bytes, glyph, 0x0002, 0);
        const maxp = try fixture.tableOffset(bytes, "maxp");
        fixture.writeU16(bytes, maxp + 28, 1);
        fixture.writeU16(bytes, maxp + 30, 0);
        try std.testing.expectError(
            error.InvalidGlyph,
            Font.parse(allocator, bytes),
        );
    }
    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyph = try glyphOneOffset(bytes);
        writeCompound(bytes, glyph, 0x0020 | 0x0002, 0);
        fixture.writeU16(bytes, glyph + 16, 0x0002);
        fixture.writeU16(bytes, glyph + 18, 0);
        const maxp = try fixture.tableOffset(bytes, "maxp");
        fixture.writeU16(bytes, maxp + 28, 1);
        fixture.writeU16(bytes, maxp + 30, 1);
        try std.testing.expectError(
            error.InvalidGlyph,
            Font.parse(allocator, bytes),
        );
    }
}

fn glyphOneOffset(bytes: []const u8) !usize {
    return try fixture.tableOffset(bytes, "glyf") + 12;
}

fn writeCompound(
    bytes: []u8,
    glyph: usize,
    flags: u16,
    component: u16,
) void {
    fixture.writeI16(bytes, glyph, -1);
    fixture.writeU16(bytes, glyph + 10, flags);
    fixture.writeU16(bytes, glyph + 12, component);
    bytes[glyph + 14] = 0;
    bytes[glyph + 15] = 0;
}

fn record(
    comptime tag: *const [4]u8,
    offset: usize,
    length: usize,
) @import("../../sfnt/root.zig").Record {
    return .{
        .tag = tag.*,
        .checksum = 0,
        .offset = offset,
        .length = length,
    };
}
