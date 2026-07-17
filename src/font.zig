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
        const tag_value = try bin.readU32At(data, 0);
        if (tag_value != 0x74746366) return 1; // "ttcf"
        if (try bin.readU32At(data, 4) >> 16 != 1 and try bin.readU32At(data, 4) >> 16 != 2) return error.BadSfnt;
        return try bin.readU32At(data, 8);
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
        try r.skip(6);

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

        if (format == .truetype and (glyf == null or loca == null)) return error.MissingTable;
        if (format == .opentype_cff and cff == null) return error.MissingTable;

        const units_per_em = try bin.readU16At(data, head.offset + 18);
        const index_to_loc_format = try bin.readI16At(data, head.offset + 50);
        const ascender = try bin.readI16At(data, hhea.offset + 4);
        const descender = try bin.readI16At(data, hhea.offset + 6);
        const line_gap = try bin.readI16At(data, hhea.offset + 8);
        const number_of_h_metrics = try bin.readU16At(data, hhea.offset + 34);
        const glyph_count = try bin.readU16At(data, maxp.offset + 4);
        if (number_of_h_metrics == 0 or number_of_h_metrics > glyph_count) return error.InvalidMetrics;

        // Record all cmap subtables once. `glyphIndex` can then pick the best
        // supported Unicode mapping per lookup without reparsing the directory.
        const cmap_subtables = try parseCmapSubtables(allocator, data, cmap);
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
    /// for CJK extension planes. Format 13 is the OpenType "many-to-one"
    /// fallback cmap used by last-resort fonts; it is less specific than
    /// format 12 but still materially better than reporting UnsupportedCmap.
    pub fn glyphIndex(self: *const Font, codepoint: u21) FontError!glyph_mod.GlyphId {
        var best: ?CmapSubtable = null;
        for (self.cmap_subtables) |subtable| {
            if (subtable.format != 0 and subtable.format != 4 and subtable.format != 6 and subtable.format != 12 and subtable.format != 13) continue;
            if (best == null or scoreCmap(subtable) > scoreCmap(best.?)) best = subtable;
        }
        const chosen = best orelse return error.UnsupportedCmap;
        return switch (chosen.format) {
            0 => try glyphIndexFormat0(self.data, chosen.offset, codepoint),
            4 => try glyphIndexFormat4(self.data, chosen.offset, codepoint),
            6 => try glyphIndexFormat6(self.data, chosen.offset, codepoint),
            12 => try glyphIndexFormat12(self.data, chosen.offset, codepoint),
            13 => try glyphIndexFormat13(self.data, chosen.offset, codepoint),
            else => error.UnsupportedCmap,
        };
    }

    /// Return horizontal metrics following the hmtx compression rule: glyphs
    /// after `numberOfHMetrics` reuse the last advance width and provide only a
    /// per-glyph left side bearing.
    pub fn horizontalMetrics(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!struct { advance_width: u16, left_side_bearing: i16 } {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
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

    pub fn kerning(self: *const Font, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        const kern = self.kern orelse return 0;
        if (kern.length < 4) return 0;
        const version = try bin.readU16At(self.data, kern.offset);
        if (version != 0) return 0;
        const table_count = try bin.readU16At(self.data, kern.offset + 2);
        var subtable_offset = kern.offset + 4;
        for (0..table_count) |_| {
            if (subtable_offset + 6 > kern.offset + kern.length) return error.BadSfnt;
            const length = try bin.readU16At(self.data, subtable_offset + 2);
            const coverage = try bin.readU16At(self.data, subtable_offset + 4);
            if (length < 6 or subtable_offset + length > kern.offset + kern.length) return error.BadSfnt;
            const format = coverage >> 8;
            const horizontal = (coverage & 0x0001) != 0;
            if (format == 0 and horizontal) {
                return try kernFormat0(self.data[subtable_offset .. subtable_offset + length], left, right);
            }
            subtable_offset += length;
        }
        return 0;
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
        }
        defer if (glyph_classes) |classes| allocator.free(classes);
        defer if (mark_attach_classes) |classes| allocator.free(classes);
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
        }
        defer if (glyph_classes) |classes| allocator.free(classes);
        defer if (mark_attach_classes) |classes| allocator.free(classes);
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

    pub fn styleAttributes(self: *const Font) FontError!StyleAttributes {
        const os2 = self.os2 orelse return .{};
        if (os2.length < 64) return error.BadSfnt;
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
        if (fvar.length < 16) return error.BadSfnt;
        const axes_array_offset = try bin.readU16At(self.data, fvar.offset + 4);
        const axis_count = try bin.readU16At(self.data, fvar.offset + 8);
        const axis_size = try bin.readU16At(self.data, fvar.offset + 10);
        if (axis_size < 20) return error.BadSfnt;
        if (axes_array_offset > fvar.length) return error.BadSfnt;
        const axes_bytes = @as(usize, axis_count) * axis_size;
        if (axes_bytes > fvar.length - axes_array_offset) return error.BadSfnt;

        const axes = try allocator.alloc(VariationAxis, axis_count);
        errdefer allocator.free(axes);
        for (axes, 0..) |*axis, index| {
            const axis_offset = fvar.offset + axes_array_offset + index * axis_size;
            axis.* = .{
                .tag = try bin.readTagAt(self.data, axis_offset),
                .min_value = fixed16_16ToF32(try bin.readI32At(self.data, axis_offset + 4)),
                .default_value = fixed16_16ToF32(try bin.readI32At(self.data, axis_offset + 8)),
                .max_value = fixed16_16ToF32(try bin.readI32At(self.data, axis_offset + 12)),
                .flags = try bin.readU16At(self.data, axis_offset + 16),
                .name_id = try bin.readU16At(self.data, axis_offset + 18),
            };
        }
        return axes;
    }

    pub fn mapVariationCoordinate(self: *const Font, axis_index: usize, normalized: f32) FontError!f32 {
        const avar = self.avar orelse return normalized;
        if (avar.length < 8) return error.BadSfnt;
        const major = try bin.readU16At(self.data, avar.offset);
        if (major != 1) return error.BadSfnt;
        const axis_count = try bin.readU16At(self.data, avar.offset + 6);
        if (axis_index >= axis_count) return normalized;

        var offset = avar.offset + 8;
        for (0..axis_count) |index| {
            if (offset + 2 > avar.offset + avar.length) return error.BadSfnt;
            const pair_count = try bin.readU16At(self.data, offset);
            offset += 2;
            const pair_bytes = @as(usize, pair_count) * 4;
            if (pair_bytes > avar.offset + avar.length - offset) return error.BadSfnt;
            if (index == axis_index) {
                return try mapAvarSegment(self.data[offset .. offset + pair_bytes], normalized);
            }
            offset += pair_bytes;
        }
        return normalized;
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
            }
            return layers;
        }
        return try allocator.alloc(ColorLayer, 0);
    }

    pub fn paletteColor(self: *const Font, palette_index: u16, color_index: u16) FontError!?PaletteColor {
        const cpal = self.cpal orelse return null;
        if (cpal.length < 12) return error.BadSfnt;
        const version = try bin.readU16At(self.data, cpal.offset);
        if (version != 0) return error.BadSfnt;
        const palette_entries = try bin.readU16At(self.data, cpal.offset + 2);
        const palette_count = try bin.readU16At(self.data, cpal.offset + 4);
        const color_count = try bin.readU16At(self.data, cpal.offset + 6);
        const color_records_offset = try bin.readU32At(self.data, cpal.offset + 8);
        if (palette_index >= palette_count or color_index >= palette_entries) return null;
        if (color_records_offset > cpal.length) return error.BadSfnt;
        if (@as(usize, color_count) * 4 > cpal.length - color_records_offset) return error.BadSfnt;
        const palette_start_offset = cpal.offset + 12 + @as(usize, palette_index) * 2;
        if (palette_start_offset + 2 > cpal.offset + cpal.length) return error.BadSfnt;
        const first_color_index = try bin.readU16At(self.data, palette_start_offset);
        const record_index = @as(usize, first_color_index) + color_index;
        if (record_index >= color_count) return null;
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
        const base_glyph_list_offset = try bin.readU32At(self.data, colr.offset + 14);
        if (base_glyph_list_offset == 0 or base_glyph_list_offset > colr.length) return null;
        const list_start = colr.offset + base_glyph_list_offset;
        if (list_start + 4 > colr.offset + colr.length) return error.BadSfnt;
        const record_count = try bin.readU32At(self.data, list_start);
        const records_start = list_start + 4;
        if (@as(usize, record_count) * 6 > colr.offset + colr.length - records_start) return error.BadSfnt;
        for (0..record_count) |index| {
            const record = records_start + index * 6;
            const base_glyph = try bin.readU16At(self.data, record);
            if (base_glyph != glyph_id) continue;
            const paint_offset = try bin.readU32At(self.data, record + 2);
            if (paint_offset > colr.length - base_glyph_list_offset) return error.BadSfnt;
            return try readColorPaint(self.data, colr, list_start + paint_offset);
        }
        return null;
    }

    pub fn colorPaintLayer(self: *const Font, layer_index: u32) FontError!?ColorPaint {
        const colr = self.colr orelse return null;
        if (colr.length < 34) return null;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 1) return null;
        const layer_list_offset = try bin.readU32At(self.data, colr.offset + 18);
        if (layer_list_offset == 0 or layer_list_offset > colr.length) return null;
        const list_start = colr.offset + layer_list_offset;
        if (list_start + 4 > colr.offset + colr.length) return error.BadSfnt;
        const layer_count = try bin.readU32At(self.data, list_start);
        if (layer_index >= layer_count) return null;
        const offsets_start = list_start + 4;
        if (@as(usize, layer_count) * 4 > colr.offset + colr.length - offsets_start) return error.BadSfnt;
        const paint_offset = try bin.readU32At(self.data, offsets_start + @as(usize, layer_index) * 4);
        if (paint_offset > colr.length - layer_list_offset) return error.BadSfnt;
        return try readColorPaint(self.data, colr, list_start + paint_offset);
    }

    pub fn svgGlyphDocument(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?SvgGlyphDocument {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const svg = self.svg orelse return null;
        if (svg.length < 10) return error.BadSfnt;
        const version = try bin.readU16At(self.data, svg.offset);
        if (version != 0) return error.BadSfnt;
        const document_list_offset = try bin.readU32At(self.data, svg.offset + 2);
        if (document_list_offset > svg.length or document_list_offset + 2 > svg.length) return error.BadSfnt;

        const list_start = svg.offset + document_list_offset;
        const list_end = svg.offset + svg.length;
        const entry_count = try bin.readU16At(self.data, list_start);
        const records_start = list_start + 2;
        if (@as(usize, entry_count) * 12 > list_end - records_start) return error.BadSfnt;

        for (0..entry_count) |index| {
            const record = records_start + index * 12;
            const start_glyph_id = try bin.readU16At(self.data, record);
            const end_glyph_id = try bin.readU16At(self.data, record + 2);
            const document_offset = try bin.readU32At(self.data, record + 4);
            const document_length = try bin.readU32At(self.data, record + 8);
            if (end_glyph_id < start_glyph_id) return error.BadSfnt;
            if (glyph_id < start_glyph_id or glyph_id > end_glyph_id) continue;
            if (document_offset > svg.length - document_list_offset or document_length > svg.length - document_list_offset - document_offset) return error.BadSfnt;
            const document_start = list_start + document_offset;
            return .{
                .start_glyph_id = start_glyph_id,
                .end_glyph_id = end_glyph_id,
                .data = self.data[document_start .. document_start + document_length],
            };
        }
        return null;
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
                const strike = try cblcStrike(self.data, cblc, strike_index);
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
    if (offset >= sbix.length) return error.BadSfnt;
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
    };
}

fn sbixGlyphPng(data: []const u8, strike: SbixStrike, glyph_id: glyph_mod.GlyphId) FontError!?BitmapGlyphPng {
    const glyph_offset_pos = strike.offset + 4 + @as(usize, glyph_id) * 4;
    const start = try bin.readU32At(data, glyph_offset_pos);
    const end = try bin.readU32At(data, glyph_offset_pos + 4);
    if (start == end) return null;
    if (end < start or end > strike.length) return error.BadSfnt;
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

fn cblcStrikeCount(data: []const u8, cblc: TableRecord) FontError!usize {
    if (cblc.length < 8) return error.BadSfnt;
    const major = try bin.readU16At(data, cblc.offset);
    const minor = try bin.readU16At(data, cblc.offset + 2);
    if ((major != 2 and major != 3) or minor != 0) return error.BadSfnt;
    const count = try bin.readU32At(data, cblc.offset + 4);
    if (@as(usize, count) * 48 > cblc.length - 8) return error.BadSfnt;
    return @intCast(count);
}

fn cblcStrike(data: []const u8, cblc: TableRecord, strike_index: usize) FontError!CblcStrike {
    const strike_count = try cblcStrikeCount(data, cblc);
    if (strike_index >= strike_count) return error.BadSfnt;
    const offset = cblc.offset + 8 + strike_index * 48;
    const index_array_offset = try bin.readU32At(data, offset);
    const index_tables_size = try bin.readU32At(data, offset + 4);
    const table_count = try bin.readU32At(data, offset + 8);
    if (index_array_offset > cblc.length) return error.BadSfnt;
    if (index_tables_size > cblc.length - index_array_offset) return error.BadSfnt;
    if (@as(usize, table_count) * 8 > index_tables_size) return error.BadSfnt;
    const start_glyph = try bin.readU16At(data, offset + 40);
    const end_glyph = try bin.readU16At(data, offset + 42);
    if (start_glyph > end_glyph) return error.BadSfnt;
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
    _ = glyph_count;
    const strike_count = try cblcStrikeCount(data, cblc);
    var best: ?BitmapGlyphPng = null;
    var best_distance: f32 = std.math.inf(f32);
    for (0..strike_count) |strike_index| {
        const strike = try cblcStrike(data, cblc, strike_index);
        if (glyph_id < strike.start_glyph or glyph_id > strike.end_glyph) continue;
        const location = (try cblcGlyphLocation(data, strike, glyph_id)) orelse continue;
        const glyph = try cbdtGlyphPng(data, cbdt, strike, location);
        const distance = @abs(@as(f32, @floatFromInt(glyph.ppem)) - size_px);
        if (best == null or distance < best_distance) {
            best = glyph;
            best_distance = distance;
        }
    }
    return best;
}

fn cblcGlyphLocation(data: []const u8, strike: CblcStrike, glyph_id: glyph_mod.GlyphId) FontError!?CblcGlyphLocation {
    for (0..strike.table_count) |table_index| {
        const record = strike.offset + table_index * 8;
        if (record + 8 > data.len or record + 8 > strike.offset + strike.index_tables_size) return error.BadSfnt;
        const first = try bin.readU16At(data, record);
        const last = try bin.readU16At(data, record + 2);
        if (glyph_id < first or glyph_id > last) continue;
        const subtable_offset = try bin.readU32At(data, record + 4);
        if (subtable_offset >= strike.index_tables_size) return error.BadSfnt;
        const subtable = strike.offset + subtable_offset;
        if (subtable + 8 > data.len or subtable + 8 > strike.offset + strike.index_tables_size) return error.BadSfnt;
        const index_format = try bin.readU16At(data, subtable);
        const image_format = try bin.readU16At(data, subtable + 2);
        const image_data_offset = try bin.readU32At(data, subtable + 4);
        if (image_data_offset > std.math.maxInt(usize)) return error.BadSfnt;
        const image_base: usize = @intCast(image_data_offset);
        const local_index: usize = glyph_id - first;
        return switch (index_format) {
            1 => try cblcGlyphLocationFormat1Or3(data, strike, subtable + 8, first, last, local_index, image_format, image_base, 4),
            3 => try cblcGlyphLocationFormat1Or3(data, strike, subtable + 8, first, last, local_index, image_format, image_base, 2),
            4 => try cblcGlyphLocationFormat4(data, strike, subtable + 8, glyph_id, image_format, image_base),
            5 => try cblcGlyphLocationFormat5(data, strike, subtable + 8, glyph_id, image_format, image_base),
            else => null,
        };
    }
    return null;
}

fn cblcGlyphLocationFormat1Or3(data: []const u8, strike: CblcStrike, offsets_offset: usize, first: glyph_mod.GlyphId, last: glyph_mod.GlyphId, local_index: usize, image_format: u16, image_base: usize, offset_size: usize) FontError!?CblcGlyphLocation {
    const glyphs = @as(usize, last - first) + 1;
    const offsets_len = (glyphs + 1) * offset_size;
    if (offsets_offset + offsets_len > data.len or offsets_offset + offsets_len > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const start = try readCblcOffset(data, offsets_offset + local_index * offset_size, offset_size);
    const end = try readCblcOffset(data, offsets_offset + (local_index + 1) * offset_size, offset_size);
    if (end <= start) return null;
    return .{ .image_format = image_format, .offset = image_base + start, .length = end - start };
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
        if (end <= start) return null;
        return .{ .image_format = image_format, .offset = image_base + start, .length = end - start };
    }
    return null;
}

fn cblcGlyphLocationFormat5(data: []const u8, strike: CblcStrike, body_offset: usize, glyph_id: glyph_mod.GlyphId, image_format: u16, image_base: usize) FontError!?CblcGlyphLocation {
    if (body_offset + 16 > data.len or body_offset + 16 > strike.offset + strike.index_tables_size) return error.BadSfnt;
    const image_size = try bin.readU32At(data, body_offset);
    _ = try readBigBitmapMetrics(data, body_offset + 4);
    const glyph_count = try bin.readU32At(data, body_offset + 12);
    const glyphs_offset = body_offset + 16;
    if (glyphs_offset + @as(usize, glyph_count) * 2 > data.len or glyphs_offset + @as(usize, glyph_count) * 2 > strike.offset + strike.index_tables_size) return error.BadSfnt;
    for (0..glyph_count) |index| {
        const current_glyph = try bin.readU16At(data, glyphs_offset + @as(usize, index) * 2);
        if (current_glyph != glyph_id) continue;
        const offset = image_base + @as(usize, index) * image_size;
        return .{ .image_format = image_format, .offset = offset, .length = image_size };
    }
    return null;
}

fn readCblcOffset(data: []const u8, offset: usize, size: usize) FontError!usize {
    return switch (size) {
        2 => try bin.readU16At(data, offset),
        4 => try bin.readU32At(data, offset),
        else => error.BadSfnt,
    };
}

fn cbdtGlyphPng(data: []const u8, cbdt: TableRecord, strike: CblcStrike, location: CblcGlyphLocation) FontError!BitmapGlyphPng {
    if (location.offset > cbdt.length or location.length > cbdt.length - location.offset) return error.BadSfnt;
    const start = cbdt.offset + location.offset;
    const end = start + location.length;
    const slice = data[start..end];
    const metrics_len: usize = switch (location.image_format) {
        17 => 5,
        18 => 8,
        19 => 0,
        else => return error.UnsupportedGlyph,
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
    return bitmapGlyphPngFromData(png, strike.ppem, strike.ppi, metrics.bearing_x, metrics.bearing_y);
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

fn sfntOffset(data: []const u8, face_index: usize) FontError!usize {
    const tag = try bin.readU32At(data, 0);
    if (tag != 0x74746366) return 0; // "ttcf"
    if (try bin.readU32At(data, 4) >> 16 != 1 and try bin.readU32At(data, 4) >> 16 != 2) return error.BadSfnt;
    const face_count = try bin.readU32At(data, 8);
    if (face_index >= face_count) return error.BadSfnt;
    const offset = try bin.readU32At(data, 12 + face_index * 4);
    if (offset >= data.len) return error.BadSfnt;
    return offset;
}

fn parseCmapSubtables(allocator: std.mem.Allocator, data: []const u8, cmap: TableRecord) FontError![]CmapSubtable {
    const count = try bin.readU16At(data, cmap.offset + 2);
    var subtables = std.ArrayList(CmapSubtable).empty;
    errdefer subtables.deinit(allocator);
    for (0..count) |i| {
        const rec = cmap.offset + 4 + i * 8;
        const sub_offset = try bin.readU32At(data, rec + 4);
        if (sub_offset >= cmap.length) return error.BadSfnt;
        const absolute = cmap.offset + sub_offset;
        try subtables.append(allocator, .{
            .platform_id = try bin.readU16At(data, rec),
            .encoding_id = try bin.readU16At(data, rec + 2),
            .offset = absolute,
            .format = try bin.readU16At(data, absolute),
        });
    }
    return try subtables.toOwnedSlice(allocator);
}

fn classDefValue(data: []const u8, offset: usize, glyph_id: glyph_mod.GlyphId) FontError!u16 {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 6 > data.len) return error.BadSfnt;
            const start_glyph = try bin.readU16At(data, offset + 2);
            const glyph_count = try bin.readU16At(data, offset + 4);
            if (glyph_id < start_glyph or glyph_id >= start_glyph + glyph_count) return 0;
            const class_offset = offset + 6 + @as(usize, glyph_id - start_glyph) * 2;
            if (class_offset + 2 > data.len) return error.BadSfnt;
            return try bin.readU16At(data, class_offset);
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
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

const NameRecord = struct {
    platform_id: u16,
    encoding_id: u16,
    language_id: u16,
    name_id: u16,
    offset: usize,
    length: usize,
};

fn readNameString(data: []const u8, name: TableRecord, name_id: u16, out: []u8) FontError!?[]const u8 {
    if (name.length < 6) return error.BadSfnt;
    const format = try bin.readU16At(data, name.offset);
    if (format > 1) return error.InvalidName;
    const count = try bin.readU16At(data, name.offset + 2);
    const storage_offset = try bin.readU16At(data, name.offset + 4);
    if (storage_offset > name.length) return error.BadSfnt;

    var best: ?NameRecord = null;
    for (0..count) |i| {
        const rec = name.offset + 6 + i * 12;
        if (rec + 12 > name.offset + name.length) return error.BadSfnt;
        const record = NameRecord{
            .platform_id = try bin.readU16At(data, rec),
            .encoding_id = try bin.readU16At(data, rec + 2),
            .language_id = try bin.readU16At(data, rec + 4),
            .name_id = try bin.readU16At(data, rec + 6),
            .length = try bin.readU16At(data, rec + 8),
            .offset = try bin.readU16At(data, rec + 10),
        };
        if (record.name_id != name_id) continue;
        if (record.offset > name.length - storage_offset or record.length > name.length - storage_offset - record.offset) return error.BadSfnt;
        if (best == null or scoreNameRecord(record) > scoreNameRecord(best.?)) best = record;
    }

    const chosen = best orelse return null;
    const string_start = name.offset + storage_offset + chosen.offset;
    const string_data = data[string_start .. string_start + chosen.length];
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
    return record.platform_id == 0 or record.platform_id == 3;
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
    if (subtable.format == 12 and subtable.platform_id == 3 and subtable.encoding_id == 10) return 7;
    if (subtable.format == 12 and subtable.platform_id == 0) return 6;
    if (subtable.format == 4 and subtable.platform_id == 3 and subtable.encoding_id == 1) return 5;
    if (subtable.format == 4 and subtable.platform_id == 0) return 4;
    if (subtable.format == 13 and subtable.platform_id == 3 and subtable.encoding_id == 10) return 3;
    if (subtable.format == 13 and subtable.platform_id == 0) return 2;
    if (subtable.format == 6 and (subtable.platform_id == 0 or subtable.platform_id == 3)) return 1;
    if (subtable.format == 0) return 1;
    return 0;
}

fn glyphIndexFormat0(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xff) return 0;
    const length = try bin.readU16At(data, offset + 2);
    if (length < 262) return error.BadSfnt;
    return data[offset + 6 + @as(usize, codepoint)];
}

fn glyphIndexFormat4(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xffff) return 0;
    const seg_count = (try bin.readU16At(data, offset + 6)) / 2;
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
        const glyph = try bin.readU16At(data, glyph_offset);
        if (glyph == 0) return 0;
        return @intCast(@as(u16, @bitCast(@as(i16, @bitCast(glyph)) +% delta)));
    }
    return 0;
}

fn glyphIndexFormat6(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    if (codepoint > 0xffff) return 0;
    const length = try bin.readU16At(data, offset + 2);
    if (length < 10) return error.BadSfnt;
    const first_code = try bin.readU16At(data, offset + 6);
    const entry_count = try bin.readU16At(data, offset + 8);
    if (@as(usize, entry_count) * 2 > @as(usize, length) - 10) return error.BadSfnt;
    const cp: u16 = @intCast(codepoint);
    if (cp < first_code) return 0;
    const index = @as(usize, cp - first_code);
    if (index >= entry_count) return 0;
    return try bin.readU16At(data, offset + 10 + index * 2);
}

fn glyphIndexFormat12(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    // Format 12 groups are sorted by startCharCode. Binary search avoids a
    // linear scan through very large CJK fonts with thousands of ranges.
    const groups = try bin.readU32At(data, offset + 12);
    var lo: usize = 0;
    var hi: usize = groups;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const group_offset = offset + 16 + mid * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
        if (codepoint < start) {
            hi = mid;
        } else if (codepoint > end) {
            lo = mid + 1;
        } else {
            const first = try bin.readU32At(data, group_offset + 8);
            return @intCast(first + codepoint - start);
        }
    }
    return 0;
}

fn glyphIndexFormat13(data: []const u8, offset: usize, codepoint: u21) FontError!glyph_mod.GlyphId {
    // Format 13 shares the segmented 32-bit group layout with format 12, but
    // each group maps every scalar in the range to the same glyph id. This is
    // how last-resort fonts cover huge Unicode ranges without carrying per-code
    // point glyph indices.
    const groups = try bin.readU32At(data, offset + 12);
    var lo: usize = 0;
    var hi: usize = groups;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const group_offset = offset + 16 + mid * 12;
        const start = try bin.readU32At(data, group_offset);
        const end = try bin.readU32At(data, group_offset + 4);
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

fn kernFormat0(data: []const u8, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
    if (data.len < 14) return 0;
    const pair_count = try bin.readU16At(data, 6);
    const needle = (@as(u32, left) << 16) | right;
    var lo: usize = 0;
    var hi: usize = pair_count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const offset = 14 + mid * 6;
        if (offset + 6 > data.len) return error.BadSfnt;
        const pair = (@as(u32, try bin.readU16At(data, offset)) << 16) | try bin.readU16At(data, offset + 2);
        if (needle < pair) {
            hi = mid;
        } else if (needle > pair) {
            lo = mid + 1;
        } else {
            return try bin.readI16At(data, offset + 4);
        }
    }
    return 0;
}

fn appendSimpleGlyph(outline: *glyph_mod.GlyphOutline, data: []const u8, contour_count: u16, transform: Transform) FontError!void {
    if (contour_count == 0) return;
    var r = bin.Reader.init(data);
    _ = try r.readI16();
    try r.skip(8);
    const end_pts = try outline.allocator.alloc(u16, contour_count);
    defer outline.allocator.free(end_pts);
    var total_points: usize = 0;
    for (end_pts) |*end| {
        end.* = try r.readU16();
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

fn readColorPaint(data: []const u8, colr: TableRecord, offset: usize) FontError!ColorPaint {
    if (offset + 5 > colr.offset + colr.length) return error.BadSfnt;
    const format = data[offset];
    return switch (format) {
        2 => .{ .solid = .{
            .palette_index = try bin.readU16At(data, offset + 1),
            .alpha = f2dot14(try bin.readI16At(data, offset + 3)),
        } },
        1 => blk: {
            if (offset + 6 > colr.offset + colr.length) return error.BadSfnt;
            break :blk .{ .layers = .{
                .layer_count = data[offset + 1],
                .first_layer_index = try bin.readU32At(data, offset + 2),
            } };
        },
        10 => blk: {
            if (offset + 6 > colr.offset + colr.length) return error.BadSfnt;
            const child_offset = try readU24At(data, offset + 1);
            const glyph_id = try bin.readU16At(data, offset + 4);
            if (child_offset > colr.offset + colr.length - offset) return error.BadSfnt;
            const child = try readColorPaint(data, colr, offset + child_offset);
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
