//! Complete GPOS lookup-sidecar construction contracts.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const build = @import("../../../accelerator/build/root.zig");
const table = @import("../../../table/root.zig");

test "lookup builder owns SinglePos sidecars and exact dispatch identity" {
    var bytes = [_]u8{0} ** 36;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 18);
    writeU16(&bytes, 12, 0x0001);
    writeI16(&bytes, 14, 25);
    writeCoverage1(&bytes, 26, 5);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const lookup = try build.lookup.one(view, 0, std.testing.allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(
        std.testing.allocator,
        &owned,
    );
    try std.testing.expectEqual(@as(usize, 0), lookup.lookup_offset);
    try std.testing.expectEqual(@as(u16, 1), lookup.lookup_type);
    try std.testing.expectEqual(@as(usize, 1), lookup.single_pos_subtables.len);
    try std.testing.expectEqual(
        @as(i16, 25),
        lookup.single_pos_subtables[0].value.x_placement,
    );
    try std.testing.expect(lookup.coverage_digest.mayHave(5));
}

test "top-level builder rejects truncated input before allocation escapes" {
    const bytes = [_]u8{0} ** 8;
    try std.testing.expectError(
        error.BadGpos,
        build.lookup.all(
            &bytes,
            0,
            8,
            std.testing.allocator,
        ),
    );
}

test "extension ContextPos class rules build compact two-glyph sidecars" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeU16(&bytes, 0, 9);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    writeU16(&bytes, 8, 1);
    writeU16(&bytes, 10, 7);
    writeU32(&bytes, 12, 8);

    const context = 16;
    writeU16(&bytes, context, 2);
    writeU16(&bytes, context + 2, 32);
    writeU16(&bytes, context + 4, 38);
    writeU16(&bytes, context + 6, 2);
    writeU16(&bytes, context + 8, 0);
    writeU16(&bytes, context + 10, 12);
    const set = context + 12;
    writeU16(&bytes, set, 1);
    writeU16(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16(&bytes, rule, 2);
    writeU16(&bytes, rule + 2, 1);
    writeU16(&bytes, rule + 4, 3);
    writeU16(&bytes, rule + 6, 1);
    writeU16(&bytes, rule + 8, 9);
    writeCoverage1(&bytes, context + 32, 5);
    writeClassDef1(&bytes, context + 38, 5, &.{ 1, 3 });

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const lookup = try build.lookup.one(view, 0, allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(allocator, &owned);

    try std.testing.expectEqual(@as(?u16, 7), lookup.extension_lookup_type);
    try std.testing.expectEqual(@as(usize, 1), lookup.context_class_subtables.len);
    const subtable = lookup.context_class_subtables[0];
    try std.testing.expectEqual(@as(?usize, 0), subtable.coverage.?.index(5));
    try std.testing.expectEqual(@as(u16, 3), subtable.rules[0].second_class);
    try std.testing.expectEqual(@as(u16, 1), subtable.rules[0].sequence_index);
    try std.testing.expectEqual(@as(u16, 9), subtable.rules[0].lookup_index);
}

test "direct chaining lookup builds one exact contiguous second-lookahead segment" {
    var bytes = [_]u8{0} ** 256;
    const fixture = writeSecondGroupingLookup(&bytes);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const lookup = try build.lookup.one(
        view,
        fixture.lookup_offset,
        std.testing.allocator,
    );
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(std.testing.allocator, &owned);

    try std.testing.expect(lookup.chaining_coverage_only);
    try std.testing.expectEqual(@as(usize, 5), lookup.chaining_subtables.len);
    try std.testing.expectEqual(@as(u16, 1), lookup.chaining_second_start);
    try std.testing.expectEqual(@as(u16, 3), lookup.chaining_second_end);

    // Subtable zero is a generic predecessor. Subtables one and two form the
    // only contiguous simple segment; subtable three closes that segment, so
    // the otherwise-eligible subtable four deliberately remains generic.
    const first_candidates = accelerator.glyph_groups.find(
        lookup.chaining_groups,
        lookup.chaining_group_slots,
        10,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(
        u16,
        &.{ 0, 1, 2, 3, 4 },
        first_candidates,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{1},
        accelerator.glyph_groups.find(
            lookup.chaining_second_groups,
            lookup.chaining_second_group_slots,
            20,
        ) orelse return error.TestUnexpectedResult,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{ 1, 2 },
        accelerator.glyph_groups.find(
            lookup.chaining_second_groups,
            lookup.chaining_second_group_slots,
            24,
        ) orelse return error.TestUnexpectedResult,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{2},
        accelerator.glyph_groups.find(
            lookup.chaining_second_groups,
            lookup.chaining_second_group_slots,
            34,
        ) orelse return error.TestUnexpectedResult,
    );
    try std.testing.expect(accelerator.glyph_groups.find(
        lookup.chaining_second_groups,
        lookup.chaining_second_group_slots,
        40,
    ) == null);

    try std.testing.expectEqual(
        @as(u16, 3),
        lookup.chaining_subtables[1].simple_lookup_index,
    );
    try std.testing.expectEqual(
        @as(u16, 5),
        lookup.chaining_subtables[2].simple_lookup_index,
    );

    // The exact second-membership and record target are construction-time
    // proofs. Once admitted, the proof-level-two runtime path uses these owned
    // values rather than trusting post-build changes in borrowed font bytes.
    writeU16(&bytes, fixture.first_simple_record + 2, 4);
    writeU16(&bytes, fixture.first_simple_lookahead_glyph, 99);
    try std.testing.expectEqual(
        @as(u16, 4),
        try view.readU16(fixture.first_simple_record + 2),
    );
    try std.testing.expectEqual(
        @as(u16, 3),
        lookup.chaining_subtables[1].simple_lookup_index,
    );
    try std.testing.expect(
        lookup.chaining_subtables[1].lookahead_coverages[0].index(20) != null,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{1},
        accelerator.glyph_groups.find(
            lookup.chaining_second_groups,
            lookup.chaining_second_group_slots,
            20,
        ) orelse return error.TestUnexpectedResult,
    );
}

test "extension chaining coverage stays on the generic wrapper path" {
    var bytes = [_]u8{0} ** 80;
    const lookup_offset = writeExtensionChainingLookup(&bytes);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };

    const lookup = try build.lookup.one(
        view,
        lookup_offset,
        std.testing.allocator,
    );
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(std.testing.allocator, &owned);

    try std.testing.expectEqual(@as(u16, 9), lookup.lookup_type);
    try std.testing.expectEqual(@as(?u16, 8), lookup.extension_lookup_type);
    try std.testing.expect(!lookup.chaining_coverage_only);
    try std.testing.expectEqual(@as(usize, 0), lookup.chaining_subtables.len);
    try std.testing.expectEqual(@as(usize, 0), lookup.chaining_groups.len);
    try std.testing.expectEqual(@as(usize, 0), lookup.chaining_second_groups.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        lookup.chaining_second_group_slots.len,
    );
    try std.testing.expectEqual(@as(u16, 0), lookup.chaining_second_start);
    try std.testing.expectEqual(@as(u16, 0), lookup.chaining_second_end);

    // The lookup-wide first-Coverage prefilter remains available, but it does
    // not turn a wrapped format-3 subtable into the direct type-8 sidecar.
    try std.testing.expectEqualSlices(
        u16,
        &.{0},
        accelerator.glyph_groups.find(
            lookup.coverage_groups,
            lookup.coverage_group_slots,
            7,
        ) orelse return error.TestUnexpectedResult,
    );
}

test "lookup builder releases second-lookahead groups on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildSecondGroupingLookup,
        .{},
    );
}

test "lookup builder releases MarkLigPos coverages on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildMarkLigatureLookup,
        .{},
    );
}

test "lookup builder releases extension mark coverages on allocation failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildExtensionMarkLookup,
        .{4},
    );
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildExtensionMarkLookup,
        .{6},
    );
}

test "lookup builder rejects a malformed later extension mark payload" {
    for ([_]u16{ 4, 6 }) |wrapped_type| {
        var bytes = [_]u8{0} ** 122;
        writeExtensionMarkLookup(&bytes, wrapped_type);
        // The second payload's second required Coverage points past the view.
        writeU16(&bytes, 74 + 4, 0xffff);
        try std.testing.expectError(
            error.BadGpos,
            build.lookup.one(.{
                .data = &bytes,
                .offset = 0,
                .length = bytes.len,
                .assume_validated = true,
            }, 0, std.testing.allocator),
        );
    }
}

fn buildExtensionMarkLookup(
    allocator: std.mem.Allocator,
    wrapped_type: u16,
) !void {
    var bytes = [_]u8{0} ** 122;
    writeExtensionMarkLookup(&bytes, wrapped_type);
    const lookup = try build.lookup.one(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(allocator, &owned);

    try std.testing.expectEqual(@as(?u16, wrapped_type), lookup.extension_lookup_type);
    if (wrapped_type == 4) {
        try std.testing.expectEqual(
            @as(usize, 2),
            lookup.mark_to_base_subtables.len,
        );
        try std.testing.expectEqual(
            @as(?usize, 0),
            lookup.mark_to_base_subtables[0].mark_coverage.?.index(22),
        );
        try std.testing.expectEqual(
            @as(?usize, 0),
            lookup.mark_to_base_subtables[1].base_coverage.?.index(30),
        );
    } else {
        try std.testing.expectEqual(
            @as(usize, 2),
            lookup.mark_to_mark_subtables.len,
        );
        try std.testing.expectEqual(
            @as(?usize, 0),
            lookup.mark_to_mark_subtables[0].mark_1_coverage.?.index(22),
        );
        try std.testing.expectEqual(
            @as(?usize, 0),
            lookup.mark_to_mark_subtables[1].mark_2_coverage.?.index(30),
        );
    }
}

fn writeExtensionMarkLookup(bytes: []u8, wrapped_type: u16) void {
    writeU16(bytes, 0, 9);
    writeU16(bytes, 2, 0);
    writeU16(bytes, 4, 2);
    writeU16(bytes, 6, 10);
    writeU16(bytes, 8, 66);
    writeExtensionMarkSubtable(bytes, 10, wrapped_type, 22, 20);
    writeExtensionMarkSubtable(bytes, 66, wrapped_type, 32, 30);
}

fn writeExtensionMarkSubtable(
    bytes: []u8,
    wrapper: usize,
    wrapped_type: u16,
    first_glyph: u16,
    second_glyph: u16,
) void {
    writeU16(bytes, wrapper, 1);
    writeU16(bytes, wrapper + 2, wrapped_type);
    writeU32(bytes, wrapper + 4, 8);
    const subtable = wrapper + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 12);
    writeU16(bytes, subtable + 4, 18);
    writeU16(bytes, subtable + 6, 1);
    writeU16(bytes, subtable + 8, 24);
    writeU16(bytes, subtable + 10, 36);
    writeCoverage1(bytes, subtable + 12, first_glyph);
    writeCoverage1(bytes, subtable + 18, second_glyph);
    writeU16(bytes, subtable + 24, 1);
    writeU16(bytes, subtable + 26, 0);
    writeU16(bytes, subtable + 28, 6);
    writeU16(bytes, subtable + 30, 1);
    writeI16(bytes, subtable + 32, 10);
    writeI16(bytes, subtable + 34, 15);
    writeU16(bytes, subtable + 36, 1);
    writeU16(bytes, subtable + 38, 4);
    writeU16(bytes, subtable + 40, 1);
    writeI16(bytes, subtable + 42, 100);
    writeI16(bytes, subtable + 44, 120);
}

fn buildMarkLigatureLookup(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 62;
    writeU16(&bytes, 0, 5);
    writeU16(&bytes, 2, 0);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);
    const subtable = 8;
    writeU16(&bytes, subtable + 0, 1);
    writeU16(&bytes, subtable + 2, 12);
    writeU16(&bytes, subtable + 4, 18);
    writeU16(&bytes, subtable + 6, 1);
    writeU16(&bytes, subtable + 8, 24);
    writeU16(&bytes, subtable + 10, 36);
    writeCoverage1(&bytes, subtable + 12, 22);
    writeCoverage1(&bytes, subtable + 18, 20);
    writeU16(&bytes, subtable + 24, 1);
    writeU16(&bytes, subtable + 26, 0);
    writeU16(&bytes, subtable + 28, 6);
    writeU16(&bytes, subtable + 30, 1);
    writeI16(&bytes, subtable + 32, 10);
    writeI16(&bytes, subtable + 34, 15);
    writeU16(&bytes, subtable + 36, 1);
    writeU16(&bytes, subtable + 38, 4);
    writeU16(&bytes, subtable + 40, 1);
    writeU16(&bytes, subtable + 42, 4);
    writeU16(&bytes, subtable + 44, 1);
    writeI16(&bytes, subtable + 46, 100);
    writeI16(&bytes, subtable + 48, 120);

    const lookup = try build.lookup.one(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(allocator, &owned);
    try std.testing.expectEqual(
        @as(usize, 1),
        lookup.mark_to_ligature_subtables.len,
    );
}

fn buildSecondGroupingLookup(allocator: std.mem.Allocator) !void {
    var bytes = [_]u8{0} ** 256;
    const fixture = writeSecondGroupingLookup(&bytes);
    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const lookup = try build.lookup.one(view, fixture.lookup_offset, allocator);
    var owned = [_]build.lookup.Lookup{lookup};
    defer build.lookup.deinitContents(allocator, &owned);

    try std.testing.expect(lookup.chaining_second_groups.len >= 8);
    try std.testing.expect(lookup.chaining_second_group_slots.len != 0);
}

const SecondGroupingFixture = struct {
    lookup_offset: usize,
    first_simple_record: usize,
    first_simple_lookahead_glyph: usize,
};

fn writeSecondGroupingLookup(bytes: []u8) SecondGroupingFixture {
    writeU16(bytes, 0, 1);
    writeU16(bytes, 8, 10);

    // Keep every nested lookup index in range while pointing it back to this
    // type-8 lookup. Fast SinglePos detection rejects that type, as intended.
    const lookup_list = 10;
    const lookup_offset = 24;
    writeU16(bytes, lookup_list, 6);
    for (0..6) |index| {
        writeU16(
            bytes,
            lookup_list + 2 + index * 2,
            @intCast(lookup_offset - lookup_list),
        );
    }

    writeU16(bytes, lookup_offset, 8);
    writeU16(bytes, lookup_offset + 2, 0);
    writeU16(bytes, lookup_offset + 4, 5);

    var cursor: usize = lookup_offset + 16;
    for (0..5) |index| {
        writeU16(
            bytes,
            lookup_offset + 6 + index * 2,
            @intCast(cursor - lookup_offset),
        );
        cursor = switch (index) {
            0, 3 => writeComplexChainingCoverage(bytes, cursor, 10, 90),
            1 => writeSimpleChainingCoverage(
                bytes,
                cursor,
                10,
                &.{ 20, 21, 22, 23, 24, 25, 26, 27 },
                3,
            ),
            2 => writeSimpleChainingCoverage(
                bytes,
                cursor,
                10,
                &.{ 24, 28, 29, 30, 31, 32, 33, 34 },
                5,
            ),
            // This subtable proves that grouping stays closed after the
            // complex residual at index three.
            4 => writeSimpleChainingCoverage(
                bytes,
                cursor,
                10,
                &.{40},
                4,
            ),
            else => unreachable,
        };
    }

    // Index zero occupies 34 bytes, so index one starts at byte 74.
    const first_simple = lookup_offset + 16 + 34;
    return .{
        .lookup_offset = lookup_offset,
        .first_simple_record = first_simple + 14,
        .first_simple_lookahead_glyph = first_simple + 28,
    };
}

fn writeExtensionChainingLookup(bytes: []u8) usize {
    writeU16(bytes, 0, 1);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 1);
    writeU16(bytes, 12, 4);

    const lookup_offset = 14;
    writeU16(bytes, lookup_offset, 9);
    writeU16(bytes, lookup_offset + 2, 0);
    writeU16(bytes, lookup_offset + 4, 1);
    writeU16(bytes, lookup_offset + 6, 10);

    const wrapper = lookup_offset + 10;
    writeU16(bytes, wrapper, 1);
    writeU16(bytes, wrapper + 2, 8);
    writeU32(bytes, wrapper + 4, 8);
    _ = writeSimpleChainingCoverage(
        bytes,
        wrapper + 8,
        7,
        &.{11},
        0,
    );
    return lookup_offset;
}

fn writeSimpleChainingCoverage(
    bytes: []u8,
    offset: usize,
    first_glyph: u16,
    lookahead_glyphs: []const u16,
    lookup_index: u16,
) usize {
    writeU16(bytes, offset, 3);
    writeU16(bytes, offset + 2, 0);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 18);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 24);
    writeU16(bytes, offset + 12, 1);
    writeU16(bytes, offset + 14, 0);
    writeU16(bytes, offset + 16, lookup_index);
    writeCoverage1(bytes, offset + 18, first_glyph);
    writeCoverage1Glyphs(bytes, offset + 24, lookahead_glyphs);
    return offset + 28 + lookahead_glyphs.len * 2;
}

fn writeComplexChainingCoverage(
    bytes: []u8,
    offset: usize,
    first_glyph: u16,
    lookahead_glyph: u16,
) usize {
    writeU16(bytes, offset, 3);
    writeU16(bytes, offset + 2, 0);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 22);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 28);
    writeU16(bytes, offset + 12, 2);
    writeU16(bytes, offset + 14, 0);
    writeU16(bytes, offset + 16, 0);
    writeU16(bytes, offset + 18, 0);
    writeU16(bytes, offset + 20, 0);
    writeCoverage1(bytes, offset + 22, first_glyph);
    writeCoverage1(bytes, offset + 28, lookahead_glyph);
    return offset + 34;
}

fn writeCoverage1Glyphs(
    bytes: []u8,
    offset: usize,
    glyphs: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeClassDef1(
    bytes: []u8,
    offset: usize,
    start: u16,
    classes: []const u16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, start);
    writeU16(bytes, offset + 4, @intCast(classes.len));
    for (classes, 0..) |class, index| {
        writeU16(bytes, offset + 6 + index * 2, class);
    }
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
