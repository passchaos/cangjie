//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const TextShaper = support.TextShaper;
const FeatureOverride = support.FeatureOverride;
const Font = support.Font;
const CharmapMapping = support.CharmapMapping;
const FontFormat = support.FontFormat;
const FontTableInfo = support.FontTableInfo;
const HorizontalMetricInfo = support.HorizontalMetricInfo;
const VerticalMetricInfo = support.VerticalMetricInfo;
const VerticalOriginMetric = support.VerticalOriginMetric;
const GlyphId = support.GlyphId;
const Bounds = support.Bounds;
const GlyphRun = support.GlyphRun;
const GlyphPosition = support.GlyphPosition;
const openTypeTag = support.openTypeTag;
const ColorRenderTarget = support.ColorRenderTarget;
const RenderTarget = support.RenderTarget;
const Rasterizer = support.Rasterizer;
const testing = support.testing;
const renderTargetPixelDifference = support.renderTargetPixelDifference;
const colorRenderTargetPixelDifference = support.colorRenderTargetPixelDifference;
const writeU16Test = support.writeU16Test;

test "loads a minimal TTF, maps Unicode, reads outline, lays out, and rasterizes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(FontFormat.truetype, font.format);
    try std.testing.expectEqual(@as(u16, 1000), font.units_per_em);
    try std.testing.expectEqual(@as(GlyphId, 1), try font.glyphIndex('A'));

    const header = try font.headInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), header.table_version);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), header.font_revision, 0.001);
    try std.testing.expectEqual(@as(u16, 1000), header.units_per_em);
    try std.testing.expectEqual(Bounds{ .x_min = 0, .y_min = 0, .x_max = 700, .y_max = 700 }, header.bounds);
    try std.testing.expectEqual(@as(u16, 8), header.lowest_rec_ppem);
    try std.testing.expectEqual(@as(i16, 0), header.index_to_loc_format);

    const maxp = try font.maxpInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), maxp.version);
    try std.testing.expectEqual(@as(u16, 2), maxp.glyph_count);
    try std.testing.expectEqual(@as(?u16, 3), maxp.max_points);
    try std.testing.expectEqual(@as(?u16, 1), maxp.max_contours);
    try std.testing.expectEqual(@as(?u16, 2), maxp.max_zones);
    try std.testing.expectEqual(@as(?u16, 0), maxp.max_component_depth);

    const hhea = try font.horizontalHeaderInfo();
    try std.testing.expectEqual(@as(u32, 0x00010000), hhea.version);
    try std.testing.expectEqual(@as(i16, 800), hhea.ascender);
    try std.testing.expectEqual(@as(i16, -200), hhea.descender);
    try std.testing.expectEqual(@as(i16, 0), hhea.line_gap);
    try std.testing.expectEqual(@as(u16, 2), hhea.long_metric_count);
    try std.testing.expect((try font.verticalHeaderInfo()) == null);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    try std.testing.expect(tables.len >= 6);
    var saw_head = false;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "head")) {
            saw_head = true;
            try std.testing.expect(table.length >= 54);
        }
    }
    try std.testing.expect(saw_head);

    var hhea_info: ?FontTableInfo = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hhea")) hhea_info = table;
    }
    const hhea_record = hhea_info orelse return error.MissingTable;
    const hhea_data = (try font.tableData(.{ 'h', 'h', 'e', 'a' })).?;
    try std.testing.expectEqual(hhea_record.length, hhea_data.len);
    try std.testing.expectEqualSlices(u8, bytes[hhea_record.offset .. hhea_record.offset + hhea_record.length], hhea_data);
    try std.testing.expect((try font.tableData(.{ 'N', 'O', 'P', 'E' })) == null);

    const charmaps = try font.charmaps(allocator);
    defer allocator.free(charmaps);
    try std.testing.expectEqual(@as(usize, 1), charmaps.len);
    try std.testing.expectEqual(@as(u16, 3), charmaps[0].platform_id);
    try std.testing.expectEqual(@as(u16, 1), charmaps[0].encoding_id);
    try std.testing.expectEqual(@as(u16, 4), charmaps[0].format);
    try std.testing.expectEqual(@as(?u32, 0), charmaps[0].language);

    const default_charmap = (try font.defaultCharmap()).?;
    try std.testing.expectEqual(charmaps[0], default_charmap);
    try std.testing.expectEqual(@as(CharmapMapping, .{ .codepoint = 'A', .glyph_id = 1 }), (try font.firstCharmapMapping(default_charmap)).?);
    try std.testing.expect((try font.nextCharmapMapping(default_charmap, 'A')) == null);

    const hmetrics = try font.horizontalMetricsTable(allocator);
    defer allocator.free(hmetrics);
    try std.testing.expectEqual(@as(usize, 2), hmetrics.len);
    try std.testing.expectEqual(HorizontalMetricInfo{ .advance_width = 500, .left_side_bearing = 0 }, hmetrics[0]);
    try std.testing.expectEqual(HorizontalMetricInfo{ .advance_width = 800, .left_side_bearing = 0 }, hmetrics[1]);
    try std.testing.expect((try font.verticalMetricsTable(allocator)) == null);

    const locations = try font.glyphLocations(allocator);
    defer allocator.free(locations);
    try std.testing.expectEqual(@as(usize, 2), locations.len);
    try std.testing.expectEqual(@as(GlyphId, 0), locations[0].glyph_id);
    try std.testing.expect(locations[0].length > 0);
    try std.testing.expect(!locations[0].empty);
    try std.testing.expectEqual(@as(GlyphId, 1), locations[1].glyph_id);
    try std.testing.expect(locations[1].length > 0);
    try std.testing.expect(!locations[1].empty);

    var outline = try font.glyphOutline(allocator, 1);
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(u16, 800), outline.advance_width);
    const bounds = try font.glyphBounds(1);
    try std.testing.expectEqual(outline.bounds, bounds);

    var layout_buffer = LayoutBuffer.init(allocator);
    defer layout_buffer.deinit();
    const run = try TextShaper.shapeUtf8(&font, &layout_buffer, "A", 20);
    try std.testing.expectEqual(@as(usize, 1), run.glyphs.len);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), run.width(), 0.001);

    const kerned = try TextShaper.shapeUtf8(&font, &layout_buffer, "AA", 20);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), kerned.width(), 0.001);

    const disable_kern = [_]FeatureOverride{.{ .tag = openTypeTag("kern"), .enabled = false }};
    const unkerned = try TextShaper.shapeUtf8WithOptions(&font, &layout_buffer, "AA", 20, .{ .features = &disable_kern });
    try std.testing.expectApproxEqAbs(@as(f32, 32.0), unkerned.width(), 0.001);

    var target = try RenderTarget.init(allocator, 32, 32);
    defer target.deinit();
    var rasterizer = Rasterizer.init(allocator);
    try rasterizer.renderRun(&target, run, 4, 24);

    var covered: usize = 0;
    for (target.pixels) |pixel| {
        if (pixel > 0) covered += 1;
    }
    try std.testing.expect(covered > 10);
}

test "VORG vertical origins are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVorgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const origins = (try font.verticalOrigins(allocator)).?;
    defer font.freeVerticalOrigins(allocator, origins);
    try std.testing.expectEqual(@as(i16, 880), origins.default_origin_y);
    try std.testing.expectEqual(@as(usize, 1), origins.metrics.len);
    try std.testing.expectEqual(VerticalOriginMetric{ .glyph_id = 1, .origin_y = 910 }, origins.metrics[0]);

    try std.testing.expectEqual(@as(?i16, 880), try font.verticalOriginY(0));
    try std.testing.expectEqual(@as(?i16, 910), try font.verticalOriginY(1));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.verticalOrigins(allocator)) == null);
    try std.testing.expect((try missing.verticalOriginY(1)) == null);
}

test "lazy VORG metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVorgTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(?i16, 910), try font.verticalOriginY(1));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var vorg_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "VORG")) vorg_offset = table.offset;
    }
    bytes[vorg_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.verticalOriginY(1));
    try std.testing.expectError(error.BadSfnt, font.verticalOrigins(allocator));
}

test "vertical header metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const vhea = (try font.verticalHeaderInfo()).?;
    try std.testing.expectEqual(@as(u32, 0x00011000), vhea.version);
    try std.testing.expectEqual(@as(i16, 800), vhea.ascender);
    try std.testing.expectEqual(@as(i16, -200), vhea.descender);
    try std.testing.expectEqual(@as(u16, 1), vhea.long_metric_count);

    const vmetrics = (try font.verticalMetricsTable(allocator)).?;
    defer allocator.free(vmetrics);
    try std.testing.expectEqual(@as(usize, 2), vmetrics.len);
    try std.testing.expectEqual(VerticalMetricInfo{ .advance_height = 1000, .top_side_bearing = 0 }, vmetrics[0]);
    try std.testing.expectEqual(VerticalMetricInfo{ .advance_height = 1000, .top_side_bearing = 0 }, vmetrics[1]);
}

test "CFF2 top-level metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCff2Otf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.cff2Info()).?;
    try std.testing.expectEqual(@as(u8, 2), info.major_version);
    try std.testing.expectEqual(@as(u8, 0), info.minor_version);
    try std.testing.expectEqual(@as(u8, 5), info.header_size);
    try std.testing.expectEqual(@as(u16, 10), info.top_dict_length);
    const global_subrs = info.global_subrs_index;
    try std.testing.expectEqual(@as(usize, 15), global_subrs.offset);
    try std.testing.expectEqual(@as(u32, 1), global_subrs.count);
    try std.testing.expectEqual(@as(u8, 1), global_subrs.off_size);
    try std.testing.expectEqual(@as(usize, 22), global_subrs.data_offset);
    try std.testing.expectEqual(@as(usize, 1), global_subrs.data_length);
    try std.testing.expectEqual(@as(?usize, 23), info.top_dict.charstrings_offset);
    try std.testing.expectEqual(@as(?usize, 43), info.top_dict.fd_array_offset);
    try std.testing.expectEqual(@as(?usize, 53), info.top_dict.fd_select_offset);
    try std.testing.expectEqual(@as(?usize, 70), info.top_dict.vstore_offset);
    const charstrings = info.charstrings_index.?;
    try std.testing.expectEqual(@as(u32, 1), charstrings.count);
    try std.testing.expectEqual(@as(u8, 1), charstrings.off_size);
    try std.testing.expectEqual(@as(usize, 30), charstrings.data_offset);
    try std.testing.expectEqual(@as(usize, 13), charstrings.data_length);
    const fd_array = info.fd_array_index.?;
    try std.testing.expectEqual(@as(u32, 1), fd_array.count);
    try std.testing.expectEqual(@as(usize, 50), fd_array.data_offset);
    try std.testing.expectEqual(@as(usize, 3), fd_array.data_length);
    const fd_select = info.fd_select.?;
    try std.testing.expectEqual(@as(usize, 53), fd_select.offset);
    try std.testing.expectEqual(@as(u8, 0), fd_select.format);
    try std.testing.expectEqual(@as(?u16, 0), try font.cff2FontDictIndex(0));
    try std.testing.expectEqual(@as(?u16, 0), try font.cff2FontDictIndex(1));
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2GlobalSubrData(0)).?);
    try std.testing.expect((try font.cff2GlobalSubrData(1)) == null);
    const font_dict = (try font.cff2FontDictInfo(0)).?;
    try std.testing.expectEqual(@as(usize, 0), font_dict.index);
    try std.testing.expectEqual(@as(usize, 50), font_dict.data_offset);
    try std.testing.expectEqual(@as(usize, 3), font_dict.data_length);
    const private = font_dict.private_dict;
    try std.testing.expectEqual(@as(usize, 56), private.offset);
    try std.testing.expectEqual(@as(usize, 6), private.size);
    try std.testing.expectEqualSlices(u8, &.{ 146, 20, 119, 21, 145, 19 }, private.data);
    try std.testing.expectEqual(@as(?i32, 7), private.default_width_x);
    try std.testing.expectEqual(@as(?i32, -20), private.nominal_width_x);
    try std.testing.expectEqual(@as(?usize, 62), private.local_subrs_offset);
    const local_subrs = private.local_subrs_index.?;
    try std.testing.expectEqual(@as(usize, 62), local_subrs.offset);
    try std.testing.expectEqual(@as(u32, 1), local_subrs.count);
    try std.testing.expectEqual(@as(usize, 69), local_subrs.data_offset);
    try std.testing.expectEqual(@as(usize, 1), local_subrs.data_length);
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2LocalSubrData(0, 0)).?);
    try std.testing.expect((try font.cff2LocalSubrData(0, 1)) == null);
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2GlobalSubrDataForOperand(-107)).?);
    try std.testing.expect((try font.cff2GlobalSubrDataForOperand(-106)) == null);
    try std.testing.expectEqualSlices(u8, &.{11}, (try font.cff2LocalSubrDataForOperand(0, -107)).?);
    try std.testing.expect((try font.cff2LocalSubrDataForOperand(0, -106)) == null);
    try std.testing.expect((try font.cff2FontDictInfo(1)) == null);
    try std.testing.expectEqualSlices(u8, &.{ 32, 10, 32, 29, 189, 159, 21, 239, 139, 139, 169, 5, 14 }, (try font.cff2CharStringData(0)).?);
    const scanned = (try font.cff2CharStringScanInfo(0)).?;
    try std.testing.expectEqual(@as(usize, 3), scanned.charstring_count);
    try std.testing.expectEqual(@as(usize, 15), scanned.byte_count);
    try std.testing.expectEqual(@as(usize, 8), scanned.number_count);
    try std.testing.expectEqual(@as(usize, 7), scanned.operator_count);
    try std.testing.expectEqual(@as(usize, 1), scanned.local_subr_call_count);
    try std.testing.expectEqual(@as(usize, 1), scanned.global_subr_call_count);
    try std.testing.expectEqual(@as(u8, 1), scanned.max_depth);
    try std.testing.expect(scanned.has_return);
    try std.testing.expect(scanned.has_endchar);
    const bounds = (try font.cff2CharStringBoundsInfo(0)).?;
    try std.testing.expect(bounds.has_bounds);
    try std.testing.expectEqual(@as(f32, 50), bounds.x_min);
    try std.testing.expectEqual(@as(f32, 20), bounds.y_min);
    try std.testing.expectEqual(@as(f32, 150), bounds.x_max);
    try std.testing.expectEqual(@as(f32, 50), bounds.y_max);
    try std.testing.expectEqual(@as(usize, 1), bounds.move_count);
    try std.testing.expectEqual(@as(usize, 2), bounds.line_count);
    try std.testing.expectEqual(@as(usize, 0), bounds.curve_count);
    try std.testing.expectEqual(@as(usize, 3), bounds.scan.charstring_count);
    try std.testing.expectEqual(@as(usize, 1), bounds.scan.local_subr_call_count);
    try std.testing.expectEqual(@as(usize, 1), bounds.scan.global_subr_call_count);
    const bounds_at_coords = (try font.cff2CharStringBoundsInfoAtCoords(0, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 50), bounds_at_coords.x_min);
    try std.testing.expectEqual(@as(f32, 150), bounds_at_coords.x_max);
    const glyph_bounds_at_coords = (try font.cff2GlyphBoundsAtCoords(0, &.{0.5})).?;
    try std.testing.expectEqual(@as(i16, 50), glyph_bounds_at_coords.x_min);
    try std.testing.expectEqual(@as(i16, 150), glyph_bounds_at_coords.x_max);
    try std.testing.expectError(error.BadSfnt, font.cff2CharStringBoundsInfoAtCoords(0, &.{std.math.nan(f32)}));
    try std.testing.expectError(error.BadSfnt, font.cff2CharStringBoundsInfoAtCoords(0, &.{1.0001}));
    try std.testing.expectError(error.BadSfnt, font.cff2GlyphBoundsAtCoords(0, &.{std.math.inf(f32)}));
    const public_bounds = try font.glyphBounds(0);
    try std.testing.expectEqual(@as(i16, 50), public_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), public_bounds.y_min);
    try std.testing.expectEqual(@as(i16, 150), public_bounds.x_max);
    try std.testing.expectEqual(@as(i16, 50), public_bounds.y_max);
    var outline = try font.glyphOutline(allocator, 0);
    defer outline.deinit();
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 20), outline.bounds.y_min);
    try std.testing.expectEqual(@as(i16, 150), outline.bounds.x_max);
    try std.testing.expectEqual(@as(i16, 50), outline.bounds.y_max);
    try std.testing.expectEqual(@as(usize, 4), outline.commands.items.len);
    try std.testing.expectEqual(@as(f32, 50), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 20), outline.commands.items[0].move_to.y);
    try std.testing.expectEqual(@as(f32, 150), outline.commands.items[1].line_to.x);
    try std.testing.expectEqual(@as(f32, 20), outline.commands.items[1].line_to.y);
    try std.testing.expectEqual(@as(f32, 150), outline.commands.items[2].line_to.x);
    try std.testing.expectEqual(@as(f32, 50), outline.commands.items[2].line_to.y);
    try std.testing.expectEqual(.close, outline.commands.items[3]);
    var outline_at_coords = (try font.cff2GlyphOutlineAtCoords(allocator, 0, &.{0.5})).?;
    defer outline_at_coords.deinit();
    try std.testing.expectEqual(@as(i16, 50), outline_at_coords.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 150), outline_at_coords.bounds.x_max);
    try std.testing.expectEqual(@as(usize, 4), outline_at_coords.commands.items.len);
    try std.testing.expectError(error.BadSfnt, font.cff2GlyphOutlineAtCoords(allocator, 0, &.{std.math.inf(f32)}));
    try std.testing.expectError(error.BadSfnt, font.cff2GlyphOutlineAtCoords(allocator, 0, &.{-1.0001}));
    try std.testing.expect((try font.cff2CharStringData(1)) == null);
    try std.testing.expect((try font.cff2CharStringScanInfo(1)) == null);
    try std.testing.expect((try font.cff2CharStringBoundsInfo(1)) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.cff2Info()) == null);
    try std.testing.expect((try missing.cff2GlobalSubrData(0)) == null);
    try std.testing.expect((try missing.cff2GlobalSubrDataForOperand(-107)) == null);
    try std.testing.expect((try missing.cff2FontDictInfo(0)) == null);
    try std.testing.expect((try missing.cff2LocalSubrData(0, 0)) == null);
    try std.testing.expect((try missing.cff2LocalSubrDataForOperand(0, -107)) == null);
    try std.testing.expect((try missing.cff2CharStringData(1)) == null);
    try std.testing.expect((try missing.cff2CharStringScanInfo(1)) == null);
    try std.testing.expect((try missing.cff2CharStringBoundsInfo(1)) == null);
    try std.testing.expect((try missing.cff2CharStringBoundsInfoAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.cff2GlyphBoundsAtCoords(1, &.{0.5})) == null);
    try std.testing.expect((try missing.cff2GlyphOutlineAtCoords(allocator, 1, &.{0.5})) == null);
    try std.testing.expect((try missing.cff2FontDictIndex(1)) == null);
}

test "CFF2 variation outline changes with normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCff2VariationOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const default_bounds = (try font.cff2GlyphBoundsAtCoords(0, &.{})).?;
    try std.testing.expectEqual(@as(i16, 50), default_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 60), default_bounds.x_max);
    const varied_bounds = (try font.cff2GlyphBoundsAtCoords(0, &.{0.5})).?;
    try std.testing.expectEqual(@as(i16, 60), varied_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 70), varied_bounds.x_max);
    const generic_varied_bounds = try font.glyphBoundsAtCoords(0, &.{0.5});
    try std.testing.expectEqual(@as(i16, 60), generic_varied_bounds.x_min);
    try std.testing.expectEqual(@as(i16, 70), generic_varied_bounds.x_max);

    var outline = (try font.cff2GlyphOutlineAtCoords(allocator, 0, &.{0.5})).?;
    defer outline.deinit();
    try std.testing.expectEqual(@as(usize, 3), outline.commands.items.len);
    try std.testing.expectEqual(@as(f32, 60), outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 70), outline.commands.items[1].line_to.x);
    var generic_outline = try font.glyphOutlineAtCoords(allocator, 0, &.{0.5});
    defer generic_outline.deinit();
    try std.testing.expectEqual(@as(f32, 60), generic_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 70), generic_outline.commands.items[1].line_to.x);
}

test "gvar metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.gvarInfo()).?;
    try std.testing.expectEqual(@as(u16, 1), info.major_version);
    try std.testing.expectEqual(@as(u16, 0), info.minor_version);
    try std.testing.expectEqual(@as(u16, 1), info.axis_count);
    try std.testing.expectEqual(@as(u16, 2), info.glyph_count);
    try std.testing.expectEqual(@as(u8, 2), info.offset_size);
    try std.testing.expectEqual(@as(usize, 0), info.glyph_variation_data_count);
    try std.testing.expect((try font.gvarGlyphInfo(0)) == null);
    try std.testing.expect((try font.gvarTupleInfo(0, 0)) == null);
    const deltas = (try font.gvarPointDeltasAtCoords(allocator, 1, &.{0.5})).?;
    defer allocator.free(deltas);
    try std.testing.expectEqual(@as(usize, 0), deltas.len);
    var default_outline = try font.glyphOutline(allocator, 1);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer varied_outline.deinit();
    try std.testing.expectEqual(default_outline.bounds, varied_outline.bounds);
    try std.testing.expectEqual(default_outline.advance_width, varied_outline.advance_width);
    try std.testing.expectEqual(@as(usize, default_outline.commands.items.len), varied_outline.commands.items.len);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.gvarInfo()) == null);
    try std.testing.expect((try missing.gvarGlyphInfo(0)) == null);
    try std.testing.expect((try missing.gvarTupleInfo(0, 0)) == null);
    try std.testing.expect((try missing.gvarPointDeltasAtCoords(allocator, 0, &.{0.5})) == null);
    try std.testing.expect((try missing.gvarPhantomPointDeltasAtCoords(allocator, 0, &.{0.5})) == null);
    try std.testing.expect((try missing.gvarGlyphBoundsAtCoords(allocator, 0, &.{0.5})) == null);
}

test "gvar point deltas are exposed for non-empty glyph data" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarDeltaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.gvarInfo()).?;
    try std.testing.expectEqual(@as(usize, 1), info.glyph_variation_data_count);
    const deltas = (try font.gvarPointDeltasAtCoords(allocator, 1, &.{0.5})).?;
    defer allocator.free(deltas);
    try std.testing.expectEqual(@as(usize, 7), deltas.len);
    try std.testing.expectEqual(@as(u16, 0), deltas[0].point);
    try std.testing.expectEqual(@as(f32, 5), deltas[0].x);
    try std.testing.expectEqual(@as(f32, 0), deltas[0].y);
    try std.testing.expectEqual(@as(f32, 1), deltas[3].x);
    try std.testing.expectEqual(@as(f32, 10), deltas[4].x);
    try std.testing.expectEqual(@as(f32, 4), deltas[5].y);
    try std.testing.expectEqual(@as(f32, -2), deltas[6].y);
    try std.testing.expectEqual(@as(u16, 6), deltas[6].point);
    try std.testing.expectEqual(@as(f32, 0), deltas[6].x);

    const phantom = (try font.gvarPhantomPointDeltasAtCoords(allocator, 1, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 1), phantom.left.x);
    try std.testing.expectEqual(@as(f32, 10), phantom.right.x);
    try std.testing.expectEqual(@as(f32, 9), phantom.horizontalAdvanceDelta());
    try std.testing.expectEqual(@as(f32, 4), phantom.top.y);
    try std.testing.expectEqual(@as(f32, -2), phantom.bottom.y);
    try std.testing.expectEqual(@as(f32, 6), phantom.verticalAdvanceDelta());

    const varied_metrics = try font.horizontalMetricsAtCoords(1, &.{0.5});
    try std.testing.expectEqual(@as(u16, 809), varied_metrics.advance_width);
    try std.testing.expectEqual(@as(i16, 1), varied_metrics.left_side_bearing);

    const varied_bounds = (try font.gvarGlyphBoundsAtCoords(allocator, 1, &.{0.5})).?;
    const default_bounds = try font.glyphBounds(1);
    try std.testing.expectEqual(default_bounds.x_min + 5, varied_bounds.x_min);
    // The generic public API must not silently fall back to the static glyf
    // header at non-default coordinates. Shape-bench extents and downstream
    // layout callers use this surface rather than the gvar-specific helper.
    try std.testing.expectEqual(varied_bounds, try font.glyphBoundsAtCoords(1, &.{0.5}));

    var default_outline = try font.glyphOutline(allocator, 1);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 1, &.{0.5});
    defer varied_outline.deinit();
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[0].move_to.x + 5), varied_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[1].line_to.x + 5), varied_outline.commands.items[1].line_to.x);
    try std.testing.expectEqual(default_outline.bounds.x_min + 5, varied_outline.bounds.x_min);
    try std.testing.expectEqual(@as(u16, 809), varied_outline.advance_width);
    try std.testing.expectEqual(@as(i16, 4), varied_outline.left_side_bearing);
}

test "gvar compound glyph deltas adjust component offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarCompoundTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const deltas = (try font.gvarPointDeltasAtCoords(allocator, 2, &.{0.5})).?;
    defer allocator.free(deltas);
    try std.testing.expectEqual(@as(usize, 5), deltas.len);
    try std.testing.expectEqual(@as(f32, 10), deltas[0].x);
    try std.testing.expectEqual(@as(f32, 9), deltas[2].x);

    const phantom = (try font.gvarPhantomPointDeltasAtCoords(allocator, 2, &.{0.5})).?;
    try std.testing.expectEqual(@as(f32, 9), phantom.horizontalAdvanceDelta());
    const varied_metrics = try font.horizontalMetricsAtCoords(2, &.{0.5});
    try std.testing.expectEqual(@as(u16, 1009), varied_metrics.advance_width);
    try std.testing.expectEqual(@as(i16, 0), varied_metrics.left_side_bearing);

    var default_outline = try font.glyphOutline(allocator, 2);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 2, &.{0.5});
    defer varied_outline.deinit();

    // Compound `gvar` point deltas apply to component placement, not to contour
    // IUP. The fixture's only component moves +10 design units at coord 0.5.
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[0].move_to.x + 10), varied_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(i16, 20), varied_outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 720), varied_outline.bounds.x_max);
    try std.testing.expectEqual(@as(u16, 1009), varied_outline.advance_width);
    try std.testing.expectEqual(@as(i16, 20), varied_outline.left_side_bearing);

    const varied_bounds = (try font.gvarGlyphBoundsAtCoords(allocator, 2, &.{0.5})).?;
    try std.testing.expectEqual(varied_outline.bounds, varied_bounds);
}

test "compound glyph point matching preserves raw off-curve indexes and nesting" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildCompoundPointMatchTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var matched = try font.glyphOutline(allocator, 2);
    defer matched.deinit();
    try std.testing.expectEqual(@as(usize, 6), matched.commands.items.len);
    try std.testing.expectEqual(@as(f32, 10), matched.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, 110), matched.commands.items[1].quad_to.control.x);
    try std.testing.expectEqual(@as(f32, 100), matched.commands.items[1].quad_to.control.y);
    try std.testing.expectEqual(@as(f32, 60), matched.commands.items[3].move_to.x);
    try std.testing.expectEqual(@as(f32, 50), matched.commands.items[3].move_to.y);
    // The two off-curve raw point 1 anchors coincide after the second
    // component's 0.5 linear transform and point-derived translation.
    try std.testing.expectEqual(matched.commands.items[1].quad_to.control, matched.commands.items[4].quad_to.control);

    var nested = try font.glyphOutline(allocator, 3);
    defer nested.deinit();
    try std.testing.expectEqual(@as(usize, 9), nested.commands.items.len);
    // Parent point 4 is relative to nested glyph 2, not to the top-level
    // scratch buffer. It anchors the third contour's raw origin at (110, 100).
    try std.testing.expectEqual(@as(f32, 110), nested.commands.items[6].move_to.x);
    try std.testing.expectEqual(@as(f32, 100), nested.commands.items[6].move_to.y);
    try std.testing.expectEqual(@as(f32, 210), nested.commands.items[7].quad_to.control.x);
    try std.testing.expectEqual(@as(f32, 200), nested.commands.items[7].quad_to.control.y);
}

test "gvar ignores component deltas for point-matched placement" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGvarPointMatchTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var default_outline = try font.glyphOutline(allocator, 4);
    defer default_outline.deinit();
    var varied_outline = try font.glyphOutlineAtCoords(allocator, 4, &.{0.5});
    defer varied_outline.deinit();

    // At coord 0.5 component 0's +20 peak delta becomes +10. The anchor point
    // therefore moves +10 and carries component 1 with it. Component 1 also has
    // a deliberately non-zero +50 peak delta; applying it would add another
    // +25 and break the point match, so all corresponding commands must differ
    // by exactly the first component's +10.
    try std.testing.expectEqual(default_outline.commands.items.len, varied_outline.commands.items.len);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[0].move_to.x + 10), varied_outline.commands.items[0].move_to.x);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[3].move_to.x + 10), varied_outline.commands.items[3].move_to.x);
    try std.testing.expectEqual(@as(f32, default_outline.commands.items[4].quad_to.control.x + 10), varied_outline.commands.items[4].quad_to.control.x);
    try std.testing.expectEqual(varied_outline.commands.items[1].quad_to.control, varied_outline.commands.items[3].move_to);
    try std.testing.expectEqual(@as(i16, 20), varied_outline.bounds.x_min);
    try std.testing.expectEqual(@as(i16, 220), varied_outline.bounds.x_max);
}
