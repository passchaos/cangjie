//! ScriptList, LangSys, and FeatureList ordering integration contracts.

const std = @import("std");
const options = @import("../../runtime/options.zig");
const run_selection = @import("../../feature/run_selection.zig");
const table_core = @import("../../table/root.zig");
const unicode = @import("../../../unicode.zig");
const validation = @import("../../validation/root.zig");

const Options = options.Options;
const Table = table_core.View;

fn selectedLookupIndices(view: Table, allocator: std.mem.Allocator, run: Options) !std.ArrayList(u16) {
    return run_selection.lookupIndices(view, allocator, run);
}

fn validateGlyphBounds(data: []const u8, offset: usize, length: usize, glyph_count: u16) !void {
    return validation.font.glyphBounds(data, offset, length, glyph_count);
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
    writeU32(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.dflt));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
    var duplicate = try selectedLookupIndices(table, allocator, .{ .script_tag = .dflt });
    defer duplicate.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), duplicate.items.len);

    // A decreasing tag still violates the searchable ScriptList topology.
    writeU32(&bytes, 18, unicode.tag("AAAA"));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    try std.testing.expectError(error.BadGpos, selectedLookupIndices(table, allocator, .{ .script_tag = .dflt }));
    writeU32(&bytes, 18, @intFromEnum(unicode.OpenTypeScriptTag.hani));

    writeU32(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.ara));
    try std.testing.expectError(error.BadGpos, validateGlyphBounds(&bytes, 0, bytes.len, 4));
    writeU32(&bytes, 34, @intFromEnum(unicode.OpenTypeLanguageTag.kor));

    writeU32(&bytes, 76, unicode.tag("aalt"));
    try validateGlyphBounds(&bytes, 0, bytes.len, 4);
}

fn writeLayoutTagOrderingTable(bytes: []u8) void {
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
    writeFeatureRecord(bytes, 70, unicode.tag("kern"), 14);
    writeFeatureRecord(bytes, 76, unicode.tag("mark"), 18);
    writeU16(bytes, 82, 0);
    writeU16(bytes, 84, 0);
    writeU16(bytes, 86, 0);
    writeU16(bytes, 88, 0);
    writeU16(bytes, 90, 0);
}

fn writeLangSys(bytes: []u8, offset: usize, feature_index: u16) void {
    writeU16(bytes, offset, 0);
    writeU16(bytes, offset + 2, 0xffff);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, feature_index);
}

fn writeFeatureRecord(bytes: []u8, offset: usize, tag_value: u32, feature_offset: u16) void {
    writeU32(bytes, offset, tag_value);
    writeU16(bytes, offset + 4, feature_offset);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
