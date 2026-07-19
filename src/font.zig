const std = @import("std");
const bin = @import("binary.zig");
const cff_mod = @import("cff.zig");
const glyph_mod = @import("glyph.zig");
const gpos_mod = @import("gpos.zig");
const gsub_mod = @import("gsub.zig");

/// Errors intentionally preserve the table family that failed. Callers such as
/// render bridges can distinguish malformed SFNT data from unsupported outline
/// formats or unsupported shaping subtables without losing allocator failures.
pub const FontError = error{
    BadSfnt,
    MissingTable,
    UnsupportedCmap,
    UnsupportedGlyph,
    UnsupportedCff,
    InvalidGlyph,
    InvalidLoca,
    InvalidMetrics,
    CompoundDepthExceeded,
    InvalidName,
} || cff_mod.CffError || gpos_mod.GposError || gsub_mod.GsubError || std.mem.Allocator.Error || error{EndOfStream};

pub const FontFormat = enum {
    truetype,
    opentype_cff,
};

pub const NameId = enum(u16) {
    copyright = 0,
    family = 1,
    subfamily = 2,
    unique_id = 3,
    full_name = 4,
    version = 5,
    postscript_name = 6,
    typographic_family = 16,
    typographic_subfamily = 17,
    compatible_full_name = 18,
    sample_text = 19,
    _,
};

pub const StyleAttributes = struct {
    weight: u16 = 400,
    width: u16 = 5,
    italic: bool = false,
    bold: bool = false,
};

pub const VariationAxis = struct {
    tag: [4]u8,
    min_value: f32,
    default_value: f32,
    max_value: f32,
    flags: u16,
    name_id: u16,

    pub fn clamp(self: VariationAxis, value: f32) f32 {
        return @min(self.max_value, @max(self.min_value, value));
    }

    pub fn normalize(self: VariationAxis, value: f32) f32 {
        const clamped = self.clamp(value);
        if (clamped == self.default_value) return 0;
        if (clamped < self.default_value) {
            const span = self.default_value - self.min_value;
            if (span == 0) return 0;
            return (clamped - self.default_value) / span;
        }
        const span = self.max_value - self.default_value;
        if (span == 0) return 0;
        return (clamped - self.default_value) / span;
    }
};

pub const VariationCoordinate = struct {
    tag: [4]u8,
    value: f32,
};

pub const ColorLayer = struct {
    glyph_id: glyph_mod.GlyphId,
    palette_index: u16,
};

pub const PaletteColor = struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8,
};

pub const ColorPaint = union(enum) {
    solid: Solid,
    glyph: Glyph,
    layers: Layers,

    pub const Solid = struct {
        palette_index: u16,
        alpha: f32,
    };

    pub const Glyph = struct {
        glyph_id: glyph_mod.GlyphId,
        solid: Solid,
    };

    pub const Layers = struct {
        first_layer_index: u32,
        layer_count: u8,
    };
};

pub const SvgGlyphDocument = struct {
    start_glyph_id: glyph_mod.GlyphId,
    end_glyph_id: glyph_mod.GlyphId,
    data: []const u8,
};

pub const BitmapGlyphPng = struct {
    ppem: u16,
    ppi: u16,
    origin_offset_x: i16,
    origin_offset_y: i16,
    width: u32,
    height: u32,
    data: []const u8,
};

pub const GlyphClass = enum(u16) {
    unclassified = 0,
    base = 1,
    ligature = 2,
    mark = 3,
    component = 4,
    _,
};

const TableRecord = struct {
    tag: [4]u8,
    checksum: u32,
    offset: usize,
    length: usize,
};

const CmapSubtable = struct {
    platform_id: u16,
    encoding_id: u16,
    offset: usize,
    length: usize,
    format: u16,
};

pub const Font = struct {
    /// The font is a borrowed byte slice. Table records and cmap subtable
    /// descriptors below only point back into this slice, so the caller must
    /// keep `data` alive for the lifetime of the Font.
    data: []const u8,
    format: FontFormat,
    units_per_em: u16,
    index_to_loc_format: i16,
    glyph_count: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    number_of_h_metrics: u16,
    head: TableRecord,
    hhea: TableRecord,
    maxp: TableRecord,
    hmtx: TableRecord,
    loca: ?TableRecord,
    cmap: TableRecord,
    kern: ?TableRecord,
    os2: ?TableRecord,
    gdef: ?TableRecord,
    gpos: ?TableRecord,
    gsub: ?TableRecord,
    name: ?TableRecord,
    stat: ?TableRecord,
    fvar: ?TableRecord,
    avar: ?TableRecord,
    colr: ?TableRecord,
    cpal: ?TableRecord,
    svg: ?TableRecord,
    sbix: ?TableRecord,
    cblc: ?TableRecord,
    cbdt: ?TableRecord,
    glyf: ?TableRecord,
    cff: ?TableRecord,
    cmap_subtables: []CmapSubtable,
    owned_tables: []TableRecord,
    allocator: std.mem.Allocator,

    /// Parse the first face of a standalone SFNT or TrueType Collection.
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) FontError!Font {
        return parseFace(allocator, data, 0);
    }

    pub fn faceCount(data: []const u8) FontError!usize {
        const header = (try parseTtcHeader(data)) orelse return 1;
        return header.face_count;
    }

    /// Parse a single face from either a plain SFNT file or a TTC.
    ///
    /// TTC face offsets are absolute from the start of the collection, while
    /// SFNT table records are absolute from the start of the font file. Keeping
    /// both as absolute offsets lets the rest of the parser use one addressing
    /// model for TTF, OTF/CFF, and TTC-backed faces.
    pub fn parseFace(allocator: std.mem.Allocator, data: []const u8, face_index: usize) FontError!Font {
        const start = try sfntOffset(data, face_index);
        if (start >= data.len) return error.BadSfnt;
        var r = bin.Reader.init(data);
        try r.seek(start);
        const scaler = try r.readU32();
        const format: FontFormat = switch (scaler) {
            0x00010000, 0x74727565 => .truetype,
            0x4f54544f => .opentype_cff,
            else => return error.BadSfnt,
        };
        const num_tables = try r.readU16();
        const search_range = try r.readU16();
        const entry_selector = try r.readU16();
        const range_shift = try r.readU16();
        try validateSfntSearchParameters(num_tables, search_range, entry_selector, range_shift);
        const directory_end = try sfntDirectoryEnd(data, start, num_tables);
        const reserved_prefix_end = if (try parseTtcHeader(data)) |header| header.header_length else 0;

        // Table records are kept after parsing because nearly every public
        // method lazily consults optional tables such as GSUB, GPOS, COLR, or
        // SVG. The parser validates bounds here so later code can slice safely.
        const records = try allocator.alloc(TableRecord, num_tables);
        errdefer allocator.free(records);
        for (records) |*record| {
            record.* = .{
                .tag = try r.tag(),
                .checksum = try r.readU32(),
                .offset = try r.readU32(),
                .length = try r.readU32(),
            };
            if (record.offset > data.len or record.length > data.len - record.offset) {
                return error.BadSfnt;
            }
        }
        try validateSfntTableDirectory(records);
        try validateSfntTableRanges(records, reserved_prefix_end, start, directory_end);

        const head = findTable(records, "head") orelse return error.MissingTable;
        const hhea = findTable(records, "hhea") orelse return error.MissingTable;
        const maxp = findTable(records, "maxp") orelse return error.MissingTable;
        const hmtx = findTable(records, "hmtx") orelse return error.MissingTable;
        const loca = findTable(records, "loca");
        const cmap = findTable(records, "cmap") orelse return error.MissingTable;
        const kern = findTable(records, "kern");
        const os2 = findTable(records, "OS/2");
        const gdef = findTable(records, "GDEF");
        const gpos = findTable(records, "GPOS");
        const gsub = findTable(records, "GSUB");
        const name = findTable(records, "name");
        const post = findTable(records, "post");
        const stat = findTable(records, "STAT");
        const fvar = findTable(records, "fvar");
        const avar = findTable(records, "avar");
        const colr = findTable(records, "COLR");
        const cpal = findTable(records, "CPAL");
        const svg = findTable(records, "SVG ");
        const sbix = findTable(records, "sbix");
        const cblc = findTable(records, "CBLC");
        const cbdt = findTable(records, "CBDT");
        const glyf = findTable(records, "glyf");
        const cff = findTable(records, "CFF ");
        const vhea = findTable(records, "vhea");
        const vmtx = findTable(records, "vmtx");
        const gvar = findTable(records, "gvar");
        const hvar = findTable(records, "HVAR");
        const mvar = findTable(records, "MVAR");
        const vvar = findTable(records, "VVAR");

        if (format == .truetype and (glyf == null or loca == null)) return error.MissingTable;
        if (format == .opentype_cff and cff == null) return error.MissingTable;

        // The offsets in the directory have already been checked against the
        // whole SFNT byte slice. These minimum sizes deliberately check the
        // *declared table records* before reading cross-table fields below, so
        // a truncated head/hhea/maxp table cannot borrow bytes from the next
        // physical table in the file.
        try validateHeadTable(data, head, format);
        try validateMaxpTable(data, maxp, format);

        const glyph_count = try bin.readU16At(data, maxp.offset + 4);
        if (post) |post_table| try validatePostTable(data, post_table, glyph_count);
        const number_of_h_metrics = try validateHorizontalMetricsTables(data, hhea, hmtx, glyph_count);
        try validateVerticalMetricsTables(data, glyph_count, vhea, vmtx);
        if (os2) |os2_table| try validateOs2Table(data, os2_table);
        if (name) |name_table| try validateNameTable(data, name_table);
        if (fvar) |fvar_table| try validateFvarTable(data, fvar_table);
        if (avar) |avar_table| try validateAvarTable(data, avar_table, fvar);
        if (kern) |kern_table| try validateKernTable(data, kern_table, glyph_count);

        const units_per_em = try bin.readU16At(data, head.offset + 18);
        const index_to_loc_format = try bin.readI16At(data, head.offset + 50);
        const ascender = try bin.readI16At(data, hhea.offset + 4);
        const descender = try bin.readI16At(data, hhea.offset + 6);
        const line_gap = try bin.readI16At(data, hhea.offset + 8);
        if (format == .opentype_cff) {
            try validateCffGlyphCount(data, cff.?, glyph_count);
        }
        if (format == .truetype) {
            const max_component_elements = try bin.readU16At(data, maxp.offset + 28);
            const max_component_depth = try bin.readU16At(data, maxp.offset + 30);
            try validateLocaTable(data, loca.?, glyf.?, glyph_count, index_to_loc_format);
            try validateGlyfTable(
                allocator,
                data,
                loca.?,
                glyf.?,
                glyph_count,
                index_to_loc_format,
                max_component_elements,
                max_component_depth,
            );
        }
        const gvar_target_context: ?GvarGlyphTargetContext = if (format == .truetype)
            .{ .loca = loca.?, .glyf = glyf.?, .index_to_loc_format = index_to_loc_format }
        else
            null;
        try validateVariationDataTables(data, glyph_count, fvar, gvar, hvar, mvar, vvar, gvar_target_context);
        try validateVariationNameReferences(allocator, data, fvar, stat, name);
        if (gdef) |gdef_table| try validateGdefTable(data, gdef_table, glyph_count);
        if (gsub) |gsub_table| try gsub_mod.validateGlyphBounds(data, gsub_table.offset, gsub_table.length, glyph_count);
        if (gpos) |gpos_table| try gpos_mod.validateGlyphBounds(data, gpos_table.offset, gpos_table.length, glyph_count);
        if (cpal) |cpal_table| {
            _ = try validateCpalPaletteEntries(data, cpal_table);
            try validateCpalNameReferences(data, cpal_table, name);
        }
        if (colr) |colr_table| {
            try validateColrV1TopLevelStructuralRanges(data, colr_table);
            try validateColrVariationData(data, colr_table, fvar, glyph_count);
            try validateColrGlyphBounds(data, colr_table, glyph_count);
            try validateColrPaletteBounds(data, colr_table, cpal);
        }
        if (svg) |svg_table| try validateSvgGlyphBounds(allocator, data, svg_table, glyph_count);
        if (sbix) |sbix_table| try validateSbixTable(data, sbix_table, glyph_count);
        if (cblc != null and cbdt != null) try validateCblcCbdtTables(data, cblc.?, cbdt.?, glyph_count);

        // Record all cmap subtables once. `glyphIndex` can then pick the best
        // supported Unicode mapping per lookup without reparsing the directory.
        const cmap_subtables = try parseCmapSubtables(allocator, data, cmap, glyph_count);
        errdefer allocator.free(cmap_subtables);

        return .{
            .data = data,
            .format = format,
            .units_per_em = units_per_em,
            .index_to_loc_format = index_to_loc_format,
            .glyph_count = glyph_count,
            .ascender = ascender,
            .descender = descender,
            .line_gap = line_gap,
            .number_of_h_metrics = number_of_h_metrics,
            .head = head,
            .hhea = hhea,
            .maxp = maxp,
            .hmtx = hmtx,
            .loca = loca,
            .cmap = cmap,
            .kern = kern,
            .os2 = os2,
            .gdef = gdef,
            .gpos = gpos,
            .gsub = gsub,
            .name = name,
            .stat = stat,
            .fvar = fvar,
            .avar = avar,
            .colr = colr,
            .cpal = cpal,
            .svg = svg,
            .sbix = sbix,
            .cblc = cblc,
            .cbdt = cbdt,
            .glyf = glyf,
            .cff = cff,
            .cmap_subtables = cmap_subtables,
            .owned_tables = records,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Font) void {
        self.allocator.free(self.cmap_subtables);
        self.allocator.free(self.owned_tables);
        self.* = undefined;
    }

    /// Map a Unicode scalar value to a glyph id using the best supported cmap.
    ///
    /// Format 12 is preferred for precise full-Unicode coverage, which matters
    /// for CJK extension planes. Format 8 is a rarely used mixed-width Unicode
    /// map, but it still carries supplementary-plane coverage and should win
    /// over BMP-only maps. Format 13 is the OpenType "many-to-one" fallback
    /// cmap used by last-resort fonts; it is less specific than format 12 but
    /// still materially better than reporting UnsupportedCmap.
    pub fn glyphIndex(self: *const Font, codepoint: u21) FontError!glyph_mod.GlyphId {
        var best: ?CmapSubtable = null;
        for (self.cmap_subtables) |subtable| {
            if (subtable.format != 0 and subtable.format != 2 and subtable.format != 4 and subtable.format != 6 and subtable.format != 8 and subtable.format != 10 and subtable.format != 12 and subtable.format != 13) continue;
            if (best == null or scoreCmap(subtable) > scoreCmap(best.?)) best = subtable;
        }
        const chosen = best orelse return error.UnsupportedCmap;
        return switch (chosen.format) {
            0 => try glyphIndexFormat0(self.data, chosen.offset, codepoint),
            2 => try glyphIndexFormat2(self.data, chosen.offset, chosen.length, codepoint),
            4 => try glyphIndexFormat4(self.data, chosen.offset, codepoint),
            6 => try glyphIndexFormat6(self.data, chosen.offset, codepoint),
            8 => try glyphIndexFormat8(self.data, chosen.offset, chosen.length, codepoint),
            10 => try glyphIndexFormat10(self.data, chosen.offset, chosen.length, codepoint),
            12 => try glyphIndexFormat12(self.data, chosen.offset, chosen.length, codepoint),
            13 => try glyphIndexFormat13(self.data, chosen.offset, chosen.length, codepoint),
            else => error.UnsupportedCmap,
        };
    }

    /// Return horizontal metrics following the hmtx compression rule: glyphs
    /// after `numberOfHMetrics` reuse the last advance width and provide only a
    /// per-glyph left side bearing.
    pub fn horizontalMetrics(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!struct { advance_width: u16, left_side_bearing: i16 } {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const required_length = try hmtxRequiredLength(self.glyph_count, self.number_of_h_metrics);
        if (self.hmtx.length < required_length) return error.InvalidMetrics;
        if (glyph_id < self.number_of_h_metrics) {
            const offset = self.hmtx.offset + @as(usize, glyph_id) * 4;
            return .{
                .advance_width = try bin.readU16At(self.data, offset),
                .left_side_bearing = try bin.readI16At(self.data, offset + 2),
            };
        }
        const last_offset = self.hmtx.offset + (@as(usize, self.number_of_h_metrics) - 1) * 4;
        const lsb_offset = self.hmtx.offset + @as(usize, self.number_of_h_metrics) * 4 + (@as(usize, glyph_id) - self.number_of_h_metrics) * 2;
        return .{
            .advance_width = try bin.readU16At(self.data, last_offset),
            .left_side_bearing = try bin.readI16At(self.data, lsb_offset),
        };
    }

    /// Map a Unicode variation sequence to a glyph id. If the font does not
    /// advertise a cmap format 14 record for the sequence, callers receive the
    /// base character mapping so unsupported variation selectors degrade like
    /// normal text renderers instead of producing a missing glyph.
    pub fn glyphIndexWithVariation(self: *const Font, codepoint: u21, variation_selector: u21) FontError!glyph_mod.GlyphId {
        return (try self.variationGlyphIndex(codepoint, variation_selector)) orelse try self.glyphIndex(codepoint);
    }

    /// Return the cmap format 14 result for a Unicode variation sequence. A
    /// non-default UVS mapping returns the explicit glyph id; a default UVS
    /// range returns the base cmap glyph id; null means the font has no record
    /// for that variation sequence.
    pub fn variationGlyphIndex(self: *const Font, codepoint: u21, variation_selector: u21) FontError!?glyph_mod.GlyphId {
        for (self.cmap_subtables) |subtable| {
            if (subtable.format != 14) continue;
            if (try glyphIndexFormat14(self, subtable.offset, codepoint, variation_selector)) |glyph_id| return glyph_id;
        }
        return null;
    }

    pub fn kerning(self: *const Font, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        const kern = self.kern orelse return 0;
        if (kern.length < 4) return 0;
        const version = try bin.readU32At(self.data, kern.offset);
        if (version == 0x00010000) {
            return try appleKernKerning(self.data, kern, left, right);
        }
        if ((version >> 16) != 0) return 0;
        return try legacyKernKerning(self.data, kern, left, right);
    }

    fn legacyKernKerning(data: []const u8, kern: TableRecord, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        const table_count = try bin.readU16At(data, kern.offset + 2);
        const table_end = kern.offset + kern.length;
        var subtable_offset = kern.offset + 4;
        var total: i32 = 0;
        var saw_matching_pair = false;
        for (0..table_count) |_| {
            if (subtable_offset > table_end or table_end - subtable_offset < 6) return error.BadSfnt;
            const length = try bin.readU16At(data, subtable_offset + 2);
            const coverage = try bin.readU16At(data, subtable_offset + 4);
            if (length < 6 or length > table_end - subtable_offset) return error.BadSfnt;
            const format = coverage >> 8;
            const horizontal = (coverage & 0x0001) != 0;
            const minimum = (coverage & 0x0002) != 0;
            const cross_stream = (coverage & 0x0004) != 0;
            const override = (coverage & 0x0008) != 0;
            if (format == 0 and horizontal and !minimum and !cross_stream) {
                // OpenType/Windows subtables have a six-byte common header
                // before the format-0 binary-search payload.
                if (try kernFormat0Body(data[subtable_offset + 6 .. subtable_offset + length], left, right)) |value| {
                    saw_matching_pair = true;
                    if (override) {
                        total = value;
                    } else {
                        total += value;
                    }
                }
            }
            subtable_offset += length;
        }
        if (!saw_matching_pair) return 0;
        return @intCast(std.math.clamp(total, std.math.minInt(i16), std.math.maxInt(i16)));
    }

    fn appleKernKerning(data: []const u8, kern: TableRecord, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        if (kern.length < 8) return error.BadSfnt;
        const table_count = try bin.readU32At(data, kern.offset + 4);
        const table_end = kern.offset + kern.length;
        var subtable_offset = kern.offset + 8;
        var total: i32 = 0;
        var saw_matching_pair = false;
        for (0..table_count) |_| {
            if (subtable_offset > table_end or table_end - subtable_offset < 8) return error.BadSfnt;
            const length = try bin.readU32At(data, subtable_offset);
            const coverage = try bin.readU16At(data, subtable_offset + 4);
            if (length < 8 or length > table_end - subtable_offset) return error.BadSfnt;

            // Apple/AAT version-1 subtables use different coverage bits from
            // the legacy OpenType header: format lives in the low byte, while a
            // clear vertical bit means normal horizontal kerning. Variation and
            // cross-stream tables need extra state this API does not provide, so
            // they are skipped rather than applying incorrect horizontal deltas.
            const format = coverage & 0x00ff;
            const vertical = (coverage & 0x8000) != 0;
            const cross_stream = (coverage & 0x4000) != 0;
            const variation = (coverage & 0x2000) != 0;
            if (format == 0 and !vertical and !cross_stream and !variation) {
                // AAT subtables have an eight-byte common header (including
                // tupleIndex) before the same format-0 pair-search payload.
                if (try kernFormat0Body(data[subtable_offset + 8 .. subtable_offset + length], left, right)) |value| {
                    saw_matching_pair = true;
                    total += value;
                }
            }
            subtable_offset += length;
        }
        if (!saw_matching_pair) return 0;
        return @intCast(std.math.clamp(total, std.math.minInt(i16), std.math.maxInt(i16)));
    }

    pub fn applyGsub(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator) FontError!void {
        return try self.applyGsubWithOptions(glyphs, allocator, .{});
    }

    /// Apply GSUB to a mutable glyph-id stream. GDEF glyph classes are expanded
    /// into a dense temporary array so lookup flags can skip bases, ligatures,
    /// or marks consistently across all lookup formats.
    pub fn applyGsubWithOptions(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        var glyph_classes: ?[]u16 = null;
        var mark_attach_classes: ?[]u16 = null;
        var mark_filtering_sets: ?[][]glyph_mod.GlyphId = null;
        if (self.gdef != null) {
            const classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(classes);
            const attach_classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(attach_classes);
            for (classes, 0..) |*class, glyph_id| {
                class.* = @intFromEnum(try self.glyphClass(@intCast(glyph_id)));
            }
            for (attach_classes, 0..) |*class, glyph_id| {
                class.* = try self.markAttachClass(@intCast(glyph_id));
            }
            glyph_classes = classes;
            mark_attach_classes = attach_classes;
            gsub_options.glyph_classes = classes;
            gsub_options.mark_attach_classes = attach_classes;
            if (try self.markFilteringSets(allocator)) |sets| {
                mark_filtering_sets = sets;
                gsub_options.mark_filtering_sets = sets;
            }
        }
        defer if (glyph_classes) |classes| allocator.free(classes);
        defer if (mark_attach_classes) |classes| allocator.free(classes);
        defer if (mark_filtering_sets) |sets| freeMarkFilteringSets(allocator, sets);
        try gsub_mod.applyWithOptions(self.data, gsub.offset, gsub.length, glyphs, allocator, gsub_options);
    }

    pub fn collectGposAdjustments(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator) FontError!void {
        return try self.collectGposAdjustmentsWithOptions(glyphs, adjustments, allocator, .{});
    }

    /// Collect GPOS placement/advance deltas for a shaped glyph stream. The
    /// returned adjustments use glyph indices in the post-GSUB stream, which is
    /// the same coordinate space used by `layout.shapeSegmentInto`.
    pub fn collectGposAdjustmentsWithOptions(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator, options: gpos_mod.LookupOptions) FontError!void {
        const gpos = self.gpos orelse return;
        var gpos_options = options;
        var glyph_classes: ?[]u16 = null;
        var mark_attach_classes: ?[]u16 = null;
        var mark_filtering_sets: ?[][]glyph_mod.GlyphId = null;
        if (self.gdef != null) {
            const classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(classes);
            const attach_classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(attach_classes);
            for (classes, 0..) |*class, glyph_id| {
                class.* = @intFromEnum(try self.glyphClass(@intCast(glyph_id)));
            }
            for (attach_classes, 0..) |*class, glyph_id| {
                class.* = try self.markAttachClass(@intCast(glyph_id));
            }
            glyph_classes = classes;
            mark_attach_classes = attach_classes;
            gpos_options.glyph_classes = classes;
            gpos_options.mark_attach_classes = attach_classes;
            if (try self.markFilteringSets(allocator)) |sets| {
                mark_filtering_sets = sets;
                gpos_options.mark_filtering_sets = sets;
            }
        }
        defer if (glyph_classes) |classes| allocator.free(classes);
        defer if (mark_attach_classes) |classes| allocator.free(classes);
        defer if (mark_filtering_sets) |sets| freeMarkFilteringSets(allocator, sets);
        try gpos_mod.collectAdjustmentsWithOptions(self.data, gpos.offset, gpos.length, glyphs, adjustments, allocator, gpos_options);
    }

    pub fn nameString(self: *const Font, name_id: NameId, out: []u8) FontError!?[]const u8 {
        const name = self.name orelse return null;
        return try readNameString(self.data, name, @intFromEnum(name_id), out);
    }

    pub fn familyName(self: *const Font, out: []u8) FontError!?[]const u8 {
        if (try self.nameString(.typographic_family, out)) |value| return value;
        return try self.nameString(.family, out);
    }

    pub fn subfamilyName(self: *const Font, out: []u8) FontError!?[]const u8 {
        if (try self.nameString(.typographic_subfamily, out)) |value| return value;
        return try self.nameString(.subfamily, out);
    }

    pub fn fullName(self: *const Font, out: []u8) FontError!?[]const u8 {
        return try self.nameString(.full_name, out);
    }

    pub fn hasStyleAttributes(self: *const Font) bool {
        return self.os2 != null;
    }

    /// Read the GDEF class definition for lookup-flag filtering.
    pub fn glyphClass(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!GlyphClass {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gdef = self.gdef orelse return .unclassified;
        if (gdef.length < 6) return error.BadSfnt;
        const major = try bin.readU16At(self.data, gdef.offset);
        if (major != 1) return error.BadSfnt;
        const glyph_class_def_offset = try bin.readU16At(self.data, gdef.offset + 4);
        if (glyph_class_def_offset == 0) return .unclassified;
        if (glyph_class_def_offset >= gdef.length) return error.BadSfnt;
        const class = try classDefValue(self.data[gdef.offset .. gdef.offset + gdef.length], glyph_class_def_offset, glyph_id);
        return @enumFromInt(class);
    }

    pub fn markAttachClass(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!u16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gdef = self.gdef orelse return 0;
        if (gdef.length < 12) return 0;
        const major = try bin.readU16At(self.data, gdef.offset);
        if (major != 1) return error.BadSfnt;
        const mark_attach_class_def_offset = try bin.readU16At(self.data, gdef.offset + 10);
        if (mark_attach_class_def_offset == 0) return 0;
        if (mark_attach_class_def_offset >= gdef.length) return error.BadSfnt;
        return try classDefValue(self.data[gdef.offset .. gdef.offset + gdef.length], mark_attach_class_def_offset, glyph_id);
    }

    fn markFilteringSets(self: *const Font, allocator: std.mem.Allocator) FontError!?[][]glyph_mod.GlyphId {
        const gdef = self.gdef orelse return null;
        if (gdef.length < 4) return error.BadSfnt;
        const major = try bin.readU16At(self.data, gdef.offset);
        const minor = try bin.readU16At(self.data, gdef.offset + 2);
        if (major != 1) return error.BadSfnt;
        // MarkGlyphSetsDef was added in GDEF 1.2.  Version 1.0/1.1 tables may
        // still be longer than the base header because their earlier offsets
        // point to subtables placed immediately after it; reading byte 12 as a
        // mark-set offset in those fonts misinterprets subtable data and can
        // make otherwise valid fonts fail shaping.
        if (minor < 2) return null;
        if (gdef.length < 14) return null;
        const mark_glyph_sets_def_offset = try bin.readU16At(self.data, gdef.offset + 12);
        if (mark_glyph_sets_def_offset == 0) return null;
        if (mark_glyph_sets_def_offset >= gdef.length) return error.BadSfnt;
        return try readMarkGlyphSetsDef(allocator, self.data[gdef.offset .. gdef.offset + gdef.length], mark_glyph_sets_def_offset);
    }

    pub fn styleAttributes(self: *const Font) FontError!StyleAttributes {
        const os2 = self.os2 orelse return .{};
        if (os2.length < 2) return error.BadSfnt;
        const version = try bin.readU16At(self.data, os2.offset);
        const minimum_length = try minimumOs2TableLength(version);
        if (os2.length < minimum_length) return error.BadSfnt;
        const weight = try bin.readU16At(self.data, os2.offset + 4);
        const width = try bin.readU16At(self.data, os2.offset + 6);
        const fs_selection = try bin.readU16At(self.data, os2.offset + 62);
        return .{
            .weight = weight,
            .width = width,
            .italic = (fs_selection & 0x0001) != 0,
            .bold = (fs_selection & 0x0020) != 0,
        };
    }

    pub fn variationAxes(self: *const Font, allocator: std.mem.Allocator) FontError![]VariationAxis {
        const fvar = self.fvar orelse return try allocator.alloc(VariationAxis, 0);
        const info = try readFvarInfo(self.data, fvar);

        const axes = try allocator.alloc(VariationAxis, info.axis_count);
        errdefer allocator.free(axes);
        for (axes, 0..) |*axis, index| {
            const axis_offset = fvar.offset + info.axes_array_offset + index * info.axis_size;
            axis.* = .{
                .tag = try bin.readTagAt(self.data, axis_offset),
                .min_value = fixed16_16ToF32(try bin.readI32At(self.data, axis_offset + 4)),
                .default_value = fixed16_16ToF32(try bin.readI32At(self.data, axis_offset + 8)),
                .max_value = fixed16_16ToF32(try bin.readI32At(self.data, axis_offset + 12)),
                .flags = try bin.readU16At(self.data, axis_offset + 16),
                .name_id = try bin.readU16At(self.data, axis_offset + 18),
            };
            if (axis.min_value > axis.default_value or axis.default_value > axis.max_value) return error.BadSfnt;
            for (axes[0..index]) |previous| {
                if (std.mem.eql(u8, &previous.tag, &axis.tag)) return error.BadSfnt;
            }
        }
        return axes;
    }

    pub fn mapVariationCoordinate(self: *const Font, axis_index: usize, normalized: f32) FontError!f32 {
        const avar = self.avar orelse return normalized;
        if (avar.offset > self.data.len or avar.length > self.data.len - avar.offset) return error.BadSfnt;
        const table = self.data[avar.offset .. avar.offset + avar.length];
        if (avar.length < 8) return error.BadSfnt;
        const major = try bin.readU16At(table, 0);
        const minor = try bin.readU16At(table, 2);
        if (major != 1 or minor != 0) return error.BadSfnt;
        const axis_count = try bin.readU16At(table, 6);
        if (self.fvar) |fvar| {
            const fvar_info = try readFvarInfo(self.data, fvar);
            if (axis_count != fvar_info.axis_count) return error.BadSfnt;
        }

        var offset: usize = 8;
        var mapped = normalized;
        for (0..axis_count) |index| {
            if (offset + 2 > table.len) return error.BadSfnt;
            const pair_count = try bin.readU16At(table, offset);
            offset += 2;
            const pair_bytes = @as(usize, pair_count) * 4;
            if (pair_bytes > table.len - offset) return error.BadSfnt;
            if (index == axis_index) {
                mapped = try mapAvarSegment(table[offset .. offset + pair_bytes], normalized);
            }
            offset += pair_bytes;
        }
        // Do not return as soon as the requested axis is mapped. The avar table
        // declares a complete SegmentMaps array, and accepting coordinates from
        // an early axis while a later declared map extends past the table would
        // let malformed fonts hide truncated variation data behind axis order.
        return mapped;
    }

    pub fn normalizedVariationCoordinates(self: *const Font, allocator: std.mem.Allocator, coordinates: []const VariationCoordinate) FontError![]f32 {
        const axes = try self.variationAxes(allocator);
        defer allocator.free(axes);

        const normalized = try allocator.alloc(f32, axes.len);
        errdefer allocator.free(normalized);
        for (axes, 0..) |axis, index| {
            const user_value = variationValueForAxis(axis, coordinates) orelse axis.default_value;
            normalized[index] = try self.mapVariationCoordinate(index, axis.normalize(user_value));
        }
        return normalized;
    }

    pub fn colorLayers(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError![]ColorLayer {
        const colr = self.colr orelse return try allocator.alloc(ColorLayer, 0);
        if (colr.length < 14) return error.BadSfnt;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 0) return try allocator.alloc(ColorLayer, 0);
        const base_count = try bin.readU16At(self.data, colr.offset + 2);
        const base_offset = try bin.readU32At(self.data, colr.offset + 4);
        const layer_offset = try bin.readU32At(self.data, colr.offset + 8);
        const layer_count = try bin.readU16At(self.data, colr.offset + 12);
        if (base_offset > colr.length or layer_offset > colr.length) return error.BadSfnt;
        if (@as(usize, base_count) * 6 > colr.length - base_offset) return error.BadSfnt;
        if (@as(usize, layer_count) * 4 > colr.length - layer_offset) return error.BadSfnt;

        for (0..base_count) |index| {
            const record = colr.offset + base_offset + index * 6;
            const base_glyph = try bin.readU16At(self.data, record);
            if (base_glyph != glyph_id) continue;
            const first_layer = try bin.readU16At(self.data, record + 2);
            const num_layers = try bin.readU16At(self.data, record + 4);
            if (first_layer > layer_count or num_layers > layer_count - first_layer) return error.BadSfnt;
            const layers = try allocator.alloc(ColorLayer, num_layers);
            errdefer allocator.free(layers);
            for (layers, 0..) |*layer, layer_index| {
                const layer_record = colr.offset + layer_offset + (@as(usize, first_layer) + layer_index) * 4;
                layer.* = .{
                    .glyph_id = try bin.readU16At(self.data, layer_record),
                    .palette_index = try bin.readU16At(self.data, layer_record + 2),
                };
                try self.validateColorPaletteIndex(layer.palette_index);
            }
            return layers;
        }
        return try allocator.alloc(ColorLayer, 0);
    }

    pub fn paletteColor(self: *const Font, palette_index: u16, color_index: u16) FontError!?PaletteColor {
        const cpal = self.cpal orelse return null;
        if (cpal.length < 12) return error.BadSfnt;
        const palette_entries = try validateCpalPaletteEntries(self.data, cpal);
        const palette_count = try bin.readU16At(self.data, cpal.offset + 4);
        const color_records_offset: usize = @intCast(try bin.readU32At(self.data, cpal.offset + 8));

        if (palette_index >= palette_count or color_index >= palette_entries) return null;
        const palette_start_offset = cpal.offset + 12 + @as(usize, palette_index) * 2;
        const first_color_index = try bin.readU16At(self.data, palette_start_offset);
        const record_index = @as(usize, first_color_index) + color_index;
        const record = cpal.offset + color_records_offset + record_index * 4;
        return .{
            .blue = self.data[record],
            .green = self.data[record + 1],
            .red = self.data[record + 2],
            .alpha = self.data[record + 3],
        };
    }

    pub fn colorPaint(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?ColorPaint {
        const colr = self.colr orelse return null;
        if (colr.length < 34) return null;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 1) return null;
        const base_glyph_list_offset: usize = @intCast(try bin.readU32At(self.data, colr.offset + 14));
        if (base_glyph_list_offset == 0) return null;
        try validateColrV1OptionalOffset(base_glyph_list_offset, colr, 4);
        const list_start = colr.offset + base_glyph_list_offset;
        const record_count = try bin.readU32At(self.data, list_start);
        const records_start = list_start + 4;
        if (@as(usize, record_count) * 6 > colr.offset + colr.length - records_start) return error.BadSfnt;
        const paint_data_start = 4 + @as(usize, record_count) * 6;
        for (0..record_count) |index| {
            const record = records_start + index * 6;
            const base_glyph = try bin.readU16At(self.data, record);
            if (base_glyph != glyph_id) continue;
            const paint_offset: usize = @intCast(try bin.readU32At(self.data, record + 2));
            // BaseGlyphPaintRecord offsets are child-table offsets, not raw
            // cursors into the BaseGlyphList header. Reject overlaps with the
            // declared record array so malformed fonts cannot reinterpret
            // glyph ids or offset bytes as PaintSolid/PaintGlyph payloads.
            if (paint_offset < paint_data_start) return error.BadSfnt;
            if (paint_offset > colr.length - base_glyph_list_offset) return error.BadSfnt;
            const paint_start = list_start + paint_offset;
            var graph_guard = ColorPaintGraphGuard{};
            try validateColorPaintGraph(self, paint_start, &graph_guard);
            return try readColorPaint(self, paint_start);
        }
        return null;
    }

    fn validateColorPaletteIndex(self: *const Font, color_index: u16) FontError!void {
        // COLR palette indices are only meaningful when a CPAL table declares a
        // color slot for them.  Validate at parse/read boundaries so rendering
        // code does not silently drop malformed color layers or paints as if
        // they merely selected an absent runtime palette.
        if (self.cpal == null) return error.BadSfnt;
        _ = (try self.paletteColor(0, color_index)) orelse return error.BadSfnt;
    }

    pub fn colorPaintLayer(self: *const Font, layer_index: u32) FontError!?ColorPaint {
        const colr = self.colr orelse return null;
        if (colr.length < 34) return null;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 1) return null;
        const layer_list = (try colrLayerList(self.data, colr)) orelse return null;
        if (layer_index >= layer_list.layer_count) return null;
        const paint_start = try colrLayerPaintOffset(self.data, colr, layer_list, layer_index);
        var graph_guard = ColorPaintGraphGuard{};
        try validateColorPaintLayer(self, layer_list, layer_index, &graph_guard);
        return try readColorPaint(self, paint_start);
    }

    pub fn svgGlyphDocument(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?SvgGlyphDocument {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const svg = self.svg orelse return null;
        const document_list = try svgDocumentList(self.data, svg);

        var previous_end_glyph_id: ?glyph_mod.GlyphId = null;
        var match: ?SvgGlyphDocument = null;
        for (0..document_list.entry_count) |index| {
            const record = try readSvgDocumentRecord(self.data, document_list.records_start + index * 12);
            try validateSvgDocumentRecord(record, document_list, self.glyph_count, &previous_end_glyph_id);
            if (glyph_id >= record.start_glyph_id and glyph_id <= record.end_glyph_id) {
                const document_start = document_list.start + record.document_offset;
                match = .{
                    .start_glyph_id = record.start_glyph_id,
                    .end_glyph_id = record.end_glyph_id,
                    .data = self.data[document_start .. document_start + record.document_length],
                };
            }
        }
        return match;
    }

    pub fn svgDocument(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
        const document = try self.svgGlyphDocument(glyph_id);
        return if (document) |value| value.data else null;
    }

    pub fn bestBitmapStrikePpem(self: *const Font, size_px: f32) FontError!?u16 {
        var best_ppem: ?u16 = null;
        var best_distance: f32 = std.math.inf(f32);

        if (self.sbix) |sbix| {
            const strike_count = try sbixStrikeCount(self.data, sbix);
            for (0..strike_count) |strike_index| {
                const strike = try sbixStrike(self.data, sbix, self.glyph_count, strike_index);
                recordBestBitmapPpem(strike.ppem, size_px, &best_ppem, &best_distance);
            }
        }

        if (self.cblc != null and self.cbdt != null) {
            const cblc = self.cblc.?;
            const strike_count = try cblcStrikeCount(self.data, cblc);
            for (0..strike_count) |strike_index| {
                const strike = try cblcStrike(self.data, cblc, self.glyph_count, strike_index);
                recordBestBitmapPpem(strike.ppem, size_px, &best_ppem, &best_distance);
            }
        }

        return best_ppem;
    }

    pub fn bitmapGlyphPng(self: *const Font, glyph_id: glyph_mod.GlyphId, size_px: f32) FontError!?BitmapGlyphPng {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;

        if (self.sbix) |sbix| {
            const strike_count = try sbixStrikeCount(self.data, sbix);
            var best: ?BitmapGlyphPng = null;
            var best_distance: f32 = std.math.inf(f32);
            for (0..strike_count) |strike_index| {
                const strike = try sbixStrike(self.data, sbix, self.glyph_count, strike_index);
                const maybe_glyph = try sbixGlyphPng(self.data, strike, glyph_id);
                if (maybe_glyph) |glyph| {
                    const distance = @abs(@as(f32, @floatFromInt(glyph.ppem)) - size_px);
                    if (best == null or distance < best_distance) {
                        best = glyph;
                        best_distance = distance;
                    }
                }
            }
            if (best) |glyph| return glyph;
        }

        if (self.cblc != null and self.cbdt != null) {
            return try cblcGlyphPng(self.data, self.cblc.?, self.cbdt.?, self.glyph_count, glyph_id, size_px);
        }
        return null;
    }

    pub fn glyphOutline(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError!glyph_mod.GlyphOutline {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const metrics = try self.horizontalMetrics(glyph_id);
        const bounds = if (self.format == .truetype)
            try self.glyphBounds(glyph_id)
        else
            glyph_mod.Bounds{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        var outline = glyph_mod.GlyphOutline.init(allocator, glyph_id, bounds, metrics.advance_width, metrics.left_side_bearing);
        errdefer outline.deinit();
        if (self.format == .truetype) {
            try self.appendGlyphOutline(&outline, glyph_id, .{ .xx = 1, .yx = 0, .xy = 0, .yy = 1, .dx = 0, .dy = 0 }, 0);
        } else {
            const cff = self.cff orelse return error.MissingTable;
            const info = try cff_mod.parseInfo(self.data[cff.offset .. cff.offset + cff.length]);
            try cff_mod.appendGlyphOutline(allocator, self.data[cff.offset .. cff.offset + cff.length], info, &outline, glyph_id);
        }
        return outline;
    }

    fn glyphBounds(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!glyph_mod.Bounds {
        const slice = try self.glyphData(glyph_id);
        if (slice.len == 0) return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        return .{
            .x_min = try bin.readI16At(slice, 2),
            .y_min = try bin.readI16At(slice, 4),
            .x_max = try bin.readI16At(slice, 6),
            .y_max = try bin.readI16At(slice, 8),
        };
    }

    fn glyphData(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError![]const u8 {
        const glyf = self.glyf orelse return error.MissingTable;
        const start = try self.locaOffset(glyph_id);
        const end = try self.locaOffset(glyph_id + 1);
        if (end < start or end > glyf.length) return error.InvalidLoca;
        return self.data[glyf.offset + start .. glyf.offset + end];
    }

    fn locaOffset(self: *const Font, glyph_id: u32) FontError!usize {
        if (glyph_id > self.glyph_count) return error.InvalidGlyph;
        const loca = self.loca orelse return error.MissingTable;
        const required_length = try locaEntryRequiredLength(glyph_id, self.index_to_loc_format);
        if (loca.length < required_length) return error.InvalidLoca;
        return switch (self.index_to_loc_format) {
            0 => @as(usize, try bin.readU16At(self.data, loca.offset + @as(usize, glyph_id) * 2)) * 2,
            1 => try bin.readU32At(self.data, loca.offset + @as(usize, glyph_id) * 4),
            else => error.InvalidLoca,
        };
    }

    fn appendGlyphOutline(self: *const Font, outline: *glyph_mod.GlyphOutline, glyph_id: glyph_mod.GlyphId, transform: Transform, depth: u8) FontError!void {
        if (depth > 8) return error.CompoundDepthExceeded;
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return;
        const contour_count = try bin.readI16At(data, 0);
        if (contour_count >= 0) {
            // Simple glyf outlines store contour end points plus compressed
            // point deltas. Compound outlines recurse into component glyphs.
            try appendSimpleGlyph(outline, data, @intCast(contour_count), transform);
        } else {
            try self.appendCompoundGlyph(outline, data, transform, depth + 1);
        }
    }

    fn appendCompoundGlyph(self: *const Font, outline: *glyph_mod.GlyphOutline, data: []const u8, parent_transform: Transform, depth: u8) FontError!void {
        var r = bin.Reader.init(data);
        _ = try r.readI16();
        try r.skip(8);
        while (true) {
            const flags = try r.readU16();
            const component_glyph = try r.readU16();
            var arg1: i16 = 0;
            var arg2: i16 = 0;
            if ((flags & 0x0001) != 0) {
                arg1 = try r.readI16();
                arg2 = try r.readI16();
            } else {
                arg1 = try r.readI8();
                arg2 = try r.readI8();
            }
            // This parser supports component placement expressed as direct XY
            // offsets. Point-to-point component matching requires hinting-time
            // semantics and is rejected until that behavior is implemented.
            if ((flags & 0x0002) == 0) return error.UnsupportedGlyph;

            var child = Transform.identity();
            child.dx = @floatFromInt(arg1);
            child.dy = @floatFromInt(arg2);
            if ((flags & 0x0008) != 0) {
                const scale = f2dot14(try r.readI16());
                child.xx = scale;
                child.yy = scale;
            } else if ((flags & 0x0040) != 0) {
                child.xx = f2dot14(try r.readI16());
                child.yy = f2dot14(try r.readI16());
            } else if ((flags & 0x0080) != 0) {
                child.xx = f2dot14(try r.readI16());
                child.yx = f2dot14(try r.readI16());
                child.xy = f2dot14(try r.readI16());
                child.yy = f2dot14(try r.readI16());
            }
            try self.appendGlyphOutline(outline, component_glyph, parent_transform.mul(child), depth);
            if ((flags & 0x0020) == 0) break;
        }
    }
};

const Transform = struct {
    xx: f32,
    yx: f32,
    xy: f32,
    yy: f32,
    dx: f32,
    dy: f32,

    fn identity() Transform {
        return .{ .xx = 1, .yx = 0, .xy = 0, .yy = 1, .dx = 0, .dy = 0 };
    }

    fn apply(self: Transform, point: glyph_mod.Point) glyph_mod.Point {
        return .{
            .x = point.x * self.xx + point.y * self.xy + self.dx,
            .y = point.x * self.yx + point.y * self.yy + self.dy,
        };
    }

    fn mul(a: Transform, b: Transform) Transform {
        return .{
            .xx = a.xx * b.xx + a.xy * b.yx,
            .yx = a.yx * b.xx + a.yy * b.yx,
            .xy = a.xx * b.xy + a.xy * b.yy,
            .yy = a.yx * b.xy + a.yy * b.yy,
            .dx = a.xx * b.dx + a.xy * b.dy + a.dx,
            .dy = a.yx * b.dx + a.yy * b.dy + a.dy,
        };
    }
};

const SbixStrike = struct {
    ppem: u16,
    ppi: u16,
    offset: usize,
    length: usize,
    bitmap_data_offset: usize,
};

const CblcStrike = struct {
    ppem: u16,
    ppi: u16,
    offset: usize,
    index_tables_size: usize,
    table_count: usize,
    start_glyph: glyph_mod.GlyphId,
    end_glyph: glyph_mod.GlyphId,
};

const CblcGlyphLocation = struct {
    image_format: u16,
    offset: usize,
    length: usize,
};

fn cblcImageLocation(image_format: u16, image_base: usize, start: usize, end: usize) FontError!?CblcGlyphLocation {
    if (end < start) return error.BadSfnt;
    if (end == start) return null;
    if (start > std.math.maxInt(usize) - image_base) return error.BadSfnt;
    const offset = image_base + start;
    const length = end - start;
    // Validate the addition that cbdtGlyphPng will later use for the declared
    // image slice. Very large CBLC imageDataOffset values are legal u32s but
    // cannot describe an in-memory CBDT range if adding the glyph payload span
    // wraps usize.
    if (length > std.math.maxInt(usize) - offset) return error.BadSfnt;
    return .{ .image_format = image_format, .offset = offset, .length = length };
}

const BitmapMetrics = struct {
    height: u8,
    width: u8,
    bearing_x: i8,
    bearing_y: i8,
    advance: u8,
};

fn recordBestBitmapPpem(ppem: u16, size_px: f32, best_ppem: *?u16, best_distance: *f32) void {
    const distance = @abs(@as(f32, @floatFromInt(ppem)) - size_px);
    if (best_ppem.* == null or distance < best_distance.*) {
        best_ppem.* = ppem;
        best_distance.* = distance;
    }
}

fn sbixStrikeCount(data: []const u8, sbix: TableRecord) FontError!usize {
    if (sbix.length < 8) return error.BadSfnt;
    const version = try bin.readU16At(data, sbix.offset);
    if (version != 1) return error.BadSfnt;
    const count = try bin.readU32At(data, sbix.offset + 4);
    if (@as(usize, count) * 4 > sbix.length - 8) return error.BadSfnt;
    return @intCast(count);
}

fn sbixStrike(data: []const u8, sbix: TableRecord, glyph_count: u16, strike_index: usize) FontError!SbixStrike {
    const strike_count = try sbixStrikeCount(data, sbix);
    if (strike_index >= strike_count) return error.BadSfnt;
    const offset = try bin.readU32At(data, sbix.offset + 8 + strike_index * 4);
    // Strike offsets are relative to the sbix table, but their targets are
    // strike payloads.  A target inside the sbix header/strike-offset array
    // would reinterpret table metadata as ppem/ppi and glyph offsets.
    const minimum_strike_offset = 8 + strike_count * 4;
    if (offset < minimum_strike_offset or offset >= sbix.length) return error.BadSfnt;
    const next_offset = if (strike_index + 1 < strike_count)
        try bin.readU32At(data, sbix.offset + 8 + (strike_index + 1) * 4)
    else
        @as(u32, @intCast(sbix.length));
    if (next_offset < offset or next_offset > sbix.length) return error.BadSfnt;

    const absolute = sbix.offset + offset;
    const length = @as(usize, next_offset - offset);
    const offsets_len = (@as(usize, glyph_count) + 1) * 4;
    if (length < 4 + offsets_len) return error.BadSfnt;
    return .{
        .ppem = try bin.readU16At(data, absolute),
        .ppi = try bin.readU16At(data, absolute + 2),
        .offset = absolute,
        .length = length,
        .bitmap_data_offset = 4 + offsets_len,
    };
}

fn sbixGlyphPng(data: []const u8, strike: SbixStrike, glyph_id: glyph_mod.GlyphId) FontError!?BitmapGlyphPng {
    const glyph_offset_pos = strike.offset + 4 + @as(usize, glyph_id) * 4;
    const start = try bin.readU32At(data, glyph_offset_pos);
    const end = try bin.readU32At(data, glyph_offset_pos + 4);
    // Glyph data offsets must start after the strike header and the complete
    // glyph-offset array.  Offsets into that metadata are malformed even when
    // equal, because "missing glyph" markers should still point at a legal
    // data boundary rather than hiding a corrupt offset array.
    if (start < strike.bitmap_data_offset or end < strike.bitmap_data_offset) return error.BadSfnt;
    if (end < start or end > strike.length) return error.BadSfnt;
    if (end == start) return null;
    if (end - start < 8) return error.BadSfnt;

    const glyph_start = strike.offset + start;
    const glyph_end = strike.offset + end;
    const graphic_type = try bin.readTagAt(data, glyph_start + 4);
    if (!bin.tagEq(graphic_type, "png ")) return null;
    const png = data[glyph_start + 8 .. glyph_end];
    if (png.len < 24) return error.BadSfnt;
    if (!std.mem.eql(u8, png[1..4], "PNG")) return error.BadSfnt;
    return .{
        .ppem = strike.ppem,
        .ppi = strike.ppi,
        .origin_offset_x = try bin.readI16At(data, glyph_start),
        .origin_offset_y = try bin.readI16At(data, glyph_start + 2),
        .width = try bin.readU32At(png, 16),
        .height = try bin.readU32At(png, 20),
        .data = png,
    };
}

fn validateSbixTable(data: []const u8, sbix: TableRecord, glyph_count: u16) FontError!void {
    const strike_count = try sbixStrikeCount(data, sbix);
    for (0..strike_count) |strike_index| {
        const strike = try sbixStrike(data, sbix, glyph_count, strike_index);
        try validateSbixStrikeGlyphOffsets(data, strike, glyph_count);
    }
}

fn validateSbixStrikeGlyphOffsets(data: []const u8, strike: SbixStrike, glyph_count: u16) FontError!void {
    var previous = try bin.readU32At(data, strike.offset + 4);
    if (previous < strike.bitmap_data_offset or previous > strike.length) return error.BadSfnt;

    for (0..glyph_count) |glyph_index| {
        const offset_pos = strike.offset + 4 + (glyph_index + 1) * 4;
        const current = try bin.readU32At(data, offset_pos);
        // The glyph offset array is a monotonic list of boundaries relative to
        // the strike start. Validate the entire array at parse time so bitmap
        // selection APIs cannot accept a font whose unused glyph records point
        // back into strike metadata or beyond the declared sbix table.
        if (current < previous) return error.BadSfnt;
        if (current < strike.bitmap_data_offset or current > strike.length) return error.BadSfnt;
        if (current != previous and current - previous < 8) return error.BadSfnt;
        previous = current;
    }
}

fn cblcStrikeCount(data: []const u8, cblc: TableRecord) FontError!usize {
    if (cblc.length < 8) return error.BadSfnt;
    const major = try bin.readU16At(data, cblc.offset);
    const minor = try bin.readU16At(data, cblc.offset + 2);
    if ((major != 2 and major != 3) or minor != 0) return error.BadSfnt;
    const count = try bin.readU32At(data, cblc.offset + 4);
    if (@as(usize, count) * 48 > cblc.length - 8) return error.BadSfnt;
    return @intCast(count);
}

fn cblcStrike(data: []const u8, cblc: TableRecord, glyph_count: u16, strike_index: usize) FontError!CblcStrike {
    const strike_count = try cblcStrikeCount(data, cblc);
    if (strike_index >= strike_count) return error.BadSfnt;
    const offset = cblc.offset + 8 + strike_index * 48;
    const index_array_offset = try bin.readU32At(data, offset);
    const index_tables_size = try bin.readU32At(data, offset + 4);
    const table_count = try bin.readU32At(data, offset + 8);
    const minimum_index_array_offset = 8 + strike_count * 48;
    // IndexSubTableArray is payload for a strike, not part of the CBLC header
    // or bitmapSizeTable directory.  Requiring it to start after the full
    // strike directory prevents malformed fonts from reinterpreting strike
    // metadata as glyph-range records.
    if (index_array_offset < minimum_index_array_offset) return error.BadSfnt;
    if (index_array_offset > cblc.length) return error.BadSfnt;
    if (index_tables_size > cblc.length - index_array_offset) return error.BadSfnt;
    if (@as(usize, table_count) * 8 > index_tables_size) return error.BadSfnt;
    const start_glyph = try bin.readU16At(data, offset + 40);
    const end_glyph = try bin.readU16At(data, offset + 42);
    if (start_glyph > end_glyph) return error.BadSfnt;
    if (end_glyph >= glyph_count) return error.BadSfnt;
    return .{
        .ppem = data[offset + 44],
        .ppi = 0,
        .offset = cblc.offset + index_array_offset,
        .index_tables_size = index_tables_size,
        .table_count = table_count,
        .start_glyph = start_glyph,
        .end_glyph = end_glyph,
    };
}

fn cblcGlyphPng(data: []const u8, cblc: TableRecord, cbdt: TableRecord, glyph_count: u16, glyph_id: glyph_mod.GlyphId, size_px: f32) FontError!?BitmapGlyphPng {
    const strike_count = try cblcStrikeCount(data, cblc);
    var best: ?BitmapGlyphPng = null;
    var best_distance: f32 = std.math.inf(f32);
    for (0..strike_count) |strike_index| {
        const strike = try cblcStrike(data, cblc, glyph_count, strike_index);
        if (glyph_id < strike.start_glyph or glyph_id > strike.end_glyph) continue;
        const location = (try cblcGlyphLocation(data, strike, glyph_id)) orelse continue;
        const glyph = (try cbdtGlyphPng(data, cbdt, strike, location)) orelse continue;
        const distance = @abs(@as(f32, @floatFromInt(glyph.ppem)) - size_px);
        if (best == null or distance < best_distance) {
            best = glyph;
            best_distance = distance;
        }
    }
    return best;
}

fn validateCblcCbdtTables(data: []const u8, cblc: TableRecord, cbdt: TableRecord, glyph_count: u16) FontError!void {
    const strike_count = try cblcStrikeCount(data, cblc);
    for (0..strike_count) |strike_index| {
        const strike = try cblcStrike(data, cblc, glyph_count, strike_index);
        for (strike.start_glyph..@as(usize, strike.end_glyph) + 1) |glyph_index| {
            const location = (try cblcGlyphLocation(data, strike, @intCast(glyph_index))) orelse continue;
            try validateCbdtGlyphData(data, cbdt, location, glyph_count);
        }
    }
}

fn validateCbdtGlyphData(data: []const u8, cbdt: TableRecord, location: CblcGlyphLocation, glyph_count: u16) FontError!void {
    if (location.offset > cbdt.length or location.length > cbdt.length - location.offset) return error.BadSfnt;

    // CBLC is an index over CBDT payloads, so all non-empty locations must be
    // structurally safe even when this library does not render that bitmap
    // format. Validating every referenced payload at parse time prevents an
    // unused strike or glyph from hiding an out-of-bounds CBDT slice that would
    // otherwise surface only during a later bitmap lookup.
    const start = cbdt.offset + location.offset;
    const end = start + location.length;
    const slice = data[start..end];
    switch (location.image_format) {
        1 => return try validateCbdtBitmapPayload(slice, 5, true),
        2 => return try validateCbdtBitmapPayload(slice, 5, false),
        6 => return try validateCbdtBitmapPayload(slice, 8, true),
        7 => return try validateCbdtBitmapPayload(slice, 8, false),
        8 => return try validateCbdtCompoundPayload(slice, 5, glyph_count),
        9 => return try validateCbdtCompoundPayload(slice, 8, glyph_count),
        17 => return try validateCbdtEmbeddedDataPayload(slice, 5),
        18 => return try validateCbdtEmbeddedDataPayload(slice, 8),
        19 => return try validateCbdtEmbeddedDataPayload(slice, 0),
        else => return,
    }
}

fn validateCbdtBitmapPayload(slice: []const u8, metrics_len: usize, byte_aligned_rows: bool) FontError!void {
    if (slice.len < metrics_len) return error.BadSfnt;

    const metrics = switch (metrics_len) {
        5 => try readSmallBitmapMetrics(slice, 0),
        8 => try readBigBitmapMetrics(slice, 0),
        else => unreachable,
    };
    const bitmap_len = if (byte_aligned_rows)
        @as(usize, metrics.height) * ((@as(usize, metrics.width) + 7) / 8)
    else
        (@as(usize, metrics.height) * @as(usize, metrics.width) + 7) / 8;
    if (bitmap_len > slice.len - metrics_len) return error.BadSfnt;
}

fn validateCbdtCompoundPayload(slice: []const u8, metrics_len: usize, glyph_count: u16) FontError!void {
    const components_start = metrics_len + 3;
    if (slice.len < components_start) return error.BadSfnt;
    switch (metrics_len) {
        5 => _ = try readSmallBitmapMetrics(slice, 0),
        8 => _ = try readBigBitmapMetrics(slice, 0),
        else => unreachable,
    }

    // CBDT compound bitmap payloads recursively reference glyph IDs through a
    // compact component array. Validate the array count and target glyphs here
    // so an otherwise-unused bitmap strike cannot contain dangling references
    // that would only be discovered by a future non-PNG renderer.
    const component_count = try bin.readU16At(slice, metrics_len + 1);
    if (@as(usize, component_count) > (slice.len - components_start) / 4) return error.BadSfnt;
    for (0..component_count) |component_index| {
        const component = components_start + component_index * 4;
        try validateGlyphIdInMaxp(try bin.readU16At(slice, component), glyph_count);
    }
}

fn validateCbdtEmbeddedDataPayload(slice: []const u8, metrics_len: usize) FontError!void {
    if (slice.len < metrics_len + 4) return error.BadSfnt;
    const data_len = try bin.readU32At(slice, metrics_len);
    if (data_len > slice.len - metrics_len - 4) return error.BadSfnt;
}

fn cblcGlyphLocation(data: []const u8, strike: CblcStrike, glyph_id: glyph_mod.GlyphId) FontError!?CblcGlyphLocation {
    const SelectedIndexSubtable = struct {
        first: glyph_mod.GlyphId,
        last: glyph_mod.GlyphId,
        offset: usize,
    };
    var selected: ?SelectedIndexSubtable = null;
    var previous_last: ?glyph_mod.GlyphId = null;
    for (0..strike.table_count) |table_index| {
        const record = strike.offset + table_index * 8;
        if (record + 8 > data.len or record + 8 > strike.offset + strike.index_tables_size) return error.BadSfnt;
        const first = try bin.readU16At(data, record);
        const last = try bin.readU16At(data, record + 2);
        const subtable_offset = try bin.readU32At(data, record + 4);
        if (first > last) return error.BadSfnt;
        if (first < strike.start_glyph or last > strike.end_glyph) return error.BadSfnt;
        if (previous_last) |previous| {
            // The IndexSubTableArray is sorted by glyph range.  Overlapping or
            // decreasing ranges make glyph lookup order-dependent, and can hide
            // malformed records behind an earlier match.
            if (first <= previous) return error.BadSfnt;
        }
        previous_last = last;
        // Subtable offsets are relative to the IndexSubTableArray and should
        // point past the array records themselves.  Offsets into the record
        // array would reinterpret glyph range metadata as an index subtable.
        const subtable_data_start = @as(usize, strike.table_count) * 8;
        if (subtable_offset < subtable_data_start or subtable_offset >= strike.index_tables_size) return error.BadSfnt;
        if (glyph_id >= first and glyph_id <= last) selected = .{ .first = first, .last = last, .offset = subtable_offset };
    }
    const entry = selected orelse return null;
    const subtable = strike.offset + entry.offset;
    if (subtable + 8 > data.len or subtable + 8 > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const index_format = try bin.readU16At(data, subtable);
    const image_format = try bin.readU16At(data, subtable + 2);
    const image_data_offset = try bin.readU32At(data, subtable + 4);
    if (image_data_offset > std.math.maxInt(usize)) return error.BadSfnt;
    const image_base: usize = @intCast(image_data_offset);
    const local_index: usize = glyph_id - entry.first;
    return switch (index_format) {
        1 => try cblcGlyphLocationFormat1Or3(data, strike, subtable + 8, entry.first, entry.last, local_index, image_format, image_base, 4),
        2 => try cblcGlyphLocationFormat2(data, strike, subtable + 8, entry.first, entry.last, local_index, image_format, image_base),
        3 => try cblcGlyphLocationFormat1Or3(data, strike, subtable + 8, entry.first, entry.last, local_index, image_format, image_base, 2),
        4 => try cblcGlyphLocationFormat4(data, strike, subtable + 8, glyph_id, image_format, image_base),
        5 => try cblcGlyphLocationFormat5(data, strike, subtable + 8, entry.first, entry.last, glyph_id, image_format, image_base),
        else => null,
    };
}

fn cblcGlyphLocationFormat1Or3(data: []const u8, strike: CblcStrike, offsets_offset: usize, first: glyph_mod.GlyphId, last: glyph_mod.GlyphId, local_index: usize, image_format: u16, image_base: usize, offset_size: usize) FontError!?CblcGlyphLocation {
    const glyphs = @as(usize, last - first) + 1;
    const offsets_len = (glyphs + 1) * offset_size;
    if (offsets_offset + offsets_len > data.len or offsets_offset + offsets_len > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const start = try readCblcOffset(data, offsets_offset + local_index * offset_size, offset_size);
    const end = try readCblcOffset(data, offsets_offset + (local_index + 1) * offset_size, offset_size);
    // Equal adjacent offsets are the CBLC encoding for "no bitmap for this
    // glyph". A decreasing range is different: it means the index subtable is
    // corrupt and must not be silently treated as a missing glyph.
    return try cblcImageLocation(image_format, image_base, start, end);
}

fn cblcGlyphLocationFormat2(data: []const u8, strike: CblcStrike, body_offset: usize, first: glyph_mod.GlyphId, last: glyph_mod.GlyphId, local_index: usize, image_format: u16, image_base: usize) FontError!?CblcGlyphLocation {
    if (body_offset + 12 > data.len or body_offset + 12 > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const image_size = try bin.readU32At(data, body_offset);
    if (image_size == 0) return error.BadSfnt;
    _ = try readBigBitmapMetrics(data, body_offset + 4);

    // Index format 2 is a fixed-size dense range: every glyph covered by the
    // IndexSubTableArray entry consumes exactly imageSize bytes in CBDT.  Check
    // the terminal offset, not just the requested glyph, so an oversized range
    // or multiplication overflow is caught while parsing CBLC/CBDT metadata.
    const glyphs = @as(usize, last - first) + 1;
    const last_start = try checkedCblcImageStart(glyphs - 1, image_size);
    _ = try checkedCblcImageEnd(last_start, image_size);

    const start = try checkedCblcImageStart(local_index, image_size);
    const end = try checkedCblcImageEnd(start, image_size);
    return try cblcImageLocation(image_format, image_base, start, end);
}

fn cblcGlyphLocationFormat4(data: []const u8, strike: CblcStrike, body_offset: usize, glyph_id: glyph_mod.GlyphId, image_format: u16, image_base: usize) FontError!?CblcGlyphLocation {
    if (body_offset + 4 > data.len or body_offset + 4 > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const pair_count = try bin.readU32At(data, body_offset);
    const pairs_offset = body_offset + 4;
    const pairs_len = (@as(usize, pair_count) + 1) * 4;
    if (pairs_offset + pairs_len > data.len or pairs_offset + pairs_len > strike.offset + strike.index_tables_size) return error.BadSfnt;
    for (0..pair_count) |index| {
        const pair = pairs_offset + @as(usize, index) * 4;
        const current_glyph = try bin.readU16At(data, pair);
        if (current_glyph != glyph_id) continue;
        const start = try bin.readU16At(data, pair + 2);
        const end = try bin.readU16At(data, pair + 6);
        return try cblcImageLocation(image_format, image_base, start, end);
    }
    return null;
}

fn cblcGlyphLocationFormat5(data: []const u8, strike: CblcStrike, body_offset: usize, first: glyph_mod.GlyphId, last: glyph_mod.GlyphId, glyph_id: glyph_mod.GlyphId, image_format: u16, image_base: usize) FontError!?CblcGlyphLocation {
    if (body_offset + 16 > data.len or body_offset + 16 > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const image_size = try bin.readU32At(data, body_offset);
    _ = try readBigBitmapMetrics(data, body_offset + 4);
    const glyph_count = try bin.readU32At(data, body_offset + 12);
    if (glyph_count == 0) return error.BadSfnt;
    if (image_size == 0) return error.BadSfnt;

    const range_glyphs = @as(usize, last - first) + 1;
    if (@as(usize, glyph_count) > range_glyphs) return error.BadSfnt;
    const glyphs_offset = body_offset + 16;
    if (glyphs_offset + @as(usize, glyph_count) * 2 > data.len or glyphs_offset + @as(usize, glyph_count) * 2 > strike.offset + strike.index_tables_size) return error.BadSfnt;

    var previous: ?glyph_mod.GlyphId = null;
    var match_index: ?usize = null;
    for (0..glyph_count) |index| {
        const current_glyph = try bin.readU16At(data, glyphs_offset + @as(usize, index) * 2);
        // Format 5 is sparse, but the glyphCodeArray is still ordered and
        // scoped by the IndexSubTableArray range. Enforcing that contract here
        // prevents duplicate/out-of-range codes from making bitmap lookup
        // depend on which valid glyph happens to trigger subtable parsing.
        if (current_glyph < first or current_glyph > last) return error.BadSfnt;
        if (previous) |prev| {
            if (current_glyph <= prev) return error.BadSfnt;
        }
        previous = current_glyph;
        if (current_glyph == glyph_id) match_index = @intCast(index);
    }

    const index = match_index orelse return null;
    const start = try checkedCblcImageStart(index, image_size);
    const end = try checkedCblcImageEnd(start, image_size);
    return try cblcImageLocation(image_format, image_base, start, end);
}

fn checkedCblcImageStart(index: usize, image_size: u32) FontError!usize {
    const size: usize = @intCast(image_size);
    if (index != 0 and size > std.math.maxInt(usize) / index) return error.BadSfnt;
    return index * size;
}

fn checkedCblcImageEnd(start: usize, image_size: u32) FontError!usize {
    const size: usize = @intCast(image_size);
    if (size > std.math.maxInt(usize) - start) return error.BadSfnt;
    return start + size;
}

fn readCblcOffset(data: []const u8, offset: usize, size: usize) FontError!usize {
    return switch (size) {
        2 => try bin.readU16At(data, offset),
        4 => try bin.readU32At(data, offset),
        else => error.BadSfnt,
    };
}

fn cbdtGlyphPng(data: []const u8, cbdt: TableRecord, strike: CblcStrike, location: CblcGlyphLocation) FontError!?BitmapGlyphPng {
    if (location.offset > cbdt.length or location.length > cbdt.length - location.offset) return error.BadSfnt;
    switch (location.image_format) {
        17, 18, 19 => {},
        // `bitmapGlyphPng` is intentionally a PNG-only API.  Non-PNG CBDT
        // image formats may still be valid font data, so treat them as no PNG
        // candidate after validating their declared CBDT byte range above.
        else => return null,
    }
    const start = cbdt.offset + location.offset;
    const end = start + location.length;
    const slice = data[start..end];
    const metrics_len: usize = switch (location.image_format) {
        17 => 5,
        18 => 8,
        19 => 0,
        else => unreachable,
    };
    if (slice.len < metrics_len + 4) return error.BadSfnt;
    const metrics = switch (location.image_format) {
        17 => readSmallBitmapMetrics(slice, 0) catch unreachable,
        18 => readBigBitmapMetrics(slice, 0) catch unreachable,
        19 => BitmapMetrics{ .height = 0, .width = 0, .bearing_x = 0, .bearing_y = 0, .advance = 0 },
        else => unreachable,
    };
    const data_len = try bin.readU32At(slice, metrics_len);
    if (data_len > slice.len - metrics_len - 4) return error.BadSfnt;
    const png = slice[metrics_len + 4 .. metrics_len + 4 + data_len];
    return try bitmapGlyphPngFromData(png, strike.ppem, strike.ppi, metrics.bearing_x, metrics.bearing_y);
}

fn bitmapGlyphPngFromData(png: []const u8, ppem: u16, ppi: u16, origin_offset_x: i16, origin_offset_y: i16) FontError!BitmapGlyphPng {
    if (png.len < 24) return error.BadSfnt;
    if (!std.mem.eql(u8, png[1..4], "PNG")) return error.BadSfnt;
    return .{
        .ppem = ppem,
        .ppi = ppi,
        .origin_offset_x = origin_offset_x,
        .origin_offset_y = origin_offset_y,
        .width = try bin.readU32At(png, 16),
        .height = try bin.readU32At(png, 20),
        .data = png,
    };
}

fn readSmallBitmapMetrics(data: []const u8, offset: usize) FontError!BitmapMetrics {
    if (offset + 5 > data.len) return error.BadSfnt;
    return .{
        .height = data[offset],
        .width = data[offset + 1],
        .bearing_x = @bitCast(data[offset + 2]),
        .bearing_y = @bitCast(data[offset + 3]),
        .advance = data[offset + 4],
    };
}

fn readBigBitmapMetrics(data: []const u8, offset: usize) FontError!BitmapMetrics {
    if (offset + 8 > data.len) return error.BadSfnt;
    return .{
        .height = data[offset],
        .width = data[offset + 1],
        .bearing_x = @bitCast(data[offset + 2]),
        .bearing_y = @bitCast(data[offset + 3]),
        .advance = data[offset + 4],
    };
}

fn findTable(records: []const TableRecord, comptime table_tag: []const u8) ?TableRecord {
    for (records) |record| {
        if (bin.tagEq(record.tag, table_tag)) return record;
    }
    return null;
}

fn validateSfntSearchParameters(num_tables: u16, search_range: u16, entry_selector: u16, range_shift: u16) FontError!void {
    if (num_tables == 0) return error.BadSfnt;

    var max_power_of_two: usize = 1;
    var expected_entry_selector: u16 = 0;
    while (max_power_of_two * 2 <= num_tables) {
        max_power_of_two *= 2;
        expected_entry_selector += 1;
    }

    const expected_search_range = max_power_of_two * 16;
    const table_record_bytes = @as(usize, num_tables) * 16;
    if (expected_search_range > std.math.maxInt(u16) or table_record_bytes > std.math.maxInt(u16)) return error.BadSfnt;
    const expected_range_shift = table_record_bytes - expected_search_range;
    if (search_range != expected_search_range or entry_selector != expected_entry_selector or range_shift != expected_range_shift) {
        return error.BadSfnt;
    }
}

fn validateSfntTableDirectory(records: []const TableRecord) FontError!void {
    var previous_tag: ?[4]u8 = null;
    for (records) |record| {
        if (previous_tag) |previous| {
            // The SFNT directory is specified as a lexicographically sorted map
            // keyed by tag. Requiring strict order rejects duplicates and keeps
            // required-table lookup from depending on malformed record order.
            if (std.mem.order(u8, &previous, &record.tag) != .lt) return error.BadSfnt;
        }
        previous_tag = record.tag;
    }
}

fn sfntDirectoryEnd(data: []const u8, start: usize, num_tables: u16) FontError!usize {
    const record_bytes = @as(usize, num_tables) * 16;
    if (start > data.len or data.len - start < 12) return error.BadSfnt;
    if (record_bytes > data.len - start - 12) return error.BadSfnt;
    return start + 12 + record_bytes;
}

fn validateSfntTableRanges(records: []const TableRecord, reserved_prefix_end: usize, directory_start: usize, directory_end: usize) FontError!void {
    for (records, 0..) |record, index| {
        // OpenType table payloads are independent ranges that must not alias
        // reserved SFNT/TTC metadata or another table in the same face. TTCs
        // can share table payloads across faces, and shared payloads may sit
        // before this face's directory, so validate interval
        // overlap rather than requiring every offset to be after `directory_end`.
        if (record.length == 0) continue;
        const record_end = record.offset + record.length;
        if (record.offset < reserved_prefix_end) return error.BadSfnt;
        if (rangesOverlap(record.offset, record_end, directory_start, directory_end)) return error.BadSfnt;
        for (records[index + 1 ..]) |other| {
            if (other.length == 0) continue;
            const other_end = other.offset + other.length;
            if (rangesOverlap(record.offset, record_end, other.offset, other_end)) return error.BadSfnt;
        }
    }
}

fn rangesOverlap(a_start: usize, a_end: usize, b_start: usize, b_end: usize) bool {
    return a_start < b_end and b_start < a_end;
}

fn requireTableLength(record: TableRecord, minimum_length: usize) FontError!void {
    if (record.length < minimum_length) return error.BadSfnt;
}

fn validateHeadTable(data: []const u8, head: TableRecord, format: FontFormat) FontError!void {
    try requireTableLength(head, 54);

    const version = try bin.readU32At(data, head.offset);
    const magic_number = try bin.readU32At(data, head.offset + 12);
    const units_per_em = try bin.readU16At(data, head.offset + 18);
    const x_min = try bin.readI16At(data, head.offset + 36);
    const y_min = try bin.readI16At(data, head.offset + 38);
    const x_max = try bin.readI16At(data, head.offset + 40);
    const y_max = try bin.readI16At(data, head.offset + 42);
    const index_to_loc_format = try bin.readI16At(data, head.offset + 50);
    const glyph_data_format = try bin.readI16At(data, head.offset + 52);

    // These fields are SFNT-wide invariants rather than Cangjie preferences:
    // accepting an arbitrary version or magic number means the bytes may not be
    // a `head` table at all, and accepting out-of-range design units makes
    // later font-size-to-em math ambiguous for otherwise parseable faces.
    if (version != 0x00010000) return error.BadSfnt;
    if (magic_number != 0x5f0f3cf5) return error.BadSfnt;
    if (units_per_em < 16 or units_per_em > 16384) return error.BadSfnt;
    if (x_min > x_max or y_min > y_max) return error.BadSfnt;

    // indexToLocFormat only drives glyf/loca lookup.  CFF-backed OpenType
    // faces do not have a loca table, so avoid rejecting legacy production OTFs
    // for an otherwise-unused field while still validating TrueType faces before
    // their loca table is interpreted.
    if (format == .truetype and index_to_loc_format != 0 and index_to_loc_format != 1) {
        return error.InvalidLoca;
    }
    if (glyph_data_format != 0) return error.BadSfnt;
}

fn validateMaxpTable(data: []const u8, maxp: TableRecord, format: FontFormat) FontError!void {
    try requireTableLength(maxp, 6);
    const version = try bin.readU32At(data, maxp.offset);
    switch (format) {
        .truetype => {
            // TrueType outlines require the version 1.0 maxp payload because
            // rasterizers use its glyph-program and composite limits when
            // validating glyf instructions. Accepting the six-byte CFF shape
            // here would silently classify an internally inconsistent SFNT as
            // a usable TrueType face.
            if (version != 0x00010000) return error.BadSfnt;
            try requireTableLength(maxp, 32);
            const max_zones = try bin.readU16At(data, maxp.offset + 14);
            // maxZones is one of the few maxp v1 maxima with a fixed semantic
            // range: TrueType programs may use either the glyph zone alone or
            // the glyph plus twilight zone. Rejecting other values during face
            // load keeps malformed hinting metadata from being mistaken for an
            // unbounded interpreter resource count.
            if (max_zones != 1 and max_zones != 2) return error.BadSfnt;
        },
        .opentype_cff => {
            // CFF-backed OpenType fonts use maxp version 0.5, whose contract is
            // only the version and numGlyphs fields. A version 1.0 maxp table
            // belongs to glyf-based fonts and indicates a mismatched outline
            // stack even when the CFF table is otherwise present.
            if (version != 0x00005000) return error.BadSfnt;
        },
    }
}

fn validateCffGlyphCount(data: []const u8, cff: TableRecord, glyph_count: u16) FontError!void {
    // For CFF-backed OpenType faces, maxp.numGlyphs must describe the
    // CharStrings INDEX exactly. Validate the relationship during parse so
    // callers do not accept a face whose cmap or shaping tables can name
    // glyph ids that the CFF outline data can never resolve.
    const info = try cff_mod.parseInfo(data[cff.offset .. cff.offset + cff.length]);
    if (info.charstrings_count != glyph_count) return error.BadSfnt;
}

fn minimumOs2TableLength(version: u16) FontError!usize {
    // usWeightClass/usWidthClass/fsSelection all live in the original OS/2
    // payload, but the SFNT directory length is still the table's versioned
    // contract. Enforcing the full minimum keeps a truncated v4/v5 OS/2 table
    // from being accepted just because the early style fields happen to fit.
    return switch (version) {
        0 => 78,
        1 => 86,
        2...4 => 96,
        5 => 100,
        else => error.BadSfnt,
    };
}

fn validateOs2Table(data: []const u8, os2: TableRecord) FontError!void {
    try requireTableLength(os2, 2);
    const version = try bin.readU16At(data, os2.offset);
    try requireTableLength(os2, try minimumOs2TableLength(version));

    const weight = try bin.readU16At(data, os2.offset + 4);
    const width = try bin.readU16At(data, os2.offset + 6);
    const fs_selection = try bin.readU16At(data, os2.offset + 62);

    // These fields are used by font databases and style matching, so validate
    // their OS/2-defined ranges when the face is parsed rather than accepting a
    // font whose advertised style cannot be represented consistently later.
    if (weight < 1 or weight > 1000) return error.BadSfnt;
    if (width < 1 or width > 9) return error.BadSfnt;

    const reserved_selection_bits: u16 = 0xfc00;
    if ((fs_selection & reserved_selection_bits) != 0) return error.BadSfnt;

    const regular = (fs_selection & 0x0040) != 0;
    const named_style_bits = fs_selection & (0x0001 | 0x0020 | 0x0200);
    if (regular and named_style_bits != 0) return error.BadSfnt;
}

fn validateHorizontalMetricsTables(data: []const u8, hhea: TableRecord, hmtx: TableRecord, glyph_count: u16) FontError!u16 {
    try validateMetricHeader(data, hhea, 0x00010000);
    const metric_count = try bin.readU16At(data, hhea.offset + 34);
    const required_hmtx_length = try metricTableRequiredLength(glyph_count, metric_count);
    if (hmtx.length < required_hmtx_length) return error.InvalidMetrics;
    return metric_count;
}

fn validateVerticalMetricsTables(data: []const u8, glyph_count: u16, maybe_vhea: ?TableRecord, maybe_vmtx: ?TableRecord) FontError!void {
    if (maybe_vhea == null and maybe_vmtx == null) return;
    const vhea = maybe_vhea orelse return error.InvalidMetrics;
    const vmtx = maybe_vmtx orelse return error.InvalidMetrics;

    // vhea/vmtx mirror the hhea/hmtx compression contract for vertical layout:
    // the header declares how many full advance/bearing records exist, and the
    // remaining glyphs borrow the final advance while supplying only a top side
    // bearing. Validate the pair while the font is parsed even though Cangjie
    // does not yet expose vertical metrics, so a malformed production font
    // cannot be accepted with a latent out-of-bounds vmtx table.
    try validateVerticalMetricHeader(data, vhea);
    const metric_count = try bin.readU16At(data, vhea.offset + 34);
    const required_vmtx_length = try metricTableRequiredLength(glyph_count, metric_count);
    if (vmtx.length < required_vmtx_length) return error.InvalidMetrics;
}

fn validateVerticalMetricHeader(data: []const u8, vhea: TableRecord) FontError!void {
    try requireTableLength(vhea, 36);
    const version = try bin.readU32At(data, vhea.offset);
    if (version != 0x00010000 and version != 0x00011000) return error.InvalidMetrics;
    try validateMetricHeaderReservedFields(data, vhea);
}

fn validateMetricHeader(data: []const u8, header: TableRecord, expected_version: u32) FontError!void {
    try requireTableLength(header, 36);
    const version = try bin.readU32At(data, header.offset);
    if (version != expected_version) return error.InvalidMetrics;
    try validateMetricHeaderReservedFields(data, header);
}

fn validateMetricHeaderReservedFields(data: []const u8, header: TableRecord) FontError!void {
    // The four reserved int16 fields and metricDataFormat are required to be
    // zero by both hhea and vhea. Enforcing those constants makes the metric
    // count at byte 34 unambiguous and keeps malformed table variants from
    // passing validation merely because their final two bytes look plausible.
    for (0..5) |index| {
        if (try bin.readU16At(data, header.offset + 24 + index * 2) != 0) return error.InvalidMetrics;
    }
}

fn validatePostTable(data: []const u8, post: TableRecord, glyph_count: u16) FontError!void {
    try requireTableLength(post, 32);
    const version = try bin.readU32At(data, post.offset);
    switch (version) {
        0x00010000 => {
            // Format 1.0 implies the complete standard Macintosh glyph-name
            // set. If maxp advertises a different glyph count, consumers that
            // synthesize glyph names from `post` and consumers that use maxp
            // for metrics/outlines disagree on the addressable glyph set.
            if (glyph_count != 258) return error.BadSfnt;
        },
        0x00020000 => try validatePostFormat2(data, post, glyph_count),
        0x00025000 => try validatePostFormat25(data, post, glyph_count),
        0x00030000 => {},
        0x00040000 => try validatePostFormat4(post, glyph_count),
        else => return error.BadSfnt,
    }
}

fn validatePostFormat2(data: []const u8, post: TableRecord, glyph_count: u16) FontError!void {
    const table = data[post.offset .. post.offset + post.length];
    if (post.length - 32 < 2) return error.BadSfnt;
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (number_of_glyphs != glyph_count) return error.BadSfnt;
    const glyph_name_indices_offset: usize = 34;
    const glyph_name_indices_len = @as(usize, number_of_glyphs) * 2;
    if (glyph_name_indices_len > post.length - glyph_name_indices_offset) return error.BadSfnt;

    var custom_name_count: usize = 0;
    for (0..number_of_glyphs) |glyph_index| {
        const name_index = try bin.readU16At(table, glyph_name_indices_offset + glyph_index * 2);
        if (name_index >= 258) {
            custom_name_count = @max(custom_name_count, @as(usize, name_index) - 257);
        }
    }

    var cursor = glyph_name_indices_offset + glyph_name_indices_len;
    for (0..custom_name_count) |_| {
        if (cursor >= post.length) return error.BadSfnt;
        const name_len = table[cursor];
        cursor += 1;
        if (name_len == 0 or name_len > 63) return error.BadSfnt;
        if (@as(usize, name_len) > post.length - cursor) return error.BadSfnt;
        if (!isPostGlyphName(table[cursor .. cursor + name_len])) return error.BadSfnt;
        cursor += name_len;
    }
}

fn validatePostFormat25(data: []const u8, post: TableRecord, glyph_count: u16) FontError!void {
    const table = data[post.offset .. post.offset + post.length];
    if (post.length - 32 < 2) return error.BadSfnt;
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (number_of_glyphs != glyph_count) return error.BadSfnt;
    const offsets_offset: usize = 34;
    if (@as(usize, number_of_glyphs) > post.length - offsets_offset) return error.BadSfnt;

    for (0..number_of_glyphs) |glyph_index| {
        const signed_delta: i8 = @bitCast(table[offsets_offset + glyph_index]);
        const standard_index = @as(i32, @intCast(glyph_index)) + @as(i32, signed_delta);
        if (standard_index < 0 or standard_index >= 258) return error.BadSfnt;
    }
}

fn validatePostFormat4(post: TableRecord, glyph_count: u16) FontError!void {
    if (@as(usize, glyph_count) * 2 > post.length - 32) return error.BadSfnt;
}

fn validateKernTable(data: []const u8, kern: TableRecord, glyph_count: u16) FontError!void {
    try requireTableLength(kern, 4);
    const version = try bin.readU32At(data, kern.offset);
    if (version == 0x00010000) {
        try validateAppleKernTable(data, kern, glyph_count);
        return;
    }
    if ((version >> 16) != 0) {
        // Unknown non-legacy versions are ignored by `kerning`; keep that
        // compatibility behavior instead of rejecting a table this renderer
        // intentionally does not interpret.
        return;
    }
    try validateLegacyKernTable(data, kern, glyph_count);
}

fn validateLegacyKernTable(data: []const u8, kern: TableRecord, glyph_count: u16) FontError!void {
    const table_count = try bin.readU16At(data, kern.offset + 2);
    const table_end = kern.offset + kern.length;
    var subtable_offset = kern.offset + 4;
    for (0..table_count) |_| {
        if (subtable_offset > table_end or table_end - subtable_offset < 6) return error.BadSfnt;
        const length = try bin.readU16At(data, subtable_offset + 2);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        if (length < 6 or length > table_end - subtable_offset) return error.BadSfnt;

        const format = coverage >> 8;
        const horizontal = (coverage & 0x0001) != 0;
        const minimum = (coverage & 0x0002) != 0;
        const cross_stream = (coverage & 0x0004) != 0;
        if (format == 0 and horizontal and !minimum and !cross_stream) {
            try validateKernFormat0Body(data[subtable_offset + 6 .. subtable_offset + length], glyph_count);
        }
        subtable_offset += length;
    }
}

fn validateAppleKernTable(data: []const u8, kern: TableRecord, glyph_count: u16) FontError!void {
    try requireTableLength(kern, 8);
    const table_count = try bin.readU32At(data, kern.offset + 4);
    const table_end = kern.offset + kern.length;
    var subtable_offset = kern.offset + 8;
    for (0..table_count) |_| {
        if (subtable_offset > table_end or table_end - subtable_offset < 8) return error.BadSfnt;
        const length = try bin.readU32At(data, subtable_offset);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        if (length < 8 or length > table_end - subtable_offset) return error.BadSfnt;

        const format = coverage & 0x00ff;
        const vertical = (coverage & 0x8000) != 0;
        const cross_stream = (coverage & 0x4000) != 0;
        const variation = (coverage & 0x2000) != 0;
        if (format == 0 and !vertical and !cross_stream and !variation) {
            try validateKernFormat0Body(data[subtable_offset + 8 .. subtable_offset + length], glyph_count);
        }
        subtable_offset += length;
    }
}

fn validateKernFormat0Body(data: []const u8, glyph_count: u16) FontError!void {
    // Format-0 kern subtables are searched with a binary search over packed
    // left/right glyph pairs. Validate the complete pair array while parsing so
    // malformed fonts cannot hide out-of-range glyph IDs or make kerning depend
    // on unsorted record order.
    if (data.len < 8) return error.BadSfnt;
    const pair_count = try bin.readU16At(data, 0);
    if (@as(usize, pair_count) * 6 > data.len - 8) return error.BadSfnt;

    var previous_pair: ?u32 = null;
    for (0..pair_count) |index| {
        const offset = 8 + index * 6;
        const left = try bin.readU16At(data, offset);
        const right = try bin.readU16At(data, offset + 2);
        try validateGlyphIdInMaxp(left, glyph_count);
        try validateGlyphIdInMaxp(right, glyph_count);

        const pair = (@as(u32, left) << 16) | right;
        if (previous_pair) |previous| {
            if (pair <= previous) return error.BadSfnt;
        }
        previous_pair = pair;
    }
}

fn isPostGlyphName(name: []const u8) bool {
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '_') continue;
        return false;
    }
    return true;
}

fn hmtxRequiredLength(glyph_count: u16, number_of_h_metrics: u16) FontError!usize {
    return metricTableRequiredLength(glyph_count, number_of_h_metrics);
}

fn metricTableRequiredLength(glyph_count: u16, metric_count: u16) FontError!usize {
    if (metric_count == 0 or metric_count > glyph_count) return error.InvalidMetrics;
    return @as(usize, metric_count) * 4 + @as(usize, glyph_count - metric_count) * 2;
}

fn locaEntryRequiredLength(glyph_id: u32, index_to_loc_format: i16) FontError!usize {
    const entry_count = @as(usize, glyph_id) + 1;
    return switch (index_to_loc_format) {
        0 => entry_count * 2,
        1 => entry_count * 4,
        else => error.InvalidLoca,
    };
}

fn validateLocaTable(data: []const u8, loca: TableRecord, glyf: TableRecord, glyph_count: u16, index_to_loc_format: i16) FontError!void {
    const required_length = try locaEntryRequiredLength(glyph_count, index_to_loc_format);
    if (loca.length < required_length) return error.InvalidLoca;

    // The loca table is the authoritative glyf byte map. Validate the complete
    // offset array at parse time instead of deferring malformed entries until a
    // specific glyph is outlined; otherwise a font can be accepted while later
    // glyph ids reveal decreasing offsets or pointers beyond the glyf table.
    var previous: usize = 0;
    for (0..@as(usize, glyph_count) + 1) |index| {
        const current = switch (index_to_loc_format) {
            0 => @as(usize, try bin.readU16At(data, loca.offset + index * 2)) * 2,
            1 => try bin.readU32At(data, loca.offset + index * 4),
            else => return error.InvalidLoca,
        };
        if (current < previous or current > glyf.length) return error.InvalidLoca;
        previous = current;
    }
}

fn glyfOffsetFromLoca(data: []const u8, loca: TableRecord, index_to_loc_format: i16, glyph_index: usize) FontError!usize {
    return switch (index_to_loc_format) {
        0 => @as(usize, try bin.readU16At(data, loca.offset + glyph_index * 2)) * 2,
        1 => try bin.readU32At(data, loca.offset + glyph_index * 4),
        else => error.InvalidLoca,
    };
}

fn validateGlyfTable(
    allocator: std.mem.Allocator,
    data: []const u8,
    loca: TableRecord,
    glyf: TableRecord,
    glyph_count: u16,
    index_to_loc_format: i16,
    max_component_elements: u16,
    max_component_depth: u16,
) FontError!void {
    // `loca` proves where each glyph byte range lives; `glyf` still owns the
    // structure inside those ranges. Validate the cheap cross-table contracts
    // at parse time so a malformed compound glyph cannot be accepted and then
    // fail only when the specific glyph is outlined during layout or fallback.
    const compound_adjacency = try allocator.alloc(CompoundGlyphLinks, glyph_count);
    @memset(compound_adjacency, .{});
    defer {
        for (compound_adjacency) |links| allocator.free(links.components);
        allocator.free(compound_adjacency);
    }
    const point_counts = try allocator.alloc(?usize, glyph_count);
    defer allocator.free(point_counts);
    @memset(point_counts, null);

    for (0..glyph_count) |glyph_index| {
        const start = try glyfOffsetFromLoca(data, loca, index_to_loc_format, glyph_index);
        const end = try glyfOffsetFromLoca(data, loca, index_to_loc_format, glyph_index + 1);
        if (end == start) {
            point_counts[glyph_index] = 0;
            continue;
        }
        if (end < start or end > glyf.length) return error.InvalidLoca;

        const glyph_data = data[glyf.offset + start .. glyf.offset + end];
        if (glyph_data.len < 10) return error.InvalidGlyph;
        const contour_count = try bin.readI16At(glyph_data, 0);
        if (contour_count >= 0) {
            point_counts[glyph_index] = try validateSimpleGlyphDescription(glyph_data, @intCast(contour_count));
        } else {
            compound_adjacency[glyph_index] = try validateCompoundGlyphDescription(allocator, glyph_data, glyph_count);
        }
    }

    try validateCompoundGlyphGraph(allocator, compound_adjacency, max_component_depth);
    try validateMaxComponentElements(compound_adjacency, max_component_elements);
    try validateCompoundGlyphPointMatches(compound_adjacency, point_counts);
}

const CompoundGlyphLinks = struct {
    components: []CompoundGlyphComponent = &.{},
};

const CompoundGlyphComponent = struct {
    glyph: glyph_mod.GlyphId,
    point_match: ?CompoundGlyphPointMatch = null,
};

const CompoundGlyphPointMatch = struct {
    parent_point: u16,
    child_point: u16,
};

fn validateSimpleGlyphDescription(glyph_data: []const u8, contour_count: u16) FontError!usize {
    if (contour_count == 0) return 0;

    var offset: usize = 10; // numberOfContours + x/y bounds.
    var total_points: usize = 0;
    var previous_end: ?u16 = null;
    for (0..contour_count) |_| {
        if (offset + 2 > glyph_data.len) return error.InvalidGlyph;
        const end = try bin.readU16At(glyph_data, offset);
        offset += 2;
        if (previous_end) |prev| {
            if (end <= prev) return error.InvalidGlyph;
        }
        previous_end = end;
        total_points = @as(usize, end) + 1;
    }

    if (offset + 2 > glyph_data.len) return error.InvalidGlyph;
    const instruction_len = try bin.readU16At(glyph_data, offset);
    offset += 2;
    if (@as(usize, instruction_len) > glyph_data.len - offset) return error.InvalidGlyph;
    offset += instruction_len;

    // Simple glyph coordinates are split into an RLE flag stream followed by
    // separate X and Y delta streams. Validate those byte counts while parsing
    // the flags so malformed outlines are rejected during font parsing rather
    // than only when a caller later expands this specific glyph.
    var expanded_flags: usize = 0;
    var x_bytes: usize = 0;
    var y_bytes: usize = 0;
    while (expanded_flags < total_points) {
        if (offset >= glyph_data.len) return error.InvalidGlyph;
        const flag = glyph_data[offset];
        offset += 1;
        expanded_flags += 1;
        x_bytes += simpleGlyphCoordinateByteCount(flag, true);
        y_bytes += simpleGlyphCoordinateByteCount(flag, false);
        if ((flag & 0x08) != 0) {
            if (offset >= glyph_data.len) return error.InvalidGlyph;
            const repeat = glyph_data[offset];
            offset += 1;
            if (@as(usize, repeat) > total_points - expanded_flags) return error.InvalidGlyph;
            expanded_flags += repeat;
            x_bytes += @as(usize, repeat) * simpleGlyphCoordinateByteCount(flag, true);
            y_bytes += @as(usize, repeat) * simpleGlyphCoordinateByteCount(flag, false);
        }
    }

    if (x_bytes > glyph_data.len - offset) return error.InvalidGlyph;
    offset += x_bytes;
    if (y_bytes > glyph_data.len - offset) return error.InvalidGlyph;
    return total_points;
}

fn simpleGlyphCoordinateByteCount(flag: u8, x_axis: bool) usize {
    const short_vector_bit: u8 = if (x_axis) 0x02 else 0x04;
    const same_or_positive_bit: u8 = if (x_axis) 0x10 else 0x20;
    if ((flag & short_vector_bit) != 0) return 1;
    if ((flag & same_or_positive_bit) != 0) return 0;
    return 2;
}

fn validateCompoundGlyphDescription(allocator: std.mem.Allocator, glyph_data: []const u8, glyph_count: u16) FontError!CompoundGlyphLinks {
    var components = std.ArrayList(CompoundGlyphComponent).empty;
    errdefer components.deinit(allocator);

    var offset: usize = 10; // numberOfContours + x/y bounds.
    while (true) {
        if (offset + 4 > glyph_data.len) return error.InvalidGlyph;
        const flags = try bin.readU16At(glyph_data, offset);
        try validateCompoundGlyphFlags(flags);
        // Do not enforce uniqueness for USE_MY_METRICS. The TrueType rasterizer
        // contract treats the first flagged component as the metrics source, and
        // real production fonts may set the bit on later components as well.
        // Reject only flag combinations that make the component stream itself
        // ambiguous; preserving this leniency keeps parse-time validation from
        // excluding fonts accepted by platform engines.
        const component_glyph = try bin.readU16At(glyph_data, offset + 2);
        if (component_glyph >= glyph_count) return error.InvalidGlyph;
        offset += 4;

        const argument_bytes: usize = if ((flags & 0x0001) != 0) 4 else 2;
        if (argument_bytes > glyph_data.len - offset) return error.InvalidGlyph;
        const point_match = try readCompoundGlyphPointMatch(glyph_data[offset .. offset + argument_bytes], flags);
        try components.append(allocator, .{ .glyph = component_glyph, .point_match = point_match });
        offset += argument_bytes;

        const has_scale = (flags & 0x0008) != 0;
        const has_xy_scale = (flags & 0x0040) != 0;
        const has_two_by_two = (flags & 0x0080) != 0;
        const scale_flag_count = @as(u8, @intFromBool(has_scale)) +
            @as(u8, @intFromBool(has_xy_scale)) +
            @as(u8, @intFromBool(has_two_by_two));
        if (scale_flag_count > 1) return error.InvalidGlyph;
        const scale_bytes: usize = if (has_scale) 2 else if (has_xy_scale) 4 else if (has_two_by_two) 8 else 0;
        if (scale_bytes > glyph_data.len - offset) return error.InvalidGlyph;
        offset += scale_bytes;

        if ((flags & 0x0020) == 0) {
            if ((flags & 0x0100) != 0) {
                if (offset + 2 > glyph_data.len) return error.InvalidGlyph;
                const instruction_length = try bin.readU16At(glyph_data, offset);
                offset += 2;
                if (@as(usize, instruction_length) > glyph_data.len - offset) return error.InvalidGlyph;
            }
            return .{ .components = try components.toOwnedSlice(allocator) };
        }
    }
}

fn validateCompoundGlyphFlags(flags: u16) FontError!void {
    // Composite glyph flags are part of the glyf bytecode grammar, not an
    // opaque renderer hint. Rejecting unknown bits at parse time prevents the
    // component stream from being interpreted with semantics this parser does
    // not implement, and catches the obsolete bit 4 before it can masquerade as
    // a normal component.
    const known_flags: u16 = 0x0001 | 0x0002 | 0x0004 | 0x0008 |
        0x0020 | 0x0040 | 0x0080 | 0x0100 |
        0x0200 | 0x0400 | 0x0800 | 0x1000;
    if ((flags & ~known_flags) != 0) return error.InvalidGlyph;

    // SCALED_COMPONENT_OFFSET and UNSCALED_COMPONENT_OFFSET give opposite
    // meanings to the same component arguments; accepting both would leave
    // component placement dependent on whichever interpretation a later
    // renderer happens to choose.
    if ((flags & 0x0800) != 0 and (flags & 0x1000) != 0) return error.InvalidGlyph;
}

fn readCompoundGlyphPointMatch(argument_data: []const u8, flags: u16) FontError!?CompoundGlyphPointMatch {
    // When ARGS_ARE_XY_VALUES is clear, the two component arguments are point
    // numbers: arg1 names a point already contributed to the parent compound
    // glyph, and arg2 names a point in the referenced child glyph. Preserve
    // those unsigned values so a later graph walk can check them against the
    // actual simple/compound point counts instead of treating this placement
    // mode as opaque bytes until outline expansion rejects it as unsupported.
    if ((flags & 0x0002) != 0) return null;

    return if ((flags & 0x0001) != 0)
        .{
            .parent_point = try bin.readU16At(argument_data, 0),
            .child_point = try bin.readU16At(argument_data, 2),
        }
    else
        .{
            .parent_point = argument_data[0],
            .child_point = argument_data[1],
        };
}

fn validateCompoundGlyphGraph(allocator: std.mem.Allocator, adjacency: []const CompoundGlyphLinks, max_component_depth: u16) FontError!void {
    // Compound glyphs form a directed component graph. maxp.maxComponentDepth is
    // the font-wide bound on nested composite expansion; enforcing it here keeps
    // parsed fonts inside the same recursion budget used later by outline
    // materialization, and turns under-reported limits into a parse-time
    // correctness error instead of a glyph-specific surprise.
    const states = try allocator.alloc(CompoundVisitState, adjacency.len);
    defer allocator.free(states);
    @memset(states, .unvisited);
    const depths = try allocator.alloc(u16, adjacency.len);
    defer allocator.free(depths);
    @memset(depths, 0);

    for (adjacency, 0..) |_, glyph_index| {
        if (states[glyph_index] == .unvisited) {
            _ = try visitCompoundGlyph(adjacency, states, depths, @intCast(glyph_index));
        }
        if (depths[glyph_index] > max_component_depth) return error.InvalidGlyph;
    }
}

const CompoundVisitState = enum {
    unvisited,
    visiting,
    visited,
};

fn visitCompoundGlyph(
    adjacency: []const CompoundGlyphLinks,
    states: []CompoundVisitState,
    depths: []u16,
    glyph_id: glyph_mod.GlyphId,
) FontError!u16 {
    const index: usize = glyph_id;
    switch (states[index]) {
        .visited => return depths[index],
        .visiting => return error.InvalidGlyph,
        .unvisited => {},
    }

    states[index] = .visiting;
    var max_depth: u16 = 0;
    for (adjacency[index].components) |component| {
        const component_depth = try visitCompoundGlyph(adjacency, states, depths, component.glyph);
        if (component_depth == std.math.maxInt(u16)) return error.InvalidGlyph;
        max_depth = @max(max_depth, component_depth + 1);
    }
    depths[index] = max_depth;
    states[index] = .visited;
    return max_depth;
}

fn validateMaxComponentElements(adjacency: []const CompoundGlyphLinks, max_component_elements: u16) FontError!void {
    // maxp.maxComponentElements describes the largest direct component count in
    // any compound glyph. It is easy for a malformed table to keep every
    // component record structurally valid while under-reporting this aggregate;
    // validating the aggregate makes maxp useful as a trusted summary table.
    for (adjacency) |links| {
        if (links.components.len > max_component_elements) return error.InvalidGlyph;
    }
}

fn validateCompoundGlyphPointMatches(adjacency: []const CompoundGlyphLinks, point_counts: []?usize) FontError!void {
    // Point-matching components form constraints across the compound graph, so
    // they cannot be fully checked while reading one component record in
    // isolation. After cycle/depth validation has proven the graph finite,
    // derive each compound glyph's point count and ensure every matched parent
    // and child point is already present in its respective outline.
    for (adjacency, 0..) |_, glyph_index| {
        _ = try compoundGlyphPointCount(adjacency, point_counts, @intCast(glyph_index));
    }
}

fn compoundGlyphPointCount(adjacency: []const CompoundGlyphLinks, point_counts: []?usize, glyph_id: glyph_mod.GlyphId) FontError!usize {
    const index: usize = glyph_id;
    if (point_counts[index]) |count| return count;

    var total: usize = 0;
    for (adjacency[index].components) |component| {
        const child_count = try compoundGlyphPointCount(adjacency, point_counts, component.glyph);
        if (component.point_match) |point_match| {
            if (@as(usize, point_match.parent_point) >= total) return error.InvalidGlyph;
            if (@as(usize, point_match.child_point) >= child_count) return error.InvalidGlyph;
        }
        if (child_count > std.math.maxInt(usize) - total) return error.InvalidGlyph;
        total += child_count;
    }

    point_counts[index] = total;
    return total;
}

const TtcHeader = struct {
    face_count: usize,
    header_length: usize,
};

fn parseTtcHeader(data: []const u8) FontError!?TtcHeader {
    const tag = try bin.readU32At(data, 0);
    if (tag != 0x74746366) return null; // "ttcf"

    const version = try bin.readU32At(data, 4);
    const major = version >> 16;
    if (major != 1 and major != 2) return error.BadSfnt;

    const face_count: usize = @intCast(try bin.readU32At(data, 8));
    if (face_count == 0) return error.BadSfnt;
    if (face_count > (data.len - 12) / 4) return error.BadSfnt;

    // TTC face offsets are an array immediately following the fixed 12-byte
    // header. Version 2 collections add three DSIG fields after that array.
    // Treat the complete header as reserved so a malformed offset cannot make
    // the SFNT parser reinterpret collection metadata as an embedded font.
    var header_length = 12 + face_count * 4;
    if (major == 2) {
        if (header_length > data.len - 12) return error.BadSfnt;
        const dsig_tag = try bin.readU32At(data, header_length);
        const dsig_length = try bin.readU32At(data, header_length + 4);
        const dsig_offset = try bin.readU32At(data, header_length + 8);
        header_length += 12;

        // The optional DSIG table is described by absolute collection offsets.
        // Empty descriptors are encoded as all zero; any partially-populated
        // descriptor must identify an in-file range after the complete TTC
        // header. Otherwise a v2 collection can advertise signatures that alias
        // face offsets or point beyond the borrowed byte slice.
        if (dsig_tag == 0 and dsig_length == 0 and dsig_offset == 0) {
            // No digital-signature table is present.
        } else {
            if (dsig_tag != 0x44534947 or dsig_length == 0) return error.BadSfnt;
            const dsig_start: usize = @intCast(dsig_offset);
            const length: usize = @intCast(dsig_length);
            if (dsig_start < header_length) return error.BadSfnt;
            if (dsig_start > data.len or length > data.len - dsig_start) return error.BadSfnt;
        }
    }

    return .{
        .face_count = face_count,
        .header_length = header_length,
    };
}

fn sfntOffset(data: []const u8, face_index: usize) FontError!usize {
    const header = (try parseTtcHeader(data)) orelse return 0;
    if (face_index >= header.face_count) return error.BadSfnt;
    const offset = try bin.readU32At(data, 12 + face_index * 4);
    if (offset < header.header_length) return error.BadSfnt;
    if (offset > data.len - 12) return error.BadSfnt;
    return offset;
}

fn parseCmapSubtables(allocator: std.mem.Allocator, data: []const u8, cmap: TableRecord, glyph_count: u16) FontError![]CmapSubtable {
    if (cmap.length < 4) return error.BadSfnt;
    const version = try bin.readU16At(data, cmap.offset);
    if (version != 0) return error.BadSfnt;
    const count = try bin.readU16At(data, cmap.offset + 2);
    if (@as(usize, count) * 8 > cmap.length - 4) return error.BadSfnt;
    const records_end = 4 + @as(usize, count) * 8;

    var subtables = std.ArrayList(CmapSubtable).empty;
    errdefer subtables.deinit(allocator);
    var previous_encoding: ?struct { platform_id: u16, encoding_id: u16 } = null;
    for (0..count) |i| {
        const rec = cmap.offset + 4 + i * 8;
        const platform_id = try bin.readU16At(data, rec);
        const encoding_id = try bin.readU16At(data, rec + 2);
        if (previous_encoding) |previous| {
            // Encoding records are a directory keyed by platform/encoding ID.
            // Enforcing the OpenType sort order also rejects duplicate keys,
            // avoiding ambiguous cmap selection when two records claim the
            // same platform-specific character map.
            if (platform_id < previous.platform_id or (platform_id == previous.platform_id and encoding_id <= previous.encoding_id)) {
                return error.BadSfnt;
            }
        }
        previous_encoding = .{ .platform_id = platform_id, .encoding_id = encoding_id };

        const sub_offset = try bin.readU32At(data, rec + 4);
        // EncodingRecord offsets name complete cmap subtables, not arbitrary
        // byte positions. Requiring child subtables to start after the record
        // directory prevents an offset field or a later EncodingRecord from
        // being reinterpreted as a plausible format-0 header.
        if (sub_offset < records_end or sub_offset > cmap.length - 2) return error.BadSfnt;
        const absolute = cmap.offset + sub_offset;
        const format = try bin.readU16At(data, absolute);
        const length = try cmapSubtableLength(data, cmap, @intCast(sub_offset), format);
        try validateCmapSubtable(data, absolute, length, format, platform_id, encoding_id);
        try validateCmapGlyphIds(data, absolute, length, format, glyph_count);
        try subtables.append(allocator, .{
            .platform_id = platform_id,
            .encoding_id = encoding_id,
            .offset = absolute,
            .length = length,
            .format = format,
        });
    }
    return try subtables.toOwnedSlice(allocator);
}

fn cmapSubtableLength(data: []const u8, cmap: TableRecord, sub_offset: usize, format: u16) FontError!usize {
    const available = cmap.length - sub_offset;
    const absolute = cmap.offset + sub_offset;
    const length: usize = switch (format) {
        0, 2, 4, 6 => blk: {
            if (available < 4) return error.BadSfnt;
            break :blk try bin.readU16At(data, absolute + 2);
        },
        8, 10, 12, 13 => blk: {
            if (available < 8) return error.BadSfnt;
            break :blk try bin.readU32At(data, absolute + 4);
        },
        14 => blk: {
            if (available < 6) return error.BadSfnt;
            break :blk try bin.readU32At(data, absolute + 2);
        },
        else => available,
    };

    // Cmap offsets are scoped to the declared cmap table, not to the whole
    // SFNT file. Remembering each subtable's own declared length prevents a
    // malformed format 8/10/12/13 table from satisfying its glyph array or group
    // reads with bytes that actually belong to the next SFNT table.
    if (length == 0 or length > available) return error.BadSfnt;
    return length;
}

fn validateCmapSubtable(data: []const u8, offset: usize, length: usize, format: u16, platform_id: u16, encoding_id: u16) FontError!void {
    try validateCmapEncodingCompatibility(platform_id, encoding_id, format);
    const validate_bmp_scalars = cmapSubtableUsesUnicodeScalars(platform_id, encoding_id);
    switch (format) {
        0 => try validateCmapFormat0(length),
        2 => try validateCmapFormat2(data, offset, length),
        6 => try validateCmapFormat6(data, offset, length, validate_bmp_scalars),
        8 => try validateCmapFormat8(data, offset, length),
        10 => try validateCmapFormat10(data, offset, length),
        4 => try validateCmapFormat4(data, offset, length, validate_bmp_scalars),
        12, 13 => try validateSegmentedCmapGroups(data, offset, length),
        14 => try validateCmapFormat14(data, offset, length),
        else => {},
    }
}

fn validateCmapEncodingCompatibility(platform_id: u16, encoding_id: u16, format: u16) FontError!void {
    const valid = switch (platform_id) {
        0 => switch (encoding_id) {
            // Deprecated Unicode encodings are still Unicode character maps, but
            // their historical fonts predate the modern BMP/full-repertoire
            // split. Keep accepting numeric mapping formats while still keeping
            // the format-13/14 special-purpose encodings exclusive below.
            0, 1, 2 => isGeneralCharacterCmapFormat(format),
            3 => isUnicodeBmpCmapFormat(format),
            4 => isUnicodeFullRepertoireCmapFormat(format),
            5 => format == 14,
            6 => format == 13,
            else => false,
        },
        1 => isLegacyByteOrBmpCmapFormat(format),
        2 => encoding_id <= 2 and isGeneralCharacterCmapFormat(format),
        3 => switch (encoding_id) {
            0, 1 => format == 4,
            // Windows CJK code-page cmaps are not Unicode scalar maps; both the
            // mixed-byte format 2 and segmented format 4 encodings are seen in
            // legacy fonts.
            2, 3, 4, 5, 6 => format == 2 or format == 4,
            10 => format == 12,
            else => false,
        },
        // Custom and user-defined platforms can use the ordinary character-code
        // mapping formats, but format 13 and 14 have Unicode-platform-only
        // contracts: last-resort scalar ranges and variation sequences.
        4, 240...255 => isCustomPlatformCmapFormat(format),
        else => false,
    };
    if (!valid) return error.BadSfnt;
}

fn isLegacyByteOrBmpCmapFormat(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6 => true,
        else => false,
    };
}

fn isGeneralCharacterCmapFormat(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6, 8, 10, 12 => true,
        else => false,
    };
}

fn isUnicodeBmpCmapFormat(format: u16) bool {
    return format == 4 or format == 6;
}

fn isUnicodeFullRepertoireCmapFormat(format: u16) bool {
    return format == 8 or format == 10 or format == 12;
}

fn isCustomPlatformCmapFormat(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6, 8, 10, 12 => true,
        else => false,
    };
}

fn cmapSubtableUsesUnicodeScalars(platform_id: u16, encoding_id: u16) bool {
    return switch (platform_id) {
        // The Unicode platform and the Windows Unicode BMP/full-repertoire
        // encodings describe Unicode scalar values. Legacy symbol/code-page
        // cmaps can use the same binary formats for non-Unicode character
        // codes, so surrogate filtering below is only applied to true Unicode
        // encoding records.
        0 => true,
        3 => encoding_id == 1 or encoding_id == 10,
        else => false,
    };
}

fn isUnicodeScalarValue(value: u32) bool {
    return value <= 0x10ffff and !isUnicodeSurrogate(value);
}

fn isUnicodeSurrogate(value: u32) bool {
    return value >= 0xd800 and value <= 0xdfff;
}

fn isUnicodeVariationSelector(value: u32) bool {
    return (value >= 0xfe00 and value <= 0xfe0f) or (value >= 0xe0100 and value <= 0xe01ef);
}

fn validateCmapGlyphIds(data: []const u8, offset: usize, length: usize, format: u16, glyph_count: u16) FontError!void {
    switch (format) {
        0 => {
            try validateCmapFormat0(length);
            for (data[offset + 6 .. offset + 262]) |glyph_id| {
                try validateCmapGlyphId(glyph_id, glyph_count);
            }
        },
        2 => try validateCmapFormat2GlyphIds(data, offset, length, glyph_count),
        4 => try validateCmapFormat4GlyphIds(data, offset, length, glyph_count),
        6 => {
            const entry_count = try bin.readU16At(data, offset + 8);
            for (0..entry_count) |index| {
                try validateCmapGlyphId(try bin.readU16At(data, offset + 10 + index * 2), glyph_count);
            }
        },
        8 => try validateCmapFormat8GlyphIds(data, offset, length, glyph_count),
        10 => {
            const entry_count: usize = @intCast(try bin.readU32At(data, offset + 16));
            for (0..entry_count) |index| {
                try validateCmapGlyphId(try bin.readU16At(data, offset + 20 + index * 2), glyph_count);
            }
        },
        12 => try validateCmapFormat12GlyphIds(data, offset, length, glyph_count),
        13 => try validateCmapFormat13GlyphIds(data, offset, length, glyph_count),
        14 => try validateCmapFormat14GlyphIds(data, offset, length, glyph_count),
        else => {},
    }
}

fn validateCmapGlyphId(glyph_id: u32, glyph_count: u16) FontError!void {
    // cmap data is a cross-table contract: every non-missing mapping names a
    // glyph in the maxp glyph set. Validate the declared mapping space while
    // parsing so later text shaping cannot manufacture out-of-range glyph ids
    // that fail only when metrics or outlines are requested.
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

fn addU16Wrapping(value: u16, delta: i16) u16 {
    return @as(u16, @bitCast(@as(i16, @bitCast(value)) +% delta));
}

fn validateCmapFormat2GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) FontError!void {
    const table_end = offset + length;
    var max_subheader_index: u16 = 0;
    for (0..256) |high_byte| {
        const key = try bin.readU16At(data, offset + 6 + high_byte * 2);
        max_subheader_index = @max(max_subheader_index, key / 8);
    }

    const subheaders_offset = offset + 6 + 512;
    for (0..@as(usize, max_subheader_index) + 1) |subheader_index| {
        const subheader_offset = subheaders_offset + subheader_index * 8;
        const entry_count = try bin.readU16At(data, subheader_offset + 2);
        const id_delta = try bin.readI16At(data, subheader_offset + 4);
        const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
        for (0..entry_count) |entry_index| {
            const glyph_offset = subheader_offset + 6 + @as(usize, id_range_offset) + entry_index * 2;
            if (glyph_offset + 2 > table_end) return error.BadSfnt;
            const raw_glyph = try bin.readU16At(data, glyph_offset);
            if (raw_glyph == 0) continue;
            try validateCmapGlyphId(addU16Wrapping(raw_glyph, id_delta), glyph_count);
        }
    }
}

fn validateCmapFormat4GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) FontError!void {
    const table_end = offset + length;
    const seg_count = @as(usize, try bin.readU16At(data, offset + 6) / 2);
    const end_codes = offset + 14;
    const start_codes = end_codes + seg_count * 2 + 2;
    const id_deltas = start_codes + seg_count * 2;
    const id_range_offsets = id_deltas + seg_count * 2;

    for (0..seg_count) |segment_index| {
        const start = try bin.readU16At(data, start_codes + segment_index * 2);
        const end = try bin.readU16At(data, end_codes + segment_index * 2);
        const delta = try bin.readI16At(data, id_deltas + segment_index * 2);
        const range_offset = try bin.readU16At(data, id_range_offsets + segment_index * 2);
        var codepoint = start;
        while (true) : (codepoint +%= 1) {
            const glyph_id = if (range_offset == 0) blk: {
                break :blk addU16Wrapping(codepoint, delta);
            } else blk: {
                const glyph_offset = id_range_offsets + segment_index * 2 + @as(usize, range_offset) + (@as(usize, codepoint - start) * 2);
                if (glyph_offset + 2 > table_end) return error.BadSfnt;
                const raw_glyph = try bin.readU16At(data, glyph_offset);
                if (raw_glyph == 0) {
                    if (codepoint == end) break;
                    continue;
                }
                break :blk addU16Wrapping(raw_glyph, delta);
            };
            try validateCmapGlyphId(glyph_id, glyph_count);
            if (codepoint == end) break;
        }
    }
}

fn validateCmapFormat8GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) FontError!void {
    const group_count: usize = @intCast(try bin.readU32At(data, offset + cmap_format8_groups_offset - 4));
    _ = length;
    for (0..group_count) |index| {
        const group_offset = offset + cmap_format8_groups_offset + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        const first_glyph = try bin.readU32At(data, group_offset + 8);
        const span = end - start;
        if (first_glyph > std.math.maxInt(u32) - span) return error.BadSfnt;
        try validateCmapGlyphId(first_glyph + span, glyph_count);
    }
}

fn validateCmapFormat12GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) FontError!void {
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    _ = length;
    for (0..group_count) |index| {
        const group_offset = offset + 16 + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        const first_glyph = try bin.readU32At(data, group_offset + 8);
        const span = end - start;
        if (first_glyph > std.math.maxInt(u32) - span) return error.BadSfnt;
        try validateCmapGlyphId(first_glyph + span, glyph_count);
    }
}

fn validateCmapFormat13GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) FontError!void {
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    _ = length;
    for (0..group_count) |index| {
        const glyph_id = try bin.readU32At(data, offset + 16 + index * 12 + 8);
        try validateCmapGlyphId(glyph_id, glyph_count);
    }
}

fn validateCmapFormat14GlyphIds(data: []const u8, offset: usize, length: usize, glyph_count: u16) FontError!void {
    const record_count: usize = @intCast(try bin.readU32At(data, offset + 6));
    const table_end = offset + length;
    for (0..record_count) |record_index| {
        const record = offset + 10 + record_index * 11;
        const non_default_offset = try bin.readU32At(data, record + 7);
        if (non_default_offset == 0) continue;
        const mappings_offset = offset + @as(usize, non_default_offset);
        const mapping_count: usize = @intCast(try bin.readU32At(data, mappings_offset));
        if (mapping_count > (table_end - (mappings_offset + 4)) / 5) return error.BadSfnt;
        for (0..mapping_count) |mapping_index| {
            try validateCmapGlyphId(try bin.readU16At(data, mappings_offset + 4 + mapping_index * 5 + 3), glyph_count);
        }
    }
}

fn validateCmapFormat0(length: usize) FontError!void {
    // Format 0 has exactly 256 one-byte glyph entries after its six-byte
    // header. Treat the length as a fixed structural contract rather than a
    // minimum so trailing bytes cannot be hidden inside a subtable that later
    // EncodingRecords may also try to interpret.
    if (length != 262) return error.BadSfnt;
}

fn validateCmapFormat2(data: []const u8, offset: usize, length: usize) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 526) return error.BadSfnt;

    const table_end = offset + length;
    var max_subheader_index: u16 = 0;
    for (0..256) |high_byte| {
        const key = try bin.readU16At(data, offset + 6 + high_byte * 2);
        // SubHeaderKeys are byte offsets divided by the fixed eight-byte
        // SubHeader size. Requiring alignment at parse time prevents lookup
        // from interpreting the middle of one SubHeader as another.
        if ((key & 7) != 0) return error.BadSfnt;
        max_subheader_index = @max(max_subheader_index, key / 8);
    }

    const subheaders_offset = offset + 6 + 512;
    const subheaders_len = (@as(usize, max_subheader_index) + 1) * 8;
    if (subheaders_len > table_end - subheaders_offset) return error.BadSfnt;
    const glyph_array_start = subheaders_offset + subheaders_len;

    for (0..@as(usize, max_subheader_index) + 1) |subheader_index| {
        const subheader_offset = subheaders_offset + subheader_index * 8;
        const first_code = try bin.readU16At(data, subheader_offset);
        const entry_count = try bin.readU16At(data, subheader_offset + 2);
        _ = try bin.readI16At(data, subheader_offset + 4);
        const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
        if (entry_count == 0) continue;

        const last_entry_index = @as(usize, entry_count) - 1;
        if (@as(usize, first_code) + last_entry_index > 0xff) return error.BadSfnt;
        if ((id_range_offset & 1) != 0) return error.BadSfnt;
        const first_glyph = subheader_offset + 6 + @as(usize, id_range_offset);
        const last_glyph = first_glyph + last_entry_index * 2;
        // idRangeOffset is relative to its own word. The glyph index array is
        // conceptually after the declared SubHeader array, so disallow offsets
        // that point back into SubHeader metadata or beyond the declared cmap.
        if (first_glyph < glyph_array_start or last_glyph > table_end or table_end - last_glyph < 2) return error.BadSfnt;
    }
}

fn validateCmapFormat6(data: []const u8, offset: usize, length: usize, validate_unicode_scalars: bool) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 10) return error.BadSfnt;
    const first_code = try bin.readU16At(data, offset + 6);
    const entry_count = try bin.readU16At(data, offset + 8);
    if (@as(usize, entry_count) * 2 != length - 10) return error.BadSfnt;
    if (entry_count != 0) {
        const last_code = @as(u32, first_code) + @as(u32, entry_count) - 1;
        if (last_code > std.math.maxInt(u16)) return error.BadSfnt;
        if (validate_unicode_scalars) {
            if (!isUnicodeScalarValue(first_code) or !isUnicodeScalarValue(last_code)) return error.BadSfnt;
            if (first_code < 0xe000 and last_code > 0xd7ff) return error.BadSfnt;
        }
    }
}

const cmap_format8_is32_offset = 12;
const cmap_format8_is32_len = 8192;
const cmap_format8_groups_offset = cmap_format8_is32_offset + cmap_format8_is32_len + 4;

fn validateCmapFormat8(data: []const u8, offset: usize, length: usize) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < cmap_format8_groups_offset) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const group_bytes = length - cmap_format8_groups_offset;
    if (group_bytes % 12 != 0) return error.BadSfnt;
    const group_count: usize = @intCast(try bin.readU32At(data, offset + cmap_format8_groups_offset - 4));
    if (group_count != group_bytes / 12) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..group_count) |index| {
        const group_offset = offset + cmap_format8_groups_offset + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (!isUnicodeScalarValue(start) or !isUnicodeScalarValue(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            // Format 8 lookups use the same sorted group search as format 12,
            // with an additional is32 bitset to identify UTF-16 high words.
            // Enforce ordering at parse time so malformed group arrays cannot
            // make scalar-to-glyph mapping depend on record order.
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;

        try validateCmapFormat8RangeWidth(data, offset, start, end);
    }
}

fn validateExtendedCmapReservedField(data: []const u8, offset: usize) FontError!void {
    // Extended cmap formats 8/10/12/13 all reserve the UInt16 field after the
    // format word. Keep it zero so a malformed table cannot advertise a
    // private variant while being interpreted by the standard parser.
    if (try bin.readU16At(data, offset + 2) != 0) return error.BadSfnt;
}

fn validateCmapFormat8RangeWidth(data: []const u8, offset: usize, start: u32, end: u32) FontError!void {
    // The is32 bitset is part of format 8's decoding contract, not merely a
    // hint. A BMP codepoint named by a group must be marked as a standalone
    // 16-bit character, while every high word used by supplementary-plane
    // groups must be marked as the first half of a 32-bit character code.
    if (start <= 0xffff) {
        var word = start;
        const last_bmp = @min(end, 0xffff);
        while (word <= last_bmp) : (word += 1) {
            if (cmapFormat8Is32(data, offset, @intCast(word))) return error.BadSfnt;
        }
    }
    if (end > 0xffff) {
        var high_word = @max(start, 0x10000) >> 16;
        const last_high_word = end >> 16;
        while (high_word <= last_high_word) : (high_word += 1) {
            if (!cmapFormat8Is32(data, offset, @intCast(high_word))) return error.BadSfnt;
        }
    }
}

fn cmapFormat8Is32(data: []const u8, offset: usize, word: u16) bool {
    const byte_offset = offset + cmap_format8_is32_offset + @as(usize, word) / 8;
    const bit_mask: u8 = @as(u8, 0x80) >> @intCast(word & 7);
    return (data[byte_offset] & bit_mask) != 0;
}

fn validateCmapFormat10(data: []const u8, offset: usize, length: usize) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 20) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const start_code = try bin.readU32At(data, offset + 12);
    if (!isUnicodeScalarValue(start_code)) return error.BadSfnt;
    const num_chars = try bin.readU32At(data, offset + 16);
    if (@as(u64, num_chars) * 2 != @as(u64, length - 20)) return error.BadSfnt;
    if (num_chars == 0) return;
    const last_code = @as(u64, start_code) + @as(u64, num_chars) - 1;
    if (last_code > std.math.maxInt(u32)) return error.BadSfnt;
    const last_scalar: u32 = @intCast(last_code);
    if (!isUnicodeScalarValue(last_scalar)) return error.BadSfnt;
    if (start_code < 0xe000 and last_scalar > 0xd7ff) return error.BadSfnt;
}

fn validateCmapFormat4(data: []const u8, offset: usize, length: usize, validate_unicode_scalars: bool) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    const seg_count_x2 = try bin.readU16At(data, offset + 6);
    if (seg_count_x2 == 0 or (seg_count_x2 & 1) != 0) return error.BadSfnt;
    const seg_count = @as(usize, seg_count_x2 / 2);
    const minimum_length = 16 + seg_count * 8;
    if (length < minimum_length) return error.BadSfnt;

    const table_end = offset + length;
    const end_codes = offset + 14;
    const reserved_pad = end_codes + seg_count * 2;
    const start_codes = reserved_pad + 2;
    const id_deltas = start_codes + seg_count * 2;
    const id_range_offsets = id_deltas + seg_count * 2;
    const glyph_array_start = id_range_offsets + seg_count * 2;
    if (try bin.readU16At(data, reserved_pad) != 0) return error.BadSfnt;

    var previous_end: ?u16 = null;
    for (0..seg_count) |index| {
        const start = try bin.readU16At(data, start_codes + index * 2);
        const end = try bin.readU16At(data, end_codes + index * 2);
        if (end < start) return error.BadSfnt;
        if (validate_unicode_scalars and (isUnicodeSurrogate(start) or isUnicodeSurrogate(end) or (start < 0xe000 and end > 0xd7ff))) return error.BadSfnt;
        if (previous_end) |last_end| {
            // Format 4 is searched as an ordered segment array. Reject
            // overlapping or out-of-order records at cmap parse time so glyph
            // lookup cannot become dependent on malformed directory order.
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;

        const range_offset = try bin.readU16At(data, id_range_offsets + index * 2);
        if (range_offset != 0) {
            if ((range_offset & 1) != 0) return error.BadSfnt;
            const first_glyph = id_range_offsets + index * 2 + @as(usize, range_offset);
            const last_delta = @as(usize, end) - @as(usize, start);
            const last_glyph = first_glyph + last_delta * 2;
            // Validate the full declared segment, not just the character a
            // future lookup happens to ask for. Otherwise a malformed cmap can
            // look fine for early codepoints while later codepoints read past
            // the subtable into the next SFNT table.
            if (first_glyph < glyph_array_start or last_glyph > table_end or table_end - last_glyph < 2) return error.BadSfnt;
        }
    }

    // OpenType format 4 requires a terminal 0xffff segment. The lookup loop
    // uses the first segment whose endCode is >= the requested scalar; without
    // the sentinel, malformed BMP subtables can stop early and hide later
    // invalid segment data.
    if (previous_end != 0xffff) return error.BadSfnt;
}

fn validateSegmentedCmapGroups(data: []const u8, offset: usize, length: usize) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    if (group_count > (length - 16) / 12) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..group_count) |index| {
        const group_offset = offset + 16 + index * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (!isUnicodeScalarValue(start) or !isUnicodeScalarValue(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            // Format 12/13 group arrays are searched as sorted, disjoint
            // intervals. Rejecting overlap and out-of-order starts at parse
            // time keeps malformed cmap data from producing order-dependent
            // glyph mappings later.
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;
    }
}

fn validateCmapFormat14(data: []const u8, offset: usize, length: usize) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 10) return error.BadSfnt;
    const record_count: usize = @intCast(try bin.readU32At(data, offset + 6));
    const records_end = try cmapFormat14RecordsEnd(length, record_count);

    const table_end = offset + length;
    var previous_selector: ?u32 = null;
    for (0..record_count) |index| {
        const record = offset + 10 + index * 11;
        const selector = try readU24At(data, record);
        if (!isUnicodeVariationSelector(selector)) return error.BadSfnt;
        if (previous_selector) |last_selector| {
            // Variation selector records are consumed with an early-exit search
            // in glyphIndexFormat14. Reject unsorted/duplicate selectors here
            // so malformed cmaps cannot make mappings depend on record order.
            if (selector <= last_selector) return error.BadSfnt;
        }
        previous_selector = selector;

        const default_offset = try bin.readU32At(data, record + 3);
        const non_default_offset = try bin.readU32At(data, record + 7);
        if (default_offset != 0) {
            const default_payload_offset = try validateCmapFormat14PayloadOffset(default_offset, records_end, length);
            const default_absolute = offset + default_payload_offset;
            const default_range = try cmapFormat14DefaultUvsRange(data, default_absolute, table_end);
            try validateCmapFormat14DefaultUvs(data, default_absolute, table_end);
            try validateCmapFormat14UvsRangeDoesNotAliasRecords(
                data,
                offset,
                table_end,
                index,
                default_range,
            );
        }
        if (non_default_offset != 0) {
            const non_default_payload_offset = try validateCmapFormat14PayloadOffset(non_default_offset, records_end, length);
            const non_default_absolute = offset + non_default_payload_offset;
            const non_default_range = try cmapFormat14NonDefaultUvsRange(data, non_default_absolute, table_end);
            try validateCmapFormat14NonDefaultUvs(data, non_default_absolute, table_end);
            try validateCmapFormat14UvsRangeDoesNotAliasRecords(
                data,
                offset,
                table_end,
                index,
                non_default_range,
            );
        }
        if (default_offset != 0 and non_default_offset != 0) {
            const default_absolute = offset + try validateCmapFormat14PayloadOffset(default_offset, records_end, length);
            const non_default_absolute = offset + try validateCmapFormat14PayloadOffset(non_default_offset, records_end, length);
            const default_range = try cmapFormat14DefaultUvsRange(data, default_absolute, table_end);
            const non_default_range = try cmapFormat14NonDefaultUvsRange(data, non_default_absolute, table_end);
            if (payloadRangesOverlap(default_range, non_default_range)) return error.BadSfnt;
            try validateCmapFormat14UvsSetsDisjoint(
                data,
                default_absolute,
                non_default_absolute,
                table_end,
            );
        }
    }
}

const CmapFormat14PayloadRange = struct {
    start: usize,
    end: usize,
};

fn cmapFormat14RecordsEnd(length: usize, record_count: usize) FontError!usize {
    if (length < 10) return error.BadSfnt;
    if (record_count > (length - 10) / 11) return error.BadSfnt;
    return 10 + record_count * 11;
}

fn validateCmapFormat14PayloadOffset(payload_offset: u32, records_end: usize, length: usize) FontError!usize {
    const offset: usize = @intCast(payload_offset);
    // A non-zero UVS payload offset must name a child array after the complete
    // VariationSelectorRecord directory. Keeping this check in one helper lets
    // both parse-time validation and lazy lookup reject record-directory aliases
    // with the same boundary contract.
    if (offset < records_end or offset >= length) return error.BadSfnt;
    return offset;
}

fn cmapFormat14DefaultUvsRange(data: []const u8, offset: usize, table_end: usize) FontError!CmapFormat14PayloadRange {
    if (offset + 4 > table_end) return error.BadSfnt;
    const range_count: usize = @intCast(try bin.readU32At(data, offset));
    if (range_count > (table_end - (offset + 4)) / 4) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + range_count * 4 };
}

fn cmapFormat14NonDefaultUvsRange(data: []const u8, offset: usize, table_end: usize) FontError!CmapFormat14PayloadRange {
    if (offset + 4 > table_end) return error.BadSfnt;
    const mapping_count: usize = @intCast(try bin.readU32At(data, offset));
    if (mapping_count > (table_end - (offset + 4)) / 5) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + mapping_count * 5 };
}

fn payloadRangesOverlap(a: CmapFormat14PayloadRange, b: CmapFormat14PayloadRange) bool {
    return a.start < b.end and b.start < a.end;
}

fn validateCmapFormat14UvsRangeDoesNotAliasRecords(
    data: []const u8,
    cmap_offset: usize,
    table_end: usize,
    current_record_index: usize,
    candidate: CmapFormat14PayloadRange,
) FontError!void {
    // Each format-14 UVS array is a variable-length child table. Offsets that
    // point into another selector's child payload make two records share bytes
    // with incompatible ownership, so a later edit to one selector can silently
    // reinterpret the other's Unicode ranges or glyph IDs. Reject aliasing at
    // parse time, while still permitting adjacent payloads.
    for (0..current_record_index) |previous_index| {
        const previous_record = cmap_offset + 10 + previous_index * 11;
        const previous_default_offset = try bin.readU32At(data, previous_record + 3);
        if (previous_default_offset != 0) {
            const previous_range = try cmapFormat14DefaultUvsRange(
                data,
                cmap_offset + @as(usize, previous_default_offset),
                table_end,
            );
            if (payloadRangesOverlap(candidate, previous_range)) return error.BadSfnt;
        }

        const previous_non_default_offset = try bin.readU32At(data, previous_record + 7);
        if (previous_non_default_offset != 0) {
            const previous_range = try cmapFormat14NonDefaultUvsRange(
                data,
                cmap_offset + @as(usize, previous_non_default_offset),
                table_end,
            );
            if (payloadRangesOverlap(candidate, previous_range)) return error.BadSfnt;
        }
    }
}

fn validateCmapFormat14DefaultUvs(data: []const u8, offset: usize, table_end: usize) FontError!void {
    if (offset + 4 > table_end) return error.BadSfnt;
    const range_count: usize = @intCast(try bin.readU32At(data, offset));
    if (range_count > (table_end - (offset + 4)) / 4) return error.BadSfnt;

    var previous_end: ?u32 = null;
    for (0..range_count) |index| {
        const range = offset + 4 + index * 4;
        const start = try readU24At(data, range);
        if (!isUnicodeScalarValue(start)) return error.BadSfnt;
        const end_u64 = @as(u64, start) + data[range + 3];
        if (end_u64 > 0x10ffff) return error.BadSfnt;
        const end: u32 = @intCast(end_u64);
        if (!isUnicodeScalarValue(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;
    }
}

fn validateCmapFormat14NonDefaultUvs(data: []const u8, offset: usize, table_end: usize) FontError!void {
    if (offset + 4 > table_end) return error.BadSfnt;
    const mapping_count: usize = @intCast(try bin.readU32At(data, offset));
    if (mapping_count > (table_end - (offset + 4)) / 5) return error.BadSfnt;

    var previous_unicode: ?u32 = null;
    for (0..mapping_count) |index| {
        const mapping = offset + 4 + index * 5;
        const unicode_value = try readU24At(data, mapping);
        if (!isUnicodeScalarValue(unicode_value)) return error.BadSfnt;
        if (previous_unicode) |last_unicode| {
            if (unicode_value <= last_unicode) return error.BadSfnt;
        }
        previous_unicode = unicode_value;
    }
}

fn validateCmapFormat14UvsSetsDisjoint(data: []const u8, default_offset: usize, non_default_offset: usize, table_end: usize) FontError!void {
    const default_count: usize = @intCast(try bin.readU32At(data, default_offset));
    const non_default_count: usize = @intCast(try bin.readU32At(data, non_default_offset));
    if (default_count > (table_end - (default_offset + 4)) / 4) return error.BadSfnt;
    if (non_default_count > (table_end - (non_default_offset + 4)) / 5) return error.BadSfnt;

    // A Unicode variation sequence is either default (use the base cmap glyph)
    // or non-default (use the explicit UVS glyph), never both for the same
    // selector. The two arrays are already validated as sorted, so a linear
    // merge detects contradictory records without allocating per-selector side
    // tables even for large CJK variation maps.
    var default_index: usize = 0;
    for (0..non_default_count) |mapping_index| {
        const mapping = non_default_offset + 4 + mapping_index * 5;
        const unicode_value = try readU24At(data, mapping);

        while (default_index < default_count) {
            const range = default_offset + 4 + default_index * 4;
            const start = try readU24At(data, range);
            const end = start + data[range + 3];
            if (end >= unicode_value) break;
            default_index += 1;
        }
        if (default_index < default_count) {
            const range = default_offset + 4 + default_index * 4;
            const start = try readU24At(data, range);
            const end = start + data[range + 3];
            if (unicode_value >= start and unicode_value <= end) return error.BadSfnt;
        }
    }
}

fn classDefValue(data: []const u8, offset: usize, glyph_id: glyph_mod.GlyphId) FontError!u16 {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 6 > data.len) return error.BadSfnt;
            const start_glyph = try bin.readU16At(data, offset + 2);
            const glyph_count = try bin.readU16At(data, offset + 4);
            if (@as(usize, glyph_count) * 2 > data.len - (offset + 6)) return error.BadSfnt;
            // ClassDef format 1 covers `glyph_count` glyph IDs starting at
            // `startGlyphID`. GDEF tables often use the same ClassDef shape as
            // GSUB/GPOS; validate the full declared class array and keep the
            // boundary arithmetic widened so edge ranges near 0xffff do not
            // overflow before validation can run.
            const glyph_index = @as(usize, glyph_id);
            const start_index = @as(usize, start_glyph);
            const end_exclusive = start_index + @as(usize, glyph_count);
            if (glyph_index < start_index or glyph_index >= end_exclusive) return 0;
            const class_offset = offset + 6 + (glyph_index - start_index) * 2;
            if (class_offset + 2 > data.len) return error.BadSfnt;
            return try bin.readU16At(data, class_offset);
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
            try validateClassDefFormat2Ranges(data, offset, range_count);
            for (0..range_count) |index| {
                const range_offset = offset + 4 + index * 6;
                const start = try bin.readU16At(data, range_offset);
                const end = try bin.readU16At(data, range_offset + 2);
                const class = try bin.readU16At(data, range_offset + 4);
                if (glyph_id >= start and glyph_id <= end) return class;
            }
            return 0;
        },
        else => return error.BadSfnt,
    }
}

fn validateClassDefFormat2Ranges(data: []const u8, offset: usize, range_count: u16) FontError!void {
    // OpenType ClassDef format 2 records are sorted by StartGlyphID and must not
    // overlap. GDEF class data feeds lookup-flag filtering, so accepting
    // overlapping/reversed ranges can misclassify glyphs before GSUB/GPOS even
    // see the run.
    var previous_end: ?glyph_mod.GlyphId = null;
    for (0..range_count) |index| {
        const range_offset = offset + 4 + index * 6;
        const start = try bin.readU16At(data, range_offset);
        const end = try bin.readU16At(data, range_offset + 2);
        if (end < start) return error.BadSfnt;
        if (previous_end) |last_end| {
            if (start <= last_end) return error.BadSfnt;
        }
        previous_end = end;
    }
}

fn validateGdefTable(data: []const u8, gdef: TableRecord, glyph_count: u16) FontError!void {
    if (gdef.length < 12) return error.BadSfnt;
    const table = data[gdef.offset .. gdef.offset + gdef.length];
    const major = try bin.readU16At(table, 0);
    const minor = try bin.readU16At(table, 2);
    if (major != 1) return error.BadSfnt;

    const header_len = minimumGdefHeaderLength(minor);
    if (gdef.length < header_len) return error.BadSfnt;

    const glyph_class_def_offset = try bin.readU16At(table, 4);
    const attach_list_offset = try bin.readU16At(table, 6);
    const lig_caret_list_offset = try bin.readU16At(table, 8);
    const mark_attach_class_def_offset = try bin.readU16At(table, 10);
    if (glyph_class_def_offset != 0) {
        try validateGdefChildOffset(glyph_class_def_offset, gdef.length, header_len);
        try validateClassDefGlyphBounds(table, glyph_class_def_offset, glyph_count);
    }
    if (attach_list_offset != 0) try validateGdefChildOffset(attach_list_offset, gdef.length, header_len);
    if (lig_caret_list_offset != 0) try validateGdefChildOffset(lig_caret_list_offset, gdef.length, header_len);
    if (mark_attach_class_def_offset != 0) {
        try validateGdefChildOffset(mark_attach_class_def_offset, gdef.length, header_len);
        try validateClassDefGlyphBounds(table, mark_attach_class_def_offset, glyph_count);
    }

    if (minor >= 2) {
        const mark_glyph_sets_def_offset = try bin.readU16At(table, 12);
        if (mark_glyph_sets_def_offset != 0) {
            try validateGdefChildOffset(mark_glyph_sets_def_offset, gdef.length, header_len);
            try validateMarkGlyphSetsDefGlyphBounds(table, mark_glyph_sets_def_offset, glyph_count);
        }
    }
    if (minor >= 3) {
        const item_var_store_offset: usize = @intCast(try bin.readU32At(table, 14));
        if (item_var_store_offset != 0) try validateGdefChildOffset(item_var_store_offset, gdef.length, header_len);
    }
}

fn minimumGdefHeaderLength(minor: u16) usize {
    return if (minor >= 3) 18 else if (minor >= 2) 14 else 12;
}

fn validateGdefChildOffset(offset: usize, table_len: usize, header_len: usize) FontError!void {
    // GDEF top-level offsets are relative to the GDEF table and name child
    // subtables, not bytes inside the versioned header.  Keeping them past the
    // header prevents a malformed table from reinterpreting offset fields as a
    // ClassDef or Coverage payload during lookup-flag filtering.
    if (offset < header_len or offset >= table_len) return error.BadSfnt;
}

fn validateClassDefGlyphBounds(data: []const u8, offset: usize, glyph_count: u16) FontError!void {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 6 > data.len) return error.BadSfnt;
            const start_glyph = try bin.readU16At(data, offset + 2);
            const count = try bin.readU16At(data, offset + 4);
            if (@as(usize, count) * 2 > data.len - (offset + 6)) return error.BadSfnt;
            if (count == 0) return;
            if (start_glyph >= glyph_count) return error.BadSfnt;
            if (@as(usize, count) > @as(usize, glyph_count - start_glyph)) return error.BadSfnt;
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
            try validateClassDefFormat2Ranges(data, offset, range_count);
            for (0..range_count) |index| {
                const range_offset = offset + 4 + index * 6;
                const end = try bin.readU16At(data, range_offset + 2);
                if (end >= glyph_count) return error.BadSfnt;
            }
        },
        else => return error.BadSfnt,
    }
}

fn validateMarkGlyphSetsDefGlyphBounds(data: []const u8, offset: usize, glyph_count: u16) FontError!void {
    if (offset + 4 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    if (format != 1) return error.BadSfnt;
    const set_count = try bin.readU16At(data, offset + 2);
    if (@as(usize, set_count) * 4 > data.len - (offset + 4)) return error.BadSfnt;
    const coverage_data_start = 4 + @as(usize, set_count) * 4;
    for (0..set_count) |index| {
        const coverage_relative = try bin.readU32At(data, offset + 4 + index * 4);
        if (coverage_relative < coverage_data_start) return error.BadSfnt;
        if (coverage_relative > data.len - offset) return error.BadSfnt;
        try validateCoverageGlyphBounds(data, offset + coverage_relative, glyph_count);
    }
}

fn validateCoverageGlyphBounds(data: []const u8, offset: usize, glyph_count: u16) FontError!void {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const count = try bin.readU16At(data, offset + 2);
            if (@as(usize, count) * 2 > data.len - (offset + 4)) return error.BadSfnt;
            var previous: ?glyph_mod.GlyphId = null;
            for (0..count) |index| {
                const glyph_id = try bin.readU16At(data, offset + 4 + index * 2);
                if (previous) |last| {
                    if (glyph_id <= last) return error.BadSfnt;
                }
                if (glyph_id >= glyph_count) return error.BadSfnt;
                previous = glyph_id;
            }
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
            var previous_end: ?glyph_mod.GlyphId = null;
            for (0..range_count) |index| {
                const range_offset = offset + 4 + index * 6;
                const start = try bin.readU16At(data, range_offset);
                const end = try bin.readU16At(data, range_offset + 2);
                if (end < start) return error.BadSfnt;
                if (previous_end) |last_end| {
                    if (start <= last_end) return error.BadSfnt;
                }
                if (end >= glyph_count) return error.BadSfnt;
                previous_end = end;
            }
        },
        else => return error.BadSfnt,
    }
}

fn readMarkGlyphSetsDef(allocator: std.mem.Allocator, data: []const u8, offset: usize) FontError![][]glyph_mod.GlyphId {
    if (offset + 4 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    if (format != 1) return error.BadSfnt;
    const set_count = try bin.readU16At(data, offset + 2);
    if (@as(usize, set_count) * 4 > data.len - (offset + 4)) return error.BadSfnt;
    const coverage_data_start = 4 + @as(usize, set_count) * 4;

    const sets = try allocator.alloc([]glyph_mod.GlyphId, set_count);
    errdefer allocator.free(sets);
    var initialized: usize = 0;
    errdefer {
        for (sets[0..initialized]) |set| allocator.free(set);
    }

    for (sets, 0..) |*set, index| {
        const coverage_relative = try bin.readU32At(data, offset + 4 + index * 4);
        // Coverage offsets are relative to the MarkGlyphSetsDef table. Require
        // every child Coverage table to start after the declared offset array so
        // malformed GDEF data cannot reinterpret the MarkGlyphSetsDef header or
        // sibling offset entries as a synthetic glyph set.
        if (coverage_relative < coverage_data_start) return error.BadSfnt;
        if (coverage_relative > data.len - offset) return error.BadSfnt;
        set.* = try coverageGlyphs(allocator, data, offset + coverage_relative);
        initialized += 1;
    }
    return sets;
}

fn coverageGlyphs(allocator: std.mem.Allocator, data: []const u8, offset: usize) FontError![]glyph_mod.GlyphId {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const glyph_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, glyph_count) * 2 > data.len - (offset + 4)) return error.BadSfnt;
            const glyphs = try allocator.alloc(glyph_mod.GlyphId, glyph_count);
            errdefer allocator.free(glyphs);
            var previous: ?glyph_mod.GlyphId = null;
            for (glyphs, 0..) |*glyph, index| {
                const glyph_id = try bin.readU16At(data, offset + 4 + index * 2);
                if (previous) |last| {
                    if (glyph_id <= last) return error.BadSfnt;
                }
                previous = glyph_id;
                glyph.* = glyph_id;
            }
            return glyphs;
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
            var glyph_total: usize = 0;
            var previous_end: ?glyph_mod.GlyphId = null;
            for (0..range_count) |index| {
                const range_offset = offset + 4 + index * 6;
                const start = try bin.readU16At(data, range_offset);
                const end = try bin.readU16At(data, range_offset + 2);
                if (end < start) return error.BadSfnt;
                if (previous_end) |last_end| {
                    if (start <= last_end) return error.BadSfnt;
                }
                previous_end = end;
                glyph_total += @as(usize, end) - @as(usize, start) + 1;
            }

            const glyphs = try allocator.alloc(glyph_mod.GlyphId, glyph_total);
            errdefer allocator.free(glyphs);
            var out: usize = 0;
            for (0..range_count) |index| {
                const range_offset = offset + 4 + index * 6;
                const start = try bin.readU16At(data, range_offset);
                const end = try bin.readU16At(data, range_offset + 2);
                for (start..@as(usize, end) + 1) |glyph| {
                    glyphs[out] = @intCast(glyph);
                    out += 1;
                }
            }
            return glyphs;
        },
        else => return error.BadSfnt,
    }
}

fn freeMarkFilteringSets(allocator: std.mem.Allocator, sets: [][]glyph_mod.GlyphId) void {
    for (sets) |set| allocator.free(set);
    allocator.free(sets);
}

const NameRecord = struct {
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    offset: usize,
    length: usize,
};

const NameTableLayout = struct {
    format: u16,
    count: u16,
    storage_offset: usize,
    storage_length: usize,
    lang_tag_records_start: usize = 0,
    lang_tag_count: usize = 0,
};

const name_records_start: usize = 6;
const name_record_size: usize = 12;
const lang_tag_record_size: usize = 4;

fn validateNameTable(data: []const u8, name: TableRecord) FontError!void {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    for (0..layout.count) |index| {
        const record = try readNameRecord(table, index);
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data);
    }
}

/// Compact index of name IDs that have at least one structurally valid string.
/// fvar and STAT do not identify a platform/language-specific record; they
/// reference a name ID and let normal name-table fallback choose the localized
/// string later. Tracking only IDs mirrors that contract while still forcing
/// all referenced user-facing metadata to be present and decodable.
const NameIdIndex = struct {
    words: [1024]u64 = .{0} ** 1024,

    fn add(self: *NameIdIndex, name_id: u16) void {
        const word_index = @as(usize, name_id) / 64;
        const bit_index: u6 = @intCast(name_id & 63);
        self.words[word_index] |= @as(u64, 1) << bit_index;
    }

    fn contains(self: *const NameIdIndex, name_id: u16) bool {
        const word_index = @as(usize, name_id) / 64;
        const bit_index: u6 = @intCast(name_id & 63);
        return (self.words[word_index] & (@as(u64, 1) << bit_index)) != 0;
    }
};

fn readNameIdIndex(data: []const u8, name: TableRecord) FontError!NameIdIndex {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    // Variation metadata may reference many name IDs across fvar instances and
    // STAT AxisValue records. Index the already-validated records once so
    // cross-table checks are deterministic without repeatedly reparsing `name`.
    var index = NameIdIndex{};
    for (0..layout.count) |record_index| {
        const record = try readNameRecord(table, record_index);
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data);
        index.add(record.name_id);
    }
    return index;
}

fn validateNameIdReference(name_index: ?*const NameIdIndex, name_id: u16) FontError!void {
    const index = name_index orelse return error.InvalidName;
    if (!index.contains(name_id)) return error.InvalidName;
}

fn validateOptionalNameIdReference(name_index: ?*const NameIdIndex, name_id: u16) FontError!void {
    if (name_id == 0xffff) return;
    try validateNameIdReference(name_index, name_id);
}

fn nameTableSlice(data: []const u8, name: TableRecord) FontError![]const u8 {
    if (name.offset > data.len or name.length > data.len - name.offset) return error.BadSfnt;
    return data[name.offset .. name.offset + name.length];
}

fn readNameTableLayout(table: []const u8) FontError!NameTableLayout {
    if (table.len < 6) return error.BadSfnt;
    const format = try bin.readU16At(table, 0);
    if (format > 1) return error.InvalidName;
    const count = try bin.readU16At(table, 2);
    const storage_offset: usize = @intCast(try bin.readU16At(table, 4));

    if (@as(usize, count) > (table.len - name_records_start) / name_record_size) return error.BadSfnt;
    const records_len = @as(usize, count) * name_record_size;
    const records_end = name_records_start + records_len;

    // name.stringOffset is relative to the name table and denotes the first
    // byte of shared string storage. It must sit after every versioned metadata
    // record, otherwise a malicious NameRecord or LangTagRecord can reinterpret
    // table headers as a plausible UTF-16 string.
    var minimum_storage_offset = records_end;
    var layout = NameTableLayout{
        .format = format,
        .count = count,
        .storage_offset = storage_offset,
        .storage_length = 0,
    };
    if (format == 1) {
        if (records_end + 2 > table.len) return error.BadSfnt;
        const lang_tag_count: usize = @intCast(try bin.readU16At(table, records_end));
        const lang_tag_records_start = records_end + 2;
        if (lang_tag_count > (table.len - lang_tag_records_start) / lang_tag_record_size) return error.BadSfnt;
        minimum_storage_offset = lang_tag_records_start + lang_tag_count * lang_tag_record_size;
        layout.lang_tag_records_start = lang_tag_records_start;
        layout.lang_tag_count = lang_tag_count;
    }
    if (storage_offset < minimum_storage_offset or storage_offset > table.len) return error.BadSfnt;
    layout.storage_length = table.len - storage_offset;
    return layout;
}

fn validateNameLanguageTags(table: []const u8, layout: NameTableLayout) FontError!void {
    if (layout.format != 1) return;
    for (0..layout.lang_tag_count) |index| {
        const record_offset = layout.lang_tag_records_start + index * lang_tag_record_size;
        const length: usize = @intCast(try bin.readU16At(table, record_offset));
        const offset: usize = @intCast(try bin.readU16At(table, record_offset + 2));
        const tag_data = try nameStorageString(table, layout, offset, length);
        try validateUtf16BeNameData(tag_data);
    }
}

fn readNameRecord(table: []const u8, index: usize) FontError!NameRecord {
    const rec = name_records_start + index * name_record_size;
    if (rec + name_record_size > table.len) return error.BadSfnt;
    return .{
        .platform_id = try bin.readU16At(table, rec),
        .encoding_id = try bin.readU16At(table, rec + 2),
        .language_id = try bin.readU16At(table, rec + 4),
        .name_id = try bin.readU16At(table, rec + 6),
        .length = try bin.readU16At(table, rec + 8),
        .offset = try bin.readU16At(table, rec + 10),
    };
}

fn validateNameRecordMetadata(layout: NameTableLayout, record: NameRecord) FontError!void {
    try validateNameRecordPlatformEncoding(record);

    // In name table format 1, language IDs from 0x8000 upward are indexes into
    // the LangTagRecord array. Validate the reference for every record at parse
    // time so later family/style lookups cannot trip over an unrelated broken
    // localized name entry. Older format-0 language IDs remain platform-owned.
    if (layout.format == 1 and (record.language_id & 0x8000) != 0) {
        const lang_tag_index = @as(usize, record.language_id & 0x7fff);
        if (lang_tag_index >= layout.lang_tag_count) return error.BadSfnt;
    }
}

fn validateNameRecordPlatformEncoding(record: NameRecord) FontError!void {
    switch (record.platform_id) {
        0 => if (record.encoding_id > 6) return error.InvalidName,
        // Macintosh encoding IDs are legacy Script Manager codes. Keep them
        // range-agnostic here: the important structural guarantee is that the
        // platform itself is registered, while many old production fonts use
        // obscure Mac encodings that Cangjie treats as opaque single-byte data.
        1 => {},
        2 => if (record.encoding_id > 2) return error.InvalidName,
        3 => switch (record.encoding_id) {
            0, 1, 2, 3, 4, 5, 6, 10 => {},
            else => return error.InvalidName,
        },
        4 => {},
        else => return error.InvalidName,
    }
}

fn nameRecordString(table: []const u8, layout: NameTableLayout, record: NameRecord) FontError![]const u8 {
    return try nameStorageString(table, layout, record.offset, record.length);
}

fn nameStorageString(table: []const u8, layout: NameTableLayout, offset: usize, length: usize) FontError![]const u8 {
    if (offset > layout.storage_length or length > layout.storage_length - offset) return error.BadSfnt;
    const start = layout.storage_offset + offset;
    return table[start .. start + length];
}

fn validateNameRecordEncoding(record: NameRecord, string_data: []const u8) FontError!void {
    if (isUtf16Name(record)) try validateUtf16BeNameData(string_data);
}

fn validateUtf16BeNameData(data: []const u8) FontError!void {
    if (data.len % 2 != 0) return error.InvalidName;
    var index: usize = 0;
    while (index < data.len) : (index += 2) {
        const unit = std.mem.readInt(u16, data[index..][0..2], .big);
        if (unit >= 0xd800 and unit <= 0xdbff) {
            if (index + 4 > data.len) return error.InvalidName;
            const low = std.mem.readInt(u16, data[index + 2 ..][0..2], .big);
            if (low < 0xdc00 or low > 0xdfff) return error.InvalidName;
            index += 2;
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            return error.InvalidName;
        }
    }
}

fn readNameString(data: []const u8, name: TableRecord, name_id: u16, out: []u8) FontError!?[]const u8 {
    const table = try nameTableSlice(data, name);
    const layout = try readNameTableLayout(table);
    try validateNameLanguageTags(table, layout);

    var best: ?NameRecord = null;
    for (0..layout.count) |i| {
        const record = try readNameRecord(table, i);
        try validateNameRecordMetadata(layout, record);
        const string_data = try nameRecordString(table, layout, record);
        try validateNameRecordEncoding(record, string_data);
        if (record.name_id != name_id) continue;
        if (best == null or scoreNameRecord(record) > scoreNameRecord(best.?)) best = record;
    }

    const chosen = best orelse return null;
    const string_data = try nameRecordString(table, layout, chosen);
    if (isUtf16Name(chosen)) return try decodeUtf16BeName(string_data, out);
    return try decodeSingleByteName(string_data, out);
}

fn scoreNameRecord(record: NameRecord) u8 {
    var score: u8 = 0;
    if (isUtf16Name(record)) score += 8;
    if (record.platform_id == 3 and record.language_id == 0x0409) score += 4;
    if (record.platform_id == 0) score += 3;
    if (record.platform_id == 1 and record.language_id == 0) score += 1;
    return score;
}

fn isUtf16Name(record: NameRecord) bool {
    return switch (record.platform_id) {
        0 => true,
        2 => record.encoding_id == 1,
        // Windows name strings are UTF-16BE only for the Unicode encodings.
        // Legacy Shift-JIS/GBK/Big5/Wansung/Johab records are structurally
        // valid but are not Unicode strings, so do not apply surrogate rules.
        3 => record.encoding_id == 0 or record.encoding_id == 1 or record.encoding_id == 10,
        else => false,
    };
}

fn decodeUtf16BeName(data: []const u8, out: []u8) FontError![]const u8 {
    if (data.len % 2 != 0) return error.InvalidName;
    var written: usize = 0;
    var index: usize = 0;
    while (index < data.len) : (index += 2) {
        const unit = std.mem.readInt(u16, data[index..][0..2], .big);
        const codepoint: u21 = if (unit >= 0xd800 and unit <= 0xdbff) blk: {
            if (index + 4 > data.len) return error.InvalidName;
            const low = std.mem.readInt(u16, data[index + 2 ..][0..2], .big);
            if (low < 0xdc00 or low > 0xdfff) return error.InvalidName;
            index += 2;
            break :blk 0x10000 + ((@as(u21, unit - 0xd800) << 10) | @as(u21, low - 0xdc00));
        } else if (unit >= 0xdc00 and unit <= 0xdfff) {
            return error.InvalidName;
        } else unit;
        const length = std.unicode.utf8CodepointSequenceLength(codepoint) catch return error.InvalidName;
        if (written + length > out.len) return error.InvalidName;
        written += std.unicode.utf8Encode(codepoint, out[written..]) catch return error.InvalidName;
    }
    return out[0..written];
}

fn decodeSingleByteName(data: []const u8, out: []u8) FontError![]const u8 {
    if (data.len > out.len) return error.InvalidName;
    @memcpy(out[0..data.len], data);
    return out[0..data.len];
}

fn scoreCmap(subtable: CmapSubtable) u8 {
    if (subtable.format == 12 and subtable.platform_id == 3 and subtable.encoding_id == 10) return 8;
    if (subtable.format == 12 and subtable.platform_id == 0) return 7;
    if (subtable.format == 8 and subtable.platform_id == 0 and subtable.encoding_id == 4) return 6;
    if (subtable.format == 4 and subtable.platform_id == 3 and subtable.encoding_id == 1) return 5;
    if (subtable.format == 4 and subtable.platform_id == 0) return 4;
    if (subtable.format == 13 and subtable.platform_id == 0 and subtable.encoding_id == 6) return 2;
    if (subtable.format == 10 and subtable.platform_id == 0 and subtable.encoding_id == 4) return 2;
    if (subtable.format == 2 and (subtable.platform_id == 0 or subtable.platform_id == 3)) return 1;
    if (subtable.format == 6 and (subtable.platform_id == 0 or subtable.platform_id == 3)) return 1;
    if (subtable.format == 0) return 1;
    return 0;
}

fn glyphIndexFormat0(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xff) return 0;
    const length = try bin.readU16At(data, offset + 2);
    try validateCmapFormat0(length);
    return data[offset + 6 + @as(usize, codepoint)];
}

fn glyphIndexFormat2(data: []const u8, offset: usize, length: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xffff) return 0;
    try validateCmapFormat2(data, offset, length);

    const high_byte: u8 = @intCast((codepoint >> 8) & 0xff);
    const low_byte: u8 = @intCast(codepoint & 0xff);
    const key = try bin.readU16At(data, offset + 6 + @as(usize, high_byte) * 2);
    const subheader_index = key / 8;
    const subheader_offset = offset + 6 + 512 + @as(usize, subheader_index) * 8;

    // The first subheader also maps one-byte character codes. For non-zero
    // high bytes, only a referenced subheader is valid; an absent high-byte
    // key means the two-byte character is unmapped rather than falling through
    // the single-byte table.
    if (high_byte != 0 and subheader_index == 0) return 0;

    const first_code = try bin.readU16At(data, subheader_offset);
    const entry_count = try bin.readU16At(data, subheader_offset + 2);
    const id_delta = try bin.readI16At(data, subheader_offset + 4);
    const id_range_offset = try bin.readU16At(data, subheader_offset + 6);
    const char_code = @as(u16, low_byte);
    if (char_code < first_code) return 0;
    const entry_index = @as(usize, char_code - first_code);
    if (entry_index >= entry_count) return 0;

    const glyph_offset = subheader_offset + 6 + @as(usize, id_range_offset) + entry_index * 2;
    const glyph = try bin.readU16At(data, glyph_offset);
    if (glyph == 0) return 0;
    return @intCast(@as(u16, @bitCast(@as(i16, @bitCast(glyph)) +% id_delta)));
}

fn glyphIndexFormat4(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xffff) return 0;
    if (offset > data.len or data.len - offset < 8) return error.BadSfnt;
    const length = try bin.readU16At(data, offset + 2);
    if (length > data.len - offset) return error.BadSfnt;

    const seg_count_x2 = try bin.readU16At(data, offset + 6);
    if (seg_count_x2 == 0 or (seg_count_x2 & 1) != 0) return error.BadSfnt;
    const seg_count = @as(usize, seg_count_x2 / 2);
    const minimum_length = 16 + seg_count * 8;
    if (length < minimum_length) return error.BadSfnt;

    const table_end = offset + @as(usize, length);
    const end_codes = offset + 14;
    const start_codes = end_codes + @as(usize, seg_count) * 2 + 2;
    const id_deltas = start_codes + @as(usize, seg_count) * 2;
    const id_range_offsets = id_deltas + @as(usize, seg_count) * 2;
    const cp: u16 = @intCast(codepoint);
    for (0..seg_count) |i| {
        const end = try bin.readU16At(data, end_codes + i * 2);
        if (cp > end) continue;
        const start = try bin.readU16At(data, start_codes + i * 2);
        if (cp < start) return 0;
        const delta = try bin.readI16At(data, id_deltas + i * 2);
        const range_offset = try bin.readU16At(data, id_range_offsets + i * 2);
        if (range_offset == 0) {
            return @intCast(@as(u16, @bitCast(@as(i16, @bitCast(cp)) +% delta)));
        }
        const glyph_offset = id_range_offsets + i * 2 + range_offset + (@as(usize, cp - start) * 2);
        // idRangeOffset addresses are relative to the idRangeOffset word, but
        // the resolved glyph id still belongs to this format-4 subtable. Do
        // not let malformed cmaps read arbitrary bytes from the containing SFNT
        // when the subtable's declared length ends before the glyph array.
        if (glyph_offset + 2 > table_end) return error.BadSfnt;
        const glyph = try bin.readU16At(data, glyph_offset);
        if (glyph == 0) return 0;
        return @intCast(@as(u16, @bitCast(@as(i16, @bitCast(glyph)) +% delta)));
    }
    return 0;
}

fn glyphIndexFormat6(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xffff) return 0;
    const length = try bin.readU16At(data, offset + 2);
    try validateCmapFormat6(data, offset, length, false);
    const first_code = try bin.readU16At(data, offset + 6);
    const entry_count = try bin.readU16At(data, offset + 8);
    const cp: u16 = @intCast(codepoint);
    if (cp < first_code) return 0;
    const index = @as(usize, cp - first_code);
    if (index >= entry_count) return 0;
    return try bin.readU16At(data, offset + 10 + index * 2);
}

fn glyphIndexFormat8(data: []const u8, offset: usize, length: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    try validateCmapFormat8(data, offset, length);
    return try glyphIndexSequentialMapGroups(data, offset, cmap_format8_groups_offset, length, codepoint);
}

fn glyphIndexFormat10(data: []const u8, offset: usize, length: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    try validateCmapFormat10(data, offset, length);
    const start_code = try bin.readU32At(data, offset + 12);
    const num_chars = try bin.readU32At(data, offset + 16);
    if (codepoint < start_code) return 0;
    const index = @as(usize, codepoint - start_code);
    if (index >= num_chars) return 0;
    return try bin.readU16At(data, offset + 20 + index * 2);
}

fn glyphIndexFormat12(data: []const u8, offset: usize, length: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    return try glyphIndexSequentialMapGroups(data, offset, 16, length, codepoint);
}

fn glyphIndexFormat13(data: []const u8, offset: usize, length: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    // Format 13 shares the segmented 32-bit group layout with format 12, but
    // each group maps every scalar in the range to the same glyph id. This is
    // how last-resort fonts cover huge Unicode ranges without carrying per-code
    // point glyph indices.
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    const groups = try bin.readU32At(data, offset + 12);
    if (@as(usize, groups) > (length - 16) / 12) return error.BadSfnt;

    var lo: usize = 0;
    var hi: usize = @intCast(groups);
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const group_offset = offset + 16 + mid * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (codepoint < start) {
            hi = mid;
        } else if (codepoint > end) {
            lo = mid + 1;
        } else {
            const glyph_id = try bin.readU32At(data, group_offset + 8);
            if (glyph_id > std.math.maxInt(glyph_mod.GlyphId)) return error.BadSfnt;
            return @intCast(glyph_id);
        }
    }
    return 0;
}

fn glyphIndexSequentialMapGroups(data: []const u8, offset: usize, groups_offset: usize, length: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    // SequentialMapGroup records are sorted by startCharCode. Binary search
    // avoids a linear scan through very large CJK fonts with thousands of
    // ranges and is shared by format 8 and format 12.
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (groups_offset < 4 or groups_offset > length) return error.BadSfnt;
    const groups = try bin.readU32At(data, offset + groups_offset - 4);
    if (@as(usize, groups) > (length - groups_offset) / 12) return error.BadSfnt;

    var lo: usize = 0;
    var hi: usize = @intCast(groups);
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const group_offset = offset + groups_offset + mid * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (end < start) return error.BadSfnt;
        if (codepoint < start) {
            hi = mid;
        } else if (codepoint > end) {
            lo = mid + 1;
        } else {
            const first = try bin.readU32At(data, group_offset + 8);
            const delta = @as(u32, codepoint) - start;
            if (first > std.math.maxInt(u32) - delta) return error.BadSfnt;
            const glyph_id = first + delta;
            if (glyph_id > std.math.maxInt(glyph_mod.GlyphId)) return error.BadSfnt;
            return @intCast(glyph_id);
        }
    }
    return 0;
}

fn glyphIndexFormat14(self: *const Font, offset: usize, codepoint: u21, variation_selector: u21) FontError!?glyph_mod.GlyphId {
    if (variation_selector > 0xffffff or codepoint > 0xffffff) return null;
    const data = self.data;
    const length: usize = @intCast(try bin.readU32At(data, offset + 2));
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    const table_end = offset + length;
    const record_count: usize = @intCast(try bin.readU32At(data, offset + 6));
    const records_end = try cmapFormat14RecordsEnd(length, record_count);

    const selector: u32 = @intCast(variation_selector);
    var previous_selector: ?u32 = null;
    for (0..record_count) |index| {
        const record = offset + 10 + index * 11;
        const record_selector = try readU24At(data, record);
        if (!isUnicodeVariationSelector(record_selector)) return error.BadSfnt;
        if (previous_selector) |last_selector| {
            if (record_selector <= last_selector) return error.BadSfnt;
        }
        previous_selector = record_selector;
        if (selector < record_selector) return null;
        if (selector > record_selector) continue;

        const default_offset = try bin.readU32At(data, record + 3);
        const non_default_offset = try bin.readU32At(data, record + 7);
        if (non_default_offset != 0) {
            const non_default_payload_offset = try validateCmapFormat14PayloadOffset(non_default_offset, records_end, length);
            if (try glyphIndexFormat14NonDefault(data, offset + non_default_payload_offset, table_end, codepoint)) |glyph_id| return glyph_id;
        }
        if (default_offset != 0) {
            const default_payload_offset = try validateCmapFormat14PayloadOffset(default_offset, records_end, length);
            if (try glyphIndexFormat14DefaultContains(data, offset + default_payload_offset, table_end, codepoint)) {
                return try self.glyphIndex(codepoint);
            }
        }
        return null;
    }
    return null;
}

fn glyphIndexFormat14DefaultContains(data: []const u8, offset: usize, table_end: usize, codepoint: u21) FontError!bool {
    if (offset + 4 > table_end) return error.BadSfnt;
    const range_count = try bin.readU32At(data, offset);
    if (@as(usize, range_count) * 4 > table_end - (offset + 4)) return error.BadSfnt;
    const cp: u32 = @intCast(codepoint);
    for (0..range_count) |index| {
        const range = offset + 4 + index * 4;
        const start = try readU24At(data, range);
        const end = start + data[range + 3];
        if (cp >= start and cp <= end) return true;
    }
    return false;
}

fn glyphIndexFormat14NonDefault(data: []const u8, offset: usize, table_end: usize, codepoint: u21) FontError!?glyph_mod.GlyphId {
    if (offset + 4 > table_end) return error.BadSfnt;
    const mapping_count = try bin.readU32At(data, offset);
    if (@as(usize, mapping_count) * 5 > table_end - (offset + 4)) return error.BadSfnt;
    const cp: u32 = @intCast(codepoint);
    for (0..mapping_count) |index| {
        const mapping = offset + 4 + index * 5;
        const unicode_value = try readU24At(data, mapping);
        if (cp < unicode_value) return null;
        if (cp > unicode_value) continue;
        return try bin.readU16At(data, mapping + 3);
    }
    return null;
}

fn kernFormat0Body(data: []const u8, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!?i16 {
    // The format-0 body begins with the binary-search header; the surrounding
    // kern table variant owns the common subtable header length.
    if (data.len < 8) return error.BadSfnt;
    const pair_count = try bin.readU16At(data, 0);
    if (@as(usize, pair_count) * 6 > data.len - 8) return error.BadSfnt;
    const needle = (@as(u32, left) << 16) | right;
    var lo: usize = 0;
    var hi: usize = pair_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const offset = 8 + mid * 6;
        const pair = (@as(u32, try bin.readU16At(data, offset)) << 16) | try bin.readU16At(data, offset + 2);
        if (needle < pair) {
            hi = mid;
        } else if (needle > pair) {
            lo = mid + 1;
        } else {
            return try bin.readI16At(data, offset + 4);
        }
    }
    return null;
}

fn appendSimpleGlyph(outline: *glyph_mod.GlyphOutline, data: []const u8, contour_count: u16, transform: Transform) FontError!void {
    if (contour_count == 0) return;
    var r = bin.Reader.init(data);
    _ = try r.readI16();
    try r.skip(8);
    const end_pts = try outline.allocator.alloc(u16, contour_count);
    defer outline.allocator.free(end_pts);
    var total_points: usize = 0;
    var previous_end: ?u16 = null;
    for (end_pts) |*end| {
        end.* = try r.readU16();
        if (previous_end) |prev| {
            // endPtsOfContours must be strictly increasing. Accepting a
            // repeated/decreasing end point lets malformed glyf data define an
            // empty or overlapping contour, which later underflows when the
            // contour slice is built from `start .. end + 1`.
            if (end.* <= prev) return error.InvalidGlyph;
        }
        previous_end = end.*;
        total_points = @as(usize, end.*) + 1;
    }
    const instruction_len = try r.readU16();
    try r.skip(instruction_len);

    // The glyf flag stream is run-length encoded; coordinate arrays that follow
    // it depend on the expanded per-point flags.
    var flags = try outline.allocator.alloc(u8, total_points);
    defer outline.allocator.free(flags);
    var i: usize = 0;
    while (i < total_points) : (i += 1) {
        const flag = try r.readU8();
        flags[i] = flag;
        if ((flag & 0x08) != 0) {
            const repeat = try r.readU8();
            for (0..repeat) |_| {
                i += 1;
                if (i >= total_points) return error.InvalidGlyph;
                flags[i] = flag;
            }
        }
    }

    // X and Y values are stored as deltas in two separate streams. Rebuild
    // absolute point coordinates before contour reconstruction.
    var points = try outline.allocator.alloc(FlaggedPoint, total_points);
    defer outline.allocator.free(points);
    var x: i16 = 0;
    for (points, flags) |*point, flag| {
        const dx: i16 = if ((flag & 0x02) != 0)
            if ((flag & 0x10) != 0) try r.readU8() else -@as(i16, try r.readU8())
        else if ((flag & 0x10) != 0)
            0
        else
            try r.readI16();
        x += dx;
        point.x = x;
        point.on_curve = (flag & 0x01) != 0;
    }
    var y: i16 = 0;
    for (points, flags) |*point, flag| {
        const dy: i16 = if ((flag & 0x04) != 0)
            if ((flag & 0x20) != 0) try r.readU8() else -@as(i16, try r.readU8())
        else if ((flag & 0x20) != 0)
            0
        else
            try r.readI16();
        y += dy;
        point.y = y;
    }

    var start: usize = 0;
    var builder = glyph_mod.OutlineBuilder{ .outline = outline };
    for (end_pts) |end_pt| {
        const end: usize = end_pt;
        try appendContour(&builder, points[start .. end + 1], transform);
        start = end + 1;
    }
}

const FlaggedPoint = struct {
    x: i16,
    y: i16,
    on_curve: bool,

    fn point(self: FlaggedPoint) glyph_mod.Point {
        return .{ .x = @floatFromInt(self.x), .y = @floatFromInt(self.y) };
    }
};

fn appendContour(builder: *glyph_mod.OutlineBuilder, contour: []const FlaggedPoint, transform: Transform) FontError!void {
    if (contour.len == 0) return;
    const first = contour[0];
    const last = contour[contour.len - 1];
    var current: glyph_mod.Point = undefined;
    var index: usize = 0;
    // TrueType permits contours to start with an off-curve control point. In
    // that case the visible start point is either the final on-curve point or
    // the implied midpoint between the first and last controls.
    if (first.on_curve) {
        current = first.point();
        index = 1;
    } else if (last.on_curve) {
        current = last.point();
    } else {
        current = glyph_mod.midpoint(last.point(), first.point());
    }
    try builder.moveTo(transform.apply(current));

    while (index < contour.len) {
        const p = contour[index];
        if (p.on_curve) {
            current = p.point();
            try builder.lineTo(transform.apply(current));
            index += 1;
        } else {
            // Consecutive off-curve points imply an on-curve point at their
            // midpoint, preserving quadratic continuity without storing an
            // explicit endpoint in the font.
            const control = p.point();
            const next_index = if (index + 1 < contour.len) index + 1 else 0;
            const next = contour[next_index];
            const end = if (next.on_curve) next.point() else glyph_mod.midpoint(control, next.point());
            try builder.quadTo(transform.apply(control), transform.apply(end));
            current = end;
            index += if (next.on_curve and next_index != 0) 2 else 1;
        }
    }
    try builder.close();
}

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}

const FvarInfo = struct {
    axes_array_offset: usize,
    axis_count: usize,
    axis_size: usize,
    instance_count: usize,
    instance_size: usize,
    instances_array_offset: usize,
    postscript_name_id_offset: usize,
    has_postscript_name_id: bool,
};

fn validateVariationNameReferences(allocator: std.mem.Allocator, data: []const u8, fvar: ?TableRecord, stat: ?TableRecord, name: ?TableRecord) FontError!void {
    if (fvar == null and stat == null) return;

    var name_index_storage: NameIdIndex = undefined;
    const name_index: ?*const NameIdIndex = if (name) |name_table| blk: {
        name_index_storage = try readNameIdIndex(data, name_table);
        break :blk &name_index_storage;
    } else null;

    // fvar and STAT carry user-visible IDs rather than inline strings. Missing
    // or undecodable references make style/axis selection ambiguous, so reject
    // them at parse time instead of surfacing null names much later.
    if (fvar) |fvar_table| try validateFvarNameReferences(data, fvar_table, name_index);
    if (stat) |stat_table| try validateStatTable(allocator, data, stat_table, fvar, name_index);
}

fn validateFvarNameReferences(data: []const u8, fvar: TableRecord, name_index: ?*const NameIdIndex) FontError!void {
    const info = try readFvarInfo(data, fvar);
    for (0..info.axis_count) |index| {
        const axis_offset = fvarAxisOffset(fvar, info, index);
        try validateNameIdReference(name_index, try bin.readU16At(data, axis_offset + 18));
    }

    for (0..info.instance_count) |index| {
        const instance_offset = fvarInstanceOffset(fvar, info, index);
        try validateNameIdReference(name_index, try bin.readU16At(data, instance_offset));

        // Instance PostScript names are optional in fvar 1.0 and use 0xffff as
        // the explicit "not supplied" sentinel.  Any real ID is user-visible
        // metadata and must resolve through a structurally valid name record.
        if (info.has_postscript_name_id) {
            try validateOptionalNameIdReference(name_index, try bin.readU16At(data, instance_offset + info.postscript_name_id_offset));
        }
    }
}

fn validateFvarTable(data: []const u8, fvar: TableRecord) FontError!void {
    const info = try readFvarInfo(data, fvar);

    for (0..info.axis_count) |axis_index| {
        const axis_offset = fvarAxisOffset(fvar, info, axis_index);
        const min_value = try bin.readI32At(data, axis_offset + 4);
        const default_value = try bin.readI32At(data, axis_offset + 8);
        const max_value = try bin.readI32At(data, axis_offset + 12);
        if (min_value > default_value or default_value > max_value) return error.BadSfnt;

        // OpenType 1.x reserves all fvar axis flag bits except HIDDEN_AXIS.
        // Rejecting unknown bits prevents future/garbled axis semantics from
        // being treated as ordinary exposed variation controls.
        const flags = try bin.readU16At(data, axis_offset + 16);
        if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;

        const tag = try bin.readTagAt(data, axis_offset);
        for (0..axis_index) |previous_index| {
            const previous_offset = fvarAxisOffset(fvar, info, previous_index);
            const previous_tag = try bin.readTagAt(data, previous_offset);
            if (std.mem.eql(u8, &previous_tag, &tag)) return error.BadSfnt;
        }
    }

    for (0..info.instance_count) |instance_index| {
        const instance_offset = fvarInstanceOffset(fvar, info, instance_index);
        const flags = try bin.readU16At(data, instance_offset + 2);
        if (flags != 0) return error.BadSfnt;

        for (0..info.axis_count) |axis_index| {
            const coordinate = try bin.readI32At(data, instance_offset + 4 + axis_index * 4);
            const axis_offset = fvarAxisOffset(fvar, info, axis_index);
            const min_value = try bin.readI32At(data, axis_offset + 4);
            const max_value = try bin.readI32At(data, axis_offset + 12);
            if (coordinate < min_value or coordinate > max_value) return error.BadSfnt;
        }
    }
}

fn validateStatTable(allocator: std.mem.Allocator, data: []const u8, stat: TableRecord, fvar: ?TableRecord, name_index: ?*const NameIdIndex) FontError!void {
    if (stat.length < 20) return error.BadSfnt;
    const major = try bin.readU16At(data, stat.offset);
    const minor = try bin.readU16At(data, stat.offset + 2);
    if (major != 1 or minor > 2) return error.BadSfnt;

    const design_axis_size: usize = @intCast(try bin.readU16At(data, stat.offset + 4));
    const design_axis_count: usize = @intCast(try bin.readU16At(data, stat.offset + 6));
    const design_axes_offset: usize = @intCast(try bin.readU32At(data, stat.offset + 8));
    const axis_value_count: usize = @intCast(try bin.readU16At(data, stat.offset + 12));
    const axis_value_offsets_offset: usize = @intCast(try bin.readU32At(data, stat.offset + 14));

    if (design_axis_size < 8) return error.BadSfnt;
    if (design_axis_count != 0) {
        if (design_axes_offset < 20 or design_axes_offset > stat.length) return error.BadSfnt;
        if (design_axis_count > (stat.length - design_axes_offset) / design_axis_size) return error.BadSfnt;
    } else if (design_axes_offset != 0 and design_axes_offset < 20) {
        return error.BadSfnt;
    }

    if (axis_value_count != 0) {
        if (axis_value_offsets_offset < 20 or axis_value_offsets_offset > stat.length) return error.BadSfnt;
        if (axis_value_count > (stat.length - axis_value_offsets_offset) / 2) return error.BadSfnt;
    } else if (axis_value_offsets_offset != 0 and axis_value_offsets_offset < 20) {
        return error.BadSfnt;
    }

    if (minor >= 1) try validateNameIdReference(name_index, try bin.readU16At(data, stat.offset + 18));

    const fvar_info = if (fvar) |fvar_table| try readFvarInfo(data, fvar_table) else null;
    if (fvar_info) |info| {
        if (design_axis_count != info.axis_count) return error.BadSfnt;
    }
    for (0..design_axis_count) |index| {
        const stat_axis = stat.offset + design_axes_offset + index * design_axis_size;
        const stat_tag = try bin.readTagAt(data, stat_axis);
        try validateStatDesignAxisOrder(data, stat, design_axes_offset, design_axis_size, index, &stat_tag);
        try validateNameIdReference(name_index, try bin.readU16At(data, stat_axis + 4));
        if (fvar_info) |info| {
            const fvar_table = fvar.?;
            const fvar_axis = fvar_table.offset + info.axes_array_offset + index * info.axis_size;
            const fvar_tag = try bin.readTagAt(data, fvar_axis);
            // STAT axis records provide user-facing names and ordering for the
            // variation axes. Keeping them in fvar order prevents later style
            // selection from binding a STAT AxisValue to the wrong coordinate.
            if (!std.mem.eql(u8, &stat_tag, &fvar_tag)) return error.BadSfnt;
        }
    }

    const axis_values = try allocator.alloc(StatAxisValueSummary, axis_value_count);
    defer allocator.free(axis_values);
    var previous_axis_value_offset: ?usize = null;
    for (axis_values, 0..) |*axis_value, index| {
        const entry_offset = stat.offset + axis_value_offsets_offset + index * 2;
        const axis_value_offset = try resolveStatAxisValueOffset(data, stat, axis_value_offsets_offset, entry_offset);
        try validateStatAxisValueOffsetOrder(axis_value_offset, &previous_axis_value_offset);
        axis_value.* = try validateStatAxisValue(data, stat, axis_value_offset, design_axis_count, design_axes_offset, design_axis_size, axis_value_offsets_offset, axis_value_count, name_index);
    }
    try validateStatAxisValueSet(data, stat, axis_values);
}

fn validateStatDesignAxisOrder(data: []const u8, stat: TableRecord, design_axes_offset: usize, design_axis_size: usize, axis_index: usize, axis_tag: *const [4]u8) FontError!void {
    const axis_record = stat.offset + design_axes_offset + axis_index * design_axis_size;
    const axis_ordering = try bin.readU16At(data, axis_record + 6);
    for (0..axis_index) |previous_index| {
        const previous_record = stat.offset + design_axes_offset + previous_index * design_axis_size;
        const previous_tag = try bin.readTagAt(data, previous_record);
        if (std.mem.eql(u8, axis_tag, &previous_tag)) return error.BadSfnt;
        const previous_ordering = try bin.readU16At(data, previous_record + 6);
        // AxisOrdering is the canonical presentation sort key for STAT axes.
        // Duplicate ordering values leave style UIs with no deterministic
        // canonical axis order, even when the axis tags themselves differ.
        if (axis_ordering == previous_ordering) return error.BadSfnt;
    }
}

fn resolveStatAxisValueOffset(data: []const u8, stat: TableRecord, axis_value_offsets_offset: usize, entry_offset: usize) FontError!usize {
    const relative_offset: usize = @intCast(try bin.readU16At(data, entry_offset));
    if (relative_offset > stat.length - axis_value_offsets_offset) return error.BadSfnt;
    const axis_value_offset = axis_value_offsets_offset + relative_offset;
    if (axis_value_offset < 20 or axis_value_offset > stat.length - 4) return error.BadSfnt;
    return axis_value_offset;
}

fn validateStatAxisValueOffsetOrder(axis_value_offset: usize, previous_axis_value_offset: *?usize) FontError!void {
    if (previous_axis_value_offset.*) |previous| {
        // The AxisValue offset array is the canonical child-table directory for
        // STAT style labels. Keep it in table order so equivalent records cannot
        // be reordered to produce multiple normal forms, and so later
        // cross-record checks never depend on offset-array presentation order.
        if (axis_value_offset <= previous) return error.BadSfnt;
    }
    previous_axis_value_offset.* = axis_value_offset;
}

const StatAxisPoint = struct {
    axis_index: u16,
    value: i32,
    flags: u16,
    name_id: u16,
    format: u16,
};

const StatAxisRange = struct {
    axis_index: u16,
    nominal: i32,
    min: i32,
    max: i32,
    flags: u16,
    name_id: u16,
};

const StatMultiAxis = struct {
    axis_count: usize,
};

const StatMultiAxisCoordinate = struct {
    axis_index: u16,
    value: i32,
};

const StatAxisValueKind = union(enum) {
    point: StatAxisPoint,
    range: StatAxisRange,
    multi_axis: StatMultiAxis,
};

const StatAxisValueSummary = struct {
    offset: usize,
    length: usize,
    kind: StatAxisValueKind,
};

fn validateStatAxisValue(data: []const u8, stat: TableRecord, axis_value_offset: usize, design_axis_count: usize, design_axes_offset: usize, design_axis_size: usize, axis_value_offsets_offset: usize, axis_value_count: usize, name_index: ?*const NameIdIndex) FontError!StatAxisValueSummary {
    const absolute = stat.offset + axis_value_offset;
    if (absolute + 4 > stat.offset + stat.length) return error.BadSfnt;
    const format = try bin.readU16At(data, absolute);

    // AxisValue offsets are resolved relative to the AxisValue offset array and
    // should identify real payload, not the DesignAxisRecord array or the
    // offset array itself. Without these guards a malformed font can
    // reinterpret metadata as an AxisValue table.
    const design_axes_end = design_axes_offset + design_axis_count * design_axis_size;
    if (axis_value_offset >= design_axes_offset and axis_value_offset < design_axes_end) return error.BadSfnt;
    const offset_array_end = axis_value_offsets_offset + axis_value_count * 2;
    if (axis_value_offset >= axis_value_offsets_offset and axis_value_offset < offset_array_end) return error.BadSfnt;

    switch (format) {
        1 => {
            const length: usize = 12;
            if (length > stat.length - axis_value_offset) return error.BadSfnt;
            const axis_index = try bin.readU16At(data, absolute + 2);
            if (axis_index >= design_axis_count) return error.BadSfnt;
            const flags = try bin.readU16At(data, absolute + 4);
            try validateStatAxisValueFlags(flags);
            const name_id = try bin.readU16At(data, absolute + 6);
            try validateNameIdReference(name_index, name_id);
            return .{
                .offset = axis_value_offset,
                .length = length,
                .kind = .{ .point = .{
                    .axis_index = axis_index,
                    .value = try bin.readI32At(data, absolute + 8),
                    .flags = flags,
                    .name_id = name_id,
                    .format = format,
                } },
            };
        },
        2 => {
            const length: usize = 20;
            if (length > stat.length - axis_value_offset) return error.BadSfnt;
            const axis_index = try bin.readU16At(data, absolute + 2);
            if (axis_index >= design_axis_count) return error.BadSfnt;
            const flags = try bin.readU16At(data, absolute + 4);
            try validateStatAxisValueFlags(flags);
            const name_id = try bin.readU16At(data, absolute + 6);
            try validateNameIdReference(name_index, name_id);
            const nominal = try bin.readI32At(data, absolute + 8);
            const min = try bin.readI32At(data, absolute + 12);
            const max = try bin.readI32At(data, absolute + 16);
            if (min > nominal or nominal > max) return error.BadSfnt;
            return .{
                .offset = axis_value_offset,
                .length = length,
                .kind = .{ .range = .{
                    .axis_index = axis_index,
                    .nominal = nominal,
                    .min = min,
                    .max = max,
                    .flags = flags,
                    .name_id = name_id,
                } },
            };
        },
        3 => {
            const length: usize = 16;
            if (length > stat.length - axis_value_offset) return error.BadSfnt;
            const axis_index = try bin.readU16At(data, absolute + 2);
            if (axis_index >= design_axis_count) return error.BadSfnt;
            const flags = try bin.readU16At(data, absolute + 4);
            try validateStatAxisValueFlags(flags);
            const name_id = try bin.readU16At(data, absolute + 6);
            try validateNameIdReference(name_index, name_id);
            return .{
                .offset = axis_value_offset,
                .length = length,
                .kind = .{ .point = .{
                    .axis_index = axis_index,
                    .value = try bin.readI32At(data, absolute + 8),
                    .flags = flags,
                    .name_id = name_id,
                    .format = format,
                } },
            };
        },
        4 => {
            if (axis_value_offset + 8 > stat.length) return error.BadSfnt;
            const axis_count: usize = @intCast(try bin.readU16At(data, absolute + 2));
            if (axis_count == 0) return error.BadSfnt;
            const flags = try bin.readU16At(data, absolute + 4);
            try validateStatAxisValueFlags(flags);
            const name_id = try bin.readU16At(data, absolute + 6);
            try validateNameIdReference(name_index, name_id);
            if (axis_count > (stat.length - axis_value_offset - 8) / 6) return error.BadSfnt;
            for (0..axis_count) |axis_record_index| {
                const axis_record = absolute + 8 + axis_record_index * 6;
                const axis_index = try bin.readU16At(data, axis_record);
                if (axis_index >= design_axis_count) return error.BadSfnt;
                for (0..axis_record_index) |previous_record_index| {
                    const previous_axis_record = absolute + 8 + previous_record_index * 6;
                    if (axis_index == try bin.readU16At(data, previous_axis_record)) return error.BadSfnt;
                }
            }
            if (axis_count == 1) {
                const coordinate = try readStatMultiAxisCoordinate(data, stat, axis_value_offset, 0);
                // A single-coordinate format 4 AxisValue has no extra
                // combination specificity over formats 1/2/3. Treating it as
                // a point for cross-record validation keeps style-name
                // selection from depending on table order when it duplicates a
                // point or sits ambiguously inside a single-axis range.
                return .{
                    .offset = axis_value_offset,
                    .length = 8 + axis_count * 6,
                    .kind = .{ .point = .{
                        .axis_index = coordinate.axis_index,
                        .value = coordinate.value,
                        .flags = flags,
                        .name_id = name_id,
                        .format = format,
                    } },
                };
            }
            return .{
                .offset = axis_value_offset,
                .length = 8 + axis_count * 6,
                .kind = .{ .multi_axis = .{ .axis_count = axis_count } },
            };
        },
        else => return error.BadSfnt,
    }
}

fn validateStatAxisValueFlags(flags: u16) FontError!void {
    // The STAT table currently defines only OLDER_SIBLING_FONT_ATTRIBUTE and
    // ELIDABLE_AXIS_VALUE_NAME. Rejecting reserved bits keeps future style
    // selection from silently treating unknown semantics as ordinary labels.
    if ((flags & ~@as(u16, 0x0003)) != 0) return error.BadSfnt;
}

fn validateStatAxisValuePair(data: []const u8, stat: TableRecord, a: StatAxisValueSummary, b: StatAxisValueSummary) FontError!void {
    const a_end = a.offset + a.length;
    const b_end = b.offset + b.length;
    if (a.offset < b_end and b.offset < a_end) return error.BadSfnt;

    switch (a.kind) {
        .point => |point_a| switch (b.kind) {
            .point => |point_b| try validateStatAxisPointPair(point_a, point_b),
            .range => |range_b| try validateStatAxisPointRange(point_a, range_b),
            .multi_axis => {},
        },
        .range => |range_a| switch (b.kind) {
            .point => |point_b| try validateStatAxisPointRange(point_b, range_a),
            .range => |range_b| try validateStatAxisRangePair(range_a, range_b),
            .multi_axis => {},
        },
        .multi_axis => |multi_axis_a| switch (b.kind) {
            .point, .range => {},
            .multi_axis => |multi_axis_b| try validateStatMultiAxisPair(data, stat, a, multi_axis_a, b, multi_axis_b),
        },
    }
}

fn validateStatAxisValueSet(data: []const u8, stat: TableRecord, axis_values: []const StatAxisValueSummary) FontError!void {
    for (axis_values, 0..) |axis_value, index| {
        for (axis_values[0..index]) |previous_axis_value| {
            try validateStatAxisValuePair(data, stat, previous_axis_value, axis_value);
        }
    }
}

fn validateStatMultiAxisPair(data: []const u8, stat: TableRecord, a: StatAxisValueSummary, multi_axis_a: StatMultiAxis, b: StatAxisValueSummary, multi_axis_b: StatMultiAxis) FontError!void {
    if (multi_axis_a.axis_count != multi_axis_b.axis_count) return;

    // AxisValue format 4 is a compound style label; axisValueRecords are a set
    // of axis/value coordinates, not a distinct ordered tuple. Reject exact
    // set duplicates regardless of name IDs or flags so style-name resolution
    // cannot depend on AxisValue record order. Proper subset/superset matches
    // remain valid because the later selector can prefer the more-specific set.
    for (0..multi_axis_a.axis_count) |axis_record_index| {
        const coordinate = try readStatMultiAxisCoordinate(data, stat, a.offset, axis_record_index);
        const b_value = try statMultiAxisValueForAxis(data, stat, b.offset, multi_axis_b.axis_count, coordinate.axis_index) orelse return;
        if (b_value != coordinate.value) return;
    }
    return error.BadSfnt;
}

fn readStatMultiAxisCoordinate(data: []const u8, stat: TableRecord, axis_value_offset: usize, axis_record_index: usize) FontError!StatMultiAxisCoordinate {
    const axis_record = stat.offset + axis_value_offset + 8 + axis_record_index * 6;
    return .{
        .axis_index = try bin.readU16At(data, axis_record),
        .value = try bin.readI32At(data, axis_record + 2),
    };
}

fn statMultiAxisValueForAxis(data: []const u8, stat: TableRecord, axis_value_offset: usize, axis_count: usize, axis_index: u16) FontError!?i32 {
    for (0..axis_count) |axis_record_index| {
        const coordinate = try readStatMultiAxisCoordinate(data, stat, axis_value_offset, axis_record_index);
        if (coordinate.axis_index == axis_index) return coordinate.value;
    }
    return null;
}

fn validateStatAxisPointPair(a: StatAxisPoint, b: StatAxisPoint) FontError!void {
    if (a.axis_index == b.axis_index and a.value == b.value) return error.BadSfnt;
}

fn validateStatAxisPointRange(point: StatAxisPoint, range: StatAxisRange) FontError!void {
    if (point.axis_index != range.axis_index) return;
    if (point.value < range.min or point.value > range.max) return;

    if (statFormat3RangeNominalException(point, range)) return;

    // Format 2 ranges may touch point AxisValues at their endpoints, but a
    // point inside a range (or exactly on the range's nominal endpoint) leaves
    // style-name selection ambiguous. Validate the full AxisValue set once
    // during parsing instead of letting later matching depend on table order.
    if (point.value > range.min and point.value < range.max) return error.BadSfnt;
    if (point.value == range.nominal) return error.BadSfnt;
}

fn statFormat3RangeNominalException(point: StatAxisPoint, range: StatAxisRange) bool {
    return point.format == 3 and
        point.value == range.nominal and
        point.flags == range.flags and
        point.name_id == range.name_id;
}

fn validateStatAxisRangePair(a: StatAxisRange, b: StatAxisRange) FontError!void {
    if (a.axis_index != b.axis_index) return;

    const lower, const upper = if (a.min < b.min or (a.min == b.min and a.max <= b.max)) .{ a, b } else .{ b, a };
    if (lower.max > upper.min) return error.BadSfnt;
    if (lower.max == upper.min and lower.nominal == lower.max and upper.nominal == upper.min) return error.BadSfnt;
}

fn readFvarInfo(data: []const u8, fvar: TableRecord) FontError!FvarInfo {
    if (fvar.length < 16) return error.BadSfnt;
    const major = try bin.readU16At(data, fvar.offset);
    const minor = try bin.readU16At(data, fvar.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const axes_array_offset: usize = @intCast(try bin.readU16At(data, fvar.offset + 4));
    const count_size_pairs = try bin.readU16At(data, fvar.offset + 6);
    const axis_count: usize = @intCast(try bin.readU16At(data, fvar.offset + 8));
    const axis_size: usize = @intCast(try bin.readU16At(data, fvar.offset + 10));
    const instance_count: usize = @intCast(try bin.readU16At(data, fvar.offset + 12));
    const instance_size: usize = @intCast(try bin.readU16At(data, fvar.offset + 14));
    if (count_size_pairs != 2) return error.BadSfnt;
    if (axis_size < 20) return error.BadSfnt;

    // countSizePairs is part of the fvar header layout contract: exactly two
    // count/size pairs follow it, axisCount/axisSize and
    // instanceCount/instanceSize. Validate that contract together with the
    // table-local regions so malformed headers cannot reinterpret bytes from a
    // hypothetical alternate layout as variation metadata.
    if (axes_array_offset < 16 or axes_array_offset > fvar.length) return error.BadSfnt;
    if (axis_count > (fvar.length - axes_array_offset) / axis_size) return error.BadSfnt;
    const axes_bytes = axis_count * axis_size;
    const instances_offset = axes_array_offset + axes_bytes;
    const minimum_instance_size = 4 + axis_count * 4;
    if (instance_count != 0 and instance_size < minimum_instance_size) return error.BadSfnt;
    if (instance_size != 0 and instance_count > (fvar.length - instances_offset) / instance_size) return error.BadSfnt;

    return .{
        .axes_array_offset = axes_array_offset,
        .axis_count = axis_count,
        .axis_size = axis_size,
        .instance_count = instance_count,
        .instance_size = instance_size,
        .instances_array_offset = instances_offset,
        .postscript_name_id_offset = minimum_instance_size,
        .has_postscript_name_id = instance_size >= minimum_instance_size + 2,
    };
}

fn fvarAxisOffset(fvar: TableRecord, info: FvarInfo, axis_index: usize) usize {
    return fvar.offset + info.axes_array_offset + axis_index * info.axis_size;
}

fn fvarInstanceOffset(fvar: TableRecord, info: FvarInfo, instance_index: usize) usize {
    return fvar.offset + info.instances_array_offset + instance_index * info.instance_size;
}

const GvarGlyphTargetContext = struct {
    loca: TableRecord,
    glyf: TableRecord,
    index_to_loc_format: i16,
};

fn validateVariationDataTables(data: []const u8, glyph_count: u16, fvar: ?TableRecord, gvar: ?TableRecord, hvar: ?TableRecord, mvar: ?TableRecord, vvar: ?TableRecord, gvar_target_context: ?GvarGlyphTargetContext) FontError!void {
    if (gvar == null and hvar == null and mvar == null and vvar == null) return;
    const fvar_info = try readFvarInfo(data, fvar orelse return error.BadSfnt);
    if (gvar) |table| try validateGvarTable(data, table, glyph_count, fvar_info.axis_count, gvar_target_context);
    if (hvar) |table| try validateMetricVariationTable(data, table, fvar_info.axis_count, 20);
    if (vvar) |table| try validateMetricVariationTable(data, table, fvar_info.axis_count, 24);
    if (mvar) |table| try validateMvarTable(data, table, fvar_info.axis_count);
}

fn validateAvarTable(data: []const u8, avar: TableRecord, fvar: ?TableRecord) FontError!void {
    if (avar.length < 8) return error.BadSfnt;
    const major = try bin.readU16At(data, avar.offset);
    const minor = try bin.readU16At(data, avar.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const reserved = try bin.readU16At(data, avar.offset + 4);
    if (reserved != 0) return error.BadSfnt;

    const axis_count: usize = @intCast(try bin.readU16At(data, avar.offset + 6));
    if (fvar) |fvar_table| {
        const fvar_info = try readFvarInfo(data, fvar_table);
        if (axis_count != fvar_info.axis_count) return error.BadSfnt;
    } else if (axis_count != 0) {
        // avar segment maps are indexed only by the fvar axis order. Without
        // fvar, non-empty maps have no authoritative axis contract and should
        // not be accepted as parse-time variation metadata.
        return error.BadSfnt;
    }

    var offset: usize = 8;
    for (0..axis_count) |_| {
        if (offset + 2 > avar.length) return error.BadSfnt;
        const pair_count: usize = @intCast(try bin.readU16At(data, avar.offset + offset));
        offset += 2;
        const segment_bytes = pair_count * 4;
        if (segment_bytes > avar.length - offset) return error.BadSfnt;
        try validateAvarSegmentMap(data[avar.offset + offset .. avar.offset + offset + segment_bytes]);
        offset += segment_bytes;
    }
    if (offset != avar.length) return error.BadSfnt;
}

fn validateAvarSegmentMap(segment_data: []const u8) FontError!void {
    const pair_count = segment_data.len / 4;
    if (pair_count < 3) return error.BadSfnt;

    var has_minus_one = false;
    var has_zero = false;
    var has_plus_one = false;
    var previous_from: ?i16 = null;
    var previous_to: ?i16 = null;
    for (0..pair_count) |index| {
        const offset = index * 4;
        const from = try readI16FromSlice(segment_data, offset);
        const to = try readI16FromSlice(segment_data, offset + 2);
        if (!isAvarNormalizedValue(from) or !isAvarNormalizedValue(to)) return error.BadSfnt;
        if (previous_from) |last_from| {
            // Segment maps are piecewise-linear functions over normalized
            // coordinates. Requiring strict monotonicity for both axes catches
            // ambiguous duplicate breakpoints and reversed mappings at parse
            // time instead of allowing interpolation to depend on record order.
            if (from <= last_from) return error.BadSfnt;
        }
        if (previous_to) |last_to| {
            if (to < last_to) return error.BadSfnt;
        }
        if (from == avar_minus_one and to == avar_minus_one) has_minus_one = true;
        if (from == 0 and to == 0) has_zero = true;
        if (from == avar_plus_one and to == avar_plus_one) has_plus_one = true;
        previous_from = from;
        previous_to = to;
    }

    // OpenType requires every axis map to preserve the normalized endpoints and
    // default coordinate. Enforcing those anchors keeps malformed avar data from
    // shifting default instances or extrapolating beyond the design-space edge.
    if (!has_minus_one or !has_zero or !has_plus_one) return error.BadSfnt;
}

const avar_minus_one: i16 = -0x4000;
const avar_plus_one: i16 = 0x4000;

fn isAvarNormalizedValue(value: i16) bool {
    return value >= avar_minus_one and value <= avar_plus_one;
}

fn validateGvarTable(data: []const u8, gvar: TableRecord, glyph_count: u16, fvar_axis_count: usize, target_context: ?GvarGlyphTargetContext) FontError!void {
    if (gvar.length < 20) return error.BadSfnt;
    const major = try bin.readU16At(data, gvar.offset);
    const minor = try bin.readU16At(data, gvar.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const axis_count: usize = @intCast(try bin.readU16At(data, gvar.offset + 4));
    const shared_tuple_count: usize = @intCast(try bin.readU16At(data, gvar.offset + 6));
    const shared_tuple_offset: usize = @intCast(try bin.readU32At(data, gvar.offset + 8));
    const table_glyph_count = try bin.readU16At(data, gvar.offset + 12);
    const flags = try bin.readU16At(data, gvar.offset + 14);
    const glyph_data_offset: usize = @intCast(try bin.readU32At(data, gvar.offset + 16));

    if (axis_count != fvar_axis_count or table_glyph_count != glyph_count) return error.BadSfnt;
    if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;

    const offset_size: usize = if ((flags & 0x0001) != 0) 4 else 2;
    const offsets_len = (@as(usize, glyph_count) + 1) * offset_size;
    if (offsets_len > gvar.length - 20) return error.BadSfnt;

    // The glyph offset array is fixed immediately after the gvar header. The
    // glyph variation data block must start after that array; otherwise offset
    // entries can be reinterpreted as per-glyph tuple data.
    const minimum_glyph_data_offset = 20 + offsets_len;
    if (glyph_data_offset < minimum_glyph_data_offset or glyph_data_offset > gvar.length) return error.BadSfnt;

    const shared_tuples: []const u8 = if (shared_tuple_count != 0) blk: {
        if (shared_tuple_offset < minimum_glyph_data_offset or shared_tuple_offset > glyph_data_offset) return error.BadSfnt;
        const tuple_bytes = shared_tuple_count * axis_count * 2;
        if (tuple_bytes > glyph_data_offset - shared_tuple_offset) return error.BadSfnt;
        const tuple_data = data[gvar.offset + shared_tuple_offset .. gvar.offset + shared_tuple_offset + tuple_bytes];
        try validateGvarTupleCoordinateArray(tuple_data, axis_count * shared_tuple_count);
        break :blk tuple_data;
    } else &.{};

    const glyph_data_limit = gvar.length - glyph_data_offset;
    var previous = blk: {
        const raw_offset = try readGvarGlyphDataOffset(data, gvar.offset + 20, offset_size);
        const current = if (offset_size == 2) raw_offset * 2 else raw_offset;
        if (current > glyph_data_limit) return error.BadSfnt;
        break :blk current;
    };
    for (0..glyph_count) |glyph_index| {
        const offset_entry = gvar.offset + 20 + (@as(usize, glyph_index) + 1) * offset_size;
        const raw_offset = try readGvarGlyphDataOffset(data, offset_entry, offset_size);
        const current = if (offset_size == 2) raw_offset * 2 else raw_offset;
        if (current < previous or current > glyph_data_limit) return error.BadSfnt;
        if (current > previous) {
            const glyph_data_start = gvar.offset + glyph_data_offset + previous;
            const target_count = if (target_context) |context|
                try gvarGlyphTargetCount(data, context, @intCast(glyph_index))
            else
                null;
            try validateGvarGlyphVariationData(data[glyph_data_start .. gvar.offset + glyph_data_offset + current], axis_count, shared_tuple_count, shared_tuples, target_count);
        }
        previous = current;
    }
}

fn gvarGlyphTargetCount(data: []const u8, context: GvarGlyphTargetContext, glyph_id: glyph_mod.GlyphId) FontError!usize {
    const start = try glyfOffsetFromLoca(data, context.loca, context.index_to_loc_format, glyph_id);
    const end = try glyfOffsetFromLoca(data, context.loca, context.index_to_loc_format, @as(usize, glyph_id) + 1);
    if (end == start) return 4;
    if (end < start or end > context.glyf.length) return error.InvalidLoca;

    const glyph_data = data[context.glyf.offset + start .. context.glyf.offset + end];
    if (glyph_data.len < 10) return error.InvalidGlyph;
    const contour_count = try bin.readI16At(glyph_data, 0);
    return if (contour_count >= 0)
        (try simpleGlyphPointCount(glyph_data, @intCast(contour_count))) + 4
    else
        (try compoundGlyphComponentCount(glyph_data)) + 4;
}

fn simpleGlyphPointCount(glyph_data: []const u8, contour_count: u16) FontError!usize {
    if (contour_count == 0) return 0;
    const last_end_offset = 10 + (@as(usize, contour_count) - 1) * 2;
    if (last_end_offset + 2 > glyph_data.len) return error.InvalidGlyph;
    return @as(usize, try bin.readU16At(glyph_data, last_end_offset)) + 1;
}

fn compoundGlyphComponentCount(glyph_data: []const u8) FontError!usize {
    var offset: usize = 10; // numberOfContours + x/y bounds.
    var component_count: usize = 0;
    while (true) {
        if (offset + 4 > glyph_data.len) return error.InvalidGlyph;
        const flags = try bin.readU16At(glyph_data, offset);
        offset += 4;
        component_count += 1;

        const argument_bytes: usize = if ((flags & 0x0001) != 0) 4 else 2;
        if (argument_bytes > glyph_data.len - offset) return error.InvalidGlyph;
        offset += argument_bytes;

        const has_scale = (flags & 0x0008) != 0;
        const has_xy_scale = (flags & 0x0040) != 0;
        const has_two_by_two = (flags & 0x0080) != 0;
        const scale_bytes: usize = if (has_scale) 2 else if (has_xy_scale) 4 else if (has_two_by_two) 8 else 0;
        if (scale_bytes > glyph_data.len - offset) return error.InvalidGlyph;
        offset += scale_bytes;

        if ((flags & 0x0020) == 0) return component_count;
    }
}

const GvarPointSelection = union(enum) {
    all_points,
    explicit: struct {
        count: usize,
        max_point: usize,
    },
};

const GvarTupleHeader = struct {
    variation_data_size: usize,
    tuple_index: u16,
    header_size: usize,

    fn hasPrivatePointNumbers(self: GvarTupleHeader) bool {
        return (self.tuple_index & 0x2000) != 0;
    }
};

fn validateGvarGlyphVariationData(glyph_data: []const u8, axis_count: usize, shared_tuple_count: usize, shared_tuples: []const u8, target_count: ?usize) FontError!void {
    if (glyph_data.len < 4) return error.BadSfnt;
    const raw_tuple_count = try bin.readU16At(glyph_data, 0);
    if ((raw_tuple_count & 0x7000) != 0) return error.BadSfnt;
    const uses_shared_point_numbers = (raw_tuple_count & 0x8000) != 0;
    const tuple_count: usize = @intCast(raw_tuple_count & 0x0fff);
    if (tuple_count == 0) return error.BadSfnt;

    const data_offset: usize = @intCast(try bin.readU16At(glyph_data, 2));
    if (data_offset < 4 or data_offset > glyph_data.len) return error.BadSfnt;

    var header_cursor: usize = 4;
    var tuple_data_bytes: usize = 0;
    for (0..tuple_count) |_| {
        if (header_cursor > data_offset) return error.BadSfnt;
        const header = try readGvarTupleHeader(glyph_data, header_cursor, axis_count, shared_tuple_count, shared_tuples);
        if (header.header_size > data_offset - header_cursor) return error.BadSfnt;
        header_cursor += header.header_size;
        if (header.variation_data_size > glyph_data.len - data_offset - tuple_data_bytes) return error.BadSfnt;
        tuple_data_bytes += header.variation_data_size;
    }

    // The tuple headers are variable-width and the serialized data block is
    // addressed by dataOffset. Validate the whole header array first, then walk
    // the serialized payload in tuple order so one malformed late tuple cannot
    // hide behind an earlier valid one.
    var data_cursor = data_offset;
    const shared_points: ?GvarPointSelection = if (uses_shared_point_numbers)
        try validateGvarPackedPointNumbers(glyph_data, &data_cursor, glyph_data.len)
    else
        null;
    if (tuple_data_bytes > glyph_data.len - data_cursor) return error.BadSfnt;

    header_cursor = 4;
    var tuple_cursor = data_cursor;
    for (0..tuple_count) |_| {
        const header = try readGvarTupleHeader(glyph_data, header_cursor, axis_count, shared_tuple_count, shared_tuples);
        header_cursor += header.header_size;

        const tuple_end = tuple_cursor + header.variation_data_size;
        var payload_cursor = tuple_cursor;
        const points = if (header.hasPrivatePointNumbers())
            try validateGvarPackedPointNumbers(glyph_data, &payload_cursor, tuple_end)
        else
            shared_points orelse GvarPointSelection.all_points;
        const delta_count = try gvarDeltaCountForPointSelection(points, target_count);

        // Packed deltas do not carry their own logical count. Explicit point
        // lists provide it directly; all-points tuples get their count from the
        // paired glyf outline/component list plus four phantom points.
        if (delta_count) |count| {
            try validateGvarPackedDeltas(glyph_data, &payload_cursor, tuple_end, count);
            try validateGvarPackedDeltas(glyph_data, &payload_cursor, tuple_end, count);
            if (payload_cursor != tuple_end) return error.BadSfnt;
        }

        tuple_cursor = tuple_end;
    }
}

fn gvarDeltaCountForPointSelection(points: GvarPointSelection, target_count: ?usize) FontError!?usize {
    switch (points) {
        .all_points => return target_count,
        .explicit => |explicit| {
            if (target_count) |count| {
                if (explicit.count != 0 and explicit.max_point >= count) return error.BadSfnt;
            }
            return explicit.count;
        },
    }
}

fn readGvarTupleHeader(glyph_data: []const u8, offset: usize, axis_count: usize, shared_tuple_count: usize, shared_tuples: []const u8) FontError!GvarTupleHeader {
    if (offset > glyph_data.len or glyph_data.len - offset < 4) return error.BadSfnt;
    const variation_data_size: usize = @intCast(try bin.readU16At(glyph_data, offset));
    const tuple_index = try bin.readU16At(glyph_data, offset + 2);
    if ((tuple_index & 0x1000) != 0) return error.BadSfnt;

    const embedded_peak_tuple = (tuple_index & 0x8000) != 0;
    if (!embedded_peak_tuple and @as(usize, tuple_index & 0x0fff) >= shared_tuple_count) return error.BadSfnt;

    var header_size: usize = 4;
    if (embedded_peak_tuple) header_size += axis_count * 2;
    if ((tuple_index & 0x4000) != 0) header_size += axis_count * 4;
    if (header_size > glyph_data.len - offset) return error.BadSfnt;
    try validateGvarTupleHeaderCoordinates(glyph_data, offset, axis_count, tuple_index, shared_tuples, shared_tuple_count);

    return .{
        .variation_data_size = variation_data_size,
        .tuple_index = tuple_index,
        .header_size = header_size,
    };
}

fn validateGvarTupleCoordinateArray(tuple_data: []const u8, coordinate_count: usize) FontError!void {
    if (coordinate_count * 2 != tuple_data.len) return error.BadSfnt;
    for (0..coordinate_count) |index| {
        _ = try readGvarNormalizedCoordinate(tuple_data, index * 2);
    }
}

fn validateGvarTupleHeaderCoordinates(glyph_data: []const u8, offset: usize, axis_count: usize, tuple_index: u16, shared_tuples: []const u8, shared_tuple_count: usize) FontError!void {
    const embedded_peak_tuple = (tuple_index & 0x8000) != 0;
    const intermediate_region = (tuple_index & 0x4000) != 0;
    const embedded_peak_offset = offset + 4;
    const intermediate_start_offset = embedded_peak_offset + if (embedded_peak_tuple) axis_count * 2 else 0;
    const intermediate_end_offset = intermediate_start_offset + axis_count * 2;
    const shared_tuple_index: usize = @intCast(tuple_index & 0x0fff);
    const shared_peak_offset = shared_tuple_index * axis_count * 2;

    if (!embedded_peak_tuple and (shared_tuple_index >= shared_tuple_count or shared_peak_offset + axis_count * 2 > shared_tuples.len)) return error.BadSfnt;

    for (0..axis_count) |axis_index| {
        const peak = if (embedded_peak_tuple)
            try readGvarNormalizedCoordinate(glyph_data, embedded_peak_offset + axis_index * 2)
        else
            try readGvarNormalizedCoordinate(shared_tuples, shared_peak_offset + axis_index * 2);

        if (intermediate_region) {
            const start = try readGvarNormalizedCoordinate(glyph_data, intermediate_start_offset + axis_index * 2);
            const end = try readGvarNormalizedCoordinate(glyph_data, intermediate_end_offset + axis_index * 2);
            try validateGvarIntermediateAxis(start, peak, end);
        }
    }
}

fn readGvarNormalizedCoordinate(data: []const u8, offset: usize) FontError!i16 {
    const value = bin.readI16At(data, offset) catch return error.BadSfnt;
    // Tuple records use F2DOT14 values, whose bit pattern can represent
    // nearly +/-2.0. In gvar they are normalized design-space coordinates and
    // must stay inside the [-1, +1] variation-space cube.
    if (value < -0x4000 or value > 0x4000) return error.BadSfnt;
    return value;
}

fn validateGvarIntermediateAxis(start: i16, peak: i16, end: i16) FontError!void {
    // The interpolation scalar treats invalid axis triples as "ignored" in the
    // spec pseudo-code, but accepting such data at parse time can hide a tuple
    // region that never behaves as authored. Keep intermediate regions ordered
    // and on one side of the default point unless a zero peak deliberately
    // marks this axis as non-participating.
    if (start > peak or peak > end) return error.BadSfnt;
    if (start < 0 and end > 0 and peak != 0) return error.BadSfnt;
}

fn validateGvarPackedPointNumbers(data: []const u8, cursor: *usize, limit: usize) FontError!GvarPointSelection {
    if (cursor.* >= limit) return error.BadSfnt;
    const first = data[cursor.*];
    cursor.* += 1;
    if (first == 0) return .all_points;

    const point_count: usize = if ((first & 0x80) == 0) first else blk: {
        if (cursor.* >= limit) return error.BadSfnt;
        const second = data[cursor.*];
        cursor.* += 1;
        break :blk (@as(usize, first & 0x7f) << 8) | second;
    };

    var remaining = point_count;
    var last_point: usize = 0;
    var saw_point = false;
    while (remaining != 0) {
        if (cursor.* >= limit) return error.BadSfnt;
        const control = data[cursor.*];
        cursor.* += 1;
        const run_count = @as(usize, control & 0x7f) + 1;
        if (run_count > remaining) return error.BadSfnt;
        const words = (control & 0x80) != 0;
        for (0..run_count) |_| {
            const delta: usize = if (words) blk: {
                if (cursor.* > limit or 2 > limit - cursor.*) return error.BadSfnt;
                const value = try bin.readU16At(data, cursor.*);
                cursor.* += 2;
                break :blk value;
            } else blk: {
                if (cursor.* >= limit) return error.BadSfnt;
                const value = data[cursor.*];
                cursor.* += 1;
                break :blk value;
            };
            if (delta > std.math.maxInt(usize) - last_point) return error.BadSfnt;
            last_point += delta;
            saw_point = true;
        }
        remaining -= run_count;
    }

    return .{ .explicit = .{
        .count = point_count,
        .max_point = if (saw_point) last_point else 0,
    } };
}

fn validateGvarPackedDeltas(data: []const u8, cursor: *usize, limit: usize, delta_count: usize) FontError!void {
    var remaining = delta_count;
    while (remaining != 0) {
        if (cursor.* >= limit) return error.BadSfnt;
        const control = data[cursor.*];
        cursor.* += 1;
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > remaining) return error.BadSfnt;

        const run_bytes: usize = if ((control & 0x80) != 0)
            0
        else if ((control & 0x40) != 0)
            run_count * 2
        else
            run_count;
        if (run_bytes > limit - cursor.*) return error.BadSfnt;
        cursor.* += run_bytes;
        remaining -= run_count;
    }
}

fn readGvarGlyphDataOffset(data: []const u8, offset: usize, size: usize) FontError!usize {
    return switch (size) {
        2 => try bin.readU16At(data, offset),
        4 => try bin.readU32At(data, offset),
        else => error.BadSfnt,
    };
}

fn validateMetricVariationTable(data: []const u8, table: TableRecord, fvar_axis_count: usize, minimum_length: usize) FontError!void {
    if (table.length < minimum_length) return error.BadSfnt;
    const major = try bin.readU16At(data, table.offset);
    const minor = try bin.readU16At(data, table.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const store_offset: usize = @intCast(try bin.readU32At(data, table.offset + 4));
    _ = try validateItemVariationStore(data, table, store_offset, fvar_axis_count, minimum_length);
}

fn validateMvarTable(data: []const u8, mvar: TableRecord, fvar_axis_count: usize) FontError!void {
    if (mvar.length < 12) return error.BadSfnt;
    const major = try bin.readU16At(data, mvar.offset);
    const minor = try bin.readU16At(data, mvar.offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const reserved = try bin.readU16At(data, mvar.offset + 4);
    const value_record_size: usize = @intCast(try bin.readU16At(data, mvar.offset + 6));
    const value_record_count: usize = @intCast(try bin.readU16At(data, mvar.offset + 8));
    const store_offset: usize = @intCast(try bin.readU16At(data, mvar.offset + 10));
    if (reserved != 0 or value_record_size < 8) return error.BadSfnt;
    if (value_record_count > (mvar.length - 12) / value_record_size) return error.BadSfnt;

    const records_end = 12 + value_record_count * value_record_size;
    const store_info = try validateItemVariationStore(data, mvar, store_offset, fvar_axis_count, records_end);
    for (0..value_record_count) |index| {
        const record = mvar.offset + 12 + index * value_record_size;
        const outer_index: usize = @intCast(try bin.readU16At(data, record + 4));
        const inner_index: usize = @intCast(try bin.readU16At(data, record + 6));
        if (outer_index >= store_info.item_data_count) return error.BadSfnt;
        const item_count = try itemVariationDataItemCount(data, mvar, store_offset, outer_index);
        if (inner_index >= item_count) return error.BadSfnt;
    }
}

const ItemVariationStoreInfo = struct {
    item_data_count: usize,
    end_offset: usize,
};

const VariationRegionListInfo = struct {
    region_count: usize,
    end_offset: usize,
};

const ItemVariationDataInfo = struct {
    item_count: usize,
    end_offset: usize,
};

fn validateItemVariationStore(data: []const u8, table: TableRecord, store_offset: usize, fvar_axis_count: usize, minimum_store_offset: usize) FontError!ItemVariationStoreInfo {
    if (store_offset < minimum_store_offset or store_offset > table.length or table.length - store_offset < 8) return error.BadSfnt;
    const store = table.offset + store_offset;
    const format = try bin.readU16At(data, store);
    if (format != 1) return error.BadSfnt;
    const region_list_offset: usize = @intCast(try bin.readU32At(data, store + 2));
    const item_data_count: usize = @intCast(try bin.readU16At(data, store + 6));
    const offsets_array_end = 8 + item_data_count * 4;
    if (offsets_array_end > table.length - store_offset) return error.BadSfnt;

    const region_info = try validateVariationRegionList(data, table, store_offset, region_list_offset, fvar_axis_count, offsets_array_end);
    var end_offset = @max(offsets_array_end, region_info.end_offset);
    for (0..item_data_count) |index| {
        const item_data_offset: usize = @intCast(try bin.readU32At(data, store + 8 + index * 4));
        if (item_data_offset < offsets_array_end) return error.BadSfnt;
        const item_info = try validateItemVariationData(data, table, store_offset, item_data_offset, region_info.region_count);
        end_offset = @max(end_offset, item_info.end_offset);
    }
    return .{ .item_data_count = item_data_count, .end_offset = store_offset + end_offset };
}

fn validateVariationRegionList(data: []const u8, table: TableRecord, store_offset: usize, region_list_offset: usize, fvar_axis_count: usize, minimum_region_offset: usize) FontError!VariationRegionListInfo {
    if (region_list_offset < minimum_region_offset or region_list_offset > table.length - store_offset or table.length - store_offset - region_list_offset < 4) return error.BadSfnt;
    const region_list = table.offset + store_offset + region_list_offset;
    const axis_count: usize = @intCast(try bin.readU16At(data, region_list));
    const region_count: usize = @intCast(try bin.readU16At(data, region_list + 2));
    if (axis_count != fvar_axis_count) return error.BadSfnt;
    const region_bytes = region_count * axis_count * 6;
    if (region_bytes > table.length - store_offset - region_list_offset - 4) return error.BadSfnt;
    return .{ .region_count = region_count, .end_offset = region_list_offset + 4 + region_bytes };
}

fn validateItemVariationData(data: []const u8, table: TableRecord, store_offset: usize, item_data_offset: usize, region_count: usize) FontError!ItemVariationDataInfo {
    if (item_data_offset > table.length - store_offset or table.length - store_offset - item_data_offset < 6) return error.BadSfnt;
    const item_data = table.offset + store_offset + item_data_offset;
    const item_count: usize = @intCast(try bin.readU16At(data, item_data));
    const raw_word_delta_count = try bin.readU16At(data, item_data + 2);
    const region_index_count: usize = @intCast(try bin.readU16At(data, item_data + 4));
    const word_delta_count: usize = @intCast(raw_word_delta_count & 0x7fff);
    const long_words = (raw_word_delta_count & 0x8000) != 0;
    if (word_delta_count > region_index_count) return error.BadSfnt;
    if (region_index_count > region_count) return error.BadSfnt;

    const region_indexes_offset = item_data + 6;
    const region_indexes_bytes = region_index_count * 2;
    if (region_indexes_bytes > table.length - store_offset - item_data_offset - 6) return error.BadSfnt;
    for (0..region_index_count) |index| {
        const region_index = try bin.readU16At(data, region_indexes_offset + index * 2);
        if (region_index >= region_count) return error.BadSfnt;
    }

    const remaining = table.length - store_offset - item_data_offset - 6 - region_indexes_bytes;
    const narrow_delta_count = region_index_count - word_delta_count;
    const row_size = if (long_words)
        word_delta_count * 4 + narrow_delta_count * 2
    else
        word_delta_count * 2 + narrow_delta_count;
    if (row_size != 0 and item_count > remaining / row_size) return error.BadSfnt;
    if (row_size == 0 and item_count != 0) return error.BadSfnt;
    return .{ .item_count = item_count, .end_offset = item_data_offset + 6 + region_indexes_bytes + item_count * row_size };
}

fn itemVariationDataItemCount(data: []const u8, table: TableRecord, store_offset: usize, outer_index: usize) FontError!usize {
    const store = table.offset + store_offset;
    const item_data_count: usize = @intCast(try bin.readU16At(data, store + 6));
    if (outer_index >= item_data_count) return error.BadSfnt;
    const item_data_offset: usize = @intCast(try bin.readU32At(data, store + 8 + outer_index * 4));
    if (item_data_offset > table.length - store_offset or table.length - store_offset - item_data_offset < 2) return error.BadSfnt;
    return try bin.readU16At(data, table.offset + store_offset + item_data_offset);
}

fn mapAvarSegment(segment_data: []const u8, normalized: f32) FontError!f32 {
    const pair_count = segment_data.len / 4;
    if (pair_count == 0) return normalized;
    var previous_from = f2dot14(try readI16FromSlice(segment_data, 0));
    var previous_to = f2dot14(try readI16FromSlice(segment_data, 2));
    if (normalized <= previous_from) return previous_to;
    for (1..pair_count) |index| {
        const offset = index * 4;
        const current_from = f2dot14(try readI16FromSlice(segment_data, offset));
        const current_to = f2dot14(try readI16FromSlice(segment_data, offset + 2));
        if (normalized <= current_from) {
            if (current_from == previous_from) return current_to;
            const t = (normalized - previous_from) / (current_from - previous_from);
            return previous_to + t * (current_to - previous_to);
        }
        previous_from = current_from;
        previous_to = current_to;
    }
    return previous_to;
}

const SvgDocumentList = struct {
    start: usize,
    length: usize,
    entry_count: usize,
    records_start: usize,
    document_data_start: usize,
};

const SvgDocumentRecord = struct {
    start_glyph_id: glyph_mod.GlyphId,
    end_glyph_id: glyph_mod.GlyphId,
    document_offset: usize,
    document_length: usize,
};

const SvgDocumentByteRange = struct {
    start: usize,
    end: usize,
};

const gzip_magic = [_]u8{ 0x1f, 0x8b };
const gzip_deflate_method = 8;

fn svgDocumentList(data: []const u8, svg: TableRecord) FontError!SvgDocumentList {
    if (svg.length < 10) return error.BadSfnt;
    const version = try bin.readU16At(data, svg.offset);
    if (version != 0) return error.BadSfnt;
    const document_list_offset: usize = @intCast(try bin.readU32At(data, svg.offset + 2));
    const reserved = try bin.readU32At(data, svg.offset + 6);
    // The final four bytes of the SVG table header are reserved and must be
    // zero. Treating them as padding rather than validating them would make a
    // malformed header indistinguishable from future incompatible semantics.
    if (reserved != 0) return error.BadSfnt;
    // Offsets in the SVG table are relative to the SVG table or to the
    // SVGDocumentList. Keep both child regions past their fixed metadata so
    // malformed fonts cannot reinterpret the header or records as XML data.
    if (document_list_offset < 10) return error.BadSfnt;
    if (document_list_offset > svg.length or 2 > svg.length - document_list_offset) return error.BadSfnt;

    const list_start = svg.offset + document_list_offset;
    const list_length = svg.length - document_list_offset;
    const entry_count = try bin.readU16At(data, list_start);
    const records_start = list_start + 2;
    const record_bytes = @as(usize, entry_count) * 12;
    if (record_bytes > list_length - 2) return error.BadSfnt;
    return .{
        .start = list_start,
        .length = list_length,
        .entry_count = entry_count,
        .records_start = records_start,
        .document_data_start = 2 + record_bytes,
    };
}

fn readSvgDocumentRecord(data: []const u8, offset: usize) FontError!SvgDocumentRecord {
    return .{
        .start_glyph_id = try bin.readU16At(data, offset),
        .end_glyph_id = try bin.readU16At(data, offset + 2),
        .document_offset = @intCast(try bin.readU32At(data, offset + 4)),
        .document_length = @intCast(try bin.readU32At(data, offset + 8)),
    };
}

fn validateSvgDocumentRecord(record: SvgDocumentRecord, document_list: SvgDocumentList, glyph_count: u16, previous_end_glyph_id: *?glyph_mod.GlyphId) FontError!void {
    // SVGDocumentRecords are global glyph metadata, so every advertised
    // inclusive range must fit maxp.numGlyphs even if callers never request
    // that document. Otherwise an accepted font can later surface a color
    // glyph id that has no metrics, outline, or bitmap contract.
    if (record.end_glyph_id < record.start_glyph_id) return error.BadSfnt;
    try validateGlyphIdInMaxp(record.start_glyph_id, glyph_count);
    try validateGlyphIdInMaxp(record.end_glyph_id, glyph_count);

    // The OpenType SVG document list is a sorted search table over glyph-id
    // ranges. Enforcing monotonic, disjoint ranges at parse time avoids
    // ambiguous ownership when two records could both describe the same glyph
    // and keeps later lookups independent of linear-scan accident.
    if (previous_end_glyph_id.*) |previous_end| {
        if (record.start_glyph_id <= previous_end) return error.BadSfnt;
    }
    previous_end_glyph_id.* = record.end_glyph_id;

    if (record.document_offset < document_list.document_data_start) return error.BadSfnt;
    if (record.document_length == 0) return error.BadSfnt;
    if (record.document_offset > document_list.length or record.document_length > document_list.length - record.document_offset) return error.BadSfnt;
}

fn validateSvgDocumentByteRanges(ranges: []SvgDocumentByteRange) FontError!void {
    if (ranges.len < 2) return;

    std.mem.sort(SvgDocumentByteRange, ranges, {}, struct {
        fn lessThan(_: void, lhs: SvgDocumentByteRange, rhs: SvgDocumentByteRange) bool {
            if (lhs.start == rhs.start) return lhs.end < rhs.end;
            return lhs.start < rhs.start;
        }
    }.lessThan);

    for (ranges[1..], 1..) |range, index| {
        const previous = ranges[index - 1];
        if (range.start < previous.end) {
            // Multiple glyph ranges may intentionally reference the exact same
            // SVG document bytes.  Partial overlaps, however, make one XML
            // document borrow bytes from another and leave later renderers with
            // no deterministic document boundary, so reject them at parse time.
            if (range.start != previous.start or range.end != previous.end) return error.BadSfnt;
        }
    }
}

fn validateSvgDocumentPayload(allocator: std.mem.Allocator, document: []const u8) FontError!void {
    const payload = stripUtf8Bom(document);
    if (payload.len == 0) return error.BadSfnt;
    if (isGzipSvgDocument(payload)) return;

    var stack = std.ArrayList([]const u8).empty;
    defer stack.deinit(allocator);

    var cursor = try skipXmlBeforeRootTrivia(payload, 0);
    var root_seen = false;
    while (cursor < payload.len) {
        if (payload[cursor] != '<') {
            const next_tag = std.mem.indexOfScalarPos(u8, payload, cursor, '<') orelse payload.len;
            if (stack.items.len == 0 and !isXmlWhitespaceOnly(payload[cursor..next_tag])) return error.BadSfnt;
            cursor = next_tag;
            continue;
        }

        if (std.mem.startsWith(u8, payload[cursor..], "<!--")) {
            cursor = (try xmlCommentEnd(payload, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<?")) {
            cursor = (try xmlProcessingInstructionEnd(payload, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<![CDATA[")) {
            if (stack.items.len == 0) return error.BadSfnt;
            cursor = (try xmlCdataEnd(payload, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<!DOCTYPE")) {
            // A DOCTYPE declaration is only part of the XML prolog. Accepting
            // it after the root has started would let a second top-level
            // construct hide behind markup the renderer never expects.
            if (root_seen or stack.items.len != 0) return error.BadSfnt;
            cursor = (try xmlDeclarationEnd(payload, cursor)) + 1;
            cursor = try skipXmlBeforeRootTrivia(payload, cursor);
            continue;
        }
        if (std.mem.startsWith(u8, payload[cursor..], "<!")) return error.BadSfnt;

        const tag_end = try xmlTagEnd(payload, cursor);
        const closing = cursor + 1 < payload.len and payload[cursor + 1] == '/';
        const name = xmlTagName(payload, cursor, tag_end, closing) orelse return error.BadSfnt;
        if (closing) {
            if (stack.items.len == 0) return error.BadSfnt;
            const active_name = stack.items[stack.items.len - 1];
            stack.items.len -= 1;
            if (!std.mem.eql(u8, active_name, name)) return error.BadSfnt;
            cursor = tag_end + 1;
            if (stack.items.len == 0) {
                cursor = try skipXmlTrailingTrivia(payload, cursor);
                if (cursor != payload.len) return error.BadSfnt;
                return;
            }
            continue;
        }

        if (stack.items.len == 0) {
            if (root_seen) return error.BadSfnt;
            if (!std.mem.eql(u8, xmlLocalName(name), "svg")) return error.BadSfnt;
            root_seen = true;
        }
        if (xmlTagSelfCloses(payload, cursor, tag_end)) {
            cursor = tag_end + 1;
            if (stack.items.len == 0) {
                cursor = try skipXmlTrailingTrivia(payload, cursor);
                if (cursor != payload.len) return error.BadSfnt;
                return;
            }
        } else {
            try stack.append(allocator, name);
            cursor = tag_end + 1;
        }
    }

    if (!root_seen or stack.items.len != 0) return error.BadSfnt;
}

fn stripUtf8Bom(document: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, document, "\xef\xbb\xbf")) document[3..] else document;
}

fn isGzipSvgDocument(document: []const u8) bool {
    if (!std.mem.startsWith(u8, document, &gzip_magic)) return false;
    // OpenType SVG documents may be gzip-compressed. The renderer currently
    // only consumes cleartext XML, so parse-time validation merely recognizes a
    // well-formed gzip header prefix and leaves decompression support to a
    // future renderer path instead of rejecting otherwise valid SFNT metadata.
    return document.len >= 10 and document[2] == gzip_deflate_method;
}

fn skipXmlBeforeRootTrivia(document: []const u8, start: usize) FontError!usize {
    var cursor = start;
    while (cursor < document.len) {
        cursor = skipXmlWhitespace(document, cursor);
        if (std.mem.startsWith(u8, document[cursor..], "<?")) {
            cursor = (try xmlProcessingInstructionEnd(document, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, document[cursor..], "<!--")) {
            cursor = (try xmlCommentEnd(document, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, document[cursor..], "<!DOCTYPE")) {
            cursor = (try xmlDeclarationEnd(document, cursor)) + 1;
            continue;
        }
        return cursor;
    }
    return cursor;
}

fn skipXmlTrailingTrivia(document: []const u8, start: usize) FontError!usize {
    var cursor = start;
    while (cursor < document.len) {
        cursor = skipXmlWhitespace(document, cursor);
        if (std.mem.startsWith(u8, document[cursor..], "<?")) {
            cursor = (try xmlProcessingInstructionEnd(document, cursor)) + 1;
            continue;
        }
        if (std.mem.startsWith(u8, document[cursor..], "<!--")) {
            cursor = (try xmlCommentEnd(document, cursor)) + 1;
            continue;
        }
        return cursor;
    }
    return cursor;
}

fn skipXmlWhitespace(document: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < document.len and isXmlWhitespace(document[cursor])) : (cursor += 1) {}
    return cursor;
}

fn isXmlWhitespaceOnly(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (!isXmlWhitespace(byte)) return false;
    }
    return true;
}

fn isXmlWhitespace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

fn xmlProcessingInstructionEnd(document: []const u8, start: usize) FontError!usize {
    return std.mem.indexOfPos(u8, document, start + 2, "?>") orelse error.BadSfnt;
}

fn xmlCommentEnd(document: []const u8, start: usize) FontError!usize {
    return (std.mem.indexOfPos(u8, document, start + 4, "-->") orelse return error.BadSfnt) + 2;
}

fn xmlCdataEnd(document: []const u8, start: usize) FontError!usize {
    return (std.mem.indexOfPos(u8, document, start + "<![CDATA[".len, "]]>") orelse return error.BadSfnt) + 2;
}

fn xmlDeclarationEnd(document: []const u8, start: usize) FontError!usize {
    var cursor = start + 2;
    var quote: ?u8 = null;
    var bracket_depth: usize = 0;
    while (cursor < document.len) : (cursor += 1) {
        const byte = document[cursor];
        if (quote) |active_quote| {
            if (byte == active_quote) quote = null;
            continue;
        }
        switch (byte) {
            '"', '\'' => quote = byte,
            '[' => bracket_depth += 1,
            ']' => if (bracket_depth != 0) {
                bracket_depth -= 1;
            },
            '>' => if (bracket_depth == 0) return cursor,
            else => {},
        }
    }
    return error.BadSfnt;
}

fn xmlTagEnd(document: []const u8, start: usize) FontError!usize {
    var cursor = start + 1;
    var quote: ?u8 = null;
    while (cursor < document.len) : (cursor += 1) {
        const byte = document[cursor];
        if (quote) |active_quote| {
            if (byte == active_quote) quote = null;
            continue;
        }
        switch (byte) {
            '"', '\'' => quote = byte,
            '>' => return cursor,
            else => {},
        }
    }
    return error.BadSfnt;
}

fn xmlTagName(document: []const u8, tag_start: usize, tag_end: usize, closing: bool) ?[]const u8 {
    var cursor = tag_start + 1;
    if (closing) cursor += 1;
    if (cursor >= tag_end or !isXmlNameByte(document[cursor])) return null;
    const name_start = cursor;
    while (cursor < tag_end and isXmlNameByte(document[cursor])) : (cursor += 1) {}
    return document[name_start..cursor];
}

fn xmlTagSelfCloses(document: []const u8, tag_start: usize, tag_end: usize) bool {
    var cursor = tag_end;
    while (cursor > tag_start + 1) {
        cursor -= 1;
        if (isXmlWhitespace(document[cursor])) continue;
        return document[cursor] == '/';
    }
    return false;
}

fn xmlLocalName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, name, ':')) |colon| name[colon + 1 ..] else name;
}

fn isXmlNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-' or byte == ':' or byte == '.';
}

fn validateSvgGlyphBounds(allocator: std.mem.Allocator, data: []const u8, svg: TableRecord, glyph_count: u16) FontError!void {
    const document_list = try svgDocumentList(data, svg);

    const byte_ranges = try allocator.alloc(SvgDocumentByteRange, document_list.entry_count);
    defer allocator.free(byte_ranges);

    var previous_end_glyph_id: ?glyph_mod.GlyphId = null;
    for (0..document_list.entry_count) |index| {
        const record = try readSvgDocumentRecord(data, document_list.records_start + index * 12);
        try validateSvgDocumentRecord(record, document_list, glyph_count, &previous_end_glyph_id);
        byte_ranges[index] = .{
            .start = record.document_offset,
            .end = record.document_offset + record.document_length,
        };
        const document_start = document_list.start + record.document_offset;
        try validateSvgDocumentPayload(allocator, data[document_start .. document_start + record.document_length]);
    }
    try validateSvgDocumentByteRanges(byte_ranges);
}

fn validateCpalPaletteEntries(data: []const u8, cpal: TableRecord) FontError!u16 {
    if (cpal.length < 12) return error.BadSfnt;
    const version = try bin.readU16At(data, cpal.offset);
    if (version > 1) return error.BadSfnt;
    const palette_entries = try bin.readU16At(data, cpal.offset + 2);
    const palette_count = try bin.readU16At(data, cpal.offset + 4);
    const color_count = try bin.readU16At(data, cpal.offset + 6);
    const color_records_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + 8));

    const palette_indices_len = @as(usize, palette_count) * 2;
    if (palette_indices_len > cpal.length - 12) return error.BadSfnt;
    const version_0_header_len = 12 + palette_indices_len;
    const header_len = if (version == 1) blk: {
        if (12 > cpal.length - version_0_header_len) return error.BadSfnt;
        const palette_types_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len));
        const palette_labels_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len + 4));
        const palette_entry_labels_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len + 8));
        const extended_header_len = version_0_header_len + 12;
        try validateCpalPaletteTypeValues(data, cpal, extended_header_len, palette_types_offset, palette_count);
        try validateCpalOptionalArray(cpal, extended_header_len, palette_labels_offset, palette_count, 2);
        try validateCpalOptionalArray(cpal, extended_header_len, palette_entry_labels_offset, palette_entries, 2);
        break :blk extended_header_len;
    } else version_0_header_len;

    // The palette-start indices and v1 extension offsets are declared metadata,
    // not color payload. Keeping ColorRecordsArray after that header prevents a
    // malformed CPAL table from reinterpreting palette indices or optional name
    // arrays as BGRA color records during parse-time COLR validation.
    if (color_records_offset < header_len or color_records_offset > cpal.length) return error.BadSfnt;
    if (@as(usize, color_count) > (cpal.length - color_records_offset) / 4) return error.BadSfnt;

    if (version == 1) {
        const palette_types_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len));
        const palette_labels_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len + 4));
        const palette_entry_labels_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len + 8));
        try validateCpalV1PayloadRanges(
            cpal,
            header_len,
            palette_types_offset,
            palette_labels_offset,
            palette_entry_labels_offset,
            palette_count,
            palette_entries,
            color_records_offset,
            color_count,
        );
    }

    try validateCpalPaletteSlices(data, cpal, palette_count, palette_entries, color_count);
    return palette_entries;
}

fn validateCpalPaletteSlices(data: []const u8, cpal: TableRecord, palette_count: u16, palette_entries: u16, color_count: u16) FontError!void {
    var previous_first_color_index: ?usize = null;
    var previous_palette_end: ?usize = null;

    for (0..palette_count) |palette_index| {
        const first_color_index: usize = @intCast(try bin.readU16At(data, cpal.offset + 12 + palette_index * 2));
        const entries: usize = @intCast(palette_entries);
        const colors: usize = @intCast(color_count);
        if (first_color_index > colors or entries > colors - first_color_index) return error.BadSfnt;

        if (previous_first_color_index) |previous_first| {
            // CPAL palettes are fixed-size slices into ColorRecordsArray. Keep
            // the declared firstColorIndex array canonical and non-overlapping
            // so palette lookup cannot depend on duplicated or reordered
            // slices that reinterpret the same BGRA records as distinct
            // palettes.
            if (first_color_index <= previous_first) return error.BadSfnt;
            if (first_color_index < previous_palette_end.?) return error.BadSfnt;
        }

        previous_first_color_index = first_color_index;
        previous_palette_end = first_color_index + entries;
    }
}

fn validateCpalOptionalArray(cpal: TableRecord, header_len: usize, offset: usize, count: usize, item_size: usize) FontError!void {
    if (offset == 0) return;
    if (offset < header_len or offset > cpal.length) return error.BadSfnt;
    if (count > (cpal.length - offset) / item_size) return error.BadSfnt;
}

const CpalPayloadRange = struct {
    start: usize,
    end: usize,
};

fn validateCpalV1PayloadRanges(
    cpal: TableRecord,
    header_len: usize,
    palette_types_offset: usize,
    palette_labels_offset: usize,
    palette_entry_labels_offset: usize,
    palette_count: usize,
    palette_entries: usize,
    color_records_offset: usize,
    color_count: usize,
) FontError!void {
    var ranges: [4]CpalPayloadRange = undefined;
    var range_count: usize = 0;

    try appendCpalPayloadRange(&ranges, &range_count, cpal, header_len, palette_types_offset, palette_count, 4);
    try appendCpalPayloadRange(&ranges, &range_count, cpal, header_len, palette_labels_offset, palette_count, 2);
    try appendCpalPayloadRange(&ranges, &range_count, cpal, header_len, palette_entry_labels_offset, palette_entries, 2);
    try appendCpalPayloadRange(&ranges, &range_count, cpal, header_len, color_records_offset, color_count, 4);

    for (ranges[0..range_count], 0..) |lhs, lhs_index| {
        for (ranges[lhs_index + 1 .. range_count]) |rhs| {
            // CPAL v1 offsets name independently typed arrays. Even when two
            // arrays have compatible element widths, sharing bytes would let a
            // palette label, palette-type flag, or BGRA color record be
            // reinterpreted as a different payload later in the pipeline.
            if (cpalPayloadRangesOverlap(lhs, rhs)) return error.BadSfnt;
        }
    }
}

fn appendCpalPayloadRange(
    ranges: *[4]CpalPayloadRange,
    range_count: *usize,
    cpal: TableRecord,
    header_len: usize,
    offset: usize,
    count: usize,
    item_size: usize,
) FontError!void {
    if (offset == 0) return;
    try validateCpalOptionalArray(cpal, header_len, offset, count, item_size);
    const byte_len = count * item_size;
    ranges[range_count.*] = .{ .start = offset, .end = offset + byte_len };
    range_count.* += 1;
}

fn cpalPayloadRangesOverlap(lhs: CpalPayloadRange, rhs: CpalPayloadRange) bool {
    return lhs.start < rhs.end and rhs.start < lhs.end;
}

const cpal_known_palette_type_mask: u32 = 0x0000_0003;

fn validateCpalPaletteTypeValues(data: []const u8, cpal: TableRecord, header_len: usize, offset: usize, palette_count: usize) FontError!void {
    if (offset == 0) return;
    try validateCpalOptionalArray(cpal, header_len, offset, palette_count, 4);

    // CPAL v1 palette type values are bitsets whose currently assigned bits
    // only describe light/dark-background suitability.  Rejecting reserved bits
    // at parse time keeps future flags from being silently misinterpreted by
    // palette selection code that only understands today's two-bit contract.
    for (0..palette_count) |palette_index| {
        const palette_type = try bin.readU32At(data, cpal.offset + offset + palette_index * 4);
        if (palette_type & ~cpal_known_palette_type_mask != 0) return error.BadSfnt;
    }
}

fn validateCpalNameReferences(data: []const u8, cpal: TableRecord, name: ?TableRecord) FontError!void {
    if (cpal.length < 12) return error.BadSfnt;
    const version = try bin.readU16At(data, cpal.offset);
    if (version == 0) return;
    if (version > 1) return error.BadSfnt;

    const palette_entries: usize = @intCast(try bin.readU16At(data, cpal.offset + 2));
    const palette_count: usize = @intCast(try bin.readU16At(data, cpal.offset + 4));
    const palette_indices_len = palette_count * 2;
    if (palette_indices_len > cpal.length - 12) return error.BadSfnt;
    const version_0_header_len = 12 + palette_indices_len;
    if (12 > cpal.length - version_0_header_len) return error.BadSfnt;

    const palette_labels_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len + 4));
    const palette_entry_labels_offset: usize = @intCast(try bin.readU32At(data, cpal.offset + version_0_header_len + 8));
    if (palette_labels_offset == 0 and palette_entry_labels_offset == 0) return;

    var name_index_storage: NameIdIndex = undefined;
    const name_index: ?*const NameIdIndex = if (name) |name_table| blk: {
        name_index_storage = try readNameIdIndex(data, name_table);
        break :blk &name_index_storage;
    } else null;

    // CPAL v1 label arrays contain optional name IDs, not raw strings.  Check
    // them while parsing so palette UIs never expose a dangling or undecodable
    // localized label after the font has otherwise been accepted.
    const extended_header_len = version_0_header_len + 12;
    try validateCpalNameIdArray(data, cpal, extended_header_len, palette_labels_offset, palette_count, name_index);
    try validateCpalNameIdArray(data, cpal, extended_header_len, palette_entry_labels_offset, palette_entries, name_index);
}

fn validateCpalNameIdArray(data: []const u8, cpal: TableRecord, header_len: usize, offset: usize, count: usize, name_index: ?*const NameIdIndex) FontError!void {
    if (offset == 0) return;
    try validateCpalOptionalArray(cpal, header_len, offset, count, 2);
    for (0..count) |index| {
        const name_id = try bin.readU16At(data, cpal.offset + offset + index * 2);
        try validateOptionalNameIdReference(name_index, name_id);
    }
}

fn validateColrPaletteBounds(data: []const u8, colr: TableRecord, cpal: ?TableRecord) FontError!void {
    if (colr.length < 2) return error.BadSfnt;
    const cpal_palette_entries = if (cpal) |cpal_table| try validateCpalPaletteEntries(data, cpal_table) else null;
    const version = try bin.readU16At(data, colr.offset);
    switch (version) {
        0 => try validateColrV0PaletteBounds(data, colr, cpal_palette_entries),
        1 => try validateColrV1PaletteBounds(data, colr, cpal_palette_entries),
        else => {},
    }
}

fn validateColrPaletteIndexBounds(palette_index: u16, cpal_palette_entries: ?u16) FontError!void {
    const palette_entries = cpal_palette_entries orelse return error.BadSfnt;
    if (palette_index >= palette_entries) return error.BadSfnt;
}

fn validateColrV0PaletteBounds(data: []const u8, colr: TableRecord, cpal_palette_entries: ?u16) FontError!void {
    const ranges = try validateColrV0TopLevelRanges(data, colr);
    const layer_offset = ranges.layer.start;
    const layer_count = try bin.readU16At(data, colr.offset + 12);
    for (0..layer_count) |index| {
        const palette_index = try bin.readU16At(data, colr.offset + layer_offset + index * 4 + 2);
        try validateColrPaletteIndexBounds(palette_index, cpal_palette_entries);
    }
}

fn validateColrV1PaletteBounds(data: []const u8, colr: TableRecord, cpal_palette_entries: ?u16) FontError!void {
    if (colr.length < 34) return error.BadSfnt;
    const base_glyph_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 14));
    if (base_glyph_list_offset != 0) {
        try validateColrV1OptionalOffset(base_glyph_list_offset, colr, 4);
        const list_start = colr.offset + base_glyph_list_offset;
        const record_count: usize = @intCast(try bin.readU32At(data, list_start));
        const records_start = list_start + 4;
        if (record_count > (colr.offset + colr.length - records_start) / 6) return error.BadSfnt;
        const paint_data_start = 4 + record_count * 6;
        for (0..record_count) |index| {
            const record = records_start + index * 6;
            const paint_offset: usize = @intCast(try bin.readU32At(data, record + 2));
            if (paint_offset < paint_data_start) return error.BadSfnt;
            if (paint_offset > colr.length - base_glyph_list_offset) return error.BadSfnt;
            var guard = ColorPaintGraphGuard{};
            try validateColorPaintPaletteBounds(data, colr, cpal_palette_entries, list_start + paint_offset, &guard);
        }
    }

    if (try colrLayerList(data, colr)) |layer_list| {
        for (0..layer_list.layer_count) |layer_index| {
            const paint_offset = try colrLayerPaintOffset(data, colr, layer_list, @intCast(layer_index));
            var guard = ColorPaintGraphGuard{};
            try validateColorPaintPaletteBounds(data, colr, cpal_palette_entries, paint_offset, &guard);
        }
    }
}

fn validateColorPaintPaletteBounds(data: []const u8, colr: TableRecord, cpal_palette_entries: ?u16, offset: usize, guard: *ColorPaintGraphGuard) FontError!void {
    const info = try validateColorPaintRecordBounds(data, colr, offset);
    try guard.enter(offset);
    defer guard.leave();
    try guard.claimPaintRecord(data, colr, offset, info);

    switch (info.kind) {
        .colr_layers => {
            const layer_count = data[offset + 1];
            const first_layer_index = try bin.readU32At(data, offset + 2);
            if (layer_count == 0) return;
            const layer_list = (try colrLayerList(data, colr)) orelse return error.BadSfnt;
            const first: usize = @intCast(first_layer_index);
            if (first > layer_list.layer_count or @as(usize, layer_count) > layer_list.layer_count - first) return error.BadSfnt;
            for (0..layer_count) |layer_offset| {
                const paint_offset = try colrLayerPaintOffset(data, colr, layer_list, first_layer_index + @as(u32, @intCast(layer_offset)));
                try validateColorPaintPaletteBounds(data, colr, cpal_palette_entries, paint_offset, guard);
            }
        },
        .solid => {
            try validateColrPaletteIndexBounds(try bin.readU16At(data, offset + 1), cpal_palette_entries);
        },
        .glyph, .single_child => try validateColorPaintPaletteBounds(data, colr, cpal_palette_entries, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), guard),
        .color_line => try validateColrColorLinePaletteBounds(data, colr, offset, info.min_size, cpal_palette_entries),
        .composite => {
            try validateColorPaintPaletteBounds(data, colr, cpal_palette_entries, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), guard);
            try validateColorPaintPaletteBounds(data, colr, cpal_palette_entries, try colorPaintChildOffset(data, colr, offset, info.min_size, 5), guard);
        },
        .colr_glyph, .terminal => return,
    }
}

fn validateColrGlyphBounds(data: []const u8, colr: TableRecord, glyph_count: u16) FontError!void {
    if (colr.length < 2) return error.BadSfnt;
    const version = try bin.readU16At(data, colr.offset);
    switch (version) {
        0 => try validateColrV0GlyphBounds(data, colr, glyph_count),
        1 => try validateColrV1GlyphBounds(data, colr, glyph_count),
        else => {},
    }
}

fn validateColrV0GlyphBounds(data: []const u8, colr: TableRecord, glyph_count: u16) FontError!void {
    const ranges = try validateColrV0TopLevelRanges(data, colr);
    const base_count = try bin.readU16At(data, colr.offset + 2);
    const base_offset = ranges.base.start;
    const layer_offset = ranges.layer.start;
    const layer_count = try bin.readU16At(data, colr.offset + 12);

    var previous_base_glyph: ?u16 = null;
    var previous_layer_slice_end: ?u16 = null;
    for (0..base_count) |index| {
        const record = colr.offset + base_offset + index * 6;
        const base_glyph = try bin.readU16At(data, record);
        try validateColrBaseGlyphOrder(base_glyph, &previous_base_glyph);
        try validateGlyphIdInMaxp(base_glyph, glyph_count);
        const first_layer = try bin.readU16At(data, record + 2);
        const num_layers = try bin.readU16At(data, record + 4);
        if (first_layer > layer_count or num_layers > layer_count - first_layer) return error.BadSfnt;
        try validateColrLayerSliceOrder(first_layer, num_layers, &previous_layer_slice_end);
    }
    for (0..layer_count) |index| {
        const layer_record = colr.offset + layer_offset + index * 4;
        try validateGlyphIdInMaxp(try bin.readU16At(data, layer_record), glyph_count);
    }
}

fn validateColrV1GlyphBounds(data: []const u8, colr: TableRecord, glyph_count: u16) FontError!void {
    if (colr.length < 34) return error.BadSfnt;
    try validateColrV1ClipList(data, colr, glyph_count);

    const base_glyph_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 14));
    if (base_glyph_list_offset != 0) {
        try validateColrV1OptionalOffset(base_glyph_list_offset, colr, 4);
        const list_start = colr.offset + base_glyph_list_offset;
        const record_count: usize = @intCast(try bin.readU32At(data, list_start));
        const records_start = list_start + 4;
        if (record_count > (colr.offset + colr.length - records_start) / 6) return error.BadSfnt;
        const paint_data_start = 4 + record_count * 6;
        var previous_base_glyph: ?u16 = null;
        for (0..record_count) |index| {
            const record = records_start + index * 6;
            const base_glyph = try bin.readU16At(data, record);
            try validateColrBaseGlyphOrder(base_glyph, &previous_base_glyph);
            try validateGlyphIdInMaxp(base_glyph, glyph_count);
            const paint_offset: usize = @intCast(try bin.readU32At(data, record + 2));
            if (paint_offset < paint_data_start) return error.BadSfnt;
            if (paint_offset > colr.length - base_glyph_list_offset) return error.BadSfnt;
            var guard = ColorPaintGraphGuard{};
            try validateColorPaintGlyphBounds(data, colr, glyph_count, list_start + paint_offset, &guard);
        }
    }

    if (try colrLayerList(data, colr)) |layer_list| {
        for (0..layer_list.layer_count) |layer_index| {
            const paint_offset = try colrLayerPaintOffset(data, colr, layer_list, @intCast(layer_index));
            var guard = ColorPaintGraphGuard{};
            try validateColorPaintGlyphBounds(data, colr, glyph_count, paint_offset, &guard);
        }
    }
}

const ColrV0TopLevelRanges = struct {
    base: ColrV1StructuralRange,
    layer: ColrV1StructuralRange,
};

fn validateColrV0TopLevelRanges(data: []const u8, colr: TableRecord) FontError!ColrV0TopLevelRanges {
    if (colr.length < 14) return error.BadSfnt;
    const version = try bin.readU16At(data, colr.offset);
    if (version != 0) return error.BadSfnt;

    const base_count = try bin.readU16At(data, colr.offset + 2);
    const base_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 4));
    const layer_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 8));
    const layer_count = try bin.readU16At(data, colr.offset + 12);
    const base = try validateColrV0TopLevelRange(colr, base_offset, base_count, 6);
    const layer = try validateColrV0TopLevelRange(colr, layer_offset, layer_count, 4);

    // COLR v0 has two independently typed top-level arrays. Requiring both to
    // start after the fixed header and occupy disjoint bytes prevents a broken
    // table from making BaseGlyphRecords double as LayerRecords or vice versa.
    if (colrRangesOverlap(base, layer)) return error.BadSfnt;
    return .{ .base = base, .layer = layer };
}

fn validateColrV0TopLevelRange(colr: TableRecord, offset: usize, count: u16, record_size: usize) FontError!ColrV1StructuralRange {
    if (offset > colr.length) return error.BadSfnt;
    if (count == 0) return .{ .start = offset, .end = offset };
    if (offset < 14) return error.BadSfnt;
    const byte_len = @as(usize, count) * record_size;
    if (byte_len > colr.length - offset) return error.BadSfnt;
    return .{ .start = offset, .end = offset + byte_len };
}

fn validateColrBaseGlyphOrder(base_glyph: u16, previous_base_glyph: *?u16) FontError!void {
    if (previous_base_glyph.*) |previous| {
        // COLR base glyph arrays are binary-search records keyed by glyph ID.
        // Enforce the spec's strict ordering during parse validation so
        // duplicate or decreasing records cannot make color glyph selection
        // depend on a renderer's search strategy.
        if (base_glyph <= previous) return error.BadSfnt;
    }
    previous_base_glyph.* = base_glyph;
}

fn validateColrLayerSliceOrder(first_layer: u16, num_layers: u16, previous_layer_slice_end: *?u16) FontError!void {
    if (previous_layer_slice_end.*) |previous_end| {
        // Each COLR v0 BaseGlyphRecord owns a contiguous LayerRecord slice.
        // Keeping those slices in BaseGlyphRecord order and non-overlapping
        // prevents two glyphs from sharing mutable layer metadata or making
        // layer ownership depend on how a renderer traverses the base array.
        if (first_layer < previous_end) return error.BadSfnt;
    }
    previous_layer_slice_end.* = first_layer + num_layers;
}

fn validateColrV1OptionalOffset(offset: usize, colr: TableRecord, min_size: usize) FontError!void {
    // COLR v1's optional top-level offsets are all relative to the start of
    // the COLR table and must identify child tables, not bytes in the fixed
    // version-1 header. Header aliasing can otherwise reinterpret offset fields
    // as BaseGlyphList/LayerList counts or paint formats during parse-time
    // validation and later color rendering.
    if (offset < 34 or offset > colr.length or min_size > colr.length - offset) return error.BadSfnt;
}

const ColrV1StructuralRange = struct {
    start: usize,
    end: usize,
};

fn validateColrV1TopLevelStructuralRanges(data: []const u8, colr: TableRecord) FontError!void {
    if (colr.length < 2) return error.BadSfnt;
    const version = try bin.readU16At(data, colr.offset);
    if (version != 1) return;
    if (colr.length < 34) return error.BadSfnt;

    var ranges: [3]ColrV1StructuralRange = undefined;
    var count: usize = 0;

    const base_glyph_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 14));
    if (base_glyph_list_offset != 0) {
        ranges[count] = try colrV1BaseGlyphListStructuralRange(data, colr, base_glyph_list_offset);
        count += 1;
    }

    const layer_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 18));
    if (layer_list_offset != 0) {
        ranges[count] = try colrV1LayerListStructuralRange(data, colr, layer_list_offset);
        count += 1;
    }

    const clip_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 22));
    if (clip_list_offset != 0) {
        ranges[count] = try colrV1ClipListStructuralRange(data, colr, clip_list_offset);
        count += 1;
    }

    for (ranges[0..count], 0..) |lhs, lhs_index| {
        for (ranges[lhs_index + 1 .. count]) |rhs| {
            // These offsets name distinct top-level COLR v1 child tables. Their
            // count/record arrays define how later relative offsets are
            // interpreted, so even a zero-count alias must be rejected instead
            // of letting one optional table borrow another table's header bytes.
            if (colrRangesOverlap(lhs, rhs)) return error.BadSfnt;
        }
    }
}

fn colrV1BaseGlyphListStructuralRange(data: []const u8, colr: TableRecord, offset: usize) FontError!ColrV1StructuralRange {
    try validateColrV1OptionalOffset(offset, colr, 4);
    const start = colr.offset + offset;
    const record_count: usize = @intCast(try bin.readU32At(data, start));
    const records_start = start + 4;
    if (record_count > (colr.offset + colr.length - records_start) / 6) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + record_count * 6 };
}

fn colrV1LayerListStructuralRange(data: []const u8, colr: TableRecord, offset: usize) FontError!ColrV1StructuralRange {
    try validateColrV1OptionalOffset(offset, colr, 4);
    const start = colr.offset + offset;
    const layer_count: usize = @intCast(try bin.readU32At(data, start));
    const offsets_start = start + 4;
    if (layer_count > (colr.offset + colr.length - offsets_start) / 4) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 4 + layer_count * 4 };
}

fn colrV1ClipListStructuralRange(data: []const u8, colr: TableRecord, offset: usize) FontError!ColrV1StructuralRange {
    try validateColrV1OptionalOffset(offset, colr, 5);
    const start = colr.offset + offset;
    const format = data[start];
    if (format != 1) return error.BadSfnt;
    const clip_count: usize = @intCast(try bin.readU32At(data, start + 1));
    const records_start = start + 5;
    if (clip_count > (colr.offset + colr.length - records_start) / 7) return error.BadSfnt;
    return .{ .start = offset, .end = offset + 5 + clip_count * 7 };
}

fn colrRangesOverlap(lhs: ColrV1StructuralRange, rhs: ColrV1StructuralRange) bool {
    return lhs.start < rhs.end and rhs.start < lhs.end;
}

fn validateColrV1ClipList(data: []const u8, colr: TableRecord, glyph_count: u16) FontError!void {
    const clip_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 22));
    if (clip_list_offset == 0) return;

    // ClipList is one of COLR v1's optional offset subtables. Its offsets are
    // relative to the ClipList table, not to COLR, and must not alias the
    // ClipRecord array. Validate it while parsing so later renderers can trust
    // clip metadata rather than reinterpreting records as ClipBox payload.
    try validateColrV1OptionalOffset(clip_list_offset, colr, 5);
    const clip_list_start = colr.offset + clip_list_offset;
    const format = data[clip_list_start];
    if (format != 1) return error.BadSfnt;

    const clip_count: usize = @intCast(try bin.readU32At(data, clip_list_start + 1));
    const records_start = clip_list_start + 5;
    if (clip_count > (colr.offset + colr.length - records_start) / 7) return error.BadSfnt;
    const clip_data_start = 5 + clip_count * 7;

    var previous_end_glyph: ?u16 = null;
    for (0..clip_count) |index| {
        const record = records_start + index * 7;
        const start_glyph = try bin.readU16At(data, record);
        const end_glyph = try bin.readU16At(data, record + 2);
        if (start_glyph > end_glyph) return error.BadSfnt;
        try validateGlyphIdInMaxp(start_glyph, glyph_count);
        try validateGlyphIdInMaxp(end_glyph, glyph_count);
        if (previous_end_glyph) |previous| {
            if (start_glyph <= previous) return error.BadSfnt;
        }
        previous_end_glyph = end_glyph;

        const clip_box_offset: usize = @intCast(try readU24At(data, record + 4));
        if (clip_box_offset < clip_data_start) return error.BadSfnt;
        if (clip_box_offset > colr.length - clip_list_offset) return error.BadSfnt;
        try validateColrV1ClipBox(data, colr, clip_list_start + clip_box_offset);
    }
}

fn validateColrV1ClipBox(data: []const u8, colr: TableRecord, offset: usize) FontError!void {
    const colr_end = colr.offset + colr.length;
    if (offset >= colr_end) return error.BadSfnt;

    const min_size: usize = switch (data[offset]) {
        1 => 9,
        2 => 13,
        else => return error.BadSfnt,
    };
    if (min_size > colr_end - offset) return error.BadSfnt;

    const x_min = try bin.readI16At(data, offset + 1);
    const y_min = try bin.readI16At(data, offset + 3);
    const x_max = try bin.readI16At(data, offset + 5);
    const y_max = try bin.readI16At(data, offset + 7);
    if (x_min > x_max or y_min > y_max) return error.BadSfnt;
}

const DeltaSetIndexMapInfo = struct {
    offset: usize,
    end_offset: usize,
    map_count: usize,
    entry_format: u8,
    entry_size: usize,
    map_data_start: usize,
};

const ColrVariationContext = struct {
    store_offset: usize,
    item_data_count: usize,
    map: ?DeltaSetIndexMapInfo,
};

fn validateColrVariationData(data: []const u8, colr: TableRecord, fvar: ?TableRecord, glyph_count: u16) FontError!void {
    if (colr.length < 2) return error.BadSfnt;
    const version = try bin.readU16At(data, colr.offset);
    if (version != 1) return;
    if (colr.length < 34) return error.BadSfnt;

    const var_index_map_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 26));
    const store_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 30));
    if (var_index_map_offset != 0 and store_offset == 0) return error.BadSfnt;

    var context_storage: ColrVariationContext = undefined;
    const context: ?*const ColrVariationContext = if (store_offset != 0) blk: {
        const fvar_info = try readFvarInfo(data, fvar orelse return error.BadSfnt);
        const store_info = try validateItemVariationStore(data, colr, store_offset, fvar_info.axis_count, 34);
        const store_range = ColrV1StructuralRange{ .start = store_offset, .end = store_info.end_offset };
        try validateColrVariationRangeDisjointFromStructural(data, colr, store_range);
        const map = if (var_index_map_offset != 0) blk_map: {
            const map = try validateDeltaSetIndexMap(data, colr, store_offset, store_info.item_data_count, var_index_map_offset);
            try validateColrVariationTopLevelRanges(store_offset, store_info.end_offset, map.offset, map.end_offset);
            // Variation subtables share the same COLR-relative offset space as
            // BaseGlyphList, LayerList, and ClipList. Keep their structural
            // payloads disjoint so a valid paint list cannot also be decoded as
            // a VarIndexMap or ItemVariationStore header.
            try validateColrVariationRangeDisjointFromStructural(data, colr, .{ .start = map.offset, .end = map.end_offset });
            break :blk_map map;
        } else null;
        context_storage = .{
            .store_offset = store_offset,
            .item_data_count = store_info.item_data_count,
            .map = map,
        };
        break :blk &context_storage;
    } else null;

    try validateColrV1ClipListVariationRefs(data, colr, glyph_count, context);

    const base_glyph_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 14));
    if (base_glyph_list_offset != 0) {
        try validateColrV1OptionalOffset(base_glyph_list_offset, colr, 4);
        const list_start = colr.offset + base_glyph_list_offset;
        const record_count: usize = @intCast(try bin.readU32At(data, list_start));
        const records_start = list_start + 4;
        if (record_count > (colr.offset + colr.length - records_start) / 6) return error.BadSfnt;
        const paint_data_start = 4 + record_count * 6;
        for (0..record_count) |index| {
            const record = records_start + index * 6;
            const paint_offset: usize = @intCast(try bin.readU32At(data, record + 2));
            if (paint_offset < paint_data_start) return error.BadSfnt;
            if (paint_offset > colr.length - base_glyph_list_offset) return error.BadSfnt;
            var guard = ColorPaintGraphGuard{};
            try validateColorPaintVariationRefs(data, colr, list_start + paint_offset, context, &guard);
        }
    }

    if (try colrLayerList(data, colr)) |layer_list| {
        for (0..layer_list.layer_count) |layer_index| {
            const paint_offset = try colrLayerPaintOffset(data, colr, layer_list, @intCast(layer_index));
            var guard = ColorPaintGraphGuard{};
            try validateColorPaintVariationRefs(data, colr, paint_offset, context, &guard);
        }
    }
}

fn validateDeltaSetIndexMap(data: []const u8, table: TableRecord, store_offset: usize, item_data_count: usize, map_offset: usize) FontError!DeltaSetIndexMapInfo {
    if (map_offset < 34 or map_offset > table.length or table.length - map_offset < 4) return error.BadSfnt;
    const map_start = table.offset + map_offset;
    const format = data[map_start];
    const entry_format = data[map_start + 1];
    if ((entry_format & 0xc0) != 0) return error.BadSfnt;

    const entry_size = @as(usize, ((entry_format & 0x30) >> 4)) + 1;
    const inner_bit_count = @as(usize, entry_format & 0x0f) + 1;
    if (inner_bit_count > entry_size * 8) return error.BadSfnt;

    const map_count, const map_data_start = switch (format) {
        0 => .{ @as(usize, @intCast(try bin.readU16At(data, map_start + 2))), map_start + 4 },
        1 => blk: {
            if (table.length - map_offset < 6) return error.BadSfnt;
            break :blk .{ @as(usize, @intCast(try bin.readU32At(data, map_start + 2))), map_start + 6 };
        },
        else => return error.BadSfnt,
    };
    if (map_count != 0 and map_count > (table.offset + table.length - map_data_start) / entry_size) return error.BadSfnt;

    const info = DeltaSetIndexMapInfo{
        .offset = map_offset,
        .end_offset = map_data_start - table.offset + map_count * entry_size,
        .map_count = map_count,
        .entry_format = entry_format,
        .entry_size = entry_size,
        .map_data_start = map_data_start,
    };
    for (0..map_count) |index| {
        const outer_index, const inner_index = try readDeltaSetIndexMapEntry(data, info, index);
        try validateColrDeltaSetReference(data, table, store_offset, item_data_count, outer_index, inner_index);
    }
    return info;
}

fn validateColrVariationTopLevelRanges(store_offset: usize, store_end_offset: usize, map_offset: usize, map_end_offset: usize) FontError!void {
    // COLR VarIndexMap and ItemVariationStore are independent top-level
    // subtables.  Their offsets are both relative to COLR, so accepting
    // overlapping ranges would let one subtable reinterpret the other's count,
    // offset array, or delta payload as a different variation structure.
    if (map_offset < store_end_offset and store_offset < map_end_offset) return error.BadSfnt;
}

fn validateColrVariationRangeDisjointFromStructural(data: []const u8, colr: TableRecord, variation_range: ColrV1StructuralRange) FontError!void {
    const base_glyph_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 14));
    if (base_glyph_list_offset != 0) {
        const structural_range = try colrV1BaseGlyphListStructuralRange(data, colr, base_glyph_list_offset);
        if (colrRangesOverlap(variation_range, structural_range)) return error.BadSfnt;
    }

    const layer_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 18));
    if (layer_list_offset != 0) {
        const structural_range = try colrV1LayerListStructuralRange(data, colr, layer_list_offset);
        if (colrRangesOverlap(variation_range, structural_range)) return error.BadSfnt;
    }

    const clip_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 22));
    if (clip_list_offset != 0) {
        const structural_range = try colrV1ClipListStructuralRange(data, colr, clip_list_offset);
        if (colrRangesOverlap(variation_range, structural_range)) return error.BadSfnt;
    }
}

fn readDeltaSetIndexMapEntry(data: []const u8, map: DeltaSetIndexMapInfo, index: usize) FontError!struct { usize, usize } {
    const entry_offset = map.map_data_start + index * map.entry_size;
    var entry: u32 = 0;
    for (0..map.entry_size) |byte_index| {
        entry = (entry << 8) | data[entry_offset + byte_index];
    }

    const inner_bit_count = @as(u5, @intCast((map.entry_format & 0x0f) + 1));
    const inner_mask = (@as(u32, 1) << inner_bit_count) - 1;
    return .{
        @as(usize, @intCast(entry >> inner_bit_count)),
        @as(usize, @intCast(entry & inner_mask)),
    };
}

fn validateColrDeltaSetReference(data: []const u8, table: TableRecord, store_offset: usize, item_data_count: usize, outer_index: usize, inner_index: usize) FontError!void {
    if (outer_index >= item_data_count) return error.BadSfnt;
    const item_count = try itemVariationDataItemCount(data, table, store_offset, outer_index);
    if (inner_index >= item_count) return error.BadSfnt;
}

fn validateColrVariationIndexSequence(data: []const u8, colr: TableRecord, context: ?*const ColrVariationContext, var_index_base: u32, item_count: usize) FontError!void {
    const ctx = context orelse return error.BadSfnt;
    if (item_count == 0) return;
    if (@as(usize, var_index_base) > std.math.maxInt(u32) - (item_count - 1)) return error.BadSfnt;

    if (ctx.map) |map| {
        if (map.map_count == 0) return error.BadSfnt;
        for (0..item_count) |sequence_index| {
            const logical_index = @as(usize, var_index_base) + sequence_index;
            const mapped_index = if (logical_index >= map.map_count) map.map_count - 1 else logical_index;
            const outer_index, const inner_index = try readDeltaSetIndexMapEntry(data, map, mapped_index);
            try validateColrDeltaSetReference(data, colr, ctx.store_offset, ctx.item_data_count, outer_index, inner_index);
        }
        return;
    }

    for (0..item_count) |sequence_index| {
        const var_index = var_index_base + @as(u32, @intCast(sequence_index));
        try validateColrDeltaSetReference(
            data,
            colr,
            ctx.store_offset,
            ctx.item_data_count,
            @as(usize, @intCast(var_index >> 16)),
            @as(usize, @intCast(var_index & 0xffff)),
        );
    }
}

fn validateColrV1ClipListVariationRefs(data: []const u8, colr: TableRecord, glyph_count: u16, context: ?*const ColrVariationContext) FontError!void {
    const clip_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 22));
    if (clip_list_offset == 0) return;
    try validateColrV1OptionalOffset(clip_list_offset, colr, 5);

    const clip_list_start = colr.offset + clip_list_offset;
    if (data[clip_list_start] != 1) return error.BadSfnt;
    const clip_count: usize = @intCast(try bin.readU32At(data, clip_list_start + 1));
    const records_start = clip_list_start + 5;
    if (clip_count > (colr.offset + colr.length - records_start) / 7) return error.BadSfnt;
    const clip_data_start = 5 + clip_count * 7;

    for (0..clip_count) |index| {
        const record = records_start + index * 7;
        try validateGlyphIdInMaxp(try bin.readU16At(data, record), glyph_count);
        try validateGlyphIdInMaxp(try bin.readU16At(data, record + 2), glyph_count);
        const clip_box_offset: usize = @intCast(try readU24At(data, record + 4));
        if (clip_box_offset < clip_data_start) return error.BadSfnt;
        if (clip_box_offset > colr.length - clip_list_offset) return error.BadSfnt;
        try validateColrV1ClipBoxVariationRefs(data, colr, clip_list_start + clip_box_offset, context);
    }
}

fn validateColrV1ClipBoxVariationRefs(data: []const u8, colr: TableRecord, offset: usize, context: ?*const ColrVariationContext) FontError!void {
    try validateColrV1ClipBox(data, colr, offset);
    if (data[offset] != 2) return;
    try validateColrVariationIndexSequence(data, colr, context, try bin.readU32At(data, offset + 9), 4);
}

fn validateColorPaintVariationRefs(data: []const u8, colr: TableRecord, offset: usize, context: ?*const ColrVariationContext, guard: *ColorPaintGraphGuard) FontError!void {
    const info = try validateColorPaintRecordBounds(data, colr, offset);
    try guard.enter(offset);
    defer guard.leave();
    try guard.claimPaintRecord(data, colr, offset, info);

    switch (info.kind) {
        .colr_layers => {
            const layer_count = data[offset + 1];
            const first_layer_index = try bin.readU32At(data, offset + 2);
            if (layer_count == 0) return;
            const layer_list = (try colrLayerList(data, colr)) orelse return error.BadSfnt;
            const first: usize = @intCast(first_layer_index);
            if (first > layer_list.layer_count or @as(usize, layer_count) > layer_list.layer_count - first) return error.BadSfnt;
            for (0..layer_count) |layer_offset| {
                const paint_offset = try colrLayerPaintOffset(data, colr, layer_list, first_layer_index + @as(u32, @intCast(layer_offset)));
                try validateColorPaintVariationRefs(data, colr, paint_offset, context, guard);
            }
        },
        .solid => {
            if (data[offset] == 3) {
                // PaintVarSolid varies only its alpha field, so varIndexBase
                // must resolve exactly one delta-set reference. Validating it
                // during parsing keeps malformed COLR graphs from reaching a
                // renderer with a dangling ItemVariationStore reference.
                try validateColrVariationIndexSequence(data, colr, context, try bin.readU32At(data, offset + 5), 1);
            }
        },
        .glyph, .single_child => {
            try validateColrVariableTransformVariationRefs(data, colr, offset, info, context);
            try validateColorPaintVariationRefs(data, colr, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), context, guard);
        },
        .composite => {
            try validateColorPaintVariationRefs(data, colr, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), context, guard);
            try validateColorPaintVariationRefs(data, colr, try colorPaintChildOffset(data, colr, offset, info.min_size, 5), context, guard);
        },
        .color_line => try validateColorPaintGradientVariationRefs(data, colr, offset, context),
        .colr_glyph, .terminal => return,
    }
}

fn validateColrVariableTransformVariationRefs(data: []const u8, colr: TableRecord, offset: usize, info: ColorPaintFormatInfo, context: ?*const ColrVariationContext) FontError!void {
    const item_count = colrVariableTransformItemCount(data[offset]) orelse return;
    // Variable transform paints append varIndexBase after their scalar transform
    // arguments (or after the transform offset for PaintVarTransform). Check
    // the whole consecutive delta sequence now so matrix/translate/scale/etc.
    // paints cannot be parsed successfully with dangling variation rows that
    // only fail later when variation coordinates are applied.
    try validateColrVariationIndexSequence(data, colr, context, try bin.readU32At(data, offset + info.min_size - 4), item_count);
}

fn colrVariableTransformItemCount(format: u8) ?usize {
    return switch (format) {
        13 => 6, // PaintVarTransform: xx, yx, xy, yy, dx, dy.
        15 => 2, // PaintVarTranslate: dx, dy.
        17 => 2, // PaintVarScale: scaleX, scaleY.
        19 => 4, // PaintVarScaleAroundCenter: scaleX, scaleY, centerX, centerY.
        21 => 1, // PaintVarScaleUniform: scale.
        23 => 3, // PaintVarScaleUniformAroundCenter: scale, centerX, centerY.
        25 => 1, // PaintVarRotate: angle.
        27 => 3, // PaintVarRotateAroundCenter: angle, centerX, centerY.
        29 => 2, // PaintVarSkew: xSkewAngle, ySkewAngle.
        31 => 4, // PaintVarSkewAroundCenter: xSkewAngle, ySkewAngle, centerX, centerY.
        else => null,
    };
}

fn validateColorPaintGradientVariationRefs(data: []const u8, colr: TableRecord, offset: usize, context: ?*const ColrVariationContext) FontError!void {
    const format = data[offset];
    const info = colorPaintFormatInfo(format).?;
    const coordinate_item_count: usize = switch (format) {
        5, 7 => 6,
        9 => 4,
        else => return,
    };

    // Variable gradient paints have two independent variation consumers: the
    // paint's geometry varIndexBase and each VarColorStop's stop/alpha
    // varIndexBase.  Validate both here so a syntactically valid gradient
    // cannot later dereference missing delta-set rows only when variation
    // coordinates are applied.
    try validateColrVariationIndexSequence(
        data,
        colr,
        context,
        try bin.readU32At(data, offset + info.min_size - 4),
        coordinate_item_count,
    );

    const color_line_offset = try colorPaintChildOffset(data, colr, offset, info.min_size, 1);
    const stop_count: usize = @intCast(try bin.readU16At(data, color_line_offset + 1));
    const stops_start = color_line_offset + 3;
    for (0..stop_count) |index| {
        // A VarColorStop varies StopOffset and Alpha; PaletteIndex remains a
        // discrete CPAL reference and is checked by palette-bound validation.
        try validateColrVariationIndexSequence(
            data,
            colr,
            context,
            try bin.readU32At(data, stops_start + index * colrColorStopSize(true) + 6),
            2,
        );
    }
}

fn validateColorPaintGlyphBounds(data: []const u8, colr: TableRecord, glyph_count: u16, offset: usize, guard: *ColorPaintGraphGuard) FontError!void {
    const info = try validateColorPaintRecordBounds(data, colr, offset);
    try guard.enter(offset);
    defer guard.leave();
    try guard.claimPaintRecord(data, colr, offset, info);

    switch (info.kind) {
        .colr_layers => {
            const layer_count = data[offset + 1];
            const first_layer_index = try bin.readU32At(data, offset + 2);
            if (layer_count == 0) return;
            const layer_list = (try colrLayerList(data, colr)) orelse return error.BadSfnt;
            const first: usize = @intCast(first_layer_index);
            if (first > layer_list.layer_count or @as(usize, layer_count) > layer_list.layer_count - first) return error.BadSfnt;
            for (0..layer_count) |layer_offset| {
                const paint_offset = try colrLayerPaintOffset(data, colr, layer_list, first_layer_index + @as(u32, @intCast(layer_offset)));
                try validateColorPaintGlyphBounds(data, colr, glyph_count, paint_offset, guard);
            }
        },
        .glyph => {
            try validateGlyphIdInMaxp(try bin.readU16At(data, offset + 4), glyph_count);
            try validateColorPaintGlyphBounds(data, colr, glyph_count, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), guard);
        },
        .colr_glyph => try validateGlyphIdInMaxp(try bin.readU16At(data, offset + 1), glyph_count),
        .single_child => try validateColorPaintGlyphBounds(data, colr, glyph_count, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), guard),
        .composite => {
            try validateColorPaintGlyphBounds(data, colr, glyph_count, try colorPaintChildOffset(data, colr, offset, info.min_size, 1), guard);
            try validateColorPaintGlyphBounds(data, colr, glyph_count, try colorPaintChildOffset(data, colr, offset, info.min_size, 5), guard);
        },
        .solid, .color_line, .terminal => return,
    }
}

fn validateGlyphIdInMaxp(glyph_id: u32, glyph_count: u16) FontError!void {
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

const max_colr_paint_graph_depth = 64;
const max_colr_paint_owned_ranges = 2048;

const ColorPaintGraphGuard = struct {
    stack: [max_colr_paint_graph_depth]usize = undefined,
    owned_ranges: [max_colr_paint_owned_ranges]ColrPaintByteRange = undefined,
    depth: usize = 0,
    owned_range_count: usize = 0,

    fn enter(self: *ColorPaintGraphGuard, offset: usize) FontError!void {
        for (self.stack[0..self.depth]) |active_offset| {
            if (active_offset == offset) return error.BadSfnt;
        }
        if (self.depth == self.stack.len) return error.BadSfnt;
        self.stack[self.depth] = offset;
        self.depth += 1;
    }

    fn leave(self: *ColorPaintGraphGuard) void {
        std.debug.assert(self.depth > 0);
        self.depth -= 1;
    }

    fn claimPaintRecord(self: *ColorPaintGraphGuard, data: []const u8, colr: TableRecord, offset: usize, info: ColorPaintFormatInfo) FontError!void {
        try self.claimRange(.{ .start = offset, .end = offset + info.min_size });

        switch (data[offset]) {
            12, 13 => try self.claimRange(try colrTransformMatrixPayloadRange(data, colr, offset, info.min_size)),
            4...9 => try self.claimRange(try colrColorLinePayloadRange(data, colr, offset, info.min_size, colrPaintUsesVarColorLine(data[offset]))),
            else => {},
        }
    }

    fn claimRange(self: *ColorPaintGraphGuard, range: ColrPaintByteRange) FontError!void {
        if (range.start >= range.end) return error.BadSfnt;
        for (self.owned_ranges[0..self.owned_range_count]) |owned| {
            if (colrPaintRangesOverlap(range, owned)) return error.BadSfnt;
        }
        if (self.owned_range_count == self.owned_ranges.len) return error.BadSfnt;
        self.owned_ranges[self.owned_range_count] = range;
        self.owned_range_count += 1;
    }
};

const ColorPaintKind = enum {
    terminal,
    colr_layers,
    solid,
    glyph,
    colr_glyph,
    color_line,
    single_child,
    composite,
};

const ColorPaintFormatInfo = struct {
    min_size: usize,
    kind: ColorPaintKind,
};

fn colorPaintFormatInfo(format: u8) ?ColorPaintFormatInfo {
    return switch (format) {
        1 => .{ .min_size = 6, .kind = .colr_layers },
        2, 3 => .{ .min_size = if (format == 2) 5 else 9, .kind = .solid },
        4, 6 => .{ .min_size = 16, .kind = .color_line },
        5, 7 => .{ .min_size = 20, .kind = .color_line },
        8 => .{ .min_size = 12, .kind = .color_line },
        9 => .{ .min_size = 16, .kind = .color_line },
        10 => .{ .min_size = 6, .kind = .glyph },
        11 => .{ .min_size = 3, .kind = .colr_glyph },
        12 => .{ .min_size = 7, .kind = .single_child },
        13 => .{ .min_size = 11, .kind = .single_child },
        14, 16, 28 => .{ .min_size = 8, .kind = .single_child },
        15, 17, 29 => .{ .min_size = 12, .kind = .single_child },
        18 => .{ .min_size = 12, .kind = .single_child },
        19 => .{ .min_size = 16, .kind = .single_child },
        20, 24 => .{ .min_size = 6, .kind = .single_child },
        21, 25 => .{ .min_size = 10, .kind = .single_child },
        22, 26 => .{ .min_size = 10, .kind = .single_child },
        23, 27 => .{ .min_size = 14, .kind = .single_child },
        30 => .{ .min_size = 12, .kind = .single_child },
        31 => .{ .min_size = 16, .kind = .single_child },
        32 => .{ .min_size = 8, .kind = .composite },
        else => null,
    };
}

fn validateColorPaintRecordBounds(data: []const u8, colr: TableRecord, offset: usize) FontError!ColorPaintFormatInfo {
    const colr_end = colr.offset + colr.length;
    if (offset >= colr_end) return error.BadSfnt;
    const format = data[offset];
    const info = colorPaintFormatInfo(format) orelse return error.BadSfnt;
    // Rejecting reserved paint format bytes at parse time prevents malformed
    // COLR v1 graphs from being accepted merely because the current renderer
    // would later report the same record as unsupported.
    if (info.min_size > colr_end - offset) return error.BadSfnt;
    if (format == 2 or format == 3) {
        try validateColrAlpha(try bin.readI16At(data, offset + 3));
    }
    if (info.kind == .color_line) {
        try validateColrColorLine(data, colr, offset, info.min_size, colrPaintUsesVarColorLine(format));
    }
    try validateColrPaintTransformPayloadBounds(data, colr, offset, info);
    try validateColrPaintChildPayloadOwnership(data, colr, offset, info);
    if (format == 32) {
        // CompositeMode is an enum, not an open-ended flag field. Rejecting
        // reserved values while walking PaintComposite keeps later renderers
        // from accidentally selecting an implementation-defined blend mode.
        const composite_mode = data[offset + 4];
        if (composite_mode > max_colr_composite_mode) return error.BadSfnt;
    }
    return info;
}

fn validateColrPaintTransformPayloadBounds(data: []const u8, colr: TableRecord, offset: usize, info: ColorPaintFormatInfo) FontError!void {
    switch (data[offset]) {
        12, 13 => _ = try colrTransformMatrixPayloadRange(data, colr, offset, info.min_size),
        else => return,
    }
}

const ColrPaintByteRange = struct {
    start: usize,
    end: usize,
};

fn colrPaintRangesOverlap(a: ColrPaintByteRange, b: ColrPaintByteRange) bool {
    return a.start < b.end and b.start < a.end;
}

fn colrPaintHeaderRange(data: []const u8, colr: TableRecord, paint_offset: usize) FontError!ColrPaintByteRange {
    const colr_end = colr.offset + colr.length;
    if (paint_offset >= colr_end) return error.BadSfnt;
    const info = colorPaintFormatInfo(data[paint_offset]) orelse return error.BadSfnt;
    if (info.min_size > colr_end - paint_offset) return error.BadSfnt;
    return .{ .start = paint_offset, .end = paint_offset + info.min_size };
}

fn colrTransformMatrixPayloadRange(data: []const u8, colr: TableRecord, offset: usize, min_size: usize) FontError!ColrPaintByteRange {
    const transform_offset: usize = @intCast(try readU24At(data, offset + 4));
    if (transform_offset < min_size) return error.BadSfnt;
    if (transform_offset > colr.offset + colr.length - offset) return error.BadSfnt;
    const matrix_offset = offset + transform_offset;
    if (24 > colr.offset + colr.length - matrix_offset) return error.BadSfnt;
    return .{ .start = matrix_offset, .end = matrix_offset + 24 };
}

fn validateColrPaintChildPayloadOwnership(data: []const u8, colr: TableRecord, offset: usize, info: ColorPaintFormatInfo) FontError!void {
    switch (data[offset]) {
        12, 13 => {
            const child = try colorPaintChildOffset(data, colr, offset, info.min_size, 1);
            const child_header = try colrPaintHeaderRange(data, colr, child);
            const matrix = try colrTransformMatrixPayloadRange(data, colr, offset, info.min_size);
            // The transform matrix is a sibling payload of the child Paint, not
            // padding that the child may reuse.  Keeping the byte ranges
            // disjoint prevents a crafted matrix coefficient from doubling as a
            // PaintSolid/PaintGlyph header during recursive graph validation.
            if (colrPaintRangesOverlap(child_header, matrix)) return error.BadSfnt;
        },
        32 => {
            const source = try colorPaintChildOffset(data, colr, offset, info.min_size, 1);
            const backdrop = try colorPaintChildOffset(data, colr, offset, info.min_size, 5);
            const source_header = try colrPaintHeaderRange(data, colr, source);
            const backdrop_header = try colrPaintHeaderRange(data, colr, backdrop);
            // PaintComposite owns two independent child Paint headers.  Sharing
            // or partially overlapping those headers would make source/backdrop
            // interpretation depend on which traversal reaches the bytes first.
            if (colrPaintRangesOverlap(source_header, backdrop_header)) return error.BadSfnt;
        },
        else => return,
    }
}

const max_colr_extend_mode = 2;

fn validateColrColorLine(data: []const u8, colr: TableRecord, offset: usize, paint_header_size: usize, variable: bool) FontError!void {
    const color_line_range = try colrColorLinePayloadRange(data, colr, offset, paint_header_size, variable);
    const color_line_offset = color_line_range.start;

    const extend = data[color_line_offset];
    if (extend > max_colr_extend_mode) return error.BadSfnt;

    const stop_count: usize = @intCast(try bin.readU16At(data, color_line_offset + 1));
    // Gradients need at least two ordered stops to define a non-degenerate
    // interpolation interval.  Enforcing this at parse time keeps renderers
    // from inventing fallback colors for malformed ColorLine payloads.
    if (stop_count < 2) return error.BadSfnt;

    const stops_start = color_line_offset + 3;
    const stop_size = colrColorStopSize(variable);

    var previous_stop = try bin.readI16At(data, stops_start);
    try validateColrAlpha(try bin.readI16At(data, stops_start + 4));
    for (1..stop_count) |index| {
        const stop_offset = stops_start + index * stop_size;
        const current_stop = try bin.readI16At(data, stop_offset);
        if (current_stop < previous_stop) return error.BadSfnt;
        try validateColrAlpha(try bin.readI16At(data, stop_offset + 4));
        previous_stop = current_stop;
    }
}

fn colrColorLinePayloadRange(data: []const u8, colr: TableRecord, offset: usize, paint_header_size: usize, variable: bool) FontError!ColrPaintByteRange {
    const color_line_offset = try colorPaintChildOffset(data, colr, offset, paint_header_size, 1);
    const colr_end = colr.offset + colr.length;
    if (color_line_offset + 3 > colr_end) return error.BadSfnt;

    const stop_count: usize = @intCast(try bin.readU16At(data, color_line_offset + 1));
    const stops_start = color_line_offset + 3;
    const stop_size = colrColorStopSize(variable);
    if (stop_count > (colr_end - stops_start) / stop_size) return error.BadSfnt;
    return .{ .start = color_line_offset, .end = stops_start + stop_count * stop_size };
}

fn validateColrColorLinePaletteBounds(data: []const u8, colr: TableRecord, offset: usize, paint_header_size: usize, cpal_palette_entries: ?u16) FontError!void {
    const color_line_offset = try colorPaintChildOffset(data, colr, offset, paint_header_size, 1);
    if (color_line_offset + 3 > colr.offset + colr.length) return error.BadSfnt;
    const stop_count: usize = @intCast(try bin.readU16At(data, color_line_offset + 1));
    const stops_start = color_line_offset + 3;
    const stop_size = colrColorStopSize(colrPaintUsesVarColorLine(data[offset]));
    if (stop_count > (colr.offset + colr.length - stops_start) / stop_size) return error.BadSfnt;
    for (0..stop_count) |index| {
        try validateColrPaletteIndexBounds(try bin.readU16At(data, stops_start + index * stop_size + 2), cpal_palette_entries);
    }
}

fn colrPaintUsesVarColorLine(format: u8) bool {
    return format == 5 or format == 7 or format == 9;
}

fn colrColorStopSize(variable: bool) usize {
    return if (variable) 10 else 6;
}

fn validateColrAlpha(raw_alpha: i16) FontError!void {
    // PaintSolid/PaintVarSolid alpha is encoded as F2DOT14 but semantically is
    // opacity, whose valid range is closed [0, 1]. Reject the extra numeric
    // range that F2DOT14 can represent so malformed fonts cannot smuggle
    // negative or over-opaque colors into later blending code.
    if (raw_alpha < 0 or raw_alpha > 0x4000) return error.BadSfnt;
}

const max_colr_composite_mode = 27;

fn colorPaintChildOffset(data: []const u8, colr: TableRecord, offset: usize, parent_size: usize, field_offset: usize) FontError!usize {
    const child_offset: usize = @intCast(try readU24At(data, offset + field_offset));
    if (child_offset < parent_size) return error.BadSfnt;
    if (child_offset > colr.offset + colr.length - offset) return error.BadSfnt;
    return offset + child_offset;
}

const ColrLayerList = struct {
    start: usize,
    layer_count: usize,
    offsets_start: usize,
    paint_data_start: usize,
};

fn colrLayerList(data: []const u8, colr: TableRecord) FontError!?ColrLayerList {
    if (colr.length < 22) return error.BadSfnt;
    const layer_list_offset: usize = @intCast(try bin.readU32At(data, colr.offset + 18));
    if (layer_list_offset == 0) return null;
    try validateColrV1OptionalOffset(layer_list_offset, colr, 4);

    const list_start = colr.offset + layer_list_offset;
    const layer_count: usize = @intCast(try bin.readU32At(data, list_start));
    const offsets_start = list_start + 4;
    if (layer_count > (colr.offset + colr.length - offsets_start) / 4) return error.BadSfnt;
    const layer_list = ColrLayerList{
        .start = list_start,
        .layer_count = layer_count,
        .offsets_start = offsets_start,
        .paint_data_start = 4 + layer_count * 4,
    };
    try validateColrLayerListPaintHeaderOwnership(data, colr, layer_list);
    return layer_list;
}

fn validateColrLayerListPaintHeaderOwnership(data: []const u8, colr: TableRecord, layer_list: ColrLayerList) FontError!void {
    // LayerList offsets are the canonical paint order for PaintColrLayers.
    // Require each layer to own at least its fixed Paint header and keep those
    // headers in the same byte order as the offset array. This rejects duplicate
    // or partially-overlapping layer entries without trying to infer ownership
    // of every recursively referenced child payload.
    var previous_header_end: ?usize = null;
    for (0..layer_list.layer_count) |index| {
        const paint_offset: usize = @intCast(try bin.readU32At(data, layer_list.offsets_start + index * 4));
        if (paint_offset < layer_list.paint_data_start) return error.BadSfnt;
        const layer_list_offset = layer_list.start - colr.offset;
        if (paint_offset > colr.length - layer_list_offset) return error.BadSfnt;
        if (previous_header_end) |previous_end| {
            if (paint_offset < previous_end) return error.BadSfnt;
        }

        const paint_start = layer_list.start + paint_offset;
        if (paint_start >= colr.offset + colr.length) return error.BadSfnt;
        const info = colorPaintFormatInfo(data[paint_start]) orelse return error.BadSfnt;
        if (info.min_size > colr.offset + colr.length - paint_start) return error.BadSfnt;
        previous_header_end = paint_offset + info.min_size;
    }
}

fn colrLayerPaintOffset(data: []const u8, colr: TableRecord, layer_list: ColrLayerList, layer_index: u32) FontError!usize {
    const index: usize = @intCast(layer_index);
    if (index >= layer_list.layer_count) return error.BadSfnt;
    const paint_offset: usize = @intCast(try bin.readU32At(data, layer_list.offsets_start + index * 4));
    // LayerList Paint offsets are relative to the LayerList table. They must
    // point past the declared offset array so a malformed font cannot treat
    // list metadata as a Paint table, and they must remain inside COLR.
    if (paint_offset < layer_list.paint_data_start) return error.BadSfnt;
    const layer_list_offset = layer_list.start - colr.offset;
    if (paint_offset > colr.length - layer_list_offset) return error.BadSfnt;
    return layer_list.start + paint_offset;
}

fn validateColorPaintLayer(font: *const Font, layer_list: ColrLayerList, layer_index: u32, guard: *ColorPaintGraphGuard) FontError!void {
    const colr = font.colr orelse return error.BadSfnt;
    const paint_offset = try colrLayerPaintOffset(font.data, colr, layer_list, layer_index);
    try validateColorPaintGraph(font, paint_offset, guard);
}

fn validateColorPaintGraph(font: *const Font, offset: usize, guard: *ColorPaintGraphGuard) FontError!void {
    const colr = font.colr orelse return error.BadSfnt;
    const data = font.data;
    if (offset >= colr.offset + colr.length) return error.BadSfnt;
    const info = try validateColorPaintRecordBounds(data, colr, offset);
    try guard.enter(offset);
    defer guard.leave();
    try guard.claimPaintRecord(data, colr, offset, info);

    const format = data[offset];
    switch (format) {
        1 => {
            if (offset + 6 > colr.offset + colr.length) return error.BadSfnt;
            const layer_count = data[offset + 1];
            const first_layer_index = try bin.readU32At(data, offset + 2);
            if (layer_count == 0) return;
            const layer_list = (try colrLayerList(data, colr)) orelse return error.BadSfnt;
            const first: usize = @intCast(first_layer_index);
            if (first > layer_list.layer_count or @as(usize, layer_count) > layer_list.layer_count - first) return error.BadSfnt;
            for (0..layer_count) |layer_offset| {
                try validateColorPaintLayer(font, layer_list, first_layer_index + @as(u32, @intCast(layer_offset)), guard);
            }
        },
        2 => {
            if (offset + 5 > colr.offset + colr.length) return error.BadSfnt;
            try font.validateColorPaletteIndex(try bin.readU16At(data, offset + 1));
        },
        10 => {
            if (offset + 6 > colr.offset + colr.length) return error.BadSfnt;
            const child_offset: usize = @intCast(try readU24At(data, offset + 1));
            if (child_offset < 6) return error.BadSfnt;
            if (child_offset > colr.offset + colr.length - offset) return error.BadSfnt;
            try validateColorPaintGraph(font, offset + child_offset, guard);
        },
        // Unsupported paint formats are left for `readColorPaint` to report
        // when callers ask for that specific paint.  Graph validation only
        // follows the recursive formats this parser can otherwise traverse
        // indefinitely.
        else => return,
    }
}

fn readColorPaint(font: *const Font, offset: usize) FontError!ColorPaint {
    const colr = font.colr orelse return error.BadSfnt;
    const data = font.data;
    if (offset + 5 > colr.offset + colr.length) return error.BadSfnt;
    const format = data[offset];
    return switch (format) {
        2 => blk: {
            const palette_index = try bin.readU16At(data, offset + 1);
            try font.validateColorPaletteIndex(palette_index);
            break :blk .{ .solid = .{
                .palette_index = palette_index,
                .alpha = f2dot14(try bin.readI16At(data, offset + 3)),
            } };
        },
        1 => blk: {
            if (offset + 6 > colr.offset + colr.length) return error.BadSfnt;
            break :blk .{ .layers = .{
                .layer_count = data[offset + 1],
                .first_layer_index = try bin.readU32At(data, offset + 2),
            } };
        },
        10 => blk: {
            if (offset + 6 > colr.offset + colr.length) return error.BadSfnt;
            const child_offset: usize = @intCast(try readU24At(data, offset + 1));
            const glyph_id = try bin.readU16At(data, offset + 4);
            // A PaintGlyph child starts after this six-byte parent record.
            // Smaller offsets overlap the parent's Offset24/GlyphID fields;
            // offset zero would recurse into the same PaintGlyph forever.
            if (child_offset < 6) return error.BadSfnt;
            if (child_offset > colr.offset + colr.length - offset) return error.BadSfnt;
            const child = try readColorPaint(font, offset + child_offset);
            break :blk switch (child) {
                .solid => |solid| .{ .glyph = .{ .glyph_id = glyph_id, .solid = solid } },
                else => error.UnsupportedGlyph,
            };
        },
        else => error.UnsupportedGlyph,
    };
}

fn readU24At(data: []const u8, offset: usize) FontError!u32 {
    if (offset + 3 > data.len) return error.BadSfnt;
    return (@as(u32, data[offset]) << 16) | (@as(u32, data[offset + 1]) << 8) | data[offset + 2];
}

fn variationValueForAxis(axis: VariationAxis, coordinates: []const VariationCoordinate) ?f32 {
    for (coordinates) |coordinate| {
        if (std.mem.eql(u8, &axis.tag, &coordinate.tag)) return coordinate.value;
    }
    return null;
}

fn readI16FromSlice(data: []const u8, offset: usize) FontError!i16 {
    return bin.readI16At(data, offset) catch |err| switch (err) {
        error.EndOfStream => error.BadSfnt,
    };
}

test "reads GDEF mark glyph filtering sets" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 52;

    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 2);
    writeU32Test(&bytes, 4, 12);
    writeU32Test(&bytes, 8, 22);

    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 2);
    writeU16Test(&bytes, 16, 5);
    writeU16Test(&bytes, 18, 9);

    writeU16Test(&bytes, 22, 2);
    writeU16Test(&bytes, 24, 2);
    writeU16Test(&bytes, 26, 20);
    writeU16Test(&bytes, 28, 21);
    writeU16Test(&bytes, 30, 0);
    writeU16Test(&bytes, 32, 30);
    writeU16Test(&bytes, 34, 32);
    writeU16Test(&bytes, 36, 2);

    const sets = try readMarkGlyphSetsDef(allocator, &bytes, 0);
    defer freeMarkFilteringSets(allocator, sets);

    try std.testing.expectEqual(@as(usize, 2), sets.len);
    try std.testing.expectEqualSlices(glyph_mod.GlyphId, &.{ 5, 9 }, sets[0]);
    try std.testing.expectEqualSlices(glyph_mod.GlyphId, &.{ 20, 21, 30, 31, 32 }, sets[1]);
}

test "GDEF MarkGlyphSetsDef rejects coverage offsets into its header" {
    var bytes: [16]u8 = .{0} ** 16;
    writeU16Test(&bytes, 0, 1); // MarkGlyphSetsDef format.
    writeU16Test(&bytes, 2, 1); // One CoverageOffset entry follows.
    writeU32Test(&bytes, 4, 0); // Would reinterpret the MarkGlyphSetsDef header as Coverage format 1.

    try std.testing.expectError(error.BadSfnt, readMarkGlyphSetsDef(std.testing.allocator, &bytes, 0));
}

test "GDEF MarkGlyphSetsDef rejects malformed coverage ordering" {
    var bytes: [28]u8 = .{0} ** 28;
    writeU16Test(&bytes, 0, 1); // MarkGlyphSetsDef format.
    writeU16Test(&bytes, 2, 1);
    writeU32Test(&bytes, 4, 8);

    writeU16Test(&bytes, 8, 1); // Coverage format 1.
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 9);
    writeU16Test(&bytes, 14, 5); // Unsorted; mark sets must use canonical Coverage data.
    try std.testing.expectError(error.BadSfnt, readMarkGlyphSetsDef(std.testing.allocator, &bytes, 0));

    writeU16Test(&bytes, 8, 2); // Coverage format 2.
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 5);
    writeU16Test(&bytes, 14, 9);
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 9); // Overlaps the previous inclusive range.
    writeU16Test(&bytes, 20, 11);
    writeU16Test(&bytes, 22, 5);
    try std.testing.expectError(error.BadSfnt, readMarkGlyphSetsDef(std.testing.allocator, &bytes, 0));
}

test "ignores mark glyph filtering offset field before GDEF 1.2" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16Test(&bytes, 0, 1); // major
    writeU16Test(&bytes, 2, 0); // GDEF 1.0: no MarkGlyphSetsDef field.
    writeU16Test(&bytes, 4, 14); // GlyphClassDef offset.
    writeU16Test(&bytes, 12, 1); // First bytes of the class def, not a mark-set offset.
    writeU16Test(&bytes, 14, 1); // ClassDef format 1.
    writeU16Test(&bytes, 16, 3); // startGlyphID
    writeU16Test(&bytes, 18, 1); // glyphCount
    writeU16Test(&bytes, 20, 3); // class value: mark

    const font = gdefOnlyFont(&bytes);
    try std.testing.expectEqual(GlyphClass.mark, try font.glyphClass(3));
    try std.testing.expect((try font.markFilteringSets(std.testing.allocator)) == null);
}

test "GDEF ClassDef format 1 validates upper glyph boundary without overflow" {
    var bytes: [14]u8 = .{0} ** 14;
    writeU16Test(&bytes, 0, 1); // ClassDef format 1.
    writeU16Test(&bytes, 2, 0xffff); // startGlyphID at the u16 boundary.
    writeU16Test(&bytes, 4, 1); // Only one class value follows.
    writeU16Test(&bytes, 6, @intFromEnum(GlyphClass.mark));

    try std.testing.expectEqual(@as(u16, @intFromEnum(GlyphClass.mark)), try classDefValue(&bytes, 0, 0xffff));

    // The declared ClassDef span can exceed the physical table when widened.
    // This must report malformed GDEF/SFNT data, not wrap `startGlyphID +
    // glyphCount` and silently treat the boundary glyph as unclassified.
    writeU16Test(&bytes, 4, 5);
    try std.testing.expectError(error.BadSfnt, classDefValue(&bytes, 0, 0xffff));
}

test "GDEF ClassDef format 2 rejects overlapping and reversed ranges" {
    var bytes: [22]u8 = .{0} ** 22;
    writeU16Test(&bytes, 0, 2); // ClassDef format 2.
    writeU16Test(&bytes, 2, 3); // Three ClassRangeRecords.
    writeU16Test(&bytes, 4, 10);
    writeU16Test(&bytes, 6, 12);
    writeU16Test(&bytes, 8, @intFromEnum(GlyphClass.base));
    writeU16Test(&bytes, 10, 12); // Overlaps the previous inclusive range.
    writeU16Test(&bytes, 12, 14);
    writeU16Test(&bytes, 14, @intFromEnum(GlyphClass.mark));
    writeU16Test(&bytes, 16, 20);
    writeU16Test(&bytes, 18, 18); // Reversed range.
    writeU16Test(&bytes, 20, @intFromEnum(GlyphClass.component));

    try std.testing.expectError(error.BadSfnt, classDefValue(&bytes, 0, 12));

    writeU16Test(&bytes, 10, 13); // Repair overlap so the reversed range is checked.
    try std.testing.expectError(error.BadSfnt, classDefValue(&bytes, 0, 18));
}

test "GDEF parse validation rejects class and mark-set glyph ids past maxp" {
    var valid_classdef: [22]u8 = .{0} ** 22;
    writeU16Test(&valid_classdef, 0, 1); // GDEF major.
    writeU16Test(&valid_classdef, 2, 0); // GDEF 1.0 header.
    writeU16Test(&valid_classdef, 4, 12); // GlyphClassDef follows the header.
    writeU16Test(&valid_classdef, 12, 1); // ClassDef format 1.
    writeU16Test(&valid_classdef, 14, 2); // startGlyphID.
    writeU16Test(&valid_classdef, 16, 2); // Covers glyphs 2 and 3 in a four-glyph font.
    writeU16Test(&valid_classdef, 18, @intFromEnum(GlyphClass.mark));
    writeU16Test(&valid_classdef, 20, @intFromEnum(GlyphClass.mark));
    try validateGdefTable(&valid_classdef, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = valid_classdef.len }, 4);

    var classdef_past_maxp = valid_classdef;
    writeU16Test(&classdef_past_maxp, 16, 3); // Would cover glyph 4, outside maxp.numGlyphs.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&classdef_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = classdef_past_maxp.len }, 4));

    var child_offset_overlap = valid_classdef;
    writeU16Test(&child_offset_overlap, 4, 4); // Reinterprets GDEF header bytes as ClassDef data.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&child_offset_overlap, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = child_offset_overlap.len }, 4));

    var mark_set_past_maxp: [30]u8 = .{0} ** 30;
    writeU16Test(&mark_set_past_maxp, 0, 1); // GDEF major.
    writeU16Test(&mark_set_past_maxp, 2, 2); // GDEF 1.2 includes MarkGlyphSetsDef.
    writeU16Test(&mark_set_past_maxp, 12, 14); // MarkGlyphSetsDef follows the v1.2 header.
    writeU16Test(&mark_set_past_maxp, 14, 1); // MarkGlyphSetsDef format 1.
    writeU16Test(&mark_set_past_maxp, 16, 1);
    writeU32Test(&mark_set_past_maxp, 18, 8); // Coverage starts after the set offset array.
    writeU16Test(&mark_set_past_maxp, 22, 1); // Coverage format 1.
    writeU16Test(&mark_set_past_maxp, 24, 2);
    writeU16Test(&mark_set_past_maxp, 26, 1);
    writeU16Test(&mark_set_past_maxp, 28, 4); // Invalid for maxp.numGlyphs == 4.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&mark_set_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = mark_set_past_maxp.len }, 4));
}

test "legacy kern format 0 accumulates multiple horizontal subtables" {
    var data: [44]u8 = .{0} ** 44;
    writeU16Test(&data, 0, 0);
    writeU16Test(&data, 2, 2);
    writeKernFormat0Subtable(&data, 4, 0x0001, 1, 1, -40);
    writeKernFormat0Subtable(&data, 24, 0x0001, 1, 1, -70);

    const font = kernOnlyFont(&data);
    try std.testing.expectEqual(@as(i16, -110), try font.kerning(1, 1));
    try std.testing.expectEqual(@as(i16, 0), try font.kerning(0, 1));
}

test "legacy kern ignores minimum and cross-stream subtables" {
    var data: [64]u8 = .{0} ** 64;
    writeU16Test(&data, 0, 0);
    writeU16Test(&data, 2, 3);
    writeKernFormat0Subtable(&data, 4, 0x0003, 1, 1, -100);
    writeKernFormat0Subtable(&data, 24, 0x0005, 1, 1, -80);
    writeKernFormat0Subtable(&data, 44, 0x0001, 1, 1, -30);

    const font = kernOnlyFont(&data);
    try std.testing.expectEqual(@as(i16, -30), try font.kerning(1, 1));
}

test "legacy kern format 0 rejects truncated binary-search header" {
    var data: [16]u8 = .{0} ** 16;
    writeU16Test(&data, 0, 0); // legacy kern table version
    writeU16Test(&data, 2, 1); // one subtable
    writeU16Test(&data, 4, 0); // subtable version
    writeU16Test(&data, 6, 12); // Stops before the required rangeShift field.
    writeU16Test(&data, 8, 0x0001); // format 0, horizontal

    const font = kernOnlyFont(&data);
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
}

test "Apple kern v1 format 0 applies horizontal pair subtables" {
    var data: [54]u8 = .{0} ** 54;
    writeU32Test(&data, 0, 0x00010000); // Apple/AAT kern table version.
    writeU32Test(&data, 4, 2);
    writeAppleKernFormat0Subtable(&data, 8, 0x0000, 1, 1, -35);
    writeAppleKernFormat0Subtable(&data, 31, 0x0000, 1, 1, -45);

    const font = kernOnlyFont(&data);
    try std.testing.expectEqual(@as(i16, -80), try font.kerning(1, 1));
    try std.testing.expectEqual(@as(i16, 0), try font.kerning(0, 1));
}

test "Apple kern v1 validates declared subtable lengths" {
    var data: [22]u8 = .{0} ** 22;
    writeU32Test(&data, 0, 0x00010000);
    writeU32Test(&data, 4, 1);
    writeU32Test(&data, 8, 14); // Stops before the format-0 rangeShift field.
    writeU16Test(&data, 12, 0x0000); // horizontal format 0.

    const font = kernOnlyFont(&data);
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
}

test "kern format 0 pair arrays are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        var kern: [24]u8 = .{0} ** 24;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        var kern: [24]u8 = .{0} ** 24;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 2, 1, -40);

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var kern: [30]u8 = .{0} ** 30;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeU16Test(&kern, 4, 0);
        writeU16Test(&kern, 6, 26);
        writeU16Test(&kern, 8, 0x0001);
        writeU16Test(&kern, 10, 2); // nPairs.
        writeU16Test(&kern, 12, 6);
        writeU16Test(&kern, 14, 0);
        writeU16Test(&kern, 16, 0);
        writeU16Test(&kern, 18, 1);
        writeU16Test(&kern, 20, 1);
        writeI16Test(&kern, 22, -40);
        writeU16Test(&kern, 24, 0); // Out of sort order after (1, 1).
        writeU16Test(&kern, 26, 1);
        writeI16Test(&kern, 28, -20);

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "Apple kern v1 format 0 pair glyph ids are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var kern: [31]u8 = .{0} ** 31;
    writeU32Test(&kern, 0, 0x00010000);
    writeU32Test(&kern, 4, 1);
    writeAppleKernFormat0Subtable(&kern, 8, 0x0000, 1, 2, -35);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "sbix offsets cannot overlap table or strike metadata" {
    var table_overlap: [32]u8 = .{0} ** 32;
    writeU16Test(&table_overlap, 0, 1); // version
    writeU32Test(&table_overlap, 4, 1); // one strike offset follows
    writeU32Test(&table_overlap, 8, 8); // Points at the strike-offset array.
    const sbix = TableRecord{ .tag = .{ 's', 'b', 'i', 'x' }, .checksum = 0, .offset = 0, .length = table_overlap.len };
    try std.testing.expectError(error.BadSfnt, sbixStrike(&table_overlap, sbix, 1, 0));

    var glyph_overlap: [48]u8 = .{0} ** 48;
    writeU16Test(&glyph_overlap, 0, 1); // version
    writeU32Test(&glyph_overlap, 4, 1);
    writeU32Test(&glyph_overlap, 8, 12); // First strike begins after sbix metadata.
    writeU16Test(&glyph_overlap, 12, 16); // ppem
    writeU16Test(&glyph_overlap, 14, 72); // ppi
    writeU32Test(&glyph_overlap, 16, 4); // Non-empty glyph points back into the offset array.
    writeU32Test(&glyph_overlap, 20, 20);

    const strike = try sbixStrike(&glyph_overlap, sbix, 1, 0);
    try std.testing.expectError(error.BadSfnt, sbixGlyphPng(&glyph_overlap, strike, 0));
}

test "sbix parse validation checks every strike glyph offset" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16Test(&bytes, 0, 1); // sbix version
    writeU32Test(&bytes, 4, 1); // one strike
    writeU32Test(&bytes, 8, 12); // strike data starts after the strike-offset array
    writeU16Test(&bytes, 12, 16); // ppem
    writeU16Test(&bytes, 14, 72); // ppi

    const sbix = TableRecord{ .tag = .{ 's', 'b', 'i', 'x' }, .checksum = 0, .offset = 0, .length = bytes.len };

    // Two glyphs require three offsets. The second glyph is "unused" for many
    // runtime lookups, but parse-time validation must still reject its
    // decreasing boundary so malformed payloads cannot hide behind glyph choice.
    writeU32Test(&bytes, 16, 24);
    writeU32Test(&bytes, 20, 32);
    writeU32Test(&bytes, 24, 28);
    try std.testing.expectError(error.BadSfnt, validateSbixTable(&bytes, sbix, 2));

    writeU32Test(&bytes, 24, 36); // Non-empty glyph payload is shorter than the sbix origin+type header.
    try std.testing.expectError(error.BadSfnt, validateSbixTable(&bytes, sbix, 2));

    writeU32Test(&bytes, 24, 40);
    try validateSbixTable(&bytes, sbix, 2);
}

test "CBLC bitmap index subtables reject decreasing image offsets" {
    const strike = CblcStrike{
        .ppem = 16,
        .ppi = 0,
        .offset = 0,
        .index_tables_size = 0,
        .table_count = 0,
        .start_glyph = 1,
        .end_glyph = 1,
    };

    var format3_offsets: [4]u8 = .{0} ** 4;
    writeU16Test(&format3_offsets, 0, 10);
    writeU16Test(&format3_offsets, 2, 4);
    var format3_strike = strike;
    format3_strike.index_tables_size = format3_offsets.len;
    try std.testing.expectError(error.BadSfnt, cblcGlyphLocationFormat1Or3(
        &format3_offsets,
        format3_strike,
        0,
        1,
        1,
        0,
        17,
        0,
        2,
    ));

    var format4_pairs: [12]u8 = .{0} ** 12;
    writeU32Test(&format4_pairs, 0, 1);
    writeU16Test(&format4_pairs, 4, 1);
    writeU16Test(&format4_pairs, 6, 10);
    writeU16Test(&format4_pairs, 8, 2);
    writeU16Test(&format4_pairs, 10, 4);
    var format4_strike = strike;
    format4_strike.index_tables_size = format4_pairs.len;
    try std.testing.expectError(error.BadSfnt, cblcGlyphLocationFormat4(&format4_pairs, format4_strike, 0, 1, 17, 0));
}

test "CBLC fixed-size index formats validate dense and sparse invariants" {
    const strike = CblcStrike{
        .ppem = 16,
        .ppi = 0,
        .offset = 0,
        .index_tables_size = 32,
        .table_count = 1,
        .start_glyph = 1,
        .end_glyph = 3,
    };

    var format2: [12]u8 = .{0} ** 12;
    writeU32Test(&format2, 0, 9); // One fixed-size image-format-17 CBDT payload.
    const dense_location = (try cblcGlyphLocationFormat2(&format2, strike, 0, 1, 3, 2, 17, 0)).?;
    try std.testing.expectEqual(@as(usize, 18), dense_location.offset);
    try std.testing.expectEqual(@as(usize, 9), dense_location.length);

    writeU32Test(&format2, 0, 0);
    try std.testing.expectError(error.BadSfnt, cblcGlyphLocationFormat2(&format2, strike, 0, 1, 3, 0, 17, 0));

    var data: [121]u8 = .{0} ** 121;
    writeU16Test(&data, 0, 2); // CBLC major version.
    writeU16Test(&data, 2, 0); // CBLC minor version.
    writeU32Test(&data, 4, 1); // One bitmapSizeTable.
    writeU32Test(&data, 8, 56); // IndexSubTableArray immediately after the strike directory.
    writeU32Test(&data, 12, 38); // One array record plus one format-5 subtable.
    writeU32Test(&data, 16, 1); // One IndexSubTableArray record.
    writeU16Test(&data, 48, 1); // startGlyphIndex.
    writeU16Test(&data, 50, 3); // endGlyphIndex.
    data[52] = 16; // ppem.

    writeU16Test(&data, 56, 1); // firstGlyphIndex.
    writeU16Test(&data, 58, 3); // lastGlyphIndex.
    writeU32Test(&data, 60, 8); // Subtable starts after the array record.
    writeU16Test(&data, 64, 5); // indexFormat 5: sparse fixed-size images.
    writeU16Test(&data, 66, 17); // imageFormat 17: small metrics + dataLen.
    writeU32Test(&data, 68, 0); // imageDataOffset.
    writeU32Test(&data, 72, 9); // imageSize.
    writeU32Test(&data, 84, 3); // Three glyph codes follow.
    writeU16Test(&data, 88, 1);
    writeU16Test(&data, 90, 3);
    writeU16Test(&data, 92, 2); // Out of order; must be caught before lookup succeeds.

    const cblc = TableRecord{ .tag = .{ 'C', 'B', 'L', 'C' }, .checksum = 0, .offset = 0, .length = 94 };
    const cbdt = TableRecord{ .tag = .{ 'C', 'B', 'D', 'T' }, .checksum = 0, .offset = 94, .length = 27 };
    try std.testing.expectError(error.BadSfnt, validateCblcCbdtTables(&data, cblc, cbdt, 4));

    writeU16Test(&data, 90, 2);
    writeU16Test(&data, 92, 3);
    try validateCblcCbdtTables(&data, cblc, cbdt, 4);

    writeU16Test(&data, 92, 4); // Outside the subtable's declared 1...3 range.
    try std.testing.expectError(error.BadSfnt, validateCblcCbdtTables(&data, cblc, cbdt, 4));
}

test "CBLC strike glyph ranges stay within maxp glyph count" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16Test(&bytes, 0, 2); // major version.
    writeU16Test(&bytes, 2, 0); // minor version.
    writeU32Test(&bytes, 4, 1); // one strike.
    writeU32Test(&bytes, 8, 56); // indexSubTableArrayOffset at end: empty index array.
    writeU32Test(&bytes, 12, 0);
    writeU32Test(&bytes, 16, 0);
    writeU16Test(&bytes, 48, 0); // startGlyphIndex.
    writeU16Test(&bytes, 50, 2); // endGlyphIndex exceeds a two-glyph font's max glyph id.
    bytes[52] = 16;

    const cblc = TableRecord{ .tag = .{ 'C', 'B', 'L', 'C' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, cblcStrike(&bytes, cblc, 2, 0));
}

test "CBLC index arrays cannot overlap the strike directory" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16Test(&bytes, 0, 2); // major version.
    writeU16Test(&bytes, 2, 0); // minor version.
    writeU32Test(&bytes, 4, 1); // one bitmapSizeTable.
    writeU32Test(&bytes, 8, 8); // Points back into the bitmapSizeTable.
    writeU32Test(&bytes, 12, 48);
    writeU32Test(&bytes, 16, 1);
    writeU16Test(&bytes, 48, 1);
    writeU16Test(&bytes, 50, 1);
    bytes[52] = 16;

    const cblc = TableRecord{ .tag = .{ 'C', 'B', 'L', 'C' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, cblcStrike(&bytes, cblc, 2, 0));
}

test "CBLC index subtable array validates ordering before returning a location" {
    const strike = CblcStrike{
        .ppem = 16,
        .ppi = 0,
        .offset = 0,
        .index_tables_size = 40,
        .table_count = 2,
        .start_glyph = 1,
        .end_glyph = 4,
    };

    var overlapping: [40]u8 = .{0} ** 40;
    writeU16Test(&overlapping, 0, 1);
    writeU16Test(&overlapping, 2, 2);
    writeU32Test(&overlapping, 4, 16);
    writeU16Test(&overlapping, 8, 2); // Overlaps the previous inclusive range.
    writeU16Test(&overlapping, 10, 3);
    writeU32Test(&overlapping, 12, 28);
    try std.testing.expectError(error.BadSfnt, cblcGlyphLocation(&overlapping, strike, 1));

    var subtable_overlap = overlapping;
    writeU16Test(&subtable_overlap, 8, 3); // Repair ordering.
    writeU16Test(&subtable_overlap, 10, 4);
    writeU32Test(&subtable_overlap, 12, 4); // Points into IndexSubTableArray records.
    try std.testing.expectError(error.BadSfnt, cblcGlyphLocation(&subtable_overlap, strike, 1));
}

test "CBLC image locations reject arithmetic overflow before CBDT slicing" {
    const max = std.math.maxInt(usize);

    try std.testing.expectError(error.BadSfnt, cblcImageLocation(17, max - 4, 8, 12));
    try std.testing.expectError(error.BadSfnt, cblcImageLocation(17, max - 4, 2, 8));
    try std.testing.expectError(error.BadSfnt, checkedCblcImageStart(max / 2 + 1, 2));
    try std.testing.expectError(error.BadSfnt, checkedCblcImageEnd(max - 1, 2));

    const missing = try cblcImageLocation(17, 10, 4, 4);
    try std.testing.expectEqual(@as(?CblcGlyphLocation, null), missing);

    const location = (try cblcImageLocation(17, 10, 4, 8)).?;
    try std.testing.expectEqual(@as(usize, 14), location.offset);
    try std.testing.expectEqual(@as(usize, 4), location.length);
}

test "CBLC CBDT parse validation checks every referenced bitmap payload" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    const cblc_offset = try sfntTableOffset(bytes, "CBLC");
    const cbdt_offset = try sfntTableOffset(bytes, "CBDT");
    const original_data_len = try bin.readU32At(bytes, cbdt_offset + 9);

    // The CBLC fixture references one format-17 CBDT PNG payload. Corrupting
    // its embedded dataLen leaves all CBLC offsets/ranges intact, so only a
    // parse-time walk that checks referenced CBDT records catches the defect
    // before a specific bitmap glyph is requested.
    writeU32Test(bytes, cbdt_offset + 9, 0xffff_ffff);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));

    // Restore the CBDT payload and instead point the CBLC location just past
    // the declared CBDT table. The glyph is valid only if both the bitmap index
    // and the data table agree on the referenced byte range.
    writeU32Test(bytes, cbdt_offset + 9, original_data_len);
    writeU32Test(bytes, cblc_offset + 68, 0xffff_ff00); // indexSubTable.imageDataOffset
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "CBDT non-PNG payloads validate metrics and compound glyph references" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildCbdtPngTtf(allocator);
        defer allocator.free(bytes);

        const cblc_offset = try sfntTableOffset(bytes, "CBLC");
        const cbdt_offset = try sfntTableOffset(bytes, "CBDT");
        writeU16Test(bytes, cblc_offset + 66, 1); // image format 1: byte-aligned bitmap data.
        writeU16Test(bytes, cblc_offset + 74, 6); // CBLC now declares only six CBDT bytes.
        bytes[cbdt_offset + 4] = 2; // height
        bytes[cbdt_offset + 5] = 9; // width: two bytes per row when byte-aligned.
        // Only one byte follows the five-byte small metrics block, but the
        // bitmap metrics require four bytes of image data.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildCbdtPngTtf(allocator);
        defer allocator.free(bytes);

        const cblc_offset = try sfntTableOffset(bytes, "CBLC");
        const cbdt_offset = try sfntTableOffset(bytes, "CBDT");
        writeU16Test(bytes, cblc_offset + 66, 8); // image format 8: small metrics + component array.
        writeU16Test(bytes, cblc_offset + 74, 12);
        bytes[cbdt_offset + 4] = 1; // height
        bytes[cbdt_offset + 5] = 1; // width
        bytes[cbdt_offset + 9] = 0; // pad
        writeU16Test(bytes, cbdt_offset + 10, 1); // one component.
        writeU16Test(bytes, cbdt_offset + 12, 2); // maxp declares glyph IDs 0 and 1 only.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "CBDT non-PNG image formats are skipped by PNG lookup" {
    var bytes: [80]u8 = .{0} ** 80;
    writeU16Test(&bytes, 0, 2); // CBLC major version.
    writeU16Test(&bytes, 2, 0);
    writeU32Test(&bytes, 4, 1); // one bitmapSizeTable.

    writeU32Test(&bytes, 8, 56); // IndexSubTableArray follows the strike directory.
    writeU32Test(&bytes, 12, 20);
    writeU32Test(&bytes, 16, 1);
    writeU16Test(&bytes, 48, 1);
    writeU16Test(&bytes, 50, 1);
    bytes[52] = 16;

    writeU16Test(&bytes, 56, 1);
    writeU16Test(&bytes, 58, 1);
    writeU32Test(&bytes, 60, 8);

    writeU16Test(&bytes, 64, 3); // IndexSubTable format 3.
    writeU16Test(&bytes, 66, 1); // CBDT image format 1 is not PNG data.
    writeU32Test(&bytes, 68, 0);
    writeU16Test(&bytes, 72, 0);
    writeU16Test(&bytes, 74, 4);

    const cblc = TableRecord{ .tag = .{ 'C', 'B', 'L', 'C' }, .checksum = 0, .offset = 0, .length = 76 };
    const cbdt = TableRecord{ .tag = .{ 'C', 'B', 'D', 'T' }, .checksum = 0, .offset = 76, .length = 4 };
    try std.testing.expectEqual(@as(?BitmapGlyphPng, null), try cblcGlyphPng(&bytes, cblc, cbdt, 2, 1, 16));
}

test "cmap format 4 idRangeOffset stays inside declared subtable length" {
    var valid: [26]u8 = .{0} ** 26;
    writeU16Test(&valid, 0, 4);
    writeU16Test(&valid, 2, valid.len);
    writeU16Test(&valid, 6, 2); // one segment
    writeU16Test(&valid, 14, 'A'); // endCode[0]
    writeU16Test(&valid, 18, 'A'); // startCode[0]
    writeI16Test(&valid, 20, 0); // idDelta[0]
    writeU16Test(&valid, 22, 2); // glyphIdArray starts immediately after idRangeOffset[0]
    writeU16Test(&valid, 24, 99);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 99), try glyphIndexFormat4(&valid, 0, 'A'));

    var truncated: [32]u8 = .{0} ** 32;
    writeU16Test(&truncated, 0, 4);
    writeU16Test(&truncated, 2, 24);
    writeU16Test(&truncated, 6, 2);
    writeU16Test(&truncated, 14, 'A');
    writeU16Test(&truncated, 18, 'A');
    writeI16Test(&truncated, 20, 0);
    writeU16Test(&truncated, 22, 2);
    writeU16Test(&truncated, 24, 99);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat4(&truncated, 0, 'A'));
}

test "cmap 32-bit subtables stay inside declared lengths" {
    var format10: [24]u8 = .{0} ** 24;
    writeU16Test(&format10, 0, 10);
    writeU32Test(&format10, 4, 20); // Declared length excludes the glyph array below.
    writeU32Test(&format10, 12, 0x1f600);
    writeU32Test(&format10, 16, 1);
    writeU16Test(&format10, 20, 7);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat10(&format10, 0, 20, 0x1f600));

    var format12: [28]u8 = .{0} ** 28;
    writeU16Test(&format12, 0, 12);
    writeU32Test(&format12, 4, 16); // Declared length excludes the group below.
    writeU32Test(&format12, 12, 1);
    writeU32Test(&format12, 16, 'A');
    writeU32Test(&format12, 20, 'A');
    writeU32Test(&format12, 24, 9);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat12(&format12, 0, 16, 'A'));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 9), try glyphIndexFormat12(&format12, 0, 28, 'A'));

    var format13: [28]u8 = .{0} ** 28;
    writeU16Test(&format13, 0, 13);
    writeU32Test(&format13, 4, 16); // Declared length excludes the group below.
    writeU32Test(&format13, 12, 1);
    writeU32Test(&format13, 16, 0);
    writeU32Test(&format13, 20, 0x10ffff);
    writeU32Test(&format13, 24, 3);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat13(&format13, 0, 16, 'A'));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 3), try glyphIndexFormat13(&format13, 0, 28, 0x1f600));
}

test "cmap format 14 lookup mirrors parse-time selector and payload validation" {
    var valid: [38]u8 = .{0} ** 38;
    writeU16Test(&valid, 0, 14);
    writeU32Test(&valid, 2, valid.len);
    writeU32Test(&valid, 6, 1);
    writeU24Test(&valid, 10, 0xfe0f);
    writeU32Test(&valid, 13, 21);
    writeU32Test(&valid, 17, 29);
    writeU32Test(&valid, 21, 1);
    writeU24Test(&valid, 25, 'B');
    valid[28] = 0;
    writeU32Test(&valid, 29, 1);
    writeU24Test(&valid, 33, 'A');
    writeU16Test(&valid, 36, 3);

    const records_end = try cmapFormat14RecordsEnd(valid.len, 1);
    try validateCmapFormat14(&valid, 0, valid.len);
    try std.testing.expectEqual(@as(usize, 21), try validateCmapFormat14PayloadOffset(21, records_end, valid.len));
    try std.testing.expectEqual(@as(?glyph_mod.GlyphId, 3), try glyphIndexFormat14NonDefault(&valid, 29, valid.len, 'A'));
    try std.testing.expect(try glyphIndexFormat14DefaultContains(&valid, 21, valid.len, 'B'));

    var alias_record_directory = valid;
    writeU32Test(&alias_record_directory, 17, 20);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat14(&alias_record_directory, 0, alias_record_directory.len));
    try std.testing.expectError(error.BadSfnt, validateCmapFormat14PayloadOffset(20, records_end, alias_record_directory.len));

    var invalid_selector = valid;
    writeU24Test(&invalid_selector, 10, 'A');
    try std.testing.expectError(error.BadSfnt, validateCmapFormat14(&invalid_selector, 0, invalid_selector.len));

    var unsorted_selector_records: [56]u8 = .{0} ** 56;
    writeU16Test(&unsorted_selector_records, 0, 14);
    writeU32Test(&unsorted_selector_records, 2, unsorted_selector_records.len);
    writeU32Test(&unsorted_selector_records, 6, 2);
    writeU24Test(&unsorted_selector_records, 10, 0xe0100);
    writeU32Test(&unsorted_selector_records, 13, 32);
    writeU24Test(&unsorted_selector_records, 21, 0xfe0f);
    writeU32Test(&unsorted_selector_records, 24, 40);
    writeU32Test(&unsorted_selector_records, 32, 1);
    writeU24Test(&unsorted_selector_records, 36, 'A');
    writeU32Test(&unsorted_selector_records, 40, 1);
    writeU24Test(&unsorted_selector_records, 44, 'B');
    try std.testing.expectError(error.BadSfnt, validateCmapFormat14(&unsorted_selector_records, 0, unsorted_selector_records.len));
}

test "cmap format 2 validates subheader and glyph-array bounds" {
    var valid: [12 + 536]u8 = .{0} ** (12 + 536);
    writeU16Test(&valid, 2, 1);
    writeU16Test(&valid, 4, 3);
    writeU16Test(&valid, 6, 2);
    writeU32Test(&valid, 8, 12);
    const subtable = 12;
    writeU16Test(&valid, subtable, 2);
    writeU16Test(&valid, subtable + 2, 536);
    writeU16Test(&valid, subtable + 6 + 0x12 * 2, 8); // High byte 0x12 uses SubHeader[1].
    writeU16Test(&valid, subtable + 518, 0);
    writeU16Test(&valid, subtable + 520, 0);
    writeU16Test(&valid, subtable + 526, 0x34);
    writeU16Test(&valid, subtable + 528, 1);
    writeI16Test(&valid, subtable + 530, 0);
    writeU16Test(&valid, subtable + 532, 2);
    writeU16Test(&valid, subtable + 534, 77);

    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = valid.len,
    };
    const subtables = try parseCmapSubtables(std.testing.allocator, &valid, cmap, 128);
    defer std.testing.allocator.free(subtables);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 77), try glyphIndexFormat2(&valid, subtable, 536, 0x1234));

    var unaligned_key = valid;
    writeU16Test(&unaligned_key, subtable + 6 + 0x12 * 2, 10);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(std.testing.allocator, &unaligned_key, cmap, 128));

    var backwards_range = valid;
    writeU16Test(&backwards_range, subtable + 532, 0);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(std.testing.allocator, &backwards_range, cmap, 128));
}

test "cmap format 6 and 10 validate declared array size and Unicode range" {
    var format6: [12]u8 = .{0} ** 12;
    writeU16Test(&format6, 0, 6);
    writeU16Test(&format6, 2, format6.len);
    writeU16Test(&format6, 6, 'A');
    writeU16Test(&format6, 8, 1);
    writeU16Test(&format6, 10, 5);
    try validateCmapFormat6(&format6, 0, format6.len, true);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 5), try glyphIndexFormat6(&format6, 0, 'A'));

    var truncated_format6 = format6;
    writeU16Test(&truncated_format6, 2, 10);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat6(&truncated_format6, 0, 10, true));

    var overflowing_format6: [14]u8 = .{0} ** 14;
    writeU16Test(&overflowing_format6, 0, 6);
    writeU16Test(&overflowing_format6, 2, overflowing_format6.len);
    writeU16Test(&overflowing_format6, 6, 0xffff);
    writeU16Test(&overflowing_format6, 8, 2);
    writeU16Test(&overflowing_format6, 10, 1);
    writeU16Test(&overflowing_format6, 12, 2);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat6(&overflowing_format6, 0, overflowing_format6.len, true));

    var format10: [22]u8 = .{0} ** 22;
    writeU16Test(&format10, 0, 10);
    writeU32Test(&format10, 4, format10.len);
    writeU32Test(&format10, 12, 0x10ffff);
    writeU32Test(&format10, 16, 1);
    writeU16Test(&format10, 20, 9);
    try validateCmapFormat10(&format10, 0, format10.len);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 9), try glyphIndexFormat10(&format10, 0, format10.len, 0x10ffff));

    var overflowing_format10 = format10;
    writeU32Test(&overflowing_format10, 12, 0x110000);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat10(&overflowing_format10, 0, overflowing_format10.len));

    var surrogate_format10 = format10;
    writeU32Test(&surrogate_format10, 12, 0xd800);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat10(&surrogate_format10, 0, surrogate_format10.len));

    var surrogate_spanning_format10: [24]u8 = .{0} ** 24;
    writeU16Test(&surrogate_spanning_format10, 0, 10);
    writeU32Test(&surrogate_spanning_format10, 4, surrogate_spanning_format10.len);
    writeU32Test(&surrogate_spanning_format10, 12, 0xd7ff);
    writeU32Test(&surrogate_spanning_format10, 16, 2);
    writeU16Test(&surrogate_spanning_format10, 20, 9);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat10(&surrogate_spanning_format10, 0, surrogate_spanning_format10.len));

    var extra_bytes_format10: [24]u8 = .{0} ** 24;
    writeU16Test(&extra_bytes_format10, 0, 10);
    writeU32Test(&extra_bytes_format10, 4, extra_bytes_format10.len);
    writeU32Test(&extra_bytes_format10, 12, 'A');
    writeU32Test(&extra_bytes_format10, 16, 1);
    writeU16Test(&extra_bytes_format10, 20, 9);
    try std.testing.expectError(error.BadSfnt, validateCmapFormat10(&extra_bytes_format10, 0, extra_bytes_format10.len));
}

test "cmap parser rejects subtable length past cmap table boundary" {
    const allocator = std.testing.allocator;
    var data: [44]u8 = .{0} ** 44;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 20,
    };

    writeU16Test(&data, 0, 0);
    writeU16Test(&data, 2, 1);
    writeU16Test(&data, 4, 3);
    writeU16Test(&data, 6, 10);
    writeU32Test(&data, 8, 12);
    writeU16Test(&data, 12, 12);
    writeU32Test(&data, 16, 28);
    writeU32Test(&data, 24, 1);
    writeU32Test(&data, 28, 'A');
    writeU32Test(&data, 32, 'A');
    writeU32Test(&data, 36, 9);

    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &data, cmap, 128));
}

test "cmap format 0 length is fixed at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildByteEncodingCmapTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    inline for (.{ @as(u16, 261), @as(u16, 263) }) |length| {
        const bytes = try test_font.buildByteEncodingCmapTtf(allocator);
        defer allocator.free(bytes);
        const cmap_offset = try sfntTableOffset(bytes, "cmap");
        // Format 0 has no variable payload: padding belongs to the enclosing
        // SFNT table, not to the cmap subtable's declared length.
        writeU16Test(bytes, cmap_offset + 14, length);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "cmap header version and encoding records are canonical" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 282,
    };

    var valid: [282]u8 = .{0} ** 282;
    writeU16Test(&valid, 0, 0);
    writeU16Test(&valid, 2, 2);
    writeU16Test(&valid, 4, 0);
    writeU16Test(&valid, 6, 0);
    writeU32Test(&valid, 8, 20);
    writeU16Test(&valid, 12, 0);
    writeU16Test(&valid, 14, 1);
    writeU32Test(&valid, 16, 20);
    writeU16Test(&valid, 20, 0);
    writeU16Test(&valid, 22, 262);

    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 1);
    defer allocator.free(subtables);
    try std.testing.expectEqual(@as(usize, 2), subtables.len);

    var bad_version = valid;
    writeU16Test(&bad_version, 0, 1);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bad_version, cmap, 1));

    var duplicate_encoding = valid;
    writeU16Test(&duplicate_encoding, 14, 0);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &duplicate_encoding, cmap, 1));

    var unsorted_encoding = valid;
    writeU16Test(&unsorted_encoding, 6, 1);
    writeU16Test(&unsorted_encoding, 14, 0);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &unsorted_encoding, cmap, 1));

    var header_alias = valid;
    writeU32Test(&header_alias, 8, 0); // Reinterprets the cmap version/count fields as a subtable header.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &header_alias, cmap, 1));

    var record_alias = valid;
    writeU32Test(&record_alias, 8, 12); // Points into the second EncodingRecord rather than a child subtable.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &record_alias, cmap, 1));
}

test "cmap format 4 parser rejects malformed segment metadata" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 44,
    };

    var valid: [44]u8 = .{0} ** 44;
    writeCmapFormat4TwoSegmentHeaderTest(&valid, valid.len - 12);
    writeCmapFormat4SegmentTest(&valid, 0, 'A', 'A', @as(i16, 1) - @as(i16, @bitCast(@as(u16, 'A'))), 0);
    writeCmapFormat4SegmentTest(&valid, 1, 0xffff, 0xffff, 1, 0);
    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var nonzero_reserved_pad = valid;
    writeU16Test(&nonzero_reserved_pad, 30, 1);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &nonzero_reserved_pad, cmap, 512));

    var odd_range_offset = valid;
    writeCmapFormat4SegmentTest(&odd_range_offset, 0, 'A', 'A', 0, 1);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &odd_range_offset, cmap, 512));

    var unsorted = valid;
    writeCmapFormat4SegmentTest(&unsorted, 1, 0x0040, 0xffff, 1, 0);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &unsorted, cmap, 512));

    var missing_sentinel = valid;
    writeCmapFormat4SegmentTest(&missing_sentinel, 1, 'Z', 'Z', 1, 0);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &missing_sentinel, cmap, 512));
}

test "cmap format 4 parser validates full idRangeOffset segment span" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 48,
    };

    var bytes: [48]u8 = .{0} ** 48;
    writeCmapFormat4TwoSegmentHeaderTest(&bytes, 36); // Declared subtable ends before the glyph array for 'C'.
    writeCmapFormat4SegmentTest(&bytes, 0, 'A', 'C', 0, 4);
    writeCmapFormat4SegmentTest(&bytes, 1, 0xffff, 0xffff, 1, 0);
    writeU16Test(&bytes, 44, 7); // Glyph for 'A' would fit.
    writeU16Test(&bytes, 46, 9); // Glyph for 'B' would fit; 'C' would not.

    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bytes, cmap, 512));
}

test "Unicode cmap subtables reject surrogate and non-scalar character ranges" {
    const allocator = std.testing.allocator;

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 44,
        };
        var surrogate_format4: [44]u8 = .{0} ** 44;
        writeCmapFormat4TwoSegmentHeaderTest(&surrogate_format4, surrogate_format4.len - 12);
        writeCmapFormat4SegmentTest(&surrogate_format4, 0, 0xd7ff, 0xd800, 0x2802, 0);
        writeCmapFormat4SegmentTest(&surrogate_format4, 1, 0xffff, 0xffff, 1, 0);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &surrogate_format4, cmap, 512));

        var symbol_format4 = surrogate_format4;
        writeU16Test(&symbol_format4, 6, 0); // Windows symbol encoding is not a Unicode-scalar cmap.
        const subtables = try parseCmapSubtables(allocator, &symbol_format4, cmap, 512);
        allocator.free(subtables);
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 24,
        };
        var surrogate_format6: [24]u8 = .{0} ** 24;
        writeU16Test(&surrogate_format6, 0, 0);
        writeU16Test(&surrogate_format6, 2, 1);
        writeU16Test(&surrogate_format6, 4, 3);
        writeU16Test(&surrogate_format6, 6, 1);
        writeU32Test(&surrogate_format6, 8, 12);
        writeU16Test(&surrogate_format6, 12, 6);
        writeU16Test(&surrogate_format6, 14, 12);
        writeU16Test(&surrogate_format6, 18, 0xd800);
        writeU16Test(&surrogate_format6, 20, 1);
        writeU16Test(&surrogate_format6, 22, 1);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &surrogate_format6, cmap, 512));
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 40,
        };
        var surrogate_format12: [40]u8 = .{0} ** 40;
        writeCmapFormat12HeaderTest(&surrogate_format12, surrogate_format12.len - 12, 1);
        writeCmapGroupTest(&surrogate_format12, 28, 0xd7ff, 0xe000, 1);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &surrogate_format12, cmap, 512));

        var nonscalar_format12 = surrogate_format12;
        writeCmapGroupTest(&nonscalar_format12, 28, 0x110000, 0x110000, 1);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &nonscalar_format12, cmap, 512));
    }
}

test "cmap platform and encoding records allow only compatible formats" {
    const allocator = std.testing.allocator;

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 44,
        };
        var format4: [44]u8 = .{0} ** 44;
        writeCmapFormat4TwoSegmentHeaderTest(&format4, format4.len - 12);
        writeCmapFormat4SegmentTest(&format4, 0, 'A', 'A', @as(i16, 1) - @as(i16, @bitCast(@as(u16, 'A'))), 0);
        writeCmapFormat4SegmentTest(&format4, 1, 0xffff, 0xffff, 1, 0);
        const subtables = try parseCmapSubtables(allocator, &format4, cmap, 512);
        allocator.free(subtables);

        var variation_sequence_format4 = format4;
        writeU16Test(&variation_sequence_format4, 4, 0);
        writeU16Test(&variation_sequence_format4, 6, 5);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &variation_sequence_format4, cmap, 512));

        var full_repertoire_format4 = format4;
        writeU16Test(&full_repertoire_format4, 6, 10);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &full_repertoire_format4, cmap, 512));
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 40,
        };
        var format12: [40]u8 = .{0} ** 40;
        writeCmapFormat12HeaderTest(&format12, format12.len - 12, 1);
        writeCmapGroupTest(&format12, 28, 0x100, 0x100, 1);
        const subtables = try parseCmapSubtables(allocator, &format12, cmap, 512);
        allocator.free(subtables);

        var bmp_format12 = format12;
        writeU16Test(&bmp_format12, 6, 1);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bmp_format12, cmap, 512));

        var last_resort_format12 = format12;
        writeU16Test(&last_resort_format12, 4, 0);
        writeU16Test(&last_resort_format12, 6, 6);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &last_resort_format12, cmap, 512));

        var format13 = last_resort_format12;
        writeU16Test(&format13, 12, 13);
        const format13_subtables = try parseCmapSubtables(allocator, &format13, cmap, 512);
        allocator.free(format13_subtables);

        var windows_format13 = format13;
        writeU16Test(&windows_format13, 4, 3);
        writeU16Test(&windows_format13, 6, 10);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &windows_format13, cmap, 512));
    }

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 22,
        };
        var format14: [22]u8 = .{0} ** 22;
        writeCmapFormat14HeaderTest(&format14, 10, 0);
        const subtables = try parseCmapSubtables(allocator, &format14, cmap, 512);
        allocator.free(subtables);

        var non_uvs_format14 = format14;
        writeU16Test(&non_uvs_format14, 4, 3);
        writeU16Test(&non_uvs_format14, 6, 10);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &non_uvs_format14, cmap, 512));
    }
}

test "GPOS glyph ids are validated against maxp glyph count" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalGposTtf(allocator);
        defer allocator.free(bytes);
        const gpos_offset = try sfntTableOffset(bytes, "GPOS");
        // The fixture declares maxp.numGlyphs == 2, so the PairValueRecord's
        // secondGlyph must be 0 or 1. Runtime shaping might never see this
        // pair, but parse-time validation should reject the dangling glyph id.
        writeU16Test(bytes, gpos_offset + 56, 2);
        try std.testing.expectError(error.BadGpos, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
        defer allocator.free(bytes);
        const gpos_offset = try sfntTableOffset(bytes, "GPOS");
        writeU16Test(bytes, gpos_offset + 42, 2); // SinglePos Coverage glyph.
        try std.testing.expectError(error.BadGpos, Font.parse(allocator, bytes));
    }
}

test "GSUB glyph ids are validated against maxp glyph count at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        const gsub_offset = try sfntTableOffset(bytes, "GSUB");
        // The fixture declares maxp.numGlyphs == 3. A ligature result glyph of
        // 3 is structurally well-formed GSUB data, but it cannot be shaped into
        // this face because later metrics/outline lookups only cover glyphs 0-2.
        writeU16Test(bytes, gsub_offset + 46, 3);
        try std.testing.expectError(error.BadGsub, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildReverseChainingGsubTtf(allocator);
        defer allocator.free(bytes);
        const gsub_offset = try sfntTableOffset(bytes, "GSUB");
        // ReverseChainSingleSubst substitutes are often applied late and only
        // for matching context. Parse-time validation should still reject a
        // latent out-of-range replacement before shaping exposes it.
        writeU16Test(bytes, gsub_offset + 72, 4);
        try std.testing.expectError(error.BadGsub, Font.parse(allocator, bytes));
    }
}

test "cmap glyph ids are validated against maxp glyph count" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const cmap_offset = try sfntTableOffset(bytes, "cmap");
        const format4_offset = cmap_offset + 12;
        // The fixture declares maxp.numGlyphs == 2, so glyph id 2 is outside
        // the usable glyph set even though the format-4 segment itself is
        // structurally well-formed.
        writeI16Test(bytes, format4_offset + 24, @as(i16, 2) - @as(i16, @bitCast(@as(u16, 'A'))));
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var format12: [40]u8 = .{0} ** 40;
        writeCmapFormat12HeaderTest(&format12, format12.len - 12, 1);
        writeCmapGroupTest(&format12, 28, 0x100, 0x102, 2);

        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = format12.len,
        };
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &format12, cmap, 4));
    }
}

test "cmap format 8 validates mixed-width structure and lookup" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 8244,
    };

    var valid: [8244]u8 = .{0} ** 8244;
    writeCmapFormat8HeaderTest(&valid, valid.len - 12, 2);
    setCmapFormat8Is32Test(&valid, 1, true);
    writeCmapGroupTest(&valid, 8220, 'A', 'A', 5);
    writeCmapGroupTest(&valid, 8232, 0x10000, 0x10001, 6);

    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 16);
    defer allocator.free(subtables);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 5), try glyphIndexFormat8(&valid, 12, valid.len - 12, 'A'));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 6), try glyphIndexFormat8(&valid, 12, valid.len - 12, 0x10000));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 7), try glyphIndexFormat8(&valid, 12, valid.len - 12, 0x10001));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 0), try glyphIndexFormat8(&valid, 12, valid.len - 12, 0x20000));

    var bad_reserved = valid;
    writeU16Test(&bad_reserved, 14, 1);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bad_reserved, cmap, 16));

    var extra_bytes = valid;
    writeU32Test(&extra_bytes, 16, valid.len - 10);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &extra_bytes, cmap, 16));

    var missing_is32 = valid;
    setCmapFormat8Is32Test(&missing_is32, 1, false);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &missing_is32, cmap, 16));

    var bmp_marked_32 = valid;
    setCmapFormat8Is32Test(&bmp_marked_32, 'A', true);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bmp_marked_32, cmap, 16));

    var unsorted = valid;
    writeCmapGroupTest(&unsorted, 8232, 0x40, 0x40, 6);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &unsorted, cmap, 16));

    var bad_glyph = valid;
    writeCmapGroupTest(&bad_glyph, 8232, 0x10000, 0x10001, 15);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bad_glyph, cmap, 16));
}

test "cmap segmented groups must be sorted and disjoint" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 52,
    };

    var valid: [52]u8 = .{0} ** 52;
    writeCmapFormat12HeaderTest(&valid, valid.len - 12, 2);
    writeCmapGroupTest(&valid, 28, 0x100, 0x1ff, 4);
    writeCmapGroupTest(&valid, 40, 0x200, 0x200, 0x104);
    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var unsorted = valid;
    writeCmapGroupTest(&unsorted, 40, 0x050, 0x060, 0x104);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &unsorted, cmap, 512));

    var overlapping = valid;
    writeCmapGroupTest(&overlapping, 40, 0x1ff, 0x200, 0x104);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &overlapping, cmap, 512));
}

test "cmap extended subtables require a zero reserved field" {
    const allocator = std.testing.allocator;

    {
        var format10: [34]u8 = .{0} ** 34;
        writeU16Test(&format10, 0, 0); // cmap version.
        writeU16Test(&format10, 2, 1);
        writeU16Test(&format10, 4, 0); // Unicode full repertoire.
        writeU16Test(&format10, 6, 4);
        writeU32Test(&format10, 8, 12);
        writeU16Test(&format10, 12, 10);
        writeU16Test(&format10, 14, 1); // Reserved UInt16 must remain zero.
        writeU32Test(&format10, 16, 22);
        writeU32Test(&format10, 24, 0x10000);
        writeU32Test(&format10, 28, 1);
        writeU16Test(&format10, 32, 1);

        const cmap: TableRecord = .{ .tag = .{ 'c', 'm', 'a', 'p' }, .checksum = 0, .offset = 0, .length = format10.len };
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &format10, cmap, 4));
    }

    {
        var format12: [40]u8 = .{0} ** 40;
        writeCmapFormat12HeaderTest(&format12, format12.len - 12, 1);
        writeU16Test(&format12, 14, 1); // Reserved UInt16 must remain zero.
        writeCmapGroupTest(&format12, 28, 0x100, 0x100, 1);

        const cmap: TableRecord = .{ .tag = .{ 'c', 'm', 'a', 'p' }, .checksum = 0, .offset = 0, .length = format12.len };
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &format12, cmap, 4));
    }

    {
        var format13: [40]u8 = .{0} ** 40;
        writeU16Test(&format13, 0, 0); // cmap version.
        writeU16Test(&format13, 2, 1);
        writeU16Test(&format13, 4, 0); // Unicode last-resort cmap.
        writeU16Test(&format13, 6, 6);
        writeU32Test(&format13, 8, 12);
        writeU16Test(&format13, 12, 13);
        writeU16Test(&format13, 14, 1); // Reserved UInt16 must remain zero.
        writeU32Test(&format13, 16, 28);
        writeU32Test(&format13, 24, 1);
        writeCmapGroupTest(&format13, 28, 0x100, 0x1ff, 1);

        const cmap: TableRecord = .{ .tag = .{ 'c', 'm', 'a', 'p' }, .checksum = 0, .offset = 0, .length = format13.len };
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &format13, cmap, 4));
    }
}

test "cmap format 14 UVS offsets cannot overlap selector records" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 41,
    };

    var valid: [41]u8 = .{0} ** 41;
    writeCmapFormat14HeaderTest(&valid, 29, 1);
    writeU24Test(&valid, 22, 0x00fe0f); // Variation selector.
    writeU32Test(&valid, 25, 21); // Default UVS table starts after the selector record array.
    writeU32Test(&valid, 33, 1); // One default UVS range.
    writeU24Test(&valid, 37, 'A');
    valid[40] = 0; // additionalCount.
    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var default_overlap = valid;
    writeU32Test(&default_overlap, 25, 17); // Reinterprets selector-record fields as DefaultUVS data.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &default_overlap, cmap, 512));

    var non_default_overlap = valid;
    writeU32Test(&non_default_overlap, 25, 0);
    writeU32Test(&non_default_overlap, 29, 17); // Same metadata-overlap issue for NonDefaultUVS.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &non_default_overlap, cmap, 512));
}

test "cmap format 14 validates selectors and UVS Unicode scalar values" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 50,
    };

    var valid: [50]u8 = .{0} ** 50;
    writeCmapFormat14HeaderTest(&valid, 38, 1);
    writeU24Test(&valid, 22, 0x0e0100); // Supplemental variation selector.
    writeU32Test(&valid, 25, 21);
    writeU32Test(&valid, 29, 29);
    writeU32Test(&valid, 33, 1);
    writeU24Test(&valid, 37, 'A');
    valid[40] = 0;
    writeU32Test(&valid, 41, 1);
    writeU24Test(&valid, 45, 'B');
    writeU16Test(&valid, 48, 1);
    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var bad_selector = valid;
    writeU24Test(&bad_selector, 22, 'A');
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &bad_selector, cmap, 512));

    var surrogate_default = valid;
    writeU24Test(&surrogate_default, 37, 0xd800);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &surrogate_default, cmap, 512));

    var spanning_default = valid;
    writeU24Test(&spanning_default, 37, 0xd7ff);
    spanning_default[40] = 1;
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &spanning_default, cmap, 512));

    var surrogate_non_default = valid;
    writeU24Test(&surrogate_non_default, 45, 0xd800);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &surrogate_non_default, cmap, 512));

    var duplicate_sequence = valid;
    writeU24Test(&duplicate_sequence, 45, 'A'); // 'A' is already covered by the DefaultUVS range.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &duplicate_sequence, cmap, 512));

    var overlapping_sets = valid;
    overlapping_sets[40] = 1; // DefaultUVS covers 'A' and 'B'; NonDefaultUVS maps 'B'.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &overlapping_sets, cmap, 512));
}

test "cmap format 14 UVS payloads cannot overlap or alias" {
    const allocator = std.testing.allocator;
    const cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = 70,
    };

    var valid: [70]u8 = .{0} ** 70;
    writeCmapFormat14HeaderTest(&valid, 58, 2);
    writeU24Test(&valid, 22, 0x00fe0e);
    writeU32Test(&valid, 25, 32); // Selector 1 DefaultUVS: absolute 44..52.
    writeU24Test(&valid, 33, 0x00fe0f);
    writeU32Test(&valid, 40, 40); // Selector 2 NonDefaultUVS: absolute 52..61.
    writeU32Test(&valid, 44, 1);
    writeU24Test(&valid, 48, 'A');
    valid[51] = 0;
    writeU32Test(&valid, 52, 1);
    writeU24Test(&valid, 56, 'B');
    writeU16Test(&valid, 59, 1);
    const subtables = try parseCmapSubtables(allocator, &valid, cmap, 512);
    allocator.free(subtables);

    var cross_selector_alias = valid;
    writeU32Test(&cross_selector_alias, 40, 32); // Reuses selector 1's DefaultUVS bytes as selector 2 NonDefaultUVS.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &cross_selector_alias, cmap, 512));

    var same_selector_overlap = valid;
    writeU32Test(&same_selector_overlap, 29, 36); // Starts inside selector 1's DefaultUVS payload.
    writeU32Test(&same_selector_overlap, 48, 1);
    writeU24Test(&same_selector_overlap, 52, 'B');
    writeU16Test(&same_selector_overlap, 55, 1);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &same_selector_overlap, cmap, 512));

    var cross_selector_partial_overlap = same_selector_overlap;
    writeU32Test(&cross_selector_partial_overlap, 29, 0);
    writeU32Test(&cross_selector_partial_overlap, 36, 36); // Selector 2 DefaultUVS starts inside selector 1's payload.
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &cross_selector_partial_overlap, cmap, 512));
}

test "simple glyf contours reject non-increasing end points" {
    var glyph_data: [24]u8 = .{0} ** 24;
    writeI16Test(&glyph_data, 0, 2); // contourCount
    writeI16Test(&glyph_data, 2, 0);
    writeI16Test(&glyph_data, 4, 0);
    writeI16Test(&glyph_data, 6, 100);
    writeI16Test(&glyph_data, 8, 100);
    writeU16Test(&glyph_data, 10, 0);
    writeU16Test(&glyph_data, 12, 0); // Repeats the first contour end.
    writeU16Test(&glyph_data, 14, 0); // instructionLength
    glyph_data[16] = 0x31;

    var outline = glyph_mod.GlyphOutline.init(
        std.testing.allocator,
        1,
        .{ .x_min = 0, .y_min = 0, .x_max = 100, .y_max = 100 },
        500,
        0,
    );
    defer outline.deinit();

    try std.testing.expectError(error.InvalidGlyph, appendSimpleGlyph(&outline, &glyph_data, 2, Transform.identity()));
}

test "simple glyf programs and coordinate streams validate at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        writeU16Test(bytes, glyph_one + 12, 15); // instructionLength exceeds the remaining glyph byte range.

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        bytes[glyph_one + 14] = 0x39; // REPEAT_FLAG on a normal on-curve point.
        bytes[glyph_one + 15] = 3; // Expands past endPtsOfContours[0] == 2.

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        // Three flags with neither SHORT_VECTOR nor SAME_OR_POSITIVE set require
        // three 16-bit X deltas and three 16-bit Y deltas, more than this
        // declared glyph range contains after the flag stream.
        bytes[glyph_one + 14] = 0x01;
        bytes[glyph_one + 15] = 0x01;
        bytes[glyph_one + 16] = 0x01;

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }
}

test "core metrics and loca stay inside declared table lengths" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{ "head", "hhea", "maxp" }, .{ 52, 34, 4 }) |tag, length| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, tag, length);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, "hmtx", 6);
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, "loca", 4);
        try std.testing.expectError(error.InvalidLoca, Font.parse(allocator, bytes));
    }
}

test "vertical metric tables validate paired count and vmtx length at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, "vmtx", 4); // Missing the compressed top side bearing for glyph 1.
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset = try sfntTableOffset(bytes, "vhea");
        writeU16Test(bytes, vhea_offset + 34, 0);
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));

        writeU16Test(bytes, vhea_offset + 34, 3); // More full vertical metrics than maxp.numGlyphs.
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableTag(bytes, "vmtx", "zzzz");
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableTag(bytes, "vhea", "vhdz");
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset = try sfntTableOffset(bytes, "vhea");
        writeU16Test(bytes, vhea_offset + 24, 1); // Reserved fields must be zero.
        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }
}

test "loca offsets are validated against glyf at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const loca_offset = try sfntTableOffset(bytes, "loca");
        writeU16Test(bytes, loca_offset + 4, 1); // Third entry moves backward from glyph 0's end.
        try std.testing.expectError(error.InvalidLoca, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const loca_offset = try sfntTableOffset(bytes, "loca");
        writeU16Test(bytes, loca_offset + 4, 22); // Short format stores offsets divided by two; 44 > glyf.len.
        try std.testing.expectError(error.InvalidLoca, Font.parse(allocator, bytes));
    }
}

test "compound glyf components are validated against maxp at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    const glyf_offset = try sfntTableOffset(bytes, "glyf");
    const glyph_one = glyf_offset + 12;
    writeI16Test(bytes, glyph_one, -1); // Compound glyph.
    writeU16Test(bytes, glyph_one + 10, 0x0002); // ARGS_ARE_XY_VALUES, byte args.
    writeU16Test(bytes, glyph_one + 12, 2); // maxp.numGlyphs is 2, so glyph id 2 is out of range.
    bytes[glyph_one + 14] = 0;
    bytes[glyph_one + 15] = 0;

    try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
}

test "compound glyf component flags reject conflicting transforms" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    const glyf_offset = try sfntTableOffset(bytes, "glyf");
    const glyph_one = glyf_offset + 12;
    writeI16Test(bytes, glyph_one, -1); // Compound glyph.
    // WE_HAVE_A_SCALE and WE_HAVE_AN_X_AND_Y_SCALE are mutually exclusive in a
    // component record. Accepting both would desynchronize the remaining
    // component stream and hide malformed glyph data until outline expansion.
    writeU16Test(bytes, glyph_one + 10, 0x0002 | 0x0008 | 0x0040);
    writeU16Test(bytes, glyph_one + 12, 0);
    bytes[glyph_one + 14] = 0;
    bytes[glyph_one + 15] = 0;

    try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
}

test "compound glyf component flags reject reserved and conflicting offset semantics" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{
        @as(u16, 0x0002 | 0x0010), // Bit 4 is obsolete/reserved in composite glyph records.
        @as(u16, 0x0002 | 0x0800 | 0x1000), // Scaled and unscaled offsets are mutually exclusive.
        @as(u16, 0x0002 | 0x2000), // Bits above OVERLAP_COMPOUND are not defined by glyf.
    }) |flags| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        writeI16Test(bytes, glyph_one, -1); // Compound glyph.
        writeU16Test(bytes, glyph_one + 10, flags);
        writeU16Test(bytes, glyph_one + 12, 0);
        bytes[glyph_one + 14] = 0;
        bytes[glyph_one + 15] = 0;

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }
}

test "compound glyf permits repeated USE_MY_METRICS flags" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    const glyf_offset = try sfntTableOffset(bytes, "glyf");
    const maxp_offset = try sfntTableOffset(bytes, "maxp");
    const glyph_one = glyf_offset + 12;
    writeI16Test(bytes, glyph_one, -1); // Compound glyph.
    writeU16Test(bytes, glyph_one + 10, 0x0020 | 0x0200 | 0x0002); // MORE_COMPONENTS + USE_MY_METRICS.
    writeU16Test(bytes, glyph_one + 12, 0);
    bytes[glyph_one + 14] = 0;
    bytes[glyph_one + 15] = 0;
    writeU16Test(bytes, glyph_one + 16, 0x0200 | 0x0002); // Later USE_MY_METRICS bits do not invalidate the glyph.
    writeU16Test(bytes, glyph_one + 18, 0);
    bytes[glyph_one + 20] = 0;
    bytes[glyph_one + 21] = 0;

    // Keep maxp's aggregate summaries high enough that this exercises duplicate
    // USE_MY_METRICS flags rather than component-count validation.
    writeU16Test(bytes, maxp_offset + 28, 2);
    writeU16Test(bytes, maxp_offset + 30, 1);

    var font = try Font.parse(allocator, bytes);
    font.deinit();
}

test "compound glyf point-matching arguments reject out-of-range point numbers" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{
        .{ .flags = @as(u16, 0x0001), .argument_offset = @as(usize, 14) }, // 16-bit point numbers.
        .{ .flags = @as(u16, 0x0000), .argument_offset = @as(usize, 14) }, // 8-bit point numbers.
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        const glyph_one = glyf_offset + 12;
        writeI16Test(bytes, glyph_one, -1); // Compound glyph.
        writeU16Test(bytes, glyph_one + 10, case.flags);
        writeU16Test(bytes, glyph_one + 12, 0);
        bytes[glyph_one + case.argument_offset] = 0xff; // Parent point is outside the initially empty compound.
        bytes[glyph_one + case.argument_offset + 1] = 0;

        // Keep maxp's compound summaries consistent so the rejection below is
        // specifically about interpreting point-matching arguments, not the
        // aggregate component limits checked later in glyf validation.
        writeU16Test(bytes, maxp_offset + 28, 1);
        writeU16Test(bytes, maxp_offset + 30, 1);

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }
}

test "compound glyf component graph rejects cycles at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    const glyf_offset = try sfntTableOffset(bytes, "glyf");
    const glyph_one = glyf_offset + 12;
    writeI16Test(bytes, glyph_one, -1); // Compound glyph.
    // A direct self-reference is structurally well-formed at the component
    // record level, but the component graph has no finite expansion.
    writeU16Test(bytes, glyph_one + 10, 0x0002); // ARGS_ARE_XY_VALUES, byte args.
    writeU16Test(bytes, glyph_one + 12, 1);
    bytes[glyph_one + 14] = 0;
    bytes[glyph_one + 15] = 0;

    try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
}

test "compound glyf aggregates must not exceed maxp composite limits" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        const glyph_one = glyf_offset + 12;
        writeI16Test(bytes, glyph_one, -1); // Compound glyph.
        writeU16Test(bytes, glyph_one + 10, 0x0002); // ARGS_ARE_XY_VALUES, byte args.
        writeU16Test(bytes, glyph_one + 12, 0);
        bytes[glyph_one + 14] = 0;
        bytes[glyph_one + 15] = 0;

        writeU16Test(bytes, maxp_offset + 28, 1); // maxComponentElements
        writeU16Test(bytes, maxp_offset + 30, 0); // maxComponentDepth under-reports the direct component.
        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        const glyph_one = glyf_offset + 12;
        writeI16Test(bytes, glyph_one, -1); // Compound glyph.
        writeU16Test(bytes, glyph_one + 10, 0x0020 | 0x0002); // MORE_COMPONENTS + ARGS_ARE_XY_VALUES.
        writeU16Test(bytes, glyph_one + 12, 0);
        bytes[glyph_one + 14] = 0;
        bytes[glyph_one + 15] = 0;
        writeU16Test(bytes, glyph_one + 16, 0x0002); // Second direct component.
        writeU16Test(bytes, glyph_one + 18, 0);
        bytes[glyph_one + 20] = 0;
        bytes[glyph_one + 21] = 0;

        writeU16Test(bytes, maxp_offset + 28, 1); // maxComponentElements under-reports the two direct components.
        writeU16Test(bytes, maxp_offset + 30, 1);
        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }
}

test "maxp table version and length must match the outline format" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        writeU32Test(bytes, maxp_offset, 0x00005000);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, "maxp", 6);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        writeU32Test(bytes, maxp_offset, 0x00010000);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "TrueType maxp maxZones is validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        writeU16Test(bytes, maxp_offset + 14, 1);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    inline for (.{ 0, 3 }) |bad_max_zones| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        // OpenType restricts maxZones to the glyph zone alone (1) or glyph
        // plus twilight zone (2). Values outside that set are malformed, not
        // larger production-font resource requests.
        writeU16Test(bytes, maxp_offset + 14, bad_max_zones);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "CFF CharStrings INDEX count must match maxp glyph count" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{
        @as(u16, 1),
        @as(u16, 3),
    }) |glyph_count| {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);

        const hhea_offset = try sfntTableOffset(bytes, "hhea");
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        // Keep hmtx structurally valid for both altered glyph counts so this
        // regression reaches the CFF/maxp cross-table check rather than failing
        // earlier in generic horizontal-metrics validation.
        writeU16Test(bytes, hhea_offset + 34, 1);
        writeU16Test(bytes, maxp_offset + 4, glyph_count);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "OpenType CFF table rejects malformed CFF header fields at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const cff_offset = try sfntTableOffset(bytes, "CFF ");
        bytes[cff_offset] = 2;
        try std.testing.expectError(error.BadCff, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const cff_offset = try sfntTableOffset(bytes, "CFF ");
        bytes[cff_offset + 2] = 3;
        try std.testing.expectError(error.BadCff, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(bytes);
        const cff_offset = try sfntTableOffset(bytes, "CFF ");
        bytes[cff_offset + 3] = 0;
        try std.testing.expectError(error.BadCff, Font.parse(allocator, bytes));
    }
}

test "head table invariants are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    inline for (.{
        .{ .offset = 0, .value = @as(u32, 0x00020000), .err = error.BadSfnt },
        .{ .offset = 12, .value = @as(u32, 0), .err = error.BadSfnt },
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        writeU32Test(bytes, head_offset + case.offset, case.value);
        try std.testing.expectError(case.err, Font.parse(allocator, bytes));
    }

    inline for (.{
        .{ .value = @as(u16, 15), .err = error.BadSfnt },
        .{ .value = @as(u16, 16385), .err = error.BadSfnt },
        .{ .value = @as(u16, 2), .err = error.InvalidLoca },
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        writeU16Test(bytes, head_offset + 18, case.value);
        if (case.err == error.InvalidLoca) {
            writeI16Test(bytes, head_offset + 50, @bitCast(case.value));
            writeU16Test(bytes, head_offset + 18, 1000);
        }
        try std.testing.expectError(case.err, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        writeI16Test(bytes, head_offset + 36, 701); // xMin must not exceed xMax.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        writeI16Test(bytes, head_offset + 52, 1); // glyphDataFormat is specified as zero.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "post table structural contracts are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        var post: [32]u8 = .{0} ** 32;
        writePostHeaderTest(&post, 0x00030000);
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        var post: [44]u8 = .{0} ** 44;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "A.alt");
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        var post: [36]u8 = .{0} ** 36;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 3); // Must match maxp.numGlyphs == 2.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [42]u8 = .{0} ** 42;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 4; // Only three bytes of the Pascal string are present.
        @memcpy(post[39..42], "Alt");
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [43]u8 = .{0} ** 43;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 4;
        @memcpy(post[39..43], "bad-"); // Hyphen is not valid in `post` glyph names.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [36]u8 = .{0} ** 36;
        writePostHeaderTest(&post, 0x00025000);
        writeU16Test(&post, 32, 2);
        post[34] = 0;
        post[35] = 0;
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        var post: [36]u8 = .{0} ** 36;
        writePostHeaderTest(&post, 0x00025000);
        writeU16Test(&post, 32, 2);
        post[34] = 0xff; // Glyph 0 would map to standard index -1.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [36]u8 = .{0} ** 36;
        writePostHeaderTest(&post, 0x00040000);
        writeU16Test(&post, 32, 0xffff);
        writeU16Test(&post, 34, 'A');
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        var post: [34]u8 = .{0} ** 34;
        writePostHeaderTest(&post, 0x00040000);
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [32]u8 = .{0} ** 32;
        writePostHeaderTest(&post, 0x00010000); // Format 1.0 implies exactly 258 glyphs.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [32]u8 = .{0} ** 32;
        writePostHeaderTest(&post, 0x00050000);
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "TTC face offsets cannot overlap collection metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const valid = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(valid);
    try std.testing.expectEqual(@as(usize, 1), try Font.faceCount(valid));

    var font = try Font.parse(allocator, valid);
    font.deinit();

    const overlapping = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(overlapping);
    writeU32Test(overlapping, 12, 12); // Points into the face-offset array.
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, overlapping));

    const truncated_offsets = overlapping[0..15];
    try std.testing.expectError(error.BadSfnt, Font.faceCount(truncated_offsets));
}

test "SFNT table payload ranges cannot overlap metadata or each other" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableOffset(bytes, "kern", 12); // Points into the SFNT table-record array.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        try setSfntTableOffset(bytes, "kern", head_offset);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory rejects duplicate tags" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    try setSfntTableTag(bytes, "kern", "head");

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SFNT offset table search parameters must match table count" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{ 6, 8, 10 }) |field_offset| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        writeU16Test(bytes, field_offset, try bin.readU16At(bytes, field_offset) + 1);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory tags must be strictly sorted" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const first_record = 12;
    const second_record = 28;
    var first_tag: [4]u8 = undefined;
    var second_tag: [4]u8 = undefined;
    @memcpy(&first_tag, bytes[first_record .. first_record + 4]);
    @memcpy(&second_tag, bytes[second_record .. second_record + 4]);
    @memcpy(bytes[first_record .. first_record + 4], &second_tag);
    @memcpy(bytes[second_record .. second_record + 4], &first_tag);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "name table storage offset cannot overlap metadata records" {
    var out: [16]u8 = undefined;

    var format0: [20]u8 = .{0} ** 20;
    writeU16Test(&format0, 0, 0);
    writeU16Test(&format0, 2, 1);
    writeU16Test(&format0, 4, 6); // Points at the first NameRecord, not at string storage.
    writeUtf16NameRecordTest(&format0, 6, 1, 2, 0);
    try std.testing.expectError(error.BadSfnt, readNameString(&format0, nameTableRecord(format0.len), @intFromEnum(NameId.family), &out));

    var format1: [28]u8 = .{0} ** 28;
    writeU16Test(&format1, 0, 1);
    writeU16Test(&format1, 2, 1);
    writeU16Test(&format1, 4, 20); // After langTagCount, but still inside the LangTagRecord array.
    writeUtf16NameRecordTest(&format1, 6, 1, 2, 0);
    writeU16Test(&format1, 18, 1); // langTagCount
    writeU16Test(&format1, 20, 4); // LangTagRecord.length
    writeU16Test(&format1, 22, 2); // LangTagRecord.offset
    try std.testing.expectError(error.BadSfnt, readNameString(&format1, nameTableRecord(format1.len), @intFromEnum(NameId.family), &out));
}

test "name table format 1 validates language tag storage ranges" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 24);
    writeUtf16NameRecordTest(&bytes, 6, 1, 4, 0);
    writeU16Test(&bytes, 18, 1);
    writeU16Test(&bytes, 20, 4);
    writeU16Test(&bytes, 22, 4);
    bytes[25] = 'O';
    bytes[27] = 'K';
    bytes[29] = 'e';
    bytes[31] = 'n';

    var out: [16]u8 = undefined;
    try std.testing.expectEqualStrings("OK", (try readNameString(&bytes, nameTableRecord(bytes.len), @intFromEnum(NameId.family), &out)).?);

    writeU16Test(&bytes, 22, 6);
    try std.testing.expectError(error.BadSfnt, readNameString(&bytes, nameTableRecord(bytes.len), @intFromEnum(NameId.family), &out));
}

test "name table validates every record string at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);
    const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
    const record = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.typographic_subfamily));
    writeU16Test(bytes, record + 8, 1); // UTF-16 name strings must have an even byte length.

    try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
}

test "name table validates every record storage range at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);
    const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
    const name_length: usize = @intCast(try sfntTableLength(bytes, "name"));
    const storage_offset: usize = @intCast(try bin.readU16At(bytes, name_offset + 4));
    const storage_length = name_length - storage_offset;
    const record = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.postscript_name));
    writeU16Test(bytes, record + 10, @intCast(storage_length)); // Non-empty record starts just past storage.

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "name table rejects invalid platform encodings at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtf(allocator);
    defer allocator.free(bytes);
    const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
    const record = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.family));
    writeU16Test(bytes, record, 5); // OpenType name tables only define platform IDs 0 through 4.

    try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
}

test "name table format 1 language ids reference valid UTF-16 language tags" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16Test(&bytes, 0, 1); // format 1 name table.
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 24);
    writeNameRecordTest(&bytes, 6, 3, 1, 0x8000, 1, 4, 0);
    writeU16Test(&bytes, 18, 1); // one LangTagRecord.
    writeU16Test(&bytes, 20, 4);
    writeU16Test(&bytes, 22, 4);
    bytes[25] = 'O';
    bytes[27] = 'K';
    bytes[29] = 'e';
    bytes[31] = 'n';

    try validateNameTable(&bytes, nameTableRecord(bytes.len));

    var bad_language_id = bytes;
    writeU16Test(&bad_language_id, 10, 0x8001);
    try std.testing.expectError(error.BadSfnt, validateNameTable(&bad_language_id, nameTableRecord(bad_language_id.len)));

    var bad_language_tag = bytes;
    writeU16Test(&bad_language_tag, 20, 3);
    try std.testing.expectError(error.InvalidName, validateNameTable(&bad_language_tag, nameTableRecord(bad_language_tag.len)));
}

test "SVG document glyph ranges stay within maxp glyph count" {
    var bytes: [30]u8 = .{0} ** 30;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16Test(&bytes, 12, 1); // startGlyphID.
    writeU16Test(&bytes, 14, 2); // endGlyphID is invalid when maxp.numGlyphs == 2.
    writeU32Test(&bytes, 16, 14); // document data starts after the record array.
    writeU32Test(&bytes, 20, 6);
    @memcpy(bytes[24..30], "<svg/>");

    const svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2));

    writeU16Test(&bytes, 14, 1);
    try validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2);
}

test "SVG document glyph ranges must be sorted and disjoint" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 2); // two SVGDocumentRecords.
    writeU16Test(&bytes, 12, 1); // first record covers glyph 1.
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 26); // document data starts after both records.
    writeU32Test(&bytes, 20, 6);
    writeU16Test(&bytes, 24, 2); // second record covers glyphs 2 and 3.
    writeU16Test(&bytes, 26, 3);
    writeU32Test(&bytes, 28, 32);
    writeU32Test(&bytes, 32, 6);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..48], "<svg/>");

    const svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 4);

    var overlapping = bytes;
    writeU16Test(&overlapping, 24, 1); // Overlaps glyph 1 from the first range.
    writeU16Test(&overlapping, 26, 2);
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &overlapping, svg, 4));

    var unsorted = bytes;
    writeU16Test(&unsorted, 12, 2);
    writeU16Test(&unsorted, 14, 2);
    writeU16Test(&unsorted, 24, 1); // Disjoint, but out of ascending glyph order.
    writeU16Test(&unsorted, 26, 1);
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &unsorted, svg, 4));
}

test "SVG document byte ranges reject partial overlaps" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 2); // two SVGDocumentRecords.
    writeU16Test(&bytes, 12, 0); // first record covers glyph 0.
    writeU16Test(&bytes, 14, 0);
    writeU32Test(&bytes, 16, 32); // Byte ranges need not follow glyph order.
    writeU32Test(&bytes, 20, 6);
    writeU16Test(&bytes, 24, 1); // second record covers glyph 1.
    writeU16Test(&bytes, 26, 1);
    writeU32Test(&bytes, 28, 26);
    writeU32Test(&bytes, 32, 6);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..48], "<svg/>");

    const svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2);

    var shared_document = bytes;
    writeU32Test(&shared_document, 16, 26);
    writeU32Test(&shared_document, 20, 6);
    writeU32Test(&shared_document, 28, 26);
    writeU32Test(&shared_document, 32, 6);
    try validateSvgGlyphBounds(std.testing.allocator, &shared_document, svg, 2);

    var partial_overlap: [53]u8 = .{0} ** 53;
    writeU16Test(&partial_overlap, 0, 0);
    writeU32Test(&partial_overlap, 2, 10);
    writeU16Test(&partial_overlap, 10, 2);
    writeU16Test(&partial_overlap, 12, 0);
    writeU16Test(&partial_overlap, 14, 0);
    writeU32Test(&partial_overlap, 16, 26);
    writeU32Test(&partial_overlap, 20, 17);
    writeU16Test(&partial_overlap, 24, 1);
    writeU16Test(&partial_overlap, 26, 1);
    writeU32Test(&partial_overlap, 28, 31); // Points at the nested <svg/> inside the first document.
    writeU32Test(&partial_overlap, 32, 6);
    @memcpy(partial_overlap[36..53], "<svg><svg/></svg>");
    const overlap_svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = partial_overlap.len };
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &partial_overlap, overlap_svg, 2));
}

test "SVG document payload must have a single svg root" {
    var bytes: [44]u8 = .{0} ** 44;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 14);
    writeU32Test(&bytes, 20, 20);

    const svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = bytes.len };
    @memcpy(bytes[24..44], "<svg><g></g></svg>  ");
    try validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2);

    @memcpy(bytes[24..44], "<g></g>             ");
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2));

    @memcpy(bytes[24..44], "<svg></g>           ");
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2));

    @memcpy(bytes[24..44], "<svg/><svg/>        ");
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2));
}

test "SVG document payload root is validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);
    const svg_offset: usize = @intCast(try sfntTableOffset(bytes, "SVG "));
    const document_list_offset: usize = @intCast(try bin.readU32At(bytes, svg_offset + 2));
    const document_list_start = svg_offset + document_list_offset;
    const record_start = document_list_start + 2;
    const document_offset: usize = @intCast(try bin.readU32At(bytes, record_start + 4));
    const document_start = document_list_start + document_offset;
    bytes[document_start + 1] = 'g'; // Changes the root element from <svg ...> to a non-SVG root.

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SVG document glyph range ordering is enforced at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);
    const svg_offset: usize = @intCast(try sfntTableOffset(bytes, "SVG "));

    writeU16Test(bytes, svg_offset + 0, 0); // SVG table version.
    writeU32Test(bytes, svg_offset + 2, 10); // SVGDocumentListOffset.
    writeU16Test(bytes, svg_offset + 10, 2); // two SVGDocumentRecords.
    writeU16Test(bytes, svg_offset + 12, 1);
    writeU16Test(bytes, svg_offset + 14, 1);
    writeU32Test(bytes, svg_offset + 16, 26); // first document starts after both records.
    writeU32Test(bytes, svg_offset + 20, 4);
    writeU16Test(bytes, svg_offset + 24, 1); // Invalid: overlaps the previous glyph range.
    writeU16Test(bytes, svg_offset + 26, 1);
    writeU32Test(bytes, svg_offset + 28, 30);
    writeU32Test(bytes, svg_offset + 32, 4);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SVG document byte range overlap is rejected at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSvgTtf(allocator);
    defer allocator.free(bytes);
    const svg_offset: usize = @intCast(try sfntTableOffset(bytes, "SVG "));

    writeU16Test(bytes, svg_offset + 0, 0); // SVG table version.
    writeU32Test(bytes, svg_offset + 2, 10); // SVGDocumentListOffset.
    writeU16Test(bytes, svg_offset + 10, 2); // two SVGDocumentRecords.
    writeU16Test(bytes, svg_offset + 12, 0);
    writeU16Test(bytes, svg_offset + 14, 0);
    writeU32Test(bytes, svg_offset + 16, 26); // First document: [26, 34).
    writeU32Test(bytes, svg_offset + 20, 8);
    writeU16Test(bytes, svg_offset + 24, 1);
    writeU16Test(bytes, svg_offset + 26, 1);
    writeU32Test(bytes, svg_offset + 28, 30); // Overlaps only the first document tail.
    writeU32Test(bytes, svg_offset + 32, 8);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SVG document offsets cannot overlap table metadata" {
    var header_overlap: [18]u8 = .{0} ** 18;
    writeU16Test(&header_overlap, 0, 0);
    writeU32Test(&header_overlap, 2, 6); // Points into the SVG table header's reserved field.
    const header_font = svgOnlyFont(&header_overlap);
    try std.testing.expectError(error.BadSfnt, header_font.svgGlyphDocument(1));

    var record_overlap: [28]u8 = .{0} ** 28;
    writeU16Test(&record_overlap, 0, 0);
    writeU32Test(&record_overlap, 2, 10);
    writeU16Test(&record_overlap, 10, 1);
    writeU16Test(&record_overlap, 12, 1);
    writeU16Test(&record_overlap, 14, 1);
    writeU32Test(&record_overlap, 16, 2); // Points at the SVGDocumentRecord array.
    writeU32Test(&record_overlap, 20, 4);
    @memcpy(record_overlap[24..28], "<svg");

    const record_font = svgOnlyFont(&record_overlap);
    try std.testing.expectError(error.BadSfnt, record_font.svgGlyphDocument(1));
}

test "SVG table header reserved field must be zero" {
    var bytes: [30]u8 = .{0} ** 30;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU32Test(&bytes, 6, 1); // Reserved; OpenType requires zero.
    writeU16Test(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 14);
    writeU32Test(&bytes, 20, 6);
    @memcpy(bytes[24..30], "<svg/>");

    const svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2));
}

test "SVG document length must be non-zero" {
    var bytes: [30]u8 = .{0} ** 30;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 24);
    writeU32Test(&bytes, 20, 0); // Empty documents cannot contain an SVG root.
    @memcpy(bytes[24..30], "<svg/>");

    const svg = TableRecord{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateSvgGlyphBounds(std.testing.allocator, &bytes, svg, 2));
}

test "SVG header and document length are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildSvgTtf(allocator);
        defer allocator.free(bytes);
        const svg_offset: usize = @intCast(try sfntTableOffset(bytes, "SVG "));
        writeU32Test(bytes, svg_offset + 6, 1); // Reserved header field.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildSvgTtf(allocator);
        defer allocator.free(bytes);
        const svg_offset: usize = @intCast(try sfntTableOffset(bytes, "SVG "));
        const document_list_offset: usize = @intCast(try bin.readU32At(bytes, svg_offset + 2));
        const document_list_start = svg_offset + document_list_offset;
        const record_start = document_list_start + 2;
        writeU32Test(bytes, record_start + 8, 0); // svgDocLength.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "CPAL color records cannot overlap palette index array" {
    var bytes: [20]u8 = .{0} ** 20;
    writeU16Test(&bytes, 0, 0); // version
    writeU16Test(&bytes, 2, 1); // numPaletteEntries
    writeU16Test(&bytes, 4, 2); // numPalettes: first-color-index array is 4 bytes.
    writeU16Test(&bytes, 6, 1); // numColorRecords
    writeU32Test(&bytes, 8, 14); // Must be at least 16 to sit after both palette entries.
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 0);
    bytes[16] = 10;
    bytes[17] = 20;
    bytes[18] = 30;
    bytes[19] = 40;

    const font = cpalOnlyFont(&bytes);
    try std.testing.expectError(error.BadSfnt, font.paletteColor(0, 0));
}

test "CPAL palette entries stay inside declared color records" {
    var bytes: [18]u8 = .{0} ** 18;
    writeU16Test(&bytes, 0, 0); // version
    writeU16Test(&bytes, 2, 2); // numPaletteEntries claims two colors.
    writeU16Test(&bytes, 4, 1); // numPalettes
    writeU16Test(&bytes, 6, 1); // numColorRecords only has one color.
    writeU32Test(&bytes, 8, 14);
    writeU16Test(&bytes, 12, 0);
    bytes[14] = 10;
    bytes[15] = 20;
    bytes[16] = 30;
    bytes[17] = 40;

    const font = cpalOnlyFont(&bytes);
    try std.testing.expectError(error.BadSfnt, font.paletteColor(0, 0));
}

test "CPAL palette slices must be ordered and non-overlapping" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16Test(&bytes, 0, 0); // CPAL version 0.
    writeU16Test(&bytes, 2, 2); // each palette has two entries.
    writeU16Test(&bytes, 4, 2); // two firstColorIndex entries.
    writeU16Test(&bytes, 6, 4); // four BGRA records are declared.
    writeU32Test(&bytes, 8, 16);
    writeU16Test(&bytes, 12, 0);
    writeU16Test(&bytes, 14, 2);

    const cpal = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(u16, 2), try validateCpalPaletteEntries(&bytes, cpal));

    var duplicate_start = bytes;
    writeU16Test(&duplicate_start, 14, 0);
    try std.testing.expectError(error.BadSfnt, validateCpalPaletteEntries(&duplicate_start, cpal));

    var overlapping_slice = bytes;
    writeU16Test(&overlapping_slice, 14, 1);
    try std.testing.expectError(error.BadSfnt, validateCpalPaletteEntries(&overlapping_slice, cpal));

    var out_of_order = bytes;
    writeU16Test(&out_of_order, 12, 2);
    writeU16Test(&out_of_order, 14, 0);
    try std.testing.expectError(error.BadSfnt, validateCpalPaletteEntries(&out_of_order, cpal));
}

test "CPAL v1 labels must resolve through the name table" {
    var bytes: [54]u8 = .{0} ** 54;
    writeU16Test(&bytes, 0, 1); // CPAL version 1 includes optional label arrays.
    writeU16Test(&bytes, 2, 1); // numPaletteEntries.
    writeU16Test(&bytes, 4, 1); // numPalettes.
    writeU16Test(&bytes, 6, 1); // numColorRecords.
    writeU32Test(&bytes, 8, 30); // ColorRecordsArray follows both label arrays.
    writeU16Test(&bytes, 12, 0); // First color index for palette 0.
    writeU32Test(&bytes, 14, 0); // no palette type array.
    writeU32Test(&bytes, 18, 26); // one palette label NameID.
    writeU32Test(&bytes, 22, 28); // one palette-entry label NameID.
    writeU16Test(&bytes, 26, 256);
    writeU16Test(&bytes, 28, 0xffff); // Explicitly unlabeled palette entry.
    bytes[30] = 10;
    bytes[31] = 20;
    bytes[32] = 30;
    bytes[33] = 40;

    const name_offset = 34;
    writeU16Test(&bytes, name_offset + 0, 0);
    writeU16Test(&bytes, name_offset + 2, 1);
    writeU16Test(&bytes, name_offset + 4, 18);
    writeUtf16NameRecordTest(&bytes, name_offset + 6, 256, 2, 0);
    bytes[name_offset + 19] = 'P';

    const cpal = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = name_offset };
    const name = TableRecord{ .tag = .{ 'n', 'a', 'm', 'e' }, .checksum = 0, .offset = name_offset, .length = bytes.len - name_offset };
    try validateCpalNameReferences(&bytes, cpal, name);

    var missing_palette_label = bytes;
    writeU16Test(&missing_palette_label, 26, 257);
    try std.testing.expectError(error.InvalidName, validateCpalNameReferences(&missing_palette_label, cpal, name));

    var missing_entry_label = bytes;
    writeU16Test(&missing_entry_label, 28, 257);
    try std.testing.expectError(error.InvalidName, validateCpalNameReferences(&missing_entry_label, cpal, name));

    try std.testing.expectError(error.InvalidName, validateCpalNameReferences(&bytes, cpal, null));
}

test "CPAL v1 palette types reject reserved bits" {
    var bytes: [34]u8 = .{0} ** 34;
    writeU16Test(&bytes, 0, 1); // CPAL version 1 includes optional palette-type flags.
    writeU16Test(&bytes, 2, 1); // numPaletteEntries.
    writeU16Test(&bytes, 4, 1); // numPalettes.
    writeU16Test(&bytes, 6, 1); // numColorRecords.
    writeU32Test(&bytes, 8, 30); // ColorRecordsArray follows the type array.
    writeU16Test(&bytes, 12, 0); // First color index for palette 0.
    writeU32Test(&bytes, 14, 26); // one palette type value.
    writeU32Test(&bytes, 18, 0); // no palette label array.
    writeU32Test(&bytes, 22, 0); // no palette-entry label array.
    writeU32Test(&bytes, 26, 0x0000_0004); // Reserved CPAL palette-type bit.
    bytes[30] = 10;
    bytes[31] = 20;
    bytes[32] = 30;
    bytes[33] = 40;

    const cpal = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateCpalPaletteEntries(&bytes, cpal));

    writeU32Test(&bytes, 26, 0x0000_0003); // Valid: light and dark background suitability bits.
    try std.testing.expectEqual(@as(u16, 1), try validateCpalPaletteEntries(&bytes, cpal));
}

test "CPAL v1 payload arrays cannot alias each other" {
    var bytes: [38]u8 = .{0} ** 38;
    writeU16Test(&bytes, 0, 1); // CPAL version 1.
    writeU16Test(&bytes, 2, 1); // numPaletteEntries.
    writeU16Test(&bytes, 4, 1); // numPalettes.
    writeU16Test(&bytes, 6, 1); // numColorRecords.
    writeU32Test(&bytes, 8, 34); // ColorRecordsArray follows all optional arrays.
    writeU16Test(&bytes, 12, 0);
    writeU32Test(&bytes, 14, 26); // paletteTypesArray: bytes 26..30.
    writeU32Test(&bytes, 18, 30); // paletteLabelsArray: bytes 30..32.
    writeU32Test(&bytes, 22, 32); // paletteEntryLabelsArray: bytes 32..34.
    writeU32Test(&bytes, 26, 0x0000_0003);
    writeU16Test(&bytes, 30, 0xffff);
    writeU16Test(&bytes, 32, 0xffff);
    bytes[34] = 10;
    bytes[35] = 20;
    bytes[36] = 30;
    bytes[37] = 40;

    const cpal = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectEqual(@as(u16, 1), try validateCpalPaletteEntries(&bytes, cpal));

    var label_alias = bytes;
    writeU32Test(&label_alias, 22, 30); // Entry labels reuse the palette-label payload.
    try std.testing.expectError(error.BadSfnt, validateCpalPaletteEntries(&label_alias, cpal));

    var color_alias = bytes;
    writeU32Test(&color_alias, 8, 28); // BGRA color records start inside the palette-type array.
    writeU32Test(&color_alias, 26, 0); // Keep reserved type bits clear while testing ownership.
    try std.testing.expectError(error.BadSfnt, validateCpalPaletteEntries(&color_alias, cpal));
}

test "COLR glyph references stay within maxp glyph count" {
    var colr_v0: [24]u8 = .{0} ** 24;
    writeU16Test(&colr_v0, 0, 0); // COLR version 0.
    writeU16Test(&colr_v0, 2, 1); // one BaseGlyphRecord.
    writeU32Test(&colr_v0, 4, 14);
    writeU32Test(&colr_v0, 8, 20);
    writeU16Test(&colr_v0, 12, 1); // one LayerRecord.
    writeU16Test(&colr_v0, 14, 1); // base glyph.
    writeU16Test(&colr_v0, 16, 0);
    writeU16Test(&colr_v0, 18, 1);
    writeU16Test(&colr_v0, 20, 2); // Invalid layer glyph for maxp.numGlyphs == 2.

    const colr_v0_record = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_v0.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&colr_v0, colr_v0_record, 2));

    writeU16Test(&colr_v0, 20, 1);
    try validateColrGlyphBounds(&colr_v0, colr_v0_record, 2);

    var colr_v1: [55]u8 = .{0} ** 55;
    writeU16Test(&colr_v1, 0, 1); // COLR version 1.
    writeU32Test(&colr_v1, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&colr_v1, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&colr_v1, 38, 1); // base glyph.
    writeU32Test(&colr_v1, 40, 10); // PaintGlyph at byte 44.
    colr_v1[44] = 10; // PaintGlyph.
    writeU24Test(&colr_v1, 45, 6); // child PaintSolid at byte 50.
    writeU16Test(&colr_v1, 48, 2); // Invalid PaintGlyph glyphID for maxp.numGlyphs == 2.
    colr_v1[50] = 2; // PaintSolid.
    writeU16Test(&colr_v1, 51, 0);
    writeF2Dot14Test(&colr_v1, 53, 1.0);

    const colr_v1_record = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_v1.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&colr_v1, colr_v1_record, 2));

    writeU16Test(&colr_v1, 48, 1);
    try validateColrGlyphBounds(&colr_v1, colr_v1_record, 2);
}

test "COLR v0 top-level arrays cannot alias header or each other" {
    var bytes: [28]u8 = .{0} ** 28;
    writeU16Test(&bytes, 0, 0); // COLR version 0.
    writeU16Test(&bytes, 2, 1); // one BaseGlyphRecord.
    writeU32Test(&bytes, 4, 14);
    writeU32Test(&bytes, 8, 20);
    writeU16Test(&bytes, 12, 1); // one LayerRecord.
    writeU16Test(&bytes, 14, 1);
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 1);
    writeU16Test(&bytes, 20, 1);
    writeU16Test(&bytes, 22, 0);

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateColrGlyphBounds(&bytes, colr, 2);

    var base_in_header = bytes;
    writeU32Test(&base_in_header, 4, 12); // Reinterprets numLayers as BaseGlyphRecord data.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&base_in_header, colr, 2));

    var layer_in_header = bytes;
    writeU32Test(&layer_in_header, 8, 10); // Reinterprets array offsets/count as LayerRecord data.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&layer_in_header, colr, 2));

    var arrays_overlap = bytes;
    writeU32Test(&arrays_overlap, 8, 18); // LayerRecord starts inside the BaseGlyphRecord.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&arrays_overlap, colr, 2));
}

test "COLR v0 layer slices are ordered and non-overlapping" {
    var bytes: [38]u8 = .{0} ** 38;
    writeU16Test(&bytes, 0, 0); // COLR version 0.
    writeU16Test(&bytes, 2, 2); // two BaseGlyphRecords.
    writeU32Test(&bytes, 4, 14);
    writeU32Test(&bytes, 8, 26);
    writeU16Test(&bytes, 12, 3); // three LayerRecords.
    writeU16Test(&bytes, 14, 1);
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 2); // base glyph 1 owns layers 0 and 1.
    writeU16Test(&bytes, 20, 3);
    writeU16Test(&bytes, 22, 2);
    writeU16Test(&bytes, 24, 1); // base glyph 3 owns the adjacent layer 2.
    writeU16Test(&bytes, 26, 1);
    writeU16Test(&bytes, 30, 2);
    writeU16Test(&bytes, 34, 3);

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateColrGlyphBounds(&bytes, colr, 4);

    var overlapping_slice = bytes;
    writeU16Test(&overlapping_slice, 22, 1); // Starts inside the first base glyph's layer slice.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&overlapping_slice, colr, 4));

    var decreasing_slice = bytes;
    writeU16Test(&decreasing_slice, 16, 2);
    writeU16Test(&decreasing_slice, 18, 1);
    writeU16Test(&decreasing_slice, 22, 0); // Disjoint but not in BaseGlyphRecord order.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&decreasing_slice, colr, 4));
}

test "COLR base glyph records are strictly ordered" {
    var colr_v0: [34]u8 = .{0} ** 34;
    writeU16Test(&colr_v0, 0, 0); // COLR version 0.
    writeU16Test(&colr_v0, 2, 2); // two BaseGlyphRecords.
    writeU32Test(&colr_v0, 4, 14);
    writeU32Test(&colr_v0, 8, 26);
    writeU16Test(&colr_v0, 12, 2); // two LayerRecords.
    writeU16Test(&colr_v0, 14, 2); // First base glyph.
    writeU16Test(&colr_v0, 16, 0);
    writeU16Test(&colr_v0, 18, 1);
    writeU16Test(&colr_v0, 20, 1); // Invalid: BaseGlyphRecords must increase by glyph ID.
    writeU16Test(&colr_v0, 22, 1);
    writeU16Test(&colr_v0, 24, 1);
    writeU16Test(&colr_v0, 26, 1);
    writeU16Test(&colr_v0, 30, 1);

    const colr_v0_record = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_v0.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&colr_v0, colr_v0_record, 4));

    writeU16Test(&colr_v0, 20, 3);
    try validateColrGlyphBounds(&colr_v0, colr_v0_record, 4);

    var colr_v1: [60]u8 = .{0} ** 60;
    writeU16Test(&colr_v1, 0, 1); // COLR version 1.
    writeU32Test(&colr_v1, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&colr_v1, 34, 2); // two BaseGlyphPaintRecords.
    writeU16Test(&colr_v1, 38, 2); // First base glyph.
    writeU32Test(&colr_v1, 40, 16); // PaintSolid at byte 50.
    writeU16Test(&colr_v1, 44, 1); // Invalid: duplicate/decreasing key order.
    writeU32Test(&colr_v1, 46, 21); // PaintSolid at byte 55.
    colr_v1[50] = 2;
    writeU16Test(&colr_v1, 51, 0);
    writeF2Dot14Test(&colr_v1, 53, 1.0);
    colr_v1[55] = 2;
    writeU16Test(&colr_v1, 56, 0);
    writeF2Dot14Test(&colr_v1, 58, 1.0);

    const colr_v1_record = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_v1.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&colr_v1, colr_v1_record, 4));

    writeU16Test(&colr_v1, 44, 3);
    try validateColrGlyphBounds(&colr_v1, colr_v1_record, 4);
}

test "COLR palette indices are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildColorTtf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeU16Test(bytes, colr_offset + 22, 2); // CPAL declares palette entries 0 and 1 only.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeU16Test(bytes, colr_offset + 45, 2); // PaintSolid palette index.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildColorV1GlyphTtf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeU16Test(bytes, colr_offset + 51, 2); // Nested PaintGlyph child PaintSolid palette index.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildColorV1LayersTtf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeU16Test(bytes, colr_offset + 80, 2); // PaintColrLayers-reachable layer paint.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "COLR v1 reachable paint formats are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        bytes[colr_offset + 44] = 0; // Reserved, not a valid COLR v1 Paint format.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildColorV1LayersTtf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        bytes[colr_offset + 73] = 33; // Reserved format reachable through PaintColrLayers.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "COLR v1 top-level offsets cannot alias the header" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeU32Test(bytes, colr_offset + 14, 30); // BaseGlyphListOffset points into ItemVariationStoreOffset.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildColorV1LayersTtf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeU32Test(bytes, colr_offset + 18, 26); // LayerListOffset points into VarIndexMapOffset.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "COLR v1 optional top-level tables cannot alias one another" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildColorV1Ttf(allocator);
    defer allocator.free(bytes);
    const colr_offset = try sfntTableOffset(bytes, "COLR");
    writeU32Test(bytes, colr_offset + 18, 34); // LayerListOffset aliases BaseGlyphListOffset.
    writeU32Test(bytes, colr_offset + 34, 0); // Both zero-count headers would otherwise parse.

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "COLR v1 variable paints reference valid variation data" {
    var bytes: [128]u8 = .{0} ** 128;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };

    const colr_offset = fvar.length;
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = colr_offset, .length = 92 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarSolid at BaseGlyphList + 10.
    bytes[colr_offset + 44] = 3;
    writeU16Test(&bytes, colr_offset + 45, 0);
    writeF2Dot14Test(&bytes, colr_offset + 47, 1.0);
    writeU32Test(&bytes, colr_offset + 49, 0); // varIndexBase.

    var missing_store = bytes;
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&missing_store, colr, fvar, 2));

    writeU32Test(&bytes, colr_offset + 30, 53); // ItemVariationStoreOffset.
    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 53);
    try validateColrVariationData(&bytes, colr, fvar, 2);

    var bad_implicit_var_index = bytes;
    writeU32Test(&bad_implicit_var_index, colr_offset + 49, 1); // outer 0, inner 1; item 0 has one row.
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bad_implicit_var_index, colr, fvar, 2));

    var bad_map = bytes;
    writeU32Test(&bad_map, colr_offset + 26, 53); // VarIndexMapOffset.
    writeU32Test(&bad_map, colr_offset + 30, 58); // ItemVariationStoreOffset follows the map.
    bad_map[colr_offset + 53] = 0; // DeltaSetIndexMap format 0.
    bad_map[colr_offset + 54] = 0; // one-byte entries, one inner-index bit.
    writeU16Test(&bad_map, colr_offset + 55, 1); // one mapping entry.
    bad_map[colr_offset + 57] = 1; // outer 0, inner 1; outside the single item row.
    writeItemVariationStoreWithOneItem(&bad_map, colr_offset + 58);
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bad_map, colr, fvar, 2));
}

test "COLR v1 variable gradients validate paint and stop variation indexes" {
    var bytes: [180]u8 = .{0} ** 180;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };

    const colr_offset = fvar.length;
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = colr_offset, .length = 144 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 30, 90); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarLinearGradient at BaseGlyphList + 10.

    bytes[colr_offset + 44] = 5; // PaintVarLinearGradient.
    writeU24Test(&bytes, colr_offset + 45, 20); // VarColorLine starts immediately after the paint.
    writeI16Test(&bytes, colr_offset + 48, 0); // x0.
    writeI16Test(&bytes, colr_offset + 50, 0); // y0.
    writeI16Test(&bytes, colr_offset + 52, 100); // x1.
    writeI16Test(&bytes, colr_offset + 54, 0); // y1.
    writeI16Test(&bytes, colr_offset + 56, 0); // x2.
    writeI16Test(&bytes, colr_offset + 58, 100); // y2.
    writeU32Test(&bytes, colr_offset + 60, 0); // geometry varIndexBase covers six coordinate deltas.

    const color_line = colr_offset + 64;
    bytes[color_line] = 0; // ExtendMode.pad.
    writeU16Test(&bytes, color_line + 1, 2);
    writeF2Dot14Test(&bytes, color_line + 3, 0.0);
    writeU16Test(&bytes, color_line + 5, 0);
    writeF2Dot14Test(&bytes, color_line + 7, 1.0);
    writeU32Test(&bytes, color_line + 9, 0); // stop/alpha varIndexBase covers two deltas.
    writeF2Dot14Test(&bytes, color_line + 13, 1.0);
    writeU16Test(&bytes, color_line + 15, 0);
    writeF2Dot14Test(&bytes, color_line + 17, 1.0);
    writeU32Test(&bytes, color_line + 19, 0);

    writeItemVariationStoreWithItems(&bytes, colr_offset + 90, 6);
    try validateColrVariationData(&bytes, colr, fvar, 2);

    var missing_store = bytes;
    writeU32Test(&missing_store, colr_offset + 30, 0);
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&missing_store, colr, fvar, 2));

    var bad_geometry_index = bytes;
    writeU32Test(&bad_geometry_index, colr_offset + 60, 1); // Sequence 1..6 exceeds the six-row item data.
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bad_geometry_index, colr, fvar, 2));

    var bad_stop_index = bytes;
    writeU32Test(&bad_stop_index, color_line + 19, 5); // VarColorStop needs rows 5 and 6.
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bad_stop_index, colr, fvar, 2));
}

test "COLR v1 variable transform paints validate variation indexes" {
    var bytes: [180]u8 = .{0} ** 180;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };

    const colr_offset = fvar.length;
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = colr_offset, .length = 134 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 30, 90); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarTransform at BaseGlyphList + 10.

    bytes[colr_offset + 44] = 13; // PaintVarTransform.
    writeU24Test(&bytes, colr_offset + 45, 35); // Child PaintSolid after the matrix.
    writeU24Test(&bytes, colr_offset + 48, 11); // VarAffine2x3 starts after PaintVarTransform.
    writeU32Test(&bytes, colr_offset + 51, 0); // varIndexBase covers the six matrix scalars.
    writeF16Dot16Test(&bytes, colr_offset + 55, 1.0); // xx.
    writeF16Dot16Test(&bytes, colr_offset + 59, 0.0); // yx.
    writeF16Dot16Test(&bytes, colr_offset + 63, 0.0); // xy.
    writeF16Dot16Test(&bytes, colr_offset + 67, 1.0); // yy.
    writeF16Dot16Test(&bytes, colr_offset + 71, 0.0); // dx.
    writeF16Dot16Test(&bytes, colr_offset + 75, 0.0); // dy.
    bytes[colr_offset + 79] = 2; // PaintSolid child.
    writeU16Test(&bytes, colr_offset + 80, 0);
    writeF2Dot14Test(&bytes, colr_offset + 82, 1.0);

    writeItemVariationStoreWithItems(&bytes, colr_offset + 90, 6);
    try validateColrVariationData(&bytes, colr, fvar, 2);

    var missing_store = bytes;
    writeU32Test(&missing_store, colr_offset + 30, 0);
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&missing_store, colr, fvar, 2));

    var bad_matrix_index = bytes;
    writeU32Test(&bad_matrix_index, colr_offset + 51, 1); // Matrix deltas need rows 1 through 6.
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bad_matrix_index, colr, fvar, 2));
}

test "COLR v1 variation map and store subtables cannot overlap" {
    var bytes: [128]u8 = .{0} ** 128;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };

    const colr_offset = fvar.length;
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = colr_offset, .length = 92 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 26, 84); // VarIndexMapOffset overlaps the store's ItemVariationData.
    writeU32Test(&bytes, colr_offset + 30, 53); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarSolid at BaseGlyphList + 10.
    bytes[colr_offset + 44] = 3;
    writeU16Test(&bytes, colr_offset + 45, 0);
    writeF2Dot14Test(&bytes, colr_offset + 47, 1.0);
    writeU32Test(&bytes, colr_offset + 49, 0); // varIndexBase resolves through the map.

    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 53);

    // These bytes are still part of the ItemVariationStore payload, but they
    // can also be decoded as a valid one-entry DeltaSetIndexMap unless the
    // top-level COLR variation subtables are checked for aliasing.
    bytes[colr_offset + 86] = 0; // Delta row low byte; doubles as mapCount high byte.
    bytes[colr_offset + 87] = 1; // First byte after the store; doubles as mapCount low byte.
    bytes[colr_offset + 88] = 0; // Map entry: outer 0, inner 0.

    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bytes, colr, fvar, 2));
}

test "COLR v1 variation subtables cannot alias optional structural tables" {
    var bytes: [160]u8 = .{0} ** 160;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };

    const colr_offset = fvar.length;
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = colr_offset, .length = 124 };
    writeU16Test(&bytes, colr_offset + 0, 1); // COLR version 1.
    writeU32Test(&bytes, colr_offset + 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, colr_offset + 18, 53); // LayerListOffset aliases VarIndexMapOffset below.
    writeU32Test(&bytes, colr_offset + 26, 53); // VarIndexMapOffset.
    writeU32Test(&bytes, colr_offset + 30, 70); // ItemVariationStoreOffset.

    writeU32Test(&bytes, colr_offset + 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, colr_offset + 38, 1);
    writeU32Test(&bytes, colr_offset + 40, 10); // PaintVarSolid at BaseGlyphList + 10.
    bytes[colr_offset + 44] = 3;
    writeU16Test(&bytes, colr_offset + 45, 0);
    writeF2Dot14Test(&bytes, colr_offset + 47, 1.0);
    writeU32Test(&bytes, colr_offset + 49, 0); // varIndexBase resolves through the aliased map.

    // These bytes describe a one-entry LayerList (paint offset 12) but also
    // decode as a valid format-0 DeltaSetIndexMap with one one-byte entry.
    // The table must be rejected for aliasing before both interpretations can
    // reach downstream paint and variation validators.
    bytes[colr_offset + 53] = 0; // DeltaSetIndexMap format 0; LayerList count high byte.
    bytes[colr_offset + 54] = 0; // one-byte entries, one inner-index bit.
    writeU16Test(&bytes, colr_offset + 55, 1); // mapCount; LayerList count low bytes.
    writeU32Test(&bytes, colr_offset + 57, 12); // first layer paint offset; map entry byte is zero.
    bytes[colr_offset + 65] = 2; // PaintSolid reachable through the LayerList interpretation.
    writeU16Test(&bytes, colr_offset + 66, 0);
    writeF2Dot14Test(&bytes, colr_offset + 68, 1.0);
    writeItemVariationStoreWithOneItem(&bytes, colr_offset + 70);

    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&bytes, colr, fvar, 2));

    writeU32Test(&bytes, colr_offset + 26, 0); // Removing the map makes the remaining structure valid.
    try validateColrVariationData(&bytes, colr, fvar, 2);

    var store_alias = bytes;
    writeU32Test(&store_alias, colr_offset + 18, 70); // LayerListOffset aliases the ItemVariationStore.
    writeU32Test(&store_alias, colr_offset + 26, 0);
    try std.testing.expectError(error.BadSfnt, validateColrVariationData(&store_alias, colr, fvar, 2));
}

test "COLR palette indices must be declared by CPAL" {
    const allocator = std.testing.allocator;

    var colr_v0_with_cpal: [42]u8 = .{0} ** 42;
    writeU16Test(&colr_v0_with_cpal, 0, 0); // COLR version 0.
    writeU16Test(&colr_v0_with_cpal, 2, 1); // one BaseGlyphRecord.
    writeU32Test(&colr_v0_with_cpal, 4, 14);
    writeU32Test(&colr_v0_with_cpal, 8, 20);
    writeU16Test(&colr_v0_with_cpal, 12, 1);
    writeU16Test(&colr_v0_with_cpal, 14, 1); // base glyph.
    writeU16Test(&colr_v0_with_cpal, 16, 0);
    writeU16Test(&colr_v0_with_cpal, 18, 1);
    writeU16Test(&colr_v0_with_cpal, 20, 1); // layer glyph.
    writeU16Test(&colr_v0_with_cpal, 22, 1); // Invalid: CPAL only declares color index 0.
    writeSingleEntryCpalTest(&colr_v0_with_cpal, 24);

    const colr_v0_font = colrCpalOnlyFont(&colr_v0_with_cpal, 24);
    try std.testing.expectError(error.BadSfnt, colr_v0_font.colorLayers(allocator, 1));

    var colr_v1_with_cpal: [67]u8 = .{0} ** 67;
    writeU16Test(&colr_v1_with_cpal, 0, 1); // COLR version 1.
    writeU32Test(&colr_v1_with_cpal, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&colr_v1_with_cpal, 34, 1);
    writeU16Test(&colr_v1_with_cpal, 38, 1);
    writeU32Test(&colr_v1_with_cpal, 40, 10); // PaintSolid at byte 44.
    colr_v1_with_cpal[44] = 2;
    writeU16Test(&colr_v1_with_cpal, 45, 1); // Invalid: CPAL only declares color index 0.
    writeF2Dot14Test(&colr_v1_with_cpal, 47, 1.0);
    writeSingleEntryCpalTest(&colr_v1_with_cpal, 49);

    const colr_v1_font = colrCpalOnlyFont(&colr_v1_with_cpal, 49);
    try std.testing.expectError(error.BadSfnt, colr_v1_font.colorPaint(1));
}

test "COLR v1 gradient ColorLine stops are validated" {
    var bytes: [99]u8 = .{0} ** 99;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, 38, 1);
    writeU32Test(&bytes, 40, 10); // PaintLinearGradient at byte 44.

    bytes[44] = 4; // PaintLinearGradient.
    writeU24Test(&bytes, 45, 16); // ColorLine starts immediately after the paint header.
    writeI16Test(&bytes, 48, 0);
    writeI16Test(&bytes, 50, 0);
    writeI16Test(&bytes, 52, 100);
    writeI16Test(&bytes, 54, 0);
    writeI16Test(&bytes, 56, 0);
    writeI16Test(&bytes, 58, 100);

    const color_line = 60;
    bytes[color_line] = 0; // ExtendMode.pad.
    writeU16Test(&bytes, color_line + 1, 2);
    writeF2Dot14Test(&bytes, color_line + 3, 0.0);
    writeU16Test(&bytes, color_line + 5, 0);
    writeF2Dot14Test(&bytes, color_line + 7, 1.0);
    writeF2Dot14Test(&bytes, color_line + 9, 1.0);
    writeU16Test(&bytes, color_line + 11, 1);
    writeF2Dot14Test(&bytes, color_line + 13, 1.0);

    const colr_len = color_line + 15;
    writeTwoEntryCpalTest(&bytes, colr_len);
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_len };
    const cpal = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = colr_len, .length = bytes.len - colr_len };
    try validateColrPaletteBounds(&bytes, colr, cpal);

    var bad_extend = bytes;
    bad_extend[color_line] = 3; // ExtendMode only defines pad, repeat, and reflect.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&bad_extend, colr, 2));

    var too_few_stops = bytes;
    writeU16Test(&too_few_stops, color_line + 1, 1);
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&too_few_stops, colr, 2));

    var descending_stops = bytes;
    writeF2Dot14Test(&descending_stops, color_line + 9, -0.25);
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&descending_stops, colr, 2));

    var bad_stop_alpha = bytes;
    writeI16Test(&bad_stop_alpha, color_line + 13, 0x4001);
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&bad_stop_alpha, colr, 2));

    var bad_stop_palette = bytes;
    writeU16Test(&bad_stop_palette, color_line + 11, 2); // CPAL below declares palette entries 0 and 1 only.
    try std.testing.expectError(error.BadSfnt, validateColrPaletteBounds(&bad_stop_palette, colr, cpal));
}

test "COLR v1 PaintComposite rejects reserved composite modes" {
    var bytes: [62]u8 = .{0} ** 62;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, 38, 1);
    writeU32Test(&bytes, 40, 10); // PaintComposite at byte 44.

    bytes[44] = 32; // PaintComposite.
    writeU24Test(&bytes, 45, 8); // Source paint starts immediately after the composite record.
    bytes[48] = 28; // Invalid: CompositeMode currently defines values 0 through 27.
    writeU24Test(&bytes, 49, 13); // Backdrop paint starts after the source PaintSolid.
    bytes[52] = 2;
    writeU16Test(&bytes, 53, 0);
    writeF2Dot14Test(&bytes, 55, 1.0);
    bytes[57] = 2;
    writeU16Test(&bytes, 58, 0);
    writeF2Dot14Test(&bytes, 60, 1.0);

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&bytes, colr, 2));

    bytes[48] = 27; // Valid: plus-lighter is the highest assigned CompositeMode.
    try validateColrGlyphBounds(&bytes, colr, 2);
}

test "COLR v1 PaintComposite child headers cannot overlap" {
    var bytes: [62]u8 = .{0} ** 62;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, 38, 1);
    writeU32Test(&bytes, 40, 10); // PaintComposite at byte 44.

    bytes[44] = 32; // PaintComposite.
    writeU24Test(&bytes, 45, 8); // Source PaintSolid at byte 52.
    bytes[48] = 0; // CompositeMode.clear.
    writeU24Test(&bytes, 49, 10); // Backdrop PaintSolid starts inside the source header.
    bytes[52] = 2; // Source PaintSolid.
    bytes[54] = 2; // Also looks like a backdrop PaintSolid format byte.
    writeF2Dot14Test(&bytes, 55, 1.0); // Valid source alpha.
    writeF2Dot14Test(&bytes, 57, 1.0); // Valid backdrop alpha.

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&bytes, colr, 2));
}

test "COLR v1 PaintTransform requires a complete Affine2x3 matrix" {
    var bytes: [79]u8 = .{0} ** 79;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, 38, 1);
    writeU32Test(&bytes, 40, 10); // PaintTransform at byte 44.

    bytes[44] = 12; // PaintTransform.
    writeU24Test(&bytes, 45, 31); // child PaintSolid follows the Affine2x3 matrix.
    writeU24Test(&bytes, 48, 7); // matrix starts immediately after PaintTransform.
    writeF16Dot16Test(&bytes, 51, 1.0); // xx.
    writeF16Dot16Test(&bytes, 55, 0.0); // yx.
    writeF16Dot16Test(&bytes, 59, 1.0); // xy.
    writeF16Dot16Test(&bytes, 63, 0.0); // yy.
    writeF16Dot16Test(&bytes, 67, 0.0); // dx.
    // dy is intentionally truncated to three bytes. The child paint offset is
    // outside this declared COLR length, so the matrix-specific check must
    // reject the record before graph traversal can reach the child.

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&bytes, colr, 2));

    var valid = bytes ++ [_]u8{0};
    writeF16Dot16Test(&valid, 71, 0.0); // dy completes the Affine2x3.
    valid[75] = 2; // PaintSolid child.
    writeU16Test(&valid, 76, 0);
    writeF2Dot14Test(&valid, 78, 1.0);

    const valid_colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = valid.len };
    try validateColrGlyphBounds(&valid, valid_colr, 2);
}

test "COLR v1 PaintTransform child header cannot overlap matrix payload" {
    var bytes: [75]u8 = .{0} ** 75;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, 38, 1);
    writeU32Test(&bytes, 40, 10); // PaintTransform at byte 44.

    bytes[44] = 12; // PaintTransform.
    writeU24Test(&bytes, 45, 20); // Child PaintSolid starts at byte 64, inside the matrix.
    writeU24Test(&bytes, 48, 7); // Affine2x3 matrix owns bytes 51..75.
    bytes[64] = 2; // Child header is individually plausible.
    writeU16Test(&bytes, 65, 0);
    writeF2Dot14Test(&bytes, 67, 1.0);

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&bytes, colr, 2));
}

test "COLR v1 PaintSolid alpha is validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeI16Test(bytes, colr_offset + 47, -1); // Negative opacity is outside PaintSolid's semantic range.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildColorV1Ttf(allocator);
        defer allocator.free(bytes);
        const colr_offset = try sfntTableOffset(bytes, "COLR");
        writeI16Test(bytes, colr_offset + 47, 0x4001); // Alpha may not exceed 1.0.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "COLR v1 paint offsets cannot overlap parent metadata" {
    var base_list_overlap: [44]u8 = .{0} ** 44;
    writeU16Test(&base_list_overlap, 0, 1); // COLR version 1.
    writeU32Test(&base_list_overlap, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&base_list_overlap, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&base_list_overlap, 38, 2); // glyph id; its low byte looks like PaintSolid format.
    writeU32Test(&base_list_overlap, 40, 5); // Points into the BaseGlyphPaintRecord, not after it.

    const base_font = colrOnlyFont(&base_list_overlap);
    try std.testing.expectError(error.BadSfnt, base_font.colorPaint(2));

    var layer_list_overlap: [46]u8 = .{0} ** 46;
    writeU16Test(&layer_list_overlap, 0, 1); // COLR version 1.
    writeU32Test(&layer_list_overlap, 18, 34); // LayerListOffset.
    writeU32Test(&layer_list_overlap, 34, 2); // two PaintOffsets; low byte looks like PaintSolid.
    writeU32Test(&layer_list_overlap, 38, 3); // Points into numLayers, not after both offsets.

    const layer_font = colrOnlyFont(&layer_list_overlap);
    try std.testing.expectError(error.BadSfnt, layer_font.colorPaintLayer(0));

    var paint_glyph_overlap: [54]u8 = .{0} ** 54;
    writeU16Test(&paint_glyph_overlap, 0, 1); // COLR version 1.
    writeU32Test(&paint_glyph_overlap, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&paint_glyph_overlap, 34, 1);
    writeU16Test(&paint_glyph_overlap, 38, 1);
    writeU32Test(&paint_glyph_overlap, 40, 10); // Valid offset to the PaintGlyph below.
    paint_glyph_overlap[44] = 10; // PaintGlyph.
    paint_glyph_overlap[47] = 5; // Child paint offset overlaps the PaintGlyph's glyphID field.
    writeU16Test(&paint_glyph_overlap, 48, 2); // low byte at +5 looks like PaintSolid format.

    const paint_glyph_font = colrOnlyFont(&paint_glyph_overlap);
    try std.testing.expectError(error.BadSfnt, paint_glyph_font.colorPaint(1));
}

test "COLR v1 LayerList paint headers are ordered and non-overlapping" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 18, 34); // LayerListOffset.

    writeU32Test(&bytes, 34, 2); // two layer paint offsets.
    writeU32Test(&bytes, 38, 12); // PaintSolid at LayerList + 12.
    writeU32Test(&bytes, 42, 17); // Adjacent PaintSolid after the first header.
    bytes[46] = 2;
    writeU16Test(&bytes, 47, 0);
    writeF2Dot14Test(&bytes, 49, 1.0);
    bytes[51] = 2;
    writeU16Test(&bytes, 52, 1);
    writeF2Dot14Test(&bytes, 54, 1.0);

    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateColrGlyphBounds(&bytes, colr, 2);

    var duplicate_header = bytes;
    writeU32Test(&duplicate_header, 42, 12); // Reuses the first layer's PaintSolid header.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&duplicate_header, colr, 2));

    var partial_overlap = bytes;
    writeU32Test(&partial_overlap, 42, 14); // Starts inside the first PaintSolid header.
    partial_overlap[48] = 2; // Keep the aliased byte looking like a valid paint format.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&partial_overlap, colr, 2));

    var decreasing_order = bytes;
    writeU32Test(&decreasing_order, 38, 17);
    writeU32Test(&decreasing_order, 42, 12); // Disjoint headers, but not in LayerList order.
    try std.testing.expectError(error.BadSfnt, validateColrGlyphBounds(&decreasing_order, colr, 2));
}

test "COLR v1 paint graph rejects cyclic layer references" {
    var bytes: [66]u8 = .{0} ** 66;
    writeU16Test(&bytes, 0, 1); // COLR version 1.
    writeU32Test(&bytes, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&bytes, 18, 44); // LayerListOffset.

    writeU32Test(&bytes, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&bytes, 38, 1); // glyph id.
    writeU32Test(&bytes, 40, 26); // BaseGlyphList-relative paint offset -> byte 60.

    writeU32Test(&bytes, 44, 1); // one layer paint offset.
    writeU32Test(&bytes, 48, 16); // LayerList-relative paint offset -> byte 60.

    bytes[60] = 1; // PaintColrLayers.
    bytes[61] = 1; // Reuses layer 0, which points back to this paint.
    writeU32Test(&bytes, 62, 0);

    const font = colrOnlyFont(&bytes);
    try std.testing.expectError(error.BadSfnt, font.colorPaint(1));
    try std.testing.expectError(error.BadSfnt, font.colorPaintLayer(0));
}

test "TTC v2 DSIG descriptor validates range and null consistency" {
    var valid_empty: [28]u8 = .{0} ** 28;
    writeTagTest(&valid_empty, 0, "ttcf");
    writeU32Test(&valid_empty, 4, 0x00020000);
    writeU32Test(&valid_empty, 8, 1);
    writeU32Test(&valid_empty, 12, 28);
    try std.testing.expectEqual(@as(usize, 1), try Font.faceCount(&valid_empty));

    var partial_descriptor = valid_empty;
    writeTagTest(&partial_descriptor, 16, "DSIG");
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&partial_descriptor));

    var wrong_tag = valid_empty;
    writeTagTest(&wrong_tag, 16, "BAD!");
    writeU32Test(&wrong_tag, 20, 4);
    writeU32Test(&wrong_tag, 24, 28);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&wrong_tag));

    var header_overlap = valid_empty;
    writeTagTest(&header_overlap, 16, "DSIG");
    writeU32Test(&header_overlap, 20, 4);
    writeU32Test(&header_overlap, 24, 24);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&header_overlap));

    var out_of_bounds: [32]u8 = .{0} ** 32;
    writeTagTest(&out_of_bounds, 0, "ttcf");
    writeU32Test(&out_of_bounds, 4, 0x00020000);
    writeU32Test(&out_of_bounds, 8, 1);
    writeU32Test(&out_of_bounds, 12, 28);
    writeTagTest(&out_of_bounds, 16, "DSIG");
    writeU32Test(&out_of_bounds, 20, 8);
    writeU32Test(&out_of_bounds, 24, 28);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&out_of_bounds));

    var valid_dsig: [32]u8 = .{0} ** 32;
    writeTagTest(&valid_dsig, 0, "ttcf");
    writeU32Test(&valid_dsig, 4, 0x00020000);
    writeU32Test(&valid_dsig, 8, 1);
    writeU32Test(&valid_dsig, 12, 28);
    writeTagTest(&valid_dsig, 16, "DSIG");
    writeU32Test(&valid_dsig, 20, 4);
    writeU32Test(&valid_dsig, 24, 28);
    try std.testing.expectEqual(@as(usize, 1), try Font.faceCount(&valid_dsig));
}

test "fvar axes and instance arrays stay inside declared table regions" {
    const allocator = std.testing.allocator;

    var overlapping_axes: [36]u8 = .{0} ** 36;
    writeU32Test(&overlapping_axes, 0, 0x00010000);
    writeU16Test(&overlapping_axes, 4, 12); // Points into the fvar header.
    writeU16Test(&overlapping_axes, 6, 2);
    writeU16Test(&overlapping_axes, 8, 1);
    writeU16Test(&overlapping_axes, 10, 20);
    writeTagTest(&overlapping_axes, 12, "wght"); // Would look like an axis tag to the old parser.

    const overlapping_font = fvarOnlyFont(&overlapping_axes);
    try std.testing.expectError(error.BadSfnt, overlapping_font.variationAxes(allocator));

    var truncated_instances: [36]u8 = .{0} ** 36;
    writeU32Test(&truncated_instances, 0, 0x00010000);
    writeU16Test(&truncated_instances, 4, 16);
    writeU16Test(&truncated_instances, 6, 2);
    writeU16Test(&truncated_instances, 8, 1);
    writeU16Test(&truncated_instances, 10, 20);
    writeU16Test(&truncated_instances, 12, 1); // One declared instance follows the axes.
    writeU16Test(&truncated_instances, 14, 8);
    writeFvarAxisTest(&truncated_instances, 16, "wght", 100.0, 400.0, 900.0, 256);

    const truncated_font = fvarOnlyFont(&truncated_instances);
    try std.testing.expectError(error.BadSfnt, truncated_font.variationAxes(allocator));

    var valid_with_instance: [44]u8 = .{0} ** 44;
    writeU32Test(&valid_with_instance, 0, 0x00010000);
    writeU16Test(&valid_with_instance, 4, 16);
    writeU16Test(&valid_with_instance, 6, 2);
    writeU16Test(&valid_with_instance, 8, 1);
    writeU16Test(&valid_with_instance, 10, 20);
    writeU16Test(&valid_with_instance, 12, 1);
    writeU16Test(&valid_with_instance, 14, 8);
    writeFvarAxisTest(&valid_with_instance, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeU16Test(&valid_with_instance, 36, 300); // subfamilyNameID
    writeU16Test(&valid_with_instance, 38, 0); // flags
    writeU32Test(&valid_with_instance, 40, 0x00010000); // one coordinate

    const valid_font = fvarOnlyFont(&valid_with_instance);
    const axes = try valid_font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 1), axes.len);
    try std.testing.expectEqualStrings("wght", &axes[0].tag);

    var bad_count_size_pairs = valid_with_instance;
    writeU16Test(&bad_count_size_pairs, 6, 3);
    const bad_count_size_pairs_font = fvarOnlyFont(&bad_count_size_pairs);
    try std.testing.expectError(error.BadSfnt, bad_count_size_pairs_font.variationAxes(allocator));
}

test "fvar axis records require ordered ranges and unique tags" {
    const allocator = std.testing.allocator;

    var invalid_range: [36]u8 = .{0} ** 36;
    writeU32Test(&invalid_range, 0, 0x00010000);
    writeU16Test(&invalid_range, 4, 16);
    writeU16Test(&invalid_range, 6, 2);
    writeU16Test(&invalid_range, 8, 1);
    writeU16Test(&invalid_range, 10, 20);
    writeFvarAxisTest(&invalid_range, 16, "wght", 900.0, 400.0, 100.0, 256);

    const invalid_range_font = fvarOnlyFont(&invalid_range);
    try std.testing.expectError(error.BadSfnt, invalid_range_font.variationAxes(allocator));

    var duplicate_tags: [56]u8 = .{0} ** 56;
    writeU32Test(&duplicate_tags, 0, 0x00010000);
    writeU16Test(&duplicate_tags, 4, 16);
    writeU16Test(&duplicate_tags, 6, 2);
    writeU16Test(&duplicate_tags, 8, 2);
    writeU16Test(&duplicate_tags, 10, 20);
    writeFvarAxisTest(&duplicate_tags, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeFvarAxisTest(&duplicate_tags, 36, "wght", 50.0, 100.0, 200.0, 257);

    const duplicate_font = fvarOnlyFont(&duplicate_tags);
    try std.testing.expectError(error.BadSfnt, duplicate_font.variationAxes(allocator));
}

test "fvar axis metadata is validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const fvar_offset: usize = @intCast(try sfntTableOffset(bytes, "fvar"));
        writeU16Test(bytes, fvar_offset + 6, 3); // fvar has exactly two count/size pairs.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const fvar_offset: usize = @intCast(try sfntTableOffset(bytes, "fvar"));
        writeTagTest(bytes, fvar_offset + 36, "wght"); // Duplicate the first axis tag.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const fvar_offset: usize = @intCast(try sfntTableOffset(bytes, "fvar"));
        writeU16Test(bytes, fvar_offset + 32, 0x0002); // Only HIDDEN_AXIS is defined.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const fvar_offset: usize = @intCast(try sfntTableOffset(bytes, "fvar"));
        writeF16Dot16Test(bytes, fvar_offset + 20, 950.0); // minValue > defaultValue.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "fvar instance coordinates stay inside axis ranges" {
    var bytes: [44]u8 = .{0} ** 44;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 8);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeU16Test(&bytes, 36, 258); // subfamilyNameID.
    writeU16Test(&bytes, 38, 0); // flags.
    writeF16Dot16Test(&bytes, 40, 700.0);

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateFvarTable(&bytes, fvar);

    var reserved_instance_flags = bytes;
    writeU16Test(&reserved_instance_flags, 38, 1);
    try std.testing.expectError(error.BadSfnt, validateFvarTable(&reserved_instance_flags, fvar));

    var coordinate_past_axis_range = bytes;
    writeF16Dot16Test(&coordinate_past_axis_range, 40, 950.0);
    try std.testing.expectError(error.BadSfnt, validateFvarTable(&coordinate_past_axis_range, fvar));
}

test "fvar and STAT user-facing name IDs resolve through name table" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const fvar_offset: usize = @intCast(try sfntTableOffset(bytes, "fvar"));
        writeU16Test(bytes, fvar_offset + 34, 400); // No name table record names the weight axis with this ID.
        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);
        const stat_offset: usize = @intCast(try sfntTableOffset(bytes, "STAT"));
        writeU16Test(bytes, stat_offset + 44, 400); // AxisValue nameID.
        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableTag(bytes, "name", "namx");
        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }
}

test "fvar instance name IDs resolve through name table" {
    var bytes: [46]u8 = .{0} ** 46;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 10);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeU16Test(&bytes, 36, 300); // instance subfamilyNameID
    writeU16Test(&bytes, 38, 0);
    writeF16Dot16Test(&bytes, 40, 400.0);
    writeU16Test(&bytes, 44, 301); // optional postScriptNameID

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = nameIndexForTest(&.{ 256, 300, 301 });
    try validateFvarNameReferences(&bytes, fvar, &names);

    var missing_subfamily = bytes;
    writeU16Test(&missing_subfamily, 36, 400);
    try std.testing.expectError(error.InvalidName, validateFvarNameReferences(&missing_subfamily, fvar, &names));

    var missing_postscript = bytes;
    writeU16Test(&missing_postscript, 44, 400);
    try std.testing.expectError(error.InvalidName, validateFvarNameReferences(&missing_postscript, fvar, &names));

    var omitted_postscript = bytes;
    writeU16Test(&omitted_postscript, 44, 0xffff);
    try validateFvarNameReferences(&omitted_postscript, fvar, &names);
}

test "avar validates every declared segment map before returning a coordinate" {
    var bytes: [20]u8 = .{0} ** 20;
    writeU16Test(&bytes, 0, 1); // major
    writeU16Test(&bytes, 2, 0); // minor
    writeU16Test(&bytes, 4, 0); // reserved
    writeU16Test(&bytes, 6, 2); // two axis maps follow the header
    writeU16Test(&bytes, 8, 2);
    writeF2Dot14Test(&bytes, 10, -1.0);
    writeF2Dot14Test(&bytes, 12, -1.0);
    writeF2Dot14Test(&bytes, 14, 1.0);
    writeF2Dot14Test(&bytes, 16, 1.0);
    writeU16Test(&bytes, 18, 1); // Declares a second map, but no pair bytes remain.

    const font = avarOnlyFont(&bytes);
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, 0.0));
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(99, 0.5));
}

test "avar axis count must match fvar axis count when both tables exist" {
    var bytes: [46]u8 = .{0} ** 46;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeU16Test(&bytes, 36, 1); // avar major.
    writeU16Test(&bytes, 38, 0); // avar minor.
    writeU16Test(&bytes, 42, 2); // Mismatches the single fvar axis.
    writeU16Test(&bytes, 44, 3); // Would be the first segment-map count if counts matched.

    const font = fvarAvarOnlyFont(&bytes, 36);
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, 0.0));
}

test "avar segment maps are fully validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const avar_offset: usize = @intCast(try sfntTableOffset(bytes, "avar"));
        writeU16Test(bytes, avar_offset + 4, 1); // Reserved in avar version 1.0.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const avar_offset: usize = @intCast(try sfntTableOffset(bytes, "avar"));
        writeU16Test(bytes, avar_offset + 8, 2); // Segment maps must include -1, 0, and +1 anchors.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const avar_offset: usize = @intCast(try sfntTableOffset(bytes, "avar"));
        writeF2Dot14Test(bytes, avar_offset + 18, -0.25); // Breaks fromCoordinate sort order.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const avar_offset: usize = @intCast(try sfntTableOffset(bytes, "avar"));
        writeF2Dot14Test(bytes, avar_offset + 16, 0.25); // The default coordinate must map to itself.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        const avar_offset: usize = @intCast(try sfntTableOffset(bytes, "avar"));
        writeF2Dot14Test(bytes, avar_offset + 20, -0.25); // toCoordinate would move backwards.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, "avar", @intCast(try sfntTableLength(bytes, "avar") - 2));
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "gvar table matches fvar axes and maxp glyph count" {
    var bytes: [62]u8 = .{0} ** 62;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);

    const gvar_offset = 36;
    writeU16Test(&bytes, gvar_offset + 0, 1);
    writeU16Test(&bytes, gvar_offset + 2, 0);
    writeU16Test(&bytes, gvar_offset + 4, 1); // axisCount matches fvar.
    writeU16Test(&bytes, gvar_offset + 12, 2); // glyphCount matches maxp.
    writeU32Test(&bytes, gvar_offset + 16, 26); // Glyph data begins after three short offsets.

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = gvar_offset };
    const gvar = TableRecord{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = bytes.len - gvar_offset };
    try validateVariationDataTables(&bytes, 2, fvar, gvar, null, null, null, null);

    var axis_mismatch = bytes;
    writeU16Test(&axis_mismatch, gvar_offset + 4, 2);
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&axis_mismatch, 2, fvar, gvar, null, null, null, null));

    var glyph_mismatch = bytes;
    writeU16Test(&glyph_mismatch, gvar_offset + 12, 3);
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&glyph_mismatch, 2, fvar, gvar, null, null, null, null));
}

test "gvar glyph variation data validates tuple payloads" {
    var bytes: [76]u8 = .{0} ** 76;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);

    const gvar_offset = 36;
    writeGvarOneGlyphPrivatePointTupleTest(&bytes, gvar_offset);

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = gvar_offset };
    const gvar = TableRecord{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = bytes.len - gvar_offset };
    try validateVariationDataTables(&bytes, 1, fvar, gvar, null, null, null, null);

    var with_glyf_context: [104]u8 = .{0} ** 104;
    @memcpy(with_glyf_context[0..bytes.len], &bytes);
    const loca_offset = bytes.len;
    const glyf_offset = loca_offset + 4;
    writeU16Test(&with_glyf_context, loca_offset + 0, 0);
    writeU16Test(&with_glyf_context, loca_offset + 2, 12); // Short loca: glyph byte length 24.
    writeI16Test(&with_glyf_context, glyf_offset + 0, 1); // one simple contour.
    writeU16Test(&with_glyf_context, glyf_offset + 10, 2); // three real points plus four phantom points.
    const context = GvarGlyphTargetContext{
        .loca = .{ .tag = .{ 'l', 'o', 'c', 'a' }, .checksum = 0, .offset = loca_offset, .length = 4 },
        .glyf = .{ .tag = .{ 'g', 'l', 'y', 'f' }, .checksum = 0, .offset = glyf_offset, .length = 24 },
        .index_to_loc_format = 0,
    };
    try validateVariationDataTables(&with_glyf_context, 1, fvar, gvar, null, null, null, context);

    var point_past_glyf_target_count = with_glyf_context;
    point_past_glyf_target_count[gvar_offset + 24 + 12] = 7; // Valid structure, but only points 0..6 exist.
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&point_past_glyf_target_count, 1, fvar, gvar, null, null, null, context));

    var truncated_y_delta = bytes;
    writeU16Test(&truncated_y_delta, gvar_offset + 24 + 4, 4); // tuple variationDataSize excludes the Y delta byte.
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&truncated_y_delta, 1, fvar, gvar, null, null, null, null));

    var overstated_point_run = bytes;
    overstated_point_run[gvar_offset + 24 + 11] = 1; // One-point tuple declares a two-entry point-number run.
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&overstated_point_run, 1, fvar, gvar, null, null, null, null));

    var missing_peak_tuple = bytes;
    writeU16Test(&missing_peak_tuple, gvar_offset + 24 + 6, 0x2000); // Private points, but no embedded peak or shared tuple.
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&missing_peak_tuple, 1, fvar, gvar, null, null, null, null));

    var reserved_flags = bytes;
    writeU16Test(&reserved_flags, gvar_offset + 14, 0x0002);
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&reserved_flags, 1, fvar, gvar, null, null, null, null));
}

test "gvar tuple coordinates validate normalized peaks and intermediate regions" {
    const gvar_offset = 36;

    var embedded_peak: [76]u8 = .{0} ** 76;
    writeU32Test(&embedded_peak, 0, 0x00010000);
    writeU16Test(&embedded_peak, 4, 16);
    writeU16Test(&embedded_peak, 6, 2);
    writeU16Test(&embedded_peak, 8, 1);
    writeU16Test(&embedded_peak, 10, 20);
    writeFvarAxisTest(&embedded_peak, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeGvarOneGlyphPrivatePointTupleTest(&embedded_peak, gvar_offset);

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = gvar_offset };
    const embedded_gvar = TableRecord{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = embedded_peak.len - gvar_offset };
    try validateVariationDataTables(&embedded_peak, 1, fvar, embedded_gvar, null, null, null, null);

    var peak_outside_normalized_space = embedded_peak;
    writeI16Test(&peak_outside_normalized_space, gvar_offset + 24 + 8, 0x4001);
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&peak_outside_normalized_space, 1, fvar, embedded_gvar, null, null, null, null));

    var shared_peak: [78]u8 = .{0} ** 78;
    writeU32Test(&shared_peak, 0, 0x00010000);
    writeU16Test(&shared_peak, 4, 16);
    writeU16Test(&shared_peak, 6, 2);
    writeU16Test(&shared_peak, 8, 1);
    writeU16Test(&shared_peak, 10, 20);
    writeFvarAxisTest(&shared_peak, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeGvarOneGlyphSharedTupleTest(&shared_peak, gvar_offset, 1.0);

    const shared_gvar = TableRecord{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = shared_peak.len - gvar_offset };
    try validateVariationDataTables(&shared_peak, 1, fvar, shared_gvar, null, null, null, null);

    var shared_peak_outside_normalized_space = shared_peak;
    writeI16Test(&shared_peak_outside_normalized_space, gvar_offset + 24, 0x4001);
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&shared_peak_outside_normalized_space, 1, fvar, shared_gvar, null, null, null, null));

    var intermediate: [80]u8 = .{0} ** 80;
    writeU32Test(&intermediate, 0, 0x00010000);
    writeU16Test(&intermediate, 4, 16);
    writeU16Test(&intermediate, 6, 2);
    writeU16Test(&intermediate, 8, 1);
    writeU16Test(&intermediate, 10, 20);
    writeFvarAxisTest(&intermediate, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeGvarOneGlyphIntermediateTupleTest(&intermediate, gvar_offset, 0.0, 0.5, 1.0);

    const intermediate_gvar = TableRecord{ .tag = .{ 'g', 'v', 'a', 'r' }, .checksum = 0, .offset = gvar_offset, .length = intermediate.len - gvar_offset };
    try validateVariationDataTables(&intermediate, 1, fvar, intermediate_gvar, null, null, null, null);

    var reversed_intermediate = intermediate;
    writeF2Dot14Test(&reversed_intermediate, gvar_offset + 24 + 10, 0.75); // start > peak.
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&reversed_intermediate, 1, fvar, intermediate_gvar, null, null, null, null));

    var crossing_intermediate = intermediate;
    writeF2Dot14Test(&crossing_intermediate, gvar_offset + 24 + 10, -1.0); // Crosses zero with a non-zero peak.
    try std.testing.expectError(error.BadSfnt, validateVariationDataTables(&crossing_intermediate, 1, fvar, intermediate_gvar, null, null, null, null));

    var ignored_axis_intermediate = intermediate;
    writeGvarOneGlyphIntermediateTupleTest(&ignored_axis_intermediate, gvar_offset, -1.0, 0.0, 1.0);
    try validateVariationDataTables(&ignored_axis_intermediate, 1, fvar, intermediate_gvar, null, null, null, null);
}

test "VariationStore data validates axis and region indexes" {
    var bytes: [54]u8 = .{0} ** 54;
    writeHvarTableWithOneItemVariationData(&bytes);
    const hvar = TableRecord{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateMetricVariationTable(&bytes, hvar, 1, 20);

    var axis_mismatch = bytes;
    writeU16Test(&axis_mismatch, 32, 2); // VariationRegionList axisCount.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&axis_mismatch, hvar, 1, 20));

    var bad_region_index = bytes;
    writeU16Test(&bad_region_index, 50, 1); // Only region index 0 is declared.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&bad_region_index, hvar, 1, 20));
}

test "MVAR value records reference existing ItemVariationData items" {
    var bytes: [54]u8 = .{0} ** 54;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU16Test(&bytes, 6, 8); // valueRecordSize.
    writeU16Test(&bytes, 8, 1); // one value record.
    writeU16Test(&bytes, 10, 20); // ItemVariationStore offset.
    writeTagTest(&bytes, 12, "hasc");
    writeU16Test(&bytes, 16, 0); // outerIndex.
    writeU16Test(&bytes, 18, 0); // innerIndex.
    writeItemVariationStoreWithOneItem(&bytes, 20);

    const mvar = TableRecord{ .tag = .{ 'M', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateMvarTable(&bytes, mvar, 1);

    var bad_inner_index = bytes;
    writeU16Test(&bad_inner_index, 18, 1);
    try std.testing.expectError(error.BadSfnt, validateMvarTable(&bad_inner_index, mvar, 1));
}

test "STAT design axes must match fvar axis ordering" {
    var bytes: [78]u8 = .{0} ** 78;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);

    const stat_offset = 36;
    writeStatHeaderTest(&bytes, stat_offset, 1, 1, 28);
    writeStatAxisTest(&bytes, stat_offset + 20, "wght", 256, 0);
    writeU16Test(&bytes, stat_offset + 28, 2);
    writeStatAxisValueFormat1Test(&bytes, stat_offset + 30, 0);

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = 36 };
    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = stat_offset, .length = bytes.len - stat_offset };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258 });
    try validateStatTable(std.testing.allocator, &bytes, stat, fvar, &names);

    var mismatched = bytes;
    writeTagTest(&mismatched, stat_offset + 20, "wdth");
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &mismatched, stat, fvar, &names));
}

test "STAT design axes have unique tags and ordering values" {
    var bytes: [56]u8 = .{0} ** 56;
    writeStatHeaderTest(&bytes, 0, 2, 0, 0);
    writeStatAxisTest(&bytes, 20, "wght", 256, 0);
    writeStatAxisTest(&bytes, 28, "wdth", 257, 1);

    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = nameIndexForTest(&.{ 2, 256, 257 });
    try validateStatTable(std.testing.allocator, &bytes, stat, null, &names);

    var duplicate_tag = bytes;
    writeStatAxisTest(&duplicate_tag, 28, "wght", 257, 1);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_tag, stat, null, &names));

    var duplicate_order = bytes;
    writeStatAxisTest(&duplicate_order, 28, "wdth", 257, 0);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_order, stat, null, &names));
}

test "STAT AxisValue offsets and axis indexes stay inside declared records" {
    var metadata_overlap: [42]u8 = .{0} ** 42;
    writeStatHeaderTest(&metadata_overlap, 0, 1, 1, 28);
    writeStatAxisTest(&metadata_overlap, 20, "wght", 256, 0);
    writeU16Test(&metadata_overlap, 28, 0); // Points back into the AxisValue offsets array.
    writeStatAxisValueFormat1Test(&metadata_overlap, 30, 0);

    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = metadata_overlap.len };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258 });
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &metadata_overlap, stat, null, &names));

    var bad_axis_index = metadata_overlap;
    writeU16Test(&bad_axis_index, 28, 2);
    writeStatAxisValueFormat1Test(&bad_axis_index, 30, 1); // Only axis 0 is declared.
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &bad_axis_index, stat, null, &names));
}

test "STAT AxisValue offset array is strictly increasing" {
    var bytes: [64]u8 = .{0} ** 64;
    writeStatHeaderTest(&bytes, 0, 1, 2, 28);
    writeStatAxisTest(&bytes, 20, "wght", 256, 0);
    writeU16Test(&bytes, 28, 4);
    writeU16Test(&bytes, 30, 24);
    writeStatAxisValueFormat2Test(&bytes, 32, 0, 258, 350.0, 300.0, 400.0);
    writeStatAxisValueFormat1WithValueTest(&bytes, 52, 0, 259, 500.0);

    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258, 259 });
    try validateStatTable(std.testing.allocator, &bytes, stat, null, &names);

    var decreasing_offsets = bytes;
    writeU16Test(&decreasing_offsets, 28, 24);
    writeU16Test(&decreasing_offsets, 30, 4);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &decreasing_offsets, stat, null, &names));

    var duplicate_offsets = bytes;
    writeU16Test(&duplicate_offsets, 30, 4);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_offsets, stat, null, &names));
}

test "STAT AxisValue payloads do not overlap" {
    var bytes: [64]u8 = .{0} ** 64;
    writeStatHeaderTest(&bytes, 0, 1, 2, 28);
    writeStatAxisTest(&bytes, 20, "wght", 256, 0);
    writeU16Test(&bytes, 28, 4);
    writeU16Test(&bytes, 30, 24);
    writeStatAxisValueFormat2Test(&bytes, 32, 0, 258, 350.0, 300.0, 400.0);
    writeStatAxisValueFormat1WithValueTest(&bytes, 52, 0, 258, 500.0);

    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258 });
    try validateStatTable(std.testing.allocator, &bytes, stat, null, &names);

    var overlapping_payload = bytes;
    writeU16Test(&overlapping_payload, 30, 12); // Starts inside the first 20-byte AxisValue record.
    writeStatAxisValueFormat1WithValueTest(&overlapping_payload, 40, 0, 258, 400.0);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &overlapping_payload, stat, null, &names));
}

test "STAT AxisValue ranges and points avoid ambiguous overlaps" {
    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = 94 };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258, 259, 260, 261 });

    var touching_ranges: [94]u8 = .{0} ** 94;
    writeStatHeaderTest(&touching_ranges, 0, 1, 3, 28);
    writeStatAxisTest(&touching_ranges, 20, "wght", 256, 0);
    writeU16Test(&touching_ranges, 28, 6);
    writeU16Test(&touching_ranges, 30, 26);
    writeU16Test(&touching_ranges, 32, 46);
    writeStatAxisValueFormat2Test(&touching_ranges, 34, 0, 258, 350.0, 300.0, 400.0);
    writeStatAxisValueFormat2Test(&touching_ranges, 54, 0, 259, 450.0, 400.0, 500.0);
    writeStatAxisValueFormat1WithValueTest(&touching_ranges, 74, 0, 260, 500.0);
    try validateStatTable(std.testing.allocator, &touching_ranges, stat, null, &names);

    var overlapping_ranges = touching_ranges;
    writeStatAxisValueFormat2Test(&overlapping_ranges, 54, 0, 259, 450.0, 399.0, 500.0);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &overlapping_ranges, stat, null, &names));

    var duplicate_boundary_nominal = touching_ranges;
    writeStatAxisValueFormat2Test(&duplicate_boundary_nominal, 34, 0, 258, 400.0, 300.0, 400.0);
    writeStatAxisValueFormat2Test(&duplicate_boundary_nominal, 54, 0, 259, 400.0, 400.0, 500.0);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_boundary_nominal, stat, null, &names));

    var point_inside_range = touching_ranges;
    writeStatAxisValueFormat1WithValueTest(&point_inside_range, 74, 0, 260, 350.0);
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &point_inside_range, stat, null, &names));

    var linked_point_at_nominal = touching_ranges;
    writeStatAxisValueFormat3Test(&linked_point_at_nominal, 74, 0, 258, 350.0, 700.0);
    try validateStatTable(std.testing.allocator, &linked_point_at_nominal, stat, null, &names);

    var duplicate_points: [60]u8 = .{0} ** 60;
    writeStatHeaderTest(&duplicate_points, 0, 1, 2, 28);
    writeStatAxisTest(&duplicate_points, 20, "wght", 256, 0);
    writeU16Test(&duplicate_points, 28, 4);
    writeU16Test(&duplicate_points, 30, 16);
    writeStatAxisValueFormat1WithValueTest(&duplicate_points, 32, 0, 258, 400.0);
    writeStatAxisValueFormat3Test(&duplicate_points, 44, 0, 261, 400.0, 700.0);
    const duplicate_points_stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = duplicate_points.len };
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_points, duplicate_points_stat, null, &names));
}

test "STAT format 4 AxisValue records reference each axis once" {
    var duplicate_axis: [46]u8 = .{0} ** 46;
    writeStatHeaderTest(&duplicate_axis, 0, 1, 1, 28);
    writeStatAxisTest(&duplicate_axis, 20, "wght", 256, 0);
    writeU16Test(&duplicate_axis, 28, 2);
    writeU16Test(&duplicate_axis, 30, 4);
    writeU16Test(&duplicate_axis, 32, 2); // axisCount.
    writeU16Test(&duplicate_axis, 34, 0); // flags.
    writeU16Test(&duplicate_axis, 36, 258);
    writeU16Test(&duplicate_axis, 38, 0);
    writeF16Dot16Test(&duplicate_axis, 40, 400.0);
    writeU16Test(&duplicate_axis, 44, 0); // Duplicate axis index.

    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = duplicate_axis.len };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258 });
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_axis, stat, null, &names));
}

test "STAT single-axis format 4 values must not duplicate point or range labels" {
    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = 80 };
    const names = nameIndexForTest(&.{ 0, 2, 256, 258, 259, 260 });

    var bytes: [80]u8 = .{0} ** 80;
    writeStatHeaderTest(&bytes, 0, 1, 3, 28);
    writeStatAxisTest(&bytes, 20, "wght", 256, 0);
    writeU16Test(&bytes, 28, 6);
    writeU16Test(&bytes, 30, 18);
    writeU16Test(&bytes, 32, 38);
    writeStatAxisValueFormat1WithValueTest(&bytes, 34, 0, 258, 700.0);
    writeStatAxisValueFormat2Test(&bytes, 46, 0, 259, 450.0, 400.0, 500.0);
    writeStatAxisValueFormat4Test(&bytes, 66, 260, &.{
        .{ .axis_index = 0, .value = 300.0 },
    });
    try validateStatTable(std.testing.allocator, &bytes, stat, null, &names);

    var duplicate_point = bytes;
    writeStatAxisValueFormat4Test(&duplicate_point, 66, 260, &.{
        .{ .axis_index = 0, .value = 700.0 },
    });
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_point, stat, null, &names));

    var inside_range = bytes;
    writeStatAxisValueFormat4Test(&inside_range, 66, 260, &.{
        .{ .axis_index = 0, .value = 450.0 },
    });
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &inside_range, stat, null, &names));

    var boundary = bytes;
    writeStatAxisValueFormat4Test(&boundary, 66, 260, &.{
        .{ .axis_index = 0, .value = 400.0 },
    });
    try validateStatTable(std.testing.allocator, &boundary, stat, null, &names);
}

test "STAT format 4 AxisValue coordinate sets must be unique" {
    var bytes: [96]u8 = .{0} ** 96;
    writeStatHeaderTest(&bytes, 0, 2, 3, 36);
    writeStatAxisTest(&bytes, 20, "wght", 256, 0);
    writeStatAxisTest(&bytes, 28, "wdth", 257, 1);
    writeU16Test(&bytes, 36, 6);
    writeU16Test(&bytes, 38, 26);
    writeU16Test(&bytes, 40, 40);
    writeStatAxisValueFormat4Test(&bytes, 42, 258, &.{
        .{ .axis_index = 0, .value = 400.0 },
        .{ .axis_index = 1, .value = 100.0 },
    });
    writeStatAxisValueFormat4Test(&bytes, 62, 259, &.{
        .{ .axis_index = 0, .value = 400.0 },
    });
    writeStatAxisValueFormat4Test(&bytes, 76, 260, &.{
        .{ .axis_index = 0, .value = 700.0 },
        .{ .axis_index = 1, .value = 100.0 },
    });

    const stat = TableRecord{ .tag = .{ 'S', 'T', 'A', 'T' }, .checksum = 0, .offset = 0, .length = bytes.len };
    const names = nameIndexForTest(&.{ 2, 256, 257, 258, 259, 260 });
    try validateStatTable(std.testing.allocator, &bytes, stat, null, &names);

    var duplicate_coordinate_set = bytes;
    writeStatAxisValueFormat4Test(&duplicate_coordinate_set, 76, 260, &.{
        .{ .axis_index = 1, .value = 100.0 },
        .{ .axis_index = 0, .value = 400.0 },
    });
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &duplicate_coordinate_set, stat, null, &names));
}

test "OS/2 style attributes respect versioned table lengths" {
    var valid_v4: [96]u8 = .{0} ** 96;
    writeU16Test(&valid_v4, 0, 4); // OS/2 v4 requires the 96-byte v2+ payload.
    writeU16Test(&valid_v4, 4, 650);
    writeU16Test(&valid_v4, 6, 3);
    writeU16Test(&valid_v4, 62, 0x0021); // italic + bold

    const valid_font = os2OnlyFont(&valid_v4, valid_v4.len);
    const attributes = try valid_font.styleAttributes();
    try std.testing.expectEqual(@as(u16, 650), attributes.weight);
    try std.testing.expectEqual(@as(u16, 3), attributes.width);
    try std.testing.expect(attributes.italic);
    try std.testing.expect(attributes.bold);

    const truncated_v4 = os2OnlyFont(&valid_v4, 64);
    try std.testing.expectError(error.BadSfnt, truncated_v4.styleAttributes());

    var truncated_v5: [100]u8 = .{0} ** 100;
    writeU16Test(&truncated_v5, 0, 5); // v5 extends v2-v4 by optical size fields.
    writeU16Test(&truncated_v5, 4, 400);
    writeU16Test(&truncated_v5, 6, 5);
    const short_v5 = os2OnlyFont(&truncated_v5, 96);
    try std.testing.expectError(error.BadSfnt, short_v5.styleAttributes());
}

test "OS/2 table is validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Wide", "Metric Sans Wide", 400, 10, false, false);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Broken", "Metric Sans Broken", 0, 5, false, false);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Broken", "Metric Sans Broken", 400, 5, false, false);
        defer allocator.free(bytes);
        try setSfntTableLength(bytes, "OS/2", 64);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Broken", "Metric Sans Broken", 400, 5, false, false);
        defer allocator.free(bytes);
        const os2_offset = try sfntTableOffset(bytes, "OS/2");
        writeU16Test(bytes, os2_offset + 62, 0x0400);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Bold", "Metric Sans Bold", 700, 5, false, true);
        defer allocator.free(bytes);
        const os2_offset = try sfntTableOffset(bytes, "OS/2");
        // REGULAR contradicts named style bits such as BOLD/ITALIC/OBLIQUE and
        // should not be accepted simply because styleAttributes can read it.
        writeU16Test(bytes, os2_offset + 62, 0x0060);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
        defer allocator.free(bytes);
        const os2_offset = try sfntTableOffset(bytes, "OS/2");
        writeU16Test(bytes, os2_offset, 6);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

fn gdefOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 64,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 1,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .os2 = null,
        .gdef = .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = data.len },
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .colr = null,
        .cpal = null,
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn os2OnlyFont(data: []const u8, declared_length: usize) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 2,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 2,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .os2 = .{ .tag = .{ 'O', 'S', '/', '2' }, .checksum = 0, .offset = 0, .length = declared_length },
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .colr = null,
        .cpal = null,
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn colrOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 16,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 2,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .os2 = null,
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .colr = .{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = data.len },
        .cpal = null,
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn colrCpalOnlyFont(data: []const u8, colr_length: usize) Font {
    var font = colrOnlyFont(data);
    font.colr = .{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_length };
    font.cpal = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = colr_length, .length = data.len - colr_length };
    return font;
}

fn cpalOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 2,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 2,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .os2 = null,
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .colr = null,
        .cpal = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = data.len },
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn svgOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 4,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 2,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .os2 = null,
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .colr = null,
        .cpal = null,
        .svg = .{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = data.len },
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn fvarOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 2,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 2,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .os2 = null,
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = .{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = data.len },
        .avar = null,
        .colr = null,
        .cpal = null,
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn avarOnlyFont(data: []const u8) Font {
    var font = fvarOnlyFont(data);
    font.fvar = null;
    font.avar = .{ .tag = .{ 'a', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = data.len };
    return font;
}

fn fvarAvarOnlyFont(data: []const u8, fvar_length: usize) Font {
    var font = fvarOnlyFont(data);
    font.fvar = .{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = fvar_length };
    font.avar = .{ .tag = .{ 'a', 'v', 'a', 'r' }, .checksum = 0, .offset = fvar_length, .length = data.len - fvar_length };
    return font;
}

fn kernOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    return .{
        .data = data,
        .format = .truetype,
        .units_per_em = 1000,
        .index_to_loc_format = 0,
        .glyph_count = 2,
        .ascender = 0,
        .descender = 0,
        .line_gap = 0,
        .number_of_h_metrics = 2,
        .head = dummy_table,
        .hhea = dummy_table,
        .maxp = dummy_table,
        .hmtx = dummy_table,
        .loca = null,
        .cmap = dummy_table,
        .kern = .{ .tag = .{ 'k', 'e', 'r', 'n' }, .checksum = 0, .offset = 0, .length = data.len },
        .os2 = null,
        .gdef = null,
        .gpos = null,
        .gsub = null,
        .name = null,
        .stat = null,
        .fvar = null,
        .avar = null,
        .colr = null,
        .cpal = null,
        .svg = null,
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .glyf = null,
        .cff = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn setSfntTableLength(bytes: []u8, comptime table_tag: []const u8, length: u32) FontError!void {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, 4);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset + 16 > bytes.len) return error.BadSfnt;
        if (!std.mem.eql(u8, bytes[record_offset .. record_offset + 4], table_tag)) continue;
        writeU32Test(bytes, record_offset + 12, length);
        return;
    }
    return error.MissingTable;
}

fn sfntTableOffset(bytes: []const u8, comptime table_tag: []const u8) FontError!u32 {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, 4);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset + 16 > bytes.len) return error.BadSfnt;
        if (std.mem.eql(u8, bytes[record_offset .. record_offset + 4], table_tag)) {
            return @intCast(try bin.readU32At(bytes, record_offset + 8));
        }
    }
    return error.MissingTable;
}

fn sfntTableLength(bytes: []const u8, comptime table_tag: []const u8) FontError!u32 {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, 4);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset + 16 > bytes.len) return error.BadSfnt;
        if (std.mem.eql(u8, bytes[record_offset .. record_offset + 4], table_tag)) {
            return try bin.readU32At(bytes, record_offset + 12);
        }
    }
    return error.MissingTable;
}

fn setSfntTableOffset(bytes: []u8, comptime table_tag: []const u8, offset: u32) FontError!void {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, 4);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset + 16 > bytes.len) return error.BadSfnt;
        if (!std.mem.eql(u8, bytes[record_offset .. record_offset + 4], table_tag)) continue;
        writeU32Test(bytes, record_offset + 8, offset);
        return;
    }
    return error.MissingTable;
}

fn setSfntTableTag(bytes: []u8, comptime old_tag: []const u8, comptime new_tag: []const u8) FontError!void {
    if (old_tag.len != 4 or new_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, 4);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset + 16 > bytes.len) return error.BadSfnt;
        if (!std.mem.eql(u8, bytes[record_offset .. record_offset + 4], old_tag)) continue;
        @memcpy(bytes[record_offset .. record_offset + 4], new_tag);
        return;
    }
    return error.MissingTable;
}

fn nameRecordOffsetForId(bytes: []const u8, name_offset: usize, name_id: u16) FontError!usize {
    if (name_offset + 6 > bytes.len) return error.BadSfnt;
    const count = try bin.readU16At(bytes, name_offset + 2);
    for (0..count) |index| {
        const record_offset = name_offset + name_records_start + index * name_record_size;
        if (record_offset + name_record_size > bytes.len) return error.BadSfnt;
        if (try bin.readU16At(bytes, record_offset + 6) == name_id) return record_offset;
    }
    return error.InvalidName;
}

fn nameTableRecord(length: usize) TableRecord {
    return .{ .tag = .{ 'n', 'a', 'm', 'e' }, .checksum = 0, .offset = 0, .length = length };
}

fn writeNameRecordTest(bytes: []u8, offset: usize, platform_id: u16, encoding_id: u16, language_id: u16, name_id: u16, length: u16, storage_offset: u16) void {
    writeU16Test(bytes, offset + 0, platform_id);
    writeU16Test(bytes, offset + 2, encoding_id);
    writeU16Test(bytes, offset + 4, language_id);
    writeU16Test(bytes, offset + 6, name_id);
    writeU16Test(bytes, offset + 8, length);
    writeU16Test(bytes, offset + 10, storage_offset);
}

fn writeUtf16NameRecordTest(bytes: []u8, offset: usize, name_id: u16, length: u16, storage_offset: u16) void {
    writeNameRecordTest(bytes, offset, 3, 1, 0x0409, name_id, length, storage_offset);
}

fn nameIndexForTest(name_ids: []const u16) NameIdIndex {
    var index = NameIdIndex{};
    for (name_ids) |name_id| index.add(name_id);
    return index;
}

fn writeKernFormat0Subtable(bytes: []u8, offset: usize, coverage: u16, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId, value: i16) void {
    writeU16Test(bytes, offset + 0, 0);
    writeU16Test(bytes, offset + 2, 20);
    writeU16Test(bytes, offset + 4, coverage);
    writeKernFormat0Body(bytes, offset + 6, left, right, value);
}

fn writeAppleKernFormat0Subtable(bytes: []u8, offset: usize, coverage: u16, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId, value: i16) void {
    writeU32Test(bytes, offset + 0, 23);
    writeU16Test(bytes, offset + 4, coverage);
    writeU16Test(bytes, offset + 6, 0); // tupleIndex
    writeKernFormat0Body(bytes, offset + 8, left, right, value);
}

fn writeKernFormat0Body(bytes: []u8, offset: usize, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId, value: i16) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 6);
    writeU16Test(bytes, offset + 4, 0);
    writeU16Test(bytes, offset + 6, 0);
    writeU16Test(bytes, offset + 8, left);
    writeU16Test(bytes, offset + 10, right);
    writeI16Test(bytes, offset + 12, value);
}

fn writePostHeaderTest(bytes: []u8, version: u32) void {
    writeU32Test(bytes, 0, version);
    writeU32Test(bytes, 4, 0); // italicAngle.
    writeI16Test(bytes, 8, 0); // underlinePosition.
    writeI16Test(bytes, 10, 0); // underlineThickness.
    writeU32Test(bytes, 12, 0); // isFixedPitch.
    writeU32Test(bytes, 16, 0); // minMemType42.
    writeU32Test(bytes, 20, 0); // maxMemType42.
    writeU32Test(bytes, 24, 0); // minMemType1.
    writeU32Test(bytes, 28, 0); // maxMemType1.
}

fn writeSingleEntryCpalTest(bytes: []u8, offset: usize) void {
    writeU16Test(bytes, offset + 0, 0); // version.
    writeU16Test(bytes, offset + 2, 1); // numPaletteEntries.
    writeU16Test(bytes, offset + 4, 1); // numPalettes.
    writeU16Test(bytes, offset + 6, 1); // numColorRecords.
    writeU32Test(bytes, offset + 8, 14);
    writeU16Test(bytes, offset + 12, 0);
    bytes[offset + 14] = 0;
    bytes[offset + 15] = 0;
    bytes[offset + 16] = 255;
    bytes[offset + 17] = 255;
}

fn writeTwoEntryCpalTest(bytes: []u8, offset: usize) void {
    writeU16Test(bytes, offset + 0, 0); // version.
    writeU16Test(bytes, offset + 2, 2); // numPaletteEntries.
    writeU16Test(bytes, offset + 4, 1); // numPalettes.
    writeU16Test(bytes, offset + 6, 2); // numColorRecords.
    writeU32Test(bytes, offset + 8, 16);
    writeU16Test(bytes, offset + 12, 0);
    bytes[offset + 16] = 0;
    bytes[offset + 17] = 0;
    bytes[offset + 18] = 255;
    bytes[offset + 19] = 255;
    bytes[offset + 20] = 255;
    bytes[offset + 21] = 0;
    bytes[offset + 22] = 0;
    bytes[offset + 23] = 255;
}

fn writeFvarAxisTest(bytes: []u8, offset: usize, tag_text: []const u8, min: f32, default: f32, max: f32, name_id: u16) void {
    writeTagTest(bytes, offset, tag_text);
    writeF16Dot16Test(bytes, offset + 4, min);
    writeF16Dot16Test(bytes, offset + 8, default);
    writeF16Dot16Test(bytes, offset + 12, max);
    writeU16Test(bytes, offset + 16, 0);
    writeU16Test(bytes, offset + 18, name_id);
}

fn writeStatHeaderTest(bytes: []u8, offset: usize, design_axis_count: u16, axis_value_count: u16, axis_value_offsets_offset: u32) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, 1);
    writeU16Test(bytes, offset + 4, 8);
    writeU16Test(bytes, offset + 6, design_axis_count);
    writeU32Test(bytes, offset + 8, 20);
    writeU16Test(bytes, offset + 12, axis_value_count);
    writeU32Test(bytes, offset + 14, axis_value_offsets_offset);
    writeU16Test(bytes, offset + 18, 2); // elidedFallbackNameID
}

fn writeStatAxisTest(bytes: []u8, offset: usize, tag_text: []const u8, name_id: u16, ordering: u16) void {
    writeTagTest(bytes, offset, tag_text);
    writeU16Test(bytes, offset + 4, name_id);
    writeU16Test(bytes, offset + 6, ordering);
}

fn writeStatAxisValueFormat1Test(bytes: []u8, offset: usize, axis_index: u16) void {
    writeStatAxisValueFormat1WithValueTest(bytes, offset, axis_index, 258, 400.0);
}

fn writeStatAxisValueFormat1WithValueTest(bytes: []u8, offset: usize, axis_index: u16, name_id: u16, value: f32) void {
    writeU16Test(bytes, offset + 0, 1);
    writeU16Test(bytes, offset + 2, axis_index);
    writeU16Test(bytes, offset + 4, 0);
    writeU16Test(bytes, offset + 6, name_id);
    writeF16Dot16Test(bytes, offset + 8, value);
}

fn writeStatAxisValueFormat2Test(bytes: []u8, offset: usize, axis_index: u16, name_id: u16, nominal: f32, min: f32, max: f32) void {
    writeU16Test(bytes, offset + 0, 2);
    writeU16Test(bytes, offset + 2, axis_index);
    writeU16Test(bytes, offset + 4, 0);
    writeU16Test(bytes, offset + 6, name_id);
    writeF16Dot16Test(bytes, offset + 8, nominal);
    writeF16Dot16Test(bytes, offset + 12, min);
    writeF16Dot16Test(bytes, offset + 16, max);
}

fn writeStatAxisValueFormat3Test(bytes: []u8, offset: usize, axis_index: u16, name_id: u16, value: f32, linked_value: f32) void {
    writeU16Test(bytes, offset + 0, 3);
    writeU16Test(bytes, offset + 2, axis_index);
    writeU16Test(bytes, offset + 4, 0);
    writeU16Test(bytes, offset + 6, name_id);
    writeF16Dot16Test(bytes, offset + 8, value);
    writeF16Dot16Test(bytes, offset + 12, linked_value);
}

const StatAxisValueFormat4CoordinateTest = struct {
    axis_index: u16,
    value: f32,
};

fn writeStatAxisValueFormat4Test(bytes: []u8, offset: usize, name_id: u16, coordinates: []const StatAxisValueFormat4CoordinateTest) void {
    writeU16Test(bytes, offset + 0, 4);
    writeU16Test(bytes, offset + 2, @intCast(coordinates.len));
    writeU16Test(bytes, offset + 4, 0);
    writeU16Test(bytes, offset + 6, name_id);
    for (coordinates, 0..) |coordinate, index| {
        const record_offset = offset + 8 + index * 6;
        writeU16Test(bytes, record_offset + 0, coordinate.axis_index);
        writeF16Dot16Test(bytes, record_offset + 2, coordinate.value);
    }
}

fn writeHvarTableWithOneItemVariationData(bytes: []u8) void {
    writeU16Test(bytes, 0, 1);
    writeU16Test(bytes, 2, 0);
    writeU32Test(bytes, 4, 20); // ItemVariationStore offset.
    writeItemVariationStoreWithOneItem(bytes, 20);
}

fn writeItemVariationStoreWithOneItem(bytes: []u8, offset: usize) void {
    writeItemVariationStoreWithItems(bytes, offset, 1);
}

fn writeItemVariationStoreWithItems(bytes: []u8, offset: usize, item_count: u16) void {
    writeU16Test(bytes, offset + 0, 1); // format.
    writeU32Test(bytes, offset + 2, 12); // VariationRegionList offset.
    writeU16Test(bytes, offset + 6, 1); // itemVariationDataCount.
    writeU32Test(bytes, offset + 8, 24); // ItemVariationData offset.

    writeU16Test(bytes, offset + 12, 1); // axisCount.
    writeU16Test(bytes, offset + 14, 1); // regionCount.
    writeF2Dot14Test(bytes, offset + 16, -1.0);
    writeF2Dot14Test(bytes, offset + 18, 0.0);
    writeF2Dot14Test(bytes, offset + 20, 1.0);

    writeU16Test(bytes, offset + 24, item_count);
    writeU16Test(bytes, offset + 26, 1); // wordDeltaCount.
    writeU16Test(bytes, offset + 28, 1); // regionIndexCount.
    writeU16Test(bytes, offset + 30, 0); // regionIndexes[0].
    for (0..item_count) |index| {
        writeI16Test(bytes, offset + 32 + index * 2, 7); // delta rows.
    }
}

fn writeGvarOneGlyphPrivatePointTupleTest(bytes: []u8, offset: usize) void {
    writeU16Test(bytes, offset + 0, 1); // majorVersion.
    writeU16Test(bytes, offset + 2, 0); // minorVersion.
    writeU16Test(bytes, offset + 4, 1); // axisCount.
    writeU16Test(bytes, offset + 12, 1); // glyphCount.
    writeU32Test(bytes, offset + 16, 24); // GlyphVariationData array after two short offsets.
    writeU16Test(bytes, offset + 20, 0);
    writeU16Test(bytes, offset + 22, 8); // One 16-byte GlyphVariationData block.

    const glyph_data = offset + 24;
    writeU16Test(bytes, glyph_data + 0, 1); // one TupleVariationHeader.
    writeU16Test(bytes, glyph_data + 2, 10); // serialized data starts after the embedded peak tuple.
    writeU16Test(bytes, glyph_data + 4, 6); // private point numbers plus X/Y packed deltas.
    writeU16Test(bytes, glyph_data + 6, 0xa000); // embedded peak tuple and private point numbers.
    writeF2Dot14Test(bytes, glyph_data + 8, 1.0); // peakTuple[0].
    bytes[glyph_data + 10] = 1; // one explicit point number.
    bytes[glyph_data + 11] = 0; // one byte-sized point-number delta follows.
    bytes[glyph_data + 12] = 0; // point 0.
    bytes[glyph_data + 13] = 0x80; // one zero X delta.
    bytes[glyph_data + 14] = 0; // one byte-sized Y delta.
    bytes[glyph_data + 15] = 7;
}

fn writeGvarOneGlyphSharedTupleTest(bytes: []u8, offset: usize, peak: f32) void {
    writeU16Test(bytes, offset + 0, 1); // majorVersion.
    writeU16Test(bytes, offset + 2, 0); // minorVersion.
    writeU16Test(bytes, offset + 4, 1); // axisCount.
    writeU16Test(bytes, offset + 6, 1); // one shared tuple.
    writeU32Test(bytes, offset + 8, 24); // Shared tuple array starts after the short offsets.
    writeU16Test(bytes, offset + 12, 1); // glyphCount.
    writeU32Test(bytes, offset + 16, 26); // GlyphVariationData follows the shared tuple.
    writeU16Test(bytes, offset + 20, 0);
    writeU16Test(bytes, offset + 22, 8); // One 16-byte GlyphVariationData block.
    writeF2Dot14Test(bytes, offset + 24, peak);

    const glyph_data = offset + 26;
    writeU16Test(bytes, glyph_data + 0, 1); // one TupleVariationHeader.
    writeU16Test(bytes, glyph_data + 2, 8); // serialized data starts after the shared tuple reference header.
    writeU16Test(bytes, glyph_data + 4, 6); // private point numbers plus X/Y packed deltas.
    writeU16Test(bytes, glyph_data + 6, 0x2000); // shared peak tuple index 0 and private point numbers.
    bytes[glyph_data + 8] = 1;
    bytes[glyph_data + 9] = 0;
    bytes[glyph_data + 10] = 0;
    bytes[glyph_data + 11] = 0x80;
    bytes[glyph_data + 12] = 0;
    bytes[glyph_data + 13] = 7;
}

fn writeGvarOneGlyphIntermediateTupleTest(bytes: []u8, offset: usize, start: f32, peak: f32, end: f32) void {
    writeU16Test(bytes, offset + 0, 1); // majorVersion.
    writeU16Test(bytes, offset + 2, 0); // minorVersion.
    writeU16Test(bytes, offset + 4, 1); // axisCount.
    writeU16Test(bytes, offset + 12, 1); // glyphCount.
    writeU32Test(bytes, offset + 16, 24); // GlyphVariationData array after two short offsets.
    writeU16Test(bytes, offset + 20, 0);
    writeU16Test(bytes, offset + 22, 10); // One 20-byte GlyphVariationData block.

    const glyph_data = offset + 24;
    writeU16Test(bytes, glyph_data + 0, 1); // one TupleVariationHeader.
    writeU16Test(bytes, glyph_data + 2, 14); // serialized data starts after peak/start/end tuples.
    writeU16Test(bytes, glyph_data + 4, 6); // private point numbers plus X/Y packed deltas.
    writeU16Test(bytes, glyph_data + 6, 0xe000); // embedded peak, intermediate region, private points.
    writeF2Dot14Test(bytes, glyph_data + 8, peak);
    writeF2Dot14Test(bytes, glyph_data + 10, start);
    writeF2Dot14Test(bytes, glyph_data + 12, end);
    bytes[glyph_data + 14] = 1;
    bytes[glyph_data + 15] = 0;
    bytes[glyph_data + 16] = 0;
    bytes[glyph_data + 17] = 0x80;
    bytes[glyph_data + 18] = 0;
    bytes[glyph_data + 19] = 7;
}

fn writeTagTest(bytes: []u8, offset: usize, tag_text: []const u8) void {
    std.debug.assert(tag_text.len == 4);
    @memcpy(bytes[offset..][0..4], tag_text);
}

fn writeF16Dot16Test(bytes: []u8, offset: usize, value: f32) void {
    writeI32Test(bytes, offset, @intFromFloat(value * 65536.0));
}

fn writeF2Dot14Test(bytes: []u8, offset: usize, value: f32) void {
    writeI16Test(bytes, offset, @intFromFloat(value * 16384.0));
}

fn writeCmapFormat8HeaderTest(bytes: []u8, length: u32, groups: u32) void {
    writeU16Test(bytes, 0, 0);
    writeU16Test(bytes, 2, 1);
    writeU16Test(bytes, 4, 0);
    writeU16Test(bytes, 6, 4);
    writeU32Test(bytes, 8, 12);
    writeU16Test(bytes, 12, 8);
    writeU32Test(bytes, 16, length);
    writeU32Test(bytes, 8216, groups);
}

fn setCmapFormat8Is32Test(bytes: []u8, word: u16, value: bool) void {
    const byte_offset = 24 + @as(usize, word) / 8;
    const mask: u8 = @as(u8, 0x80) >> @intCast(word & 7);
    if (value) {
        bytes[byte_offset] |= mask;
    } else {
        bytes[byte_offset] &= ~mask;
    }
}

fn writeCmapFormat12HeaderTest(bytes: []u8, length: u32, groups: u32) void {
    writeU16Test(bytes, 0, 0);
    writeU16Test(bytes, 2, 1);
    writeU16Test(bytes, 4, 3);
    writeU16Test(bytes, 6, 10);
    writeU32Test(bytes, 8, 12);
    writeU16Test(bytes, 12, 12);
    writeU32Test(bytes, 16, length);
    writeU32Test(bytes, 24, groups);
}

fn writeCmapFormat14HeaderTest(bytes: []u8, length: u32, records: u32) void {
    writeU16Test(bytes, 0, 0);
    writeU16Test(bytes, 2, 1);
    writeU16Test(bytes, 4, 0);
    writeU16Test(bytes, 6, 5);
    writeU32Test(bytes, 8, 12);
    writeU16Test(bytes, 12, 14);
    writeU32Test(bytes, 14, length);
    writeU32Test(bytes, 18, records);
}

fn writeCmapFormat4TwoSegmentHeaderTest(bytes: []u8, length: u16) void {
    writeU16Test(bytes, 0, 0);
    writeU16Test(bytes, 2, 1);
    writeU16Test(bytes, 4, 3);
    writeU16Test(bytes, 6, 1);
    writeU32Test(bytes, 8, 12);
    writeU16Test(bytes, 12, 4);
    writeU16Test(bytes, 14, length);
    writeU16Test(bytes, 18, 4); // segCountX2: two segments including the required sentinel.
    writeU16Test(bytes, 20, 4);
    writeU16Test(bytes, 22, 1);
    writeU16Test(bytes, 24, 0);
}

fn writeCmapFormat4SegmentTest(bytes: []u8, segment_index: usize, start: u16, end: u16, delta: i16, range_offset: u16) void {
    const subtable = 12;
    writeU16Test(bytes, subtable + 14 + segment_index * 2, end);
    writeU16Test(bytes, subtable + 20 + segment_index * 2, start);
    writeI16Test(bytes, subtable + 24 + segment_index * 2, delta);
    writeU16Test(bytes, subtable + 28 + segment_index * 2, range_offset);
}

fn writeCmapGroupTest(bytes: []u8, offset: usize, start: u32, end: u32, glyph_id: u32) void {
    writeU32Test(bytes, offset, start);
    writeU32Test(bytes, offset + 4, end);
    writeU32Test(bytes, offset + 8, glyph_id);
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU24Test(bytes: []u8, offset: usize, value: u32) void {
    std.debug.assert(value <= 0x00ff_ffff);
    bytes[offset] = @intCast(value >> 16);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeI32Test(bytes: []u8, offset: usize, value: i32) void {
    std.mem.writeInt(i32, bytes[offset..][0..4], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}
