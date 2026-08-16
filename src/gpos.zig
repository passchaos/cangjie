const std = @import("std");
const accelerator_core = @import("gpos/accelerator/root.zig");
const GlyphId = @import("glyph.zig").GlyphId;
const positioning = @import("gpos/positioning/root.zig");
pub const runtime = @import("gpos/runtime/root.zig");
const runtime_lookup = @import("gpos/runtime/lookup/root.zig");
const runtime_run = @import("gpos/runtime/run.zig");
const table_core = @import("gpos/table/root.zig");
const validation = @import("gpos/validation/root.zig");
const unicode = @import("unicode.zig");

/// GPOS produces additive adjustments instead of mutating glyph ids. The caller
/// applies these deltas while constructing final glyph positions.
pub const GposError = error{
    BadGpos,
    InvalidShapingInput,
    UnsupportedGpos,
    EndOfStream,
};

pub const Adjustment = positioning.Adjustment;
pub const AttachmentType = positioning.AttachmentType;

const Table = table_core.View;

pub const VariationStore = positioning.VariationStore;

pub const LookupAccelerator = accelerator_core.model.Lookup;
pub const LookupOptions = runtime.Options;
const PairPosAcceleratorKind = accelerator_core.model.PairPositionKind;
const previousUnignoredCoveredGlyph =
    runtime_lookup.marks.search.previousUnignoredCoveredGlyph;
const pairPosSubtablesHaveNativeData =
    runtime_lookup.pair.accelerated.hasNativeData;
const buildLookupAccelerator = accelerator_core.build.lookup.one;
const deinitLookupAcceleratorContents =
    accelerator_core.build.lookup.deinitContents;

/// Validate GPOS glyph references that are meaningful at font-load time.
///
/// Shaping only visits records whose coverage matches a supplied glyph run, so
/// an out-of-range glyph id in an otherwise well-formed GPOS table could remain
/// latent until later code assumes every advertised glyph has metrics and
/// outline/bitmap contracts. This pass reuses the supported-subtable preflight
/// walker with maxp.numGlyphs attached to the table. Unsupported lookup types
/// remain ignorable, matching the shaping path, while malformed supported
/// lookups and glyph ids outside maxp are rejected.
pub fn validateGlyphBounds(data: []const u8, offset: usize, length: usize, glyph_count: u16) GposError!void {
    return validation.font.glyphBounds(
        data,
        offset,
        length,
        glyph_count,
    );
}

/// Collect positioning adjustments for a post-GSUB glyph stream.
pub fn collectAdjustments(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)!void {
    return try collectAdjustmentsWithOptions(data, offset, length, glyphs, adjustments, allocator, .{});
}

pub fn collectAdjustmentsWithOptions(data: []const u8, offset: usize, length: usize, glyphs: []const GlyphId, adjustments: *std.ArrayList(Adjustment), allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!void {
    return runtime_run.collect(
        data,
        offset,
        length,
        glyphs,
        adjustments,
        allocator,
        options,
    );
}

pub fn selectedLookupIndicesForOptions(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)![]u16 {
    return runtime_run.lookupIndicesForOptions(
        data,
        offset,
        length,
        allocator,
        options,
    );
}

pub fn buildLookupAccelerators(data: []const u8, offset: usize, length: usize, allocator: std.mem.Allocator) (GposError || std.mem.Allocator.Error)![]LookupAccelerator {
    return accelerator_core.build.lookup.all(
        data,
        offset,
        length,
        allocator,
    );
}

pub fn deinitLookupAccelerators(allocator: std.mem.Allocator, accelerators: []LookupAccelerator) void {
    accelerator_core.build.lookup.deinit(allocator, accelerators);
}

fn selectedLookupIndices(table: Table, allocator: std.mem.Allocator, options: LookupOptions) (GposError || std.mem.Allocator.Error)!std.ArrayList(u16) {
    return runtime_run.selectedLookupIndices(table, allocator, options);
}

const collectLookup = runtime_lookup.dispatcher.collect;
const collectLookupWithIndex = runtime_lookup.dispatcher.collectWithIndex;

test "GPOS simple PairPos accelerator preserves zero adjustment precedence" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    // Lookup with two PairPos alternatives.
    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 40);

    // First format-1 subtable explicitly handles (5, 7) with xAdvance=0.
    const first = 10;
    writeU16Test(&bytes, first + 0, 1);
    writeU16Test(&bytes, first + 2, 20);
    writeU16Test(&bytes, first + 4, 0x0004);
    writeU16Test(&bytes, first + 6, 0);
    writeU16Test(&bytes, first + 8, 1);
    writeU16Test(&bytes, first + 10, 12);
    const pair_set = first + 12;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 7);
    writeI16Test(&bytes, pair_set + 4, 0);
    writeCoverage1Test(&bytes, first + 20, 5);

    // Later format-2 fallback would kern the same pair by -40 if precedence is
    // lost. It remains generic in the accelerator.
    const second = 40;
    writeU16Test(&bytes, second + 0, 2);
    writeU16Test(&bytes, second + 2, 24);
    writeU16Test(&bytes, second + 4, 0x0004);
    writeU16Test(&bytes, second + 6, 0);
    writeU16Test(&bytes, second + 8, 30);
    writeU16Test(&bytes, second + 10, 38);
    writeU16Test(&bytes, second + 12, 2);
    writeU16Test(&bytes, second + 14, 2);
    writeI16Test(&bytes, second + 16, 0);
    writeI16Test(&bytes, second + 18, 0);
    writeI16Test(&bytes, second + 20, 0);
    writeI16Test(&bytes, second + 22, -40);
    writeCoverage1Test(&bytes, second + 24, 5);
    writeClassDef1Test(&bytes, second + 30, 5, 1);
    writeClassDef1Test(&bytes, second + 38, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 1), accelerator.pair_pos_records.len);
    try std.testing.expectEqual(@as(i16, 0), accelerator.pair_pos_records[0].x_advance);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{ .lookup_accelerators = &accelerators },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
}

test "GPOS ExtensionPos PairPos accelerator preserves device stride and precedence" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

    // One homogeneous ExtensionPos lookup wrapping two ordered PairPos
    // alternatives.
    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 44);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 20);
    // xAdvance plus a nullable xAdvanceDeviceOffset. The latter makes each
    // ValueRecord four bytes rather than two and exercises predecoded strides.
    writeU16Test(&bytes, first_pair + 4, 0x0044);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 12);
    const first_set = first_pair + 12;
    writeU16Test(&bytes, first_set + 0, 1);
    writeU16Test(&bytes, first_set + 2, 7);
    writeI16Test(&bytes, first_set + 4, 0);
    writeU16Test(&bytes, first_set + 6, 0);
    writeCoverage1Test(&bytes, first_pair + 20, 5);

    const second_extension = 44;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 2);
    writeU16Test(&bytes, second_pair + 2, 32);
    writeU16Test(&bytes, second_pair + 4, 0x0044);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 38);
    writeU16Test(&bytes, second_pair + 10, 46);
    writeU16Test(&bytes, second_pair + 12, 2);
    writeU16Test(&bytes, second_pair + 14, 2);
    // Four class matrix records, each xAdvance followed by a null device
    // offset. The final record would apply -40 to class (1, 1).
    for (0..4) |record_index| {
        writeI16Test(&bytes, second_pair + 16 + record_index * 4, if (record_index == 3) -40 else 0);
        writeU16Test(&bytes, second_pair + 18 + record_index * 4, 0);
    }
    writeCoverage1Test(&bytes, second_pair + 32, 5);
    writeClassDef1Test(&bytes, second_pair + 38, 5, 1);
    writeClassDef1Test(&bytes, second_pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expect(accelerator.pair_pos_extension);
    try std.testing.expectEqual(@as(usize, 2), accelerator.pair_pos_subtables.len);
    try std.testing.expectEqual(PairPosAcceleratorKind.format_1_x_advance, accelerator.pair_pos_subtables[0].kind);
    try std.testing.expectEqual(PairPosAcceleratorKind.format_2_dense_x_advance, accelerator.pair_pos_subtables[1].kind);
    const candidates = accelerator_core.glyph_groups.find(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        5,
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(u16, &.{ 0, 1 }, candidates);
    try std.testing.expect(accelerator_core.glyph_groups.find(
        accelerator.coverage_groups,
        accelerator.coverage_group_slots,
        6,
    ) == null);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = false,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    // The first wrapper explicitly handled this pair with zero adjustment.
    // The later class fallback must not override it with -40.
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
}

test "GPOS pure class PairPos lookup activates native matrix without format 1 records" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 64;

    writeU16Test(&bytes, 0, 2); // PairPos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);
    const pair = 8;
    writeU16Test(&bytes, pair + 0, 2);
    writeU16Test(&bytes, pair + 2, 32);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0);
    writeU16Test(&bytes, pair + 8, 38);
    writeU16Test(&bytes, pair + 10, 46);
    writeU16Test(&bytes, pair + 12, 2);
    writeU16Test(&bytes, pair + 14, 2);
    writeI16Test(&bytes, pair + 16, 0);
    writeI16Test(&bytes, pair + 18, 0);
    writeI16Test(&bytes, pair + 20, 0);
    writeI16Test(&bytes, pair + 22, -31);
    writeCoverage1Test(&bytes, pair + 32, 5);
    writeClassDef1Test(&bytes, pair + 38, 5, 1);
    writeClassDef1Test(&bytes, pair + 46, 7, 1);

    const table = Table{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
    const accelerator = try buildLookupAccelerator(table, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 0), accelerator.pair_pos_records.len);
    try std.testing.expect(pairPosSubtablesHaveNativeData(accelerator.pair_pos_subtables));
    // Distinguish actual native-matrix dispatch from a generic parser that
    // happens to produce the same result. Public Font shaping would reject
    // this post-proof mutation by checksum; this detached test deliberately
    // mutates only the borrowed matrix after the accelerator copied `-31`.
    writeI16Test(&bytes, pair + 22, 99);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        table,
        0,
        0,
        &.{ 5, 7 },
        &adjustments,
        allocator,
        .{
            .lookup_accelerators = &accelerators,
            .run_has_default_ignorables = false,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -31), adjustments.items[0].x_advance);
}

test "GPOS skips direct mark lookups when GDEF classes show no marks" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 56;

    writeU16Test(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const mark_base = 8;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 36);
    writeCoverage1Test(&bytes, mark_base + 12, 22);
    writeCoverage1Test(&bytes, mark_base + 18, 20);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 100, 120);

    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };
    const glyphs = [_]GlyphId{ 20, 22 };

    var fallback_adjustments = std.ArrayList(Adjustment).empty;
    defer fallback_adjustments.deinit(allocator);
    try collectLookup(table, 0, &glyphs, &fallback_adjustments, allocator, .{});
    try std.testing.expectEqual(@as(usize, 1), fallback_adjustments.items.len);

    const accelerator = try buildLookupAccelerator(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    try std.testing.expectEqual(@as(usize, 1), accelerator.mark_to_base_subtables.len);
    try std.testing.expectEqual(@as(?usize, 0), accelerator.mark_to_base_subtables[0].mark_coverage.?.index(22));
    try std.testing.expectEqual(@as(?usize, 0), accelerator.mark_to_base_subtables[0].base_coverage.?.index(20));

    var accelerated_adjustments = std.ArrayList(Adjustment).empty;
    defer accelerated_adjustments.deinit(allocator);
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        &accelerated_adjustments,
        allocator,
        .{ .lookup_accelerators = &accelerators },
        null,
    );
    try std.testing.expectEqualSlices(Adjustment, fallback_adjustments.items, accelerated_adjustments.items);

    var glyph_classes = [_]u16{0} ** 24;
    glyph_classes[20] = 1; // Base.
    glyph_classes[22] = 1; // GDEF says this covered glyph is not a mark.
    var classified_adjustments = std.ArrayList(Adjustment).empty;
    defer classified_adjustments.deinit(allocator);
    try collectLookup(table, 0, &glyphs, &classified_adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqual(@as(usize, 0), classified_adjustments.items.len);

    glyph_classes[22] = 3;
    try collectLookup(table, 0, &glyphs, &classified_adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });
    try std.testing.expectEqual(@as(usize, 1), classified_adjustments.items.len);
}

test "GPOS validates layout tag record ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 92;
    writeLayoutTagOrderingTable(&bytes);
    const table = Table{ .data = &bytes, .offset = 0, .length = bytes.len };

    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var selected = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer selected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), selected.items.len);

    // Adjacent duplicate ScriptRecords are tolerated and every child remains
    // validated. Runtime selection keeps the first authored record.
    writeU32Test(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var duplicate = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer duplicate.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), duplicate.items.len);

    // A decreasing tag still violates the searchable ScriptList topology.
    writeU32Test(&bytes, 18, unicode.tag("AAAA"));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGpos, selectedLookupIndices(table, allocator, .{ .script_tag = .dflt }));
    writeU32Test(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));

    writeU32Test(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.ara));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    writeU32Test(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));

    writeU32Test(&bytes, 76, unicode.tag("aalt"));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

test "GPOS MarkAttachmentType uses MarkAttachClassDef without glyph classes" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 26;

    writeSinglePositionLookup(&bytes, 0, 5, 0x0100, 33); // MarkAttachmentType 1.
    writeU16Test(&bytes, 16, 1);
    writeU16Test(&bytes, 18, 2);
    writeU16Test(&bytes, 20, 5);
    writeU16Test(&bytes, 22, 8);

    const glyphs = [_]GlyphId{ 5, 7, 8 };
    var mark_attach_classes = [_]u16{0} ** 9;
    mark_attach_classes[5] = 2;
    mark_attach_classes[7] = 1;
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_attach_classes = &mark_attach_classes,
    });

    // Non-zero MarkAttachClassDef entries identify marks even when GlyphClassDef
    // is absent or incomplete. Glyph 5 is a mark of the wrong attachment type,
    // so the covered SinglePos adjustment must not apply to it. Glyph 8 has no
    // attachment class and still participates as an ordinary glyph.
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "GPOS lookup flags honor GDEF mark filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{7}, &.{5} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);

    // Exercise the cached dispatch path used after Font validation.
    adjustments.clearRetainingCapacity();
    const accelerator = try buildLookupAccelerator(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer deinitLookupAcceleratorContents(allocator, @constCast(&[_]LookupAccelerator{accelerator}));
    const accelerators = [_]LookupAccelerator{accelerator};
    try collectLookupWithIndex(
        .{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true },
        0,
        0,
        &glyphs,
        &adjustments,
        allocator,
        .{
            .mark_filtering_sets = &mark_sets,
            .lookup_accelerators = &accelerators,
            .assume_validated = true,
        },
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, 33), adjustments.items[0].x_placement);
}

test "GPOS rejects missing GDEF mark filtering set indexes during shaping" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 1); // Invalid: only set 0 is supplied below.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 33);
    writeCoverage1Test(&bytes, single + 8, 5);

    const glyphs = [_]GlyphId{5};
    const mark_sets = [_][]const GlyphId{&.{5}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    // The MarkFilteringSet field is a direct index into GDEF MarkGlyphSetsDef.
    // Once those sets are available, accepting an out-of-range index would
    // turn malformed positioning into a silent no-op or a glyph-class fallback.
    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    }));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS lookup flags combine mark filtering set and attachment type" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 28;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0x0210); // MarkAttachmentType 2 + UseMarkFilteringSet.
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 0); // MarkFilteringSet index.

    const single = 10;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 41);
    writeCoverage1ListTest(&bytes, single + 8, &.{ 5, 7 });

    const glyphs = [_]GlyphId{ 5, 7 };
    var glyph_classes = [_]u16{0} ** 8;
    glyph_classes[5] = 3;
    glyph_classes[7] = 3;
    var mark_attach_classes = [_]u16{0} ** 8;
    mark_attach_classes[5] = 1;
    mark_attach_classes[7] = 2;
    const mark_sets = [_][]const GlyphId{&.{ 5, 7 }};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 41), adjustments.items[0].x_placement);
}

test "GPOS context nested lookup honors nested lookup flags" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 74;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 18, 0);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 2);
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);

    writeCoverage1Test(&bytes, context + 22, 1);
    writeSinglePositionLookup(&bytes, 52, 2, 0x0008, 50);

    const glyphs = [_]GlyphId{ 1, 2 };
    const glyph_classes = [_]u16{ 0, 1, 3 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
    });

    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS extension single positioning preflights wrapped value arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 60;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 32);

    const first_extension = 10;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 45);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_extension = 32;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 2);
    writeU16Test(&bytes, second_single + 2, 14);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeU16Test(&bytes, second_single + 6, 7);
    writeCoverage1Test(&bytes, second_single + 14, 30);
    // The second wrapped SinglePos declares seven value records, extending past
    // table.length. Reject the whole ExtensionPos lookup before the first
    // wrapper appends its otherwise valid adjustment for glyph 10.

    const glyphs = [_]GlyphId{ 10, 30 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct single positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 46;

    writeU16Test(&bytes, 0, 1); // SinglePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 26);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 45);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_single = 26;
    writeU16Test(&bytes, second_single + 0, 2);
    writeU16Test(&bytes, second_single + 2, 14);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeU16Test(&bytes, second_single + 6, 7);
    writeCoverage1Test(&bytes, second_single + 14, 30);
    // The second SinglePos subtable declares seven ValueRecords, extending past
    // table.length. Reject the lookup before collecting the first subtable's
    // otherwise valid xAdvance adjustment.

    const glyphs = [_]GlyphId{ 10, 30 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct cursive positioning preflights all subtables atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 58;

    writeU16Test(&bytes, 0, 3); // CursivePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 46);

    const first_cursive = 10;
    writeU16Test(&bytes, first_cursive + 0, 1);
    writeU16Test(&bytes, first_cursive + 2, 14);
    writeU16Test(&bytes, first_cursive + 4, 2);
    writeU16Test(&bytes, first_cursive + 6, 0);
    writeU16Test(&bytes, first_cursive + 8, 22);
    writeU16Test(&bytes, first_cursive + 10, 28);
    writeU16Test(&bytes, first_cursive + 12, 0);
    writeCoverage1ListTest(&bytes, first_cursive + 14, &.{ 10, 11 });
    writeAnchor1Test(&bytes, first_cursive + 22, 100, 50);
    writeAnchor1Test(&bytes, first_cursive + 28, 20, 10);

    const second_cursive = 46;
    writeU16Test(&bytes, second_cursive + 0, 1);
    writeU16Test(&bytes, second_cursive + 2, 6);
    writeU16Test(&bytes, second_cursive + 4, 1);
    writeU16Test(&bytes, second_cursive + 6, 1); // Truncated Coverage format 1.
    writeU16Test(&bytes, second_cursive + 8, 2);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS direct mark-to-base positioning preflights anchor arrays atomically" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU16Test(&bytes, 0, 4); // MarkBasePos lookup.
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 58);

    const first_mark_base = 10;
    writeU16Test(&bytes, first_mark_base + 0, 1);
    writeU16Test(&bytes, first_mark_base + 2, 12);
    writeU16Test(&bytes, first_mark_base + 4, 18);
    writeU16Test(&bytes, first_mark_base + 6, 1);
    writeU16Test(&bytes, first_mark_base + 8, 24);
    writeU16Test(&bytes, first_mark_base + 10, 36);
    writeCoverage1Test(&bytes, first_mark_base + 12, 2);
    writeCoverage1Test(&bytes, first_mark_base + 18, 1);
    const first_mark_array = first_mark_base + 24;
    writeU16Test(&bytes, first_mark_array + 0, 1);
    writeU16Test(&bytes, first_mark_array + 2, 0);
    writeU16Test(&bytes, first_mark_array + 4, 6);
    writeAnchor1Test(&bytes, first_mark_array + 6, 20, 30);
    const first_base_array = first_mark_base + 36;
    writeU16Test(&bytes, first_base_array + 0, 1);
    writeU16Test(&bytes, first_base_array + 2, 4);
    writeAnchor1Test(&bytes, first_base_array + 4, 100, 100);

    const second_mark_base = 58;
    writeU16Test(&bytes, second_mark_base + 0, 1);
    writeU16Test(&bytes, second_mark_base + 2, 12);
    writeU16Test(&bytes, second_mark_base + 4, 18);
    writeU16Test(&bytes, second_mark_base + 6, 1);
    writeU16Test(&bytes, second_mark_base + 8, 24);
    writeU16Test(&bytes, second_mark_base + 10, 30);
    writeCoverage1Test(&bytes, second_mark_base + 12, 2);
    writeCoverage1Test(&bytes, second_mark_base + 18, 1);
    const second_mark_array = second_mark_base + 24;
    writeU16Test(&bytes, second_mark_array + 0, 1);
    writeU16Test(&bytes, second_mark_array + 2, 0);
    writeU16Test(&bytes, second_mark_array + 4, 8); // Anchor starts exactly at table.length.

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try std.testing.expectError(error.BadGpos, collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{}));
    try std.testing.expectEqual(@as(usize, 0), adjustments.items.len);
}

test "GPOS context nested lookup can apply pair positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 96;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 2);
    // PosLookupRecord sequenceIndex=0 intentionally invokes PairPos on the
    // first glyph of the matched input. The nested lookup must still inspect
    // the following glyph in the real run and produce both pair adjustments.
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 1);

    writeU16Test(&bytes, 52, 2);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const pair = 60;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0004);
    writeU16Test(&bytes, pair + 6, 0x0001);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 1);
    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 2);
    writeI16Test(&bytes, pair_set + 4, -50);
    writeI16Test(&bytes, pair_set + 6, 20);

    const glyphs = [_]GlyphId{ 1, 2 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[1].x_placement);
}

test "GPOS context nested lookup can apply cursive positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 124;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 22);
    // The PosLookupRecord targets sequenceIndex 1. A nested CursivePos must
    // use glyph 20 as the previous cursive glyph, while leaving the unrelated
    // earlier 10-12 join untouched.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 20);

    writeU16Test(&bytes, 52, 3);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const cursive = 60;
    writeU16Test(&bytes, cursive + 0, 1);
    writeU16Test(&bytes, cursive + 2, 22);
    writeU16Test(&bytes, cursive + 4, 4);
    writeU16Test(&bytes, cursive + 6, 0);
    writeU16Test(&bytes, cursive + 8, 34);
    writeU16Test(&bytes, cursive + 10, 40);
    writeU16Test(&bytes, cursive + 12, 0);
    writeU16Test(&bytes, cursive + 14, 0);
    writeU16Test(&bytes, cursive + 16, 46);
    writeU16Test(&bytes, cursive + 18, 52);
    writeU16Test(&bytes, cursive + 20, 0);
    writeCoverage1ListTest(&bytes, cursive + 22, &.{ 10, 12, 20, 22 });
    writeAnchor1Test(&bytes, cursive + 34, 100, 30);
    writeAnchor1Test(&bytes, cursive + 40, 20, 5);
    writeAnchor1Test(&bytes, cursive + 46, 200, 70);
    writeAnchor1Test(&bytes, cursive + 52, 50, 10);

    const glyphs = [_]GlyphId{ 10, 12, 20, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 200), adjustments.items[0].x_advance);
    try std.testing.expect(adjustments.items[0].x_advance_absolute);
    try std.testing.expectEqual(@as(usize, 3), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i16, -50), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, 60), adjustments.items[1].y_placement);
}

test "GPOS single positioning subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 40;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 24);

    const first_single = 10;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 20);
    writeCoverage1Test(&bytes, first_single + 8, 10);

    const second_single = 24;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 30);
    writeCoverage1Test(&bytes, second_single + 8, 10);

    const glyphs = [_]GlyphId{10};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Lookup subtables are ordered alternatives. The second overlapping
    // SinglePos subtable must not add another xPlacement after the first match.
    try std.testing.expectEqual(@as(i16, 20), adjustments.items[0].x_placement);
}

test "GPOS pair positioning records precedence when first value is empty" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const pair = 8;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0000); // Empty valueFormat1 is common when only the second glyph moves.
    writeU16Test(&bytes, pair + 6, 0x0001);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 10);

    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, 25);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[1].x_placement);
}

test "GPOS PairPos second ValueRecord consumes overlapping second glyph" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 48;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 8);

    const pair = 8;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0x0001); // First glyph xPlacement.
    writeU16Test(&bytes, pair + 6, 0x0002); // Second glyph yPlacement.
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 18);

    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 18);
    writeI16Test(&bytes, pair_set + 4, -100);
    writeI16Test(&bytes, pair_set + 6, -100);

    const glyphs = [_]GlyphId{ 18, 18, 18, 18 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 4), adjustments.items.len);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].y_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[1].x_placement);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[1].y_placement);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[2].x_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[2].y_placement);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[3].x_placement);
    try std.testing.expectEqual(@as(i16, -100), adjustments.items[3].y_placement);
}

test "GPOS pair positioning subtables do not cascade within lookup" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 80;

    writeU16Test(&bytes, 0, 2);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 10);
    writeU16Test(&bytes, 8, 44);

    const first_pair = 10;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const second_pair = 44;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // Subtables in a lookup are alternatives. The first matching PairPos
    // subtable wins for this pair; the later matching subtable must not add its
    // xAdvance on top.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS context nested lookup can apply extension positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 90;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 1);
    writeU16Test(&bytes, rule + 2, 1);
    // PosLookupRecord invokes lookup 1, an ExtensionPos wrapping SinglePos, at
    // sequenceIndex 0. Nested extension handling must preserve the context
    // target index rather than ignoring the lookup or applying it globally.
    writeU16Test(&bytes, rule + 4, 0);
    writeU16Test(&bytes, rule + 6, 1);
    writeCoverage1Test(&bytes, context + 22, 3);

    writeU16Test(&bytes, 52, 9);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);
    const extension = 60;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 1);
    writeU32Test(&bytes, extension + 4, 8);
    const single = extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0004);
    writeI16Test(&bytes, single + 6, 70);
    writeCoverage1Test(&bytes, single + 8, 3);

    const glyphs = [_]GlyphId{3};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_advance);
}

test "GPOS accelerates nested extension chaining class positioning" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 142;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 10); // Empty ScriptList.
    writeU16Test(&bytes, 6, 12); // Empty FeatureList.
    writeU16Test(&bytes, 8, 14); // LookupList.
    writeU16Test(&bytes, 10, 0);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 6); // Lookup 0.
    writeU16Test(&bytes, 18, 106); // Lookup 1.

    const extension_lookup = 20;
    writeU16Test(&bytes, extension_lookup + 0, 9); // ExtensionPos.
    writeU16Test(&bytes, extension_lookup + 2, 0);
    writeU16Test(&bytes, extension_lookup + 4, 1);
    writeU16Test(&bytes, extension_lookup + 6, 8);

    const extension = 28;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 8); // ChainContextPos.
    writeU32Test(&bytes, extension + 4, 8);

    const chain = 36;
    writeU16Test(&bytes, chain + 0, 2); // Chaining class format.
    writeU16Test(&bytes, chain + 2, 50); // Coverage.
    writeU16Test(&bytes, chain + 4, 56); // Empty backtrack ClassDef.
    writeU16Test(&bytes, chain + 6, 62); // Input ClassDef.
    writeU16Test(&bytes, chain + 8, 70); // Lookahead ClassDef.
    writeU16Test(&bytes, chain + 10, 2);
    writeU16Test(&bytes, chain + 12, 0);
    writeU16Test(&bytes, chain + 14, 16); // Class 1 rule set.

    const set = chain + 16;
    writeU16Test(&bytes, set + 0, 2);
    writeU16Test(&bytes, set + 2, 6);
    writeU16Test(&bytes, set + 4, 20);
    const first_rule = set + 6;
    writeU16Test(&bytes, first_rule + 0, 0); // BacktrackCount.
    writeU16Test(&bytes, first_rule + 2, 1); // InputCount.
    writeU16Test(&bytes, first_rule + 4, 1); // LookaheadCount.
    writeU16Test(&bytes, first_rule + 6, 3); // Non-matching lookahead class.
    writeU16Test(&bytes, first_rule + 8, 1);
    writeU16Test(&bytes, first_rule + 10, 0);
    writeU16Test(&bytes, first_rule + 12, 1);
    const second_rule = set + 20;
    writeU16Test(&bytes, second_rule + 0, 0);
    writeU16Test(&bytes, second_rule + 2, 1);
    writeU16Test(&bytes, second_rule + 4, 1);
    writeU16Test(&bytes, second_rule + 6, 2); // Matching lookahead class.
    writeU16Test(&bytes, second_rule + 8, 1);
    writeU16Test(&bytes, second_rule + 10, 0);
    writeU16Test(&bytes, second_rule + 12, 1);

    writeCoverage1Test(&bytes, chain + 50, 10);
    writeU16Test(&bytes, chain + 56, 1); // Empty ClassDef format 1.
    writeU16Test(&bytes, chain + 58, 0);
    writeU16Test(&bytes, chain + 60, 0);
    writeClassDef1Test(&bytes, chain + 62, 10, 1);
    writeClassDef1Test(&bytes, chain + 70, 20, 2);

    writeSinglePositionLookup(&bytes, 120, 10, 0, 50);

    const glyphs = [_]GlyphId{ 10, 20 };
    const accelerators = try buildLookupAccelerators(&bytes, 0, bytes.len, allocator);
    defer deinitLookupAccelerators(allocator, accelerators);
    try std.testing.expect(accelerators[0].chaining_class_subtables.len != 0);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);
    try runtime_lookup.nested.apply(.{ .data = &bytes, .offset = 0, .length = bytes.len, .assume_validated = true }, &glyphs, 0, 0, &adjustments, allocator, .{
        .lookup_accelerators = accelerators,
        .assume_validated = true,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 50), adjustments.items[0].x_placement);
}

test "GPOS chaining coverage nested ExtensionPos SinglePos respects alternatives" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 140;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 70);

    writeU16Test(&bytes, 16, 8);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const chaining = 24;
    writeU16Test(&bytes, chaining + 0, 3);
    writeU16Test(&bytes, chaining + 2, 1);
    writeU16Test(&bytes, chaining + 4, 24);
    writeU16Test(&bytes, chaining + 6, 2);
    writeU16Test(&bytes, chaining + 8, 30);
    writeU16Test(&bytes, chaining + 10, 36);
    writeU16Test(&bytes, chaining + 12, 1);
    writeU16Test(&bytes, chaining + 14, 42);
    writeU16Test(&bytes, chaining + 16, 1);
    // Match [10, 11] only when preceded by 7 and followed by 12, then apply
    // lookup 1 to input sequenceIndex 1. The nested lookup contains two
    // ExtensionPos(SinglePos) subtables for glyph 11; the first matching
    // wrapper must win instead of cascading both SinglePos adjustments.
    writeU16Test(&bytes, chaining + 18, 1);
    writeU16Test(&bytes, chaining + 20, 1);
    writeCoverage1Test(&bytes, chaining + 24, 7);
    writeCoverage1Test(&bytes, chaining + 30, 10);
    writeCoverage1Test(&bytes, chaining + 36, 11);
    writeCoverage1Test(&bytes, chaining + 42, 12);

    writeU16Test(&bytes, 80, 9);
    writeU16Test(&bytes, 84, 2);
    writeU16Test(&bytes, 86, 10);
    writeU16Test(&bytes, 88, 32);

    const first_extension = 90;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0004);
    writeI16Test(&bytes, first_single + 6, 40);
    writeCoverage1Test(&bytes, first_single + 8, 11);

    const second_extension = 112;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0004);
    writeI16Test(&bytes, second_single + 6, 90);
    writeCoverage1Test(&bytes, second_single + 8, 11);

    const glyphs = [_]GlyphId{ 7, 10, 11, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 2), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 40), adjustments.items[0].x_advance);
}

test "GPOS context nested ExtensionPos PairPos respects alternatives with mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 170;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 54);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 18, 0x0010);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 10);
    writeU16Test(&bytes, 24, 0);

    const context = 26;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 11);
    writeU16Test(&bytes, rule + 6, 0);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 64, 9);
    writeU16Test(&bytes, 66, 0x0010);
    writeU16Test(&bytes, 68, 2);
    writeU16Test(&bytes, 70, 12);
    writeU16Test(&bytes, 72, 56);
    writeU16Test(&bytes, 74, 0);

    const first_extension = 76;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const second_extension = 120;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The unselected mark is transparent for both the outer ContextPos match
    // and the wrapped PairPos lookup. Once the first ExtensionPos(PairPos)
    // subtable matches that filtered pair, the second wrapper in the same
    // lookup must remain an alternative rather than adding another adjustment.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

test "GPOS nested chaining context can recurse into PairPos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 220;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 4);
    writeU16Test(&bytes, 12, 10); // Lookup 0: outer ChainContextPos.
    writeU16Test(&bytes, 14, 50); // Lookup 1: ExtensionPos(ChainContextPos).
    writeU16Test(&bytes, 16, 110); // Lookup 2: ChainContextPos.
    writeU16Test(&bytes, 18, 160); // Lookup 3: PairPos.

    writeU16Test(&bytes, 20, 8);
    writeU16Test(&bytes, 22, 0);
    writeU16Test(&bytes, 24, 1);
    writeU16Test(&bytes, 26, 8);
    const outer = 28;
    writeU16Test(&bytes, outer + 0, 3);
    writeU16Test(&bytes, outer + 2, 0); // BacktrackCount.
    writeU16Test(&bytes, outer + 4, 1); // InputGlyphCount.
    writeU16Test(&bytes, outer + 6, 18);
    writeU16Test(&bytes, outer + 8, 0); // LookAheadCount.
    writeU16Test(&bytes, outer + 10, 1); // PosCount.
    writeU16Test(&bytes, outer + 12, 0); // SequenceIndex 0.
    writeU16Test(&bytes, outer + 14, 1); // Lookup 1.
    writeCoverage1Test(&bytes, outer + 18, 10);

    writeU16Test(&bytes, 60, 9);
    writeU16Test(&bytes, 62, 0);
    writeU16Test(&bytes, 64, 1);
    writeU16Test(&bytes, 66, 8);
    const extension = 68;
    writeU16Test(&bytes, extension + 0, 1);
    writeU16Test(&bytes, extension + 2, 8);
    writeU32Test(&bytes, extension + 4, 8);
    const middle = extension + 8;
    writeU16Test(&bytes, middle + 0, 3);
    writeU16Test(&bytes, middle + 2, 0);
    writeU16Test(&bytes, middle + 4, 2);
    writeU16Test(&bytes, middle + 6, 22);
    writeU16Test(&bytes, middle + 8, 28);
    writeU16Test(&bytes, middle + 10, 0);
    writeU16Test(&bytes, middle + 12, 1);
    writeU16Test(&bytes, middle + 14, 0);
    writeU16Test(&bytes, middle + 16, 2);
    writeCoverage1Test(&bytes, middle + 22, 10);
    writeCoverage1Test(&bytes, middle + 28, 11);

    writeU16Test(&bytes, 120, 8);
    writeU16Test(&bytes, 122, 0);
    writeU16Test(&bytes, 124, 1);
    writeU16Test(&bytes, 126, 8);
    const inner = 128;
    writeU16Test(&bytes, inner + 0, 3);
    writeU16Test(&bytes, inner + 2, 0);
    writeU16Test(&bytes, inner + 4, 1);
    writeU16Test(&bytes, inner + 6, 18);
    writeU16Test(&bytes, inner + 8, 1);
    writeU16Test(&bytes, inner + 10, 24);
    writeU16Test(&bytes, inner + 12, 1);
    writeU16Test(&bytes, inner + 14, 0);
    writeU16Test(&bytes, inner + 16, 3);
    writeCoverage1Test(&bytes, inner + 18, 10);
    writeCoverage1Test(&bytes, inner + 24, 11);

    writeU16Test(&bytes, 170, 2);
    writeU16Test(&bytes, 172, 0);
    writeU16Test(&bytes, 174, 1);
    writeU16Test(&bytes, 176, 8);
    const pair = 178;
    writeU16Test(&bytes, pair + 0, 1);
    writeU16Test(&bytes, pair + 2, 22);
    writeU16Test(&bytes, pair + 4, 0);
    writeU16Test(&bytes, pair + 6, 0x0004);
    writeU16Test(&bytes, pair + 8, 1);
    writeU16Test(&bytes, pair + 10, 28);
    writeCoverage1Test(&bytes, pair + 22, 10);
    const pair_set = pair + 28;
    writeU16Test(&bytes, pair_set + 0, 1);
    writeU16Test(&bytes, pair_set + 2, 11);
    writeI16Test(&bytes, pair_set + 4, -70);

    const glyphs = [_]GlyphId{ 10, 11 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 20, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    try std.testing.expectEqual(@as(i16, 0), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[1].index);
    try std.testing.expectEqual(@as(i16, -70), adjustments.items[1].x_advance);
}

test "GPOS context nested lookup can apply MarkBasePos" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 106;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 12);
    // PosLookupRecord sequenceIndex=1 invokes MarkBasePos on the matched mark.
    // The nested lookup still needs the full run so it can locate glyph 10 as
    // the previous base, but it must not position marks outside this record.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 52, 4);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_base = 60;
    writeU16Test(&bytes, mark_base + 0, 1);
    writeU16Test(&bytes, mark_base + 2, 12);
    writeU16Test(&bytes, mark_base + 4, 18);
    writeU16Test(&bytes, mark_base + 6, 1);
    writeU16Test(&bytes, mark_base + 8, 24);
    writeU16Test(&bytes, mark_base + 10, 36);

    writeCoverage1Test(&bytes, mark_base + 12, 12);
    writeCoverage1Test(&bytes, mark_base + 18, 10);

    const mark_array = mark_base + 24;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const base_array = mark_base + 36;
    writeU16Test(&bytes, base_array + 0, 1);
    writeU16Test(&bytes, base_array + 2, 4);
    writeAnchor1Test(&bytes, base_array + 4, 80, 120);

    const glyphs = [_]GlyphId{ 10, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS context nested lookup applies MarkLigPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 22);
    // The context matches only [20, 22], but the nested MarkLigPos subtable
    // also covers the later [21, 22] cluster. PosLookupRecord sequenceIndex=1
    // must therefore attach just the matched mark while still using the full
    // run to find glyph 20 as its preceding ligature.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 20);

    writeU16Test(&bytes, 52, 5);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_lig = 60;
    writeU16Test(&bytes, mark_lig + 0, 1);
    writeU16Test(&bytes, mark_lig + 2, 12);
    writeU16Test(&bytes, mark_lig + 4, 18);
    writeU16Test(&bytes, mark_lig + 6, 1);
    writeU16Test(&bytes, mark_lig + 8, 26);
    writeU16Test(&bytes, mark_lig + 10, 38);

    writeCoverage1Test(&bytes, mark_lig + 12, 22);
    writeCoverage1ListTest(&bytes, mark_lig + 18, &.{ 20, 21 });

    const mark_array = mark_lig + 26;
    writeU16Test(&bytes, mark_array + 0, 1);
    writeU16Test(&bytes, mark_array + 2, 0);
    writeU16Test(&bytes, mark_array + 4, 6);
    writeAnchor1Test(&bytes, mark_array + 6, 10, 15);

    const ligature_array = mark_lig + 38;
    writeU16Test(&bytes, ligature_array + 0, 2);
    writeU16Test(&bytes, ligature_array + 2, 6);
    writeU16Test(&bytes, ligature_array + 4, 16);

    const first_ligature_attach = ligature_array + 6;
    writeU16Test(&bytes, first_ligature_attach + 0, 1);
    writeU16Test(&bytes, first_ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, first_ligature_attach + 4, 100, 120);

    const second_ligature_attach = ligature_array + 16;
    writeU16Test(&bytes, second_ligature_attach + 0, 1);
    writeU16Test(&bytes, second_ligature_attach + 2, 4);
    writeAnchor1Test(&bytes, second_ligature_attach + 4, 200, 220);

    const glyphs = [_]GlyphId{ 20, 22, 21, 22 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 90), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS context nested lookup applies MarkToMarkPos only at sequence index" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 116;

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 8, 10);
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 6);
    writeU16Test(&bytes, 14, 42);

    writeU16Test(&bytes, 16, 7);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 8);

    const context = 24;
    writeU16Test(&bytes, context + 0, 1);
    writeU16Test(&bytes, context + 2, 22);
    writeU16Test(&bytes, context + 4, 1);
    writeU16Test(&bytes, context + 6, 8);

    const set = context + 8;
    writeU16Test(&bytes, set + 0, 1);
    writeU16Test(&bytes, set + 2, 4);
    const rule = set + 4;
    writeU16Test(&bytes, rule + 0, 2);
    writeU16Test(&bytes, rule + 2, 1);
    writeU16Test(&bytes, rule + 4, 12);
    // The matched input is [10, 12], and sequenceIndex=1 targets only that
    // second glyph. A later [13, 12] mark pair is covered by MarkToMarkPos too,
    // so a nested implementation that rescans the entire run would incorrectly
    // attach the final glyph as well.
    writeU16Test(&bytes, rule + 6, 1);
    writeU16Test(&bytes, rule + 8, 1);
    writeCoverage1Test(&bytes, context + 22, 10);

    writeU16Test(&bytes, 52, 6);
    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 8);

    const mark_mark = 60;
    writeU16Test(&bytes, mark_mark + 0, 1);
    writeU16Test(&bytes, mark_mark + 2, 12);
    writeU16Test(&bytes, mark_mark + 4, 18);
    writeU16Test(&bytes, mark_mark + 6, 1);
    writeU16Test(&bytes, mark_mark + 8, 26);
    writeU16Test(&bytes, mark_mark + 10, 38);

    writeCoverage1Test(&bytes, mark_mark + 12, 12);
    writeCoverage1ListTest(&bytes, mark_mark + 18, &.{ 10, 13 });

    const mark_1_array = mark_mark + 26;
    writeU16Test(&bytes, mark_1_array + 0, 1);
    writeU16Test(&bytes, mark_1_array + 2, 0);
    writeU16Test(&bytes, mark_1_array + 4, 6);
    writeAnchor1Test(&bytes, mark_1_array + 6, 10, 15);

    const mark_2_array = mark_mark + 38;
    writeU16Test(&bytes, mark_2_array + 0, 2);
    writeU16Test(&bytes, mark_2_array + 2, 6);
    writeU16Test(&bytes, mark_2_array + 4, 12);
    writeAnchor1Test(&bytes, mark_2_array + 6, 80, 120);
    writeAnchor1Test(&bytes, mark_2_array + 12, 200, 220);

    const glyphs = [_]GlyphId{ 10, 12, 13, 12 };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 16, &glyphs, &adjustments, allocator, .{});

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 1), adjustments.items[0].index);
    try std.testing.expectEqual(@as(i16, 70), adjustments.items[0].x_placement);
    try std.testing.expectEqual(@as(i16, 105), adjustments.items[0].y_placement);
    try std.testing.expect(adjustments.items[0].markAttachment());
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[0].attachment_parent_index);
}

test "GPOS ExtensionPos single positioning subtables respect mark filtering ordering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 72;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 2);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, 36);
    writeU16Test(&bytes, 10, 0);

    const first_extension = 12;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 1);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_single = first_extension + 8;
    writeU16Test(&bytes, first_single + 0, 1);
    writeU16Test(&bytes, first_single + 2, 8);
    writeU16Test(&bytes, first_single + 4, 0x0001);
    writeI16Test(&bytes, first_single + 6, 25);
    writeCoverage1Test(&bytes, first_single + 8, 5);

    const second_extension = 36;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 1);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_single = second_extension + 8;
    writeU16Test(&bytes, second_single + 0, 1);
    writeU16Test(&bytes, second_single + 2, 8);
    writeU16Test(&bytes, second_single + 4, 0x0001);
    writeI16Test(&bytes, second_single + 6, 40);
    writeCoverage1Test(&bytes, second_single + 8, 5);

    const glyphs = [_]GlyphId{ 5, 7 };
    const mark_sets = [_][]const GlyphId{ &.{5}, &.{7} };
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    // Homogeneous ExtensionPos(SinglePos) subtables must behave like direct
    // SinglePos alternatives: the first matching wrapper wins for the original
    // mark, while the unselected mark filtering-set member remains transparent.
    try std.testing.expectEqual(@as(i16, 25), adjustments.items[0].x_placement);
}

test "GPOS mixed ExtensionPos PairPos alternatives respect mark filtering" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 128;

    writeU16Test(&bytes, 0, 9);
    writeU16Test(&bytes, 2, 0x0010); // UseMarkFilteringSet; selected mark set index follows subtable offsets.
    writeU16Test(&bytes, 4, 3);
    writeU16Test(&bytes, 6, 14);
    writeU16Test(&bytes, 8, 58);
    writeU16Test(&bytes, 10, 82);
    writeU16Test(&bytes, 12, 0);

    const first_extension = 14;
    writeU16Test(&bytes, first_extension + 0, 1);
    writeU16Test(&bytes, first_extension + 2, 2);
    writeU32Test(&bytes, first_extension + 4, 8);
    const first_pair = first_extension + 8;
    writeU16Test(&bytes, first_pair + 0, 1);
    writeU16Test(&bytes, first_pair + 2, 22);
    writeU16Test(&bytes, first_pair + 4, 0x0004);
    writeU16Test(&bytes, first_pair + 6, 0);
    writeU16Test(&bytes, first_pair + 8, 1);
    writeU16Test(&bytes, first_pair + 10, 28);
    writeCoverage1Test(&bytes, first_pair + 22, 10);
    writeU16Test(&bytes, first_pair + 28, 1);
    writeU16Test(&bytes, first_pair + 30, 11);
    writeI16Test(&bytes, first_pair + 32, -30);

    const middle_extension = 58;
    writeU16Test(&bytes, middle_extension + 0, 1);
    writeU16Test(&bytes, middle_extension + 2, 1);
    writeU32Test(&bytes, middle_extension + 4, 8);
    const single = middle_extension + 8;
    writeU16Test(&bytes, single + 0, 1);
    writeU16Test(&bytes, single + 2, 8);
    writeU16Test(&bytes, single + 4, 0x0001);
    writeI16Test(&bytes, single + 6, 25);
    writeCoverage1Test(&bytes, single + 8, 99);

    const second_extension = 82;
    writeU16Test(&bytes, second_extension + 0, 1);
    writeU16Test(&bytes, second_extension + 2, 2);
    writeU32Test(&bytes, second_extension + 4, 8);
    const second_pair = second_extension + 8;
    writeU16Test(&bytes, second_pair + 0, 1);
    writeU16Test(&bytes, second_pair + 2, 22);
    writeU16Test(&bytes, second_pair + 4, 0x0004);
    writeU16Test(&bytes, second_pair + 6, 0);
    writeU16Test(&bytes, second_pair + 8, 1);
    writeU16Test(&bytes, second_pair + 10, 28);
    writeCoverage1Test(&bytes, second_pair + 22, 10);
    writeU16Test(&bytes, second_pair + 28, 1);
    writeU16Test(&bytes, second_pair + 30, 11);
    writeI16Test(&bytes, second_pair + 32, -70);

    const glyphs = [_]GlyphId{ 10, 12, 11 };
    var glyph_classes = [_]u16{0} ** 13;
    glyph_classes[12] = 3;
    var mark_attach_classes = [_]u16{0} ** 13;
    mark_attach_classes[12] = 2;
    const mark_sets = [_][]const GlyphId{&.{13}};
    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(allocator);

    try collectLookup(.{ .data = &bytes, .offset = 0, .length = bytes.len }, 0, &glyphs, &adjustments, allocator, .{
        .glyph_classes = &glyph_classes,
        .mark_attach_classes = &mark_attach_classes,
        .mark_filtering_sets = &mark_sets,
    });

    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(@as(usize, 0), adjustments.items[0].index);
    try std.testing.expect(adjustments.items[0].pair_positioned);
    // The middle ExtensionPos(SinglePos) makes the lookup heterogeneous, so it
    // cannot use the homogeneous PairPos fast path. PairPos wrappers are still
    // ordered alternatives for glyph 10, and mark filtering keeps glyph 12
    // transparent when searching for the second glyph of the pair.
    try std.testing.expectEqual(@as(i16, -30), adjustments.items[0].x_advance);
}

fn writeSinglePositionLookup(bytes: []u8, lookup_offset: usize, glyph: GlyphId, lookup_flag: u16, x_placement: i16) void {
    writeU16Test(bytes, lookup_offset + 0, 1);
    writeU16Test(bytes, lookup_offset + 2, lookup_flag);
    writeU16Test(bytes, lookup_offset + 4, 1);
    writeU16Test(bytes, lookup_offset + 6, 8);

    const single = lookup_offset + 8;
    writeU16Test(bytes, single + 0, 1);
    writeU16Test(bytes, single + 2, 8);
    writeU16Test(bytes, single + 4, 0x0001);
    writeI16Test(bytes, single + 6, x_placement);
    writeCoverage1Test(bytes, single + 8, glyph);
}

fn writeCoverage1Test(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, glyph);
}

fn writeCoverage1ListTest(bytes: []u8, offset: usize, glyphs: []const GlyphId) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, i| {
        writeU16Test(bytes, offset + 4 + i * 2, glyph);
    }
}

fn writeClassDef1Test(bytes: []u8, offset: usize, start: GlyphId, class: u16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, start);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, class);
}

fn writeAnchor1Test(bytes: []u8, offset: usize, x: i16, y: i16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeI16Test(bytes, offset + 2, x);
    writeI16Test(bytes, offset + 4, y);
}

fn writeLangSysTest(bytes: []u8, offset: usize, feature_index: u16) void {
    writeU16Test(bytes, offset, 0);
    writeU16Test(bytes, offset + 2, 0xffff);
    writeU16Test(bytes, offset + 4, 1);
    writeU16Test(bytes, offset + 6, feature_index);
}

fn writeLayoutTagOrderingTable(bytes: []u8) void {
    writeU32Test(bytes, 0, 0x00010000);
    writeU16Test(bytes, 4, 10);
    writeU16Test(bytes, 6, 68);
    writeU16Test(bytes, 8, 90);

    writeU16Test(bytes, 10, 2);
    writeU32Test(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16Test(bytes, 16, 14);
    writeU32Test(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));
    writeU16Test(bytes, 22, 54);

    writeU16Test(bytes, 24, 16);
    writeU16Test(bytes, 26, 2);
    writeU32Test(bytes, 28, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16Test(bytes, 32, 24);
    writeU32Test(bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));
    writeU16Test(bytes, 38, 32);
    writeLangSysTest(bytes, 40, 0);
    writeLangSysTest(bytes, 48, 1);
    writeLangSysTest(bytes, 56, 1);

    writeU16Test(bytes, 64, 0);
    writeU16Test(bytes, 66, 0);

    writeU16Test(bytes, 68, 2);
    writeFeatureRecordTest(bytes, 70, unicode.tag("kern"), 14);
    writeFeatureRecordTest(bytes, 76, unicode.tag("mark"), 18);
    writeU16Test(bytes, 82, 0);
    writeU16Test(bytes, 84, 0);
    writeU16Test(bytes, 86, 0);
    writeU16Test(bytes, 88, 0);

    writeU16Test(bytes, 90, 0);
}

fn writeFeatureRecordTest(bytes: []u8, offset: usize, tag_value: u32, feature_offset: u16) void {
    writeU32Test(bytes, offset, tag_value);
    writeU16Test(bytes, offset + 4, feature_offset);
}

test {
    _ = @import("gpos/tests/accelerator/root.zig");
    _ = @import("gpos/tests/feature/root.zig");
    _ = @import("gpos/tests/positioning/root.zig");
    _ = @import("gpos/tests/runtime/root.zig");
    _ = @import("gpos/tests/table/root.zig");
    _ = @import("gpos/tests/validation/root.zig");
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn readU16(table: Table, relative: usize) GposError!u16 {
    return table.readU16(relative);
}

fn readU32(table: Table, relative: usize) GposError!u32 {
    return table.readU32(relative);
}
