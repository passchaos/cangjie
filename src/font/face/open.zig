//! Allocation-free SFNT face opening with explicit full-validation promotion.
//!
//! `OpenFace` matches the conventional face-open lifecycle used by FreeType:
//! it validates the collection/offset table, bounded table records, and the
//! core tables needed to expose scalar face properties. Optional table grammar
//! and whole-file checksums are validated only when `validate` promotes the
//! reference to the ordinary fully validated `Face`.

const std = @import("std");

const bin = @import("../../binary.zig");
const font_mod = @import("../../font.zig");
const face_mod = @import("root.zig");
const sfnt = @import("../sfnt/root.zig");
const core_tables = @import("../tables/core/root.zig");
const metric_tables = @import("../tables/metrics/root.zig");
const Properties = @import("properties.zig").Properties;

pub const OpenFace = struct {
    data: []const u8,
    face_index: usize,
    core_properties: Properties,

    pub fn open(data: []const u8) font_mod.FontError!OpenFace {
        return openIndex(data, 0);
    }

    pub fn openIndex(
        data: []const u8,
        face_index: usize,
    ) font_mod.FontError!OpenFace {
        const collection = try sfnt.collection.parse(data);
        const start = if (collection) |header|
            try sfnt.collection.faceOffset(data, header, face_index)
        else if (face_index == 0)
            0
        else
            return error.BadSfnt;
        if (start > data.len or 12 > data.len - start) return error.BadSfnt;

        const scaler = try bin.readU32At(data, start);
        const declared_format: font_mod.FontFormat = switch (scaler) {
            0x00010000, 0x74727565 => .truetype,
            0x4f54544f => .opentype_cff,
            else => return error.BadSfnt,
        };
        const num_tables = try bin.readU16At(data, start + 4);
        try sfnt.validateSearchParameters(
            num_tables,
            try bin.readU16At(data, start + 6),
            try bin.readU16At(data, start + 8),
            try bin.readU16At(data, start + 10),
        );
        const directory_end = try sfnt.directoryEnd(data.len, start, num_tables);
        const reserved_prefix_end = if (collection) |header| header.header_length else 0;

        var previous_tag: ?[4]u8 = null;
        var head: ?sfnt.Record = null;
        var hhea: ?sfnt.Record = null;
        var hmtx: ?sfnt.Record = null;
        var maxp: ?sfnt.Record = null;
        var cmap: ?sfnt.Record = null;
        var loca: ?sfnt.Record = null;
        var glyf: ?sfnt.Record = null;
        var cff: ?sfnt.Record = null;
        var cff2: ?sfnt.Record = null;
        var sbix: ?sfnt.Record = null;
        var cblc: ?sfnt.Record = null;
        var cbdt: ?sfnt.Record = null;
        var eblc: ?sfnt.Record = null;
        var ebdt: ?sfnt.Record = null;
        var gsub: ?sfnt.Record = null;
        var gpos: ?sfnt.Record = null;

        for (0..num_tables) |index| {
            const record = try readRecord(data, start, index);
            try validateOpenRecord(
                data,
                record,
                previous_tag,
                reserved_prefix_end,
                .{ .start = start, .end = directory_end },
                if (collection) |header| header.dsig_range else null,
            );
            previous_tag = record.tag;
            if (std.mem.eql(u8, &record.tag, "head")) head = record;
            if (std.mem.eql(u8, &record.tag, "hhea")) hhea = record;
            if (std.mem.eql(u8, &record.tag, "hmtx")) hmtx = record;
            if (std.mem.eql(u8, &record.tag, "maxp")) maxp = record;
            if (std.mem.eql(u8, &record.tag, "cmap")) cmap = record;
            if (std.mem.eql(u8, &record.tag, "loca")) loca = record;
            if (std.mem.eql(u8, &record.tag, "glyf")) glyf = record;
            if (std.mem.eql(u8, &record.tag, "CFF ")) cff = record;
            if (std.mem.eql(u8, &record.tag, "CFF2")) cff2 = record;
            if (std.mem.eql(u8, &record.tag, "sbix")) sbix = record;
            if (std.mem.eql(u8, &record.tag, "CBLC")) cblc = record;
            if (std.mem.eql(u8, &record.tag, "CBDT")) cbdt = record;
            if (std.mem.eql(u8, &record.tag, "EBLC")) eblc = record;
            if (std.mem.eql(u8, &record.tag, "EBDT")) ebdt = record;
            if (std.mem.eql(u8, &record.tag, "GSUB")) gsub = record;
            if (std.mem.eql(u8, &record.tag, "GPOS")) gpos = record;
        }

        const head_record = head orelse return error.MissingTable;
        const maxp_record = maxp orelse return error.MissingTable;
        _ = cmap orelse return error.MissingTable;
        const has_horizontal_metrics = hhea != null and hmtx != null;
        if ((hhea == null) != (hmtx == null)) return error.MissingTable;
        const has_glyf_outlines = glyf != null and loca != null;
        const has_embedded_bitmaps = sbix != null or
            (cblc != null and cbdt != null) or
            (eblc != null and ebdt != null);
        const has_layout_tables = gsub != null or gpos != null;
        const format = try core_tables.maxp.selectFormat(
            data,
            maxp_record,
            declared_format,
            has_glyf_outlines,
            cff != null or cff2 != null,
        );
        if (format == .truetype and
            !has_glyf_outlines and !has_embedded_bitmaps and !has_layout_tables)
        {
            return error.MissingTable;
        }
        if (format == .opentype_cff and
            cff == null and cff2 == null and
            !has_embedded_bitmaps and !has_layout_tables)
        {
            return error.MissingTable;
        }

        try core_tables.head.validate(data, head_record, format);
        try core_tables.maxp.validate(data, maxp_record, format);
        const head_info = try core_tables.head.info(data, head_record);
        const maxp_info = try core_tables.maxp.info(data, maxp_record);
        const horizontal = if (has_horizontal_metrics)
            try metric_tables.validateHorizontal(
                data,
                hhea.?,
                hmtx.?,
                maxp_info.glyph_count,
            )
        else
            null;

        return .{
            .data = data,
            .face_index = face_index,
            .core_properties = .{
                .format = format,
                .units_per_em = head_info.units_per_em,
                .glyph_count = maxp_info.glyph_count,
                .ascender = if (horizontal) |value| value.ascender else @intCast(head_info.units_per_em),
                .descender = if (horizontal) |value| value.descender else 0,
                .line_gap = if (horizontal) |value| value.line_gap else 0,
            },
        };
    }

    pub fn count(data: []const u8) font_mod.FontError!usize {
        return face_mod.Face.count(data);
    }

    pub fn properties(self: OpenFace) Properties {
        return self.core_properties;
    }

    /// Perform Cangjie's complete table/checksum validation and construct all
    /// reusable acceleration state needed by shaping and rendering.
    pub fn validate(
        self: OpenFace,
        allocator: std.mem.Allocator,
    ) font_mod.FontError!face_mod.Face {
        return face_mod.Face.parseIndex(allocator, self.data, self.face_index);
    }
};

fn readRecord(
    data: []const u8,
    face_offset: usize,
    index: usize,
) font_mod.FontError!sfnt.Record {
    const offset = face_offset + 12 + index * 16;
    return .{
        .tag = try bin.readTagAt(data, offset),
        .checksum = try bin.readU32At(data, offset + 4),
        .offset = try bin.readU32At(data, offset + 8),
        .length = try bin.readU32At(data, offset + 12),
    };
}

fn validateOpenRecord(
    data: []const u8,
    record: sfnt.Record,
    previous_tag: ?[4]u8,
    reserved_prefix_end: usize,
    directory: sfnt.Range,
    dsig: ?sfnt.Range,
) font_mod.FontError!void {
    try sfnt.validateTag(record.tag);
    if (previous_tag) |previous| {
        if (std.mem.order(u8, &previous, &record.tag) != .lt) {
            return error.BadSfnt;
        }
    }
    if (record.offset > data.len or record.length > data.len - record.offset) {
        return error.BadSfnt;
    }
    if (record.length == 0) return;
    if ((record.offset & 3) != 0 or record.offset < reserved_prefix_end) {
        return error.BadSfnt;
    }
    const range = sfnt.Range{
        .start = record.offset,
        .end = record.offset + record.length,
    };
    if (sfnt.overlaps(range, directory)) return error.BadSfnt;
    if (dsig) |reserved| if (sfnt.overlaps(range, reserved)) {
        return error.BadSfnt;
    };
}

test "OpenFace exposes core properties before full validation" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    const opened = try OpenFace.open(bytes);
    var validated = try opened.validate(allocator);
    defer validated.deinit();
    try std.testing.expectEqual(validated.properties(), opened.properties());
}

test "OpenFace rejects malformed core directories without allocating" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    bytes[12] = 0x01;
    try std.testing.expectError(error.BadSfnt, OpenFace.open(bytes));
}

test "OpenFace defers optional-table validation until promotion" {
    const allocator = std.testing.allocator;
    const test_font = @import("../../test_font.zig");
    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    const kern = try tableRecordByTag(bytes, "kern");
    bytes[kern.offset + kern.length - 1] ^= 1;
    const opened = try OpenFace.open(bytes);
    try std.testing.expectEqual(@as(u16, 2), opened.properties().glyph_count);
    try std.testing.expectError(error.BadSfnt, opened.validate(allocator));
}

fn tableRecordByTag(
    data: []const u8,
    comptime tag: []const u8,
) font_mod.FontError!sfnt.Record {
    const table_count = try bin.readU16At(data, 4);
    for (0..table_count) |index| {
        const record = try readRecord(data, 0, index);
        if (std.mem.eql(u8, &record.tag, tag)) return record;
    }
    return error.MissingTable;
}
