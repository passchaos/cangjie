//! Integration coverage migrated from the former package root.

const std = @import("std");
const support = @import("../support.zig");
const LayoutBuffer = support.LayoutBuffer;
const FontFallbackCache = support.FontFallbackCache;
const ShapedRunCache = support.ShapedRunCache;
const TextShaper = support.TextShaper;
const Font = support.Font;
const AnkrAnchorInfo = support.AnkrAnchorInfo;
const FeatureSettingInfo = support.FeatureSettingInfo;
const GaspRange = support.GaspRange;
const TrueTypeProgramKind = support.TrueTypeProgramKind;
const MathValueRecordInfo = support.MathValueRecordInfo;
const MathGlyphValueRecordInfo = support.MathGlyphValueRecordInfo;
const MathVariantRecordInfo = support.MathVariantRecordInfo;
const MathPartRecordInfo = support.MathPartRecordInfo;
const MetricVariationIndexMapEntryInfo = support.MetricVariationIndexMapEntryInfo;
const MvarValueRecordInfo = support.MvarValueRecordInfo;
const KerxPairInfo = support.KerxPairInfo;
const MorxFeatureInfo = support.MorxFeatureInfo;
const FontCascade = support.FontCascade;
const testing = support.testing;

test "MVAR value records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.mvarInfo(allocator)).?;
    defer font.freeMvarInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    try std.testing.expectEqual(@as(u16, 8), info.value_record_size);
    try std.testing.expectEqual(@as(?usize, 28), info.item_variation_store_offset);
    try std.testing.expectEqual(@as(usize, 2), info.value_records.len);
    try std.testing.expectEqual(MvarValueRecordInfo{
        .value_tag = .{ 'h', 'a', 's', 'c' },
        .delta_set_outer_index = 0,
        .delta_set_inner_index = 0,
    }, info.value_records[0]);
    try std.testing.expect(info.value_records[0].hasVariationData());
    try std.testing.expectEqualStrings("hdsc", &info.value_records[1].value_tag);
    try std.testing.expectEqual(@as(u16, 0xffff), info.value_records[1].delta_set_outer_index);
    try std.testing.expectEqual(@as(u16, 0xffff), info.value_records[1].delta_set_inner_index);
    try std.testing.expect(!info.value_records[1].hasVariationData());

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.mvarInfo(allocator)) == null);
}

test "lazy MVAR metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMvarTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.mvarInfo(allocator)).?;
    defer font.freeMvarInfo(allocator, info);
    try std.testing.expectEqual(@as(usize, 2), info.value_records.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var mvar_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "MVAR")) mvar_offset = table.offset;
    }
    bytes[mvar_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.mvarInfo(allocator));
}

test "BASE baseline metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildBaseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.baseInfo(allocator)).?;
    defer font.freeBaseInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 0x00010000), info.version);
    const horizontal = info.horizontal.?;
    try std.testing.expectEqual(@as(usize, 2), horizontal.baseline_tags.len);
    try std.testing.expectEqualStrings("ideo", &horizontal.baseline_tags[0]);
    try std.testing.expectEqualStrings("romn", &horizontal.baseline_tags[1]);
    try std.testing.expectEqual(@as(usize, 1), horizontal.scripts.len);
    try std.testing.expectEqualStrings("latn", &horizontal.scripts[0].tag);
    try std.testing.expectEqual(@as(?u16, 1), horizontal.scripts[0].default_baseline_index);
    try std.testing.expectEqual(@as(?i16, 0), horizontal.scripts[0].coordinates[0]);
    try std.testing.expectEqual(@as(?i16, 500), horizontal.scripts[0].coordinates[1]);
    try std.testing.expect(info.vertical == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.baseInfo(allocator)) == null);
}

test "lazy BASE metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildBaseTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.baseInfo(allocator)).?;
    defer font.freeBaseInfo(allocator, info);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var base_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "BASE")) base_offset = table.offset;
    }
    bytes[base_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.baseInfo(allocator));
}

test "AAT trak records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildTrakTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.trakInfo(allocator)).?;
    defer font.freeTrakInfo(allocator, info);
    try std.testing.expectEqual(@as(usize, 1), info.horizontal.len);
    try std.testing.expectEqual(@as(usize, 0), info.vertical.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), info.horizontal[0].track, 0.001);
    try std.testing.expectEqual(@as(u16, 300), info.horizontal[0].name_id);
    try std.testing.expectEqual(@as(usize, 2), info.horizontal[0].values.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), info.horizontal[0].values[0].size, 0.001);
    try std.testing.expectEqual(@as(i16, -5), info.horizontal[0].values[0].value);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), info.horizontal[0].values[1].size, 0.001);
    try std.testing.expectEqual(@as(i16, 10), info.horizontal[0].values[1].value);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.trakInfo(allocator)) == null);
}

test "lazy AAT trak records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildTrakTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const info = (try font.trakInfo(allocator)).?;
    defer font.freeTrakInfo(allocator, info);
    try std.testing.expectEqual(@as(usize, 1), info.horizontal.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var trak_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "trak")) trak_offset = table.offset;
    }
    bytes[trak_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.trakInfo(allocator));
}

test "AAT feat records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildFeatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const features = try font.featFeatures(allocator);
    defer font.freeFeatFeatures(allocator, features);
    try std.testing.expectEqual(@as(usize, 1), features.len);
    try std.testing.expectEqual(@as(u16, 1), features[0].feature);
    try std.testing.expectEqual(@as(u16, 0x8000), features[0].flags);
    try std.testing.expectEqual(@as(u16, 300), features[0].name_id);
    try std.testing.expectEqual(@as(usize, 2), features[0].settings.len);
    try std.testing.expectEqual(FeatureSettingInfo{ .setting = 0, .name_id = 301 }, features[0].settings[0]);
    try std.testing.expectEqual(FeatureSettingInfo{ .setting = 1, .name_id = 302 }, features[0].settings[1]);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty = try missing.featFeatures(allocator);
    defer missing.freeFeatFeatures(allocator, empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "lazy AAT feat records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildFeatTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const features = try font.featFeatures(allocator);
    defer font.freeFeatFeatures(allocator, features);
    try std.testing.expectEqual(@as(usize, 1), features.len);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var feat_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "feat")) feat_offset = table.offset;
    }
    bytes[feat_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.featFeatures(allocator));
}

test "ltag records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLtagTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const records = try font.ltagRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqualStrings("zh-Hant", records[0].tag);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty = try missing.ltagRecords(allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "lazy ltag records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLtagTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const records = try font.ltagRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqualStrings("zh-Hant", records[0].tag);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ltag_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "ltag")) ltag_offset = table.offset;
    }
    bytes[ltag_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.ltagRecords(allocator));
}

test "LTSH thresholds are exposed" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLtshTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.ltshInfo(allocator)).?;
    defer font.freeLtshInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 0), info.version);
    try std.testing.expectEqualSlices(u8, &.{ 7, 11 }, info.thresholds);

    try std.testing.expectEqual(@as(?u8, 7), try font.linearThreshold(0));
    try std.testing.expectEqual(@as(?u8, 11), try font.linearThreshold(1));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.ltshInfo(allocator)) == null);
    try std.testing.expect((try missing.linearThreshold(1)) == null);
}

test "lazy LTSH metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildLtshTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(?u8, 11), try font.linearThreshold(1));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var ltsh_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "LTSH")) ltsh_offset = table.offset;
    }
    bytes[ltsh_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.linearThreshold(1));
    try std.testing.expectError(error.BadSfnt, font.ltshInfo(allocator));
}

test "hdmx metadata and widths are exposed" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildHdmxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.hdmxInfo(allocator)).?;
    defer font.freeHdmxInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 0), info.version);
    try std.testing.expectEqual(@as(u32, 4), info.record_size);
    try std.testing.expectEqual(@as(usize, 2), info.records.len);
    try std.testing.expectEqual(@as(u8, 10), info.records[0].ppem);
    try std.testing.expectEqual(@as(u8, 8), info.records[0].max_width);
    try std.testing.expectEqualSlices(u8, &.{ 5, 8 }, info.records[0].widths);
    try std.testing.expectEqualSlices(u8, &.{ 6, 12 }, info.records[1].widths);

    try std.testing.expectEqual(@as(?u8, 8), try font.hdmxWidth(10, 1));
    try std.testing.expectEqual(@as(?u8, 12), try font.hdmxWidth(16, 1));
    try std.testing.expect((try font.hdmxWidth(11, 1)) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.hdmxInfo(allocator)) == null);
    try std.testing.expect((try missing.hdmxWidth(10, 1)) == null);
}

test "lazy hdmx metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildHdmxTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqual(@as(?u8, 8), try font.hdmxWidth(10, 1));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var hdmx_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "hdmx")) hdmx_offset = table.offset;
    }
    bytes[hdmx_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.hdmxWidth(10, 1));
    try std.testing.expectError(error.BadSfnt, font.hdmxInfo(allocator));
}

test "meta records are exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const records = try font.metaRecords(allocator);
    defer allocator.free(records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqualStrings("dlng", &records[0].tag);
    try std.testing.expectEqualStrings("latn", records[0].data);

    try std.testing.expectEqualStrings("latn", (try font.metaData(.{ 'd', 'l', 'n', 'g' })).?);
    try std.testing.expect((try font.metaData(.{ 's', 'l', 'n', 'g' })) == null);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    const empty = try missing.metaRecords(allocator);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expect((try missing.metaData(.{ 'd', 'l', 'n', 'g' })) == null);
}

test "lazy meta records revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMetaTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    try std.testing.expectEqualStrings("latn", (try font.metaData(.{ 'd', 'l', 'n', 'g' })).?);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var meta_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "meta")) meta_offset = table.offset;
    }
    bytes[meta_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.metaData(.{ 'd', 'l', 'n', 'g' }));
    try std.testing.expectError(error.BadSfnt, font.metaRecords(allocator));
}

test "DSIG metadata is exposed when present" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildDsigTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.dsigInfo(allocator)).?;
    defer font.freeDsigInfo(allocator, info);
    try std.testing.expectEqual(@as(u32, 1), info.version);
    try std.testing.expectEqual(@as(u16, 1), info.flags);
    try std.testing.expectEqual(@as(usize, 1), info.signatures.len);
    try std.testing.expectEqual(@as(u32, 1), info.signatures[0].format);
    try std.testing.expectEqualStrings("sig", info.signatures[0].signature);

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.dsigInfo(allocator)) == null);
}

test "lazy DSIG metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildDsigTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    const initial = (try font.dsigInfo(allocator)).?;
    defer font.freeDsigInfo(allocator, initial);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var dsig_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "DSIG")) dsig_offset = table.offset;
    }
    bytes[dsig_offset orelse return error.MissingTable] +%= 1;
    try std.testing.expectError(error.BadSfnt, font.dsigInfo(allocator));
}

test "gasp metadata and PPEM behavior are exposed" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGaspTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const info = (try font.gaspInfo(allocator)).?;
    defer font.freeGaspInfo(allocator, info);
    try std.testing.expectEqual(@as(u16, 1), info.version);
    try std.testing.expectEqual(@as(usize, 2), info.ranges.len);
    try std.testing.expectEqual(GaspRange{ .max_ppem = 8, .behavior = 0x0003 }, info.ranges[0]);
    try std.testing.expectEqual(GaspRange{ .max_ppem = 0xffff, .behavior = 0x000f }, info.ranges[1]);

    try std.testing.expectEqual(@as(?u16, 0x0003), try font.gaspBehavior(8));
    try std.testing.expectEqual(@as(?u16, 0x000f), try font.gaspBehavior(9));

    const missing_bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(missing_bytes);
    var missing = try Font.parse(allocator, missing_bytes);
    defer missing.deinit();
    try std.testing.expect((try missing.gaspInfo(allocator)) == null);
    try std.testing.expect((try missing.gaspBehavior(12)) == null);
}

test "lazy gasp metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildGaspTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(?u16, 0x0003), try font.gaspBehavior(8));

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var gasp_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "gasp")) gasp_offset = table.offset;
    }
    bytes[gasp_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.gaspBehavior(8));
    try std.testing.expectError(error.BadSfnt, font.gaspInfo(allocator));
}

test "lazy head metadata revalidates borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(u16, 1000), (try font.headInfo()).units_per_em);

    const tables = try font.tables(allocator);
    defer allocator.free(tables);
    var head_offset: ?usize = null;
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, "head")) head_offset = table.offset;
    }
    bytes[head_offset orelse return error.MissingTable] +%= 1;

    try std.testing.expectError(error.BadSfnt, font.headInfo());
}

test "lazy metric header metadata revalidates borrowed bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../../test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(u16, 2), (try font.horizontalHeaderInfo()).long_metric_count);
        const tables = try font.tables(allocator);
        defer allocator.free(tables);
        var hhea_offset: ?usize = null;
        for (tables) |table| {
            if (std.mem.eql(u8, &table.tag, "hhea")) hhea_offset = table.offset;
        }
        bytes[hhea_offset orelse return error.MissingTable] +%= 1;
        try std.testing.expectError(error.BadSfnt, font.horizontalHeaderInfo());
        try std.testing.expectError(error.InvalidMetrics, font.horizontalMetricsTable(allocator));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expect((try font.verticalHeaderInfo()) != null);
        const tables = try font.tables(allocator);
        defer allocator.free(tables);
        var vhea_offset: ?usize = null;
        for (tables) |table| {
            if (std.mem.eql(u8, &table.tag, "vhea")) vhea_offset = table.offset;
        }
        bytes[vhea_offset orelse return error.MissingTable] +%= 1;
        try std.testing.expectError(error.BadSfnt, font.verticalHeaderInfo());
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetricsTable(allocator));
    }
}
