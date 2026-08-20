//! Whole-table fixtures for Script/LangSys feature-selection integration.
//!
//! The builders keep binary topology details out of the behavioral contracts
//! while still authoring complete GSUB tables instead of mocking selectors.

const std = @import("std");
const unicode = @import("../../../../unicode.zig");

pub fn writeScriptLanguageSelection(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 90);
    writeU16(bytes, 8, 142);

    writeU16(bytes, 10, 3);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 20);
    writeU32(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));
    writeU16(bytes, 22, 44);
    writeU32(bytes, 24, @intFromEnum(unicode.OpenTypeScriptTag.latn));
    writeU16(bytes, 28, 32);

    writeScript(bytes, 30, 4, 0);
    writeLangSys(bytes, 34, 2);
    writeScript(bytes, 42, 4, 0);
    writeLangSys(bytes, 46, 1);
    writeU16(bytes, 54, 10);
    writeU16(bytes, 56, 1);
    writeU32(bytes, 58, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16(bytes, 62, 18);
    writeLangSys(bytes, 64, 0);
    writeLangSys(bytes, 72, 3);

    writeU16(bytes, 90, 4);
    writeFeatureRecord(bytes, 92, unicode.tag("ccmp"), 32);
    writeFeatureRecord(bytes, 98, unicode.tag("liga"), 26);
    writeFeatureRecord(bytes, 104, unicode.tag("rclt"), 44);
    writeFeatureRecord(bytes, 110, unicode.tag("rlig"), 38);
    writeFeature(bytes, 116, 0);
    writeFeature(bytes, 122, 1);
    writeFeature(bytes, 128, 2);
    writeFeature(bytes, 134, 3);

    writeU16(bytes, 142, 4);
    writeU16(bytes, 144, 8);
    writeU16(bytes, 146, 8);
    writeU16(bytes, 148, 8);
    writeU16(bytes, 150, 8);
}

pub fn writeGlobalVerticalSelection(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 46);
    writeU16(bytes, 8, 60);

    writeU16(bytes, 10, 2);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 14);
    writeU32(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.kana));
    writeU16(bytes, 22, 24);

    // DFLT has a default LangSys but no features.
    writeU16(bytes, 24, 4);
    writeU16(bytes, 26, 0);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, 0xffff);
    writeU16(bytes, 32, 0);

    // kana owns the sole `vert` feature. Vertical selection must still find it
    // when the active DFLT LangSys does not reference that FeatureRecord.
    writeU16(bytes, 34, 4);
    writeU16(bytes, 36, 0);
    writeU16(bytes, 38, 0);
    writeU16(bytes, 40, 0xffff);
    writeU16(bytes, 42, 1);
    writeU16(bytes, 44, 0);

    writeU16(bytes, 46, 1);
    writeU32(bytes, 48, unicode.tag("vert"));
    writeU16(bytes, 52, 8);
    writeU16(bytes, 54, 0);
    writeU16(bytes, 56, 1);
    writeU16(bytes, 58, 0);

    writeU16(bytes, 60, 1);
    writeU16(bytes, 62, 4);
    writeU16(bytes, 64, 1);
    writeU16(bytes, 66, 0);
    writeU16(bytes, 68, 1);
    writeU16(bytes, 70, 8);
    writeU16(bytes, 72, 1);
    writeU16(bytes, 74, 6);
    writeI16(bytes, 76, 1);
    writeCoverage1(bytes, 78, 1);
}

pub fn writeLayoutTagOrdering(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 68);
    writeU16(bytes, 8, 90);

    writeU16(bytes, 10, 2);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 14);
    writeU32(bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));
    writeU16(bytes, 22, 54);

    writeU16(bytes, 24, 16);
    writeU16(bytes, 26, 2);
    writeU32(bytes, 28, @intFromEnum(unicode.OpenTypeLanguageTag.jan));
    writeU16(bytes, 32, 24);
    writeU32(bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));
    writeU16(bytes, 38, 32);
    writeLangSys(bytes, 40, 0);
    writeLangSys(bytes, 48, 1);
    writeLangSys(bytes, 56, 1);

    writeU16(bytes, 64, 0);
    writeU16(bytes, 66, 0);

    writeU16(bytes, 68, 2);
    writeFeatureRecord(bytes, 70, unicode.tag("ccmp"), 14);
    writeFeatureRecord(bytes, 76, unicode.tag("liga"), 18);
    writeU16(bytes, 82, 0);
    writeU16(bytes, 84, 0);
    writeU16(bytes, 86, 0);
    writeU16(bytes, 88, 0);

    writeU16(bytes, 90, 0);
}

pub fn writeRequiredFeatureSelection(
    bytes: []u8,
    required_tag: u32,
    optional_tag: u32,
) void {
    const required_first = required_tag < optional_tag;
    const required_feature_index: u16 = if (required_first) 0 else 1;
    const optional_feature_index: u16 = if (required_first) 1 else 0;

    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 60);

    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);

    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, required_feature_index);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, optional_feature_index);

    writeU16(bytes, 34, 2);
    if (required_first) {
        writeFeatureRecord(bytes, 36, required_tag, 14);
        writeFeatureRecord(bytes, 42, optional_tag, 20);
    } else {
        writeFeatureRecord(bytes, 36, optional_tag, 20);
        writeFeatureRecord(bytes, 42, required_tag, 14);
    }
    writeFeature(bytes, 48, 0);
    writeFeature(bytes, 54, 1);

    writeU16(bytes, 60, 2);
    writeU16(bytes, 62, 0);
    writeU16(bytes, 64, 0);
}

pub fn writeRepeatedLookupSelection(bytes: []u8, feature_tag: u32) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 66);

    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 16, 8);

    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 2);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, 1);

    writeU16(bytes, 34, 2);
    writeFeatureRecord(bytes, 36, feature_tag, 14);
    writeFeatureRecord(bytes, 42, feature_tag, 24);
    writeFeatureList(bytes, 48, &.{ 3, 1, 3 });
    writeFeatureList(bytes, 58, &.{ 2, 1 });

    writeU16(bytes, 66, 4);
    writeU16(bytes, 68, 0);
    writeU16(bytes, 70, 0);
    writeU16(bytes, 72, 0);
    writeU16(bytes, 74, 0);
}

fn writeScript(
    bytes: []u8,
    offset: usize,
    default_lang_offset: u16,
    language_count: u16,
) void {
    writeU16(bytes, offset, default_lang_offset);
    writeU16(bytes, offset + 2, language_count);
}

fn writeLangSys(bytes: []u8, offset: usize, feature_index: u16) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 0xffff);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, feature_index);
}

fn writeFeatureRecord(
    bytes: []u8,
    offset: usize,
    tag_value: u32,
    feature_offset: u16,
) void {
    writeU32(bytes, offset, tag_value);
    writeU16(bytes, offset + 4, feature_offset);
}

fn writeFeature(bytes: []u8, offset: usize, lookup_index: u16) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, lookup_index);
}

fn writeFeatureList(bytes: []u8, offset: usize, lookups: []const u16) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, @intCast(lookups.len));
    for (lookups, 0..) |lookup_index, index| {
        writeU16(bytes, offset + 4 + index * 2, lookup_index);
    }
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

pub fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}
