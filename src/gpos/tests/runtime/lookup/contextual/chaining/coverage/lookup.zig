//! Coverage lookup prefilter contracts.

const std = @import("std");
const accelerator =
    @import("../../../../../../accelerator/root.zig");
const GlyphDigest = @import("../../../../../../../glyph_digest.zig").GlyphDigest;
const limits = @import("../../../../../../runtime/limits.zig");
const lookup =
    @import("../../../../../../runtime/lookup/contextual/chaining/coverage/lookup.zig");
const model =
    @import("../../../../../../runtime/lookup/contextual/model.zig");
const table = @import("../../../../../../table/root.zig");

test "chaining glyph digest activates only for amortized runs" {
    var digest = GlyphDigest.empty();
    digest.add(20);
    try std.testing.expect(!digest.mayHave(21));
    try std.testing.expect(!lookup.usesGlyphDigest(15));
    try std.testing.expect(lookup.usesGlyphDigest(16));

    // Digest collisions are allowed; exact candidate groups remain
    // authoritative after the approximate prefilter.
    var collision: ?u16 = null;
    var glyph: usize = 0;
    while (glyph <= std.math.maxInt(u16)) : (glyph += 1) {
        const candidate: u16 = @intCast(glyph);
        if (candidate != 20 and digest.mayHave(candidate)) {
            collision = candidate;
            break;
        }
    }
    try std.testing.expect(collision != null);
    const groups = [_]accelerator.glyph_groups.Group{
        .{ .glyph = 20, .subtable_indices = &.{0} },
    };
    try std.testing.expect(
        accelerator.glyph_groups.find(&groups, &.{}, collision.?) == null,
    );
}

test "direct second-lookahead groups make sparse exact hits and misses" {
    const allocator = std.testing.allocator;
    var fixture: Fixture = .{};
    fixture.addSimple(11, &.{ 100, 4000 }, 17);

    const built = try fixture.build(allocator);
    defer built.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 0), built.sidecar.chaining_second_start);
    try std.testing.expectEqual(@as(u16, 1), built.sidecar.chaining_second_end);
    try std.testing.expectEqualSlices(
        u16,
        &.{0},
        findSecond(&built.sidecar, 100).?,
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{0},
        findSecond(&built.sidecar, 4000).?,
    );
    try std.testing.expect(findSecond(&built.sidecar, 101) == null);

    try expectCollect(&built, &.{ 11, 100 }, 0, .{}, &.{17});
    try expectCollect(&built, &.{ 11, 4000 }, 0, .{}, &.{17});
    try expectCollect(&built, &.{ 11, 101 }, 0, .{}, &.{});
}

test "direct second-lookahead groups preserve authored order" {
    const allocator = std.testing.allocator;
    var fixture: Fixture = .{};
    fixture.addSimple(11, &.{ 100, 4000 }, 21);
    fixture.addSimple(11, &.{ 100, 9000 }, 22);

    const built = try fixture.build(allocator);
    defer built.deinit(allocator);

    try std.testing.expectEqualSlices(
        u16,
        &.{ 0, 1 },
        findSecond(&built.sidecar, 100).?,
    );
    try expectCollect(&built, &.{ 11, 100 }, 0, .{}, &.{21});
    try expectCollect(&built, &.{ 11, 9000 }, 0, .{}, &.{22});
}

test "complex residuals bound the indexed segment without reordering it" {
    const allocator = std.testing.allocator;
    var fixture: Fixture = .{};
    fixture.addComplex(11, &.{ 50, 51 }, 31);
    fixture.addSimple(11, &.{100}, 32);
    fixture.addSimple(11, &.{200}, 33);
    fixture.addComplex(11, &.{ 60, 61 }, 34);
    fixture.addSimple(11, &.{300}, 35);

    const built = try fixture.build(allocator);
    defer built.deinit(allocator);

    // Only the first contiguous simple run is indexed. Complex subtables on
    // either side, and simple subtables after the residual tail begins, must
    // retain the generic authored-order path.
    try std.testing.expectEqual(@as(u16, 1), built.sidecar.chaining_second_start);
    try std.testing.expectEqual(@as(u16, 3), built.sidecar.chaining_second_end);
    try std.testing.expectEqualSlices(
        u16,
        &.{1},
        findSecond(&built.sidecar, 100).?,
    );
    try std.testing.expect(findSecond(&built.sidecar, 300) == null);

    try expectCollect(&built, &.{ 11, 50, 51 }, 0, .{}, &.{31});
    try expectCollect(&built, &.{ 11, 100 }, 0, .{}, &.{32});
    try expectCollect(&built, &.{ 11, 60, 61 }, 0, .{}, &.{34});
    try expectCollect(&built, &.{ 11, 300 }, 0, .{}, &.{35});
}

test "second-lookahead grouping uses the next visible glyph" {
    const allocator = std.testing.allocator;
    var fixture: Fixture = .{};
    fixture.addSimple(11, &.{42}, 41);

    const built = try fixture.build(allocator);
    defer built.deinit(allocator);

    var glyph_classes = [_]u16{0} ** 78;
    glyph_classes[77] = 3;
    try expectCollect(
        &built,
        &.{ 11, 77, 42 },
        0x0008,
        .{ .glyph_classes = &glyph_classes },
        &.{41},
    );
    try expectCollect(
        &built,
        &.{ 11, 77 },
        0x0008,
        .{ .glyph_classes = &glyph_classes },
        &.{},
    );
}

test "fast SinglePos records reject the seventeenth contextual edge" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;
    writeU32(&bytes, 0, 0x00010000);
    writeU16(&bytes, 8, 10); // LookupList.
    writeU16(&bytes, 10, 2);
    writeU16(&bytes, 12, 6); // Chaining lookup at 16.
    writeU16(&bytes, 14, 48); // SinglePos lookup at 58.

    const chain_lookup = 16;
    writeU16(&bytes, chain_lookup, 8);
    writeU16(&bytes, chain_lookup + 2, 0);
    writeU16(&bytes, chain_lookup + 4, 1);
    writeU16(&bytes, chain_lookup + 6, 8);
    const chain = chain_lookup + 8;
    writeU16(&bytes, chain, 3);
    writeU16(&bytes, chain + 2, 0); // No backtrack.
    writeU16(&bytes, chain + 4, 1); // One input Coverage.
    writeU16(&bytes, chain + 6, 16);
    writeU16(&bytes, chain + 8, 0); // No lookahead.
    writeU16(&bytes, chain + 10, 1); // One fast SinglePos record.
    writeU16(&bytes, chain + 12, 0);
    writeU16(&bytes, chain + 14, 1);
    writeCoverage(&bytes, chain + 16, &.{5});

    const single_lookup = 58;
    writeU16(&bytes, single_lookup, 1);
    writeU16(&bytes, single_lookup + 2, 0);
    writeU16(&bytes, single_lookup + 4, 1);
    writeU16(&bytes, single_lookup + 6, 8);
    const single = single_lookup + 8;
    writeU16(&bytes, single, 1);
    writeU16(&bytes, single + 2, 8);
    writeU16(&bytes, single + 4, 0x0001);
    writeI16(&bytes, single + 6, 41);
    writeCoverage(&bytes, single + 8, &.{5});

    const view = table.View{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const sidecars = try accelerator.build.lookup.all(
        &bytes,
        0,
        bytes.len,
        allocator,
    );
    defer accelerator.build.lookup.deinit(allocator, sidecars);
    try std.testing.expectEqual(
        @as(u16, 1),
        sidecars[0].chaining_subtables[0].fast_record_count,
    );

    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);
    try std.testing.expectError(
        error.UnsupportedGpos,
        lookup.collect(
            view,
            chain_lookup,
            1,
            &.{5},
            &adjustments,
            allocator,
            0,
            .{
                .lookup_accelerators = sidecars,
                .context_depth = limits.max_context_depth,
            },
            &sidecars[0],
            rejectRecords,
            captureNested,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

const max_fixture_bytes = 1024;
const max_fixture_subtables = 8;
const fixture_lookup_offset = 12;

const Fixture = struct {
    bytes: [max_fixture_bytes]u8 = [_]u8{0} ** max_fixture_bytes,
    subtable_offsets: [max_fixture_subtables]u16 = undefined,
    subtable_count: u16 = 0,
    cursor: usize = fixture_lookup_offset + 6 + max_fixture_subtables * 2,

    fn addSimple(
        self: *Fixture,
        first: u16,
        seconds: []const u16,
        lookup_index: u16,
    ) void {
        self.addSubtable(first, seconds, lookup_index, false);
    }

    fn addComplex(
        self: *Fixture,
        first: u16,
        lookaheads: *const [2]u16,
        lookup_index: u16,
    ) void {
        self.addSubtable(first, lookaheads, lookup_index, true);
    }

    fn addSubtable(
        self: *Fixture,
        first: u16,
        seconds: []const u16,
        lookup_index: u16,
        complex: bool,
    ) void {
        std.debug.assert(self.subtable_count < max_fixture_subtables);
        const start = self.cursor;
        self.subtable_offsets[self.subtable_count] =
            @intCast(start - fixture_lookup_offset);
        self.subtable_count += 1;

        writeU16(&self.bytes, start, 3);
        writeU16(&self.bytes, start + 2, 0); // Backtrack count.
        writeU16(&self.bytes, start + 4, 1); // Input count.
        writeU16(&self.bytes, start + 6, if (complex) 24 else 18);
        writeU16(&self.bytes, start + 8, if (complex) 2 else 1);
        writeU16(&self.bytes, start + 10, if (complex) 30 else 24);
        if (complex) writeU16(&self.bytes, start + 12, 36);
        const pos_count_offset = start +
            @as(usize, if (complex) 14 else 12);
        writeU16(&self.bytes, pos_count_offset, 1);
        writeU16(&self.bytes, pos_count_offset + 2, 0);
        writeU16(&self.bytes, pos_count_offset + 4, lookup_index);

        const first_coverage = start +
            @as(usize, if (complex) 24 else 18);
        writeCoverage(&self.bytes, first_coverage, &.{first});
        const second_coverage = start +
            @as(usize, if (complex) 30 else 24);
        writeCoverage(
            &self.bytes,
            second_coverage,
            if (complex) seconds[0..1] else seconds,
        );
        if (complex) writeCoverage(&self.bytes, start + 36, seconds[1..2]);
        self.cursor = start + if (complex)
            @as(usize, 42)
        else
            28 + seconds.len * 2;
    }

    fn build(self: *Fixture, allocator: std.mem.Allocator) !BuiltFixture {
        // `coverageSubtable` probes the enclosing GPOS LookupList when it
        // considers fast nested SinglePos records. An empty but valid list is
        // sufficient here because lookup indexes are captured by the test.
        writeU16(&self.bytes, 0, 1);
        writeU16(&self.bytes, 8, 10);
        writeU16(&self.bytes, 10, 0);
        writeU16(&self.bytes, fixture_lookup_offset, 8);
        writeU16(&self.bytes, fixture_lookup_offset + 2, 0);
        writeU16(
            &self.bytes,
            fixture_lookup_offset + 4,
            self.subtable_count,
        );
        for (self.subtable_offsets[0..self.subtable_count], 0..) |offset, i| {
            writeU16(
                &self.bytes,
                fixture_lookup_offset + 6 + i * 2,
                offset,
            );
        }
        const view = table.View{
            .data = self.bytes[0..self.cursor],
            .offset = 0,
            .length = self.cursor,
            .assume_validated = true,
        };
        return .{
            .view = view,
            .sidecar = try accelerator.build.lookup.one(
                view,
                fixture_lookup_offset,
                allocator,
            ),
        };
    }
};

const BuiltFixture = struct {
    view: table.View,
    sidecar: accelerator.model.Lookup,

    fn deinit(self: BuiltFixture, allocator: std.mem.Allocator) void {
        var sidecars = [_]accelerator.model.Lookup{self.sidecar};
        accelerator.build.lookup.deinitContents(allocator, &sidecars);
    }
};

fn expectCollect(
    built: *const BuiltFixture,
    glyphs: []const u16,
    lookup_flag: u16,
    run: model.Options,
    expected_lookup_indices: []const i16,
) !void {
    const allocator = std.testing.allocator;
    var adjustments = std.ArrayList(model.Adjustment).empty;
    defer adjustments.deinit(allocator);

    try lookup.collect(
        built.view,
        fixture_lookup_offset,
        built.sidecar.subtable_count,
        glyphs,
        &adjustments,
        allocator,
        lookup_flag,
        run,
        &built.sidecar,
        captureRecords,
        captureNested,
    );

    try std.testing.expectEqual(expected_lookup_indices.len, adjustments.items.len);
    for (adjustments.items, expected_lookup_indices) |adjustment, expected| {
        try std.testing.expectEqual(@as(usize, 0), adjustment.index);
        try std.testing.expectEqual(expected, adjustment.x_advance);
    }
}

fn findSecond(
    sidecar: *const accelerator.model.Lookup,
    glyph: u16,
) ?[]const u16 {
    return accelerator.glyph_groups.find(
        sidecar.chaining_second_groups,
        sidecar.chaining_second_group_slots,
        glyph,
    );
}

fn captureRecords(
    view: table.View,
    records_pos: usize,
    record_count: usize,
    input_indices: []const usize,
    _: []const u16,
    adjustments: *std.ArrayList(model.Adjustment),
    allocator: std.mem.Allocator,
    _: model.Options,
) model.Error!void {
    for (0..record_count) |record_index| {
        const record = records_pos + record_index * 4;
        const sequence_index = try view.readU16(record);
        if (sequence_index >= input_indices.len) return error.BadGpos;
        try adjustments.append(allocator, .{
            .index = input_indices[sequence_index],
            .x_advance = @intCast(try view.readU16(record + 2)),
        });
    }
}

fn rejectRecords(
    _: table.View,
    _: usize,
    _: usize,
    _: []const usize,
    _: []const u16,
    _: *std.ArrayList(model.Adjustment),
    _: std.mem.Allocator,
    _: model.Options,
) model.Error!void {
    return error.InvalidShapingInput;
}

fn captureNested(
    _: table.View,
    _: []const u16,
    target_index: usize,
    lookup_index: u16,
    adjustments: *std.ArrayList(model.Adjustment),
    allocator: std.mem.Allocator,
    _: model.Options,
) model.Error!void {
    try adjustments.append(allocator, .{
        .index = target_index,
        .x_advance = @intCast(lookup_index),
    });
}

fn writeCoverage(bytes: []u8, offset: usize, glyphs: []const u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, offset + 4 + index * 2, glyph);
    }
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
