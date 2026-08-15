//! Minimal `Font` values for tests that exercise one borrowed SFNT table.

const std = @import("std");

const sfnt = @import("../../sfnt/root.zig");

/// Construct the common inert portion of a table-only Font fixture.
///
/// The caller supplies the concrete Font type to keep this test module
/// independent of `font.zig` and avoid an import cycle. Individual fixture
/// wrappers install only the table under test after this function returns.
pub fn init(
    comptime FontType: type,
    data: []const u8,
    glyph_count: u16,
    number_of_h_metrics: u16,
) FontType {
    const dummy_table = sfnt.Record{
        .tag = .{ 0, 0, 0, 0 },
        .checksum = 0,
        .offset = 0,
        .length = 0,
    };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = glyph_count,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = number_of_h_metrics,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .hdmx = null,
        .ltsh = null,
        .ltag = null,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .kerx = null,
        .mort = null,
        .morx = null,
        .os2 = null,
        .gasp = null,
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .ankr = null,
        .feat = null,
        .trak = null,
        .name = null,
        .math = null,
        .meta = null,
        .post = null,
        .pclt = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .cvt = null,
        .cvar = null,
        .gvar = null,
        .fpgm = null,
        .prep = null,
        .hvar = null,
        .mvar = null,
        .vvar = null,
        .varc = null,
        .ift = null,
        .iftx = null,
        .colr = null,
        .cpal = null,
        .base = null,
        .dsig = null,
        .vorg = null,
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .eblc = null,
        .ebdt = null,
        .glyf = null,
        .cff = null,
        .cff_parsed = null,
        .cff2 = null,
        .cmap_subtables = &.{},
        .owned_tables = &.{},
        .allocator = std.testing.allocator,
    };
}

/// Build the borrowed table record and its expected checksum in one place.
pub fn record(
    data: []const u8,
    tag: [4]u8,
    offset: usize,
    length: usize,
) sfnt.Record {
    var result = sfnt.Record{
        .tag = tag,
        .checksum = 0,
        .offset = offset,
        .length = length,
    };
    result.checksum = sfnt.checksum.table(data, result) catch 0;
    return result;
}
