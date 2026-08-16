//! Whole-table fixtures for GSUB feature application integration.
//!
//! Each builder authors a complete ScriptList/FeatureList/LookupList graph so
//! integration tests exercise real selection, planning, and mutation paths.

const std = @import("std");
const unicode = @import("../../../../unicode.zig");

pub fn writeSingleFeature(
    bytes: []u8,
    script: unicode.OpenTypeScriptTag,
    feature_tag: u32,
    lookup_type: u16,
) usize {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 30);
    writeU16(bytes, 8, 44);

    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(script));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 1);
    writeU16(bytes, 28, 0);

    writeU16(bytes, 30, 1);
    writeFeatureRecord(bytes, 32, feature_tag, 8);
    writeFeature(bytes, 38, 0);

    writeU16(bytes, 44, 1);
    writeU16(bytes, 46, 4);
    writeU16(bytes, 48, lookup_type);
    writeU16(bytes, 50, 0);
    writeU16(bytes, 52, 1);
    writeU16(bytes, 54, 8);
    return 56;
}

pub fn writeSingleDeltaFeature(
    bytes: []u8,
    script: unicode.OpenTypeScriptTag,
    feature_tag: u32,
    glyph: u16,
    delta: i16,
) void {
    const subtable = writeSingleFeature(bytes, script, feature_tag, 1);
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 6);
    writeI16(bytes, subtable + 4, delta);
    writeCoverage1(bytes, subtable + 6, glyph);
}

pub fn writeMultipleFeature(
    bytes: []u8,
    script: unicode.OpenTypeScriptTag,
    feature_tag: u32,
    glyph: u16,
    replacements: []const u16,
) void {
    const subtable = writeSingleFeature(bytes, script, feature_tag, 2);
    const coverage = subtable + 8;
    const sequence = coverage + 6;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, @intCast(coverage - subtable));
    writeU16(bytes, subtable + 4, 1);
    writeU16(bytes, subtable + 6, @intCast(sequence - subtable));
    writeCoverage1(bytes, coverage, glyph);
    writeU16(bytes, sequence, @intCast(replacements.len));
    for (replacements, 0..) |replacement, index| {
        writeU16(bytes, sequence + 2 + index * 2, replacement);
    }
}

pub fn writeRandomAlternate(bytes: []u8) void {
    const alternate = writeSingleFeature(
        bytes,
        .dflt,
        unicode.tag("rand"),
        3,
    );
    writeU16(bytes, alternate, 1);
    writeU16(bytes, alternate + 2, 12);
    writeU16(bytes, alternate + 4, 1);
    writeU16(bytes, alternate + 6, 18);
    writeCoverage1(bytes, alternate + 12, 10);
    writeU16(bytes, alternate + 18, 2);
    writeU16(bytes, alternate + 20, 20);
    writeU16(bytes, alternate + 22, 30);
}

pub fn writeFeatureVariations(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010001);
    writeU16(bytes, 4, 14);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 46);
    writeU32(bytes, 10, 72);

    writeU16(bytes, 14, 1);
    writeU32(bytes, 16, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    writeU16(bytes, 20, 8);
    writeU16(bytes, 22, 4);
    writeU16(bytes, 24, 0);
    writeU16(bytes, 26, 0);
    writeU16(bytes, 28, 0xffff);
    writeU16(bytes, 30, 1);
    writeU16(bytes, 32, 0);

    writeU16(bytes, 34, 1);
    writeFeatureRecord(bytes, 36, unicode.tag("rvrn"), 8);
    writeU16(bytes, 42, 0);
    writeU16(bytes, 44, 0);

    writeU16(bytes, 46, 1);
    writeU16(bytes, 48, 4);
    writeU16(bytes, 50, 1);
    writeU16(bytes, 52, 0);
    writeU16(bytes, 54, 1);
    writeU16(bytes, 56, 8);
    writeU16(bytes, 58, 2);
    writeU16(bytes, 60, 8);
    writeU16(bytes, 62, 1);
    writeU16(bytes, 64, 2);
    writeU16(bytes, 66, 1);
    writeU16(bytes, 68, 1);
    writeU16(bytes, 70, 1);

    writeU32(bytes, 72, 0x00010000);
    writeU32(bytes, 76, 1);
    writeU32(bytes, 80, 16);
    writeU32(bytes, 84, 30);
    writeU16(bytes, 88, 1);
    writeU32(bytes, 90, 6);
    writeU16(bytes, 94, 1);
    writeU16(bytes, 96, 1);
    writeI16(bytes, 98, 8192);
    writeI16(bytes, 100, 16384);
    writeU32(bytes, 102, 0x00010000);
    writeU16(bytes, 106, 1);
    writeU16(bytes, 108, 0);
    writeU32(bytes, 110, 12);
    writeU16(bytes, 114, 0);
    writeU16(bytes, 116, 1);
    writeU16(bytes, 118, 0);
}

pub fn writeBengaliLigatureStages(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 4, 10);
    writeU16(bytes, 6, 34);
    writeU16(bytes, 8, 62);

    writeU16(bytes, 10, 1);
    writeU32(bytes, 12, @intFromEnum(unicode.OpenTypeScriptTag.beng));
    writeU16(bytes, 16, 8);
    writeU16(bytes, 18, 4);
    writeU16(bytes, 20, 0);
    writeU16(bytes, 22, 0);
    writeU16(bytes, 24, 0xffff);
    writeU16(bytes, 26, 2);
    writeU16(bytes, 28, 0);
    writeU16(bytes, 30, 1);

    writeU16(bytes, 34, 2);
    writeFeatureRecord(bytes, 36, unicode.tag("half"), 14);
    writeFeatureRecord(bytes, 42, unicode.tag("pres"), 20);
    writeFeature(bytes, 48, 0);
    writeFeature(bytes, 54, 1);

    writeU16(bytes, 62, 2);
    writeU16(bytes, 64, 6);
    writeU16(bytes, 66, 58);
    writeLigatureLookup(bytes, 68, 1, 2, 4);
    writeLigatureLookup(bytes, 120, 4, 1, 6);
}

fn writeLigatureLookup(
    bytes: []u8,
    lookup: usize,
    first: u16,
    second: u16,
    ligature: u16,
) void {
    writeU16(bytes, lookup, 4);
    writeU16(bytes, lookup + 2, 0);
    writeU16(bytes, lookup + 4, 1);
    writeU16(bytes, lookup + 6, 8);

    const subtable = lookup + 8;
    writeU16(bytes, subtable, 1);
    writeU16(bytes, subtable + 2, 18);
    writeU16(bytes, subtable + 4, 1);
    writeU16(bytes, subtable + 6, 8);

    const set = subtable + 8;
    writeU16(bytes, set, 1);
    writeU16(bytes, set + 2, 4);
    writeU16(bytes, set + 4, ligature);
    writeU16(bytes, set + 6, 2);
    writeU16(bytes, set + 8, second);
    writeCoverage1(bytes, subtable + 18, first);
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

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
