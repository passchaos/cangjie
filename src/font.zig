const std = @import("std");
const aat_mort = @import("aat_mort.zig");
const aat_morx = @import("aat_morx.zig");
const aat_kerx = @import("aat_kerx.zig");
const vort = @import("vort");
const ankr_mod = @import("opentype/ankr.zig");
const base_mod = @import("opentype/base.zig");
const bin = @import("binary.zig");
const cff_mod = @import("cff.zig");
const cff2_mod = @import("opentype/cff2.zig");
const cvar_mod = @import("opentype/cvar.zig");
const glyph_mod = @import("glyph.zig");
const gvar_mod = @import("opentype/gvar.zig");
const gpos_mod = @import("gpos.zig");
const gsub_mod = @import("gsub.zig");
const feat_mod = @import("opentype/feat.zig");
const gasp_mod = @import("opentype/gasp.zig");
const cmap_iter = @import("opentype/cmap_iter.zig");
const cmap_variation = @import("opentype/cmap_variation.zig");
const ift_mod = @import("opentype/ift.zig");
const kerx_mod = @import("opentype/kerx.zig");
const ltag_mod = @import("opentype/ltag.zig");
const math_mod = @import("opentype/math.zig");
const meta_mod = @import("opentype/meta.zig");
const metric_variation_mod = @import("opentype/metric_variation.zig");
const variation_common = @import("opentype/variation/root.zig");
const delta_map = variation_common.delta_set_index_map;
const item_store = variation_common.item_store;
const macintosh_encoding = @import("opentype/macintosh_encoding.zig");
const mvar_mod = @import("opentype/mvar.zig");
const morx_mod = @import("opentype/morx.zig");
const name_mod = @import("opentype/name.zig");
const ot_layout = @import("opentype/layout.zig");
const trak_mod = @import("opentype/trak.zig");
const tt_program_mod = @import("opentype/tt_program.zig");
const sfnt = @import("font/sfnt/root.zig");
const bitmap_mod = @import("font/tables/bitmap/root.zig");
const color_tables = @import("font/tables/color/root.zig");
const colr_v0_mod = color_tables.colr_v0;
const colr_v1_mod = color_tables.colr_v1;
const colr_paint = colr_v1_mod.paint;
const colr_bases = colr_v1_mod.bases;
const colr_glyphs = colr_v1_mod.validation.glyphs;
const colr_layers = colr_v1_mod.layers;
const colr_palette = colr_v1_mod.validation.palette;
const colr_read = colr_v1_mod.read;
const colr_variation = colr_v1_mod.variation;
const cpal_mod = color_tables.cpal;
const svg_mod = @import("font/tables/svg/root.zig");
const shaping_sections = @import("shaping_sections.zig");
const unicode_mod = @import("unicode.zig");
const varc_mod = @import("opentype/varc.zig");

/// Errors intentionally preserve the table family that failed. Callers such as
/// render bridges can distinguish malformed SFNT data from unsupported outline
/// formats or unsupported shaping subtables without losing allocator failures.
pub const FontError = error{
    BadSfnt,
    MissingTable,
    UnsupportedCmap,
    UnsupportedGlyph,
    UnsupportedCff,
    InvalidCodepoint,
    InvalidGlyph,
    InvalidLoca,
    InvalidMetrics,
    InvalidBitmapSize,
    CompoundDepthExceeded,
    InvalidName,
} || cff_mod.CffError || gpos_mod.GposError || gsub_mod.GsubError || std.mem.Allocator.Error || error{EndOfStream};

pub const FontFormat = enum {
    truetype,
    opentype_cff,
};

pub const Cff2Info = cff2_mod.Info;
pub const Cff2FontDictInfo = cff2_mod.FontDictInfo;
pub const Cff2PrivateDictInfo = cff2_mod.PrivateDictInfo;
const CffParsedInfo = cff_mod.Parsed;
pub const Cff2CharStringScanInfo = cff2_mod.CharStringScanInfo;
pub const Cff2CharStringBoundsInfo = cff2_mod.CharStringBoundsInfo;
pub const GvarInfo = gvar_mod.Info;
pub const GvarGlyphInfo = gvar_mod.GlyphInfo;
pub const GvarTupleInfo = gvar_mod.TupleInfo;
pub const GvarScaledPointDelta = gvar_mod.ScaledPointDelta;
pub const GvarPhantomPointDeltas = gvar_mod.PhantomPointDeltas;
pub const MathConstant = math_mod.Constant;
pub const MathInfo = math_mod.Info;
pub const MathConstantsInfo = math_mod.Constants;
pub const MathValueRecordInfo = math_mod.ValueRecord;
pub const MathGlyphValueRecordInfo = math_mod.GlyphValueRecord;
pub const MathVariantRecordInfo = math_mod.VariantRecord;
pub const MathPartRecordInfo = math_mod.PartRecord;
pub const MathAssemblyInfo = math_mod.Assembly;
pub const MathConstructionInfo = math_mod.Construction;
pub const MathKernInfo = math_mod.MathKernInfo;
pub const MathKernRecordInfo = math_mod.MathKernRecord;
pub const MathKernTableInfo = math_mod.MathKern;
pub const MathKernCorner = math_mod.KernCorner;

pub const CvarInfo = cvar_mod.Info;
pub const CvarTupleInfo = cvar_mod.TupleInfo;
pub const TrueTypeProgramInfo = tt_program_mod.Info;
pub const TrueTypeProgramInstructionInfo = tt_program_mod.Instruction;
pub const TrueTypeProgramKind = tt_program_mod.Kind;
pub const VarcInfo = varc_mod.Info;

pub const FontTableInfo = struct {
    tag: [4]u8,
    checksum: u32,
    offset: usize,
    length: usize,
};

pub const FontHeaderInfo = struct {
    table_version: u32,
    font_revision: f32,
    flags: u16,
    units_per_em: u16,
    created: i64,
    modified: i64,
    bounds: glyph_mod.Bounds,
    mac_style: u16,
    lowest_rec_ppem: u16,
    font_direction_hint: i16,
    index_to_loc_format: i16,
    glyph_data_format: i16,
};

pub const MaxProfileInfo = struct {
    version: u32,
    glyph_count: u16,
    max_points: ?u16 = null,
    max_contours: ?u16 = null,
    max_composite_points: ?u16 = null,
    max_composite_contours: ?u16 = null,
    max_zones: ?u16 = null,
    max_twilight_points: ?u16 = null,
    max_storage: ?u16 = null,
    max_function_defs: ?u16 = null,
    max_instruction_defs: ?u16 = null,
    max_stack_elements: ?u16 = null,
    max_size_of_instructions: ?u16 = null,
    max_component_elements: ?u16 = null,
    max_component_depth: ?u16 = null,
};

pub const MetricHeaderInfo = struct {
    version: u32,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    advance_max: u16,
    min_side_bearing: i16,
    min_opposite_side_bearing: i16,
    max_extent: i16,
    caret_slope_rise: i16,
    caret_slope_run: i16,
    caret_offset: i16,
    metric_data_format: i16,
    long_metric_count: u16,
};

pub const HorizontalMetricInfo = struct {
    advance_width: u16,
    left_side_bearing: i16,
};

pub const IftPatchMapInfo = ift_mod.Info;
pub const IftTableKeyedPatchInfo = ift_mod.TableKeyedPatchInfo;
pub const IftGlyphKeyedPatchInfo = ift_mod.GlyphKeyedPatchInfo;

pub const HdmxRecord = struct {
    ppem: u8,
    max_width: u8,
    widths: []u8,
};

pub const HdmxInfo = struct {
    version: u16,
    record_size: u32,
    records: []HdmxRecord,
};

pub const LtshInfo = struct {
    version: u16,
    thresholds: []u8,
};

pub const VerticalMetricInfo = struct {
    advance_height: u16,
    top_side_bearing: i16,
};

pub const VerticalOriginMetric = struct {
    glyph_id: glyph_mod.GlyphId,
    origin_y: i16,
};

pub const VerticalOriginInfo = struct {
    default_origin_y: i16,
    metrics: []VerticalOriginMetric,
};

pub const GlyphLocationInfo = struct {
    glyph_id: glyph_mod.GlyphId,
    offset: usize,
    length: usize,
    empty: bool,
};

pub const PostInfo = struct {
    format: u32,
    italic_angle: f32,
    underline_position: i16,
    underline_thickness: i16,
    is_fixed_pitch: bool,
    min_mem_type42: u32,
    max_mem_type42: u32,
    min_mem_type1: u32,
    max_mem_type1: u32,
    glyph_name_count: ?u16 = null,
};

pub const PcltInfo = struct {
    version: u32,
    font_number: u32,
    pitch: u16,
    x_height: u16,
    style: u16,
    type_family: u16,
    cap_height: u16,
    symbol_set: u16,
    typeface: [16]u8,
    character_complement: [8]u8,
    file_name: [6]u8,
    stroke_weight: i8,
    width_type: i8,
    serif_style: u8,
};

pub const DsigSignatureInfo = struct {
    format: u32,
    offset: usize,
    length: usize,
    signature: []const u8,
};

pub const DsigInfo = struct {
    version: u32,
    flags: u16,
    signatures: []DsigSignatureInfo,
};

pub const MetaRecordInfo = meta_mod.Record;

pub const HvarInfo = metric_variation_mod.HvarInfo;
pub const MetricVariationIndexMapEntryInfo = metric_variation_mod.IndexMapEntry;
pub const MetricVariationIndexMapInfo = metric_variation_mod.IndexMap;
pub const MvarInfo = mvar_mod.Info;
pub const MvarValueRecordInfo = mvar_mod.ValueRecord;
pub const VvarInfo = metric_variation_mod.VvarInfo;

pub const LtagRecordInfo = ltag_mod.Record;

pub const FeatureNameInfo = feat_mod.Feature;
pub const FeatureSettingInfo = feat_mod.Setting;

pub const TrackInfo = trak_mod.Track;
pub const TrackTableInfo = trak_mod.Info;
pub const TrackValueInfo = trak_mod.TrackValue;

pub const AnkrAnchorInfo = ankr_mod.Anchor;
pub const AnkrGlyphAnchorsInfo = ankr_mod.GlyphAnchors;
pub const AnkrInfo = ankr_mod.Info;

pub const BaseAxisInfo = base_mod.Axis;
pub const BaseInfo = base_mod.Info;
pub const BaseScriptInfo = base_mod.Script;

pub const GaspRange = gasp_mod.Range;
pub const GaspInfo = gasp_mod.Info;

pub const KerxInfo = kerx_mod.Info;
pub const KerxPairInfo = kerx_mod.Pair;
pub const KerxSubtableInfo = kerx_mod.Subtable;
pub const MorxChainInfo = morx_mod.Chain;
pub const MorxFeatureInfo = morx_mod.Feature;
pub const MorxInfo = morx_mod.Info;
pub const MorxSubtableInfo = morx_mod.Subtable;

pub const KernTableDialect = enum {
    legacy,
    apple,
    unsupported,
};

pub const KernSubtableInfo = struct {
    offset: usize,
    length: usize,
    format: u16,
    coverage: u16,
    horizontal: bool,
    minimum: bool,
    cross_stream: bool,
    variation: bool = false,
    override: bool = false,
    tuple_index: ?u16 = null,
    pair_count: ?u16 = null,
};

pub const KernInfo = struct {
    dialect: KernTableDialect,
    version: u32,
    subtables: []KernSubtableInfo,
};

pub const CharmapInfo = struct {
    platform_id: u16,
    encoding_id: u16,
    format: u16,
    offset: usize,
    length: usize,
    /// Format 0/2/4/6 use a 16-bit language field; formats 8/10/12/13 use
    /// a 32-bit field. Format 14 and any future language-less formats report
    /// null rather than inventing a platform-specific value.
    language: ?u32 = null,
};

pub const CharmapMapping = cmap_iter.Mapping;

pub const NameId = name_mod.NameId;
pub const NameEncoding = name_mod.Encoding;
pub const NameLanguageTagInfo = name_mod.LanguageTagInfo;
pub const NameRecordInfo = name_mod.RecordInfo;

pub const StyleAttributes = struct {
    weight: u16 = 400,
    width: u16 = 5,
    italic: bool = false,
    bold: bool = false,
};

pub const Os2Info = struct {
    version: u16,
    x_avg_char_width: i16,
    weight_class: u16,
    width_class: u16,
    fs_type: u16,
    subscript_x_size: i16,
    subscript_y_size: i16,
    subscript_x_offset: i16,
    subscript_y_offset: i16,
    superscript_x_size: i16,
    superscript_y_size: i16,
    superscript_x_offset: i16,
    superscript_y_offset: i16,
    strikeout_size: i16,
    strikeout_position: i16,
    family_class: i16,
    panose: [10]u8,
    unicode_ranges: [4]u32,
    vendor_id: [4]u8,
    selection: u16,
    first_char_index: u16,
    last_char_index: u16,
    typo_ascender: i16,
    typo_descender: i16,
    typo_line_gap: i16,
    win_ascent: u16,
    win_descent: u16,
    code_page_ranges: ?[2]u32 = null,
    x_height: ?i16 = null,
    cap_height: ?i16 = null,
    default_char: ?u16 = null,
    break_char: ?u16 = null,
    max_context: ?u16 = null,
    lower_optical_point_size: ?u16 = null,
    upper_optical_point_size: ?u16 = null,
};

pub const FontDecorationMetricSource = enum {
    font,
    fallback,
};

pub const ScaledFontDecorationMetrics = struct {
    underline_position: f32,
    underline_thickness: f32,
    strikeout_position: f32,
    strikeout_thickness: f32,
};

pub const ScaledFontScriptMetrics = struct {
    superscript_x_size: f32,
    superscript_y_size: f32,
    superscript_x_offset: f32,
    superscript_y_offset: f32,
    subscript_x_size: f32,
    subscript_y_size: f32,
    subscript_x_offset: f32,
    subscript_y_offset: f32,
};

pub const FontScriptMetrics = struct {
    superscript_x_size: i16,
    superscript_y_size: i16,
    superscript_x_offset: i16,
    superscript_y_offset: i16,
    subscript_x_size: i16,
    subscript_y_size: i16,
    subscript_x_offset: i16,
    subscript_y_offset: i16,

    pub fn scale(self: FontScriptMetrics, font_size: f32, units_per_em: u16) ScaledFontScriptMetrics {
        const units = @max(@as(f32, @floatFromInt(units_per_em)), 1.0);
        const factor = font_size / units;
        return .{
            .superscript_x_size = @as(f32, @floatFromInt(self.superscript_x_size)) * factor,
            .superscript_y_size = @as(f32, @floatFromInt(self.superscript_y_size)) * factor,
            .superscript_x_offset = @as(f32, @floatFromInt(self.superscript_x_offset)) * factor,
            .superscript_y_offset = @as(f32, @floatFromInt(self.superscript_y_offset)) * factor,
            .subscript_x_size = @as(f32, @floatFromInt(self.subscript_x_size)) * factor,
            .subscript_y_size = @as(f32, @floatFromInt(self.subscript_y_size)) * factor,
            .subscript_x_offset = @as(f32, @floatFromInt(self.subscript_x_offset)) * factor,
            .subscript_y_offset = @as(f32, @floatFromInt(self.subscript_y_offset)) * factor,
        };
    }
};

pub const FontDecorationMetrics = struct {
    underline_position: i16,
    underline_thickness: i16,
    strikeout_position: i16,
    strikeout_thickness: i16,
    underline_source: FontDecorationMetricSource = .fallback,
    strikeout_source: FontDecorationMetricSource = .fallback,

    pub fn scale(self: FontDecorationMetrics, font_size: f32, units_per_em: u16) ScaledFontDecorationMetrics {
        const units = @max(@as(f32, @floatFromInt(units_per_em)), 1.0);
        const factor = font_size / units;
        return .{
            .underline_position = @as(f32, @floatFromInt(self.underline_position)) * factor,
            .underline_thickness = @max(0.5, @as(f32, @floatFromInt(self.underline_thickness)) * factor),
            .strikeout_position = @as(f32, @floatFromInt(self.strikeout_position)) * factor,
            .strikeout_thickness = @max(0.5, @as(f32, @floatFromInt(self.strikeout_thickness)) * factor),
        };
    }
};

pub const VerticalMetrics = struct {
    advance_height: u16,
    top_side_bearing: i16,
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

pub const VariationSequenceKind = cmap_variation.SequenceKind;

pub const VariationInstance = struct {
    subfamily_name_id: u16,
    flags: u16,
    postscript_name_id: ?u16 = null,
    coordinates: []VariationCoordinate,
};

pub const StatDesignAxis = struct {
    tag: [4]u8,
    name_id: u16,
    ordering: u16,
};

pub const StatAxisValue = struct {
    format: u16,
    flags: u16,
    name_id: u16,
    axis_index: ?u16 = null,
    value: ?f32 = null,
    linked_value: ?f32 = null,
    nominal_value: ?f32 = null,
    range_min_value: ?f32 = null,
    range_max_value: ?f32 = null,
    coordinates: []StatAxisValueCoordinate = &.{},
};

pub const StatAxisValueCoordinate = struct {
    axis_index: u16,
    value: f32,
};

pub const ColorLayer = colr_v0_mod.Layer;

// Preserve the established public color metadata surface while CPAL parsing
// lives in the focused modern color-table module.
pub const PaletteColor = cpal_mod.Color;
pub const PaletteInfo = cpal_mod.Palette;

// Keep the public color model stable while COLR parsers and renderers share a
// focused type layer that does not depend on the Font implementation.
pub const ColorClipBox = color_tables.model.ClipBox;
pub const ColorAffine = color_tables.model.Affine;
pub const ColorPaint = color_tables.model.Paint;

pub const SvgGlyphDocument = svg_mod.Document;
pub const ResolvedSvgGlyphDocument = svg_mod.ResolvedDocument;

// Preserve the established public type identities while their implementation
// and table grammar live in the focused embedded-bitmap module.
pub const BitmapGlyphPng = bitmap_mod.GlyphPng;
pub const BitmapGlyphInfo = bitmap_mod.GlyphInfo;
pub const BitmapStrikeSource = bitmap_mod.StrikeSource;
pub const BitmapStrikeInfo = bitmap_mod.StrikeInfo;

pub const GlyphClass = enum(u16) {
    unclassified = 0,
    base = 1,
    ligature = 2,
    mark = 3,
    component = 4,
    _,
};

const TableRecord = sfnt.Record;

fn svgTable(record: TableRecord) svg_mod.Table {
    return .{ .offset = record.offset, .length = record.length };
}

fn bitmapTable(record: TableRecord) bitmap_mod.Table {
    return .{ .offset = record.offset, .length = record.length };
}

fn cpalTable(record: TableRecord) cpal_mod.Table {
    return .{ .offset = record.offset, .length = record.length };
}

fn colrV0Table(record: TableRecord) colr_v0_mod.Table {
    return .{ .offset = record.offset, .length = record.length };
}

fn colrV1Table(record: TableRecord) colr_v1_mod.Table {
    return .{ .offset = record.offset, .length = record.length };
}

fn variationTable(record: TableRecord) item_store.Table {
    return .{ .offset = record.offset, .length = record.length };
}

const NameIdIndex = name_mod.NameIdIndex;

fn nameTableView(record: TableRecord) name_mod.Table {
    return .{ .offset = record.offset, .length = record.length };
}

fn validateNameTable(data: []const u8, name: TableRecord) FontError!void {
    return try name_mod.validate(data, nameTableView(name));
}

fn readNameIdIndex(data: []const u8, name: TableRecord) FontError!NameIdIndex {
    return try name_mod.idIndex(data, nameTableView(name));
}

fn validateNameIdReference(name_index: ?*const NameIdIndex, name_id: u16) FontError!void {
    return try name_mod.validateIdReference(name_index, name_id);
}

fn validateOptionalNameIdReference(name_index: ?*const NameIdIndex, name_id: u16) FontError!void {
    return try name_mod.validateOptionalIdReference(name_index, name_id);
}

fn readNameString(data: []const u8, name: TableRecord, name_id: u16, out: []u8) FontError!?[]const u8 {
    return try name_mod.readString(data, nameTableView(name), name_id, out);
}

const CmapSubtable = struct {
    platform_id: u16,
    encoding_id: u16,
    offset: usize,
    length: usize,
    format: u16,
};

pub const GdefLookupMetadata = struct {
    glyph_classes: ?[]u16 = null,
    mark_attach_classes: ?[]u16 = null,
    mark_filtering_sets: ?[][]glyph_mod.GlyphId = null,
    variation_store_data: ?[]u8 = null,
    variation_store: ?gpos_mod.VariationStore = null,

    pub fn deinit(self: *GdefLookupMetadata, allocator: std.mem.Allocator) void {
        if (self.glyph_classes) |classes| allocator.free(classes);
        if (self.mark_attach_classes) |classes| allocator.free(classes);
        if (self.mark_filtering_sets) |sets| freeMarkFilteringSets(allocator, sets);
        if (self.variation_store_data) |data| allocator.free(data);
        self.* = .{};
    }

    pub fn glyphClass(self: GdefLookupMetadata, glyph_id: glyph_mod.GlyphId) GlyphClass {
        const classes = self.glyph_classes orelse return .unclassified;
        const index: usize = glyph_id;
        if (index >= classes.len) return .unclassified;
        return std.enums.fromInt(GlyphClass, classes[index]) orelse .unclassified;
    }

    fn applyToGsubOptions(self: GdefLookupMetadata, options: *gsub_mod.LookupOptions) void {
        if (self.glyph_classes) |classes| options.glyph_classes = classes;
        if (self.mark_attach_classes) |classes| options.mark_attach_classes = classes;
        if (self.mark_filtering_sets) |sets| options.mark_filtering_sets = sets;
    }

    fn applyToGposOptions(self: GdefLookupMetadata, options: *gpos_mod.LookupOptions) void {
        if (self.glyph_classes) |classes| options.glyph_classes = classes;
        if (self.mark_attach_classes) |classes| options.mark_attach_classes = classes;
        if (self.mark_filtering_sets) |sets| options.mark_filtering_sets = sets;
        if (self.variation_store) |store| options.gdef_variation_store = store;
    }
};

/// Font-dependent OpenType ScriptList selection used by the shaping planner.
///
/// This type belongs to the internal font/shaping boundary rather than to the
/// public face surface. Applications select script and language through
/// `shaping.Options`; they do not execute layout-table planning themselves.
pub const LayoutScriptSelection = struct {
    tag: ?unicode_mod.OpenTypeScriptTag = null,
    requested: bool = false,
};

pub const KernLookupForShaping = struct {
    font: *const Font,
    kern: ?TableRecord,

    pub fn kerning(self: KernLookupForShaping, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        if (left >= self.font.glyph_count or right >= self.font.glyph_count) return error.InvalidGlyph;
        const kern = self.kern orelse return 0;
        if (kern.length < 4) return 0;
        const version = try bin.readU32At(self.font.data, kern.offset);
        if (version == 0x00010000) {
            return try Font.appleKernKerning(self.font.data, kern, left, right);
        }
        if ((version >> 16) != 0) return 0;
        return try Font.legacyKernKerning(self.font.data, kern, left, right);
    }
};

pub const KerxLookupForShaping = struct {
    font: *const Font,
    kerx: TableRecord,

    pub fn kerning(
        self: KerxLookupForShaping,
        left: glyph_mod.GlyphId,
        right: glyph_mod.GlyphId,
        vertical: bool,
        normalized_coords: []const f32,
    ) FontError!i32 {
        if (left >= self.font.glyph_count or right >= self.font.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        var tuple_context = KerxTupleResolverContext{
            .font = self.font,
            .normalized_coords = normalized_coords,
        };
        return try kerx_mod.pairKerning(
            self.font.data,
            self.kerx.offset,
            self.kerx.length,
            self.font.glyph_count,
            left,
            right,
            vertical,
            .{
                .context = &tuple_context,
                .resolve_fn = resolveKerxTupleVector,
            },
        );
    }

    pub fn collectOrderedAdjustments(
        self: KerxLookupForShaping,
        glyphs: []const glyph_mod.GlyphId,
        adjustments: *std.ArrayList(aat_kerx.Adjustment),
        allocator: std.mem.Allocator,
        vertical: bool,
        direction_backward: bool,
        requested_kerning: bool,
        simple_pair_eligible: []const bool,
        normalized_coords: []const f32,
    ) FontError!aat_kerx.Summary {
        try self.font.validateGlyphRun(glyphs);
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        var resolver_context = KerxOutlineResolverContext{
            .font = self.font,
            .allocator = allocator,
            .normalized_coords = normalized_coords,
        };
        var tuple_context = KerxTupleResolverContext{
            .font = self.font,
            .normalized_coords = normalized_coords,
        };
        return try aat_kerx.collectAdjustments(
            self.font.data,
            self.kerx.offset,
            self.kerx.length,
            self.font.glyph_count,
            glyphs,
            adjustments,
            allocator,
            vertical,
            direction_backward,
            requested_kerning,
            simple_pair_eligible,
            if (self.font.ankr) |table| .{ .offset = table.offset, .length = table.length } else null,
            .{
                .context = &resolver_context,
                .resolve_fn = resolveKerxOutlinePoint,
            },
            .{
                .context = &tuple_context,
                .resolve_fn = resolveKerxTupleVector,
            },
        );
    }

    pub fn hasOutputSideAdjustments(
        self: KerxLookupForShaping,
        vertical: bool,
        requested_kerning: bool,
    ) FontError!bool {
        return try kerx_mod.hasOutputSideAdjustments(
            self.font.data,
            self.kerx.offset,
            self.kerx.length,
            vertical,
            requested_kerning,
        );
    }

    pub fn anchorForShaping(self: KerxLookupForShaping, glyph_id: glyph_mod.GlyphId, anchor_index: usize) FontError!ankr_mod.Anchor {
        if (glyph_id >= self.font.glyph_count) return error.InvalidGlyph;
        const ankr = self.font.ankr orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.font.data, ankr);
        return try ankr_mod.anchor(
            self.font.data,
            ankr.offset,
            ankr.length,
            self.font.glyph_count,
            glyph_id,
            anchor_index,
        );
    }
};

const KerxOutlineResolverContext = struct {
    font: *const Font,
    allocator: std.mem.Allocator,
    normalized_coords: []const f32,
};

const KerxTupleResolverContext = struct {
    font: *const Font,
    normalized_coords: []const f32,
};

fn resolveKerxTupleVector(
    opaque_context: *const anyopaque,
    vector: []const u8,
) kerx_mod.Error!i32 {
    const context: *const KerxTupleResolverContext = @ptrCast(@alignCast(opaque_context));
    if (vector.len == 2) return std.mem.readInt(i16, vector[0..2], .big);
    const gvar = context.font.gvar orelse return error.BadSfnt;
    const axis_count = context.font.fvar_axis_count orelse return error.BadSfnt;
    return gvar_mod.sharedTupleVectorValue(
        context.font.data,
        gvar.offset,
        gvar.length,
        context.font.glyph_count,
        axis_count,
        vector,
        context.normalized_coords,
    ) catch |err| switch (err) {
        else => return error.BadSfnt,
    };
}

fn resolveKerxOutlinePoint(
    opaque_context: *const anyopaque,
    glyph_id: glyph_mod.GlyphId,
    point_index: u16,
) aat_kerx.Error!?aat_kerx.OutlinePoint {
    const context: *const KerxOutlineResolverContext = @ptrCast(@alignCast(opaque_context));
    const point = context.font.glyphContourPointForShaping(
        context.allocator,
        glyph_id,
        point_index,
        context.normalized_coords,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.BadSfnt,
    };
    return if (point) |value| .{
        .x = roundedGlyphPosition(value.x),
        .y = roundedGlyphPosition(value.y),
    } else null;
}

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
    hhea: ?TableRecord,
    maxp: TableRecord,
    hmtx: ?TableRecord,
    hdmx: ?TableRecord,
    ltsh: ?TableRecord,
    ltag: ?TableRecord,
    loca: ?TableRecord,
    cmap: TableRecord,
    kern: ?TableRecord,
    kerx: ?TableRecord,
    mort: ?TableRecord,
    morx: ?TableRecord,
    os2: ?TableRecord,
    gasp: ?TableRecord,
    gdef: ?TableRecord,
    gpos: ?TableRecord,
    gsub: ?TableRecord,
    ankr: ?TableRecord,
    feat: ?TableRecord,
    trak: ?TableRecord,
    name: ?TableRecord,
    math: ?TableRecord,
    meta: ?TableRecord,
    post: ?TableRecord,
    pclt: ?TableRecord,
    stat: ?TableRecord,
    fvar: ?TableRecord,
    /// Cached parse-time fvar axis count for variation hot paths that already
    /// trust Font.parse. Public metadata APIs still revalidate fvar before
    /// reading mutable borrowed bytes.
    fvar_axis_count: ?u16 = null,
    avar: ?TableRecord,
    cvt: ?TableRecord,
    cvar: ?TableRecord,
    gvar: ?TableRecord,
    fpgm: ?TableRecord,
    prep: ?TableRecord,
    hvar: ?TableRecord,
    mvar: ?TableRecord,
    vvar: ?TableRecord,
    varc: ?TableRecord,
    ift: ?TableRecord,
    iftx: ?TableRecord,
    colr: ?TableRecord,
    cpal: ?TableRecord,
    base: ?TableRecord,
    dsig: ?TableRecord,
    vorg: ?TableRecord,
    svg: ?TableRecord,
    sbix: ?TableRecord,
    cblc: ?TableRecord,
    cbdt: ?TableRecord,
    eblc: ?TableRecord,
    ebdt: ?TableRecord,
    glyf: ?TableRecord,
    cff: ?TableRecord,
    cff_parsed: ?CffParsedInfo,
    cff2: ?TableRecord,
    cmap_subtables: []CmapSubtable,
    owned_tables: []TableRecord,
    allocator: std.mem.Allocator,

    const OutlineReadMode = enum {
        /// Public outline APIs re-check borrowed table bytes before returning data.
        revalidate,
        /// Raster hot paths trust the grammar and checksums established by Font.parse.
        parsed,

        fn shouldRevalidate(self: OutlineReadMode) bool {
            return self == .revalidate;
        }
    };

    /// Parse the first face of a standalone SFNT or TrueType Collection.
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) FontError!Font {
        return parseFace(allocator, data, 0);
    }

    pub fn faceCount(data: []const u8) FontError!usize {
        const header = (try sfnt.collection.parse(data)) orelse return 1;
        return header.face_count;
    }

    /// Parse a single face from either a plain SFNT file or a TTC.
    ///
    /// TTC face offsets are absolute from the start of the collection, while
    /// SFNT table records are absolute from the start of the font file. Keeping
    /// both as absolute offsets lets the rest of the parser use one addressing
    /// model for TTF, OTF/CFF, and TTC-backed faces.
    pub fn parseFace(allocator: std.mem.Allocator, data: []const u8, face_index: usize) FontError!Font {
        const collection = try sfnt.collection.parse(data);
        const start = if (collection) |header|
            try sfnt.collection.faceOffset(data, header, face_index)
        else if (face_index == 0)
            0
        else
            return error.BadSfnt;
        if (start >= data.len) return error.BadSfnt;
        var r = bin.Reader.init(data);
        try r.seek(start);
        const scaler = try r.readU32();
        const declared_format: FontFormat = switch (scaler) {
            0x00010000, 0x74727565 => .truetype,
            0x4f54544f => .opentype_cff,
            else => return error.BadSfnt,
        };
        const num_tables = try r.readU16();
        const search_range = try r.readU16();
        const entry_selector = try r.readU16();
        const range_shift = try r.readU16();
        try sfnt.validateSearchParameters(num_tables, search_range, entry_selector, range_shift);
        const directory_end = try sfnt.directoryEnd(
            data.len,
            start,
            num_tables,
        );
        const ttc_header = collection;
        const is_ttc_face = ttc_header != null;
        const reserved_prefix_end = if (ttc_header) |header| header.header_length else 0;

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
        try sfnt.validateDirectory(records);
        try sfnt.validateRanges(
            records,
            reserved_prefix_end,
            .{ .start = start, .end = directory_end },
        );
        try sfnt.validatePadding(data, records);
        if (ttc_header) |header| if (header.dsig_range) |dsig| {
            try sfnt.validateDisjoint(records, .{
                .start = dsig.start,
                .end = dsig.end,
            });
        };

        const head = sfnt.find(records, "head") orelse return error.MissingTable;
        const hhea = sfnt.find(records, "hhea");
        const maxp = sfnt.find(records, "maxp") orelse return error.MissingTable;
        const hmtx = sfnt.find(records, "hmtx");
        const hdmx = sfnt.find(records, "hdmx");
        const ltsh = sfnt.find(records, "LTSH");
        const ltag = sfnt.find(records, "ltag");
        const loca = sfnt.find(records, "loca");
        const cmap = sfnt.find(records, "cmap") orelse return error.MissingTable;
        const kern = sfnt.find(records, "kern");
        const kerx = sfnt.find(records, "kerx");
        const mort = sfnt.find(records, "mort");
        const morx = sfnt.find(records, "morx");
        const os2 = sfnt.find(records, "OS/2");
        const gasp = sfnt.find(records, "gasp");
        const gdef = sfnt.find(records, "GDEF");
        const gpos = sfnt.find(records, "GPOS");
        const gsub = sfnt.find(records, "GSUB");
        const ankr = sfnt.find(records, "ankr");
        const feat = sfnt.find(records, "feat");
        const trak = sfnt.find(records, "trak");
        const name = sfnt.find(records, "name");
        const math = sfnt.find(records, "MATH");
        const meta = sfnt.find(records, "meta");
        const post = sfnt.find(records, "post");
        const pclt = sfnt.find(records, "PCLT");
        const stat = sfnt.find(records, "STAT");
        const fvar = sfnt.find(records, "fvar");
        const avar = sfnt.find(records, "avar");
        const cvt = sfnt.find(records, "cvt ");
        const cvar = sfnt.find(records, "cvar");
        const fpgm = sfnt.find(records, "fpgm");
        const prep = sfnt.find(records, "prep");
        const colr = sfnt.find(records, "COLR");
        const cpal = sfnt.find(records, "CPAL");
        const base = sfnt.find(records, "BASE");
        const dsig = sfnt.find(records, "DSIG");
        const vorg = sfnt.find(records, "VORG");
        const svg = sfnt.find(records, "SVG ");
        const sbix = sfnt.find(records, "sbix");
        const cblc = sfnt.find(records, "CBLC");
        const cbdt = sfnt.find(records, "CBDT");
        const eblc = sfnt.find(records, "EBLC");
        const ebdt = sfnt.find(records, "EBDT");
        const glyf = sfnt.find(records, "glyf");
        const cff = sfnt.find(records, "CFF ");
        const cff2 = sfnt.find(records, "CFF2");
        const vhea = sfnt.find(records, "vhea");
        const vmtx = sfnt.find(records, "vmtx");
        const gvar = sfnt.find(records, "gvar");
        const hvar = sfnt.find(records, "HVAR");
        const mvar = sfnt.find(records, "MVAR");
        const vvar = sfnt.find(records, "VVAR");
        const varc = sfnt.find(records, "VARC");
        const ift = sfnt.find(records, "IFT ");
        const iftx = sfnt.find(records, "IFTX");

        if (morx == null and mort == null and range_shift != try sfnt.expectedRangeShift(num_tables)) return error.BadSfnt;

        const has_horizontal_metrics = hhea != null and hmtx != null;
        if ((hhea == null) != (hmtx == null)) return error.MissingTable;
        const has_glyf_outlines = glyf != null and loca != null;
        const has_embedded_bitmaps = sbix != null or (cblc != null and cbdt != null);
        const has_layout_tables = gsub != null or gpos != null;
        const format = try selectOutlineFormat(
            data,
            maxp,
            declared_format,
            has_glyf_outlines,
            cff != null or cff2 != null,
        );
        if (format == .truetype) {
            // TrueType outlines are a glyf/loca pair; accepting only one table
            // leaves every glyph boundary ambiguous for outline reads. HarfBuzz
            // in-house shaping subsets may keep layout/cmap data plus a leftover
            // loca while omitting glyf entirely; accept those for shaping and let
            // outline APIs report MissingTable when glyph geometry is requested.
            if (!has_glyf_outlines and !has_embedded_bitmaps and !has_layout_tables) return error.MissingTable;
        }
        if (format == .opentype_cff and cff == null and cff2 == null and !has_embedded_bitmaps and !has_layout_tables) return error.MissingTable;

        // The offsets in the directory have already been checked against the
        // whole SFNT byte slice. These minimum sizes deliberately check the
        // *declared table records* before reading cross-table fields below, so
        // a truncated head/hhea/maxp table cannot borrow bytes from the next
        // physical table in the file.
        try validateHeadTable(data, head, format);
        try validateMaxpTable(data, maxp, format);

        const glyph_count = try bin.readU16At(data, maxp.offset + 4);
        if (post) |post_table| try validatePostTable(data, post_table, glyph_count, .{
            .compat_ttc_face = is_ttc_face,
            // Glyph names are optional metadata and do not affect cmap,
            // shaping, metrics, or outlines. Keep parse-time validation
            // structural; the public glyphName API performs strict text
            // validation before exposing a borrowed custom name.
            .custom_name_validation = .structural_only,
        });
        const number_of_h_metrics = if (has_horizontal_metrics)
            try validateHorizontalMetricsTables(data, hhea.?, hmtx.?, glyph_count)
        else
            0;
        _ = validateVerticalMetricsTables(data, glyph_count, vhea, vmtx) catch |err| switch (err) {
            // Vertical metrics are optional for horizontal UI text. Some widely
            // deployed fallback CJK fonts ship a present-but-unusable vhea/vmtx
            // pair (for example, zero vertical line metrics) while their cmap,
            // hhea/hmtx and glyf outlines are valid. Accept those fonts for
            // horizontal shaping/rasterization; callers that explicitly request
            // vertical metrics still revalidate and receive InvalidMetrics.
            error.InvalidMetrics => {},
            else => return err,
        };
        if (os2) |os2_table| try validateOs2Table(data, os2_table);
        if (pclt) |pclt_table| try validatePcltTable(data, pclt_table);
        if (ankr) |ankr_table| try validateAnkrTable(data, ankr_table, glyph_count);
        if (mort) |mort_table| try aat_mort.validate(data, mort_table.offset, mort_table.length, glyph_count);
        if (morx) |morx_table| try validateMorxTable(data, morx_table, glyph_count);
        if (math) |math_table| try validateMathTable(data, math_table);
        if (feat) |feat_table| try validateFeatTable(data, feat_table);
        if (trak) |trak_table| try validateTrakTable(data, trak_table);
        if (meta) |meta_table| try validateMetaTable(data, meta_table);
        if (name) |name_table| {
            validateNameTable(data, name_table) catch |err| switch (err) {
                error.InvalidName => if (!is_ttc_face) return err,
                else => return err,
            };
        }
        const fvar_axis_count: ?u16 = if (fvar) |fvar_table| blk: {
            try validateFvarTable(data, fvar_table);
            break :blk @intCast((try readFvarInfo(data, fvar_table)).axis_count);
        } else null;
        if (avar) |avar_table| try validateAvarTable(data, avar_table, fvar);
        const cvt_value_count = if (cvt) |cvt_table| try validateCvtTable(cvt_table) else null;
        if (fpgm) |fpgm_table| try validateTrueTypeProgramTable(data, fpgm_table);
        if (prep) |prep_table| try validateTrueTypeProgramTable(data, prep_table);
        if (kern) |kern_table| try validateKernTable(data, kern_table, glyph_count);
        if (kerx) |kerx_table| try validateKerxTable(data, kerx_table, glyph_count);
        if (hdmx) |hdmx_table| try validateHdmxTable(data, hdmx_table, glyph_count);
        if (ltsh) |ltsh_table| try validateLtshTable(data, ltsh_table, glyph_count);
        if (ltag) |ltag_table| try validateLtagTable(data, ltag_table);
        if (gasp) |gasp_table| try validateGaspTable(data, gasp_table);

        const units_per_em = try bin.readU16At(data, head.offset + 18);
        const index_to_loc_format = try bin.readI16At(data, head.offset + 50);
        const ascender = if (hhea) |table| try bin.readI16At(data, table.offset + 4) else @as(i16, @intCast(units_per_em));
        const descender = if (hhea) |table| try bin.readI16At(data, table.offset + 6) else 0;
        const line_gap = if (hhea) |table| try bin.readI16At(data, table.offset + 8) else 0;
        const cff_parsed: ?CffParsedInfo = if (format == .opentype_cff and cff != null) blk: {
            const cff_table = cff.?;
            const parsed = try cff_mod.parse(data[cff_table.offset .. cff_table.offset + cff_table.length]);
            if (parsed.info.charstrings_count != glyph_count) return error.BadSfnt;
            break :blk parsed;
        } else null;
        if (format == .opentype_cff and cff2 != null) try validateCff2Table(data, cff2.?);
        if (format == .truetype and has_glyf_outlines) {
            const max_points = try bin.readU16At(data, maxp.offset + 6);
            const max_contours = try bin.readU16At(data, maxp.offset + 8);
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
                max_points,
                max_contours,
                max_component_elements,
                max_component_depth,
            );
        }
        const gvar_target_context: ?GvarGlyphTargetContext = if (format == .truetype and has_glyf_outlines)
            .{ .loca = loca.?, .glyf = glyf.?, .index_to_loc_format = index_to_loc_format }
        else
            null;
        try validateVariationDataTablesWithCvar(data, glyph_count, fvar, gvar, hvar, mvar, vvar, cvar, cvt_value_count, gvar_target_context);
        try validateVariationNameReferences(allocator, data, fvar, stat, name, .{ .compat_ttc_face = is_ttc_face });
        if (gdef) |gdef_table| try validateGdefTableWithVariationData(data, gdef_table, glyph_count, fvar);
        if (gsub) |gsub_table| try gsub_mod.validateGlyphBoundsForShaping(data, gsub_table.offset, gsub_table.length, glyph_count);
        if (gpos) |gpos_table| try gpos_mod.validateGlyphBounds(data, gpos_table.offset, gpos_table.length, glyph_count);
        if (cpal) |cpal_table| {
            _ = cpal_mod.validate(
                data,
                cpalTable(cpal_table),
                if (name) |name_table| nameTableView(name_table) else null,
            ) catch |err| switch (err) {
                error.InvalidName => if (!is_ttc_face) return err,
                else => return err,
            };
        }
        if (varc) |varc_table| try validateVarcTable(data, varc_table, glyph_count);
        if (ift) |ift_table| try validateIftPatchMapTable(data, ift_table);
        if (iftx) |iftx_table| try validateIftPatchMapTable(data, iftx_table);
        if (colr) |colr_table| {
            try colr_v1_mod.validateTopLevel(
                data,
                colrV1Table(colr_table),
            );
            try validateColrVariationData(data, colr_table, fvar, glyph_count);
            try validateColrGlyphBounds(data, colr_table, glyph_count);
            try validateColrPaletteBounds(data, colr_table, cpal);
        }
        if (base) |base_table| try validateBaseTable(data, base_table);
        if (dsig) |dsig_table| try validateDsigTable(data, dsig_table);
        if (vorg) |vorg_table| try validateVorgTable(data, vorg_table, glyph_count);
        if (svg) |svg_table| try svg_mod.validate(
            allocator,
            data,
            svgTable(svg_table),
            glyph_count,
        );
        if (sbix) |sbix_table| try validateSbixTable(allocator, data, sbix_table, glyph_count);
        if (cblc != null and cbdt != null) try validateCblcCbdtTables(data, cblc.?, cbdt.?, glyph_count);
        if (eblc != null and ebdt != null) try validateCblcCbdtTables(data, eblc.?, ebdt.?, glyph_count);
        if (!is_ttc_face) try sfnt.checksum.validateAll(data, records);

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
            .hdmx = hdmx,
            .ltsh = ltsh,
            .ltag = ltag,
            .loca = loca,
            .cmap = cmap,
            .kern = kern,
            .kerx = kerx,
            .mort = mort,
            .morx = morx,
            .os2 = os2,
            .gasp = gasp,
            .gdef = gdef,
            .gpos = gpos,
            .gsub = gsub,
            .ankr = ankr,
            .feat = feat,
            .trak = trak,
            .name = name,
            .math = math,
            .meta = meta,
            .post = post,
            .pclt = pclt,
            .stat = stat,
            .fvar = fvar,
            .fvar_axis_count = fvar_axis_count,
            .avar = avar,
            .cvt = cvt,
            .cvar = cvar,
            .gvar = gvar,
            .fpgm = fpgm,
            .prep = prep,
            .hvar = hvar,
            .mvar = mvar,
            .vvar = vvar,
            .varc = varc,
            .ift = ift,
            .iftx = iftx,
            .colr = colr,
            .cpal = cpal,
            .base = base,
            .dsig = dsig,
            .vorg = vorg,
            .svg = svg,
            .sbix = sbix,
            .cblc = cblc,
            .cbdt = cbdt,
            .eblc = eblc,
            .ebdt = ebdt,
            .glyf = glyf,
            .cff = cff,
            .cff_parsed = cff_parsed,
            .cff2 = cff2,
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

    /// Read validated top-level metadata from the optional TrueType `gvar` table.
    pub fn gvarInfo(self: *const Font) FontError!?GvarInfo {
        const gvar = self.gvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        const fvar_info = try readFvarInfo(self.data, fvar);
        try sfnt.checksum.validate(self.data, gvar);
        try gvar_mod.validate(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count);
        return try gvar_mod.info(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count);
    }

    /// Read per-glyph metadata from the optional TrueType `gvar` table.
    pub fn gvarGlyphInfo(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?GvarGlyphInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gvar = self.gvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        const fvar_info = try readFvarInfo(self.data, fvar);
        try sfnt.checksum.validate(self.data, gvar);
        return try gvar_mod.glyphInfo(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count, glyph_id);
    }

    /// Read tuple metadata for a glyph variation entry in the optional `gvar` table.
    pub fn gvarTupleInfo(self: *const Font, glyph_id: glyph_mod.GlyphId, tuple_index: usize) FontError!?GvarTupleInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gvar = self.gvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        const fvar_info = try readFvarInfo(self.data, fvar);
        try sfnt.checksum.validate(self.data, gvar);
        return try gvar_mod.tupleInfo(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count, glyph_id, tuple_index);
    }

    /// Decode accumulated `gvar` point deltas for a glyph at normalized coordinates.
    pub fn gvarPointDeltasAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?[]GvarScaledPointDelta {
        return try self.gvarPointDeltasAtCoordsWithFlags(allocator, glyph_id, normalized_coords, null);
    }

    /// Decode the four TrueType phantom-point deltas for `glyph_id`.
    ///
    /// The return order matches FreeType/fontations terminology:
    /// `.left`, `.right`, `.top`, `.bottom`. Horizontal advance variation is
    /// `right.x - left.x`; vertical advance variation is `top.y - bottom.y`.
    /// Compound glyphs follow the same `USE_MY_METRICS` ownership rule as
    /// FreeType/fontations: use the last flagged component's glyph data, or
    /// the compound glyph's own component-count phantom range when no component
    /// requests metric ownership.
    pub fn gvarPhantomPointDeltasAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?GvarPhantomPointDeltas {
        return try self.gvarPhantomPointDeltasAtCoordsPrepared(allocator, glyph_id, normalized_coords, .revalidate);
    }

    fn gvarPhantomPointDeltasAtCoordsPrepared(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!?GvarPhantomPointDeltas {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (self.gvar == null) return null;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);

        const target = try self.gvarMetricVariationTarget(glyph_id, 0);
        const deltas = (try self.gvarPointDeltasAtCoordsPreparedNoShrink(allocator, target.glyph_id, normalized_coords, target.point_count + 4, null, read_mode)) orelse return null;
        defer allocator.free(deltas);
        return try gvar_mod.phantomPointDeltas(target.point_count, deltas);
    }

    fn gvarPointDeltasAtCoordsWithFlags(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, has_delta: ?[]bool) FontError!?[]GvarScaledPointDelta {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        return try self.gvarPointDeltasAtCoordsPrepared(allocator, glyph_id, normalized_coords, try self.gvarTargetCount(glyph_id), has_delta, .revalidate);
    }

    fn gvarPointDeltasAtCoordsPrepared(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, target_count: usize, has_delta: ?[]bool, read_mode: OutlineReadMode) FontError!?[]GvarScaledPointDelta {
        const out, const count = (try self.gvarPointDeltasAtCoordsPreparedNoShrinkWithCount(allocator, glyph_id, normalized_coords, target_count, has_delta, read_mode)) orelse return null;
        if (count == out.len) return out;
        return try allocator.realloc(out, count);
    }

    fn gvarPointDeltasAtCoordsPreparedNoShrink(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, target_count: usize, has_delta: ?[]bool, read_mode: OutlineReadMode) FontError!?[]GvarScaledPointDelta {
        const out, const count = (try self.gvarPointDeltasAtCoordsPreparedNoShrinkWithCount(allocator, glyph_id, normalized_coords, target_count, has_delta, read_mode)) orelse return null;
        if (count == 0) {
            allocator.free(out);
            return null;
        }
        std.debug.assert(count == out.len);
        return out;
    }

    fn gvarPointDeltasAtCoordsPreparedNoShrinkWithCount(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, target_count: usize, has_delta: ?[]bool, read_mode: OutlineReadMode) FontError!?struct { []GvarScaledPointDelta, usize } {
        const gvar = self.gvar orelse return null;
        const axis_count = try self.fvarAxisCountForReadMode(read_mode);
        if (read_mode.shouldRevalidate()) try sfnt.checksum.validate(self.data, gvar);
        if (target_count > @as(usize, std.math.maxInt(u16)) + 1) return error.BadSfnt;
        var inline_raw_scratch: [64]gvar_mod.PointDelta = undefined;
        const raw_scratch = if (target_count <= inline_raw_scratch.len)
            inline_raw_scratch[0..target_count]
        else
            try allocator.alloc(gvar_mod.PointDelta, target_count);
        defer if (target_count > inline_raw_scratch.len) allocator.free(raw_scratch);
        const out = try allocator.alloc(gvar_mod.ScaledPointDelta, target_count);
        errdefer allocator.free(out);
        const count = switch (read_mode) {
            .revalidate => try gvar_mod.accumulateGlyphPointDeltasForPointCountRawScratchWithFlags(self.data, gvar.offset, gvar.length, self.glyph_count, axis_count, glyph_id, normalized_coords, target_count, raw_scratch, out, has_delta),
            .parsed => try gvar_mod.accumulateGlyphPointDeltasForPointCountSkippingInactiveRawScratchWithFlags(self.data, gvar.offset, gvar.length, self.glyph_count, axis_count, glyph_id, normalized_coords, target_count, raw_scratch, out, has_delta),
        };
        if (count == 0 and read_mode == .parsed) {
            allocator.free(out);
            return null;
        }
        return .{ out, count };
    }

    fn fvarAxisCountForReadMode(self: *const Font, read_mode: OutlineReadMode) FontError!usize {
        const fvar = self.fvar orelse return error.BadSfnt;
        return switch (read_mode) {
            .revalidate => (try readFvarInfo(self.data, fvar)).axis_count,
            .parsed => self.fvar_axis_count orelse error.BadSfnt,
        };
    }

    /// Return TrueType `gvar`-adjusted glyph bounds at normalized coordinates.
    pub fn gvarGlyphBoundsAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?glyph_mod.Bounds {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (self.gvar == null) return null;
        var outline = try self.glyphOutlineAtCoords(allocator, glyph_id, normalized_coords);
        defer outline.deinit();
        return outline.bounds;
    }

    /// Return the CFF2 font-dict index selected for a glyph, when FDSelect is present.
    pub fn cff2FontDictIndex(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?u16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.fontDictIndex(self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count);
    }

    /// Borrow raw CFF2 Global Subr bytes, when the optional CFF2 table is present.
    pub fn cff2GlobalSubrData(self: *const Font, subr_index: usize) FontError!?[]const u8 {
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.globalSubrData(self.data, cff2.offset, cff2.length, subr_index);
    }

    /// Borrow a raw CFF2 Global Subr using a biased callgsubr operand.
    pub fn cff2GlobalSubrDataForOperand(self: *const Font, operand: i32) FontError!?[]const u8 {
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.globalSubrDataForOperand(self.data, cff2.offset, cff2.length, operand);
    }

    /// Read CFF2 Font DICT and Private DICT metadata for a font-dict index.
    pub fn cff2FontDictInfo(self: *const Font, font_dict_index: usize) FontError!?Cff2FontDictInfo {
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.fontDictInfo(self.data, cff2.offset, cff2.length, font_dict_index);
    }

    /// Borrow raw CFF2 Local Subr bytes for a font-dict index, when present.
    pub fn cff2LocalSubrData(self: *const Font, font_dict_index: usize, subr_index: usize) FontError!?[]const u8 {
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.localSubrData(self.data, cff2.offset, cff2.length, font_dict_index, subr_index);
    }

    /// Borrow a raw CFF2 Local Subr using a biased callsubr operand.
    pub fn cff2LocalSubrDataForOperand(self: *const Font, font_dict_index: usize, operand: i32) FontError!?[]const u8 {
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.localSubrDataForOperand(self.data, cff2.offset, cff2.length, font_dict_index, operand);
    }

    /// Borrow raw CFF2 CharString bytes for a glyph, when the optional CFF2 table is present.
    pub fn cff2CharStringData(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.charStringData(self.data, cff2.offset, cff2.length, glyph_id);
    }

    /// Structurally scan a CFF2 glyph charstring and reachable subroutines.
    pub fn cff2CharStringScanInfo(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?Cff2CharStringScanInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.charStringScanInfo(self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count);
    }

    /// Execute a CFF2 glyph charstring enough to compute conservative bounds.
    pub fn cff2CharStringBoundsInfo(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?Cff2CharStringBoundsInfo {
        return try self.cff2CharStringBoundsInfoAtCoords(glyph_id, &.{});
    }

    /// Execute CFF2 bounds using caller-supplied normalized variation coordinates.
    pub fn cff2CharStringBoundsInfoAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?Cff2CharStringBoundsInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.charStringBoundsInfoAtCoords(self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count, normalized_coords);
    }

    /// Return integer CFF2 glyph bounds using caller-supplied normalized variation coordinates.
    pub fn cff2GlyphBoundsAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?glyph_mod.Bounds {
        const bounds = (try self.cff2CharStringBoundsInfoAtCoords(glyph_id, normalized_coords)) orelse return null;
        return cff2BoundsInfoToGlyphBounds(bounds);
    }

    /// Build a CFF2 glyph outline using caller-supplied normalized variation coordinates.
    pub fn cff2GlyphOutlineAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?glyph_mod.GlyphOutline {
        return try self.cff2GlyphOutlineAtCoordsPrepared(allocator, glyph_id, normalized_coords, .revalidate);
    }

    fn cff2GlyphOutlineAtCoordsPrepared(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!?glyph_mod.GlyphOutline {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const cff2 = self.cff2 orelse return null;
        if (read_mode.shouldRevalidate()) {
            try sfnt.checksum.validate(self.data, cff2);
            try validateCff2Table(self.data, cff2);
        }
        const metrics = try self.horizontalMetricsForReadMode(glyph_id, read_mode);
        var outline = glyph_mod.GlyphOutline.init(allocator, glyph_id, .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 }, metrics.advance_width, metrics.left_side_bearing);
        errdefer outline.deinit();
        if (try cff2_mod.appendGlyphOutlineAtCoords(allocator, self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count, normalized_coords, &outline)) |bounds_info| {
            outline.bounds = cff2BoundsInfoToGlyphBounds(bounds_info);
            return outline;
        }
        outline.deinit();
        return null;
    }

    /// Read validated top-level metadata from the optional OpenType `CFF2` table.
    pub fn cff2Info(self: *const Font) FontError!?Cff2Info {
        const cff2 = self.cff2 orelse return null;
        try sfnt.checksum.validate(self.data, cff2);
        try validateCff2Table(self.data, cff2);
        return try cff2_mod.info(self.data, cff2.offset, cff2.length);
    }

    pub fn tables(self: *const Font, allocator: std.mem.Allocator) std.mem.Allocator.Error![]FontTableInfo {
        const infos = try allocator.alloc(FontTableInfo, self.owned_tables.len);
        for (infos, self.owned_tables) |*info, record| {
            info.* = .{
                .tag = record.tag,
                .checksum = record.checksum,
                .offset = record.offset,
                .length = record.length,
            };
        }
        return infos;
    }

    /// Read raw TrueType Control Value Table entries from the optional `cvt ` table.
    pub fn cvtValues(self: *const Font, allocator: std.mem.Allocator) FontError![]i16 {
        const cvt = self.cvt orelse return try allocator.alloc(i16, 0);
        try sfnt.checksum.validate(self.data, cvt);
        _ = try validateCvtTable(cvt);
        return try readCvtValues(allocator, self.data, cvt);
    }

    /// Read validated tuple metadata from the optional TrueType `cvar` table.
    pub fn cvarInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?CvarInfo {
        const cvar = self.cvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        const cvt = self.cvt orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.data, fvar);
        try validateFvarTable(self.data, fvar);
        try sfnt.checksum.validate(self.data, cvt);
        const cvt_value_count = try validateCvtTable(cvt);
        try sfnt.checksum.validate(self.data, cvar);
        const fvar_info = try readFvarInfo(self.data, fvar);
        try validateCvarTable(self.data, cvar, fvar_info.axis_count, cvt_value_count);
        return try cvar_mod.info(allocator, self.data, cvar.offset, cvar.length, fvar_info.axis_count);
    }

    pub fn freeCvarInfo(_: *const Font, allocator: std.mem.Allocator, info_value: CvarInfo) void {
        cvar_mod.free(allocator, info_value);
    }

    /// Read validated chain, feature, and subtable metadata from the optional AAT `morx` table.
    pub fn morxInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?MorxInfo {
        const morx = self.morx orelse return null;
        try sfnt.checksum.validate(self.data, morx);
        try validateMorxTable(self.data, morx, self.glyph_count);
        return try morx_mod.info(allocator, self.data, morx.offset, morx.length, self.glyph_count);
    }

    pub fn freeMorxInfo(_: *const Font, allocator: std.mem.Allocator, info_value: MorxInfo) void {
        morx_mod.free(allocator, info_value);
    }

    /// Decode a table-keyed IFT patch payload supplied by the caller.
    pub fn iftTableKeyedPatchInfo(_: *const Font, allocator: std.mem.Allocator, patch_data: []const u8) FontError!IftTableKeyedPatchInfo {
        return try ift_mod.tableKeyedPatchInfo(allocator, patch_data, 0, patch_data.len);
    }

    pub fn freeIftTableKeyedPatchInfo(_: *const Font, allocator: std.mem.Allocator, info_value: IftTableKeyedPatchInfo) void {
        ift_mod.freeTableKeyedPatchInfo(allocator, info_value);
    }

    /// Decode a glyph-keyed IFT patch payload supplied by the caller.
    pub fn iftGlyphKeyedPatchInfo(_: *const Font, patch_data: []const u8) FontError!IftGlyphKeyedPatchInfo {
        return try ift_mod.glyphKeyedPatchInfo(patch_data, 0, patch_data.len);
    }

    /// Read validated top-level metadata from the optional IFT patch map table.
    pub fn iftPatchMapInfo(self: *const Font) FontError!?IftPatchMapInfo {
        const table = self.ift orelse return null;
        try sfnt.checksum.validate(self.data, table);
        try validateIftPatchMapTable(self.data, table);
        return try ift_mod.info(self.data, table.offset, table.length);
    }

    /// Read validated top-level metadata from the optional IFTX patch map table.
    pub fn iftxPatchMapInfo(self: *const Font) FontError!?IftPatchMapInfo {
        const table = self.iftx orelse return null;
        try sfnt.checksum.validate(self.data, table);
        try validateIftPatchMapTable(self.data, table);
        return try ift_mod.info(self.data, table.offset, table.length);
    }

    /// Read validated top-level metadata from the optional OpenType `VARC` table.
    pub fn varcInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?VarcInfo {
        const varc = self.varc orelse return null;
        try sfnt.checksum.validate(self.data, varc);
        try validateVarcTable(self.data, varc, self.glyph_count);
        return try varc_mod.info(allocator, self.data, varc.offset, varc.length, self.glyph_count);
    }

    pub fn freeVarcInfo(_: *const Font, allocator: std.mem.Allocator, info_value: VarcInfo) void {
        varc_mod.free(allocator, info_value);
    }

    /// Read validated metadata and format-0 pairs from the optional AAT `kerx` table.
    pub fn kerxInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?KerxInfo {
        const kerx = self.kerx orelse return null;
        try sfnt.checksum.validate(self.data, kerx);
        try validateKerxTable(self.data, kerx, self.glyph_count);
        return try kerx_mod.info(allocator, self.data, kerx.offset, kerx.length, self.glyph_count);
    }

    pub fn freeKerxInfo(_: *const Font, allocator: std.mem.Allocator, info_value: KerxInfo) void {
        kerx_mod.free(allocator, info_value);
    }

    /// Read validated anchor points from the optional AAT `ankr` table.
    pub fn ankrInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?AnkrInfo {
        const ankr = self.ankr orelse return null;
        try sfnt.checksum.validate(self.data, ankr);
        try validateAnkrTable(self.data, ankr, self.glyph_count);
        return try ankr_mod.info(allocator, self.data, ankr.offset, ankr.length, self.glyph_count);
    }

    pub fn freeAnkrInfo(_: *const Font, allocator: std.mem.Allocator, info_value: AnkrInfo) void {
        ankr_mod.free(allocator, info_value);
    }

    /// Decode the optional TrueType `fpgm` font program as structural bytecode.
    pub fn fontProgramInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?TrueTypeProgramInfo {
        const fpgm = self.fpgm orelse return null;
        try sfnt.checksum.validate(self.data, fpgm);
        try validateTrueTypeProgramTable(self.data, fpgm);
        return try tt_program_mod.info(allocator, .font, self.data[fpgm.offset .. fpgm.offset + fpgm.length]);
    }

    /// Decode the optional TrueType `prep` control-value program as structural bytecode.
    pub fn controlValueProgramInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?TrueTypeProgramInfo {
        const prep = self.prep orelse return null;
        try sfnt.checksum.validate(self.data, prep);
        try validateTrueTypeProgramTable(self.data, prep);
        return try tt_program_mod.info(allocator, .control_value, self.data[prep.offset .. prep.offset + prep.length]);
    }

    pub fn freeTrueTypeProgramInfo(_: *const Font, allocator: std.mem.Allocator, info_value: TrueTypeProgramInfo) void {
        tt_program_mod.free(allocator, info_value);
    }

    /// Read validated metadata from the optional OpenType `HVAR` table.
    pub fn hvarInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?HvarInfo {
        const hvar = (try self.metricVariationTableForRead(.hvar)) orelse return null;
        return try metric_variation_mod.hvarInfo(allocator, self.data, hvar.offset, hvar.length);
    }

    pub fn freeHvarInfo(_: *const Font, allocator: std.mem.Allocator, info_value: HvarInfo) void {
        metric_variation_mod.freeHvar(allocator, info_value);
    }

    /// Return the HVAR advance-width delta in font units for a glyph at normalized coordinates.
    pub fn hvarAdvanceWidthDeltaAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?i32 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const hvar = (try self.metricVariationTableForRead(.hvar)) orelse return null;
        return try metric_variation_mod.hvarAdvanceWidthDelta(self.data, hvar.offset, hvar.length, glyph_id, normalized_coords);
    }

    pub fn hvarRightSideBearingDeltaAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?i32 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const hvar = (try self.metricVariationTableForRead(.hvar)) orelse return null;
        return try metric_variation_mod.hvarRightSideBearingDelta(self.data, hvar.offset, hvar.length, glyph_id, normalized_coords);
    }

    /// Return horizontal metrics with HVAR advance/LSB deltas applied when present.
    pub fn horizontalMetricsAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!HorizontalMetricInfo {
        var metrics = try self.horizontalMetricsAtCoordsForReadMode(glyph_id, normalized_coords, .revalidate);
        if (self.hvar == null and self.gvar != null) {
            if (try self.gvarPhantomPointDeltasAtCoordsPrepared(std.heap.page_allocator, glyph_id, normalized_coords, .revalidate)) |phantom| {
                // With no HVAR, OpenType derives horizontal metric deltas from
                // gvar phantom points: pp1 is the LSB delta and pp2-pp1 is the
                // advance delta. This is the high-level metrics contract used
                // by Fontations and FreeType; VARC's internal GlyphHMetrics
                // deliberately remains hmtx+HVAR only.
                metrics.left_side_bearing = clampF32ToI16(
                    roundOpenTypeF32(@as(f32, @floatFromInt(metrics.left_side_bearing)) + phantom.left.x),
                );
                metrics.advance_width = clampF32ToU16(
                    roundOpenTypeF32(@as(f32, @floatFromInt(metrics.advance_width)) + phantom.horizontalAdvanceDelta()),
                );
            }
        }
        return metrics;
    }

    fn horizontalMetricsAtCoordsForReadMode(
        self: *const Font,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
        read_mode: OutlineReadMode,
    ) FontError!HorizontalMetricInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        var metrics = try self.horizontalMetricsForReadMode(glyph_id, read_mode);
        const hvar = switch (read_mode) {
            .revalidate => (try self.metricVariationTableForRead(.hvar)) orelse return metrics,
            // Font.parse already validated HVAR against fvar and the glyph
            // count. Raster loops may therefore avoid document-level checksum
            // and structural validation on every outline request.
            .parsed => self.hvar orelse return metrics,
        };

        const advance_delta = try metric_variation_mod.hvarAdvanceWidthDelta(self.data, hvar.offset, hvar.length, glyph_id, normalized_coords);
        metrics.advance_width = clampI32ToU16(@as(i32, metrics.advance_width) + advance_delta);
        if (try metric_variation_mod.hvarLeftSideBearingDelta(self.data, hvar.offset, hvar.length, glyph_id, normalized_coords)) |lsb_delta| {
            metrics.left_side_bearing = clampI32ToI16(@as(i32, metrics.left_side_bearing) + lsb_delta);
        }
        return metrics;
    }

    /// Read validated value records from the optional OpenType `MVAR` table.
    pub fn mvarInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?MvarInfo {
        const mvar = self.mvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.data, fvar);
        try validateFvarTable(self.data, fvar);
        try sfnt.checksum.validate(self.data, mvar);
        const fvar_info = try readFvarInfo(self.data, fvar);
        try validateMvarTable(self.data, mvar, fvar_info.axis_count);
        return try mvar_mod.info(allocator, self.data, mvar.offset, mvar.length);
    }

    pub fn freeMvarInfo(_: *const Font, allocator: std.mem.Allocator, info_value: MvarInfo) void {
        mvar_mod.free(allocator, info_value);
    }

    /// Read validated metadata from the optional OpenType `VVAR` table.
    pub fn vvarInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?VvarInfo {
        const vvar = (try self.metricVariationTableForRead(.vvar)) orelse return null;
        return try metric_variation_mod.vvarInfo(allocator, self.data, vvar.offset, vvar.length);
    }

    pub fn freeVvarInfo(_: *const Font, allocator: std.mem.Allocator, info_value: VvarInfo) void {
        metric_variation_mod.freeVvar(allocator, info_value);
    }

    /// Return the VVAR advance-height delta in font units for a glyph at normalized coordinates.
    pub fn vvarAdvanceHeightDeltaAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?i32 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const vvar = (try self.metricVariationTableForRead(.vvar)) orelse return null;
        return try metric_variation_mod.vvarAdvanceHeightDelta(self.data, vvar.offset, vvar.length, glyph_id, normalized_coords);
    }

    pub fn vvarBottomSideBearingDeltaAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?i32 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const vvar = (try self.metricVariationTableForRead(.vvar)) orelse return null;
        return try metric_variation_mod.vvarBottomSideBearingDelta(self.data, vvar.offset, vvar.length, glyph_id, normalized_coords);
    }

    /// Return vertical metrics with VVAR advance/TSB deltas applied when present.
    pub fn verticalMetricsAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?VerticalMetrics {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        var metrics = (try self.verticalMetrics(glyph_id)) orelse return null;
        if (try self.metricVariationTableForRead(.vvar)) |vvar| {
            const advance_delta = try metric_variation_mod.vvarAdvanceHeightDelta(self.data, vvar.offset, vvar.length, glyph_id, normalized_coords);
            metrics.advance_height = clampI32ToU16(@as(i32, metrics.advance_height) + advance_delta);
            if (try metric_variation_mod.vvarTopSideBearingDelta(self.data, vvar.offset, vvar.length, glyph_id, normalized_coords)) |tsb_delta| {
                metrics.top_side_bearing = clampI32ToI16(@as(i32, metrics.top_side_bearing) + tsb_delta);
            }
            return metrics;
        }

        if (self.gvar != null) {
            if (try self.gvarPhantomPointDeltasAtCoordsPrepared(std.heap.page_allocator, glyph_id, normalized_coords, .revalidate)) |phantom| {
                // Without VVAR, TrueType derives vertical metrics from gvar's
                // pp3/pp4 phantom points. pp3 moves the absolute vertical
                // origin; TSB therefore also has to account for the varied
                // outline yMax rather than merely adding pp3.y to the static
                // bearing.
                const default_bounds = try self.glyphBounds(glyph_id);
                const varied_bounds = try self.glyphBoundsAtCoords(glyph_id, normalized_coords);
                const varied_origin = roundOpenTypeF32(
                    @as(f32, @floatFromInt(default_bounds.y_max)) +
                        @as(f32, @floatFromInt(metrics.top_side_bearing)) +
                        phantom.top.y,
                );
                metrics.top_side_bearing = clampF32ToI16(
                    varied_origin - @as(f32, @floatFromInt(varied_bounds.y_max)),
                );
                metrics.advance_height = clampF32ToU16(
                    roundOpenTypeF32(
                        @as(f32, @floatFromInt(metrics.advance_height)) +
                            phantom.verticalAdvanceDelta(),
                    ),
                );
            }
        }
        return metrics;
    }

    const MetricVariationKind = enum { hvar, vvar };

    fn metricVariationTableForRead(self: *const Font, kind: MetricVariationKind) FontError!?TableRecord {
        const table, const minimum_length = switch (kind) {
            .hvar => .{ self.hvar orelse return null, @as(usize, 20) },
            .vvar => .{ self.vvar orelse return null, @as(usize, 24) },
        };
        const fvar = self.fvar orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.data, fvar);
        try validateFvarTable(self.data, fvar);
        try sfnt.checksum.validate(self.data, table);
        const fvar_info = try readFvarInfo(self.data, fvar);
        try validateMetricVariationTable(self.data, table, fvar_info.axis_count, minimum_length);
        return table;
    }

    /// Read validated metadata from the optional OpenType `BASE` table.
    pub fn baseInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?BaseInfo {
        const base = self.base orelse return null;
        try sfnt.checksum.validate(self.data, base);
        return try base_mod.info(allocator, self.data, base.offset, base.length);
    }

    pub fn freeBaseInfo(_: *const Font, allocator: std.mem.Allocator, info_value: BaseInfo) void {
        base_mod.free(allocator, info_value);
    }

    /// Borrow the raw bytes of an SFNT table by four-byte tag.
    ///
    /// The returned slice points into the caller-owned font data backing this
    /// Font. Revalidate the table checksum at this API boundary so mutations to
    /// borrowed bytes after parse do not escape as authoritative table data.
    pub fn tableData(self: *const Font, tag: [4]u8) FontError!?[]const u8 {
        const record = sfnt.findTag(self.owned_tables, tag) orelse return null;
        try sfnt.checksum.validate(self.data, record);
        return self.data[record.offset .. record.offset + record.length];
    }

    /// Read validated tracking data from the optional AAT `trak` table.
    pub fn trakInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?TrackTableInfo {
        const trak = self.trak orelse return null;
        try sfnt.checksum.validate(self.data, trak);
        return try trak_mod.info(allocator, self.data, trak.offset, trak.length);
    }

    pub fn freeTrakInfo(_: *const Font, allocator: std.mem.Allocator, info: TrackTableInfo) void {
        trak_mod.free(allocator, info);
    }

    fn horizontalTrackingForShaping(self: *const Font, allocator: std.mem.Allocator, point_size: f32) FontError!?f32 {
        const info_value = (try self.trakInfo(allocator)) orelse return null;
        defer self.freeTrakInfo(allocator, info_value);
        if (info_value.horizontal.len == 0) return null;
        return trackingValueForPointSize(info_value.horizontal[0].values, if (point_size > 0) point_size else 12.0);
    }

    /// Read validated records from the optional AAT `feat` table.
    pub fn featFeatures(self: *const Font, allocator: std.mem.Allocator) FontError![]FeatureNameInfo {
        const feat = self.feat orelse return try allocator.alloc(FeatureNameInfo, 0);
        try sfnt.checksum.validate(self.data, feat);
        return try feat_mod.features(allocator, self.data, feat.offset, feat.length);
    }

    pub fn freeFeatFeatures(_: *const Font, allocator: std.mem.Allocator, features: []FeatureNameInfo) void {
        feat_mod.free(allocator, features);
    }

    /// Read validated records from the optional Apple SFNT `ltag` table.
    pub fn ltagRecords(self: *const Font, allocator: std.mem.Allocator) FontError![]LtagRecordInfo {
        const ltag = self.ltag orelse return try allocator.alloc(LtagRecordInfo, 0);
        try sfnt.checksum.validate(self.data, ltag);
        return try ltag_mod.records(allocator, self.data, ltag.offset, ltag.length);
    }

    /// Read raw MATH italics correction for a glyph, if MathGlyphInfo covers it.
    pub fn mathItalicsCorrection(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?MathValueRecordInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const math = self.math orelse return null;
        try sfnt.checksum.validate(self.data, math);
        try validateMathTable(self.data, math);
        return try math_mod.glyphValueRecord(self.data, math.offset, math.length, glyph_id, .italics_correction);
    }

    /// Read raw MATH top-accent attachment for a glyph, if MathGlyphInfo covers it.
    pub fn mathTopAccentAttachment(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?MathValueRecordInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const math = self.math orelse return null;
        try sfnt.checksum.validate(self.data, math);
        try validateMathTable(self.data, math);
        return try math_mod.glyphValueRecord(self.data, math.offset, math.length, glyph_id, .top_accent_attachment);
    }

    /// Return whether MATH marks the glyph as an extended shape.
    pub fn mathIsExtendedShape(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!bool {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const math = self.math orelse return false;
        try sfnt.checksum.validate(self.data, math);
        try validateMathTable(self.data, math);
        return try math_mod.isExtendedShape(self.data, math.offset, math.length, glyph_id);
    }

    /// Return MATH variant records for a glyph in vertical or horizontal growth direction.
    pub fn mathGlyphVariants(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, vertical: bool) FontError!?[]MathVariantRecordInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const info_value = (try self.mathInfo(allocator)) orelse return null;
        defer self.freeMathInfo(allocator, info_value);
        const construction = math_mod.constructionForGlyph(&info_value, glyph_id, vertical) orelse return null;
        const out = try allocator.alloc(MathVariantRecordInfo, construction.variants.len);
        @memcpy(out, construction.variants);
        return out;
    }

    pub fn freeMathGlyphVariants(_: *const Font, allocator: std.mem.Allocator, variants: []MathVariantRecordInfo) void {
        allocator.free(variants);
    }

    /// Return MATH assembly parts for a glyph in vertical or horizontal growth direction.
    pub fn mathGlyphAssemblyParts(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, vertical: bool) FontError!?[]MathPartRecordInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const info_value = (try self.mathInfo(allocator)) orelse return null;
        defer self.freeMathInfo(allocator, info_value);
        const construction = math_mod.constructionForGlyph(&info_value, glyph_id, vertical) orelse return null;
        const assembly = construction.assembly orelse return null;
        const out = try allocator.alloc(MathPartRecordInfo, assembly.parts.len);
        @memcpy(out, assembly.parts);
        return out;
    }

    pub fn freeMathGlyphAssemblyParts(_: *const Font, allocator: std.mem.Allocator, parts: []MathPartRecordInfo) void {
        allocator.free(parts);
    }

    pub fn mathGlyphAssemblyItalicsCorrection(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, vertical: bool) FontError!?MathValueRecordInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const info_value = (try self.mathInfo(allocator)) orelse return null;
        defer self.freeMathInfo(allocator, info_value);
        const construction = math_mod.constructionForGlyph(&info_value, glyph_id, vertical) orelse return null;
        const assembly = construction.assembly orelse return null;
        return assembly.italics_correction;
    }

    /// Return a raw MATH kern value for a glyph/corner/correction-height tuple.
    pub fn mathKernValue(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, corner: MathKernCorner, correction_height: i16) FontError!?i16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const info_value = (try self.mathInfo(allocator)) orelse return null;
        defer self.freeMathInfo(allocator, info_value);
        return math_mod.kernValue(&info_value, glyph_id, corner, correction_height);
    }

    /// Read one raw OpenType `MATH` constant, mirroring HarfBuzz's math constant selector.
    pub fn mathConstantRaw(self: *const Font, constant: MathConstant) FontError!?i32 {
        const math = self.math orelse return null;
        try sfnt.checksum.validate(self.data, math);
        try validateMathTable(self.data, math);
        return try math_mod.constantValue(self.data, math.offset, math.length, constant);
    }

    /// Read validated constants metadata from the optional OpenType `MATH` table.
    pub fn mathInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?MathInfo {
        const math = self.math orelse return null;
        try sfnt.checksum.validate(self.data, math);
        try validateMathTable(self.data, math);
        return try math_mod.info(allocator, self.data, math.offset, math.length);
    }

    pub fn freeMathInfo(_: *const Font, allocator: std.mem.Allocator, info_value: MathInfo) void {
        math_mod.free(allocator, info_value);
    }

    /// Read validated records from the optional SFNT `meta` table.
    pub fn metaRecords(self: *const Font, allocator: std.mem.Allocator) FontError![]MetaRecordInfo {
        const meta = self.meta orelse return try allocator.alloc(MetaRecordInfo, 0);
        try sfnt.checksum.validate(self.data, meta);
        return try meta_mod.records(allocator, self.data, meta.offset, meta.length);
    }

    pub fn metaData(self: *const Font, tag: [4]u8) FontError!?[]const u8 {
        const meta = self.meta orelse return null;
        try sfnt.checksum.validate(self.data, meta);
        return try meta_mod.dataForTag(self.data, meta.offset, meta.length, tag);
    }

    /// Read validated metadata from the optional SFNT `DSIG` table.
    pub fn dsigInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?DsigInfo {
        const dsig = self.dsig orelse return null;
        try sfnt.checksum.validate(self.data, dsig);
        try validateDsigTable(self.data, dsig);
        return try readDsigInfo(allocator, self.data, dsig);
    }

    pub fn freeDsigInfo(_: *const Font, allocator: std.mem.Allocator, info: DsigInfo) void {
        allocator.free(info.signatures);
    }

    /// Read validated metadata from the optional SFNT `gasp` table.
    pub fn gaspInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?GaspInfo {
        const gasp = self.gasp orelse return null;
        try sfnt.checksum.validate(self.data, gasp);
        return try gasp_mod.info(allocator, self.data, gasp.offset, gasp.length);
    }

    pub fn freeGaspInfo(_: *const Font, allocator: std.mem.Allocator, info: GaspInfo) void {
        allocator.free(info.ranges);
    }

    /// Return gasp behavior flags for a PPEM value, or null when no table exists.
    pub fn gaspBehavior(self: *const Font, ppem: u16) FontError!?u16 {
        const gasp = self.gasp orelse return null;
        try sfnt.checksum.validate(self.data, gasp);
        return try gasp_mod.behavior(self.data, gasp.offset, gasp.length, ppem);
    }

    /// Read validated metadata from the SFNT `head` table.
    ///
    /// This mirrors FreeType/fontations header inspection without requiring
    /// callers to parse raw table bytes. The returned data is copied into a
    /// value type after the borrowed `head` bytes have been revalidated.
    pub fn headInfo(self: *const Font) FontError!FontHeaderInfo {
        try sfnt.checksum.validate(self.data, self.head);
        try validateHeadTable(self.data, self.head, self.format);
        return try readFontHeaderInfo(self.data, self.head);
    }

    /// Read validated metadata from the SFNT `maxp` table.
    ///
    /// TrueType outlines expose the complete version-1.0 maximum-profile
    /// payload; CFF-backed OpenType faces expose the version-0.5 glyph count
    /// and leave TrueType-only maxima as null.
    pub fn maxpInfo(self: *const Font) FontError!MaxProfileInfo {
        try sfnt.checksum.validate(self.data, self.maxp);
        try validateMaxpTable(self.data, self.maxp, self.format);
        return try readMaxProfileInfo(self.data, self.maxp);
    }

    /// Read validated metadata from the SFNT `hhea` table.
    pub fn horizontalHeaderInfo(self: *const Font) FontError!MetricHeaderInfo {
        const hhea = self.hhea orelse return error.MissingTable;
        const hmtx = self.hmtx orelse return error.MissingTable;
        try sfnt.checksum.validate(self.data, hhea);
        _ = try validateHorizontalMetricsTables(self.data, hhea, hmtx, self.glyph_count);
        return try readMetricHeaderInfo(self.data, hhea);
    }

    /// Read validated metadata from the optional SFNT `vhea` table.
    ///
    /// Fonts without vertical metrics return null; a dangling vhea/vmtx pair or
    /// malformed borrowed table reports InvalidMetrics/BadSfnt instead of
    /// silently falling back to horizontal metrics.
    pub fn verticalHeaderInfo(self: *const Font) FontError!?MetricHeaderInfo {
        const vhea = sfnt.find(self.owned_tables, "vhea") orelse {
            if (sfnt.find(self.owned_tables, "vmtx") != null) return error.InvalidMetrics;
            return null;
        };
        const vmtx = sfnt.find(self.owned_tables, "vmtx") orelse return error.InvalidMetrics;
        try sfnt.checksum.validate(self.data, vhea);
        try sfnt.checksum.validate(self.data, vmtx);
        _ = try validateVerticalMetricsTables(self.data, self.glyph_count, vhea, vmtx);
        return try readMetricHeaderInfo(self.data, vhea);
    }

    /// Enumerate parsed cmap encoding records, similar to FreeType charmaps.
    ///
    /// The array is caller-owned. Each entry describes a validated cmap subtable
    /// using absolute offsets into the borrowed font bytes, matching `tables()`
    /// and `tableData()` rather than table-relative child offsets.
    pub fn charmaps(self: *const Font, allocator: std.mem.Allocator) FontError![]CharmapInfo {
        for (self.cmap_subtables) |subtable| try self.validateCmapLookupSubtable(subtable);

        const infos = try allocator.alloc(CharmapInfo, self.cmap_subtables.len);
        errdefer allocator.free(infos);
        for (infos, self.cmap_subtables) |*info, subtable| {
            info.* = try self.charmapInfoForSubtable(subtable);
        }
        return infos;
    }

    /// Return the cmap Cangjie will use for `glyphIndex`, after lazy validation.
    pub fn defaultCharmap(self: *const Font) FontError!?CharmapInfo {
        const subtable = self.selectedCmapSubtable() orelse return null;
        try self.validateCmapLookupSubtable(subtable);
        return try self.charmapInfoForSubtable(subtable);
    }

    /// Map a Unicode scalar with a caller-selected charmap.
    ///
    /// This mirrors FreeType-style explicit charmap selection while preserving
    /// Cangjie's Unicode-scalar public contract. Format 14 variation-selector
    /// charmaps are intentionally rejected here because they are not standalone
    /// scalar-to-glyph maps; use `variationGlyphIndex` for those records.
    pub fn glyphIndexWithCharmap(self: *const Font, charmap: CharmapInfo, codepoint: u21) FontError!glyph_mod.GlyphId {
        try validatePublicUnicodeScalar(codepoint);
        const subtable = try self.subtableForCharmap(charmap);
        if (!cmapSubtableSupportsGlyphLookup(subtable.format)) return error.UnsupportedCmap;
        return try self.glyphIndexInSubtable(subtable, codepoint);
    }

    /// Return the first non-missing mapping in a selected charmap.
    pub fn firstCharmapMapping(self: *const Font, charmap: CharmapInfo) FontError!?CharmapMapping {
        return try self.nextMappingAfter(charmap, null);
    }

    /// Return the next non-missing mapping after `codepoint` in a selected charmap.
    pub fn nextCharmapMapping(self: *const Font, charmap: CharmapInfo, codepoint: u21) FontError!?CharmapMapping {
        try validatePublicUnicodeScalar(codepoint);
        return try self.nextMappingAfter(charmap, codepoint);
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
        try validatePublicUnicodeScalar(codepoint);
        const chosen = self.selectedCmapSubtable() orelse return error.UnsupportedCmap;
        return try self.glyphIndexInSubtable(chosen, codepoint);
    }

    fn nextMappingAfter(self: *const Font, charmap: CharmapInfo, after: ?u21) FontError!?CharmapMapping {
        const subtable = try self.subtableForCharmap(charmap);
        if (!cmapSubtableSupportsGlyphLookup(subtable.format)) return error.UnsupportedCmap;
        try self.validateCmapLookupSubtable(subtable);
        if (isMacintoshRomanSubtable(subtable)) {
            return try self.nextMacintoshRomanMappingAfter(subtable, after);
        }
        return try cmap_iter.next(self.data, subtable.offset, subtable.length, subtable.format, after);
    }

    fn glyphIndexInSubtable(self: *const Font, subtable: CmapSubtable, codepoint: u21) FontError!glyph_mod.GlyphId {
        try self.validateCmapLookupSubtable(subtable);
        const mapped_codepoint: u21 = if (isMacintoshRomanSubtable(subtable))
            macintosh_encoding.unicodeToRomanByte(
                codepoint,
                (try readCmapLanguage(self.data, subtable.offset, subtable.length, subtable.format)) orelse 0,
            ) orelse return 0
        else
            codepoint;
        return try self.glyphIndexInValidatedSubtable(subtable, mapped_codepoint);
    }

    fn glyphIndexInValidatedSubtable(self: *const Font, subtable: CmapSubtable, codepoint: u21) FontError!glyph_mod.GlyphId {
        return switch (subtable.format) {
            0 => try glyphIndexFormat0(self.data, subtable.offset, codepoint),
            2 => try glyphIndexFormat2(self.data, subtable.offset, subtable.length, codepoint),
            4 => try glyphIndexFormat4(self.data, subtable.offset, codepoint),
            6 => try glyphIndexFormat6(self.data, subtable.offset, codepoint),
            8 => try glyphIndexFormat8(self.data, subtable.offset, subtable.length, codepoint),
            10 => try glyphIndexFormat10(self.data, subtable.offset, subtable.length, codepoint),
            12 => try glyphIndexFormat12(self.data, subtable.offset, subtable.length, codepoint),
            13 => try glyphIndexFormat13(self.data, subtable.offset, subtable.length, codepoint),
            else => error.UnsupportedCmap,
        };
    }

    fn nextMacintoshRomanMappingAfter(self: *const Font, subtable: CmapSubtable, after: ?u21) FontError!?CharmapMapping {
        const language = (try readCmapLanguage(self.data, subtable.offset, subtable.length, subtable.format)) orelse 0;
        var best: ?CharmapMapping = null;
        for (0..0x100) |raw_code| {
            const codepoint = macintosh_encoding.romanByteToUnicode(@intCast(raw_code), language);
            if (after) |previous| {
                if (codepoint <= previous) continue;
            }
            const glyph_id = try self.glyphIndexInValidatedSubtable(subtable, @intCast(raw_code));
            if (glyph_id == 0) continue;
            if (best == null or codepoint < best.?.codepoint) {
                best = .{ .codepoint = codepoint, .glyph_id = glyph_id };
            }
        }
        return best;
    }

    fn subtableForCharmap(self: *const Font, charmap: CharmapInfo) FontError!CmapSubtable {
        for (self.cmap_subtables) |subtable| {
            if (subtable.platform_id == charmap.platform_id and
                subtable.encoding_id == charmap.encoding_id and
                subtable.format == charmap.format and
                subtable.offset == charmap.offset and
                subtable.length == charmap.length)
            {
                const current = try self.charmapInfoForSubtable(subtable);
                if (current.language != charmap.language) return error.BadSfnt;
                return subtable;
            }
        }
        return error.BadSfnt;
    }

    fn selectedCmapSubtable(self: *const Font) ?CmapSubtable {
        var best: ?CmapSubtable = null;
        for (self.cmap_subtables) |subtable| {
            if (!cmapSubtableSupportsGlyphLookup(subtable.format)) continue;
            if (best == null or scoreCmap(subtable) > scoreCmap(best.?)) best = subtable;
        }
        return best;
    }

    fn charmapInfoForSubtable(self: *const Font, subtable: CmapSubtable) FontError!CharmapInfo {
        return .{
            .platform_id = subtable.platform_id,
            .encoding_id = subtable.encoding_id,
            .format = subtable.format,
            .offset = subtable.offset,
            .length = subtable.length,
            .language = try readCmapLanguage(self.data, subtable.offset, subtable.length, subtable.format),
        };
    }

    fn validateCmapLookupSubtable(self: *const Font, subtable: CmapSubtable) FontError!void {
        const relative_offset = try tableRelativeOffset(self.cmap, subtable.offset);
        if (subtable.length > self.cmap.length - relative_offset) return error.BadSfnt;
        try sfnt.checksum.validate(self.data, self.cmap);
        try validateCachedCmapEncodingRecord(self.data, self.cmap, subtable, relative_offset);
        const format = try bin.readU16At(self.data, subtable.offset);
        if (format != subtable.format) return error.BadSfnt;
        const length = try cmapSubtableLength(self.data, self.cmap, relative_offset, format);
        if (length != subtable.length) return error.BadSfnt;

        // Font keeps borrowed SFNT bytes and cached cmap directory entries.
        // Re-running the checksum, directory, structural, and maxp glyph-id
        // checks before lookup prevents post-parse byte mutations from
        // returning a glyph id that the originally validated cmap could not
        // have produced.
        try validateCmapSubtable(self.data, subtable.offset, subtable.length, subtable.format, subtable.platform_id, subtable.encoding_id);
        try validateCmapGlyphIds(self.data, subtable.offset, subtable.length, subtable.format, self.glyph_count);
    }

    /// Read validated horizontal device metrics from the optional SFNT `hdmx` table.
    pub fn hdmxInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?HdmxInfo {
        const hdmx = self.hdmx orelse return null;
        try sfnt.checksum.validate(self.data, hdmx);
        try validateHdmxTable(self.data, hdmx, self.glyph_count);
        return try readHdmxInfo(allocator, self.data, hdmx, self.glyph_count);
    }

    pub fn freeHdmxInfo(_: *const Font, allocator: std.mem.Allocator, info: HdmxInfo) void {
        for (info.records) |record| allocator.free(record.widths);
        allocator.free(info.records);
    }

    pub fn hdmxWidth(self: *const Font, ppem: u8, glyph_id: glyph_mod.GlyphId) FontError!?u8 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const hdmx = self.hdmx orelse return null;
        try sfnt.checksum.validate(self.data, hdmx);
        try validateHdmxTable(self.data, hdmx, self.glyph_count);
        return try readHdmxWidth(self.data, hdmx, self.glyph_count, ppem, glyph_id);
    }

    /// Read validated linear-threshold metrics from the optional SFNT `LTSH` table.
    pub fn ltshInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?LtshInfo {
        const ltsh = self.ltsh orelse return null;
        try sfnt.checksum.validate(self.data, ltsh);
        try validateLtshTable(self.data, ltsh, self.glyph_count);
        return try readLtshInfo(allocator, self.data, ltsh, self.glyph_count);
    }

    pub fn freeLtshInfo(_: *const Font, allocator: std.mem.Allocator, info: LtshInfo) void {
        allocator.free(info.thresholds);
    }

    pub fn linearThreshold(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?u8 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const ltsh = self.ltsh orelse return null;
        try sfnt.checksum.validate(self.data, ltsh);
        try validateLtshTable(self.data, ltsh, self.glyph_count);
        return self.data[ltsh.offset + 4 + glyph_id];
    }

    /// Expand the SFNT `hmtx` table into one metric record per glyph.
    pub fn horizontalMetricsTable(self: *const Font, allocator: std.mem.Allocator) FontError![]HorizontalMetricInfo {
        const metric_count = try self.validateHorizontalMetricsForRead();
        const hmtx = self.hmtx orelse return error.MissingTable;
        const metrics = try allocator.alloc(HorizontalMetricInfo, self.glyph_count);
        errdefer allocator.free(metrics);
        for (metrics, 0..) |*metric, glyph_index| {
            metric.* = try readHorizontalMetricAt(self.data, hmtx, metric_count, @intCast(glyph_index));
        }
        return metrics;
    }

    fn validateHorizontalMetricsForRead(self: *const Font) FontError!u16 {
        const hhea = self.hhea orelse return error.MissingTable;
        const hmtx = self.hmtx orelse return error.MissingTable;
        const current_metric_count = try validateHorizontalMetricsTables(self.data, hhea, hmtx, self.glyph_count);
        if (current_metric_count != self.number_of_h_metrics) return error.InvalidMetrics;
        try sfnt.checksum.validate(self.data, hhea);
        try sfnt.checksum.validate(self.data, hmtx);
        return current_metric_count;
    }

    /// Return horizontal metrics following the hmtx compression rule: glyphs
    /// after `numberOfHMetrics` reuse the last advance width and provide only a
    /// per-glyph left side bearing.
    pub fn horizontalMetrics(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!HorizontalMetricInfo {
        // Horizontal metric tables are borrowed from caller-owned font bytes.
        // Revalidate the hhea/hmtx contract at this lazy API boundary so a
        // post-parse mutation cannot make the cached metric count reinterpret
        // malformed header bytes or read through a now-shortened hmtx record.
        return try self.horizontalMetricsForReadMode(glyph_id, .revalidate);
    }

    fn horizontalMetricsForReadMode(self: *const Font, glyph_id: glyph_mod.GlyphId, read_mode: OutlineReadMode) FontError!HorizontalMetricInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const hmtx = self.hmtx orelse return .{
            .advance_width = @intCast(@as(u32, self.units_per_em) / 2),
            .left_side_bearing = 0,
        };
        const metric_count = switch (read_mode) {
            .revalidate => try self.validateHorizontalMetricsForRead(),
            .parsed => self.number_of_h_metrics,
        };
        return try readHorizontalMetricAt(self.data, hmtx, metric_count, glyph_id);
    }

    pub fn hasVerticalMetrics(self: *const Font) bool {
        return sfnt.find(self.owned_tables, "vhea") != null and sfnt.find(self.owned_tables, "vmtx") != null;
    }

    /// Expand the optional SFNT `vmtx` table into one metric record per glyph.
    pub fn verticalMetricsTable(self: *const Font, allocator: std.mem.Allocator) FontError!?[]VerticalMetricInfo {
        const context = try self.verticalMetricTablesForRead();
        const metric_count = context.metric_count orelse return null;
        const metrics = try allocator.alloc(VerticalMetricInfo, self.glyph_count);
        errdefer allocator.free(metrics);
        for (metrics, 0..) |*metric, glyph_index| {
            metric.* = try readVerticalMetricAt(self.data, context.vmtx.?, metric_count, @intCast(glyph_index));
        }
        return metrics;
    }

    const VerticalMetricReadContext = struct {
        vhea: ?TableRecord,
        vmtx: ?TableRecord,
        metric_count: ?u16,
    };

    fn verticalMetricTablesForRead(self: *const Font) FontError!VerticalMetricReadContext {
        const vhea = sfnt.find(self.owned_tables, "vhea") orelse {
            if (sfnt.find(self.owned_tables, "vmtx") != null) return error.InvalidMetrics;
            return .{ .vhea = null, .vmtx = null, .metric_count = null };
        };
        const vmtx = sfnt.find(self.owned_tables, "vmtx") orelse return error.InvalidMetrics;
        const metric_count = (try validateVerticalMetricsTables(self.data, self.glyph_count, vhea, vmtx)) orelse return .{ .vhea = null, .vmtx = null, .metric_count = null };
        try sfnt.checksum.validate(self.data, vhea);
        try sfnt.checksum.validate(self.data, vmtx);
        return .{ .vhea = vhea, .vmtx = vmtx, .metric_count = metric_count };
    }

    /// Return vertical metrics following the vmtx compression rule. Fonts
    /// without a paired vhea/vmtx table return null; malformed or post-parse
    /// mutated vertical metrics report InvalidMetrics instead of falling back
    /// to horizontal advances.
    pub fn verticalMetrics(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?VerticalMetrics {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const context = try self.verticalMetricTablesForRead();
        const metric_count = context.metric_count orelse return null;
        const metric = try readVerticalMetricAt(self.data, context.vmtx.?, metric_count, glyph_id);
        return .{ .advance_height = metric.advance_height, .top_side_bearing = metric.top_side_bearing };
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
        try validatePublicUnicodeScalar(codepoint);
        try validatePublicVariationSelector(variation_selector);
        for (self.cmap_subtables) |subtable| {
            if (subtable.format != 14) continue;
            try self.validateCmapLookupSubtable(subtable);
            if (try glyphIndexFormat14(self, subtable.offset, subtable.length, codepoint, variation_selector)) |glyph_id| return glyph_id;
        }
        return null;
    }

    /// Enumerate Unicode variation selectors advertised by cmap format 14.
    pub fn variationSelectors(self: *const Font, allocator: std.mem.Allocator) FontError![]u21 {
        const subtable = self.variationSelectorSubtable() orelse return try allocator.alloc(u21, 0);
        try self.validateCmapLookupSubtable(subtable);
        return try cmap_variation.selectors(allocator, self.data, subtable.offset, subtable.length);
    }

    /// Enumerate selectors that define a default or non-default sequence for a codepoint.
    pub fn variationSelectorsForCodepoint(self: *const Font, allocator: std.mem.Allocator, codepoint: u21) FontError![]u21 {
        try validatePublicUnicodeScalar(codepoint);
        const subtable = self.variationSelectorSubtable() orelse return try allocator.alloc(u21, 0);
        try self.validateCmapLookupSubtable(subtable);
        return try cmap_variation.selectorsForCodepoint(allocator, self.data, subtable.offset, subtable.length, codepoint);
    }

    /// Enumerate base codepoints that are defined for a variation selector.
    pub fn variationCodepointsForSelector(self: *const Font, allocator: std.mem.Allocator, variation_selector: u21) FontError![]u21 {
        try validatePublicVariationSelector(variation_selector);
        const subtable = self.variationSelectorSubtable() orelse return try allocator.alloc(u21, 0);
        try self.validateCmapLookupSubtable(subtable);
        return try cmap_variation.codepointsForSelector(allocator, self.data, subtable.offset, subtable.length, variation_selector);
    }

    /// Classify a Unicode variation sequence as default, non-default, or absent.
    pub fn variationSequenceKind(self: *const Font, codepoint: u21, variation_selector: u21) FontError!?VariationSequenceKind {
        try validatePublicUnicodeScalar(codepoint);
        try validatePublicVariationSelector(variation_selector);
        const subtable = self.variationSelectorSubtable() orelse return null;
        try self.validateCmapLookupSubtable(subtable);
        return try cmap_variation.sequenceKind(self.data, subtable.offset, subtable.length, codepoint, variation_selector);
    }

    fn variationSelectorSubtable(self: *const Font) ?CmapSubtable {
        for (self.cmap_subtables) |subtable| {
            if (subtable.format == 14) return subtable;
        }
        return null;
    }

    pub fn kerning(self: *const Font, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        // `kern` data is validated against maxp at parse time, but callers can
        // still pass arbitrary glyph IDs into this public API. Reject invalid
        // inputs before table dispatch so "no matching pair" cannot mask a
        // glyph-id contract violation, even for fonts without a kern table.
        if (left >= self.glyph_count or right >= self.glyph_count) return error.InvalidGlyph;
        const kern = self.kern orelse return 0;
        // `kern` table records cache only offsets into caller-owned SFNT bytes.
        // Re-run the parse-time pair-array validation before each lazy kerning
        // read so post-parse mutations cannot introduce dangling glyph IDs or
        // unsorted format-0 records that binary search would otherwise observe
        // as an innocuous "no pair" result.
        try sfnt.checksum.validate(self.data, kern);
        try validateKernTable(self.data, kern, self.glyph_count);
        if (kern.length < 4) return 0;
        const version = try bin.readU32At(self.data, kern.offset);
        if (version == 0x00010000) {
            return try appleKernKerning(self.data, kern, left, right);
        }
        if ((version >> 16) != 0) return 0;
        return try legacyKernKerning(self.data, kern, left, right);
    }

    fn kernLookupForShaping(self: *const Font) FontError!KernLookupForShaping {
        const kern = self.kern;
        if (kern) |kern_table| try sfnt.checksum.validate(self.data, kern_table);
        return .{ .font = self, .kern = kern };
    }

    fn kerxLookupForShaping(self: *const Font) FontError!?KerxLookupForShaping {
        const kerx = self.kerx orelse return null;
        try sfnt.checksum.validate(self.data, kerx);
        return .{ .font = self, .kerx = kerx };
    }

    /// Read validated metadata from the optional SFNT `kern` table.
    pub fn kernInfo(self: *const Font, allocator: std.mem.Allocator) FontError!?KernInfo {
        const kern = self.kern orelse return null;
        try sfnt.checksum.validate(self.data, kern);
        try validateKernTable(self.data, kern, self.glyph_count);
        return try readKernInfo(allocator, self.data, kern);
    }

    pub fn freeKernInfo(_: *const Font, allocator: std.mem.Allocator, info: KernInfo) void {
        allocator.free(info.subtables);
    }

    fn legacyKernKerning(data: []const u8, kern: TableRecord, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!i16 {
        const table_count = try bin.readU16At(data, kern.offset + 2);
        const table_end = kern.offset + kern.length;
        var subtable_offset = kern.offset + 4;
        var total: i32 = 0;
        var saw_matching_pair = false;
        for (0..table_count) |_| {
            if (subtable_offset > table_end or table_end - subtable_offset < 6) return error.BadSfnt;
            const subtable_version = try bin.readU16At(data, subtable_offset);
            const length = try bin.readU16At(data, subtable_offset + 2);
            const coverage = try bin.readU16At(data, subtable_offset + 4);
            if (length < 6 or length > table_end - subtable_offset) return error.BadSfnt;
            if (subtable_version != 0) return error.BadSfnt;
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
            if (!vertical and !cross_stream and !variation) {
                const body = data[subtable_offset + 8 .. subtable_offset + length];
                const value = if (format == 0)
                    // AAT subtables have an eight-byte common header (including
                    // tupleIndex) before the same format-0 pair-search payload.
                    try kernFormat0Body(body, left, right)
                else if (format == 2)
                    try kernFormat2Body(body, left, right)
                else
                    null;
                if (value) |kern_value| {
                    saw_matching_pair = true;
                    total += kern_value;
                }
            }
            subtable_offset += length;
        }
        if (!saw_matching_pair) return 0;
        return @intCast(std.math.clamp(total, std.math.minInt(i16), std.math.maxInt(i16)));
    }

    fn applyGsub(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator) FontError!void {
        return try self.applyGsubWithOptions(glyphs, allocator, .{});
    }

    /// Apply GSUB to a mutable glyph-id stream. GDEF glyph classes are expanded
    /// into a dense temporary array so lookup flags can skip bases, ligatures,
    /// or marks consistently across all lookup formats.
    fn applyGsubWithOptions(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        // Font objects borrow caller-owned SFNT bytes. Re-run the parse-time
        // GSUB glyph-bound walk before shaping so a post-parse mutation cannot
        // smuggle an out-of-range substitution result into the glyph stream.
        try sfnt.checksum.validate(self.data, gsub);
        try gsub_mod.validateGlyphBoundsForShaping(self.data, gsub.offset, gsub.length, self.glyph_count);
        var gdef_metadata = try self.gdefLookupMetadataForShaping(allocator);
        defer gdef_metadata.deinit(allocator);
        try self.applyGsubWithOptionsUsingGdef(glyphs, allocator, options, gdef_metadata);
    }

    fn applyGsubWithOptionsUsingGdef(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try gsub_mod.validateGlyphBoundsForShaping(self.data, gsub.offset, gsub.length, self.glyph_count);
        try self.applyGsubWithOptionsUsingGdefForShaping(glyphs, allocator, options, gdef_metadata);
        // A single public GSUB call is a complete shaping boundary. Internal
        // staged shapers use the narrower `ForShaping` entry point so modulo
        // SingleSubst intermediates may survive only until their next stage.
        try self.validateGlyphRun(glyphs.items);
    }

    fn applyGsubWithOptionsUsingGdefForShaping(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        // Font.parse already walked all supported GSUB glyph references. The
        // layout hot path may shape many small runs from the same validated
        // font, so repeat only the borrowed-table checksum proof here instead
        // of rewalking every lookup for every text node.
        try sfnt.checksum.validate(self.data, gsub);
        try self.applyGsubWithOptionsUsingGdefAfterProof(glyphs, allocator, options, gdef_metadata);
    }

    fn proveGsubTableForShaping(self: *const Font) FontError!void {
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
    }

    /// Select the concrete OpenType Layout ScriptList tag for a Unicode script.
    ///
    /// The returned tag is font-dependent: Indic scripts can choose v3, v2,
    /// or legacy entries, and the chosen generation determines which shaping
    /// engine is valid. Explicit caller tags bypass candidate expansion.
    fn selectLayoutScriptForShaping(
        self: *const Font,
        table_record: ?TableRecord,
        script: unicode_mod.Script,
        explicit_tag: ?unicode_mod.OpenTypeScriptTag,
    ) FontError!LayoutScriptSelection {
        const record = table_record orelse return .{};
        try sfnt.checksum.validate(self.data, record);
        return self.selectLayoutScriptAfterProof(record, script, explicit_tag);
    }

    /// Select from a layout table whose borrowed payload checksum was already
    /// proved by the caller. GSUB needs this boundary because HarfBuzz accepts
    /// the all-null ten-byte header as an empty table, so it must inspect that
    /// topology before entering the generic ScriptList parser without hashing
    /// every ordinary GSUB table twice.
    fn selectLayoutScriptAfterProof(
        self: *const Font,
        record: TableRecord,
        script: unicode_mod.Script,
        explicit_tag: ?unicode_mod.OpenTypeScriptTag,
    ) FontError!LayoutScriptSelection {
        const table = self.data[record.offset .. record.offset + record.length];

        var tag_buf: [3]u32 = undefined;
        const requested_tags = if (explicit_tag) |value| tags: {
            tag_buf[0] = @intFromEnum(value);
            break :tags tag_buf[0..1];
        } else tags: {
            const candidates = unicode_mod.openTypeScriptTagCandidates(script);
            for (candidates.slice(), 0..) |candidate, index| {
                tag_buf[index] = @intFromEnum(candidate);
            }
            break :tags tag_buf[0..candidates.len];
        };
        const selection = ot_layout.selectScriptTag(table, requested_tags) catch |err| switch (err) {
            error.EndOfStream, error.InvalidLayoutTable => return error.BadSfnt,
        };
        return .{
            .tag = if (selection.tag) |tag_value| std.enums.fromInt(unicode_mod.OpenTypeScriptTag, tag_value) else null,
            .requested = selection.requested,
        };
    }

    fn selectGsubScriptForShaping(
        self: *const Font,
        script: unicode_mod.Script,
        explicit_tag: ?unicode_mod.OpenTypeScriptTag,
    ) FontError!LayoutScriptSelection {
        const gsub = self.gsub orelse return .{};
        try sfnt.checksum.validate(self.data, gsub);
        // Some deployed fonts contain only the version and three null top-level
        // GSUB offsets. HarfBuzz treats that exact topology as an inert table;
        // routing it through the generic selector would interpret version bytes
        // as a ScriptList and reject an otherwise usable GPOS table.
        if (try gsub_mod.isEmptyTable(self.data, gsub.offset, gsub.length)) return .{};
        return self.selectLayoutScriptAfterProof(gsub, script, explicit_tag);
    }

    fn selectGposScriptForShaping(
        self: *const Font,
        script: unicode_mod.Script,
        explicit_tag: ?unicode_mod.OpenTypeScriptTag,
    ) FontError!LayoutScriptSelection {
        return self.selectLayoutScriptForShaping(self.gpos, script, explicit_tag);
    }

    fn applyGsubWithOptionsUsingGdefAfterProof(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applyWithOptions(self.data, gsub.offset, gsub.length, glyphs, allocator, gsub_options);
    }

    /// Internal layout fast path for an exact cached GSUB lookup selection.
    ///
    /// The caller owns the table proof and glyph/source metadata proof; the
    /// callee returns false without mutation when those cache artifacts cannot
    /// establish the narrower trusted-executor contract.
    noinline fn applyGsubCachedLookupSelectionUsingGdefAfterRunProof(
        self: *const Font,
        glyphs: *std.ArrayList(glyph_mod.GlyphId),
        allocator: std.mem.Allocator,
        options: gsub_mod.LookupOptions,
        gdef_metadata: GdefLookupMetadata,
    ) linksection(shaping_sections.isolated_hotpaths) FontError!bool {
        const gsub = self.gsub orelse return true;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.applyCachedLookupSelectionWithOptionsAfterMetadataProof(
            self.data,
            gsub.offset,
            gsub.length,
            glyphs,
            allocator,
            gsub_options,
        );
    }

    fn selectGsubLookupsForShaping(self: *const Font, allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError![]u16 {
        const gsub = self.gsub orelse return try allocator.alloc(u16, 0);
        try sfnt.checksum.validate(self.data, gsub);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.selectedLookupIndicesForOptions(self.data, gsub.offset, gsub.length, allocator, gsub_options);
    }

    fn selectGsubFeatureLookupsAfterProof(
        self: *const Font,
        allocator: std.mem.Allocator,
        feature_tag: u32,
        options: gsub_mod.LookupOptions,
        gdef_metadata: GdefLookupMetadata,
    ) FontError![]u16 {
        const gsub = self.gsub orelse return try allocator.alloc(u16, 0);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.selectedFeatureLookupIndicesForOptions(
            self.data,
            gsub.offset,
            gsub.length,
            feature_tag,
            allocator,
            gsub_options,
        );
    }

    fn applyGsubSelectedSourceFeatureAfterProof(
        self: *const Font,
        selected_lookups: []const u16,
        source_feature: u32,
        feature_value: u32,
        glyphs: *std.ArrayList(glyph_mod.GlyphId),
        allocator: std.mem.Allocator,
        options: gsub_mod.LookupOptions,
        gdef_metadata: GdefLookupMetadata,
    ) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applySelectedSourceFeatureWithOptions(
            self.data,
            gsub.offset,
            gsub.length,
            selected_lookups,
            source_feature,
            feature_value,
            glyphs,
            allocator,
            gsub_options,
        );
    }

    fn hasGsubFeatureForShaping(self: *const Font, feature_tag: u32) FontError!bool {
        const gsub = self.gsub orelse return false;
        try sfnt.checksum.validate(self.data, gsub);
        return try gsub_mod.hasFeature(self.data, gsub.offset, gsub.length, feature_tag);
    }

    fn hasGsubRandomFeatureWithAcceleratorsForShaping(self: *const Font, accelerators: []const gsub_mod.LookupAccelerator) ?bool {
        const gsub = self.gsub orelse return false;
        return gsub_mod.hasRandomFeatureWithAccelerators(self.data, gsub.offset, gsub.length, accelerators);
    }

    fn gsubLookupAcceleratorsForShaping(self: *const Font, allocator: std.mem.Allocator) FontError![]gsub_mod.LookupAccelerator {
        const gsub = self.gsub orelse return try allocator.alloc(gsub_mod.LookupAccelerator, 0);
        try sfnt.checksum.validate(self.data, gsub);
        return try gsub_mod.buildLookupAccelerators(self.data, gsub.offset, gsub.length, allocator);
    }

    fn gsubFeatureLookupPlanForShaping(self: *const Font, allocator: std.mem.Allocator, applications: []const gsub_mod.FeatureApplication, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!gsub_mod.FeatureLookupPlan {
        const gsub = self.gsub orelse return .{ .entries = try allocator.alloc(gsub_mod.FeatureLookupPlanEntry, 0) };
        try sfnt.checksum.validate(self.data, gsub);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.buildFeatureLookupPlan(self.data, gsub.offset, gsub.length, applications, allocator, gsub_options);
    }

    fn gsubMergedFeatureLookupPlanForShaping(self: *const Font, allocator: std.mem.Allocator, applications: []const gsub_mod.FeatureApplication, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!gsub_mod.MergedFeatureLookupPlan {
        const gsub = self.gsub orelse return .{
            .lookups = try allocator.alloc(gsub_mod.MergedFeatureLookup, 0),
            .lookup_offsets = try allocator.alloc(usize, 0),
        };
        try sfnt.checksum.validate(self.data, gsub);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.buildMergedFeatureLookupPlan(self.data, gsub.offset, gsub.length, applications, allocator, gsub_options);
    }

    fn applyGsubFeatureWithOptions(self: *const Font, feature_tag: u32, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        return try self.applyGsubFeatureSequenceWithOptions(&.{.{ .tag = feature_tag }}, glyphs, allocator, options);
    }

    fn applyGsubSourceFeatureWithOptions(self: *const Font, feature_tag: u32, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        return try self.applyGsubFeatureSequenceWithOptions(&.{.{ .tag = feature_tag, .source_scoped = true }}, glyphs, allocator, options);
    }

    fn applyGsubFeatureSequenceWithOptions(self: *const Font, applications: []const gsub_mod.FeatureApplication, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try gsub_mod.validateGlyphBoundsForShaping(self.data, gsub.offset, gsub.length, self.glyph_count);
        var gdef_metadata = try self.gdefLookupMetadataForShaping(allocator);
        defer gdef_metadata.deinit(allocator);
        try self.applyGsubFeatureSequenceWithOptionsUsingGdef(applications, glyphs, allocator, options, gdef_metadata);
    }

    fn applyGsubFeatureSequenceWithOptionsUsingGdef(self: *const Font, applications: []const gsub_mod.FeatureApplication, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try gsub_mod.validateGlyphBoundsForShaping(self.data, gsub.offset, gsub.length, self.glyph_count);
        try self.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(applications, glyphs, allocator, options, gdef_metadata);
        try self.validateGlyphRun(glyphs.items);
    }

    fn applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(self: *const Font, applications: []const gsub_mod.FeatureApplication, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try self.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(applications, glyphs, allocator, options, gdef_metadata);
    }

    fn applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(self: *const Font, applications: []const gsub_mod.FeatureApplication, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applyFeatureSequenceWithOptions(self.data, gsub.offset, gsub.length, applications, glyphs, allocator, gsub_options);
    }

    fn applyGsubFeatureLookupPlanUsingGdefAfterProof(self: *const Font, plan: gsub_mod.FeatureLookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applyFeatureLookupPlanWithOptions(self.data, gsub.offset, gsub.length, plan, glyphs, allocator, gsub_options);
    }

    /// Continue an internal multi-stage shaping run after its glyph/source
    /// metadata was validated by the first stage. SingleSubst format 1 may
    /// temporarily leave maxp's renderable range before a later lookup maps the
    /// ID back, so this boundary proves metadata cardinality rather than final
    /// glyph bounds. The complete shaper validates the run before GPOS/metrics.
    /// Keep this narrower than the public defensive entry point above: callers
    /// must not pass a freshly constructed or externally mutated glyph run.
    fn applyGsubFeatureLookupPlanUsingGdefAfterRunProof(self: *const Font, plan: gsub_mod.FeatureLookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applyFeatureLookupPlanWithOptionsAfterMetadataProof(
            self.data,
            gsub.offset,
            gsub.length,
            plan,
            glyphs,
            allocator,
            gsub_options,
        );
    }

    fn applyGsubMergedFeatureLookupPlanUsingGdefAfterProof(self: *const Font, plan: gsub_mod.MergedFeatureLookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applyMergedFeatureLookupPlanWithOptions(self.data, gsub.offset, gsub.length, plan, glyphs, allocator, gsub_options);
    }

    fn applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof(self: *const Font, plan: gsub_mod.MergedFeatureLookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.applyMergedFeatureLookupPlanWithOptionsAfterMetadataProof(
            self.data,
            gsub.offset,
            gsub.length,
            plan,
            glyphs,
            allocator,
            gsub_options,
        );
    }

    fn collectGposAdjustments(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator) FontError!void {
        return try self.collectGposAdjustmentsWithOptions(glyphs, adjustments, allocator, .{});
    }

    /// Collect GPOS placement/advance deltas for a shaped glyph stream. The
    /// returned adjustments use glyph indices in the post-GSUB stream, which is
    /// the same coordinate space used by `layout.shapeSegmentInto`.
    fn collectGposAdjustmentsWithOptions(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator, options: gpos_mod.LookupOptions) FontError!void {
        try self.validateGlyphRun(glyphs);
        const gpos = self.gpos orelse return;
        // GPOS data is likewise borrowed. Validate latent PairPos/SinglePos
        // glyph references on every public positioning pass instead of only at
        // Font.parse time, keeping malformed replacement bytes from hiding in
        // unvisited lookups until a specific feature or glyph run reaches them.
        try sfnt.checksum.validate(self.data, gpos);
        try gpos_mod.validateGlyphBounds(self.data, gpos.offset, gpos.length, self.glyph_count);
        var gdef_metadata = try self.gdefLookupMetadataForShaping(allocator);
        defer gdef_metadata.deinit(allocator);
        try self.collectGposAdjustmentsWithOptionsUsingGdef(glyphs, adjustments, allocator, options, gdef_metadata);
    }

    fn collectGposAdjustmentsWithOptionsUsingGdef(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator, options: gpos_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs);
        const gpos = self.gpos orelse return;
        try sfnt.checksum.validate(self.data, gpos);
        try gpos_mod.validateGlyphBounds(self.data, gpos.offset, gpos.length, self.glyph_count);
        try self.collectGposAdjustmentsWithOptionsUsingGdefForShaping(glyphs, adjustments, allocator, options, gdef_metadata);
    }

    fn collectGposAdjustmentsWithOptionsUsingGdefForShaping(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator, options: gpos_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs);
        const gpos = self.gpos orelse return;
        try sfnt.checksum.validate(self.data, gpos);
        try self.collectGposAdjustmentsWithOptionsUsingGdefAfterProof(glyphs, adjustments, allocator, options, gdef_metadata);
    }

    fn proveGposTableForShaping(self: *const Font) FontError!void {
        const gpos = self.gpos orelse return;
        try sfnt.checksum.validate(self.data, gpos);
    }

    /// Report whether this face has an OpenType positioning table.
    ///
    /// Shape-plan decisions sometimes depend on the presence of GPOS even when
    /// no lookup matches the current run. Keep that distinction separate from
    /// an empty adjustment result, and avoid re-reading the SFNT directory on
    /// every glyph while final positions are assembled.
    fn hasGposTableForShaping(self: *const Font) bool {
        return self.gpos != null;
    }

    fn hasGsubTableForShaping(self: *const Font) bool {
        return self.gsub != null;
    }

    fn hasKerxTableForShaping(self: *const Font) bool {
        return self.kerx != null;
    }

    fn hasMorxTableForShaping(self: *const Font) bool {
        return self.morx != null;
    }

    fn hasAatSubstitutionForShaping(self: *const Font) bool {
        return self.morx != null or self.mort != null;
    }

    fn applyAatSubstitutionForShaping(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        if (self.morx != null) return try self.applyMorxForShaping(glyphs, allocator, options);
        try self.validateGlyphRun(glyphs.items);
        const mort = self.mort orelse return;
        try sfnt.checksum.validate(self.data, mort);
        try aat_mort.apply(allocator, self.data, mort.offset, mort.length, self.glyph_count, glyphs, options);
    }

    fn applyMorxForShaping(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.LookupOptions) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const morx = self.morx orelse return;
        try sfnt.checksum.validate(self.data, morx);
        try validateMorxTable(self.data, morx, self.glyph_count);
        try aat_morx.apply(allocator, self.data, morx.offset, morx.length, self.glyph_count, glyphs, options);
    }

    fn collectGposAdjustmentsWithOptionsUsingGdefAfterProof(self: *const Font, glyphs: []const glyph_mod.GlyphId, adjustments: *std.ArrayList(gpos_mod.Adjustment), allocator: std.mem.Allocator, options: gpos_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs);
        const gpos = self.gpos orelse return;
        var gpos_options = options;
        gpos_options.assume_validated = true;
        gdef_metadata.applyToGposOptions(&gpos_options);
        try gpos_mod.collectAdjustmentsWithOptions(self.data, gpos.offset, gpos.length, glyphs, adjustments, allocator, gpos_options);
    }

    fn selectGposLookupsForShaping(self: *const Font, allocator: std.mem.Allocator, options: gpos_mod.LookupOptions, gdef_metadata: GdefLookupMetadata) FontError![]u16 {
        const gpos = self.gpos orelse return try allocator.alloc(u16, 0);
        try sfnt.checksum.validate(self.data, gpos);
        var gpos_options = options;
        gpos_options.assume_validated = true;
        gdef_metadata.applyToGposOptions(&gpos_options);
        return try gpos_mod.selectedLookupIndicesForOptions(self.data, gpos.offset, gpos.length, allocator, gpos_options);
    }

    fn gposLookupAcceleratorsForShaping(self: *const Font, allocator: std.mem.Allocator) FontError![]gpos_mod.LookupAccelerator {
        const gpos = self.gpos orelse return try allocator.alloc(gpos_mod.LookupAccelerator, 0);
        try sfnt.checksum.validate(self.data, gpos);
        return try gpos_mod.buildLookupAccelerators(self.data, gpos.offset, gpos.length, allocator);
    }

    fn gdefLookupMetadataForShaping(self: *const Font, allocator: std.mem.Allocator) FontError!GdefLookupMetadata {
        return try self.gdefLookupMetadata(allocator);
    }

    fn gdefLookupMetadata(self: *const Font, allocator: std.mem.Allocator) FontError!GdefLookupMetadata {
        var metadata = GdefLookupMetadata{};
        errdefer metadata.deinit(allocator);
        const gdef = self.gdef orelse return metadata;

        // GSUB/GPOS lookup-flag filtering is on the shaping hot path. The
        // public glyphClass/markAttachClass APIs defensively revalidate GDEF on
        // every single glyph query; shaping only needs one call-boundary proof
        // for the already-parsed font before expanding dense metadata arrays.
        try sfnt.checksum.validate(self.data, gdef);
        const header_len = try validateGdefHeaderForLazyApi(self.data, gdef);
        const table = self.data[gdef.offset .. gdef.offset + gdef.length];

        const glyph_class_def_offset = try bin.readU16At(self.data, gdef.offset + 4);
        if (glyph_class_def_offset != 0) {
            try validateGdefChildOffset(glyph_class_def_offset, gdef.length, header_len);
            const classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(classes);
            try readClassDefDense(table, glyph_class_def_offset, self.glyph_count, classes, true);
            metadata.glyph_classes = classes;
        }

        const mark_attach_class_def_offset = try bin.readU16At(self.data, gdef.offset + 10);
        if (mark_attach_class_def_offset != 0) {
            try validateGdefChildOffset(mark_attach_class_def_offset, gdef.length, header_len);
            const attach_classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(attach_classes);
            try readClassDefDense(table, mark_attach_class_def_offset, self.glyph_count, attach_classes, false);
            metadata.mark_attach_classes = attach_classes;
        }

        if (try self.markFilteringSets(allocator)) |sets| {
            metadata.mark_filtering_sets = sets;
        }
        if (header_len >= 18) {
            const store_offset: usize = @intCast(try bin.readU32At(self.data, gdef.offset + 14));
            if (store_offset != 0) {
                // The metadata cache can outlive caller mutations to Font's
                // borrowed SFNT bytes. Dense classes and mark sets are already
                // owned; copy the relatively rare GDEF 1.3 table as well so
                // AnchorFormat3 variation evaluation has the same lifetime and
                // proof boundary rather than rereading mutable source bytes.
                const owned = try allocator.dupe(u8, table);
                metadata.variation_store_data = owned;
                metadata.variation_store = .{
                    .data = owned,
                    .table_offset = 0,
                    .table_length = owned.len,
                    .store_offset = store_offset,
                };
            }
        }
        return metadata;
    }

    fn validateGlyphRun(self: *const Font, glyphs: []const glyph_mod.GlyphId) FontError!void {
        for (glyphs) |glyph_id| {
            if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        }
    }

    /// Validate the final glyph stream at the boundary between substitution
    /// and all consumers that require concrete font glyphs. This remains an
    /// internal shaping API because callers must not treat transient GSUB IDs
    /// as renderable merely because they fit the 16-bit GlyphId type.
    fn validateShapedGlyphRunForShaping(self: *const Font, glyphs: []const glyph_mod.GlyphId) FontError!void {
        try self.validateGlyphRun(glyphs);
    }

    pub fn nameString(self: *const Font, name_id: NameId, out: []u8) FontError!?[]const u8 {
        const name = self.name orelse return null;
        try sfnt.checksum.validate(self.data, name);
        return try readNameString(self.data, name, @intFromEnum(name_id), out);
    }

    /// Enumerate raw SFNT name records in canonical table order.
    ///
    /// Each returned `NameRecordInfo.string` slice borrows from this Font's
    /// backing bytes and keeps the table's original encoding. Use
    /// `NameRecordInfo.decodeUtf8` when a UTF-8 presentation string is needed.
    /// The array itself is caller-owned and should be released with
    /// `allocator.free(records)`.
    pub fn nameRecords(self: *const Font, allocator: std.mem.Allocator) FontError![]NameRecordInfo {
        const name = self.name orelse return try allocator.alloc(NameRecordInfo, 0);
        try sfnt.checksum.validate(self.data, name);
        return try name_mod.records(allocator, self.data, nameTableView(name));
    }

    /// Enumerate OpenType 1.6+ language-tag records from a format-1 name table.
    ///
    /// Returned slices borrow from this Font's backing bytes and are UTF-16BE,
    /// matching FreeType's FT_SfntLangTag contract. Use
    /// `NameLanguageTagInfo.decodeUtf8` for a UTF-8 BCP 47 string. Format-0
    /// name tables and fonts without a name table return an empty array.
    pub fn nameLanguageTags(self: *const Font, allocator: std.mem.Allocator) FontError![]NameLanguageTagInfo {
        const name = self.name orelse return try allocator.alloc(NameLanguageTagInfo, 0);
        try sfnt.checksum.validate(self.data, name);
        return try name_mod.languageTags(allocator, self.data, nameTableView(name));
    }

    /// Decode the BCP 47 language tag associated with a format-1 name language ID.
    pub fn nameLanguageTag(self: *const Font, language_id: u16, out: []u8) FontError!?[]const u8 {
        const name = self.name orelse return null;
        try sfnt.checksum.validate(self.data, name);
        return try name_mod.languageTag(self.data, nameTableView(name), language_id, out);
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

    /// Read validated metadata from the optional SFNT `post` table.
    pub fn postInfo(self: *const Font) FontError!?PostInfo {
        const post = self.post orelse return null;
        try sfnt.checksum.validate(self.data, post);
        try validatePostTable(self.data, post, self.glyph_count, .{
            .custom_name_validation = .structural_only,
        });
        return try readPostInfo(self.data, post);
    }

    /// Read validated metadata from the optional SFNT `PCLT` table.
    pub fn pcltInfo(self: *const Font) FontError!?PcltInfo {
        const pclt = self.pclt orelse return null;
        try sfnt.checksum.validate(self.data, pclt);
        try validatePcltTable(self.data, pclt);
        return try readPcltInfo(self.data, pclt);
    }

    /// Return the PostScript glyph name advertised by the optional `post` table.
    ///
    /// The returned slice is borrowed either from static Macintosh standard-name
    /// storage or from the caller-owned SFNT bytes backing this Font. Because the
    /// SFNT bytes are borrowed, this revalidates the complete `post` table before
    /// every lookup so post-parse mutations cannot reinterpret malformed Pascal
    /// strings or glyph-name indexes as a valid public name.
    pub fn glyphName(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const post = self.post orelse return null;
        try sfnt.checksum.validate(self.data, post);
        try validatePostTable(self.data, post, self.glyph_count, .{
            .custom_name_validation = .allow_empty,
        });
        return try readPostGlyphName(self.data, post, glyph_id);
    }

    pub fn decorationMetrics(self: *const Font) FontError!FontDecorationMetrics {
        if (self.post) |post| {
            try sfnt.checksum.validate(self.data, post);
            try validatePostTable(self.data, post, self.glyph_count, .{
                .custom_name_validation = .structural_only,
            });
        }
        if (self.os2) |os2| {
            try sfnt.checksum.validate(self.data, os2);
            _ = try readOs2StyleAttributes(self.data, os2);
        }
        return try readFontDecorationMetrics(self.data, self.post, self.os2, self.units_per_em, self.ascender, self.descender);
    }

    pub fn scaledDecorationMetrics(self: *const Font, font_size: f32) FontError!ScaledFontDecorationMetrics {
        return (try self.decorationMetrics()).scale(font_size, self.units_per_em);
    }

    pub fn scriptMetrics(self: *const Font) FontError!?FontScriptMetrics {
        const os2 = self.os2 orelse return null;
        try sfnt.checksum.validate(self.data, os2);
        _ = try readOs2StyleAttributes(self.data, os2);
        return try readOs2ScriptMetrics(self.data, os2);
    }

    pub fn scaledScriptMetrics(self: *const Font, font_size: f32) FontError!?ScaledFontScriptMetrics {
        const metrics = (try self.scriptMetrics()) orelse return null;
        return metrics.scale(font_size, self.units_per_em);
    }

    pub fn hasStyleAttributes(self: *const Font) bool {
        return self.os2 != null;
    }

    /// Read the GDEF class definition for lookup-flag filtering.
    pub fn glyphClass(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!GlyphClass {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gdef = self.gdef orelse return .unclassified;
        try sfnt.checksum.validate(self.data, gdef);
        const header_len = try validateGdefHeaderForLazyApi(self.data, gdef);
        const glyph_class_def_offset = try bin.readU16At(self.data, gdef.offset + 4);
        if (glyph_class_def_offset == 0) return .unclassified;
        // Font owns only borrowed bytes. Re-check the same top-level child
        // offset contract enforced at parse time so post-parse mutations cannot
        // make GDEF public APIs reinterpret header fields as ClassDef payloads.
        try validateGdefChildOffset(glyph_class_def_offset, gdef.length, header_len);
        const class = try classDefValue(self.data[gdef.offset .. gdef.offset + gdef.length], glyph_class_def_offset, glyph_id);
        try validateGlyphClassValue(class);
        return @enumFromInt(class);
    }

    pub fn markAttachClass(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!u16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gdef = self.gdef orelse return 0;
        try sfnt.checksum.validate(self.data, gdef);
        const header_len = try validateGdefHeaderForLazyApi(self.data, gdef);
        const mark_attach_class_def_offset = try bin.readU16At(self.data, gdef.offset + 10);
        if (mark_attach_class_def_offset == 0) return 0;
        try validateGdefChildOffset(mark_attach_class_def_offset, gdef.length, header_len);
        return try classDefValue(self.data[gdef.offset .. gdef.offset + gdef.length], mark_attach_class_def_offset, glyph_id);
    }

    fn markFilteringSets(self: *const Font, allocator: std.mem.Allocator) FontError!?[][]glyph_mod.GlyphId {
        const gdef = self.gdef orelse return null;
        try sfnt.checksum.validate(self.data, gdef);
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
        try validateGdefChildOffset(mark_glyph_sets_def_offset, gdef.length, minimumGdefHeaderLength(minor));
        const table = self.data[gdef.offset .. gdef.offset + gdef.length];
        // Mark-filtering sets are assembled lazily for GSUB/GPOS lookup flags
        // from borrowed SFNT bytes. Recheck the parse-time maxp glyph bound
        // contract here so post-parse mutations cannot inject an out-of-range
        // mark set that shaping would later treat as a valid filter class.
        try validateMarkGlyphSetsDefGlyphBounds(table, mark_glyph_sets_def_offset, self.glyph_count);
        return try readMarkGlyphSetsDef(allocator, table, mark_glyph_sets_def_offset);
    }

    pub fn styleAttributes(self: *const Font) FontError!StyleAttributes {
        const os2 = self.os2 orelse return .{};
        try sfnt.checksum.validate(self.data, os2);
        return try readOs2StyleAttributes(self.data, os2);
    }

    /// Read validated metadata from the optional SFNT `OS/2` table.
    pub fn os2Info(self: *const Font) FontError!?Os2Info {
        const os2 = self.os2 orelse return null;
        try sfnt.checksum.validate(self.data, os2);
        _ = try readOs2StyleAttributes(self.data, os2);
        return try readOs2Info(self.data, os2);
    }

    pub fn variationAxes(self: *const Font, allocator: std.mem.Allocator) FontError![]VariationAxis {
        const fvar = self.fvar orelse return try allocator.alloc(VariationAxis, 0);
        // Font owns borrowed bytes. Re-apply the full fvar table contract at
        // this public API boundary so post-parse mutations cannot expose axis
        // records whose reserved flags, duplicate tags, or instance payloads
        // would have been rejected during Font.parse.
        try sfnt.checksum.validate(self.data, fvar);
        try validateFvarTable(self.data, fvar);
        if (self.name) |name| {
            // This API exposes only axes. A stale named-instance label must not
            // prevent design coordinates from reaching otherwise valid fvar,
            // avar, and glyph-variation data; variationInstances() separately
            // keeps the complete instance-name contract strict.
            const name_index = try readNameIdIndex(self.data, name);
            try validateFvarAxisNameReferences(self.data, fvar, &name_index);
        }
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
        }
        return axes;
    }

    pub fn mapVariationCoordinate(self: *const Font, axis_index: usize, normalized: f32) FontError!f32 {
        // This low-level API accepts an already-normalized design coordinate,
        // not a user-space axis value. Keep the caller contract explicit so
        // NaN/Inf values or extrapolated coordinates cannot flow into avar's
        // piecewise interpolation and come back as a plausible endpoint.
        try validateNormalizedVariationCoordinate(normalized);
        const avar = self.avar orelse return normalized;
        try sfnt.checksum.validate(self.data, avar);
        if (avar.offset > self.data.len or avar.length > self.data.len - avar.offset) return error.BadSfnt;
        const table = self.data[avar.offset .. avar.offset + avar.length];
        if (avar.length < 8) return error.BadSfnt;
        const major = try bin.readU16At(table, 0);
        const minor = try bin.readU16At(table, 2);
        if (major != 1 or minor != 0) return error.BadSfnt;
        const axis_count = try bin.readU16At(table, 6);
        if (self.fvar) |fvar| {
            try sfnt.checksum.validate(self.data, fvar);
            const fvar_info = try readFvarInfo(self.data, fvar);
            if (axis_count != fvar_info.axis_count) return error.BadSfnt;
        } else if (axis_count != 0) {
            return error.BadSfnt;
        }
        // The public axis index is caller-supplied, so it needs a contract even
        // when the avar table is otherwise well-formed. Without this check an
        // out-of-range request silently returned the input coordinate after
        // validating unrelated maps, masking bugs in variation callers.
        if (axis_index >= axis_count) return error.BadSfnt;

        var offset: usize = 8;
        var mapped = normalized;
        for (0..axis_count) |index| {
            if (offset + 2 > table.len) return error.BadSfnt;
            const pair_count = try bin.readU16At(table, offset);
            offset += 2;
            const pair_bytes = @as(usize, pair_count) * 4;
            if (pair_bytes > table.len - offset) return error.BadSfnt;
            try validateAvarSegmentMap(table[offset .. offset + pair_bytes]);
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
        try validateVariationCoordinates(axes, coordinates);

        const normalized = try allocator.alloc(f32, axes.len);
        errdefer allocator.free(normalized);
        for (axes, 0..) |axis, index| {
            const user_value = variationValueForAxis(axis, coordinates) orelse axis.default_value;
            const mapped = try self.mapVariationCoordinate(index, axis.normalize(user_value));
            // OpenType variation consumers operate at F2Dot14 locations.
            // HarfBuzz first rounds fvar/avar design coordinates into this
            // domain; retaining an unquantized f32 here can move a gvar phantom
            // metric across a half-unit boundary even though GDEF/HVAR later
            // quantize the same location independently.
            normalized[index] = quantizeNormalizedF2Dot14(mapped);
        }
        return normalized;
    }

    pub fn variationInstances(self: *const Font, allocator: std.mem.Allocator) FontError![]VariationInstance {
        const fvar = self.fvar orelse return try allocator.alloc(VariationInstance, 0);
        try sfnt.checksum.validate(self.data, fvar);
        try validateFvarTable(self.data, fvar);
        if (self.name) |name| {
            const name_index = try readNameIdIndex(self.data, name);
            try validateFvarNameReferences(self.data, fvar, &name_index);
        }
        const info = try readFvarInfo(self.data, fvar);

        const instances = try allocator.alloc(VariationInstance, info.instance_count);
        errdefer allocator.free(instances);
        var initialized: usize = 0;
        errdefer {
            for (instances[0..initialized]) |instance| allocator.free(instance.coordinates);
        }

        for (instances, 0..) |*instance, instance_index| {
            const instance_offset = fvarInstanceOffset(fvar, info, instance_index);
            const coordinates = try allocator.alloc(VariationCoordinate, info.axis_count);
            errdefer allocator.free(coordinates);
            for (coordinates, 0..) |*coordinate, axis_index| {
                const axis_offset = fvarAxisOffset(fvar, info, axis_index);
                coordinate.* = .{
                    .tag = try bin.readTagAt(self.data, axis_offset),
                    .value = fixed16_16ToF32(try bin.readI32At(self.data, instance_offset + 4 + axis_index * 4)),
                };
            }
            instance.* = .{
                .subfamily_name_id = try bin.readU16At(self.data, instance_offset),
                .flags = try bin.readU16At(self.data, instance_offset + 2),
                .postscript_name_id = if (info.has_postscript_name_id) id: {
                    const value = try bin.readU16At(self.data, instance_offset + info.postscript_name_id_offset);
                    break :id if (value == 0xffff) null else value;
                } else null,
                .coordinates = coordinates,
            };
            initialized += 1;
        }
        return instances;
    }

    pub fn freeVariationInstances(_: *const Font, allocator: std.mem.Allocator, instances: []VariationInstance) void {
        for (instances) |instance| allocator.free(instance.coordinates);
        allocator.free(instances);
    }

    pub fn statElidedFallbackNameId(self: *const Font, allocator: std.mem.Allocator) FontError!?u16 {
        const stat = self.stat orelse return null;
        var name_index_storage: NameIdIndex = undefined;
        const name_index: ?*const NameIdIndex = if (self.name) |name| blk: {
            name_index_storage = try readNameIdIndex(self.data, name);
            break :blk &name_index_storage;
        } else null;
        try sfnt.checksum.validate(self.data, stat);
        if (self.fvar) |fvar| try sfnt.checksum.validate(self.data, fvar);
        try validateStatTable(allocator, self.data, stat, self.fvar, name_index);
        const info = try readStatInfo(self.data, stat);
        return if (info.minor >= 1) try bin.readU16At(self.data, stat.offset + 18) else null;
    }

    pub fn statDesignAxes(self: *const Font, allocator: std.mem.Allocator) FontError![]StatDesignAxis {
        const stat = self.stat orelse return try allocator.alloc(StatDesignAxis, 0);
        var name_index_storage: NameIdIndex = undefined;
        const name_index: ?*const NameIdIndex = if (self.name) |name| blk: {
            name_index_storage = try readNameIdIndex(self.data, name);
            break :blk &name_index_storage;
        } else null;
        // STAT is kept as borrowed SFNT bytes. Re-run the full parse-time STAT
        // and name-reference validation before exposing axis metadata so
        // post-parse mutations cannot leave UI axis labels dangling or reorder
        // axes away from fvar while the cached table record still looks valid.
        try sfnt.checksum.validate(self.data, stat);
        if (self.fvar) |fvar| try sfnt.checksum.validate(self.data, fvar);
        try validateStatTable(allocator, self.data, stat, self.fvar, name_index);
        const info = try readStatInfo(self.data, stat);

        const axes = try allocator.alloc(StatDesignAxis, info.design_axis_count);
        errdefer allocator.free(axes);
        for (axes, 0..) |*axis, index| {
            const axis_offset = stat.offset + info.design_axes_offset + index * info.design_axis_size;
            axis.* = .{
                .tag = try bin.readTagAt(self.data, axis_offset),
                .name_id = try bin.readU16At(self.data, axis_offset + 4),
                .ordering = try bin.readU16At(self.data, axis_offset + 6),
            };
        }
        return axes;
    }

    pub fn statAxisValues(self: *const Font, allocator: std.mem.Allocator) FontError![]StatAxisValue {
        const stat = self.stat orelse return try allocator.alloc(StatAxisValue, 0);
        var name_index_storage: NameIdIndex = undefined;
        const name_index: ?*const NameIdIndex = if (self.name) |name| blk: {
            name_index_storage = try readNameIdIndex(self.data, name);
            break :blk &name_index_storage;
        } else null;
        try sfnt.checksum.validate(self.data, stat);
        if (self.fvar) |fvar| try sfnt.checksum.validate(self.data, fvar);
        try validateStatTable(allocator, self.data, stat, self.fvar, name_index);
        const info = try readStatInfo(self.data, stat);

        const values = try allocator.alloc(StatAxisValue, info.axis_value_count);
        errdefer allocator.free(values);
        var initialized: usize = 0;
        errdefer {
            for (values[0..initialized]) |value| allocator.free(value.coordinates);
        }

        for (values, 0..) |*value, index| {
            const entry_offset = stat.offset + info.axis_value_offsets_offset + index * 2;
            const axis_value_offset = try resolveStatAxisValueOffset(self.data, stat, info.axis_value_offsets_offset, entry_offset);
            value.* = try readStatAxisValue(allocator, self.data, stat, axis_value_offset);
            initialized += 1;
        }
        return values;
    }

    pub fn freeStatAxisValues(_: *const Font, allocator: std.mem.Allocator, values: []StatAxisValue) void {
        for (values) |value| allocator.free(value.coordinates);
        allocator.free(values);
    }

    pub fn colorLayers(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError![]ColorLayer {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const colr = self.colr orelse return try allocator.alloc(ColorLayer, 0);
        try sfnt.checksum.validate(self.data, colr);
        // Preserve the established lazy API contract: even non-v0 tables need
        // the complete legacy header prefix before this method can conclude
        // that no layer-list representation is available.
        if (colr.length < 14) return error.BadSfnt;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 0) return try allocator.alloc(ColorLayer, 0);
        // Both COLR and CPAL borrow caller-owned bytes. Revalidate the complete
        // v0 directory and every glyph/palette reference before materializing
        // one selected base glyph.
        const palette_entries = if (self.cpal) |cpal|
            (try cpal_mod.validateStructure(
                self.data,
                cpalTable(cpal),
            )).palette_entries
        else
            null;
        const layout = try colr_v0_mod.validate(
            self.data,
            colrV0Table(colr),
            self.glyph_count,
            palette_entries,
        );
        const result = try colr_v0_mod.layers(
            allocator,
            self.data,
            colrV0Table(colr),
            layout,
            glyph_id,
        );
        errdefer allocator.free(result);
        for (result) |layer| {
            // Preserve the established lazy trust boundary: a CPAL checksum
            // and label-name proof is needed only when returned layers consume
            // an actual palette slot. Foreground-only and missing glyph reads
            // do not touch CPAL payload bytes.
            if (layer.palette_index == 0xffff) continue;
            _ = try self.validatedCpalLayout(self.cpal orelse return error.BadSfnt);
            break;
        }
        return result;
    }

    pub fn paletteColor(self: *const Font, palette_index: u16, color_index: u16) FontError!?PaletteColor {
        const cpal = self.cpal orelse return null;
        // CPAL v1 label arrays borrow name IDs from the same caller-owned SFNT
        // bytes as the color records. Revalidate those cross-table references
        // for lazy palette reads too, so a post-parse mutation cannot leave UI
        // palette metadata dangling while color lookup still appears valid.
        const layout = try self.validatedCpalLayout(cpal);
        return try cpal_mod.color(
            self.data,
            cpalTable(cpal),
            layout,
            palette_index,
            color_index,
        );
    }

    pub fn paletteColors(self: *const Font, allocator: std.mem.Allocator, palette_index: u16) FontError![]PaletteColor {
        const cpal = self.cpal orelse return try allocator.alloc(PaletteColor, 0);
        const layout = try self.validatedCpalLayout(cpal);
        return try cpal_mod.colors(
            allocator,
            self.data,
            cpalTable(cpal),
            layout,
            palette_index,
        );
    }

    pub fn colorPalettes(self: *const Font, allocator: std.mem.Allocator) FontError![]PaletteInfo {
        const cpal = self.cpal orelse return try allocator.alloc(PaletteInfo, 0);
        const layout = try self.validatedCpalLayout(cpal);
        return try cpal_mod.palettes(
            allocator,
            self.data,
            cpalTable(cpal),
            layout,
        );
    }

    pub fn paletteEntryLabels(self: *const Font, allocator: std.mem.Allocator) FontError![]?u16 {
        const cpal = self.cpal orelse return try allocator.alloc(?u16, 0);
        const layout = try self.validatedCpalLayout(cpal);
        return try cpal_mod.entryLabels(
            allocator,
            self.data,
            cpalTable(cpal),
            layout,
        );
    }

    fn validatedCpalLayout(
        self: *const Font,
        cpal: TableRecord,
    ) FontError!cpal_mod.Layout {
        try sfnt.checksum.validate(self.data, cpal);
        return try cpal_mod.validate(
            self.data,
            cpalTable(cpal),
            if (self.name) |name| nameTableView(name) else null,
        );
    }

    pub fn colorPaint(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?ColorPaint {
        return try self.colorPaintAtCoords(glyph_id, &.{});
    }

    /// Resolve a COLR v1 base paint at normalized variation coordinates.
    pub fn colorPaintAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?ColorPaint {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const colr = self.colr orelse return null;
        try sfnt.checksum.validate(self.data, colr);
        if (colr.length < 34) return null;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 1) return null;
        // Public COLR v1 reads expose glyph IDs from BaseGlyphPaintRecord,
        // PaintGlyph, PaintColrGlyph, and LayerList graphs. Validate the whole
        // graph against maxp again because the Font only caches a borrowed
        // table record, not an immutable copy of the validated COLR bytes.
        try validateColrGlyphBounds(self.data, colr, self.glyph_count);
        // Keep palette validation equally lazy and whole-graph. A PaintSolid in
        // an unrequested base glyph or shared LayerList entry can become
        // malformed after Font.parse, and returning a selected paint while
        // another reachable paint names a missing CPAL slot would diverge from
        // the parser's accepted-font invariant.
        try validateColrPaletteBounds(self.data, colr, self.cpal);
        if (!normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            try validateColrVariationData(self.data, colr, self.fvar, self.glyph_count);
        }
        const read_context = ColorPaintReadContext{
            .normalized_coords = normalized_coords,
            .variation = if (normalizedVariationCoordinatesAreDefault(normalized_coords))
                null
            else
                try readColrVariationContext(self.data, colr),
        };
        const base_list = (try colr_bases.read(
            self.data,
            colrV1Table(colr),
        )) orelse return null;
        const paint_start = (try colr_bases.paintOffsetForGlyph(
            self.data,
            colrV1Table(colr),
            base_list,
            glyph_id,
        )) orelse return null;
        try colr_paint.validateGraph(
            self.data,
            colrV1Table(colr),
            paint_start,
        );
        return try readColorPaint(self, paint_start, read_context);
    }

    pub fn colorClipBox(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?ColorClipBox {
        return try self.colorClipBoxAtCoords(glyph_id, &.{});
    }

    /// Resolve the COLR v1 clip box for a glyph at normalized coordinates.
    ///
    /// ClipBox format 2 stores four consecutive ItemVariationStore deltas in
    /// font units. The result intentionally remains floating point: normalized
    /// F2Dot14 coordinates can produce fractional bounds even though the base
    /// rectangle and delta rows are integer-valued.
    pub fn colorClipBoxAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?ColorClipBox {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const colr = self.colr orelse return null;
        try sfnt.checksum.validate(self.data, colr);
        if (colr.length < 34 or try bin.readU16At(self.data, colr.offset) != 1) return null;
        const list = (try colr_v1_mod.validateClipList(
            self.data,
            colrV1Table(colr),
            self.glyph_count,
        )) orelse return null;
        const box = (try colr_v1_mod.clipBoxForGlyph(
            self.data,
            colrV1Table(colr),
            list,
            glyph_id,
        )) orelse return null;
        var context: ?ColrVariationContext = null;
        const uses_variation = if (box.var_index_base) |var_index_base|
            var_index_base != colr_variation.no_index and
                !normalizedVariationCoordinatesAreDefault(normalized_coords)
        else
            false;
        if (uses_variation) {
            // The Font borrows its backing bytes, so repeat cross-reference
            // validation immediately before dereferencing a variation row. Static
            // boxes stay on the cheaper ClipList-only path.
            try validateColrVariationData(
                self.data,
                colr,
                self.fvar,
                self.glyph_count,
            );
            context =
                (try readColrVariationContext(self.data, colr)) orelse
                return error.BadSfnt;
        }
        return try colr_read.clipBox(
            self.data,
            colrV1Table(colr),
            box,
            .{
                .normalized_coords = normalized_coords,
                .variation = context,
            },
        );
    }

    /// Read validated metadata from the optional SFNT `VORG` table.
    pub fn verticalOrigins(self: *const Font, allocator: std.mem.Allocator) FontError!?VerticalOriginInfo {
        const vorg = self.vorg orelse return null;
        try sfnt.checksum.validate(self.data, vorg);
        try validateVorgTable(self.data, vorg, self.glyph_count);
        return try readVorgInfo(allocator, self.data, vorg);
    }

    pub fn freeVerticalOrigins(_: *const Font, allocator: std.mem.Allocator, info: VerticalOriginInfo) void {
        allocator.free(info.metrics);
    }

    pub fn verticalOriginY(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?i16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const vorg = self.vorg orelse return null;
        try sfnt.checksum.validate(self.data, vorg);
        try validateVorgTable(self.data, vorg, self.glyph_count);
        return try vorgOriginY(self.data, vorg, glyph_id);
    }

    /// Return VORG vertical origin Y with VVAR vOrg delta applied when present.
    pub fn verticalOriginYAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?i16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        var origin = (try self.verticalOriginY(glyph_id)) orelse return null;
        const vvar = (try self.metricVariationTableForRead(.vvar)) orelse return origin;
        if (try metric_variation_mod.vvarVerticalOriginDelta(self.data, vvar.offset, vvar.length, glyph_id, normalized_coords)) |delta| {
            origin = clampI32ToI16(@as(i32, origin) + delta);
        }
        return origin;
    }

    /// Return the OpenType vertical origin used by shaping, synthesizing it
    /// when neither VORG nor glyf/vmtx phantom-point metrics provide one.
    ///
    /// HarfBuzz centers glyph extents inside the horizontal font-extents box
    /// for this final fallback. This differs from simply using half the line
    /// advance: asymmetric glyphs and vertical punctuation need the glyph's
    /// `yMax` and height to keep the vertical baseline stable.
    fn shapingVerticalOriginYAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!i32 {
        return try self.shapingVerticalOriginYAtCoordsForReadMode(glyph_id, normalized_coords, .revalidate);
    }

    /// Parsed-font counterpart used by shaping after its table-proof cache has
    /// established immutability for the current run.
    fn shapingVerticalOriginYForShaping(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!i32 {
        return try self.shapingVerticalOriginYAtCoordsForReadMode(glyph_id, normalized_coords, .parsed);
    }

    fn shapingVerticalOriginYAtCoordsForReadMode(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!i32 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        if (try self.verticalOriginYAtCoords(glyph_id, normalized_coords)) |origin| return origin;

        const bounds = switch (read_mode) {
            .revalidate => self.glyphBoundsAtCoords(glyph_id, normalized_coords),
            .parsed => self.glyphBoundsAtCoordsForShaping(glyph_id, normalized_coords),
        } catch |err| switch (err) {
            // HarfBuzz falls back to the font ascender when the active font
            // backend cannot provide glyph extents.
            error.MissingTable, error.UnsupportedGlyph, error.UnsupportedCff => return self.ascender,
            else => return err,
        };
        if (self.format == .truetype) {
            if (try self.verticalMetricsAtCoords(glyph_id, normalized_coords)) |metrics| {
                var origin = @as(i32, bounds.y_max) + @as(i32, metrics.top_side_bearing);
                if (try self.metricVariationTableForRead(.vvar)) |vvar| {
                    if (try metric_variation_mod.vvarVerticalOriginDelta(
                        self.data,
                        vvar.offset,
                        vvar.length,
                        glyph_id,
                        normalized_coords,
                    )) |delta| {
                        origin += delta;
                    }
                }
                return origin;
            }
        }

        const font_height = @as(i32, self.ascender) - @as(i32, self.descender);
        const glyph_height = @as(i32, bounds.y_max) - @as(i32, bounds.y_min);
        return @as(i32, bounds.y_max) + @divFloor(font_height - glyph_height, 2);
    }

    /// Expand the TrueType `loca` table into one glyf byte range per glyph.
    pub fn glyphLocations(self: *const Font, allocator: std.mem.Allocator) FontError![]GlyphLocationInfo {
        const loca = self.loca orelse return error.MissingTable;
        const glyf = self.glyf orelse return error.MissingTable;
        try sfnt.checksum.validate(self.data, self.maxp);
        try sfnt.checksum.validate(self.data, loca);
        try sfnt.checksum.validate(self.data, glyf);
        try validateLocaTable(self.data, loca, glyf, self.glyph_count, self.index_to_loc_format);

        const locations = try allocator.alloc(GlyphLocationInfo, self.glyph_count);
        errdefer allocator.free(locations);
        for (locations, 0..) |*location, glyph_index| {
            const start = try glyfOffsetFromLoca(self.data, loca, self.index_to_loc_format, glyph_index);
            const end = try glyfOffsetFromLoca(self.data, loca, self.index_to_loc_format, glyph_index + 1);
            if (end < start or end > glyf.length) return error.InvalidLoca;
            location.* = .{
                .glyph_id = @intCast(glyph_index),
                .offset = glyf.offset + start,
                .length = end - start,
                .empty = end == start,
            };
        }
        return locations;
    }

    pub fn colorPaintLayer(self: *const Font, layer_index: u32) FontError!?ColorPaint {
        return try self.colorPaintLayerAtCoords(layer_index, &.{});
    }

    /// Resolve a LayerList paint at normalized variation coordinates.
    pub fn colorPaintLayerAtCoords(self: *const Font, layer_index: u32, normalized_coords: []const f32) FontError!?ColorPaint {
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const colr = self.colr orelse return null;
        try sfnt.checksum.validate(self.data, colr);
        if (colr.length < 34) return null;
        const version = try bin.readU16At(self.data, colr.offset);
        if (version != 1) return null;
        // LayerList entries are another lazy entry point into the same borrowed
        // COLR v1 paint graph. Keep its glyph-id contract in sync with
        // Font.parse instead of validating only the layer index being read.
        try validateColrGlyphBounds(self.data, colr, self.glyph_count);
        // `colorPaintLayer` bypasses BaseGlyphPaintRecord selection, but it
        // still returns COLR paints whose palette indices must be backed by
        // CPAL. Validate the complete graph so post-parse mutations in sibling
        // layers cannot hide behind the requested layer index.
        try validateColrPaletteBounds(self.data, colr, self.cpal);
        if (!normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            try validateColrVariationData(self.data, colr, self.fvar, self.glyph_count);
        }
        const layer_list = (try colr_layers.read(self.data, colrV1Table(colr))) orelse return null;
        if (layer_index >= layer_list.layer_count) return null;
        const paint_start = try colr_layers.paintOffset(
            self.data,
            colrV1Table(colr),
            layer_list,
            layer_index,
        );
        try colr_paint.validateGraph(
            self.data,
            colrV1Table(colr),
            paint_start,
        );
        return try readColorPaint(self, paint_start, .{
            .normalized_coords = normalized_coords,
            .variation = if (normalizedVariationCoordinatesAreDefault(normalized_coords))
                null
            else
                try readColrVariationContext(self.data, colr),
        });
    }

    /// Resolve a child reference from a transform paint.
    pub fn colorPaintChildAtCoords(self: *const Font, child: ColorPaint.ChildRef, normalized_coords: []const f32) FontError!ColorPaint {
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const colr = self.colr orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.data, colr);
        if (child.offset < colr.offset or child.offset >= colr.offset + colr.length) return error.BadSfnt;
        // A child reference is a public lazy entry point just like a base or
        // layer root. Revalidate the complete borrowed graph before the pure
        // decoder trusts palette and glyph references.
        try validateColrGlyphBounds(self.data, colr, self.glyph_count);
        try validateColrPaletteBounds(self.data, colr, self.cpal);
        if (!normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            try validateColrVariationData(self.data, colr, self.fvar, self.glyph_count);
        }
        try colr_paint.validateGraph(
            self.data,
            colrV1Table(colr),
            child.offset,
        );
        return try readColorPaint(self, child.offset, .{
            .normalized_coords = normalized_coords,
            .variation = if (normalizedVariationCoordinatesAreDefault(normalized_coords))
                null
            else
                try readColrVariationContext(self.data, colr),
        });
    }

    /// Resolve the root paint of a COLR v1 base glyph referenced by
    /// PaintColrGlyph. Unlike `colorPaintAtCoords`, this assumes the outer
    /// traversal has already established its graph validation contract.
    pub fn colorGlyphPaintAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!?ColorPaint {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const colr = self.colr orelse return null;
        try sfnt.checksum.validate(self.data, colr);
        if (colr.length < 34 or try bin.readU16At(self.data, colr.offset) != 1) return null;
        try validateColrGlyphBounds(self.data, colr, self.glyph_count);
        try validateColrPaletteBounds(self.data, colr, self.cpal);
        if (!normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            try validateColrVariationData(self.data, colr, self.fvar, self.glyph_count);
        }

        const base_list = (try colr_bases.read(
            self.data,
            colrV1Table(colr),
        )) orelse return null;
        const paint_offset = (try colr_bases.paintOffsetForGlyph(
            self.data,
            colrV1Table(colr),
            base_list,
            glyph_id,
        )) orelse return null;
        return try readColorPaint(self, paint_offset, .{
            .normalized_coords = normalized_coords,
            .variation = if (normalizedVariationCoordinatesAreDefault(normalized_coords))
                null
            else
                try readColrVariationContext(self.data, colr),
        });
    }

    /// Resolve one ColorStop/VarColorStop from a previously returned color
    /// line. The line borrows only COLR bytes; keeping the Font and coordinates
    /// explicit avoids embedding a pointer to a possibly stack-allocated Font
    /// value in long-lived render metadata.
    pub fn colorStopAtCoords(self: *const Font, color_line: ColorPaint.ColorLine, index: usize, normalized_coords: []const f32) FontError!?ColorPaint.ColorStop {
        const read_state = try self.colorLineReadState(
            color_line,
            normalized_coords,
        );
        return try colr_read.colorStop(
            self.data,
            read_state.table,
            color_line,
            index,
            read_state.context,
        );
    }

    /// Resolve a color line into caller-owned stops and sort by varied offset.
    ///
    /// Variation deltas may reorder stops even though the encoded base offsets
    /// are sorted. Returning an owned slice gives render bridges and other
    /// retained consumers the same stable, resolved representation used by the
    /// rasterizer without storing variation coordinates in borrowed metadata.
    pub fn colorStopsAtCoords(self: *const Font, allocator: std.mem.Allocator, color_line: ColorPaint.ColorLine, normalized_coords: []const f32) FontError![]ColorPaint.ColorStop {
        const read_state = try self.colorLineReadState(
            color_line,
            normalized_coords,
        );
        return try colr_read.colorStops(
            allocator,
            self.data,
            read_state.table,
            color_line,
            read_state.context,
        );
    }

    fn colorLineReadState(
        self: *const Font,
        color_line: ColorPaint.ColorLine,
        normalized_coords: []const f32,
    ) FontError!ColorLineReadState {
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        var context: ?ColrVariationContext = null;
        if (color_line.variable and !normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            const colr = self.colr orelse return error.BadSfnt;
            try sfnt.checksum.validate(self.data, colr);
            try validateColrVariationData(self.data, colr, self.fvar, self.glyph_count);
            context = try readColrVariationContext(self.data, colr);
        }
        const colr = self.colr;
        return .{
            .table = if (colr) |record| colrV1Table(record) else .{
                .offset = 0,
                .length = self.data.len,
            },
            .context = .{
                .normalized_coords = normalized_coords,
                .variation = context,
            },
        };
    }

    fn rawSvgGlyphDocument(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?SvgGlyphDocument {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const svg = self.svg orelse return null;
        try sfnt.checksum.validate(self.data, svg);
        return try svg_mod.rawDocument(
            self.allocator,
            self.data,
            svgTable(svg),
            self.glyph_count,
            glyph_id,
        );
    }

    /// Resolve an SVG document to validated cleartext XML.
    ///
    /// The returned handle must be deinitialized even though plain documents
    /// are borrowed; gzip documents own their bounded decoded bytes.
    pub fn resolvedSvgGlyphDocument(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError!?ResolvedSvgGlyphDocument {
        return try self.resolvedSvgGlyphDocumentForReadMode(allocator, glyph_id, .revalidate);
    }

    /// Renderer fast path for immutable fonts already validated by `Font.parse`.
    ///
    /// Only the matching document is decompressed; unrelated SVG records in the
    /// same font are not repeatedly inflated for every glyph draw.
    fn resolvedSvgGlyphDocumentForRaster(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError!?ResolvedSvgGlyphDocument {
        return try self.resolvedSvgGlyphDocumentForReadMode(allocator, glyph_id, .parsed);
    }

    fn resolvedSvgGlyphDocumentForReadMode(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        read_mode: OutlineReadMode,
    ) FontError!?ResolvedSvgGlyphDocument {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const svg = self.svg orelse return null;
        if (read_mode.shouldRevalidate()) try sfnt.checksum.validate(self.data, svg);
        return try svg_mod.resolvedDocument(
            allocator,
            self.data,
            svgTable(svg),
            self.glyph_count,
            glyph_id,
            read_mode.shouldRevalidate(),
        );
    }

    /// Return the validated raw SVG table payload.
    ///
    /// This preserves the historical borrowed-slice API; gzip data remains
    /// compressed. Renderers should use `resolvedSvgGlyphDocument()`.
    pub fn svgGlyphDocument(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?SvgGlyphDocument {
        return try self.rawSvgGlyphDocument(glyph_id);
    }

    pub fn svgDocument(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
        const document = try self.svgGlyphDocument(glyph_id);
        return if (document) |value| value.data else null;
    }

    fn appendBitmapStrikesFromLocationTables(
        self: *const Font,
        allocator: std.mem.Allocator,
        strikes: *std.ArrayList(BitmapStrikeInfo),
        location_table: TableRecord,
        data_table: TableRecord,
        source: BitmapStrikeSource,
    ) FontError!void {
        try sfnt.checksum.validate(self.data, location_table);
        try sfnt.checksum.validate(self.data, data_table);
        try validateCblcCbdtTables(self.data, location_table, data_table, self.glyph_count);
        const strike_count = try bitmap_mod.cblc.strikeCount(self.data, bitmapTable(location_table));
        try strikes.ensureUnusedCapacity(allocator, strike_count);
        for (0..strike_count) |strike_index| {
            const strike = try bitmap_mod.cblc.strike(self.data, bitmapTable(location_table), self.glyph_count, strike_index);
            strikes.appendAssumeCapacity(.{
                .source = source,
                .ppem = strike.ppem,
                .ppi = strike.ppi,
                .start_glyph = strike.start_glyph,
                .end_glyph = strike.end_glyph,
            });
        }
    }

    fn recordBestBitmapPpemFromLocationTables(
        self: *const Font,
        location_table: TableRecord,
        data_table: TableRecord,
        size_px: f32,
        best_ppem: *?u16,
    ) FontError!void {
        try sfnt.checksum.validate(self.data, location_table);
        try sfnt.checksum.validate(self.data, data_table);
        try validateCblcCbdtTables(self.data, location_table, data_table, self.glyph_count);
        const strike_count = try bitmap_mod.cblc.strikeCount(self.data, bitmapTable(location_table));
        for (0..strike_count) |strike_index| {
            const strike = try bitmap_mod.cblc.strike(self.data, bitmapTable(location_table), self.glyph_count, strike_index);
            bitmap_mod.recordBestPpem(strike.ppem, size_px, best_ppem);
        }
    }

    pub fn bitmapStrikes(self: *const Font, allocator: std.mem.Allocator) FontError![]BitmapStrikeInfo {
        var strikes = std.ArrayList(BitmapStrikeInfo).empty;
        errdefer strikes.deinit(allocator);

        if (self.sbix) |sbix| {
            try sfnt.checksum.validate(self.data, sbix);
            try validateSbixTable(self.allocator, self.data, sbix, self.glyph_count);
            const strike_count = try bitmap_mod.sbix.strikeCount(self.data, bitmapTable(sbix));
            try strikes.ensureUnusedCapacity(allocator, strike_count);
            for (0..strike_count) |strike_index| {
                const strike = try bitmap_mod.sbix.strike(self.data, bitmapTable(sbix), self.glyph_count, strike_index);
                strikes.appendAssumeCapacity(.{
                    .source = .sbix,
                    .ppem = strike.ppem,
                    .ppi = strike.ppi,
                    .start_glyph = 0,
                    .end_glyph = if (self.glyph_count == 0) 0 else self.glyph_count - 1,
                });
            }
        }

        if (self.cblc != null and self.cbdt != null) {
            try self.appendBitmapStrikesFromLocationTables(allocator, &strikes, self.cblc.?, self.cbdt.?, .cblc_cbdt);
        }
        if (self.eblc != null and self.ebdt != null) {
            try self.appendBitmapStrikesFromLocationTables(allocator, &strikes, self.eblc.?, self.ebdt.?, .eblc_ebdt);
        }

        return try strikes.toOwnedSlice(allocator);
    }

    pub fn bestBitmapStrikePpem(self: *const Font, size_px: f32) FontError!?u16 {
        try bitmap_mod.validateRequestSize(size_px);
        var best_ppem: ?u16 = null;

        if (self.sbix) |sbix| {
            try sfnt.checksum.validate(self.data, sbix);
            // Bitmap tables are borrowed from the caller-owned font bytes.
            // Re-run the full parse-time sbix contract at the public API
            // boundary so post-parse byte mutations cannot hide a corrupt
            // unselected glyph or strike behind a valid requested size.
            try validateSbixTable(self.allocator, self.data, sbix, self.glyph_count);
            const strike_count = try bitmap_mod.sbix.strikeCount(self.data, bitmapTable(sbix));
            for (0..strike_count) |strike_index| {
                const strike = try bitmap_mod.sbix.strike(self.data, bitmapTable(sbix), self.glyph_count, strike_index);
                bitmap_mod.recordBestPpem(strike.ppem, size_px, &best_ppem);
            }
        }

        if (self.cblc != null and self.cbdt != null) {
            // CBLC strike metadata is meaningful only with the CBDT payloads it
            // indexes. Revalidating both tables here keeps this metadata-only
            // query from returning a ppem for a borrowed bitmap table whose
            // referenced image bytes no longer satisfy the parser invariants.
            try self.recordBestBitmapPpemFromLocationTables(self.cblc.?, self.cbdt.?, size_px, &best_ppem);
        }
        if (self.eblc != null and self.ebdt != null) {
            try self.recordBestBitmapPpemFromLocationTables(self.eblc.?, self.ebdt.?, size_px, &best_ppem);
        }

        return best_ppem;
    }

    /// Return bitmap metadata from the exact, nearest larger, or largest
    /// smaller strike, in that order.
    pub fn bitmapGlyphInfo(self: *const Font, glyph_id: glyph_mod.GlyphId, size_px: f32) FontError!?BitmapGlyphInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try bitmap_mod.validateRequestSize(size_px);

        var best: ?BitmapGlyphInfo = null;

        if (self.sbix) |sbix| {
            try sfnt.checksum.validate(self.data, sbix);
            try validateSbixTable(self.allocator, self.data, sbix, self.glyph_count);
            const strike_count = try bitmap_mod.sbix.strikeCount(self.data, bitmapTable(sbix));
            for (0..strike_count) |strike_index| {
                const strike = try bitmap_mod.sbix.strike(self.data, bitmapTable(sbix), self.glyph_count, strike_index);
                if (try bitmap_mod.sbix.glyphInfo(self.data, strike, glyph_id, self.glyph_count)) |info| bitmap_mod.recordBestGlyphInfo(info, size_px, &best);
            }
            if (best) |info| return info;
        }

        if (self.cblc != null and self.cbdt != null) {
            const cblc = self.cblc.?;
            const cbdt = self.cbdt.?;
            try sfnt.checksum.validate(self.data, cblc);
            try sfnt.checksum.validate(self.data, cbdt);
            try validateCblcCbdtTables(self.data, cblc, cbdt, self.glyph_count);
            if (try bitmap_mod.cblc.glyphInfo(self.data, bitmapTable(cblc), bitmapTable(cbdt), self.glyph_count, glyph_id, size_px, .cblc_cbdt)) |info| return info;
        }
        if (self.eblc != null and self.ebdt != null) {
            const eblc = self.eblc.?;
            const ebdt = self.ebdt.?;
            try sfnt.checksum.validate(self.data, eblc);
            try sfnt.checksum.validate(self.data, ebdt);
            try validateCblcCbdtTables(self.data, eblc, ebdt, self.glyph_count);
            if (try bitmap_mod.cblc.glyphInfo(self.data, bitmapTable(eblc), bitmapTable(ebdt), self.glyph_count, glyph_id, size_px, .eblc_ebdt)) |info| return info;
        }
        return null;
    }

    pub fn bitmapGlyphPng(self: *const Font, glyph_id: glyph_mod.GlyphId, size_px: f32) FontError!?BitmapGlyphPng {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try bitmap_mod.validateRequestSize(size_px);

        if (self.sbix) |sbix| {
            try sfnt.checksum.validate(self.data, sbix);
            try validateSbixTable(self.allocator, self.data, sbix, self.glyph_count);
            const strike_count = try bitmap_mod.sbix.strikeCount(self.data, bitmapTable(sbix));
            var best: ?BitmapGlyphPng = null;
            for (0..strike_count) |strike_index| {
                const strike = try bitmap_mod.sbix.strike(self.data, bitmapTable(sbix), self.glyph_count, strike_index);
                const maybe_glyph = try bitmap_mod.sbix.glyphPng(self.data, strike, glyph_id, self.glyph_count);
                if (maybe_glyph) |glyph| {
                    if (best == null or bitmap_mod.ppemIsPreferred(glyph.ppem, best.?.ppem, size_px)) best = glyph;
                }
            }
            if (best) |glyph| return glyph;
        }

        if (self.cblc != null and self.cbdt != null) {
            const cblc = self.cblc.?;
            const cbdt = self.cbdt.?;
            try sfnt.checksum.validate(self.data, cblc);
            try sfnt.checksum.validate(self.data, cbdt);
            try validateCblcCbdtTables(self.data, cblc, cbdt, self.glyph_count);
            if (try bitmap_mod.cblc.glyphPng(self.data, bitmapTable(cblc), bitmapTable(cbdt), self.glyph_count, glyph_id, size_px, .cblc_cbdt)) |png| return png;
        }
        if (self.eblc != null and self.ebdt != null) {
            const eblc = self.eblc.?;
            const ebdt = self.ebdt.?;
            try sfnt.checksum.validate(self.data, eblc);
            try sfnt.checksum.validate(self.data, ebdt);
            try validateCblcCbdtTables(self.data, eblc, ebdt, self.glyph_count);
            if (try bitmap_mod.cblc.glyphPng(self.data, bitmapTable(eblc), bitmapTable(ebdt), self.glyph_count, glyph_id, size_px, .eblc_ebdt)) |png| return png;
        }
        return null;
    }

    /// Whether this face has a vector outline source for monochrome fallback.
    ///
    /// Bitmap-only TrueType fonts are valid and common for emoji. Renderers use
    /// this distinction to treat an absent bitmap (for example the space glyph)
    /// as an empty glyph instead of attempting a missing glyf/loca fallback.
    pub fn hasOutlineData(self: *const Font) bool {
        return self.glyf != null or self.cff != null or self.cff2 != null;
    }

    pub fn glyphBounds(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!glyph_mod.Bounds {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (self.varc) |varc| {
            try sfnt.checksum.validate(self.data, varc);
            try validateVarcTable(self.data, varc, self.glyph_count);
            if (try varc_mod.glyphCoverageIndex(self.data, varc.offset, varc.length, self.glyph_count, glyph_id) != null) {
                var outline = try self.glyphOutline(std.heap.page_allocator, glyph_id);
                defer outline.deinit();
                return outline.bounds;
            }
        }
        if (self.format == .truetype) {
            const loca = self.loca orelse return error.MissingTable;
            const glyf = self.glyf orelse return error.MissingTable;
            try sfnt.checksum.validate(self.data, self.maxp);
            try sfnt.checksum.validate(self.data, loca);
            try sfnt.checksum.validate(self.data, glyf);
            try validateLocaTable(self.data, loca, glyf, self.glyph_count, self.index_to_loc_format);
            return try self.glyphBoundsFromParsedTables(glyph_id);
        }
        if (self.cff2) |cff2| {
            try sfnt.checksum.validate(self.data, cff2);
            try validateCff2Table(self.data, cff2);
            const bounds = (try cff2_mod.charStringBoundsInfo(self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count)) orelse return error.InvalidGlyph;
            return cff2BoundsInfoToGlyphBounds(bounds);
        }
        if (self.cff) |cff| {
            try sfnt.checksum.validate(self.data, cff);
            try validateCffGlyphCount(self.data, cff, self.glyph_count);
            var outline = try self.glyphOutline(std.heap.page_allocator, glyph_id);
            defer outline.deinit();
            return outline.bounds;
        }
        return error.UnsupportedGlyph;
    }

    pub fn glyphBoundsAtCoords(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!glyph_mod.Bounds {
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        if (self.varc) |varc| {
            try sfnt.checksum.validate(self.data, varc);
            try validateVarcTable(self.data, varc, self.glyph_count);
            if (try varc_mod.glyphCoverageIndex(self.data, varc.offset, varc.length, self.glyph_count, glyph_id) != null) {
                var outline = try self.glyphOutlineAtCoords(std.heap.page_allocator, glyph_id, normalized_coords);
                defer outline.deinit();
                return outline.bounds;
            }
        }
        if (self.cff2 != null) {
            return (try self.cff2GlyphBoundsAtCoords(glyph_id, normalized_coords)) orelse error.UnsupportedGlyph;
        }
        if (self.format == .truetype and self.gvar != null and !normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            // Unlike static glyf bounds, a gvar instance has no authoritative
            // xMin/yMin/xMax/yMax record. Derive it from the varied outline so
            // public bounds, extents, and raster callers observe the same IUP
            // interpolation and compound-component movement. The default
            // location retains the allocation-free glyf header path below.
            var outline = try self.glyphOutlineAtCoords(std.heap.page_allocator, glyph_id, normalized_coords);
            defer outline.deinit();
            return outline.bounds;
        }
        return try self.glyphBounds(glyph_id);
    }

    fn glyphBoundsAtCoordsForShaping(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!glyph_mod.Bounds {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        if (normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            return try self.glyphBoundsFromParsedTables(glyph_id);
        }
        if (self.varc != null or self.cff2 != null or (self.format == .truetype and self.gvar != null)) {
            var outline = try self.glyphOutlineForRasterAtCoords(std.heap.page_allocator, glyph_id, normalized_coords);
            defer outline.deinit();
            return outline.bounds;
        }
        return try self.glyphBoundsFromParsedTables(glyph_id);
    }

    pub fn glyphOutline(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError!glyph_mod.GlyphOutline {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (self.format == .truetype) {
            const loca = self.loca orelse return error.MissingTable;
            const glyf = self.glyf orelse return error.MissingTable;
            try sfnt.checksum.validate(self.data, self.maxp);
            try sfnt.checksum.validate(self.data, loca);
            try sfnt.checksum.validate(self.data, glyf);
            try validateLocaTable(self.data, loca, glyf, self.glyph_count, self.index_to_loc_format);
            // The SFNT bytes are borrowed from the caller. Re-run the same glyf
            // grammar and component-graph validation enforced by Font.parse so
            // a post-parse mutation cannot be observed only by the particular
            // glyph whose outline is requested.
            const max_points = try bin.readU16At(self.data, self.maxp.offset + 6);
            const max_contours = try bin.readU16At(self.data, self.maxp.offset + 8);
            const max_component_elements = try bin.readU16At(self.data, self.maxp.offset + 28);
            const max_component_depth = try bin.readU16At(self.data, self.maxp.offset + 30);
            try validateGlyfTable(
                allocator,
                self.data,
                loca,
                glyf,
                self.glyph_count,
                self.index_to_loc_format,
                max_points,
                max_contours,
                max_component_elements,
                max_component_depth,
            );
        }
        return self.glyphOutlineFromParsedTables(allocator, glyph_id, .revalidate);
    }

    pub fn glyphOutlineAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!glyph_mod.GlyphOutline {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (normalizedVariationCoordinatesAreDefault(normalized_coords)) return try self.glyphOutline(allocator, glyph_id);
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        if (self.varc) |varc| {
            try sfnt.checksum.validate(self.data, varc);
            try validateVarcTable(self.data, varc, self.glyph_count);
            if (try varc_mod.glyphCoverageIndex(self.data, varc.offset, varc.length, self.glyph_count, glyph_id) != null) {
                return try self.varcGlyphOutlineAtCoords(allocator, glyph_id, normalized_coords, .revalidate);
            }
        }
        if (self.cff2 != null) {
            return (try self.cff2GlyphOutlineAtCoordsPrepared(allocator, glyph_id, normalized_coords, .revalidate)) orelse error.UnsupportedGlyph;
        }
        if (self.format == .truetype and self.gvar != null) {
            return try self.glyfGlyphOutlineAtCoords(allocator, glyph_id, normalized_coords, .revalidate);
        }
        return try self.glyphOutline(allocator, glyph_id);
    }

    /// Build a variation-aware outline for renderers that already trust Font.parse.
    ///
    /// This mirrors `glyphOutlineForRaster()` for variable CFF2/glyf outlines:
    /// public APIs keep their borrowed-byte checksum defenses, while raster
    /// loops can avoid revalidating an immutable parsed font once per glyph.
    fn glyphOutlineForRasterAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32) FontError!glyph_mod.GlyphOutline {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (normalizedVariationCoordinatesAreDefault(normalized_coords)) return try self.glyphOutlineForRaster(allocator, glyph_id);
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        if (self.varc) |varc| {
            if (try varc_mod.glyphCoverageIndex(self.data, varc.offset, varc.length, self.glyph_count, glyph_id) != null) {
                return try self.varcGlyphOutlineAtCoords(allocator, glyph_id, normalized_coords, .parsed);
            }
        }
        if (self.cff2 != null) {
            return (try self.cff2GlyphOutlineAtCoordsPrepared(allocator, glyph_id, normalized_coords, .parsed)) orelse error.UnsupportedGlyph;
        }
        if (self.format == .truetype and self.gvar != null) {
            return try self.glyfGlyphOutlineAtCoords(allocator, glyph_id, normalized_coords, .parsed);
        }
        return try self.glyphOutlineForRaster(allocator, glyph_id);
    }

    fn glyfGlyphOutlineAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!glyph_mod.GlyphOutline {
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return try self.glyphOutlineForReadMode(allocator, glyph_id, read_mode);
        const contour_count = try bin.readI16At(data, 0);
        if (contour_count < 0) return try self.glyfCompoundGlyphOutlineAtCoords(allocator, glyph_id, data, normalized_coords, read_mode);
        const metrics = try self.horizontalMetricsForReadMode(glyph_id, read_mode);
        const default_bounds = try self.glyphBoundsFromParsedTables(glyph_id);
        var outline = glyph_mod.GlyphOutline.init(allocator, glyph_id, default_bounds, metrics.advance_width, metrics.left_side_bearing);
        errdefer outline.deinit();
        const variation = try self.simpleGlyphVariationContext(glyph_id, normalized_coords, read_mode);
        if (try appendSimpleGlyph(&outline, null, data, @intCast(contour_count), Transform.identity(), variation)) |phantom| {
            applyGvarGlyphMetricDeltas(&outline, default_bounds, metrics, phantom);
        }
        return outline;
    }

    fn simpleGlyphVariationContext(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!?SimpleGlyphVariation {
        const gvar = self.gvar orelse return null;
        if (read_mode.shouldRevalidate()) try sfnt.checksum.validate(self.data, gvar);
        return .{
            .data = self.data,
            .table_offset = gvar.offset,
            .table_length = gvar.length,
            .glyph_count = self.glyph_count,
            .axis_count = try self.fvarAxisCountForReadMode(read_mode),
            .glyph_id = glyph_id,
            .normalized_coords = normalized_coords,
            // Public outline APIs remain defensive against malformed inactive
            // tuple payloads. Parsed raster paths already crossed Font.parse's
            // whole-table proof and may avoid decoding zero-scalar tuples.
            .validate_inactive_payloads = read_mode.shouldRevalidate(),
        };
    }

    fn glyfCompoundGlyphOutlineAtCoords(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, data: []const u8, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!glyph_mod.GlyphOutline {
        const metrics = try self.horizontalMetricsForReadMode(glyph_id, read_mode);
        const default_bounds = try self.glyphBoundsFromParsedTables(glyph_id);
        var outline = glyph_mod.GlyphOutline.init(allocator, glyph_id, default_bounds, metrics.advance_width, metrics.left_side_bearing);
        errdefer outline.deinit();
        var points = std.ArrayList(glyph_mod.Point).empty;
        defer points.deinit(allocator);
        try self.appendCompoundGlyphAtCoords(&outline, &points, data, Transform.identity(), 1, glyph_id, normalized_coords, read_mode);
        outline.bounds = glyph_mod.boundsForCommands(outline.commands.items);
        if (try self.gvarPhantomPointDeltasAtCoordsPrepared(allocator, glyph_id, normalized_coords, read_mode)) |phantom| {
            applyGvarGlyphMetricDeltas(&outline, default_bounds, metrics, phantom);
        }
        return outline;
    }

    fn glyphOutlineForRaster(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId) FontError!glyph_mod.GlyphOutline {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        // Font.parse has already validated the table grammar and checksums.
        // Rasterization is a hot path that can request dozens of outlines from
        // the same immutable parsed font in one SVG/UI frame; revalidating the
        // whole glyf/CFF/CFF2 table for every glyph makes real rendering do
        // repeated document-level validation work. Keep `glyphOutline()` as the
        // strict defensive API for callers that need post-parse mutation checks,
        // and use this parsed-font fast path for normal rendering.
        return self.glyphOutlineFromParsedTables(allocator, glyph_id, .parsed);
    }

    fn glyphOutlineForReadMode(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, read_mode: OutlineReadMode) FontError!glyph_mod.GlyphOutline {
        return switch (read_mode) {
            .revalidate => try self.glyphOutline(allocator, glyph_id),
            .parsed => try self.glyphOutlineFromParsedTables(allocator, glyph_id, .parsed),
        };
    }

    fn glyphContourPointForShaping(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        point_index: usize,
        normalized_coords: []const f32,
    ) FontError!?glyph_mod.Point {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        if (self.format != .truetype) return null;
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return null;

        const metrics = try self.horizontalMetricsForReadMode(glyph_id, .parsed);
        const bounds = try self.glyphBoundsFromParsedTables(glyph_id);
        var outline = glyph_mod.GlyphOutline.init(
            allocator,
            glyph_id,
            bounds,
            metrics.advance_width,
            metrics.left_side_bearing,
        );
        defer outline.deinit();
        var points = std.ArrayList(glyph_mod.Point).empty;
        defer points.deinit(allocator);
        if (normalizedVariationCoordinatesAreDefault(normalized_coords)) {
            try self.appendGlyphOutline(
                &outline,
                &points,
                glyph_id,
                Transform.identity(),
                0,
            );
        } else {
            try self.appendGlyphOutlineAtCoords(
                &outline,
                &points,
                glyph_id,
                Transform.identity(),
                0,
                normalized_coords,
                .parsed,
            );
        }
        return if (point_index < points.items.len) points.items[point_index] else null;
    }

    fn glyphOutlineFromParsedTables(self: *const Font, allocator: std.mem.Allocator, glyph_id: glyph_mod.GlyphId, read_mode: OutlineReadMode) FontError!glyph_mod.GlyphOutline {
        const metrics = try self.horizontalMetricsForReadMode(glyph_id, read_mode);
        const bounds = if (self.format == .truetype)
            try self.glyphBoundsFromParsedTables(glyph_id)
        else
            glyph_mod.Bounds{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        var outline = glyph_mod.GlyphOutline.init(allocator, glyph_id, bounds, metrics.advance_width, metrics.left_side_bearing);
        errdefer outline.deinit();
        if (self.varc) |varc| {
            if (read_mode.shouldRevalidate()) {
                try sfnt.checksum.validate(self.data, varc);
                try validateVarcTable(self.data, varc, self.glyph_count);
            }
            if (try varc_mod.glyphCoverageIndex(self.data, varc.offset, varc.length, self.glyph_count, glyph_id)) |_| {
                var stack: [64]glyph_mod.GlyphId = undefined;
                const axis_count = if (self.fvar != null) try self.fvarAxisCountForReadMode(read_mode) else 0;
                var scalar_cache = varc_mod.RegionScalarCache{};
                try self.appendVarcGlyphOutline(&outline, glyph_id, Transform.identity(), &.{}, &.{}, axis_count, read_mode, &stack, &scalar_cache, 0);
                outline.bounds = glyph_mod.boundsForCommands(outline.commands.items);
                return outline;
            }
        }
        if (self.format == .truetype) {
            try self.appendGlyphOutline(&outline, null, glyph_id, .{ .xx = 1, .yx = 0, .xy = 0, .yy = 1, .dx = 0, .dy = 0 }, 0);
        } else if (self.cff2) |cff2| {
            if (read_mode.shouldRevalidate()) {
                try sfnt.checksum.validate(self.data, cff2);
                try validateCff2Table(self.data, cff2);
            }
            if (try cff2_mod.appendGlyphOutline(allocator, self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count, &outline)) |bounds_info| {
                outline.bounds = cff2BoundsInfoToGlyphBounds(bounds_info);
            }
        } else {
            const cff = self.cff orelse return error.MissingTable;
            const cff_data = self.data[cff.offset .. cff.offset + cff.length];
            if (read_mode.shouldRevalidate()) {
                // Public outline APIs re-check borrowed CFF bytes before
                // serving a glyph so post-parse mutation cannot hide a
                // truncated CharStrings INDEX behind still-present glyph ids.
                try sfnt.checksum.validate(self.data, cff);
                try validateCffGlyphCount(self.data, cff, self.glyph_count);
                try cff_mod.appendGlyphOutline(allocator, cff_data, try cff_mod.parseInfo(cff_data), &outline, glyph_id);
            } else {
                try cff_mod.appendGlyphOutlinePrepared(allocator, cff_data, self.cff_parsed orelse try cff_mod.parse(cff_data), &outline, glyph_id);
            }
            // Unlike glyf, CFF has no per-glyph header bounds. Materialize them
            // from the executed Type2 path so public extents and raster callers
            // do not inherit the zero-initialized placeholder.
            outline.bounds = glyph_mod.boundsForCommands(outline.commands.items);
        }
        return outline;
    }

    fn varcGlyphOutlineAtCoords(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
        read_mode: OutlineReadMode,
    ) FontError!glyph_mod.GlyphOutline {
        const varc = self.varc orelse return error.UnsupportedGlyph;
        if (read_mode.shouldRevalidate()) {
            try sfnt.checksum.validate(self.data, varc);
            try validateVarcTable(self.data, varc, self.glyph_count);
        }
        const metrics = try self.horizontalMetricsAtCoordsForReadMode(glyph_id, normalized_coords, read_mode);
        const default_bounds = if (self.format == .truetype)
            try self.glyphBoundsFromParsedTables(glyph_id)
        else
            glyph_mod.Bounds{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        var outline = glyph_mod.GlyphOutline.init(
            allocator,
            glyph_id,
            default_bounds,
            metrics.advance_width,
            metrics.left_side_bearing,
        );
        errdefer outline.deinit();

        // VARC evaluates component conditions, transforms, and axis overrides
        // in the current component's coordinate space. RESET_UNSPECIFIED_AXES,
        // however, restores values from the immutable top-level font location,
        // so both slices must remain available throughout recursive expansion.
        const axis_count = if (self.fvar != null)
            try self.fvarAxisCountForReadMode(read_mode)
        else
            normalized_coords.len;
        var stack: [64]glyph_mod.GlyphId = undefined;
        var scalar_cache = varc_mod.RegionScalarCache{};
        try self.appendVarcGlyphOutline(
            &outline,
            glyph_id,
            Transform.identity(),
            normalized_coords,
            normalized_coords,
            axis_count,
            read_mode,
            &stack,
            &scalar_cache,
            0,
        );
        outline.bounds = glyph_mod.boundsForCommands(outline.commands.items);
        return outline;
    }

    fn appendVarcGlyphOutline(
        self: *const Font,
        outline: *glyph_mod.GlyphOutline,
        glyph_id: glyph_mod.GlyphId,
        parent_transform: Transform,
        normalized_coords: []const f32,
        font_coords: []const f32,
        font_axis_count: usize,
        read_mode: OutlineReadMode,
        stack: *[64]glyph_mod.GlyphId,
        scalar_cache: *varc_mod.RegionScalarCache,
        depth: usize,
    ) FontError!void {
        if (depth >= stack.len) return error.CompoundDepthExceeded;
        for (stack[0..depth]) |ancestor| {
            if (ancestor == glyph_id) return try self.appendBaseOutlineTransformed(outline, glyph_id, parent_transform, normalized_coords, read_mode);
        }
        const varc = self.varc orelse return try self.appendBaseOutlineTransformed(outline, glyph_id, parent_transform, normalized_coords, read_mode);
        const coverage_index = (try varc_mod.glyphCoverageIndex(self.data, varc.offset, varc.length, self.glyph_count, glyph_id)) orelse
            return try self.appendBaseOutlineTransformed(outline, glyph_id, parent_transform, normalized_coords, read_mode);
        stack[depth] = glyph_id;
        var components = try varc_mod.componentIterator(self.data, varc.offset, varc.length, self.glyph_count, coverage_index);
        while (try components.next()) |component| {
            if (component.condition_index) |condition_index| {
                if (!(try varc_mod.conditionMatchesWithCache(
                    self.data,
                    varc.offset,
                    varc.length,
                    condition_index,
                    normalized_coords,
                    scalar_cache,
                ))) continue;
            }
            if (component.glyph_id > std.math.maxInt(glyph_mod.GlyphId)) return error.InvalidGlyph;
            const child_glyph: glyph_mod.GlyphId = @intCast(component.glyph_id);
            const component_transform = try varc_mod.componentTransformWithCache(
                self.data,
                varc.offset,
                varc.length,
                component,
                normalized_coords,
                scalar_cache,
            );
            const child_transform = parent_transform.mul(transformFromVarc(component_transform));
            const coordinates_unchanged = (component.flags &
                (varc_mod.ComponentFlags.have_axes | varc_mod.ComponentFlags.reset_unspecified_axes)) == 0;
            // Missing trailing normalized coordinates are semantically zero, so
            // a component that neither overrides axes nor resets unspecified
            // axes can borrow its parent's slice directly. Only coordinate
            // remapping needs writable storage that survives the recursive call.
            const child_coord_count = varc_mod.componentCoordinateCount(normalized_coords, font_coords, font_axis_count);
            var inline_child_coords: [32]f32 = undefined;
            const child_coord_storage = if (coordinates_unchanged)
                null
            else if (child_coord_count <= inline_child_coords.len)
                inline_child_coords[0..child_coord_count]
            else
                try outline.allocator.alloc(f32, child_coord_count);
            defer if (child_coord_storage) |coords| {
                if (child_coord_count > inline_child_coords.len) outline.allocator.free(coords);
            };
            if (child_coord_storage) |coords| {
                try varc_mod.componentCoordinatesIntoWithCache(
                    outline.allocator,
                    self.data,
                    varc.offset,
                    varc.length,
                    component,
                    normalized_coords,
                    font_coords,
                    font_axis_count,
                    coords,
                    scalar_cache,
                );
            }
            const child_coords = child_coord_storage orelse normalized_coords;
            if (child_glyph == glyph_id) {
                try self.appendBaseOutlineTransformed(outline, child_glyph, child_transform, child_coords, read_mode);
            } else {
                var child_scalar_cache = varc_mod.RegionScalarCache{};
                const recursion_cache = if (coordinates_unchanged) scalar_cache else &child_scalar_cache;
                try self.appendVarcGlyphOutline(
                    outline,
                    child_glyph,
                    child_transform,
                    child_coords,
                    font_coords,
                    font_axis_count,
                    read_mode,
                    stack,
                    recursion_cache,
                    depth + 1,
                );
            }
        }
    }

    fn appendBaseOutlineTransformed(
        self: *const Font,
        outline: *glyph_mod.GlyphOutline,
        glyph_id: glyph_mod.GlyphId,
        transform: Transform,
        normalized_coords: []const f32,
        read_mode: OutlineReadMode,
    ) FontError!void {
        if (self.format == .truetype) {
            if (normalizedVariationCoordinatesAreDefault(normalized_coords) or self.gvar == null) {
                try self.appendGlyphOutline(outline, null, glyph_id, transform, 0);
            } else {
                var points = std.ArrayList(glyph_mod.Point).empty;
                defer points.deinit(outline.allocator);
                try self.appendGlyphOutlineAtCoords(outline, &points, glyph_id, transform, 0, normalized_coords, read_mode);
            }
            return;
        }

        const command_start = outline.commands.items.len;
        if (self.cff2) |cff2| {
            if (read_mode.shouldRevalidate()) {
                try sfnt.checksum.validate(self.data, cff2);
                try validateCff2Table(self.data, cff2);
            }
            if (normalizedVariationCoordinatesAreDefault(normalized_coords)) {
                _ = try cff2_mod.appendGlyphOutline(outline.allocator, self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count, outline);
            } else {
                _ = try cff2_mod.appendGlyphOutlineAtCoords(outline.allocator, self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count, normalized_coords, outline);
            }
        } else {
            const cff = self.cff orelse return error.MissingTable;
            const cff_data = self.data[cff.offset .. cff.offset + cff.length];
            if (read_mode.shouldRevalidate()) {
                try sfnt.checksum.validate(self.data, cff);
                try validateCffGlyphCount(self.data, cff, self.glyph_count);
                try cff_mod.appendGlyphOutline(outline.allocator, cff_data, try cff_mod.parseInfo(cff_data), outline, glyph_id);
            } else {
                try cff_mod.appendGlyphOutlinePrepared(outline.allocator, cff_data, self.cff_parsed orelse try cff_mod.parse(cff_data), outline, glyph_id);
            }
        }
        transformPathCommands(outline.commands.items[command_start..], transform);
    }

    fn gvarTargetCount(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!usize {
        if (self.format != .truetype) return error.UnsupportedGlyph;
        const loca = self.loca orelse return error.MissingTable;
        const glyf = self.glyf orelse return error.MissingTable;
        return try gvarGlyphTargetCount(self.data, .{
            .loca = loca,
            .glyf = glyf,
            .index_to_loc_format = self.index_to_loc_format,
        }, glyph_id);
    }

    fn gvarTargetCountForGlyphData(glyph_data: []const u8) FontError!usize {
        return (try gvar_mod.glyfVariationPointCount(glyph_data)) + 4;
    }

    const GvarMetricVariationTarget = struct {
        glyph_id: glyph_mod.GlyphId,
        point_count: usize,
    };

    fn gvarMetricVariationTarget(self: *const Font, glyph_id: glyph_mod.GlyphId, depth: u8) FontError!GvarMetricVariationTarget {
        if (depth > 64) return error.CompoundDepthExceeded;
        const data = try self.glyphData(glyph_id);
        return switch (try gvar_mod.glyfMetricTarget(data, self.glyph_count)) {
            .self => |point_count| .{ .glyph_id = glyph_id, .point_count = point_count },
            .component => |component_glyph| try self.gvarMetricVariationTarget(component_glyph, depth + 1),
        };
    }

    fn glyphBoundsFromParsedTables(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!glyph_mod.Bounds {
        const slice = try self.glyphData(glyph_id);
        if (slice.len == 0) return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        return .{
            .x_min = try bin.readI16At(slice, 2),
            .y_min = try bin.readI16At(slice, 4),
            .x_max = try bin.readI16At(slice, 6),
            .y_max = try bin.readI16At(slice, 8),
        };
    }

    fn cff2BoundsInfoToGlyphBounds(bounds: Cff2CharStringBoundsInfo) glyph_mod.Bounds {
        if (!bounds.has_bounds) return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
        // HarfBuzz/FreeType report CFF2 glyph extents by rounding each design
        // coordinate to the nearest FUnit with OpenType's +infinity tie rule.
        // Expanding minima with floor and maxima with ceil makes every
        // fractional outline one unit too wide or tall.
        return .{
            .x_min = clampF32ToI16(roundOpenTypeF32(bounds.x_min)),
            .y_min = clampF32ToI16(roundOpenTypeF32(bounds.y_min)),
            .x_max = clampF32ToI16(roundOpenTypeF32(bounds.x_max)),
            .y_max = clampF32ToI16(roundOpenTypeF32(bounds.y_max)),
        };
    }

    fn clampF32ToI16(value: f32) i16 {
        if (value <= @as(f32, @floatFromInt(std.math.minInt(i16)))) return std.math.minInt(i16);
        if (value >= @as(f32, @floatFromInt(std.math.maxInt(i16)))) return std.math.maxInt(i16);
        return @intFromFloat(value);
    }

    test "CFF2 fractional bounds use OpenType nearest rounding" {
        try std.testing.expectEqual(glyph_mod.Bounds{
            .x_min = 52,
            .y_min = -115,
            .x_max = 437,
            .y_max = 759,
        }, cff2BoundsInfoToGlyphBounds(.{
            .has_bounds = true,
            .x_min = 52.456,
            .y_min = -115.0,
            .x_max = 437.174,
            .y_max = 758.739,
        }));
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

    fn appendGlyphOutline(self: *const Font, outline: *glyph_mod.GlyphOutline, points: ?*std.ArrayList(glyph_mod.Point), glyph_id: glyph_mod.GlyphId, transform: Transform, depth: u8) FontError!void {
        if (depth > 8) return error.CompoundDepthExceeded;
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return;
        const contour_count = try bin.readI16At(data, 0);
        if (contour_count >= 0) {
            // Simple glyf outlines store contour end points plus compressed
            // point deltas. Compound outlines recurse into component glyphs.
            _ = try appendSimpleGlyph(outline, points, data, @intCast(contour_count), transform, null);
        } else if (points) |compound_points| {
            try self.appendCompoundGlyph(outline, compound_points, data, transform, depth + 1);
        } else {
            // Raw TrueType point indices are observable only while expanding a
            // compound glyph. Keep the overwhelmingly common simple-glyph path
            // allocation-free, and create one shared point array only after the
            // top-level glyph has proved to be compound.
            var compound_points = std.ArrayList(glyph_mod.Point).empty;
            defer compound_points.deinit(outline.allocator);
            try self.appendCompoundGlyph(outline, &compound_points, data, transform, depth + 1);
        }
    }

    fn appendGlyphOutlineAtCoords(self: *const Font, outline: *glyph_mod.GlyphOutline, points: *std.ArrayList(glyph_mod.Point), glyph_id: glyph_mod.GlyphId, transform: Transform, depth: u8, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!void {
        if (depth > 8) return error.CompoundDepthExceeded;
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return;
        const contour_count = try bin.readI16At(data, 0);
        if (contour_count >= 0) {
            const variation = try self.simpleGlyphVariationContext(glyph_id, normalized_coords, read_mode);
            _ = try appendSimpleGlyph(outline, points, data, @intCast(contour_count), transform, variation);
        } else {
            try self.appendCompoundGlyphAtCoords(outline, points, data, transform, depth + 1, glyph_id, normalized_coords, read_mode);
        }
    }

    fn appendCompoundGlyph(self: *const Font, outline: *glyph_mod.GlyphOutline, points: *std.ArrayList(glyph_mod.Point), data: []const u8, parent_transform: Transform, depth: u8) FontError!void {
        var r = bin.Reader.init(data);
        _ = try r.readI16();
        try r.skip(8);
        const parent_point_start = points.items.len;
        while (true) {
            const component = try readCompoundGlyphComponent(&r);
            switch (component.placement) {
                .offset => |offset| {
                    var child = component.linear_transform;
                    child.dx = @floatFromInt(offset.x);
                    child.dy = @floatFromInt(offset.y);
                    try self.appendGlyphOutline(outline, points, component.glyph_id, parent_transform.mul(child), depth);
                },
                .points => |point_match| {
                    try self.appendPointMatchedComponent(
                        outline,
                        points,
                        component.glyph_id,
                        parent_transform.mul(component.linear_transform),
                        depth,
                        parent_point_start,
                        point_match,
                    );
                },
            }
            if ((component.flags & 0x0020) == 0) break;
        }
    }

    fn appendPointMatchedComponent(
        self: *const Font,
        outline: *glyph_mod.GlyphOutline,
        points: *std.ArrayList(glyph_mod.Point),
        component_glyph: glyph_mod.GlyphId,
        transform: Transform,
        depth: u8,
        parent_point_start: usize,
        point_match: CompoundGlyphPointMatch,
    ) FontError!void {
        const child_point_start = points.items.len;
        const child_command_start = outline.commands.items.len;
        try self.appendGlyphOutline(outline, points, component_glyph, transform, depth);
        try placePointMatchedComponent(outline, points, parent_point_start, child_point_start, child_command_start, point_match);
    }

    fn appendCompoundGlyphAtCoords(self: *const Font, outline: *glyph_mod.GlyphOutline, points: *std.ArrayList(glyph_mod.Point), data: []const u8, parent_transform: Transform, depth: u8, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!void {
        const target_count = try gvarTargetCountForGlyphData(data);
        const maybe_deltas = try self.gvarPointDeltasAtCoordsPreparedNoShrink(outline.allocator, glyph_id, normalized_coords, target_count, null, read_mode);
        defer if (maybe_deltas) |deltas| outline.allocator.free(deltas);

        var r = bin.Reader.init(data);
        _ = try r.readI16();
        try r.skip(8);
        const parent_point_start = points.items.len;
        var component_index: usize = 0;
        while (true) : (component_index += 1) {
            const component = try readCompoundGlyphComponent(&r);
            switch (component.placement) {
                .offset => |offset| {
                    const component_delta = if (maybe_deltas) |deltas| gvarDeltaForPoint(deltas, component_index) else gvar_mod.Point{ .x = 0, .y = 0 };
                    var child = component.linear_transform;
                    child.dx = @as(f32, @floatFromInt(offset.x)) + roundOpenTypeF32(component_delta.x);
                    child.dy = @as(f32, @floatFromInt(offset.y)) + roundOpenTypeF32(component_delta.y);
                    try self.appendGlyphOutlineAtCoords(outline, points, component.glyph_id, parent_transform.mul(child), depth, normalized_coords, read_mode);
                },
                .points => |point_match| {
                    const child_point_start = points.items.len;
                    const child_command_start = outline.commands.items.len;
                    try self.appendGlyphOutlineAtCoords(
                        outline,
                        points,
                        component.glyph_id,
                        parent_transform.mul(component.linear_transform),
                        depth,
                        normalized_coords,
                        read_mode,
                    );
                    // A compound gvar tuple describes component translation
                    // deltas. Point-anchored components have no translation
                    // argument to vary, so FreeType and fontations deliberately
                    // ignore that component delta and derive placement solely
                    // from the two varied, linearly transformed anchor points.
                    try placePointMatchedComponent(outline, points, parent_point_start, child_point_start, child_command_start, point_match);
                },
            }
            if ((component.flags & 0x0020) == 0) break;
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

fn transformFromVarc(value: varc_mod.StaticTransform) Transform {
    return .{
        .xx = value.xx,
        .yx = value.yx,
        .xy = value.xy,
        .yy = value.yy,
        .dx = value.dx,
        .dy = value.dy,
    };
}

fn transformPathCommands(commands: []glyph_mod.PathCommand, transform: Transform) void {
    for (commands) |*command| {
        switch (command.*) {
            .move_to => |*point| point.* = transform.apply(point.*),
            .line_to => |*point| point.* = transform.apply(point.*),
            .quad_to => |*curve| {
                curve.control = transform.apply(curve.control);
                curve.end = transform.apply(curve.end);
            },
            .cubic_to => |*curve| {
                curve.c0 = transform.apply(curve.c0);
                curve.c1 = transform.apply(curve.c1);
                curve.end = transform.apply(curve.end);
            },
            .close => {},
        }
    }
}

const CompoundGlyphPlacement = union(enum) {
    offset: struct { x: i16, y: i16 },
    points: CompoundGlyphPointMatch,
};

const CompoundGlyphRuntimeComponent = struct {
    flags: u16,
    glyph_id: glyph_mod.GlyphId,
    placement: CompoundGlyphPlacement,
    linear_transform: Transform,
};

fn readCompoundGlyphComponent(r: *bin.Reader) FontError!CompoundGlyphRuntimeComponent {
    const flags = try r.readU16();
    const glyph_id = try r.readU16();
    const placement: CompoundGlyphPlacement = if ((flags & 0x0002) != 0)
        .{ .offset = if ((flags & 0x0001) != 0)
            .{ .x = try r.readI16(), .y = try r.readI16() }
        else
            .{ .x = try r.readI8(), .y = try r.readI8() } }
    else
        .{ .points = if ((flags & 0x0001) != 0)
            .{ .parent_point = try r.readU16(), .child_point = try r.readU16() }
        else
            .{ .parent_point = try r.readU8(), .child_point = try r.readU8() } };

    var transform = Transform.identity();
    if ((flags & 0x0008) != 0) {
        const scale = f2dot14(try r.readI16());
        transform.xx = scale;
        transform.yy = scale;
    } else if ((flags & 0x0040) != 0) {
        transform.xx = f2dot14(try r.readI16());
        transform.yy = f2dot14(try r.readI16());
    } else if ((flags & 0x0080) != 0) {
        transform.xx = f2dot14(try r.readI16());
        transform.yx = f2dot14(try r.readI16());
        transform.xy = f2dot14(try r.readI16());
        transform.yy = f2dot14(try r.readI16());
    }
    return .{
        .flags = flags,
        .glyph_id = glyph_id,
        .placement = placement,
        .linear_transform = transform,
    };
}

fn placePointMatchedComponent(
    outline: *glyph_mod.GlyphOutline,
    points: *std.ArrayList(glyph_mod.Point),
    parent_point_start: usize,
    child_point_start: usize,
    child_command_start: usize,
    point_match: CompoundGlyphPointMatch,
) FontError!void {
    const parent_index = parent_point_start + @as(usize, point_match.parent_point);
    const child_index = child_point_start + @as(usize, point_match.child_point);
    // Parse-time graph validation normally proves both accesses. Keep the
    // materializer defensive as well: glyphOutlineForRaster() intentionally
    // trusts parsed bytes, and no malformed or post-parse-mutated point number
    // should turn that trust boundary into an out-of-bounds access.
    if (parent_index >= child_point_start or child_index >= points.items.len) return error.InvalidGlyph;

    const parent_point = points.items[parent_index];
    const child_point = points.items[child_index];
    const offset = glyph_mod.Point{
        .x = parent_point.x - child_point.x,
        .y = parent_point.y - child_point.y,
    };
    if (offset.x == 0 and offset.y == 0) return;

    for (points.items[child_point_start..]) |*point| translateGlyphPoint(point, offset);
    for (outline.commands.items[child_command_start..]) |*command| translatePathCommand(command, offset);
}

fn translateGlyphPoint(point: *glyph_mod.Point, offset: glyph_mod.Point) void {
    point.x += offset.x;
    point.y += offset.y;
}

fn translatePathCommand(command: *glyph_mod.PathCommand, offset: glyph_mod.Point) void {
    switch (command.*) {
        .move_to => |*point| translateGlyphPoint(point, offset),
        .line_to => |*point| translateGlyphPoint(point, offset),
        .quad_to => |*curve| {
            translateGlyphPoint(&curve.control, offset);
            translateGlyphPoint(&curve.end, offset);
        },
        .cubic_to => |*curve| {
            translateGlyphPoint(&curve.c0, offset);
            translateGlyphPoint(&curve.c1, offset);
            translateGlyphPoint(&curve.end, offset);
        },
        .close => {},
    }
}

fn validateSbixTable(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: TableRecord,
    glyph_count: u16,
) FontError!void {
    return try bitmap_mod.sbix.validate(
        allocator,
        data,
        bitmapTable(table),
        glyph_count,
    );
}

fn validateCblcCbdtTables(
    data: []const u8,
    location_table: TableRecord,
    data_table: TableRecord,
    glyph_count: u16,
) FontError!void {
    return try bitmap_mod.cblc.validate(
        data,
        bitmapTable(location_table),
        bitmapTable(data_table),
        glyph_count,
    );
}

/// Internal shaping backend. This is intentionally absent from `cangjie.font`;
/// only repository pipeline modules import `font.zig` directly.
pub const shaping = struct {
    pub const applyGsub = Font.applyGsub;
    pub const collectGposAdjustments = Font.collectGposAdjustments;
    pub const verticalOriginYAtCoords = Font.shapingVerticalOriginYAtCoords;
    pub const horizontalTrackingForShaping = Font.horizontalTrackingForShaping;
    pub const kernLookupForShaping = Font.kernLookupForShaping;
    pub const kerxLookupForShaping = Font.kerxLookupForShaping;
    pub const applyGsubWithOptionsUsingGdefForShaping = Font.applyGsubWithOptionsUsingGdefForShaping;
    pub const proveGsubTableForShaping = Font.proveGsubTableForShaping;
    pub const selectGsubScriptForShaping = Font.selectGsubScriptForShaping;
    pub const selectGposScriptForShaping = Font.selectGposScriptForShaping;
    pub const applyGsubWithOptionsUsingGdefAfterProof = Font.applyGsubWithOptionsUsingGdefAfterProof;
    pub const applyGsubCachedLookupSelectionUsingGdefAfterRunProof = Font.applyGsubCachedLookupSelectionUsingGdefAfterRunProof;
    pub const selectGsubLookupsForShaping = Font.selectGsubLookupsForShaping;
    pub const selectGsubFeatureLookupsAfterProof = Font.selectGsubFeatureLookupsAfterProof;
    pub const applyGsubSelectedSourceFeatureAfterProof = Font.applyGsubSelectedSourceFeatureAfterProof;
    pub const hasGsubFeatureForShaping = Font.hasGsubFeatureForShaping;
    pub const hasGsubRandomFeatureWithAcceleratorsForShaping = Font.hasGsubRandomFeatureWithAcceleratorsForShaping;
    pub const gsubLookupAcceleratorsForShaping = Font.gsubLookupAcceleratorsForShaping;
    pub const gsubFeatureLookupPlanForShaping = Font.gsubFeatureLookupPlanForShaping;
    pub const gsubMergedFeatureLookupPlanForShaping = Font.gsubMergedFeatureLookupPlanForShaping;
    pub const applyGsubFeatureSequenceWithOptionsUsingGdefForShaping = Font.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping;
    pub const applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof = Font.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof;
    pub const applyGsubFeatureLookupPlanUsingGdefAfterProof = Font.applyGsubFeatureLookupPlanUsingGdefAfterProof;
    pub const applyGsubFeatureLookupPlanUsingGdefAfterRunProof = Font.applyGsubFeatureLookupPlanUsingGdefAfterRunProof;
    pub const applyGsubMergedFeatureLookupPlanUsingGdefAfterProof = Font.applyGsubMergedFeatureLookupPlanUsingGdefAfterProof;
    pub const applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof = Font.applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof;
    pub const collectGposAdjustmentsWithOptionsUsingGdefForShaping = Font.collectGposAdjustmentsWithOptionsUsingGdefForShaping;
    pub const proveGposTableForShaping = Font.proveGposTableForShaping;
    pub const hasGposTableForShaping = Font.hasGposTableForShaping;
    pub const hasGsubTableForShaping = Font.hasGsubTableForShaping;
    pub const hasKerxTableForShaping = Font.hasKerxTableForShaping;
    pub const hasMorxTableForShaping = Font.hasMorxTableForShaping;
    pub const hasAatSubstitutionForShaping = Font.hasAatSubstitutionForShaping;
    pub const applyAatSubstitutionForShaping = Font.applyAatSubstitutionForShaping;
    pub const applyMorxForShaping = Font.applyMorxForShaping;
    pub const collectGposAdjustmentsWithOptionsUsingGdefAfterProof = Font.collectGposAdjustmentsWithOptionsUsingGdefAfterProof;
    pub const selectGposLookupsForShaping = Font.selectGposLookupsForShaping;
    pub const gposLookupAcceleratorsForShaping = Font.gposLookupAcceleratorsForShaping;
    pub const gdefLookupMetadataForShaping = Font.gdefLookupMetadataForShaping;
    pub const validateShapedGlyphRunForShaping = Font.validateShapedGlyphRunForShaping;
    pub const shapingVerticalOriginYForShaping = Font.shapingVerticalOriginYForShaping;
};

/// Internal rendering backend that trusts the whole-face proof established by
/// `Face.parse` and therefore skips per-glyph borrowed-byte revalidation.
pub const raster_backend = struct {
    pub const resolvedSvgGlyphDocument = Font.resolvedSvgGlyphDocumentForRaster;
    pub const glyphOutlineAtCoords = Font.glyphOutlineForRasterAtCoords;
    pub const glyphOutline = Font.glyphOutlineForRaster;
};

fn readFontHeaderInfo(data: []const u8, head: TableRecord) FontError!FontHeaderInfo {
    try sfnt.requireLength(head, 54);
    return .{
        .table_version = try bin.readU32At(data, head.offset),
        .font_revision = fixed16_16ToF32(try bin.readI32At(data, head.offset + 4)),
        .flags = try bin.readU16At(data, head.offset + 16),
        .units_per_em = try bin.readU16At(data, head.offset + 18),
        .created = try readI64At(data, head.offset + 20),
        .modified = try readI64At(data, head.offset + 28),
        .bounds = .{
            .x_min = try bin.readI16At(data, head.offset + 36),
            .y_min = try bin.readI16At(data, head.offset + 38),
            .x_max = try bin.readI16At(data, head.offset + 40),
            .y_max = try bin.readI16At(data, head.offset + 42),
        },
        .mac_style = try bin.readU16At(data, head.offset + 44),
        .lowest_rec_ppem = try bin.readU16At(data, head.offset + 46),
        .font_direction_hint = try bin.readI16At(data, head.offset + 48),
        .index_to_loc_format = try bin.readI16At(data, head.offset + 50),
        .glyph_data_format = try bin.readI16At(data, head.offset + 52),
    };
}

fn readI64At(data: []const u8, offset: usize) FontError!i64 {
    const high = try bin.readU32At(data, offset);
    const low = try bin.readU32At(data, offset + 4);
    return @bitCast((@as(u64, high) << 32) | low);
}

fn validateHeadTable(data: []const u8, head: TableRecord, format: FontFormat) FontError!void {
    try sfnt.requireLength(head, 54);

    const version = try bin.readU32At(data, head.offset);
    const magic_number = try bin.readU32At(data, head.offset + 12);
    const units_per_em = try bin.readU16At(data, head.offset + 18);
    const x_min = try bin.readI16At(data, head.offset + 36);
    const y_min = try bin.readI16At(data, head.offset + 38);
    const x_max = try bin.readI16At(data, head.offset + 40);
    const y_max = try bin.readI16At(data, head.offset + 42);
    const mac_style = try bin.readU16At(data, head.offset + 44);
    const lowest_rec_ppem = try bin.readU16At(data, head.offset + 46);
    const font_direction_hint = try bin.readI16At(data, head.offset + 48);
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
    // macStyle is a seven-bit legacy summary field in `head`; higher bits are
    // reserved and must stay zero so style matching does not inherit unknown
    // future semantics. lowestRecPPEM is a pixel size, so zero is not a
    // meaningful recommendation. fontDirectionHint is deprecated, but OpenType
    // still constrains accepted stored values to the historical -2..2 range.
    if ((mac_style & 0xff80) != 0) return error.BadSfnt;
    if (lowest_rec_ppem == 0) return error.BadSfnt;
    if (font_direction_hint < -2 or font_direction_hint > 2) return error.BadSfnt;

    // indexToLocFormat only drives glyf/loca lookup.  CFF-backed OpenType
    // faces do not have a loca table, so avoid rejecting legacy production OTFs
    // for an otherwise-unused field while still validating TrueType faces before
    // their loca table is interpreted.
    if (format == .truetype and index_to_loc_format != 0 and index_to_loc_format != 1) {
        return error.InvalidLoca;
    }
    if (glyph_data_format != 0) return error.BadSfnt;
}

fn readMaxProfileInfo(data: []const u8, maxp: TableRecord) FontError!MaxProfileInfo {
    try sfnt.requireLength(maxp, 6);
    const version = try bin.readU32At(data, maxp.offset);
    var info = MaxProfileInfo{
        .version = version,
        .glyph_count = try bin.readU16At(data, maxp.offset + 4),
    };
    if (version == 0x00010000) {
        try sfnt.requireLength(maxp, 32);
        info.max_points = try bin.readU16At(data, maxp.offset + 6);
        info.max_contours = try bin.readU16At(data, maxp.offset + 8);
        info.max_composite_points = try bin.readU16At(data, maxp.offset + 10);
        info.max_composite_contours = try bin.readU16At(data, maxp.offset + 12);
        info.max_zones = try bin.readU16At(data, maxp.offset + 14);
        info.max_twilight_points = try bin.readU16At(data, maxp.offset + 16);
        info.max_storage = try bin.readU16At(data, maxp.offset + 18);
        info.max_function_defs = try bin.readU16At(data, maxp.offset + 20);
        info.max_instruction_defs = try bin.readU16At(data, maxp.offset + 22);
        info.max_stack_elements = try bin.readU16At(data, maxp.offset + 24);
        info.max_size_of_instructions = try bin.readU16At(data, maxp.offset + 26);
        info.max_component_elements = try bin.readU16At(data, maxp.offset + 28);
        info.max_component_depth = try bin.readU16At(data, maxp.offset + 30);
    }
    return info;
}

fn validateMaxpTable(data: []const u8, maxp: TableRecord, format: FontFormat) FontError!void {
    try sfnt.requireLength(maxp, 6);
    const version = try bin.readU32At(data, maxp.offset);
    switch (format) {
        .truetype => {
            // TrueType outlines require the version 1.0 maxp payload because
            // rasterizers use its glyph-program and composite limits when
            // validating glyf instructions. Accepting the six-byte CFF shape
            // here would silently classify an internally inconsistent SFNT as
            // a usable TrueType face.
            if (version != 0x00010000) return error.BadSfnt;
            // maxp v1.0 is a fixed 32-byte table. Reject tail bytes so the
            // trusted glyph-count/summary contract is consumed identically by
            // parsers that borrow table bytes and by consumers that cache it.
            if (maxp.length != 32) return error.BadSfnt;
        },
        .opentype_cff => {
            // CFF-backed OpenType fonts use maxp version 0.5, whose contract is
            // only the version and numGlyphs fields. A version 1.0 maxp table
            // belongs to glyf-based fonts and indicates a mismatched outline
            // stack even when the CFF table is otherwise present.
            if (version != 0x00005000) return error.BadSfnt;
            // maxp v0.5 has only version and numGlyphs.
            if (maxp.length != 6) return error.BadSfnt;
        },
    }
}

fn selectOutlineFormat(data: []const u8, maxp: TableRecord, declared_format: FontFormat, has_glyf_outlines: bool, has_cff_outlines: bool) FontError!FontFormat {
    try sfnt.requireLength(maxp, 6);
    const version = try bin.readU32At(data, maxp.offset);
    // Some text-rendering fixtures deliberately carry both glyf and CFF under
    // conflicting sfnt flavors. HarfBuzz selects the internally complete
    // outline stack: maxp 1.0 describes glyf limits, while maxp 0.5 is the CFF
    // glyph-count form. Preserve the scaler as a fallback so malformed
    // topologies still reach the strict format-specific validator below.
    if (has_glyf_outlines and version == 0x00010000 and maxp.length == 32) return .truetype;
    if (has_cff_outlines and version == 0x00005000 and maxp.length == 6) return .opentype_cff;
    return declared_format;
}

test "outline format follows complete maxp-backed table stack" {
    var maxp_10: [32]u8 = .{0} ** 32;
    writeU32Test(&maxp_10, 0, 0x00010000);
    const record_10 = TableRecord{ .tag = .{ 'm', 'a', 'x', 'p' }, .checksum = 0, .offset = 0, .length = maxp_10.len };
    try std.testing.expectEqual(FontFormat.truetype, try selectOutlineFormat(&maxp_10, record_10, .opentype_cff, true, true));

    var maxp_05: [6]u8 = .{0} ** 6;
    writeU32Test(&maxp_05, 0, 0x00005000);
    const record_05 = TableRecord{ .tag = .{ 'm', 'a', 'x', 'p' }, .checksum = 0, .offset = 0, .length = maxp_05.len };
    try std.testing.expectEqual(FontFormat.opentype_cff, try selectOutlineFormat(&maxp_05, record_05, .truetype, true, true));
}

fn validateCff2Table(data: []const u8, cff2: TableRecord) FontError!void {
    return try cff2_mod.validate(data, cff2.offset, cff2.length);
}

fn validateCffGlyphCount(data: []const u8, cff: TableRecord, glyph_count: u16) FontError!void {
    // For CFF-backed OpenType faces, maxp.numGlyphs must describe the
    // CharStrings INDEX exactly. Validate the relationship during parse so
    // callers do not accept a face whose cmap or shaping tables can name
    // glyph ids that the CFF outline data can never resolve.
    const info = try cff_mod.parseInfo(data[cff.offset .. cff.offset + cff.length]);
    if (info.charstrings_count != glyph_count) return error.BadSfnt;
}

fn validateMetaTable(data: []const u8, meta: TableRecord) FontError!void {
    return try meta_mod.validate(data, meta.offset, meta.length);
}

fn validateMathTable(data: []const u8, math: TableRecord) FontError!void {
    return try math_mod.validate(data, math.offset, math.length);
}

fn validateDsigTable(data: []const u8, dsig: TableRecord) FontError!void {
    try sfnt.requireLength(dsig, 8);
    if (try bin.readU32At(data, dsig.offset) != 1) return error.BadSfnt;
    const signature_count = try bin.readU16At(data, dsig.offset + 4);
    const flags = try bin.readU16At(data, dsig.offset + 6);
    if ((flags & ~@as(u16, 0x0001)) != 0) return error.BadSfnt;
    const records_end = 8 + @as(usize, signature_count) * 12;
    if (records_end > dsig.length) return error.BadSfnt;
    var previous_end: usize = records_end;
    for (0..signature_count) |index| {
        const record = dsig.offset + 8 + index * 12;
        const format = try bin.readU32At(data, record);
        if (format != 1) return error.BadSfnt;
        const length: usize = @intCast(try bin.readU32At(data, record + 4));
        const offset: usize = @intCast(try bin.readU32At(data, record + 8));
        if (offset < records_end or offset > dsig.length or length > dsig.length - offset) return error.BadSfnt;
        if (offset < previous_end) return error.BadSfnt;
        const block = dsig.offset + offset;
        if (length < 8) return error.BadSfnt;
        if (try bin.readU16At(data, block) != 0 or try bin.readU16At(data, block + 2) != 0) return error.BadSfnt;
        const signature_len: usize = @intCast(try bin.readU32At(data, block + 4));
        if (signature_len != length - 8) return error.BadSfnt;
        previous_end = offset + length;
    }
}

fn readDsigInfo(allocator: std.mem.Allocator, data: []const u8, dsig: TableRecord) FontError!DsigInfo {
    const signature_count = try bin.readU16At(data, dsig.offset + 4);
    const signatures = try allocator.alloc(DsigSignatureInfo, signature_count);
    errdefer allocator.free(signatures);
    for (signatures, 0..) |*signature, index| {
        const record = dsig.offset + 8 + index * 12;
        const length: usize = @intCast(try bin.readU32At(data, record + 4));
        const offset: usize = @intCast(try bin.readU32At(data, record + 8));
        const block = dsig.offset + offset;
        signature.* = .{
            .format = try bin.readU32At(data, record),
            .offset = offset,
            .length = length,
            .signature = data[block + 8 .. block + length],
        };
    }
    return .{
        .version = try bin.readU32At(data, dsig.offset),
        .flags = try bin.readU16At(data, dsig.offset + 6),
        .signatures = signatures,
    };
}

fn validateVorgTable(data: []const u8, vorg: TableRecord, glyph_count: u16) FontError!void {
    try sfnt.requireLength(vorg, 8);
    if (try bin.readU32At(data, vorg.offset) != 0x00010000) return error.BadSfnt;
    const count = try bin.readU16At(data, vorg.offset + 6);
    if (@as(usize, count) * 4 > vorg.length - 8) return error.BadSfnt;
    if (vorg.length != 8 + @as(usize, count) * 4) return error.BadSfnt;
    var previous: ?glyph_mod.GlyphId = null;
    for (0..count) |index| {
        const record = vorg.offset + 8 + index * 4;
        const glyph_id = try bin.readU16At(data, record);
        if (glyph_id >= glyph_count) return error.BadSfnt;
        if (previous) |last| {
            if (glyph_id <= last) return error.BadSfnt;
        }
        previous = glyph_id;
    }
}

fn readVorgInfo(allocator: std.mem.Allocator, data: []const u8, vorg: TableRecord) FontError!VerticalOriginInfo {
    const count = try bin.readU16At(data, vorg.offset + 6);
    const metrics = try allocator.alloc(VerticalOriginMetric, count);
    errdefer allocator.free(metrics);
    for (metrics, 0..) |*metric, index| {
        const record = vorg.offset + 8 + index * 4;
        metric.* = .{
            .glyph_id = try bin.readU16At(data, record),
            .origin_y = try bin.readI16At(data, record + 2),
        };
    }
    return .{
        .default_origin_y = try bin.readI16At(data, vorg.offset + 4),
        .metrics = metrics,
    };
}

fn vorgOriginY(data: []const u8, vorg: TableRecord, glyph_id: glyph_mod.GlyphId) FontError!i16 {
    const count = try bin.readU16At(data, vorg.offset + 6);
    var lo: usize = 0;
    var hi: usize = count;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const record = vorg.offset + 8 + mid * 4;
        const candidate = try bin.readU16At(data, record);
        if (glyph_id < candidate) {
            hi = mid;
        } else if (glyph_id > candidate) {
            lo = mid + 1;
        } else {
            return try bin.readI16At(data, record + 2);
        }
    }
    return try bin.readI16At(data, vorg.offset + 4);
}

fn validateGaspTable(data: []const u8, gasp: TableRecord) FontError!void {
    return try gasp_mod.validate(data, gasp.offset, gasp.length);
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
    _ = try readOs2StyleAttributes(data, os2);
}

fn readOs2Info(data: []const u8, os2: TableRecord) FontError!Os2Info {
    try sfnt.requireLength(os2, 2);
    const version = try bin.readU16At(data, os2.offset);
    try sfnt.requireLength(os2, try minimumOs2TableLength(version));

    var info = Os2Info{
        .version = version,
        .x_avg_char_width = try bin.readI16At(data, os2.offset + 2),
        .weight_class = try bin.readU16At(data, os2.offset + 4),
        .width_class = try bin.readU16At(data, os2.offset + 6),
        .fs_type = try bin.readU16At(data, os2.offset + 8),
        .subscript_x_size = try bin.readI16At(data, os2.offset + 10),
        .subscript_y_size = try bin.readI16At(data, os2.offset + 12),
        .subscript_x_offset = try bin.readI16At(data, os2.offset + 14),
        .subscript_y_offset = try bin.readI16At(data, os2.offset + 16),
        .superscript_x_size = try bin.readI16At(data, os2.offset + 18),
        .superscript_y_size = try bin.readI16At(data, os2.offset + 20),
        .superscript_x_offset = try bin.readI16At(data, os2.offset + 22),
        .superscript_y_offset = try bin.readI16At(data, os2.offset + 24),
        .strikeout_size = try bin.readI16At(data, os2.offset + 26),
        .strikeout_position = try bin.readI16At(data, os2.offset + 28),
        .family_class = try bin.readI16At(data, os2.offset + 30),
        .panose = try readArray10At(data, os2.offset + 32),
        .unicode_ranges = .{
            try bin.readU32At(data, os2.offset + 42),
            try bin.readU32At(data, os2.offset + 46),
            try bin.readU32At(data, os2.offset + 50),
            try bin.readU32At(data, os2.offset + 54),
        },
        .vendor_id = try bin.readTagAt(data, os2.offset + 58),
        .selection = try bin.readU16At(data, os2.offset + 62),
        .first_char_index = try bin.readU16At(data, os2.offset + 64),
        .last_char_index = try bin.readU16At(data, os2.offset + 66),
        .typo_ascender = try bin.readI16At(data, os2.offset + 68),
        .typo_descender = try bin.readI16At(data, os2.offset + 70),
        .typo_line_gap = try bin.readI16At(data, os2.offset + 72),
        .win_ascent = try bin.readU16At(data, os2.offset + 74),
        .win_descent = try bin.readU16At(data, os2.offset + 76),
    };
    if (version >= 1) {
        info.code_page_ranges = .{
            try bin.readU32At(data, os2.offset + 78),
            try bin.readU32At(data, os2.offset + 82),
        };
    }
    if (version >= 2) {
        info.x_height = try bin.readI16At(data, os2.offset + 86);
        info.cap_height = try bin.readI16At(data, os2.offset + 88);
        info.default_char = try bin.readU16At(data, os2.offset + 90);
        info.break_char = try bin.readU16At(data, os2.offset + 92);
        info.max_context = try bin.readU16At(data, os2.offset + 94);
    }
    if (version >= 5) {
        info.lower_optical_point_size = try bin.readU16At(data, os2.offset + 96);
        info.upper_optical_point_size = try bin.readU16At(data, os2.offset + 98);
    }
    return info;
}

fn readArray10At(data: []const u8, offset: usize) FontError![10]u8 {
    if (offset > data.len or data.len - offset < 10) return error.BadSfnt;
    var value: [10]u8 = undefined;
    @memcpy(&value, data[offset .. offset + 10]);
    return value;
}

fn readOs2StyleAttributes(data: []const u8, os2: TableRecord) FontError!StyleAttributes {
    try sfnt.requireLength(os2, 2);
    const version = try bin.readU16At(data, os2.offset);
    try sfnt.requireLength(os2, try minimumOs2TableLength(version));

    const weight = try bin.readU16At(data, os2.offset + 4);
    const width = try bin.readU16At(data, os2.offset + 6);
    const fs_selection = try bin.readU16At(data, os2.offset + 62);

    // These fields are used by font databases and style matching, so validate
    // their OS/2-defined ranges both at parse time and at lazy public API read
    // time. Font objects borrow caller-owned bytes, so this shared helper keeps
    // post-parse byte changes from surfacing impossible style metadata.
    if (weight < 1 or weight > 1000) return error.BadSfnt;
    if (width < 1 or width > 9) return error.BadSfnt;

    return .{
        .weight = weight,
        .width = width,
        .italic = (fs_selection & 0x0001) != 0,
        .bold = (fs_selection & 0x0020) != 0,
    };
}

fn readFontDecorationMetrics(
    data: []const u8,
    post: ?TableRecord,
    os2: ?TableRecord,
    units_per_em: u16,
    ascender: i16,
    descender: i16,
) FontError!FontDecorationMetrics {
    var metrics = fallbackDecorationMetrics(units_per_em, ascender, descender);
    if (post) |post_table| {
        const post_metrics = try readPostDecorationMetrics(data, post_table);
        if (post_metrics.thickness > 0) {
            metrics.underline_position = post_metrics.position;
            metrics.underline_thickness = post_metrics.thickness;
            metrics.underline_source = .font;
        }
    }
    if (os2) |os2_table| {
        const strike_metrics = try readOs2StrikeoutMetrics(data, os2_table);
        if (strike_metrics.thickness > 0) {
            metrics.strikeout_position = strike_metrics.position;
            metrics.strikeout_thickness = strike_metrics.thickness;
            metrics.strikeout_source = .font;
        }
    }
    return metrics;
}

fn readPostDecorationMetrics(data: []const u8, post: TableRecord) FontError!struct { position: i16, thickness: i16 } {
    try sfnt.requireLength(post, 12);
    return .{
        .position = try bin.readI16At(data, post.offset + 8),
        .thickness = try bin.readI16At(data, post.offset + 10),
    };
}

fn readOs2StrikeoutMetrics(data: []const u8, os2: TableRecord) FontError!struct { position: i16, thickness: i16 } {
    try sfnt.requireLength(os2, 30);
    return .{
        .thickness = try bin.readI16At(data, os2.offset + 26),
        .position = try bin.readI16At(data, os2.offset + 28),
    };
}

fn readOs2ScriptMetrics(data: []const u8, os2: TableRecord) FontError!FontScriptMetrics {
    try sfnt.requireLength(os2, 26);
    const metrics = FontScriptMetrics{
        .subscript_x_size = try bin.readI16At(data, os2.offset + 10),
        .subscript_y_size = try bin.readI16At(data, os2.offset + 12),
        .subscript_x_offset = try bin.readI16At(data, os2.offset + 14),
        .subscript_y_offset = try bin.readI16At(data, os2.offset + 16),
        .superscript_x_size = try bin.readI16At(data, os2.offset + 18),
        .superscript_y_size = try bin.readI16At(data, os2.offset + 20),
        .superscript_x_offset = try bin.readI16At(data, os2.offset + 22),
        .superscript_y_offset = try bin.readI16At(data, os2.offset + 24),
    };
    if (metrics.subscript_x_size <= 0 or metrics.subscript_y_size <= 0 or
        metrics.superscript_x_size <= 0 or metrics.superscript_y_size <= 0)
    {
        return error.InvalidMetrics;
    }
    return metrics;
}

fn fallbackDecorationMetrics(units_per_em: u16, ascender: i16, descender: i16) FontDecorationMetrics {
    const units = @max(@as(i32, @intCast(units_per_em)), 1);
    const thickness = @max(1, @divTrunc(units, 16));
    const underline_position = -@as(i32, @max(thickness, @divTrunc(units, 9)));
    const asc = if (ascender > 0) @as(i32, ascender) else @divTrunc(units * 4, 5);
    const desc = if (descender < 0) -@as(i32, descender) else @divTrunc(units, 5);
    const strikeout_position = @max(thickness, @divTrunc(asc * 3, 10));
    return .{
        .underline_position = clampI16(underline_position),
        .underline_thickness = clampI16(thickness),
        .strikeout_position = clampI16(@min(strikeout_position, asc + desc)),
        .strikeout_thickness = clampI16(thickness),
    };
}

fn clampI16(value: i32) i16 {
    if (value < std.math.minInt(i16)) return std.math.minInt(i16);
    if (value > std.math.maxInt(i16)) return std.math.maxInt(i16);
    return @intCast(value);
}

fn validateBaseTable(data: []const u8, base: TableRecord) FontError!void {
    return try base_mod.validate(data, base.offset, base.length);
}

fn validateAnkrTable(data: []const u8, ankr: TableRecord, glyph_count: u16) FontError!void {
    return try ankr_mod.validate(data, ankr.offset, ankr.length, glyph_count);
}

fn validateTrakTable(data: []const u8, trak: TableRecord) FontError!void {
    return try trak_mod.validate(data, trak.offset, trak.length);
}

fn validateFeatTable(data: []const u8, feat: TableRecord) FontError!void {
    return try feat_mod.validate(data, feat.offset, feat.length);
}

fn validateLtagTable(data: []const u8, ltag: TableRecord) FontError!void {
    return try ltag_mod.validate(data, ltag.offset, ltag.length);
}

fn validateLtshTable(data: []const u8, ltsh: TableRecord, glyph_count: u16) FontError!void {
    try sfnt.requireLength(ltsh, 4);
    if (try bin.readU16At(data, ltsh.offset) != 0) return error.BadSfnt;
    const count = try bin.readU16At(data, ltsh.offset + 2);
    if (count != glyph_count) return error.BadSfnt;
    if (ltsh.length != 4 + @as(usize, count)) return error.BadSfnt;
}

fn readLtshInfo(allocator: std.mem.Allocator, data: []const u8, ltsh: TableRecord, glyph_count: u16) FontError!LtshInfo {
    const thresholds = try allocator.alloc(u8, glyph_count);
    errdefer allocator.free(thresholds);
    @memcpy(thresholds, data[ltsh.offset + 4 .. ltsh.offset + 4 + glyph_count]);
    return .{ .version = try bin.readU16At(data, ltsh.offset), .thresholds = thresholds };
}

fn validateHdmxTable(data: []const u8, hdmx: TableRecord, glyph_count: u16) FontError!void {
    try sfnt.requireLength(hdmx, 8);
    if (try bin.readU16At(data, hdmx.offset) != 0) return error.BadSfnt;
    const record_count = try bin.readU16At(data, hdmx.offset + 2);
    const record_size = try bin.readU32At(data, hdmx.offset + 4);
    const minimum_record_size = @as(u32, glyph_count) + 2;
    if (record_size < minimum_record_size or (record_size & 3) != 0) return error.BadSfnt;
    if (@as(u64, record_count) * record_size != @as(u64, hdmx.length - 8)) return error.BadSfnt;

    var previous_ppem: ?u8 = null;
    for (0..record_count) |record_index| {
        const record = hdmx.offset + 8 + @as(usize, record_index) * @as(usize, record_size);
        const ppem = data[record];
        if (previous_ppem) |previous| {
            if (ppem <= previous) return error.BadSfnt;
        }
        previous_ppem = ppem;
    }
}

fn readHdmxInfo(allocator: std.mem.Allocator, data: []const u8, hdmx: TableRecord, glyph_count: u16) FontError!HdmxInfo {
    const version = try bin.readU16At(data, hdmx.offset);
    const record_count = try bin.readU16At(data, hdmx.offset + 2);
    const record_size = try bin.readU32At(data, hdmx.offset + 4);
    const records = try allocator.alloc(HdmxRecord, record_count);
    errdefer {
        for (records) |record| allocator.free(record.widths);
        allocator.free(records);
    }
    var initialized: usize = 0;
    errdefer {
        for (records[0..initialized]) |record| allocator.free(record.widths);
    }
    for (records, 0..) |*out, record_index| {
        const record = hdmx.offset + 8 + record_index * @as(usize, record_size);
        const widths = try allocator.alloc(u8, glyph_count);
        @memcpy(widths, data[record + 2 .. record + 2 + glyph_count]);
        out.* = .{ .ppem = data[record], .max_width = data[record + 1], .widths = widths };
        initialized += 1;
    }
    return .{ .version = version, .record_size = record_size, .records = records };
}

fn readHdmxWidth(data: []const u8, hdmx: TableRecord, glyph_count: u16, ppem: u8, glyph_id: glyph_mod.GlyphId) FontError!?u8 {
    const record_count = try bin.readU16At(data, hdmx.offset + 2);
    const record_size = try bin.readU32At(data, hdmx.offset + 4);
    for (0..record_count) |record_index| {
        const record = hdmx.offset + 8 + @as(usize, record_index) * @as(usize, record_size);
        const record_ppem = data[record];
        if (ppem < record_ppem) return null;
        if (ppem == record_ppem) return data[record + 2 + glyph_id];
    }
    _ = glyph_count;
    return null;
}

fn readMetricHeaderInfo(data: []const u8, header: TableRecord) FontError!MetricHeaderInfo {
    try sfnt.requireLength(header, 36);
    return .{
        .version = try bin.readU32At(data, header.offset),
        .ascender = try bin.readI16At(data, header.offset + 4),
        .descender = try bin.readI16At(data, header.offset + 6),
        .line_gap = try bin.readI16At(data, header.offset + 8),
        .advance_max = try bin.readU16At(data, header.offset + 10),
        .min_side_bearing = try bin.readI16At(data, header.offset + 12),
        .min_opposite_side_bearing = try bin.readI16At(data, header.offset + 14),
        .max_extent = try bin.readI16At(data, header.offset + 16),
        .caret_slope_rise = try bin.readI16At(data, header.offset + 18),
        .caret_slope_run = try bin.readI16At(data, header.offset + 20),
        .caret_offset = try bin.readI16At(data, header.offset + 22),
        .metric_data_format = try bin.readI16At(data, header.offset + 32),
        .long_metric_count = try bin.readU16At(data, header.offset + 34),
    };
}

fn readHorizontalMetricAt(data: []const u8, hmtx: TableRecord, metric_count: u16, glyph_id: glyph_mod.GlyphId) FontError!HorizontalMetricInfo {
    if (glyph_id < metric_count) {
        const offset = hmtx.offset + @as(usize, glyph_id) * 4;
        return .{
            .advance_width = try bin.readU16At(data, offset),
            .left_side_bearing = try bin.readI16At(data, offset + 2),
        };
    }
    const last_offset = hmtx.offset + (@as(usize, metric_count) - 1) * 4;
    const lsb_offset = hmtx.offset + @as(usize, metric_count) * 4 + (@as(usize, glyph_id) - metric_count) * 2;
    return .{
        .advance_width = try bin.readU16At(data, last_offset),
        .left_side_bearing = try bin.readI16At(data, lsb_offset),
    };
}

fn readVerticalMetricAt(data: []const u8, vmtx: TableRecord, metric_count: u16, glyph_id: glyph_mod.GlyphId) FontError!VerticalMetricInfo {
    if (glyph_id < metric_count) {
        const offset = vmtx.offset + @as(usize, glyph_id) * 4;
        return .{
            .advance_height = try bin.readU16At(data, offset),
            .top_side_bearing = try bin.readI16At(data, offset + 2),
        };
    }
    const last_offset = vmtx.offset + (@as(usize, metric_count) - 1) * 4;
    const tsb_offset = vmtx.offset + @as(usize, metric_count) * 4 + (@as(usize, glyph_id) - metric_count) * 2;
    return .{
        .advance_height = try bin.readU16At(data, last_offset),
        .top_side_bearing = try bin.readI16At(data, tsb_offset),
    };
}

fn validateHorizontalMetricsTables(data: []const u8, hhea: TableRecord, hmtx: TableRecord, glyph_count: u16) FontError!u16 {
    try validateMetricHeader(data, hhea, 0x00010000);
    const metric_count = try bin.readU16At(data, hhea.offset + 34);
    const required_hmtx_length = try metricTableRequiredLength(glyph_count, metric_count);
    if (hmtx.length < required_hmtx_length) return error.InvalidMetrics;
    return metric_count;
}

fn validateVerticalMetricsTables(data: []const u8, glyph_count: u16, maybe_vhea: ?TableRecord, maybe_vmtx: ?TableRecord) FontError!?u16 {
    if (maybe_vhea == null and maybe_vmtx == null) return null;
    const vhea = maybe_vhea orelse return error.InvalidMetrics;
    const vmtx = maybe_vmtx orelse return error.InvalidMetrics;

    // vhea/vmtx mirror the hhea/hmtx compression contract for vertical layout:
    // the header declares how many full advance/bearing records exist, and the
    // remaining glyphs borrow the final advance while supplying only a top side
    // bearing. Use one helper for parse-time acceptance and lazy public reads
    // so malformed production fonts cannot hide latent vmtx bounds issues.
    try validateVerticalMetricHeader(data, vhea);
    const metric_count = try bin.readU16At(data, vhea.offset + 34);
    const required_vmtx_length = try metricTableRequiredLength(glyph_count, metric_count);
    if (vmtx.length < required_vmtx_length) return error.InvalidMetrics;
    return metric_count;
}

fn validateVerticalMetricHeader(data: []const u8, vhea: TableRecord) FontError!void {
    // vhea mirrors hhea's fixed-size header contract, with only the version
    // value differing across accepted OpenType revisions.
    if (vhea.length != 36) return error.BadSfnt;
    const version = try bin.readU32At(data, vhea.offset);
    if (version != 0x00010000 and version != 0x00011000) return error.InvalidMetrics;
    try validateMetricHeaderLineMetrics(data, vhea);
    try validateMetricHeaderReservedFields(data, vhea);
}

fn validateMetricHeader(data: []const u8, header: TableRecord, expected_version: u32) FontError!void {
    // hhea and vhea are fixed-size 36-byte metric headers. They do not define
    // extension payloads, so accept neither truncation nor tail bytes before
    // trusting the metric count at byte 34.
    if (header.length != 36) return error.BadSfnt;
    const version = try bin.readU32At(data, header.offset);
    if (version != expected_version) return error.InvalidMetrics;
    try validateMetricHeaderLineMetrics(data, header);
    try validateMetricHeaderReservedFields(data, header);
}

fn validateMetricHeaderLineMetrics(data: []const u8, header: TableRecord) FontError!void {
    const ascender = try bin.readI16At(data, header.offset + 4);
    const descender = try bin.readI16At(data, header.offset + 6);
    const line_gap = try bin.readI16At(data, header.offset + 8);
    // hhea/vhea line metrics form the public line advance used by layout:
    // ascender - descender + lineGap. A negative value is nonsensical and an
    // exactly zero value leaves text engines without a usable default advance.
    // Validate the widened sum before exposing or caching table metrics so
    // malformed headers cannot produce collapsed line boxes.
    if (@as(i32, ascender) - @as(i32, descender) + @as(i32, line_gap) <= 0) return error.InvalidMetrics;
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

fn validatePcltTable(data: []const u8, pclt: TableRecord) FontError!void {
    try sfnt.requireLength(pclt, 54);
    if (pclt.length != 54) return error.BadSfnt;
    const version = try bin.readU32At(data, pclt.offset);
    if (version != 0x00010000) return error.BadSfnt;
}

fn readPcltInfo(data: []const u8, pclt: TableRecord) FontError!PcltInfo {
    try sfnt.requireLength(pclt, 54);
    return .{
        .version = try bin.readU32At(data, pclt.offset),
        .font_number = try bin.readU32At(data, pclt.offset + 4),
        .pitch = try bin.readU16At(data, pclt.offset + 8),
        .x_height = try bin.readU16At(data, pclt.offset + 10),
        .style = try bin.readU16At(data, pclt.offset + 12),
        .type_family = try bin.readU16At(data, pclt.offset + 14),
        .cap_height = try bin.readU16At(data, pclt.offset + 16),
        .symbol_set = try bin.readU16At(data, pclt.offset + 18),
        .typeface = try readArray16At(data, pclt.offset + 20),
        .character_complement = try readArray8At(data, pclt.offset + 36),
        .file_name = try readArray6At(data, pclt.offset + 44),
        .stroke_weight = @bitCast(data[pclt.offset + 50]),
        .width_type = @bitCast(data[pclt.offset + 51]),
        .serif_style = data[pclt.offset + 52],
    };
}

fn readArray16At(data: []const u8, offset: usize) FontError![16]u8 {
    if (offset > data.len or data.len - offset < 16) return error.BadSfnt;
    var value: [16]u8 = undefined;
    @memcpy(&value, data[offset .. offset + 16]);
    return value;
}

fn readArray8At(data: []const u8, offset: usize) FontError![8]u8 {
    if (offset > data.len or data.len - offset < 8) return error.BadSfnt;
    var value: [8]u8 = undefined;
    @memcpy(&value, data[offset .. offset + 8]);
    return value;
}

fn readArray6At(data: []const u8, offset: usize) FontError![6]u8 {
    if (offset > data.len or data.len - offset < 6) return error.BadSfnt;
    var value: [6]u8 = undefined;
    @memcpy(&value, data[offset .. offset + 6]);
    return value;
}

fn readPostInfo(data: []const u8, post: TableRecord) FontError!PostInfo {
    try sfnt.requireLength(post, 32);
    const format = try bin.readU32At(data, post.offset);
    const glyph_name_count: ?u16 = switch (format) {
        0x00020000, 0x00025000 => try bin.readU16At(data, post.offset + 32),
        0x00040000 => @intCast((post.length - 32) / 2),
        else => null,
    };
    return .{
        .format = format,
        .italic_angle = fixed16_16ToF32(try bin.readI32At(data, post.offset + 4)),
        .underline_position = try bin.readI16At(data, post.offset + 8),
        .underline_thickness = try bin.readI16At(data, post.offset + 10),
        .is_fixed_pitch = (try bin.readU32At(data, post.offset + 12)) != 0,
        .min_mem_type42 = try bin.readU32At(data, post.offset + 16),
        .max_mem_type42 = try bin.readU32At(data, post.offset + 20),
        .min_mem_type1 = try bin.readU32At(data, post.offset + 24),
        .max_mem_type1 = try bin.readU32At(data, post.offset + 28),
        .glyph_name_count = glyph_name_count,
    };
}

const PostValidationOptions = struct {
    compat_ttc_face: bool = false,
    custom_name_validation: enum {
        strict,
        allow_empty,
        structural_only,
    } = .strict,
};

fn validatePostTable(data: []const u8, post: TableRecord, glyph_count: u16, options: PostValidationOptions) FontError!void {
    try sfnt.requireLength(post, 32);
    const version = try bin.readU32At(data, post.offset);
    switch (version) {
        0x00010000 => {
            // Format 1.0 implies the complete standard Macintosh glyph-name
            // set. If maxp advertises a different glyph count, consumers that
            // synthesize glyph names from `post` and consumers that use maxp
            // for metrics/outlines disagree on the addressable glyph set.
            if (glyph_count != 258) return error.BadSfnt;
        },
        0x00020000 => try validatePostFormat2(data, post, glyph_count, options),
        0x00025000 => try validatePostFormat25(data, post, glyph_count),
        0x00030000 => {},
        0x00040000 => try validatePostFormat4(post, glyph_count),
        else => return error.BadSfnt,
    }
}

fn validatePostFormat2(data: []const u8, post: TableRecord, glyph_count: u16, options: PostValidationOptions) FontError!void {
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
        if (name_len > 63) return error.BadSfnt;
        if (@as(usize, name_len) > post.length - cursor) return error.BadSfnt;
        if (!options.compat_ttc_face) switch (options.custom_name_validation) {
            .strict => {
                if (name_len == 0 or !isPostGlyphName(table[cursor .. cursor + name_len])) return error.BadSfnt;
            },
            .allow_empty => {
                if (name_len != 0 and !isPostGlyphName(table[cursor .. cursor + name_len])) return error.BadSfnt;
            },
            .structural_only => {},
        };
        cursor += name_len;
    }
    if (!options.compat_ttc_face and cursor != post.length) return error.BadSfnt;
}

fn validatePostFormat25(data: []const u8, post: TableRecord, glyph_count: u16) FontError!void {
    const table = data[post.offset .. post.offset + post.length];
    if (post.length - 32 < 2) return error.BadSfnt;
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (number_of_glyphs != glyph_count) return error.BadSfnt;
    const offsets_offset: usize = 34;
    // Format 2.5 is only the fixed post header, numberOfGlyphs, and one signed
    // delta byte per glyph. It has no trailing name pool. Require exact
    // consumption so unreachable bytes cannot be preserved by one consumer and
    // ignored by another.
    const required_len = offsets_offset + @as(usize, number_of_glyphs);
    if (post.length != required_len) return error.BadSfnt;

    for (0..number_of_glyphs) |glyph_index| {
        const signed_delta: i8 = @bitCast(table[offsets_offset + glyph_index]);
        const standard_index = @as(i32, @intCast(glyph_index)) + @as(i32, signed_delta);
        if (standard_index < 0 or standard_index >= 258) return error.BadSfnt;
    }
}

fn validatePostFormat4(post: TableRecord, glyph_count: u16) FontError!void {
    // Format 4.0 stores exactly one uint16 character-code slot per glyph after
    // the fixed post header. It has no string pool or extension payload, so
    // reject tail bytes that no conforming consumer can address.
    const required_len = 32 + @as(usize, glyph_count) * 2;
    if (post.length != required_len) return error.BadSfnt;
}

fn readPostGlyphName(data: []const u8, post: TableRecord, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
    const table = data[post.offset .. post.offset + post.length];
    const version = try bin.readU32At(table, 0);
    return switch (version) {
        0x00010000 => try postStandardGlyphName(glyph_id),
        0x00020000 => try readPostFormat2GlyphName(table, glyph_id),
        0x00025000 => try readPostFormat25GlyphName(table, glyph_id),
        // Format 3.0 deliberately omits glyph names. Format 4.0 maps glyphs
        // to character codes for old composite-font workflows rather than to
        // PostScript names, so this API reports no glyph name for it.
        0x00030000, 0x00040000 => null,
        else => error.BadSfnt,
    };
}

fn readPostFormat2GlyphName(table: []const u8, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (glyph_id >= number_of_glyphs) return error.InvalidGlyph;
    const glyph_name_indices_offset: usize = 34;
    const name_index = try bin.readU16At(table, glyph_name_indices_offset + @as(usize, glyph_id) * 2);
    if (name_index < post_standard_glyph_names.len) return try postStandardGlyphName(name_index);

    // Custom names are Pascal strings stored in ordinal order immediately after
    // the glyphNameIndex array. The index value 258 names the first custom
    // string, 259 the second, and so on; validation has already guaranteed that
    // all ordinals up to the largest referenced index are structurally present.
    const name = try readPostCustomGlyphName(table, name_index - post_standard_glyph_names.len);
    return if (name.len == 0) null else name;
}

fn readPostCustomGlyphName(table: []const u8, ordinal: usize) FontError![]const u8 {
    const number_of_glyphs = try bin.readU16At(table, 32);
    var cursor: usize = 34 + @as(usize, number_of_glyphs) * 2;
    for (0..ordinal) |_| {
        if (cursor >= table.len) return error.BadSfnt;
        const name_len = table[cursor];
        cursor += 1 + @as(usize, name_len);
        if (cursor > table.len) return error.BadSfnt;
    }
    if (cursor >= table.len) return error.BadSfnt;
    const name_len = table[cursor];
    cursor += 1;
    if (@as(usize, name_len) > table.len - cursor) return error.BadSfnt;
    return table[cursor .. cursor + name_len];
}

fn readPostFormat25GlyphName(table: []const u8, glyph_id: glyph_mod.GlyphId) FontError!?[]const u8 {
    const number_of_glyphs = try bin.readU16At(table, 32);
    if (glyph_id >= number_of_glyphs) return error.InvalidGlyph;
    const signed_delta: i8 = @bitCast(table[34 + @as(usize, glyph_id)]);
    const standard_index = @as(i32, @intCast(glyph_id)) + @as(i32, signed_delta);
    if (standard_index < 0 or standard_index >= post_standard_glyph_names.len) return error.BadSfnt;
    return try postStandardGlyphName(@intCast(standard_index));
}

fn postStandardGlyphName(index: usize) FontError![]const u8 {
    if (index >= post_standard_glyph_names.len) return error.BadSfnt;
    return post_standard_glyph_names[index];
}

const post_standard_glyph_names = [_][]const u8{
    ".notdef",
    ".null",
    "nonmarkingreturn",
    "space",
    "exclam",
    "quotedbl",
    "numbersign",
    "dollar",
    "percent",
    "ampersand",
    "quotesingle",
    "parenleft",
    "parenright",
    "asterisk",
    "plus",
    "comma",
    "hyphen",
    "period",
    "slash",
    "zero",
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "colon",
    "semicolon",
    "less",
    "equal",
    "greater",
    "question",
    "at",
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "I",
    "J",
    "K",
    "L",
    "M",
    "N",
    "O",
    "P",
    "Q",
    "R",
    "S",
    "T",
    "U",
    "V",
    "W",
    "X",
    "Y",
    "Z",
    "bracketleft",
    "backslash",
    "bracketright",
    "asciicircum",
    "underscore",
    "grave",
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "braceleft",
    "bar",
    "braceright",
    "asciitilde",
    "Adieresis",
    "Aring",
    "Ccedilla",
    "Eacute",
    "Ntilde",
    "Odieresis",
    "Udieresis",
    "aacute",
    "agrave",
    "acircumflex",
    "adieresis",
    "atilde",
    "aring",
    "ccedilla",
    "eacute",
    "egrave",
    "ecircumflex",
    "edieresis",
    "iacute",
    "igrave",
    "icircumflex",
    "idieresis",
    "ntilde",
    "oacute",
    "ograve",
    "ocircumflex",
    "odieresis",
    "otilde",
    "uacute",
    "ugrave",
    "ucircumflex",
    "udieresis",
    "dagger",
    "degree",
    "cent",
    "sterling",
    "section",
    "bullet",
    "paragraph",
    "germandbls",
    "registered",
    "copyright",
    "trademark",
    "acute",
    "dieresis",
    "notequal",
    "AE",
    "Oslash",
    "infinity",
    "plusminus",
    "lessequal",
    "greaterequal",
    "yen",
    "mu",
    "partialdiff",
    "summation",
    "product",
    "pi",
    "integral",
    "ordfeminine",
    "ordmasculine",
    "Omega",
    "ae",
    "oslash",
    "questiondown",
    "exclamdown",
    "logicalnot",
    "radical",
    "florin",
    "approxequal",
    "Delta",
    "guillemotleft",
    "guillemotright",
    "ellipsis",
    "nonbreakingspace",
    "Agrave",
    "Atilde",
    "Otilde",
    "OE",
    "oe",
    "endash",
    "emdash",
    "quotedblleft",
    "quotedblright",
    "quoteleft",
    "quoteright",
    "divide",
    "lozenge",
    "ydieresis",
    "Ydieresis",
    "fraction",
    "currency",
    "guilsinglleft",
    "guilsinglright",
    "fi",
    "fl",
    "daggerdbl",
    "periodcentered",
    "quotesinglbase",
    "quotedblbase",
    "perthousand",
    "Acircumflex",
    "Ecircumflex",
    "Aacute",
    "Edieresis",
    "Egrave",
    "Iacute",
    "Icircumflex",
    "Idieresis",
    "Igrave",
    "Oacute",
    "Ocircumflex",
    "apple",
    "Ograve",
    "Uacute",
    "Ucircumflex",
    "Ugrave",
    "dotlessi",
    "circumflex",
    "tilde",
    "macron",
    "breve",
    "dotaccent",
    "ring",
    "cedilla",
    "hungarumlaut",
    "ogonek",
    "caron",
    "Lslash",
    "lslash",
    "Scaron",
    "scaron",
    "Zcaron",
    "zcaron",
    "brokenbar",
    "Eth",
    "eth",
    "Yacute",
    "yacute",
    "Thorn",
    "thorn",
    "minus",
    "multiply",
    "onesuperior",
    "twosuperior",
    "threesuperior",
    "onehalf",
    "onequarter",
    "threequarters",
    "franc",
    "Gbreve",
    "gbreve",
    "Idotaccent",
    "Scedilla",
    "scedilla",
    "Cacute",
    "cacute",
    "Ccaron",
    "ccaron",
    "dcroat",
};

fn readKernInfo(allocator: std.mem.Allocator, data: []const u8, kern: TableRecord) FontError!KernInfo {
    try sfnt.requireLength(kern, 4);
    const version = try bin.readU32At(data, kern.offset);
    if (version == 0x00010000) return try readAppleKernInfo(allocator, data, kern);
    if ((version >> 16) != 0) {
        return .{
            .dialect = .unsupported,
            .version = version,
            .subtables = try allocator.alloc(KernSubtableInfo, 0),
        };
    }
    return try readLegacyKernInfo(allocator, data, kern);
}

fn readLegacyKernInfo(allocator: std.mem.Allocator, data: []const u8, kern: TableRecord) FontError!KernInfo {
    const table_count = try bin.readU16At(data, kern.offset + 2);
    const subtables = try allocator.alloc(KernSubtableInfo, table_count);
    errdefer allocator.free(subtables);

    var subtable_offset = kern.offset + 4;
    for (subtables) |*info| {
        const length = try bin.readU16At(data, subtable_offset + 2);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        const format = coverage >> 8;
        info.* = .{
            .offset = subtable_offset,
            .length = length,
            .format = format,
            .coverage = coverage,
            .horizontal = (coverage & 0x0001) != 0,
            .minimum = (coverage & 0x0002) != 0,
            .cross_stream = (coverage & 0x0004) != 0,
            .override = (coverage & 0x0008) != 0,
            .pair_count = if (format == 0 and length >= 14) try bin.readU16At(data, subtable_offset + 6) else null,
        };
        subtable_offset += length;
    }
    return .{ .dialect = .legacy, .version = try bin.readU16At(data, kern.offset), .subtables = subtables };
}

fn readAppleKernInfo(allocator: std.mem.Allocator, data: []const u8, kern: TableRecord) FontError!KernInfo {
    const table_count: usize = @intCast(try bin.readU32At(data, kern.offset + 4));
    const subtables = try allocator.alloc(KernSubtableInfo, table_count);
    errdefer allocator.free(subtables);

    var subtable_offset = kern.offset + 8;
    for (subtables) |*info| {
        const length: usize = @intCast(try bin.readU32At(data, subtable_offset));
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        const format = coverage & 0x00ff;
        info.* = .{
            .offset = subtable_offset,
            .length = length,
            .format = format,
            .coverage = coverage,
            .horizontal = (coverage & 0x8000) == 0,
            .minimum = false,
            .cross_stream = (coverage & 0x4000) != 0,
            .variation = (coverage & 0x2000) != 0,
            .tuple_index = try bin.readU16At(data, subtable_offset + 6),
            .pair_count = if (format == 0 and length >= 16) try bin.readU16At(data, subtable_offset + 8) else null,
        };
        subtable_offset += length;
    }
    return .{ .dialect = .apple, .version = try bin.readU32At(data, kern.offset), .subtables = subtables };
}

fn validateKerxTable(data: []const u8, kerx: TableRecord, glyph_count: u16) FontError!void {
    return try kerx_mod.validate(data, kerx.offset, kerx.length, glyph_count);
}

fn validateMorxTable(data: []const u8, morx: TableRecord, glyph_count: u16) FontError!void {
    return try morx_mod.validate(data, morx.offset, morx.length, glyph_count);
}

fn validateKernTable(data: []const u8, kern: TableRecord, glyph_count: u16) FontError!void {
    try sfnt.requireLength(kern, 4);
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
        const subtable_version = try bin.readU16At(data, subtable_offset);
        const length = try bin.readU16At(data, subtable_offset + 2);
        const coverage = try bin.readU16At(data, subtable_offset + 4);
        if (length < 6 or length > table_end - subtable_offset) return error.BadSfnt;

        // Legacy OpenType kern subtables carry their own UInt16 version, which
        // must be zero. Rejecting private variants here keeps later coverage
        // bits from being interpreted with the standard format-0 body layout.
        if (subtable_version != 0) return error.BadSfnt;

        const format = coverage >> 8;
        const horizontal = (coverage & 0x0001) != 0;
        const minimum = (coverage & 0x0002) != 0;
        const cross_stream = (coverage & 0x0004) != 0;
        if (format == 0 and horizontal and !minimum and !cross_stream) {
            try validateKernFormat0Body(data[subtable_offset + 6 .. subtable_offset + length], glyph_count);
        }
        subtable_offset += length;
    }
    // The SFNT directory length is the unpadded kern payload length. Require
    // nTables and each subtable length to consume it exactly so orphan bytes
    // cannot hide an unvalidated subtable that another kern consumer might
    // still interpret.
    if (subtable_offset != table_end) return error.BadSfnt;
}

fn validateAppleKernTable(data: []const u8, kern: TableRecord, glyph_count: u16) FontError!void {
    try sfnt.requireLength(kern, 8);
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
        if (!vertical and !cross_stream and !variation) {
            const body = data[subtable_offset + 8 .. subtable_offset + length];
            if (format == 0) {
                try validateKernFormat0Body(body, glyph_count);
            } else if (format == 2) {
                try validateKernFormat2Body(body, glyph_count);
            }
        }
        subtable_offset += length;
    }
    // Apple/AAT kern v1 uses 32-bit lengths, but the same ownership rule
    // applies: the counted subtable sequence must occupy the complete declared
    // table payload rather than leaving trailing bytes with ambiguous meaning.
    if (subtable_offset != table_end) return error.BadSfnt;
}

fn validateKernFormat0Body(data: []const u8, glyph_count: u16) FontError!void {
    // Format-0 kern subtables are searched with a binary search over packed
    // left/right glyph pairs. Validate the search header and complete pair
    // array while parsing so malformed fonts cannot hide out-of-range glyph IDs
    // or depend on non-canonical binary-search metadata.
    if (data.len < 8) return error.BadSfnt;
    const pair_count = try bin.readU16At(data, 0);
    try validateKernFormat0SearchParameters(data, pair_count);
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

fn validateKernFormat0SearchParameters(data: []const u8, pair_count: u16) FontError!void {
    // FontTools and deployed fonts retain the one-record searchRange (6)
    // when nPairs is zero, with a zero rangeShift. Treat that de-facto empty
    // descriptor explicitly rather than subtracting 6 from a zero-byte pair
    // array, which otherwise underflows before the header can be accepted.
    var max_power_of_two: usize = 1;
    var expected_entry_selector: u16 = 0;
    while (max_power_of_two * 2 <= pair_count) {
        max_power_of_two *= 2;
        expected_entry_selector += 1;
    }

    const expected_search_range = max_power_of_two * 6;
    const pair_record_bytes = @as(usize, pair_count) * 6;
    if (expected_search_range > std.math.maxInt(u16) or pair_record_bytes > std.math.maxInt(u16)) return error.BadSfnt;
    const expected_range_shift = if (pair_count == 0) 0 else pair_record_bytes - expected_search_range;

    // The legacy and Apple kern format-0 bodies share this OpenType binary
    // search descriptor. Cangjie validates it even though lookups recompute the
    // search bounds from nPairs; accepting inconsistent values would mean the
    // same font bytes describe different pair arrays to different consumers.
    if (try bin.readU16At(data, 2) != expected_search_range or
        try bin.readU16At(data, 4) != expected_entry_selector or
        try bin.readU16At(data, 6) != expected_range_shift)
    {
        return error.BadSfnt;
    }
}

test "kern format 0 accepts the canonical empty pair array" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    // FontTools emits the one-record searchRange for an empty pair array, but
    // keeps rangeShift zero because no pair-record bytes exist.
    var kern: [18]u8 = .{0} ** 18;
    writeU16Test(&kern, 2, 1);
    writeU16Test(&kern, 4 + 2, 14);
    writeU16Test(&kern, 4 + 4, 0x0001);
    writeU16Test(&kern, 4 + 6 + 2, 6);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(?i16, 0), try font.kerning(1, 1));
}

fn isPostGlyphName(name: []const u8) bool {
    for (name) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == ' ' or byte == '.' or byte == '_' or byte == '-') continue;
        return false;
    }
    return true;
}

test "post glyph names accept printable fixture spaces but reject controls" {
    try std.testing.expect(isPostGlyphName("Dot Below"));
    try std.testing.expect(isPostGlyphName("Virama-Killer"));
    try std.testing.expect(!isPostGlyphName("Dot\tBelow"));
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
    max_points: u16,
    max_contours: u16,
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
            const simple_contours: u16 = @intCast(contour_count);
            const simple_points = try validateSimpleGlyphDescription(glyph_data, simple_contours);
            try validateMaxpSimpleGlyphSummary(simple_points, simple_contours, max_points, max_contours);
            point_counts[glyph_index] = simple_points;
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
        try validateSimpleGlyphFlag(flag, expanded_flags);
        offset += 1;
        expanded_flags += 1;
        x_bytes += simpleGlyphCoordinateByteCount(flag, true);
        y_bytes += simpleGlyphCoordinateByteCount(flag, false);
        if ((flag & 0x08) != 0) {
            if (offset >= glyph_data.len) return error.InvalidGlyph;
            const repeat = glyph_data[offset];
            offset += 1;
            if (@as(usize, repeat) > total_points - expanded_flags) return error.InvalidGlyph;
            if (repeat != 0) try validateSimpleGlyphFlag(flag, expanded_flags);
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

fn validateMaxpSimpleGlyphSummary(point_count: usize, contour_count: u16, max_points: u16, max_contours: u16) FontError!void {
    // maxp.maxPoints and maxp.maxContours are font-wide summaries for simple
    // glyphs. They bound stack/storage needs for clients that size glyph work
    // buffers before reading an outline, so reject tables that under-report a
    // structurally valid glyph instead of letting the inconsistency surface only
    // in a later rasterization path.
    if (point_count > max_points or contour_count > max_contours) return error.InvalidGlyph;
}

fn simpleGlyphCoordinateByteCount(flag: u8, x_axis: bool) usize {
    const short_vector_bit: u8 = if (x_axis) 0x02 else 0x04;
    const same_or_positive_bit: u8 = if (x_axis) 0x10 else 0x20;
    if ((flag & short_vector_bit) != 0) return 1;
    if ((flag & same_or_positive_bit) != 0) return 0;
    return 2;
}

fn validateSimpleGlyphFlag(flag: u8, point_index: usize) FontError!void {
    // Simple-glyph flag byte bit 7 is reserved by the glyf grammar, while bit 6
    // (OVERLAP_SIMPLE) is a whole-glyph hint carried only by the first logical
    // flag. Validate the expanded RLE stream rather than the raw bytes so a
    // repeated first flag cannot smuggle the hint onto later points.
    if ((flag & 0x80) != 0) return error.InvalidGlyph;
    if (point_index != 0 and (flag & 0x40) != 0) return error.InvalidGlyph;
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
        0x0010 | 0x0020 | 0x0040 | 0x0080 | 0x0100 |
        0x0200 | 0x0400 | 0x0800 | 0x1000 |
        0x2000 | 0x4000 | 0x8000;
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
    // actual simple/compound point counts before outline expansion uses them.
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

fn tableRelativeOffset(table: TableRecord, absolute_offset: usize) FontError!usize {
    if (absolute_offset < table.offset) return error.BadSfnt;
    const relative_offset = absolute_offset - table.offset;
    if (relative_offset > table.length) return error.BadSfnt;
    return relative_offset;
}

fn validateCachedCmapEncodingRecord(data: []const u8, cmap: TableRecord, subtable: CmapSubtable, relative_offset: usize) FontError!void {
    if (cmap.length < 4) return error.BadSfnt;
    if (try bin.readU16At(data, cmap.offset) != 0) return error.BadSfnt;
    const count = try bin.readU16At(data, cmap.offset + 2);
    if (@as(usize, count) * 8 > cmap.length - 4) return error.BadSfnt;

    var previous_encoding: ?struct { platform_id: u16, encoding_id: u16 } = null;
    for (0..count) |index| {
        const record = cmap.offset + 4 + index * 8;
        const platform_id = try bin.readU16At(data, record);
        const encoding_id = try bin.readU16At(data, record + 2);
        if (previous_encoding) |previous| {
            if (platform_id < previous.platform_id or (platform_id == previous.platform_id and encoding_id <= previous.encoding_id)) {
                return error.BadSfnt;
            }
        }
        previous_encoding = .{ .platform_id = platform_id, .encoding_id = encoding_id };
        if (platform_id != subtable.platform_id or encoding_id != subtable.encoding_id) continue;

        // Font caches cmap EncodingRecords after parse, but the underlying SFNT
        // bytes are borrowed from the caller. Re-check that the same directory
        // key still points at the same child subtable before following cached
        // offsets, so post-parse edits cannot silently redirect or erase the
        // character map while public lookup keeps using the old address.
        const current_offset: usize = @intCast(try bin.readU32At(data, record + 4));
        if (current_offset != relative_offset) return error.BadSfnt;
        return;
    }
    return error.BadSfnt;
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
        2 => try validateCmapFormat2(data, offset, length, validate_bmp_scalars),
        6 => try validateCmapFormat6(data, offset, length, validate_bmp_scalars),
        8 => try validateCmapFormat8(data, offset, length),
        10 => try validateCmapFormat10(data, offset, length),
        4 => try validateCmapFormat4(data, offset, length, validate_bmp_scalars),
        12, 13 => try validateSegmentedCmapGroups(data, offset, length),
        14 => try validateCmapFormat14(data, offset, length),
        else => {},
    }
    try validateCmapLanguageField(data, offset, length, format, platform_id);
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
            // Unknown Unicode encoding IDs occur in otherwise valid, subsetted
            // fonts. Treat ordinary mapping formats as Unicode scalar maps and
            // keep validating their structure, but do not let an unrecognized
            // optional EncodingRecord invalidate standard sibling records.
            // Formats 13/14 remain restricted to their registered encodings.
            else => isGeneralCharacterCmapFormat(format),
        },
        1 => isLegacyByteOrBmpCmapFormat(format),
        2 => encoding_id <= 2 and isGeneralCharacterCmapFormat(format),
        3 => switch (encoding_id) {
            0, 1 => format == 4,
            // Windows CJK code-page cmaps are not Unicode scalar maps; both the
            // mixed-byte format 2 and segmented format 4 encodings are seen in
            // legacy fonts.
            2, 3, 4, 5, 6 => format == 2 or format == 4,
            10 => format == 12 or format == 13,
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

fn validateCmapLanguageField(data: []const u8, offset: usize, length: usize, format: u16, platform_id: u16) FontError!void {
    // The legacy language field is only meaningful for Macintosh cmap
    // subtables. Unicode, Windows, ISO, and custom cmap records must keep it
    // zero; otherwise the same mapping bytes can be interpreted as a
    // platform-private language variant by one parser and as an ordinary
    // Unicode mapping by another.
    if (platform_id == 1) return;
    switch (format) {
        0, 2, 4, 6 => {
            if (length < 6) return error.BadSfnt;
            if (try bin.readU16At(data, offset + 4) != 0) return error.BadSfnt;
        },
        8, 10, 12, 13 => {
            if (length < 12) return error.BadSfnt;
            if (try bin.readU32At(data, offset + 8) != 0) return error.BadSfnt;
        },
        else => {},
    }
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

fn validatePublicUnicodeScalar(codepoint: u21) FontError!void {
    // Public cmap APIs accept Unicode scalar values, not arbitrary 21-bit
    // integers. Validate the boundary before scanning font tables so surrogate
    // code points cannot be reported as ordinary unmapped text or fed into a
    // default-UVS fallback lookup.
    if (!isUnicodeScalarValue(codepoint)) return error.InvalidCodepoint;
}

fn validatePublicVariationSelector(codepoint: u21) FontError!void {
    // Format-14 cmap records are keyed only by standardized Unicode variation
    // selectors. Treating an arbitrary scalar as "no UVS record" masks caller
    // bugs and can accidentally fall back through glyphIndexWithVariation as if
    // a malformed text stream were valid base text.
    if (!isUnicodeVariationSelector(codepoint)) return error.InvalidCodepoint;
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

fn validateCmapFormat2(data: []const u8, offset: usize, length: usize, validate_unicode_scalars: bool) FontError!void {
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
        if (validate_unicode_scalars) {
            // Format 2 stores only low-byte ranges in each SubHeader; the
            // high-byte key that selected the SubHeader supplies the rest of
            // the BMP code point. Validate every referencing high-byte domain
            // so Unicode cmaps cannot advertise surrogate character codes
            // while still looking structurally valid at the glyph-array level.
            try validateCmapFormat2UnicodeScalarRange(data, offset, subheader_index, first_code, entry_count);
        }
        if ((id_range_offset & 1) != 0) return error.BadSfnt;
        const first_glyph = subheader_offset + 6 + @as(usize, id_range_offset);
        const last_glyph = first_glyph + last_entry_index * 2;
        // idRangeOffset is relative to its own word. The glyph index array is
        // conceptually after the declared SubHeader array, so disallow offsets
        // that point back into SubHeader metadata or beyond the declared cmap.
        if (first_glyph < glyph_array_start or last_glyph > table_end or table_end - last_glyph < 2) return error.BadSfnt;
    }
}

fn validateCmapFormat2UnicodeScalarRange(data: []const u8, offset: usize, subheader_index: usize, first_code: u16, entry_count: u16) FontError!void {
    for (0..256) |high_byte| {
        const key = try bin.readU16At(data, offset + 6 + high_byte * 2);
        if (key / 8 != subheader_index) continue;
        if (subheader_index == 0) {
            // SubHeader[0] is also the single-byte map. High-byte zero covers
            // U+00xx; other high bytes with a zero key mean "unmapped" rather
            // than a two-byte range, matching glyphIndexFormat2.
            if (high_byte != 0) continue;
        }

        const start = (@as(u32, @intCast(high_byte)) << 8) | first_code;
        const end = start + @as(u32, entry_count) - 1;
        if (!isUnicodeScalarValue(start) or !isUnicodeScalarValue(end)) return error.BadSfnt;
        if (start < 0xe000 and end > 0xd7ff) return error.BadSfnt;
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
    // The binary-search descriptor fields are performance hints for consumers
    // that use OpenType's suggested search algorithm. Cangjie validates and
    // scans the segment arrays directly, and real AOTS/HarfBuzz test fonts may
    // leave those descriptor fields non-canonical while the mapping data is
    // otherwise valid.
    _ = validateCmapFormat4SearchParameters(data, offset, seg_count) catch {};
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
        if (index == seg_count - 1) {
            const delta = try bin.readI16At(data, id_deltas + index * 2);
            // The terminal segment is not an ordinary mapping range: OpenType
            // requires the exact 0xffff -> glyph 0 sentinel so binary-search
            // cmap consumers have a guaranteed stop record. Accepting a wider
            // or non-missing final range would make U+FFFF visible as a real
            // glyph in this parser and can make other parsers disagree about
            // where the searchable character-domain ends.
            if (start != 0xffff or end != 0xffff or delta != 1 or range_offset != 0) return error.BadSfnt;
        }
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

fn validateCmapFormat4SearchParameters(data: []const u8, offset: usize, seg_count: usize) FontError!void {
    var max_power_of_two: usize = 1;
    var expected_entry_selector: u16 = 0;
    while (max_power_of_two * 2 <= seg_count) {
        max_power_of_two *= 2;
        expected_entry_selector += 1;
    }

    const expected_search_range = max_power_of_two * 2;
    const segment_selector_bytes = seg_count * 2;
    if (expected_search_range > std.math.maxInt(u16) or segment_selector_bytes > std.math.maxInt(u16)) return error.BadSfnt;
    const expected_range_shift = segment_selector_bytes - expected_search_range;

    // Format 4 carries a small binary-search descriptor beside segCountX2.
    // Cangjie's lookup currently scans linearly, but the fields are still part
    // of the OpenType table contract. Requiring their canonical values keeps a
    // malformed private variant from being accepted just because its segment
    // arrays happen to be readable.
    if (try bin.readU16At(data, offset + 8) != expected_search_range or
        try bin.readU16At(data, offset + 10) != expected_entry_selector or
        try bin.readU16At(data, offset + 12) != expected_range_shift)
    {
        return error.BadSfnt;
    }
}

fn validateSegmentedCmapGroups(data: []const u8, offset: usize, length: usize) FontError!void {
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;
    if (length < 16) return error.BadSfnt;
    try validateExtendedCmapReservedField(data, offset);
    const group_count: usize = @intCast(try bin.readU32At(data, offset + 12));
    // Formats 12 and 13 have no trailing language or padding fields after the
    // group array. Require the UInt32 length to match the declared group count
    // exactly so an EncodingRecord cannot hide an extra partial/complete group
    // that another parser or a mutated cached subtable might later observe.
    if (@as(u64, group_count) * 12 != @as(u64, length - 16)) return error.BadSfnt;

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

fn readClassDefDense(data: []const u8, offset: usize, glyph_count: u16, out: []u16, comptime validate_glyph_class_values: bool) FontError!void {
    if (out.len != glyph_count) return error.BadSfnt;
    @memset(out, 0);

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

            const dst_start: usize = start_glyph;
            for (out[dst_start .. dst_start + count], 0..) |*class, index| {
                const value = try bin.readU16At(data, offset + 6 + index * 2);
                if (validate_glyph_class_values) try validateGlyphClassValue(value);
                class.* = value;
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
                const class = try bin.readU16At(data, range_offset + 4);
                if (end < start) return error.BadSfnt;
                if (previous_end) |last_end| {
                    if (start <= last_end) return error.BadSfnt;
                }
                if (end >= glyph_count) return error.BadSfnt;
                if (validate_glyph_class_values) try validateGlyphClassValue(class);

                // The shaping hot path wants glyph-id indexed metadata, not
                // repeated ClassDef interpretation. Fill each canonical range
                // once here so GSUB/GPOS lookup-flag filtering becomes a
                // branch-light slice lookup.
                @memset(out[@as(usize, start) .. @as(usize, end) + 1], class);
                previous_end = end;
            }
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
    return validateGdefTableWithVariationData(data, gdef, glyph_count, null);
}

fn validateGdefTableWithVariationData(data: []const u8, gdef: TableRecord, glyph_count: u16, fvar: ?TableRecord) FontError!void {
    if (gdef.offset > data.len or gdef.length > data.len - gdef.offset) return error.BadSfnt;
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
        try validateGlyphClassDefValues(table, glyph_class_def_offset);
    }
    if (attach_list_offset != 0) {
        try validateGdefChildOffset(attach_list_offset, gdef.length, header_len);
        try validateGdefAttachList(table, attach_list_offset, glyph_count);
    }
    if (lig_caret_list_offset != 0) {
        try validateGdefChildOffset(lig_caret_list_offset, gdef.length, header_len);
        try validateGdefLigCaretList(table, lig_caret_list_offset, glyph_count);
    }
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
        if (item_var_store_offset != 0) {
            try validateGdefChildOffset(item_var_store_offset, gdef.length, header_len);
            // GDEF 1.3 ItemVariationStore uses the same VariationRegionList
            // axis contract as HVAR/MVAR/COLR variation stores: its axisCount
            // must match the fvar axis order. A store without fvar cannot be
            // interpreted safely, so reject it instead of accepting a payload
            // that only happens to fit inside the GDEF byte range.
            const fvar_info = try readFvarInfo(data, fvar orelse return error.BadSfnt);
            _ = try item_store.validate(
                data,
                variationTable(gdef),
                item_var_store_offset,
                fvar_info.axis_count,
                header_len,
            );
        }
    }
}

fn validateGdefHeaderForLazyApi(data: []const u8, gdef: TableRecord) FontError!usize {
    if (gdef.length < 12) return error.BadSfnt;
    const major = try bin.readU16At(data, gdef.offset);
    const minor = try bin.readU16At(data, gdef.offset + 2);
    if (major != 1) return error.BadSfnt;
    const header_len = minimumGdefHeaderLength(minor);
    if (gdef.length < header_len) return error.BadSfnt;
    return header_len;
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

fn validateGdefAttachList(data: []const u8, offset: usize, glyph_count_bound: u16) FontError!void {
    if (offset + 4 > data.len) return error.BadSfnt;
    const coverage_relative = try bin.readU16At(data, offset);
    const glyph_count = try bin.readU16At(data, offset + 2);
    const attach_offsets_pos = offset + 4;
    if (@as(usize, glyph_count) * 2 > data.len - attach_offsets_pos) return error.BadSfnt;

    const attach_data_start = 4 + @as(usize, glyph_count) * 2;
    const coverage_offset = try checkedGdefRelativeOffset(data, offset, coverage_relative, attach_data_start);
    try validateCoverageGlyphBounds(data, coverage_offset, glyph_count_bound);
    if (try coverageGlyphCount(data, coverage_offset) != glyph_count) return error.BadSfnt;

    for (0..glyph_count) |index| {
        const attach_relative = try bin.readU16At(data, attach_offsets_pos + index * 2);
        // AttachPoint offsets are parallel to Coverage indexes and are not
        // nullable in GDEF. Requiring them to start after the declared offset
        // array prevents malformed fonts from reinterpreting AttachList header
        // bytes as point-count data for covered glyphs.
        const attach_offset = try checkedGdefRelativeOffset(data, offset, attach_relative, attach_data_start);
        try validateGdefAttachPoint(data, attach_offset);
    }
}

fn checkedGdefRelativeOffset(data: []const u8, base: usize, relative: usize, minimum_relative: usize) FontError!usize {
    if (relative < minimum_relative) return error.BadSfnt;
    if (relative > data.len - base) return error.BadSfnt;
    return base + relative;
}

fn validateGdefAttachPoint(data: []const u8, offset: usize) FontError!void {
    if (offset + 2 > data.len) return error.BadSfnt;
    const point_count = try bin.readU16At(data, offset);
    if (@as(usize, point_count) * 2 > data.len - (offset + 2)) return error.BadSfnt;

    var previous: ?u16 = null;
    for (0..point_count) |index| {
        const point = try bin.readU16At(data, offset + 2 + index * 2);
        // OpenType requires AttachPoint point indexes to be sorted. Enforcing
        // that canonical form at parse time keeps attachment metadata stable
        // instead of making later consumers choose between duplicate or
        // order-dependent point records.
        if (previous) |last| {
            if (point <= last) return error.BadSfnt;
        }
        previous = point;
    }
}

fn validateGdefLigCaretList(data: []const u8, offset: usize, glyph_count_bound: u16) FontError!void {
    if (offset + 4 > data.len) return error.BadSfnt;
    const coverage_relative = try bin.readU16At(data, offset);
    const lig_glyph_count = try bin.readU16At(data, offset + 2);
    const lig_glyph_offsets_pos = offset + 4;
    if (@as(usize, lig_glyph_count) * 2 > data.len - lig_glyph_offsets_pos) return error.BadSfnt;

    const lig_caret_data_start = 4 + @as(usize, lig_glyph_count) * 2;
    const coverage_offset = try checkedGdefRelativeOffset(data, offset, coverage_relative, lig_caret_data_start);
    try validateCoverageGlyphBounds(data, coverage_offset, glyph_count_bound);
    if (try coverageGlyphCount(data, coverage_offset) != lig_glyph_count) return error.BadSfnt;

    for (0..lig_glyph_count) |index| {
        const lig_glyph_relative = try bin.readU16At(data, lig_glyph_offsets_pos + index * 2);
        // LigGlyph offsets are parallel to Coverage indexes, and a LigGlyph's
        // own CaretValue offsets are parallel to its caret array.  Rejecting
        // offsets into either offset array keeps malformed GDEF data from
        // turning count/offset words into synthetic caret records.
        const lig_glyph_offset = try checkedGdefRelativeOffset(data, offset, lig_glyph_relative, lig_caret_data_start);
        try validateGdefLigGlyph(data, lig_glyph_offset);
    }
}

fn validateGdefLigGlyph(data: []const u8, offset: usize) FontError!void {
    if (offset + 2 > data.len) return error.BadSfnt;
    const caret_count = try bin.readU16At(data, offset);
    if (@as(usize, caret_count) * 2 > data.len - (offset + 2)) return error.BadSfnt;

    const caret_data_start = 2 + @as(usize, caret_count) * 2;
    for (0..caret_count) |index| {
        const caret_relative = try bin.readU16At(data, offset + 2 + index * 2);
        const caret_offset = try checkedGdefRelativeOffset(data, offset, caret_relative, caret_data_start);
        try validateGdefCaretValue(data, caret_offset);
    }
}

fn validateGdefCaretValue(data: []const u8, offset: usize) FontError!void {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => try ensureGdefBytesWithin(data, offset, 4),
        2 => try ensureGdefBytesWithin(data, offset, 4),
        3 => {
            try ensureGdefBytesWithin(data, offset, 6);
            const device_relative = try bin.readU16At(data, offset + 4);
            if (device_relative == 0) return error.BadSfnt;
            const device_offset = try checkedGdefRelativeOffset(data, offset, device_relative, 6);
            try validateGdefDeviceOrVariationIndexTable(data, device_offset);
        },
        else => return error.BadSfnt,
    }
}

fn validateGdefDeviceOrVariationIndexTable(data: []const u8, offset: usize) FontError!void {
    try ensureGdefBytesWithin(data, offset, 6);
    const start_size = try bin.readU16At(data, offset);
    const end_size = try bin.readU16At(data, offset + 2);
    const delta_format = try bin.readU16At(data, offset + 4);

    // Variable fonts reuse Device offsets for VariationIndex tables using
    // DeltaFormat 0x8000.  The table remains exactly the three uint16 fields;
    // the first two fields are outer/inner variation indexes instead of PPEM
    // sizes, so no packed delta payload follows.
    if (delta_format == 0x8000) return;
    if (end_size < start_size) return error.BadSfnt;

    const bits_per_delta: usize = switch (delta_format) {
        1 => 2,
        2 => 4,
        3 => 8,
        else => return error.BadSfnt,
    };
    const delta_count = @as(usize, end_size) - @as(usize, start_size) + 1;
    const words = (delta_count * bits_per_delta + 15) / 16;
    try ensureGdefBytesWithin(data, offset + 6, words * 2);
}

fn ensureGdefBytesWithin(data: []const u8, offset: usize, len: usize) FontError!void {
    if (offset > data.len or len > data.len - offset) return error.BadSfnt;
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

fn validateGlyphClassDefValues(data: []const u8, offset: usize) FontError!void {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 6 > data.len) return error.BadSfnt;
            const count = try bin.readU16At(data, offset + 4);
            if (@as(usize, count) * 2 > data.len - (offset + 6)) return error.BadSfnt;
            for (0..count) |index| {
                const class = try bin.readU16At(data, offset + 6 + index * 2);
                try validateGlyphClassValue(class);
            }
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
            try validateClassDefFormat2Ranges(data, offset, range_count);
            for (0..range_count) |index| {
                const class = try bin.readU16At(data, offset + 4 + index * 6 + 4);
                try validateGlyphClassValue(class);
            }
        },
        else => return error.BadSfnt,
    }
}

fn validateGlyphClassValue(class: u16) FontError!void {
    // GDEF's GlyphClassDef has a closed public vocabulary: 0 means
    // "unclassified" and 1..4 map to base, ligature, mark, and component.
    // MarkAttachClassDef deliberately does not use this helper because its
    // class numbers are font-defined attachment groups rather than glyph kinds.
    if (class > @intFromEnum(GlyphClass.component)) return error.BadSfnt;
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
        try validateCoverageGlyphBoundsForReadMode(data, offset + coverage_relative, glyph_count, .mark_filtering_set);
    }
}

const CoverageReadMode = enum {
    canonical,
    mark_filtering_set,
};

fn validateCoverageGlyphBounds(data: []const u8, offset: usize, glyph_count: u16) FontError!void {
    return validateCoverageGlyphBoundsForReadMode(data, offset, glyph_count, .canonical);
}

fn validateCoverageGlyphBoundsForReadMode(data: []const u8, offset: usize, glyph_count: u16, read_mode: CoverageReadMode) FontError!void {
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
                    switch (read_mode) {
                        .canonical => if (glyph_id <= last) return error.BadSfnt,
                        // Roboto's GDEF MarkGlyphSetsDef contains duplicate
                        // glyph ids in format-1 Coverage arrays. HarfBuzz and
                        // FreeType tolerate that shape for mark filtering, and
                        // downstream membership checks are set-like, so accept
                        // non-decreasing order here while still rejecting
                        // genuinely unsorted data.
                        .mark_filtering_set => if (glyph_id < last) return error.BadSfnt,
                    }
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

fn coverageGlyphCount(data: []const u8, offset: usize) FontError!u16 {
    if (offset + 2 > data.len) return error.BadSfnt;
    const format = try bin.readU16At(data, offset);
    switch (format) {
        1 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const count = try bin.readU16At(data, offset + 2);
            if (@as(usize, count) * 2 > data.len - (offset + 4)) return error.BadSfnt;
            return count;
        },
        2 => {
            if (offset + 4 > data.len) return error.BadSfnt;
            const range_count = try bin.readU16At(data, offset + 2);
            if (@as(usize, range_count) * 6 > data.len - (offset + 4)) return error.BadSfnt;
            var total: usize = 0;
            for (0..range_count) |index| {
                const range_offset = offset + 4 + index * 6;
                const start = try bin.readU16At(data, range_offset);
                const end = try bin.readU16At(data, range_offset + 2);
                if (end < start) return error.BadSfnt;
                total += @as(usize, end) - @as(usize, start) + 1;
                if (total > std.math.maxInt(u16)) return error.BadSfnt;
            }
            return @intCast(total);
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
            var out: usize = 0;
            for (0..glyph_count) |index| {
                const glyph_id = try bin.readU16At(data, offset + 4 + index * 2);
                if (previous) |last| {
                    if (glyph_id < last) return error.BadSfnt;
                    if (glyph_id == last) continue;
                }
                previous = glyph_id;
                glyphs[out] = glyph_id;
                out += 1;
            }
            return try allocator.realloc(glyphs, out);
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

fn cmapSubtableSupportsGlyphLookup(format: u16) bool {
    return switch (format) {
        0, 2, 4, 6, 8, 10, 12, 13 => true,
        else => false,
    };
}

fn readCmapLanguage(data: []const u8, offset: usize, length: usize, format: u16) FontError!?u32 {
    return switch (format) {
        0, 2, 4, 6 => blk: {
            if (length < 6) return error.BadSfnt;
            break :blk @as(u32, try bin.readU16At(data, offset + 4));
        },
        8, 10, 12, 13 => blk: {
            if (length < 12) return error.BadSfnt;
            break :blk try bin.readU32At(data, offset + 8);
        },
        else => null,
    };
}

fn isMacintoshRomanSubtable(subtable: CmapSubtable) bool {
    return subtable.platform_id == 1 and subtable.encoding_id == 0;
}

fn scoreCmap(subtable: CmapSubtable) u8 {
    if (subtable.format == 12 and subtable.platform_id == 3 and subtable.encoding_id == 10) return 8;
    if (subtable.format == 12 and subtable.platform_id == 0) return 7;
    if (subtable.format == 8 and subtable.platform_id == 0 and subtable.encoding_id == 4) return 6;
    if (subtable.format == 4 and subtable.platform_id == 3 and subtable.encoding_id == 1) return 5;
    if (subtable.format == 4 and subtable.platform_id == 0) return 4;
    if (subtable.format == 13 and ((subtable.platform_id == 0 and subtable.encoding_id == 6) or (subtable.platform_id == 3 and subtable.encoding_id == 10))) return 2;
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
    // Public glyphIndex has already rejected surrogate Unicode scalars. The
    // lazy structural recheck here intentionally keeps the scalar-domain flag
    // off because the platform/encoding record is validated by
    // validateCmapLookupSubtable before this format-specific lookup runs.
    try validateCmapFormat2(data, offset, length, false);

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
    if (@as(u64, groups) * 12 != @as(u64, length - 16)) return error.BadSfnt;

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
    if (@as(u64, groups) * 12 != @as(u64, length - groups_offset)) return error.BadSfnt;

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

fn glyphIndexFormat14(self: *const Font, offset: usize, length: usize, codepoint: u21, variation_selector: u21) FontError!?glyph_mod.GlyphId {
    if (variation_selector > 0xffffff or codepoint > 0xffffff) return null;
    const data = self.data;
    if (offset > data.len or length > data.len - offset) return error.BadSfnt;

    // Font keeps a borrowed byte slice, so callers can still mutate the backing
    // buffer after parse when it originated from []u8 test or application
    // storage. `variationGlyphIndex` has already revalidated the cached cmap
    // EncodingRecord and declared subtable length; keep this helper focused on
    // the format-14 ownership and glyph-id contracts before returning a UVS
    // glyph from mutable bytes.
    try validateCmapFormat14(data, offset, length);
    try validateCmapFormat14GlyphIds(data, offset, length, self.glyph_count);

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

fn kernFormat2Body(data: []const u8, left: glyph_mod.GlyphId, right: glyph_mod.GlyphId) FontError!?i16 {
    try validateKernFormat2Body(data, std.math.maxInt(u16));
    const left_class_offset = try bin.readU16At(data, 2);
    const right_class_offset = try bin.readU16At(data, 4);
    const left_offset = try kernFormat2ClassValue(data, left_class_offset, left);
    const right_offset = try kernFormat2ClassValue(data, right_class_offset, right);
    if (left_offset == 0 or right_offset == 0) return null;
    const combined_offset = @as(usize, left_offset) + @as(usize, right_offset);
    if (combined_offset < 8) return null;
    const value_offset = combined_offset - 8;
    if (value_offset > data.len - 2) return error.BadSfnt;
    const value = try bin.readI16At(data, value_offset);
    return if (value == 0) null else value;
}

fn validateKernFormat2Body(data: []const u8, glyph_count: u16) FontError!void {
    if (data.len < 8) return error.BadSfnt;
    const row_width = try bin.readU16At(data, 0);
    const left_class_offset = try bin.readU16At(data, 2);
    const right_class_offset = try bin.readU16At(data, 4);
    const array_offset = try bin.readU16At(data, 6);
    if (row_width == 0) return error.BadSfnt;
    if (array_offset < 8 or array_offset - 8 > data.len - 2) return error.BadSfnt;
    try validateKernFormat2ClassTable(data, left_class_offset, glyph_count);
    try validateKernFormat2ClassTable(data, right_class_offset, glyph_count);
}

fn validateKernFormat2ClassTable(data: []const u8, offset: usize, glyph_count: u16) FontError!void {
    if (offset < 8) return error.BadSfnt;
    const body_offset = offset - 8;
    if (body_offset > data.len - 4) return error.BadSfnt;
    const first_glyph = try bin.readU16At(data, body_offset);
    const glyph_len = try bin.readU16At(data, body_offset + 2);
    if (glyph_len == 0) return;
    if (@as(usize, first_glyph) + @as(usize, glyph_len) > @as(usize, glyph_count)) return error.BadSfnt;
    const values_offset = body_offset + 4;
    if (@as(usize, glyph_len) * 2 > data.len - values_offset) return error.BadSfnt;
    for (0..glyph_len) |index| {
        const value = try bin.readU16At(data, values_offset + index * 2);
        if (@as(usize, value) > data.len + 8 - 2) return error.BadSfnt;
    }
}

fn kernFormat2ClassValue(data: []const u8, class_table_offset: usize, glyph: glyph_mod.GlyphId) FontError!u16 {
    if (class_table_offset < 8) return error.BadSfnt;
    const body_offset = class_table_offset - 8;
    if (body_offset > data.len - 4) return error.BadSfnt;
    const first_glyph = try bin.readU16At(data, body_offset);
    const glyph_len = try bin.readU16At(data, body_offset + 2);
    if (glyph < first_glyph or glyph >= first_glyph + glyph_len) return 0;
    const value_offset = body_offset + 4 + (@as(usize, glyph - first_glyph) * 2);
    if (value_offset > data.len - 2) return error.BadSfnt;
    return try bin.readU16At(data, value_offset);
}

const SimpleGlyphVariation = struct {
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    axis_count: usize,
    glyph_id: glyph_mod.GlyphId,
    normalized_coords: []const f32,
    validate_inactive_payloads: bool,
};

fn appendSimpleGlyph(
    outline: *glyph_mod.GlyphOutline,
    transformed_points: ?*std.ArrayList(glyph_mod.Point),
    data: []const u8,
    contour_count: u16,
    transform: Transform,
    variation: ?SimpleGlyphVariation,
) FontError!?GvarPhantomPointDeltas {
    if (contour_count == 0) {
        // A contourless simple glyph can still vary its four metric phantom
        // points. Do not require real contours merely to preserve its advance
        // and side-bearing deltas.
        const gvar = variation orelse return null;
        const deltas = try gvar_mod.accumulateSimpleGlyphPointDeltas(
            outline.allocator,
            gvar.data,
            gvar.table_offset,
            gvar.table_length,
            gvar.glyph_count,
            gvar.axis_count,
            gvar.glyph_id,
            gvar.normalized_coords,
            &.{},
            &.{},
            gvar.validate_inactive_payloads,
        );
        defer if (deltas) |owned| outline.allocator.free(owned);
        return if (deltas) |all_deltas|
            try gvar_mod.phantomPointDeltasFromDense(0, all_deltas)
        else
            null;
    }
    var r = bin.Reader.init(data);
    _ = try r.readI16();
    try r.skip(8);
    var inline_end_pts: [8]u16 = undefined;
    const end_pts = if (contour_count <= inline_end_pts.len)
        inline_end_pts[0..contour_count]
    else
        try outline.allocator.alloc(u16, contour_count);
    defer if (contour_count > inline_end_pts.len) outline.allocator.free(end_pts);
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
    try outline.commands.ensureUnusedCapacity(outline.allocator, total_points + @as(usize, contour_count));

    // X and Y values are stored as deltas in two separate streams. Expand the
    // run-length encoded flags into the point records themselves so the hot
    // outline path does not carry a second per-point allocation.
    var inline_points: [64]FlaggedPoint = undefined;
    const points = if (total_points <= inline_points.len)
        inline_points[0..total_points]
    else
        try outline.allocator.alloc(FlaggedPoint, total_points);
    defer if (total_points > inline_points.len) outline.allocator.free(points);
    var i: usize = 0;
    while (i < total_points) : (i += 1) {
        const flag = try r.readU8();
        try validateSimpleGlyphFlag(flag, i);
        points[i].flags = flag;
        if ((flag & 0x08) != 0) {
            const repeat = try r.readU8();
            for (0..repeat) |_| {
                i += 1;
                if (i >= total_points) return error.InvalidGlyph;
                try validateSimpleGlyphFlag(flag, i);
                points[i].flags = flag;
            }
        }
    }

    // Rebuild absolute point coordinates before contour reconstruction.
    var x: i16 = 0;
    for (points) |*point| {
        const flag = point.flags;
        const dx: i16 = if ((flag & 0x02) != 0)
            if ((flag & 0x10) != 0) try r.readU8() else -@as(i16, try r.readU8())
        else if ((flag & 0x10) != 0)
            0
        else
            try r.readI16();
        x += dx;
        point.x = x;
    }
    var y: i16 = 0;
    for (points) |*point| {
        const flag = point.flags;
        const dy: i16 = if ((flag & 0x04) != 0)
            if ((flag & 0x20) != 0) try r.readU8() else -@as(i16, try r.readU8())
        else if ((flag & 0x20) != 0)
            0
        else
            try r.readI16();
        y += dy;
        point.y = y;
    }
    var phantom_deltas: ?GvarPhantomPointDeltas = null;
    if (variation) |gvar| {
        const deltas = try gvar_mod.accumulateSimpleGlyphPointDeltasWithReader(
            outline.allocator,
            gvar.data,
            gvar.table_offset,
            gvar.table_length,
            gvar.glyph_count,
            gvar.axis_count,
            gvar.glyph_id,
            gvar.normalized_coords,
            []const FlaggedPoint,
            points,
            points.len,
            flaggedPointForGvarIup,
            end_pts,
            gvar.validate_inactive_payloads,
        );
        defer if (deltas) |owned| outline.allocator.free(owned);
        if (deltas) |all_deltas| {
            const real_deltas = all_deltas[0..points.len];
            std.debug.assert(gvarDensePointIdsMatch(real_deltas));
            for (points, real_deltas) |*point, delta| {
                point.x = clampGlyphPointF32ToI16(roundOpenTypeF32(@as(f32, @floatFromInt(point.x)) + delta.x));
                point.y = clampGlyphPointF32ToI16(roundOpenTypeF32(@as(f32, @floatFromInt(point.y)) + delta.y));
            }
            // glyf headers remain authoritative when this glyph has no active
            // tuple. Recompute bounds only after gvar actually changed the
            // decoded point set.
            outline.bounds = boundsForFlaggedPoints(points);
            // The same tuple walk already decoded the four phantom points.
            // Return them to the top-level simple-glyph caller instead of
            // reparsing gvar solely to update advance and side-bearing fields.
            phantom_deltas = try gvar_mod.phantomPointDeltasFromDense(points.len, all_deltas);
        }
    }

    if (transformed_points) |raw_points| {
        // Compound point anchors address the original glyf points, including
        // off-curve controls that may disappear into implied path endpoints.
        // Preserve those points only for the lifetime of this recursive load;
        // GlyphOutline remains a compact command stream after expansion.
        try raw_points.ensureUnusedCapacity(outline.allocator, points.len);
        for (points) |point| raw_points.appendAssumeCapacity(transform.apply(point.point()));
    }

    var start: usize = 0;
    var builder = glyph_mod.OutlineBuilder{ .outline = outline };
    for (end_pts) |end_pt| {
        const end: usize = end_pt;
        try appendContour(&builder, points[start .. end + 1], transform);
        start = end + 1;
    }
    return phantom_deltas;
}

fn gvarDensePointIdsMatch(deltas: []const GvarScaledPointDelta) bool {
    for (deltas, 0..) |delta, index| {
        if (delta.point != index) return false;
    }
    return true;
}

fn flaggedPointForGvarIup(points: []const FlaggedPoint, index: usize) gvar_mod.Point {
    return .{ .x = @floatFromInt(points[index].x), .y = @floatFromInt(points[index].y) };
}

fn boundsForFlaggedPoints(points: []const FlaggedPoint) glyph_mod.Bounds {
    if (points.len == 0) return .{ .x_min = 0, .y_min = 0, .x_max = 0, .y_max = 0 };
    var result = glyph_mod.Bounds{
        .x_min = points[0].x,
        .y_min = points[0].y,
        .x_max = points[0].x,
        .y_max = points[0].y,
    };
    for (points[1..]) |point| {
        result.x_min = @min(result.x_min, point.x);
        result.y_min = @min(result.y_min, point.y);
        result.x_max = @max(result.x_max, point.x);
        result.y_max = @max(result.y_max, point.y);
    }
    return result;
}

fn gvarDeltaForPoint(deltas: []const GvarScaledPointDelta, point: usize) gvar_mod.Point {
    if (point > std.math.maxInt(u16)) return .{ .x = 0, .y = 0 };
    const point_id: u16 = @intCast(point);
    if (point < deltas.len and deltas[point].point == point_id) {
        return .{ .x = deltas[point].x, .y = deltas[point].y };
    }
    var result = gvar_mod.Point{ .x = 0, .y = 0 };
    for (deltas) |delta| {
        if (delta.point != point_id) continue;
        result.x += delta.x;
        result.y += delta.y;
    }
    return result;
}

fn applyGvarGlyphMetricDeltas(outline: *glyph_mod.GlyphOutline, default_bounds: glyph_mod.Bounds, default_metrics: HorizontalMetricInfo, phantom: GvarPhantomPointDeltas) void {
    const default_left_phantom = @as(f32, @floatFromInt(@as(i32, default_bounds.x_min) - @as(i32, default_metrics.left_side_bearing)));
    const varied_left_phantom = default_left_phantom + phantom.left.x;
    outline.left_side_bearing = clampGlyphPointF32ToI16(roundOpenTypeF32(@as(f32, @floatFromInt(outline.bounds.x_min)) - varied_left_phantom));
    outline.advance_width = clampF32ToU16(roundOpenTypeF32(@as(f32, @floatFromInt(default_metrics.advance_width)) + phantom.horizontalAdvanceDelta()));
}

fn clampF32ToU16(value: f32) u16 {
    if (value <= 0) return 0;
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(u16)))) return std.math.maxInt(u16);
    return @intFromFloat(value);
}

fn clampI32ToU16(value: i32) u16 {
    if (value <= 0) return 0;
    if (value >= std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(value);
}

fn clampI32ToI16(value: i32) i16 {
    if (value <= std.math.minInt(i16)) return std.math.minInt(i16);
    if (value >= std.math.maxInt(i16)) return std.math.maxInt(i16);
    return @intCast(value);
}

fn clampGlyphPointF32ToI16(value: f32) i16 {
    if (value <= @as(f32, @floatFromInt(std.math.minInt(i16)))) return std.math.minInt(i16);
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(i16)))) return std.math.maxInt(i16);
    return @intFromFloat(value);
}

fn roundOpenTypeF32(value: f32) f32 {
    // OpenType variation arithmetic rounds a .5 tie toward +infinity, not
    // away from zero like Zig's @round. This distinction is observable for a
    // negative half-unit gvar delta: -101.5 becomes -101, matching FreeType's
    // FT_fixedToInt and fontTools' otRound.
    return @floor(value + 0.5);
}

test "OpenType variation rounding sends half-unit ties toward positive infinity" {
    try std.testing.expectEqual(@as(f32, -103), roundOpenTypeF32(-102.5001));
    try std.testing.expectEqual(@as(f32, -101), roundOpenTypeF32(-101.5));
    try std.testing.expectEqual(@as(f32, 101), roundOpenTypeF32(100.5));
    try std.testing.expectEqual(@as(f32, 101), roundOpenTypeF32(100.5001));
}

fn roundedGlyphPosition(value: f32) i32 {
    if (value <= @as(f32, @floatFromInt(std.math.minInt(i32)))) return std.math.minInt(i32);
    if (value >= @as(f32, @floatFromInt(std.math.maxInt(i32)))) return std.math.maxInt(i32);
    return @intFromFloat(@round(value));
}

const FlaggedPoint = struct {
    x: i16 = 0,
    y: i16 = 0,
    flags: u8 = 0,

    fn onCurve(self: FlaggedPoint) bool {
        return (self.flags & 0x01) != 0;
    }

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
    if (first.onCurve()) {
        current = first.point();
        index = 1;
    } else if (last.onCurve()) {
        current = last.point();
    } else {
        current = glyph_mod.midpoint(last.point(), first.point());
    }
    try builder.moveTo(transform.apply(current));

    while (index < contour.len) {
        const p = contour[index];
        if (p.onCurve()) {
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
            const end = if (next.onCurve()) next.point() else glyph_mod.midpoint(control, next.point());
            try builder.quadTo(transform.apply(control), transform.apply(end));
            current = end;
            index += if (next.onCurve() and next_index != 0) 2 else 1;
        }
    }
    try builder.close();
}

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

fn quantizeNormalizedF2Dot14(value: f32) f32 {
    // HarfBuzz's public design-coordinate path first represents normalized
    // fvar/avar output in 16.16, then rounds that fixed value to F2Dot14.
    // Collapsing the two steps is not equivalent: 0.1 becomes 6554 in 16.16
    // and then 1639 in F2Dot14, while direct 14-bit rounding produces 1638.
    const fixed_16_16: i32 = @intFromFloat(@round(value * 65536.0));
    const fixed_2_14: i16 = @intCast((fixed_16_16 + 2) >> 2);
    return f2dot14(fixed_2_14);
}

fn fixed16_16ToF32(value: i32) f32 {
    return @as(f32, @floatFromInt(value)) / 65536.0;
}

fn trackingValueForPointSize(values: []const TrackValueInfo, point_size: f32) f32 {
    if (values.len == 0) return 0;
    for (values, 0..) |value, index| {
        if (value.size >= point_size) {
            if (index == 0) return @floatFromInt(value.value);
            const prev = values[index - 1];
            const span = value.size - prev.size;
            if (@abs(span) < std.math.floatEps(f32)) {
                return (@as(f32, @floatFromInt(prev.value)) + @as(f32, @floatFromInt(value.value))) * 0.5;
            }
            const t = (point_size - prev.size) / span;
            return @as(f32, @floatFromInt(prev.value)) +
                t * (@as(f32, @floatFromInt(value.value)) - @as(f32, @floatFromInt(prev.value)));
        }
    }
    return @floatFromInt(values[values.len - 1].value);
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

const StatInfo = struct {
    minor: u16,
    design_axis_size: usize,
    design_axis_count: usize,
    design_axes_offset: usize,
    axis_value_count: usize,
    axis_value_offsets_offset: usize,
};

const VariationNameValidationOptions = struct {
    compat_ttc_face: bool = false,
};

fn validateVariationNameReferences(allocator: std.mem.Allocator, data: []const u8, fvar: ?TableRecord, stat: ?TableRecord, name: ?TableRecord, options: VariationNameValidationOptions) FontError!void {
    if (fvar == null and stat == null) return;

    var name_index_storage: NameIdIndex = undefined;
    const name_index: ?*const NameIdIndex = if (name) |name_table| blk: {
        name_index_storage = try readNameIdIndex(data, name_table);
        break :blk &name_index_storage;
    } else null;

    // Axis labels describe the public design-coordinate controls and stay
    // strict for ordinary faces. Named instances are optional convenience
    // metadata: deployed variable fonts and upstream rendering fixtures can
    // carry stale instance labels while their axes and variation data remain
    // usable. variationInstances() revalidates the complete name contract.
    if (fvar) |fvar_table| {
        validateFvarAxisNameReferences(data, fvar_table, name_index) catch |err| switch (err) {
            error.InvalidName => if (!options.compat_ttc_face) return err,
            else => return err,
        };
    }
    if (stat) |stat_table| {
        validateStatTable(allocator, data, stat_table, fvar, name_index) catch |err| switch (err) {
            // STAT is optional for shaping, and several upstream shaping
            // fixtures carry stale STAT name IDs even though cmap/GSUB/GPOS
            // bytes are usable. Keep public STAT APIs strict; they revalidate
            // borrowed STAT bytes before exposing user-facing metadata.
            error.InvalidName => return,
            error.BadSfnt => if (fvar != null) return err,
            else => return err,
        };
    }
}

fn validateFvarNameReferences(data: []const u8, fvar: TableRecord, name_index: ?*const NameIdIndex) FontError!void {
    try validateFvarAxisNameReferences(data, fvar, name_index);
    try validateFvarInstanceNameReferences(data, fvar, name_index);
}

fn validateFvarAxisNameReferences(data: []const u8, fvar: TableRecord, name_index: ?*const NameIdIndex) FontError!void {
    const info = try readFvarInfo(data, fvar);
    for (0..info.axis_count) |index| {
        const axis_offset = fvarAxisOffset(fvar, info, index);
        try validateNameIdReference(name_index, try bin.readU16At(data, axis_offset + 18));
    }
}

fn validateFvarInstanceNameReferences(data: []const u8, fvar: TableRecord, name_index: ?*const NameIdIndex) FontError!void {
    const info = try readFvarInfo(data, fvar);
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
        try sfnt.validateTag(tag);
        for (0..axis_index) |previous_index| {
            const previous_offset = fvarAxisOffset(fvar, info, previous_index);
            const previous_tag = try bin.readTagAt(data, previous_offset);
            const previous_flags = try bin.readU16At(data, previous_offset + 16);
            if (std.mem.eql(u8, &previous_tag, &tag) and (flags & 0x0001) == 0 and (previous_flags & 0x0001) == 0) return error.BadSfnt;
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
    const info = try readStatInfo(data, stat);
    if (info.minor >= 1) try validateNameIdReference(name_index, try bin.readU16At(data, stat.offset + 18));

    for (0..info.design_axis_count) |index| {
        const stat_axis = stat.offset + info.design_axes_offset + index * info.design_axis_size;
        const stat_tag = try bin.readTagAt(data, stat_axis);
        try sfnt.validateTag(stat_tag);
        try validateStatDesignAxisOrder(data, stat, fvar, info.design_axes_offset, info.design_axis_size, index, &stat_tag);
        try validateNameIdReference(name_index, try bin.readU16At(data, stat_axis + 4));
    }

    const axis_values = try allocator.alloc(StatAxisValueSummary, info.axis_value_count);
    defer allocator.free(axis_values);
    for (axis_values, 0..) |*axis_value, index| {
        const entry_offset = stat.offset + info.axis_value_offsets_offset + index * 2;
        const axis_value_offset = try resolveStatAxisValueOffset(data, stat, info.axis_value_offsets_offset, entry_offset);
        axis_value.* = try validateStatAxisValue(
            data,
            stat,
            axis_value_offset,
            info.design_axis_count,
            info.design_axes_offset,
            info.design_axis_size,
            info.axis_value_offsets_offset,
            info.axis_value_count,
            name_index,
        );
    }
    try validateStatAxisValueSet(data, stat, axis_values);
}

fn readStatInfo(data: []const u8, stat: TableRecord) FontError!StatInfo {
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

    return .{
        .minor = minor,
        .design_axis_size = design_axis_size,
        .design_axis_count = design_axis_count,
        .design_axes_offset = design_axes_offset,
        .axis_value_count = axis_value_count,
        .axis_value_offsets_offset = axis_value_offsets_offset,
    };
}

fn validateStatDesignAxisOrder(data: []const u8, stat: TableRecord, fvar: ?TableRecord, design_axes_offset: usize, design_axis_size: usize, axis_index: usize, axis_tag: *const [4]u8) FontError!void {
    const axis_record = stat.offset + design_axes_offset + axis_index * design_axis_size;
    const axis_ordering = try bin.readU16At(data, axis_record + 6);
    for (0..axis_index) |previous_index| {
        const previous_record = stat.offset + design_axes_offset + previous_index * design_axis_size;
        const previous_tag = try bin.readTagAt(data, previous_record);
        if (std.mem.eql(u8, axis_tag, &previous_tag) and !try statDuplicateAxisTagsAllowedByFvar(data, fvar, previous_index, axis_index)) return error.BadSfnt;
        const previous_ordering = try bin.readU16At(data, previous_record + 6);
        // AxisOrdering is the canonical presentation sort key for STAT axes.
        // Duplicate ordering values leave style UIs with no deterministic
        // canonical axis order, even when the axis tags themselves differ.
        if (axis_ordering == previous_ordering) return error.BadSfnt;
    }
}

fn statDuplicateAxisTagsAllowedByFvar(data: []const u8, fvar: ?TableRecord, previous_index: usize, axis_index: usize) FontError!bool {
    const fvar_table = fvar orelse return false;
    const info = try readFvarInfo(data, fvar_table);
    if (previous_index >= info.axis_count or axis_index >= info.axis_count) return false;
    const previous_offset = fvarAxisOffset(fvar_table, info, previous_index);
    const axis_offset = fvarAxisOffset(fvar_table, info, axis_index);
    const previous_flags = try bin.readU16At(data, previous_offset + 16);
    const flags = try bin.readU16At(data, axis_offset + 16);
    return (previous_flags & 0x0001) != 0 or (flags & 0x0001) != 0;
}

fn resolveStatAxisValueOffset(data: []const u8, stat: TableRecord, axis_value_offsets_offset: usize, entry_offset: usize) FontError!usize {
    const relative_offset: usize = @intCast(try bin.readU16At(data, entry_offset));
    if (relative_offset > stat.length - axis_value_offsets_offset) return error.BadSfnt;
    const axis_value_offset = axis_value_offsets_offset + relative_offset;
    if (axis_value_offset < 20 or axis_value_offset > stat.length - 4) return error.BadSfnt;
    return axis_value_offset;
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

fn readStatAxisValue(allocator: std.mem.Allocator, data: []const u8, stat: TableRecord, axis_value_offset: usize) FontError!StatAxisValue {
    const absolute = stat.offset + axis_value_offset;
    const format = try bin.readU16At(data, absolute);
    return switch (format) {
        1 => .{
            .format = format,
            .axis_index = try bin.readU16At(data, absolute + 2),
            .flags = try bin.readU16At(data, absolute + 4),
            .name_id = try bin.readU16At(data, absolute + 6),
            .value = fixed16_16ToF32(try bin.readI32At(data, absolute + 8)),
        },
        2 => .{
            .format = format,
            .axis_index = try bin.readU16At(data, absolute + 2),
            .flags = try bin.readU16At(data, absolute + 4),
            .name_id = try bin.readU16At(data, absolute + 6),
            .nominal_value = fixed16_16ToF32(try bin.readI32At(data, absolute + 8)),
            .range_min_value = fixed16_16ToF32(try bin.readI32At(data, absolute + 12)),
            .range_max_value = fixed16_16ToF32(try bin.readI32At(data, absolute + 16)),
        },
        3 => .{
            .format = format,
            .axis_index = try bin.readU16At(data, absolute + 2),
            .flags = try bin.readU16At(data, absolute + 4),
            .name_id = try bin.readU16At(data, absolute + 6),
            .value = fixed16_16ToF32(try bin.readI32At(data, absolute + 8)),
            .linked_value = fixed16_16ToF32(try bin.readI32At(data, absolute + 12)),
        },
        4 => value: {
            const axis_count: usize = @intCast(try bin.readU16At(data, absolute + 2));
            const coordinates = try allocator.alloc(StatAxisValueCoordinate, axis_count);
            errdefer allocator.free(coordinates);
            for (coordinates, 0..) |*coordinate, axis_record_index| {
                const axis_record = absolute + 8 + axis_record_index * 6;
                coordinate.* = .{
                    .axis_index = try bin.readU16At(data, axis_record),
                    .value = fixed16_16ToF32(try bin.readI32At(data, axis_record + 2)),
                };
            }
            break :value .{
                .format = format,
                .flags = try bin.readU16At(data, absolute + 4),
                .name_id = try bin.readU16At(data, absolute + 6),
                .coordinates = coordinates,
            };
        },
        else => error.BadSfnt,
    };
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
            .multi_axis => |multi_axis_b| _ = try validateStatMultiAxisPair(data, stat, a, multi_axis_a, b, multi_axis_b),
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

fn validateStatMultiAxisPair(data: []const u8, stat: TableRecord, a: StatAxisValueSummary, multi_axis_a: StatMultiAxis, b: StatAxisValueSummary, multi_axis_b: StatMultiAxis) FontError!bool {
    if (multi_axis_a.axis_count != multi_axis_b.axis_count) return false;

    // AxisValue format 4 is a compound style label; axisValueRecords are a set
    // of axis/value coordinates, not a distinct ordered tuple. Reject exact
    // set duplicates regardless of name IDs or flags so style-name resolution
    // cannot depend on AxisValue record order. Proper subset/superset matches
    // remain valid because the later selector can prefer the more-specific set.
    for (0..multi_axis_a.axis_count) |axis_record_index| {
        const coordinate = try readStatMultiAxisCoordinate(data, stat, a.offset, axis_record_index);
        const b_value = try statMultiAxisValueForAxis(data, stat, b.offset, multi_axis_b.axis_count, coordinate.axis_index) orelse return false;
        if (b_value != coordinate.value) return false;
    }
    return true;
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
    const minimum_axis_size: usize = 20;
    const minimum_instance_size: usize = 4 + axis_count * 4;
    // fvar defines fixed axis records and instance records that are either the
    // coordinate payload alone or that payload plus a PostScript-name ID. Do not
    // accept larger private record strides: extra bytes would be unreachable by
    // this parser, and an instanceSize that is larger than the coordinates but
    // not large enough for the optional name ID would make the same bytes look
    // like padding to one consumer and metadata to another.
    if (axis_size != minimum_axis_size) return error.BadSfnt;
    if (instance_count == 0) {
        if (instance_size != 0 and instance_size != minimum_instance_size and instance_size != minimum_instance_size + 2) return error.BadSfnt;
    } else if (instance_size != minimum_instance_size and instance_size != minimum_instance_size + 2) {
        return error.BadSfnt;
    }

    // countSizePairs is part of the fvar header layout contract: exactly two
    // count/size pairs follow it, axisCount/axisSize and
    // instanceCount/instanceSize. Validate that contract together with the
    // table-local regions so malformed headers cannot reinterpret bytes from a
    // hypothetical alternate layout as variation metadata.
    if (axes_array_offset < 16 or axes_array_offset > fvar.length) return error.BadSfnt;
    if (axis_count > (fvar.length - axes_array_offset) / axis_size) return error.BadSfnt;
    const axes_bytes = axis_count * axis_size;
    const instances_offset = axes_array_offset + axes_bytes;
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

fn validateCvtTable(cvt: TableRecord) FontError!usize {
    if ((cvt.length & 1) != 0) return error.BadSfnt;
    return cvt.length / 2;
}

fn readCvtValues(allocator: std.mem.Allocator, data: []const u8, cvt: TableRecord) FontError![]i16 {
    const value_count = try validateCvtTable(cvt);
    const values = try allocator.alloc(i16, value_count);
    errdefer allocator.free(values);
    for (values, 0..) |*value, index| value.* = try bin.readI16At(data, cvt.offset + index * 2);
    return values;
}

fn validateCvarTable(data: []const u8, cvar: TableRecord, fvar_axis_count: usize, cvt_value_count: usize) FontError!void {
    return try cvar_mod.validate(data, cvar.offset, cvar.length, fvar_axis_count, cvt_value_count);
}

fn validateVarcTable(data: []const u8, varc: TableRecord, glyph_count: u16) FontError!void {
    return try varc_mod.validate(data, varc.offset, varc.length, glyph_count);
}

fn validateIftPatchMapTable(data: []const u8, table: TableRecord) FontError!void {
    return try ift_mod.validate(data, table.offset, table.length);
}

fn validateTrueTypeProgramTable(data: []const u8, table: TableRecord) FontError!void {
    return try tt_program_mod.validate(data[table.offset .. table.offset + table.length]);
}

fn validateVariationDataTables(
    data: []const u8,
    glyph_count: u16,
    fvar: ?TableRecord,
    gvar: ?TableRecord,
    hvar: ?TableRecord,
    mvar: ?TableRecord,
    vvar: ?TableRecord,
    gvar_target_context: ?GvarGlyphTargetContext,
) FontError!void {
    return try validateVariationDataTablesWithCvar(data, glyph_count, fvar, gvar, hvar, mvar, vvar, null, null, gvar_target_context);
}

fn validateVariationDataTablesWithCvar(
    data: []const u8,
    glyph_count: u16,
    fvar: ?TableRecord,
    gvar: ?TableRecord,
    hvar: ?TableRecord,
    mvar: ?TableRecord,
    vvar: ?TableRecord,
    cvar: ?TableRecord,
    cvt_value_count: ?usize,
    gvar_target_context: ?GvarGlyphTargetContext,
) FontError!void {
    if (gvar == null and hvar == null and mvar == null and vvar == null and cvar == null) return;
    const fvar_info = try readFvarInfo(data, fvar orelse return error.BadSfnt);
    if (gvar) |table| try validateGvarTable(data, table, glyph_count, fvar_info.axis_count, gvar_target_context);
    if (hvar) |table| try validateMetricVariationTable(data, table, fvar_info.axis_count, 20);
    if (vvar) |table| try validateMetricVariationTable(data, table, fvar_info.axis_count, 24);
    if (mvar) |table| try validateMvarTable(data, table, fvar_info.axis_count);
    if (cvar) |table| try validateCvarTable(data, table, fvar_info.axis_count, cvt_value_count orelse return error.BadSfnt);
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
    return (try gvar_mod.glyfVariationPointCount(glyph_data)) + 4;
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
    const store_info = try item_store.validate(
        data,
        variationTable(table),
        store_offset,
        fvar_axis_count,
        minimum_length,
    );
    try validateMetricVariationTopLevelPayloads(data, table, store_offset, store_info, minimum_length);
}

fn validateMetricVariationTopLevelPayloads(data: []const u8, table: TableRecord, store_offset: usize, store_info: item_store.Info, minimum_length: usize) FontError!void {
    // HVAR/VVAR carry several optional DeltaSetIndexMap subtables next to the
    // ItemVariationStore. These offsets share one table-relative namespace, so
    // validate them as independently-owned top-level payloads instead of
    // allowing a map to borrow store bytes (or another map's header) that happen
    // to decode as a plausible var-index map.
    var ranges: [5]item_store.Range = undefined;
    var range_count: usize = 0;
    ranges[range_count] = .{ .start = store_offset, .end = store_info.end_offset };
    range_count += 1;

    const map_field_count: usize = if (minimum_length >= 24) 4 else 3;
    for (0..map_field_count) |map_field_index| {
        const map_offset: usize = @intCast(try bin.readU32At(data, table.offset + 8 + map_field_index * 4));
        if (map_offset == 0) continue;
        const map = try validateDeltaSetIndexMap(data, table, store_offset, store_info.item_data_count, map_offset, minimum_length);
        const map_range = item_store.Range{
            .start = map.offset,
            .end = map.end_offset,
        };
        var already_owned = false;
        for (ranges[0..range_count]) |owned| {
            if (item_store.rangesEqual(map_range, owned)) {
                already_owned = true;
                break;
            }
            if (item_store.rangesOverlap(map_range, owned)) return error.BadSfnt;
        }
        if (already_owned) continue;
        ranges[range_count] = map_range;
        range_count += 1;
    }
}

fn validateDeltaSetIndexMap(
    data: []const u8,
    table: TableRecord,
    store_offset: usize,
    item_data_count: usize,
    map_offset: usize,
    minimum_map_offset: usize,
) FontError!delta_map.Map {
    const map = try delta_map.read(
        data,
        variationTable(table),
        map_offset,
        minimum_map_offset,
    );
    for (0..map.map_count) |index| {
        const mapped = try delta_map.entry(data, map, index);
        if (mapped.outer == 0xffff and mapped.inner == 0xffff) continue;
        if (mapped.outer >= item_data_count or
            mapped.inner >= try item_store.itemCount(
                data,
                variationTable(table),
                store_offset,
                mapped.outer,
            ))
        {
            return error.BadSfnt;
        }
    }
    return map;
}

fn validateMvarTable(data: []const u8, mvar: TableRecord, fvar_axis_count: usize) FontError!void {
    const mvar_header = try mvar_mod.header(data, mvar.offset, mvar.length);
    try mvar_mod.validateValueRecords(data, mvar.offset, mvar_header);
    const store_offset = mvar_header.item_variation_store_offset orelse return;

    const store_info = try item_store.validate(
        data,
        variationTable(mvar),
        store_offset,
        fvar_axis_count,
        mvar_header.records_end,
    );
    for (0..mvar_header.value_record_count) |index| {
        const record = try mvar_mod.valueRecordAt(data, mvar.offset, mvar_header, index);
        if (!record.hasVariationData()) continue;

        const outer_index: usize = @intCast(record.delta_set_outer_index);
        const inner_index: usize = @intCast(record.delta_set_inner_index);
        if (outer_index >= store_info.item_data_count) return error.BadSfnt;
        const item_count = try item_store.itemCount(
            data,
            variationTable(mvar),
            store_offset,
            outer_index,
        );
        if (inner_index >= item_count) return error.BadSfnt;
    }
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

const max_svg_document_size = svg_mod.document.max_document_size;

fn validateSvgDocumentPayload(
    allocator: std.mem.Allocator,
    document: []const u8,
) FontError!void {
    return try svg_mod.document.validate(allocator, document);
}

fn validateSvgGlyphBounds(
    allocator: std.mem.Allocator,
    data: []const u8,
    svg: TableRecord,
    glyph_count: u16,
) FontError!void {
    return try svg_mod.validate(
        allocator,
        data,
        svgTable(svg),
        glyph_count,
    );
}

fn validateColrPaletteBounds(data: []const u8, colr: TableRecord, cpal: ?TableRecord) FontError!void {
    if (colr.length < 2) return error.BadSfnt;
    const cpal_palette_entries = if (cpal) |cpal_table|
        (try cpal_mod.validateStructure(
            data,
            cpalTable(cpal_table),
        )).palette_entries
    else
        null;
    const version = try bin.readU16At(data, colr.offset);
    switch (version) {
        0 => try validateColrV0PaletteBounds(data, colr, cpal_palette_entries),
        1 => try colr_palette.validate(
            data,
            colrV1Table(colr),
            cpal_palette_entries,
        ),
        else => {},
    }
}

fn validateColrV0PaletteBounds(data: []const u8, colr: TableRecord, cpal_palette_entries: ?u16) FontError!void {
    _ = try colr_v0_mod.validatePalettes(
        data,
        colrV0Table(colr),
        cpal_palette_entries,
    );
}

fn validateColrGlyphBounds(data: []const u8, colr: TableRecord, glyph_count: u16) FontError!void {
    if (colr.length < 2) return error.BadSfnt;
    const version = try bin.readU16At(data, colr.offset);
    switch (version) {
        0 => try validateColrV0GlyphBounds(data, colr, glyph_count),
        1 => try colr_glyphs.validate(
            data,
            colrV1Table(colr),
            glyph_count,
        ),
        else => {},
    }
}

fn validateColrV0GlyphBounds(data: []const u8, colr: TableRecord, glyph_count: u16) FontError!void {
    _ = try colr_v0_mod.validateGlyphs(
        data,
        colrV0Table(colr),
        glyph_count,
    );
}

const ColrVariationContext = colr_variation.Context;

const ColorPaintReadContext = colr_read.Context;

const ColorLineReadState = struct {
    table: colr_v1_mod.Table,
    context: ColorPaintReadContext,
};

fn readColrVariationContext(data: []const u8, colr: TableRecord) FontError!?ColrVariationContext {
    return try colr_variation.read(data, colrV1Table(colr));
}

fn validateColrVariationData(
    data: []const u8,
    colr: TableRecord,
    fvar: ?TableRecord,
    glyph_count: u16,
) FontError!void {
    // Static COLR v1 data does not consume FVAR. Preserve that independence so
    // merely carrying an unrelated FVAR table cannot affect a static color
    // graph's validation path.
    const has_store = colr.length >= 34 and
        try bin.readU32At(data, colr.offset + 30) != 0;
    const axis_count = if (has_store)
        (try readFvarInfo(data, fvar orelse return error.BadSfnt)).axis_count
    else
        null;
    return try colr_variation.validate(
        data,
        colrV1Table(colr),
        axis_count,
        glyph_count,
    );
}

fn validateGlyphIdInMaxp(glyph_id: u32, glyph_count: u16) FontError!void {
    if (glyph_id >= glyph_count) return error.BadSfnt;
}

fn readColorPaint(font: *const Font, offset: usize, context: ColorPaintReadContext) FontError!ColorPaint {
    const colr = font.colr orelse return error.BadSfnt;
    return try colr_read.paint(
        font.data,
        colrV1Table(colr),
        offset,
        context,
    );
}

test "COLR v1 transform formats resolve affine matrices" {
    var bytes: [320]u8 = .{0} ** 320;
    const font = colrOnlyFont(&bytes);
    const context = ColorPaintReadContext{ .normalized_coords = &.{}, .variation = null };
    const varied_context = ColorPaintReadContext{
        .normalized_coords = &.{1},
        .variation = .{ .store_offset = 240, .item_data_count = 1, .map = null },
    };

    for (12..32) |raw_format| {
        @memset(&bytes, 0);
        writeItemVariationStoreWithItems(&bytes, 240, 10);
        const format: u8 = @intCast(raw_format);
        const info = colr_paint.formatInfo(format).?;
        bytes[0] = format;
        writeU24Test(&bytes, 1, @intCast(info.min_size));
        bytes[info.min_size] = 2; // PaintSolid child.
        writeU16Test(&bytes, info.min_size + 1, 0);
        writeF2Dot14Test(&bytes, info.min_size + 3, 1);

        switch (format) {
            12, 13 => {
                writeU24Test(&bytes, 4, @intCast(info.min_size + 5));
                const matrix = info.min_size + 5;
                writeF16Dot16Test(&bytes, matrix + 0, 2);
                writeF16Dot16Test(&bytes, matrix + 4, 0);
                writeF16Dot16Test(&bytes, matrix + 8, 0);
                writeF16Dot16Test(&bytes, matrix + 12, 3);
                writeF16Dot16Test(&bytes, matrix + 16, 40);
                writeF16Dot16Test(&bytes, matrix + 20, 50);
                if (format == 13) writeU32Test(&bytes, matrix + 24, 0);
            },
            14, 15 => {
                writeI16Test(&bytes, 4, 40);
                writeI16Test(&bytes, 6, 50);
                if (format == 15) writeU32Test(&bytes, 8, 0);
            },
            16...23 => {
                writeF2Dot14Test(&bytes, 4, 0.5);
                if (format < 20) writeF2Dot14Test(&bytes, 6, 0.75);
                if (format == 18 or format == 19 or format == 22 or format == 23) {
                    const center: usize = if (format >= 20) 6 else 8;
                    writeI16Test(&bytes, center, 100);
                    writeI16Test(&bytes, center + 2, 200);
                }
                if ((format & 1) != 0) writeU32Test(&bytes, info.min_size - 4, 0);
            },
            24...27 => {
                writeF2Dot14Test(&bytes, 4, 0.5);
                if (format >= 26) {
                    writeI16Test(&bytes, 6, 100);
                    writeI16Test(&bytes, 8, 200);
                }
                if ((format & 1) != 0) writeU32Test(&bytes, info.min_size - 4, 0);
            },
            28...31 => {
                writeF2Dot14Test(&bytes, 4, 0.25);
                writeF2Dot14Test(&bytes, 6, 0);
                if (format >= 30) {
                    writeI16Test(&bytes, 8, 100);
                    writeI16Test(&bytes, 10, 200);
                }
                if ((format & 1) != 0) writeU32Test(&bytes, info.min_size - 4, 0);
            },
            else => unreachable,
        }

        const result = try colr_read.transform(font.data, colrV1Table(font.colr.?), 0, context);
        try std.testing.expectEqual(@as(usize, info.min_size), result.child.offset);
        switch (format) {
            12, 13 => {
                try std.testing.expectApproxEqAbs(@as(f32, 2), result.affine.xx, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 3), result.affine.yy, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 40), result.affine.dx, 0.0001);
            },
            14, 15 => {
                try std.testing.expectApproxEqAbs(@as(f32, 40), result.affine.dx, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 50), result.affine.dy, 0.0001);
            },
            16...23 => try std.testing.expectApproxEqAbs(@as(f32, 0.5), result.affine.xx, 0.0001),
            24...27 => {
                try std.testing.expectApproxEqAbs(@as(f32, 0), result.affine.xx, 0.0001);
                try std.testing.expectApproxEqAbs(@as(f32, 1), result.affine.yx, 0.0001);
            },
            28...31 => try std.testing.expectApproxEqAbs(@as(f32, -1), result.affine.xy, 0.0001),
            else => unreachable,
        }
        if ((format & 1) != 0) {
            const varied = try colr_read.transform(font.data, colrV1Table(font.colr.?), 0, varied_context);
            try std.testing.expect(!std.meta.eql(result.affine, varied.affine));
        }
    }
}

fn readU24At(data: []const u8, offset: usize) FontError!u32 {
    if (offset + 3 > data.len) return error.BadSfnt;
    return (@as(u32, data[offset]) << 16) | (@as(u32, data[offset + 1]) << 8) | data[offset + 2];
}

fn validateVariationCoordinates(axes: []const VariationAxis, coordinates: []const VariationCoordinate) FontError!void {
    for (coordinates, 0..) |coordinate, coordinate_index| {
        // Variation coordinate tags are a public caller contract rather than an
        // OpenType table field. Reject duplicates and unknown tags up front so
        // shaping callers cannot accidentally depend on first-match ordering or
        // silently drop a misspelled axis such as `WGHT` instead of `wght`.
        if (!std.math.isFinite(coordinate.value)) return error.BadSfnt;
        if (variationAxisIndex(axes, coordinate.tag) == null) return error.BadSfnt;
        for (coordinates[0..coordinate_index]) |previous| {
            if (std.mem.eql(u8, &previous.tag, &coordinate.tag)) return error.BadSfnt;
        }
    }
}

fn validateNormalizedVariationCoordinate(value: f32) FontError!void {
    if (!std.math.isFinite(value)) return error.BadSfnt;
    if (value < -1.0 or value > 1.0) return error.BadSfnt;
}

fn validateNormalizedVariationCoordinateSlice(values: []const f32) FontError!void {
    for (values) |value| try validateNormalizedVariationCoordinate(value);
}

fn normalizedVariationCoordinatesAreDefault(values: []const f32) bool {
    for (values) |value| {
        if (value != 0) return false;
    }
    return true;
}

fn variationAxisIndex(axes: []const VariationAxis, tag: [4]u8) ?usize {
    for (axes, 0..) |axis, index| {
        if (std.mem.eql(u8, &axis.tag, &tag)) return index;
    }
    return null;
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

test "GDEF MarkGlyphSetsDef handles duplicate and unsorted coverage glyphs" {
    const allocator = std.testing.allocator;
    var bytes: [28]u8 = .{0} ** 28;
    writeU16Test(&bytes, 0, 1); // MarkGlyphSetsDef format.
    writeU16Test(&bytes, 2, 1);
    writeU32Test(&bytes, 4, 8);

    writeU16Test(&bytes, 8, 1); // Coverage format 1.
    writeU16Test(&bytes, 10, 3);
    writeU16Test(&bytes, 12, 5);
    writeU16Test(&bytes, 14, 5); // Duplicate glyphs appear in real GDEF mark-filtering sets.
    writeU16Test(&bytes, 16, 9);
    const sets = try readMarkGlyphSetsDef(allocator, &bytes, 0);
    defer freeMarkFilteringSets(allocator, sets);
    try std.testing.expectEqualSlices(glyph_mod.GlyphId, &.{ 5, 9 }, sets[0]);

    writeU16Test(&bytes, 12, 9);
    writeU16Test(&bytes, 14, 5); // Genuinely unsorted; still reject.
    writeU16Test(&bytes, 16, 10);
    try std.testing.expectError(error.BadSfnt, readMarkGlyphSetsDef(allocator, &bytes, 0));

    writeU16Test(&bytes, 8, 2); // Coverage format 2.
    writeU16Test(&bytes, 10, 2);
    writeU16Test(&bytes, 12, 5);
    writeU16Test(&bytes, 14, 9);
    writeU16Test(&bytes, 16, 0);
    writeU16Test(&bytes, 18, 9); // Overlaps the previous inclusive range.
    writeU16Test(&bytes, 20, 11);
    writeU16Test(&bytes, 22, 5);
    try std.testing.expectError(error.BadSfnt, readMarkGlyphSetsDef(allocator, &bytes, 0));
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

test "GDEF dense ClassDef reader fills glyph-indexed metadata" {
    var format1: [12]u8 = .{0} ** 12;
    writeU16Test(&format1, 0, 1); // ClassDef format 1.
    writeU16Test(&format1, 2, 2); // startGlyphID.
    writeU16Test(&format1, 4, 3); // glyphCount.
    writeU16Test(&format1, 6, @intFromEnum(GlyphClass.base));
    writeU16Test(&format1, 8, @intFromEnum(GlyphClass.mark));
    writeU16Test(&format1, 10, @intFromEnum(GlyphClass.component));

    var dense1: [8]u16 = undefined;
    try readClassDefDense(&format1, 0, @intCast(dense1.len), dense1[0..], true);
    try std.testing.expectEqualSlices(u16, &.{
        0,
        0,
        @intFromEnum(GlyphClass.base),
        @intFromEnum(GlyphClass.mark),
        @intFromEnum(GlyphClass.component),
        0,
        0,
        0,
    }, &dense1);

    var format2: [16]u8 = .{0} ** 16;
    writeU16Test(&format2, 0, 2); // ClassDef format 2.
    writeU16Test(&format2, 2, 2); // Two ranges.
    writeU16Test(&format2, 4, 1);
    writeU16Test(&format2, 6, 3);
    writeU16Test(&format2, 8, @intFromEnum(GlyphClass.ligature));
    writeU16Test(&format2, 10, 5);
    writeU16Test(&format2, 12, 5);
    writeU16Test(&format2, 14, 7); // MarkAttachClassDef values are font-defined, not GlyphClass enum values.

    var dense2: [8]u16 = undefined;
    try readClassDefDense(&format2, 0, @intCast(dense2.len), dense2[0..], false);
    try std.testing.expectEqualSlices(u16, &.{ 0, 2, 2, 2, 0, 7, 0, 0 }, &dense2);

    try std.testing.expectError(error.BadSfnt, readClassDefDense(&format2, 0, @intCast(dense2.len), dense2[0..], true));
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

    var class_value_past_enum = valid_classdef;
    writeU16Test(&class_value_past_enum, 18, 5); // GlyphClassDef has only classes 0..4.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&class_value_past_enum, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = class_value_past_enum.len }, 4));

    var format2_class_value_past_enum: [22]u8 = .{0} ** 22;
    writeU16Test(&format2_class_value_past_enum, 0, 1); // GDEF major.
    writeU16Test(&format2_class_value_past_enum, 2, 0);
    writeU16Test(&format2_class_value_past_enum, 4, 12);
    writeU16Test(&format2_class_value_past_enum, 12, 2); // ClassDef format 2.
    writeU16Test(&format2_class_value_past_enum, 14, 1);
    writeU16Test(&format2_class_value_past_enum, 16, 2);
    writeU16Test(&format2_class_value_past_enum, 18, 3);
    writeU16Test(&format2_class_value_past_enum, 20, 5);
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&format2_class_value_past_enum, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = format2_class_value_past_enum.len }, 4));

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

test "GDEF parse validation walks AttachList child tables" {
    var valid_attach: [30]u8 = .{0} ** 30;
    writeU16Test(&valid_attach, 0, 1); // GDEF major.
    writeU16Test(&valid_attach, 2, 0);
    writeU16Test(&valid_attach, 6, 12); // AttachList follows the GDEF 1.0 header.

    writeU16Test(&valid_attach, 12, 6); // Coverage offset, relative to AttachList.
    writeU16Test(&valid_attach, 14, 1); // One covered glyph and one AttachPoint.
    writeU16Test(&valid_attach, 16, 12); // AttachPoint offset, relative to AttachList.
    writeU16Test(&valid_attach, 18, 1); // Coverage format 1.
    writeU16Test(&valid_attach, 20, 1);
    writeU16Test(&valid_attach, 22, 3);
    writeU16Test(&valid_attach, 24, 2); // AttachPoint: two sorted point indices.
    writeU16Test(&valid_attach, 26, 4);
    writeU16Test(&valid_attach, 28, 7);
    try validateGdefTable(&valid_attach, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = valid_attach.len }, 4);

    var attach_offset_aliases_header = valid_attach;
    writeU16Test(&attach_offset_aliases_header, 16, 2); // Would reinterpret AttachList glyphCount as pointCount.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&attach_offset_aliases_header, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = attach_offset_aliases_header.len }, 4));

    var unsorted_points = valid_attach;
    writeU16Test(&unsorted_points, 28, 4); // Duplicate/decreasing point order is not canonical.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&unsorted_points, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = unsorted_points.len }, 4));

    var coverage_past_maxp = valid_attach;
    writeU16Test(&coverage_past_maxp, 22, 4); // Invalid for maxp.numGlyphs == 4.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&coverage_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = coverage_past_maxp.len }, 4));

    var mismatched_coverage: [34]u8 = .{0} ** 34;
    writeU16Test(&mismatched_coverage, 0, 1);
    writeU16Test(&mismatched_coverage, 2, 0);
    writeU16Test(&mismatched_coverage, 6, 12);
    writeU16Test(&mismatched_coverage, 12, 8); // Coverage starts after two AttachPoint offsets.
    writeU16Test(&mismatched_coverage, 14, 2); // Two AttachPoint offsets advertised.
    writeU16Test(&mismatched_coverage, 16, 14);
    writeU16Test(&mismatched_coverage, 18, 18);
    writeU16Test(&mismatched_coverage, 20, 1); // Coverage format 1, but only one glyph.
    writeU16Test(&mismatched_coverage, 22, 1);
    writeU16Test(&mismatched_coverage, 24, 1);
    writeU16Test(&mismatched_coverage, 26, 1);
    writeU16Test(&mismatched_coverage, 28, 4);
    writeU16Test(&mismatched_coverage, 30, 1);
    writeU16Test(&mismatched_coverage, 32, 7);
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&mismatched_coverage, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = mismatched_coverage.len }, 4));
}

test "GDEF parse validation walks LigCaretList child tables" {
    var valid_lig_caret: [42]u8 = .{0} ** 42;
    writeU16Test(&valid_lig_caret, 0, 1); // GDEF major.
    writeU16Test(&valid_lig_caret, 2, 0);
    writeU16Test(&valid_lig_caret, 8, 12); // LigCaretList follows the GDEF 1.0 header.

    writeU16Test(&valid_lig_caret, 12, 6); // Coverage offset, relative to LigCaretList.
    writeU16Test(&valid_lig_caret, 14, 1); // One covered ligature glyph and one LigGlyph.
    writeU16Test(&valid_lig_caret, 16, 12); // LigGlyph offset, relative to LigCaretList.
    writeU16Test(&valid_lig_caret, 18, 1); // Coverage format 1.
    writeU16Test(&valid_lig_caret, 20, 1);
    writeU16Test(&valid_lig_caret, 22, 3);
    writeU16Test(&valid_lig_caret, 24, 1); // LigGlyph: one CaretValue offset.
    writeU16Test(&valid_lig_caret, 26, 4);
    writeU16Test(&valid_lig_caret, 28, 1); // CaretValue format 1.
    writeI16Test(&valid_lig_caret, 30, 120);
    try validateGdefTable(&valid_lig_caret, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = valid_lig_caret.len }, 4);

    var lig_glyph_offset_aliases_header = valid_lig_caret;
    writeU16Test(&lig_glyph_offset_aliases_header, 16, 2); // Would reinterpret LigGlyphCount as CaretCount.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&lig_glyph_offset_aliases_header, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = lig_glyph_offset_aliases_header.len }, 4));

    var caret_offset_aliases_array = valid_lig_caret;
    writeU16Test(&caret_offset_aliases_array, 26, 2); // Would reinterpret the CaretValue offset array as a CaretValue.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&caret_offset_aliases_array, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = caret_offset_aliases_array.len }, 4));

    var coverage_past_maxp = valid_lig_caret;
    writeU16Test(&coverage_past_maxp, 22, 4); // Invalid for maxp.numGlyphs == 4.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&coverage_past_maxp, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = coverage_past_maxp.len }, 4));

    var mismatched_coverage = valid_lig_caret;
    writeU16Test(&mismatched_coverage, 20, 0); // Coverage count no longer matches LigGlyphCount.
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&mismatched_coverage, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = mismatched_coverage.len }, 4));

    var format3_caret = valid_lig_caret;
    writeU16Test(&format3_caret, 28, 3); // CaretValue format 3.
    writeI16Test(&format3_caret, 30, 120);
    writeU16Test(&format3_caret, 32, 6); // Device table offset, relative to CaretValue.
    writeU16Test(&format3_caret, 34, 12); // Device StartSize.
    writeU16Test(&format3_caret, 36, 13); // Device EndSize.
    writeU16Test(&format3_caret, 38, 1); // Two 2-bit deltas need one uint16 word.
    writeU16Test(&format3_caret, 40, 0);
    try validateGdefTable(&format3_caret, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = format3_caret.len }, 4);

    var truncated_device = format3_caret;
    try std.testing.expectError(error.BadSfnt, validateGdefTable(&truncated_device, .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = truncated_device.len - 1 }, 4));
}

test "GDEF v1.3 validates ItemVariationStore payload" {
    const fvar_len: usize = 36;
    const gdef_offset: usize = fvar_len;
    const item_store_offset: usize = 20;
    var bytes: [fvar_len + item_store_offset + 34]u8 = .{0} ** (fvar_len + item_store_offset + 34);

    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16); // axesArrayOffset.
    writeU16Test(&bytes, 6, 2); // countSizePairs.
    writeU16Test(&bytes, 8, 1); // one design axis.
    writeU16Test(&bytes, 10, 20); // axisSize.
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);

    writeU16Test(&bytes, gdef_offset + 0, 1); // GDEF major.
    writeU16Test(&bytes, gdef_offset + 2, 3); // GDEF 1.3 adds ItemVariationStoreOffset.
    writeU32Test(&bytes, gdef_offset + 14, item_store_offset);
    writeItemVariationStoreWithOneItem(&bytes, gdef_offset + item_store_offset);

    const fvar = TableRecord{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = fvar_len };
    const gdef = TableRecord{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = gdef_offset, .length = bytes.len - gdef_offset };
    try validateGdefTableWithVariationData(&bytes, gdef, 4, fvar);

    // A GDEF ItemVariationStore is meaningful only in the fvar variation-axis
    // coordinate system. Keeping that dependency explicit prevents a table that
    // merely fits in the GDEF byte range from being accepted as usable
    // variation data.
    try std.testing.expectError(error.BadSfnt, validateGdefTableWithVariationData(&bytes, gdef, 4, null));

    var bad_store_format = bytes;
    writeU16Test(&bad_store_format, gdef_offset + item_store_offset, 2);
    try std.testing.expectError(error.BadSfnt, validateGdefTableWithVariationData(&bad_store_format, gdef, 4, fvar));

    var axis_mismatch = bytes;
    writeU16Test(&axis_mismatch, gdef_offset + item_store_offset + 12, 2); // VariationRegionList axisCount.
    try std.testing.expectError(error.BadSfnt, validateGdefTableWithVariationData(&axis_mismatch, gdef, 4, fvar));
}

test "GDEF lazy glyph class rejects mutated class values outside enum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const gdef_offset: usize = @intCast(try sfntTableOffset(bytes, "GDEF"));
    try std.testing.expectEqual(GlyphClass.base, try font.glyphClass(1));

    // The parsed Font keeps a borrowed GDEF table. Rechecking the class value
    // before enum conversion prevents post-parse mutations from manufacturing
    // undeclared glyph classes while preserving arbitrary MarkAttachClassDef
    // group numbers.
    writeU16Test(bytes, gdef_offset + 20, 5);
    try std.testing.expectError(error.BadSfnt, font.glyphClass(1));

    writeU16Test(bytes, gdef_offset + 20, @intFromEnum(GlyphClass.base));
    try updateSfntTableChecksum(bytes, "GDEF");
    try std.testing.expectEqual(@as(u16, 7), try font.markAttachClass(3));
}

test "GDEF lazy class APIs revalidate borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(GlyphClass.base, try font.glyphClass(1));

    const gdef_offset: usize = @intCast(try sfntTableOffset(bytes, "GDEF"));
    // Keep the ClassDef value inside the valid GDEF enum while changing the
    // borrowed table after parse. The lazy public API must reject the table
    // because it no longer matches the SFNT checksum that Font.parse accepted.
    writeU16Test(bytes, gdef_offset + 20, @intFromEnum(GlyphClass.ligature));
    try std.testing.expectError(error.BadSfnt, font.glyphClass(1));
}

test "GDEF lazy class APIs revalidate child offsets after borrowed bytes mutate" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildGdefClassTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const gdef_offset: usize = @intCast(try sfntTableOffset(bytes, "GDEF"));
        writeU16Test(bytes, gdef_offset + 4, 6); // GlyphClassDef now points into the GDEF header.
        writeU16Test(bytes, gdef_offset + 6, 1); // Malicious header bytes decode as ClassDef format 1.
        writeU16Test(bytes, gdef_offset + 8, 0); // startGlyphID.
        writeU16Test(bytes, gdef_offset + 10, 1); // glyphCount.
        writeU16Test(bytes, gdef_offset + 12, @intFromEnum(GlyphClass.mark));

        try std.testing.expectError(error.BadSfnt, font.glyphClass(0));
    }

    {
        const bytes = try test_font.buildGdefClassTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const gdef_offset: usize = @intCast(try sfntTableOffset(bytes, "GDEF"));
        writeU16Test(bytes, gdef_offset + 10, 4); // MarkAttachClassDef now aliases the GDEF header.
        writeU16Test(bytes, gdef_offset + 4, 1); // Header bytes at offset 4 form ClassDef format 1.
        writeU16Test(bytes, gdef_offset + 6, 3); // startGlyphID.
        writeU16Test(bytes, gdef_offset + 8, 1); // glyphCount.

        try std.testing.expectError(error.BadSfnt, font.markAttachClass(3));
    }
}

test "GDEF lazy mark filtering sets revalidate glyph ids after borrowed bytes mutate" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildGdefClassTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const gdef_offset: usize = @intCast(try sfntTableOffset(bytes, "GDEF"));
    writeU16Test(bytes, gdef_offset + 2, 2); // Enable MarkGlyphSetsDef in the lazy GDEF reader.
    writeU16Test(bytes, gdef_offset + 12, 14); // Reuse the original class payload as a mark-set table.
    writeU16Test(bytes, gdef_offset + 14, 1); // MarkGlyphSetsDef format 1.
    writeU16Test(bytes, gdef_offset + 16, 1);
    writeU32Test(bytes, gdef_offset + 18, 10); // Coverage follows the one Offset32 entry.
    writeU16Test(bytes, gdef_offset + 24, 1); // Coverage format 1.
    writeU16Test(bytes, gdef_offset + 26, 1);
    writeU16Test(bytes, gdef_offset + 28, 5); // maxp.numGlyphs is still 5, so glyph id 5 is invalid.

    try std.testing.expectError(error.BadSfnt, font.markFilteringSets(allocator));
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

test "kern public API rejects glyph ids outside maxp count" {
    var data: [24]u8 = .{0} ** 24;
    writeU16Test(&data, 0, 0);
    writeU16Test(&data, 2, 1);
    writeKernFormat0Subtable(&data, 4, 0x0001, 1, 1, -40);

    const font = kernOnlyFont(&data);
    try std.testing.expectError(error.InvalidGlyph, font.kerning(2, 1));
    try std.testing.expectError(error.InvalidGlyph, font.kerning(1, 2));
}

test "kern public API revalidates borrowed pair arrays" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(i16, -40), try font.kerning(1, 1));

    const kern_offset: usize = @intCast(try sfntTableOffset(bytes, "kern"));
    writeU16Test(bytes, kern_offset + 4 + 6 + 8 + 2, 2); // Mutate right glyph outside maxp.numGlyphs.
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
}

test "kern public API revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(i16, -40), try font.kerning(1, 1));

    const kern_offset: usize = @intCast(try sfntTableOffset(bytes, "kern"));
    // Keep the pair array sorted and glyph IDs in range while changing only
    // the kerning value. The lazy public API must reject that borrowed payload
    // because it no longer matches the SFNT checksum validated by Font.parse.
    writeI16Test(bytes, kern_offset + 22, -20);
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
}

test "legacy kern subtables must use version zero" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        var kern: [24]u8 = .{0} ** 24;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);
        writeU16Test(&kern, 4, 1); // Legacy subtable version must be zero.

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var kern: [24]u8 = .{0} ** 24;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const kern_offset: usize = @intCast(try sfntTableOffset(bytes, "kern"));
        writeU16Test(bytes, kern_offset + 4, 2);
        try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
    }
}

test "kern subtable sequence must consume declared payload" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        var kern: [25]u8 = .{0} ** 25;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

        const font = kernOnlyFont(&kern);
        try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
    }

    {
        var kern: [32]u8 = .{0} ** 32;
        writeU32Test(&kern, 0, 0x00010000);
        writeU32Test(&kern, 4, 1);
        writeAppleKernFormat0Subtable(&kern, 8, 0x0000, 1, 1, -35);

        const font = kernOnlyFont(&kern);
        try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
    }

    {
        var kern: [28]u8 = .{0} ** 28;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);
        // SFNT table lengths exclude padding. Bytes that remain after the
        // counted subtable sequence are therefore ambiguous orphan payload, not
        // ignorable alignment data.
        writeU32Test(&kern, 24, 0xdead_beef);

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var kern: [24]u8 = .{0} ** 24;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(i16, -40), try font.kerning(1, 1));

        const kern_offset: usize = @intCast(try sfntTableOffset(bytes, "kern"));
        writeU16Test(bytes, kern_offset + 2, 0); // Count no subtables while leaving the original payload bytes reachable.
        try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
    }
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

test "Apple kern v1 format 2 applies class kerning" {
    var data: [58]u8 = .{0} ** 58;
    writeU32Test(&data, 0, 0x00010000);
    writeU32Test(&data, 4, 1);

    writeU32Test(&data, 8, 50); // Subtable length.
    writeU16Test(&data, 12, 0x0002); // Horizontal format 2.
    writeU16Test(&data, 14, 0); // tupleIndex.
    writeU16Test(&data, 16, 4); // rowWidth.
    writeU16Test(&data, 18, 24); // left class table offset.
    writeU16Test(&data, 20, 34); // right class table offset.
    writeU16Test(&data, 22, 16); // kerning array offset.
    writeI16Test(&data, 26, -40); // array[16 + 2].

    writeU16Test(&data, 32, 0); // left first glyph.
    writeU16Test(&data, 34, 1); // left glyph count.
    writeU16Test(&data, 36, 16); // left class row offset.

    writeU16Test(&data, 42, 1); // right first glyph.
    writeU16Test(&data, 44, 1); // right glyph count.
    writeU16Test(&data, 46, 2); // right class column offset.

    const font = kernOnlyFont(&data);
    try std.testing.expectEqual(@as(i16, -40), try font.kerning(0, 1));
    try std.testing.expectEqual(@as(i16, 0), try font.kerning(1, 1));
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

test "kern format 0 search headers are validated at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        var kern: [24]u8 = .{0} ** 24;
        writeU16Test(&kern, 0, 0);
        writeU16Test(&kern, 2, 1);
        writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);
        writeU16Test(&kern, 4 + 6 + 2, 12); // searchRange should be one 6-byte pair record.

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var kern: [31]u8 = .{0} ** 31;
        writeU32Test(&kern, 0, 0x00010000);
        writeU32Test(&kern, 4, 1);
        writeAppleKernFormat0Subtable(&kern, 8, 0x0000, 1, 1, -35);
        writeU16Test(&kern, 8 + 8 + 6, 2); // rangeShift should be zero for one pair.

        const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
        defer allocator.free(bytes);
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "kern lazy API revalidates borrowed format 0 search headers" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var kern: [24]u8 = .{0} ** 24;
    writeU16Test(&kern, 0, 0);
    writeU16Test(&kern, 2, 1);
    writeKernFormat0Subtable(&kern, 4, 0x0001, 1, 1, -40);

    const bytes = try test_font.buildMinimalTtfWithKern(allocator, &kern);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(i16, -40), try font.kerning(1, 1));

    const kern_offset: usize = @intCast(try sfntTableOffset(bytes, "kern"));
    writeU16Test(bytes, kern_offset + 4 + 6 + 4, 1); // entrySelector should be zero for one pair.
    try std.testing.expectError(error.BadSfnt, font.kerning(1, 1));
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

test "sbix public bitmap APIs revalidate borrowed strike offsets" {
    var bytes: [40]u8 = .{0} ** 40;
    writeU16Test(&bytes, 0, 1); // sbix version
    writeU32Test(&bytes, 4, 1); // one strike
    writeU32Test(&bytes, 8, 12); // strike data starts after the strike-offset array
    writeU16Test(&bytes, 12, 16); // ppem
    writeU16Test(&bytes, 14, 72); // ppi
    writeU32Test(&bytes, 16, 16); // glyph 0 start, relative to the strike
    writeU32Test(&bytes, 20, 16); // glyph 1 start; both glyphs are empty
    writeU32Test(&bytes, 24, 16); // terminal boundary

    const font = sbixOnlyFont(&bytes);
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(16));
    const strikes = try font.bitmapStrikes(std.testing.allocator);
    defer std.testing.allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(@as(?BitmapGlyphPng, null), try font.bitmapGlyphPng(0, 16));

    // Mutate an unrequested glyph boundary after constructing the borrowed
    // Font. Both public APIs must reject the whole sbix strike rather than
    // returning metadata or glyph 0 results from a now-corrupt table.
    writeU32Test(&bytes, 24, 12);
    try std.testing.expectError(error.BadSfnt, font.bitmapStrikes(std.testing.allocator));
    try std.testing.expectError(error.BadSfnt, font.bestBitmapStrikePpem(16));
    try std.testing.expectError(error.BadSfnt, font.bitmapGlyphPng(0, 16));
}

test "sbix public bitmap APIs revalidate borrowed table checksum" {
    var bytes: [40]u8 = .{0} ** 40;
    writeU16Test(&bytes, 0, 1); // sbix version.
    writeU32Test(&bytes, 4, 1); // one strike.
    writeU32Test(&bytes, 8, 12);
    writeU16Test(&bytes, 12, 16); // ppem.
    writeU16Test(&bytes, 14, 72); // ppi.
    writeU32Test(&bytes, 16, 16);
    writeU32Test(&bytes, 20, 16);
    writeU32Test(&bytes, 24, 16);

    const font = sbixOnlyFont(&bytes);
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(16));

    // Keep strike offsets and glyph payloads valid while changing strike
    // metadata after construction. Lazy bitmap APIs must reject the borrowed
    // sbix table because its SFNT checksum no longer matches.
    writeU16Test(&bytes, 12, 17);
    try std.testing.expectError(error.BadSfnt, font.bestBitmapStrikePpem(16));
    try std.testing.expectError(error.BadSfnt, font.bitmapGlyphPng(0, 16));
}

test "public bitmap APIs reject non-finite and non-positive request sizes" {
    var bytes: [40]u8 = .{0} ** 40;
    writeU16Test(&bytes, 0, 1); // sbix version
    writeU32Test(&bytes, 4, 1); // one strike
    writeU32Test(&bytes, 8, 12); // strike data starts after the strike-offset array
    writeU16Test(&bytes, 12, 16); // ppem
    writeU16Test(&bytes, 14, 72); // ppi
    writeU32Test(&bytes, 16, 16); // glyph 0 start, relative to the strike
    writeU32Test(&bytes, 20, 16); // glyph 1 start; both glyphs are empty
    writeU32Test(&bytes, 24, 16); // terminal boundary

    const font = sbixOnlyFont(&bytes);
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(16));
    try std.testing.expectEqual(@as(?BitmapGlyphPng, null), try font.bitmapGlyphPng(0, 16));

    // Bitmap strike selection is a public API input contract, independent of
    // whether the font ultimately returns a PNG payload. Validate it before
    // parsing borrowed bitmap tables so nonsensical sizes cannot masquerade as
    // a cache miss or pick a strike through NaN distance comparisons.
    try std.testing.expectError(error.InvalidBitmapSize, font.bestBitmapStrikePpem(0));
    try std.testing.expectError(error.InvalidBitmapSize, font.bestBitmapStrikePpem(-1));
    try std.testing.expectError(error.InvalidBitmapSize, font.bestBitmapStrikePpem(std.math.inf(f32)));
    try std.testing.expectError(error.InvalidBitmapSize, font.bestBitmapStrikePpem(std.math.nan(f32)));
    try std.testing.expectError(error.InvalidBitmapSize, font.bitmapGlyphPng(0, 0));
    try std.testing.expectError(error.InvalidBitmapSize, font.bitmapGlyphPng(0, std.math.nan(f32)));
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

test "CBLC public bitmap APIs revalidate borrowed CBDT payloads" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const strikes = try font.bitmapStrikes(allocator);
    defer allocator.free(strikes);
    try std.testing.expectEqual(@as(usize, 1), strikes.len);
    try std.testing.expectEqual(@as(?u16, 16), try font.bestBitmapStrikePpem(16));
    try std.testing.expect((try font.bitmapGlyphPng(1, 16)) != null);

    const cbdt_offset = try sfntTableOffset(bytes, "CBDT");
    writeU32Test(bytes, cbdt_offset + 9, 0xffff_ffff);
    try std.testing.expectError(error.BadSfnt, font.bitmapStrikes(allocator));
    try std.testing.expectError(error.BadSfnt, font.bestBitmapStrikePpem(16));
    try std.testing.expectError(error.BadSfnt, font.bitmapGlyphPng(1, 16));
    try std.testing.expectError(error.BadSfnt, font.bitmapGlyphInfo(1, 16));
}

test "CBDT embedded PNG payloads require a valid PNG datastream" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildCbdtPngTtf(allocator);
    defer allocator.free(bytes);

    const cbdt_offset = try sfntTableOffset(bytes, "CBDT");
    const png_offset = cbdt_offset + 4 + 5 + 4;
    bytes[png_offset] = 0; // The previous loose check of bytes 1..3 would still see "PNG".
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

    var format12_trailing: [30]u8 = .{0} ** 30;
    writeU16Test(&format12_trailing, 0, 12);
    writeU32Test(&format12_trailing, 4, format12_trailing.len);
    writeU32Test(&format12_trailing, 12, 1);
    writeU32Test(&format12_trailing, 16, 'A');
    writeU32Test(&format12_trailing, 20, 'A');
    writeU32Test(&format12_trailing, 24, 9);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat12(&format12_trailing, 0, format12_trailing.len, 'A'));

    var format13: [28]u8 = .{0} ** 28;
    writeU16Test(&format13, 0, 13);
    writeU32Test(&format13, 4, 16); // Declared length excludes the group below.
    writeU32Test(&format13, 12, 1);
    writeU32Test(&format13, 16, 0);
    writeU32Test(&format13, 20, 0x10ffff);
    writeU32Test(&format13, 24, 3);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat13(&format13, 0, 16, 'A'));
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 3), try glyphIndexFormat13(&format13, 0, 28, 0x1f600));

    var format13_trailing: [30]u8 = .{0} ** 30;
    writeU16Test(&format13_trailing, 0, 13);
    writeU32Test(&format13_trailing, 4, format13_trailing.len);
    writeU32Test(&format13_trailing, 12, 1);
    writeU32Test(&format13_trailing, 16, 0);
    writeU32Test(&format13_trailing, 20, 0x10ffff);
    writeU32Test(&format13_trailing, 24, 3);
    try std.testing.expectError(error.BadSfnt, glyphIndexFormat13(&format13_trailing, 0, format13_trailing.len, 0x1f600));
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

test "cmap format 14 SFNT fixture rejects aliased variation payloads" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
    const variation_offset: usize = @intCast(try bin.readU32At(bytes, cmap_offset + 16));
    // The non-default UVS array is independently owned variable-length data.
    // Pointing it at the default UVS array would make two incompatible payload
    // formats share bytes; full SFNT parsing must reject that alias, not just
    // the isolated format-14 helper tests above.
    writeU32Test(bytes, cmap_offset + variation_offset + 17, 21);
    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "cmap format 14 public lookup revalidates borrowed SFNT bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(?glyph_mod.GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));

    const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
    const variation_offset: usize = @intCast(try bin.readU32At(bytes, cmap_offset + 16));
    // Font deliberately borrows caller-owned bytes. If the caller mutates that
    // buffer after parse, the public variation lookup path must not return a
    // glyph id that is outside maxp.numGlyphs just because the original parse
    // saw a valid format-14 table.
    writeU16Test(bytes, cmap_offset + variation_offset + 36, 4);
    try std.testing.expectError(error.BadSfnt, font.variationGlyphIndex('A', 0xfe0f));
    try std.testing.expectError(error.BadSfnt, font.glyphIndexWithVariation('A', 0xfe0f));
}

// Format-14 UVS lookup uses cached cmap directory entries because it is reached
// through a separate public API from ordinary glyphIndex(). Keep that lazy path
// under the same cmap ownership contract as scalar lookup: the cached subtable
// length must still match the current bytes and still fit inside the cmap table.
test "cmap format 14 public lookup revalidates cached subtable length" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(?glyph_mod.GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));

    const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
    const cmap_length: usize = @intCast(try sfntTableLength(bytes, "cmap"));
    const variation_offset: usize = @intCast(try bin.readU32At(bytes, cmap_offset + 16));

    writeU32Test(bytes, cmap_offset + variation_offset + 2, @intCast(cmap_length - variation_offset + 1));
    try std.testing.expectError(error.BadSfnt, font.variationGlyphIndex('A', 0xfe0f));
    try std.testing.expectError(error.BadSfnt, font.glyphIndexWithVariation('A', 0xfe0f));
}

test "cmap public lookup revalidates cached encoding record offsets" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildSingleCodepointTtf(allocator, 'A');
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), try font.glyphIndex('A'));

        const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
        const format4_offset = try bin.readU32At(bytes, cmap_offset + 8);
        // The cached CmapSubtable still points at the original format-4 bytes.
        // Mutating only the EncodingRecord offset must invalidate the public
        // lookup instead of letting it follow a stale child pointer.
        writeU32Test(bytes, cmap_offset + 8, format4_offset + 2);
        try std.testing.expectError(error.BadSfnt, font.glyphIndex('A'));
    }

    {
        const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(?glyph_mod.GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));

        const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
        const variation_offset = try bin.readU32At(bytes, cmap_offset + 16);
        writeU32Test(bytes, cmap_offset + 16, variation_offset + 2);
        try std.testing.expectError(error.BadSfnt, font.variationGlyphIndex('A', 0xfe0f));
        try std.testing.expectError(error.BadSfnt, font.glyphIndexWithVariation('A', 0xfe0f));
    }
}

test "cmap public lookup revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildSingleCodepointTtf(allocator, 'A');
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), try font.glyphIndex('A'));

        const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
        const format4_offset: usize = @intCast(try bin.readU32At(bytes, cmap_offset + 8));
        // Keep the cmap structurally valid and maxp-compatible while changing
        // U+0041 from glyph 1 to glyph 0. The lazy lookup should still reject
        // the borrowed table because its directory checksum no longer matches
        // the table map validated by Font.parse.
        writeI16Test(bytes, cmap_offset + format4_offset + 24, -@as(i16, @intCast('A')));
        try std.testing.expectError(error.BadSfnt, font.glyphIndex('A'));
    }

    {
        const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(?glyph_mod.GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));

        const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
        const variation_offset: usize = @intCast(try bin.readU32At(bytes, cmap_offset + 16));
        writeU16Test(bytes, cmap_offset + variation_offset + 36, 1);
        try std.testing.expectError(error.BadSfnt, font.variationGlyphIndex('A', 0xfe0f));
        try std.testing.expectError(error.BadSfnt, font.glyphIndexWithVariation('A', 0xfe0f));
    }
}

test "cmap public APIs reject invalid Unicode scalar inputs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariationSelectorCmapTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectError(error.InvalidCodepoint, font.glyphIndex(0xd800));
    try std.testing.expectError(error.InvalidCodepoint, font.variationGlyphIndex(0xd800, 0xfe0f));
    try std.testing.expectError(error.InvalidCodepoint, font.glyphIndexWithVariation(0xd800, 0xfe0f));
    try std.testing.expectError(error.InvalidCodepoint, font.variationGlyphIndex('A', 'x'));
    try std.testing.expectError(error.InvalidCodepoint, font.glyphIndexWithVariation('A', 'x'));

    try std.testing.expectEqual(@as(?glyph_mod.GlyphId, 3), try font.variationGlyphIndex('A', 0xfe0f));
}

test "cmap public glyph lookup revalidates borrowed glyph ids" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildSingleCodepointTtf(allocator, 'A');
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), try font.glyphIndex('A'));

    const cmap_offset: usize = @intCast(try sfntTableOffset(bytes, "cmap"));
    const format4_offset: usize = @intCast(try bin.readU32At(bytes, cmap_offset + 8));
    // The cached CmapSubtable still points at the same bytes, but this delta
    // now maps U+0041 to glyph id 2 while maxp.numGlyphs declares only ids 0
    // and 1. Public lookup must re-check the cmap/maxp contract before
    // returning the stale borrow's mutated glyph id.
    writeI16Test(bytes, cmap_offset + format4_offset + 24, @as(i16, 2) - @as(i16, @bitCast(@as(u16, 'A'))));
    try std.testing.expectError(error.BadSfnt, font.glyphIndex('A'));
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

test "Unicode cmap format 2 rejects surrogate character ranges" {
    var surrogate: [12 + 536]u8 = .{0} ** (12 + 536);
    writeU16Test(&surrogate, 2, 1); // One EncodingRecord.
    writeU16Test(&surrogate, 4, 0); // Unicode platform.
    writeU16Test(&surrogate, 6, 2); // Deprecated but Unicode scalar cmap.
    writeU32Test(&surrogate, 8, 12);
    const subtable = 12;
    writeU16Test(&surrogate, subtable, 2);
    writeU16Test(&surrogate, subtable + 2, 536);
    writeU16Test(&surrogate, subtable + 6 + 0xd8 * 2, 8); // High byte 0xd8 uses SubHeader[1].
    writeU16Test(&surrogate, subtable + 526, 0); // Low byte 0 starts at U+d800.
    writeU16Test(&surrogate, subtable + 528, 1);
    writeI16Test(&surrogate, subtable + 530, 0);
    writeU16Test(&surrogate, subtable + 532, 2);
    writeU16Test(&surrogate, subtable + 534, 1);

    const unicode_cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = surrogate.len,
    };
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(std.testing.allocator, &surrogate, unicode_cmap, 128));

    // Legacy Windows code-page format-2 subtables are byte-code maps rather
    // than Unicode scalar maps. Keep accepting the same byte range there so the
    // surrogate check does not reject non-Unicode East Asian production fonts.
    writeU16Test(&surrogate, 4, 3);
    writeU16Test(&surrogate, 6, 2);
    const legacy_subtables = try parseCmapSubtables(std.testing.allocator, &surrogate, unicode_cmap, 128);
    defer std.testing.allocator.free(legacy_subtables);
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

    var sentinel_maps_real_glyph = valid;
    writeCmapFormat4SegmentTest(&sentinel_maps_real_glyph, 1, 0xffff, 0xffff, 2, 0);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &sentinel_maps_real_glyph, cmap, 512));

    var sentinel_uses_glyph_array = valid;
    writeCmapFormat4SegmentTest(&sentinel_uses_glyph_array, 1, 0xffff, 0xffff, 0, 2);
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &sentinel_uses_glyph_array, cmap, 512));

    var bad_search_range = valid;
    writeU16Test(&bad_search_range, 20, 2);
    const bad_search_range_subtables = try parseCmapSubtables(allocator, &bad_search_range, cmap, 512);
    allocator.free(bad_search_range_subtables);

    var bad_entry_selector = valid;
    writeU16Test(&bad_entry_selector, 22, 0);
    const bad_entry_selector_subtables = try parseCmapSubtables(allocator, &bad_entry_selector, cmap, 512);
    allocator.free(bad_entry_selector_subtables);

    var bad_range_shift = valid;
    writeU16Test(&bad_range_shift, 24, 2);
    const bad_range_shift_subtables = try parseCmapSubtables(allocator, &bad_range_shift, cmap, 512);
    allocator.free(bad_range_shift_subtables);
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

        var unknown_unicode_encoding_format4 = full_repertoire_format4;
        writeU16Test(&unknown_unicode_encoding_format4, 4, 0);
        const unknown_unicode_encoding = try parseCmapSubtables(allocator, &unknown_unicode_encoding_format4, cmap, 512);
        allocator.free(unknown_unicode_encoding);

        // Unknown Unicode encoding IDs may carry ordinary maps, but must not
        // appropriate the registered variation-sequence or last-resort formats.
        var unknown_variation_format = unknown_unicode_encoding_format4;
        writeU16Test(&unknown_variation_format, 12, 14);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &unknown_variation_format, cmap, 512));
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
        const windows_format13_subtables = try parseCmapSubtables(allocator, &windows_format13, cmap, 512);
        allocator.free(windows_format13_subtables);
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

test "cmap language fields require zero outside Macintosh platform" {
    const allocator = std.testing.allocator;

    {
        const cmap: TableRecord = .{
            .tag = .{ 'c', 'm', 'a', 'p' },
            .checksum = 0,
            .offset = 0,
            .length = 274,
        };
        var format0: [274]u8 = .{0} ** 274;
        writeU16Test(&format0, 0, 0); // cmap version.
        writeU16Test(&format0, 2, 1);
        writeU16Test(&format0, 4, 0); // Unicode platform, deprecated default semantics.
        writeU16Test(&format0, 6, 0);
        writeU32Test(&format0, 8, 12);
        writeU16Test(&format0, 12, 0);
        writeU16Test(&format0, 14, 262);

        const subtables = try parseCmapSubtables(allocator, &format0, cmap, 2);
        allocator.free(subtables);

        var unicode_language = format0;
        writeU16Test(&unicode_language, 16, 1);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &unicode_language, cmap, 2));

        var mac_language = unicode_language;
        writeU16Test(&mac_language, 4, 1); // Macintosh platform is the only owner of the legacy language field.
        const mac_subtables = try parseCmapSubtables(allocator, &mac_language, cmap, 2);
        allocator.free(mac_subtables);
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

        const subtables = try parseCmapSubtables(allocator, &format12, cmap, 4);
        allocator.free(subtables);

        var nonzero_language = format12;
        writeU32Test(&nonzero_language, 20, 1);
        try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &nonzero_language, cmap, 4));
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

test "GSUB and GPOS public APIs reject out-of-range glyph runs" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph_mod.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.append(allocator, 3); // maxp.numGlyphs is 3; valid ids are 0, 1, and 2.

        try std.testing.expectError(error.InvalidGlyph, font.applyGsub(&glyphs, allocator));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph_mod.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.append(allocator, 2); // No GSUB table is present, but the caller contract still applies.

        try std.testing.expectError(error.InvalidGlyph, font.applyGsub(&glyphs, allocator));
    }

    {
        const bytes = try test_font.buildMinimalGposTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos_mod.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph_mod.GlyphId{2}; // maxp.numGlyphs is 2; valid ids are 0 and 1.

        try std.testing.expectError(error.InvalidGlyph, font.collectGposAdjustments(&glyphs, &adjustments, allocator));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos_mod.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph_mod.GlyphId{2}; // No GPOS table is present, but invalid run data is not "no positioning".

        try std.testing.expectError(error.InvalidGlyph, font.collectGposAdjustments(&glyphs, &adjustments, allocator));
    }
}

test "GSUB and GPOS public APIs revalidate borrowed table glyph references" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph_mod.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.appendSlice(allocator, &.{ 1, 2 });

        const gsub_offset = try sfntTableOffset(bytes, "GSUB");
        // Font.parse validated this borrowed GSUB table. Mutating the
        // ligature-result glyph after parse must not be deferred until the
        // substitution path writes a glyph ID that lacks metrics/outlines.
        writeU16Test(bytes, gsub_offset + 46, 3);
        try std.testing.expectError(error.BadSfnt, font.applyGsub(&glyphs, allocator));
    }

    {
        const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos_mod.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph_mod.GlyphId{1};

        const gpos_offset = try sfntTableOffset(bytes, "GPOS");
        // The changed coverage glyph is not in the caller's run. The public
        // positioning API still revalidates all supported lookup payloads so an
        // unrelated feature cannot leave corrupted borrowed bytes latent.
        writeU16Test(bytes, gpos_offset + 42, 2);
        try std.testing.expectError(error.BadSfnt, font.collectGposAdjustments(&glyphs, &adjustments, allocator));
    }
}

test "GSUB and GPOS public APIs revalidate borrowed table checksums" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalGsubTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var glyphs = std.ArrayList(glyph_mod.GlyphId).empty;
        defer glyphs.deinit(allocator);
        try glyphs.appendSlice(allocator, &.{ 1, 2 });

        const gsub_offset = try sfntTableOffset(bytes, "GSUB");
        // Keep the ligature result inside maxp while changing the borrowed
        // shaping payload after Font.parse. The public API must reject it
        // because GSUB's SFNT checksum no longer matches.
        writeU16Test(bytes, gsub_offset + 46, 1);
        try std.testing.expectError(error.BadSfnt, font.applyGsub(&glyphs, allocator));
    }

    {
        const bytes = try test_font.buildMinimalGposSingleTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var adjustments = std.ArrayList(gpos_mod.Adjustment).empty;
        defer adjustments.deinit(allocator);
        const glyphs = [_]glyph_mod.GlyphId{1};

        const gpos_offset = try sfntTableOffset(bytes, "GPOS");
        writeI16Test(bytes, gpos_offset + 32, 40);
        try std.testing.expectError(error.BadSfnt, font.collectGposAdjustments(&glyphs, &adjustments, allocator));
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

    var extra_bytes: [56]u8 = .{0} ** 56;
    writeCmapFormat12HeaderTest(&extra_bytes, extra_bytes.len - 12, 2);
    writeCmapGroupTest(&extra_bytes, 28, 0x100, 0x1ff, 4);
    writeCmapGroupTest(&extra_bytes, 40, 0x200, 0x200, 0x104);
    const extra_cmap: TableRecord = .{
        .tag = .{ 'c', 'm', 'a', 'p' },
        .checksum = 0,
        .offset = 0,
        .length = extra_bytes.len,
    };
    try std.testing.expectError(error.BadSfnt, parseCmapSubtables(allocator, &extra_bytes, extra_cmap, 512));
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

        writeU16Test(&format13, 4, 3); // Windows platform.
        writeU16Test(&format13, 6, 10); // Unicode full repertoire.
        writeU16Test(&format13, 14, 0);
        const subtables = try parseCmapSubtables(allocator, &format13, cmap, 4);
        defer allocator.free(subtables);
        try std.testing.expectEqual(@as(usize, 1), subtables.len);
        try std.testing.expectEqual(@as(u16, 13), subtables[0].format);
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

    try std.testing.expectError(error.InvalidGlyph, appendSimpleGlyph(&outline, null, &glyph_data, 2, Transform.identity(), null));
}

test "glyph outline API revalidates borrowed loca and glyf bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const loca_offset: usize = @intCast(try sfntTableOffset(bytes, "loca"));
        writeU16Test(bytes, loca_offset, 7); // Makes glyph 0's loca entry decrease before glyph 1.
        try std.testing.expectError(error.BadSfnt, font.glyphBounds(1));
        try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 1));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const glyf_offset: usize = @intCast(try sfntTableOffset(bytes, "glyf"));
        // Glyph 0 is not requested below. Mutating its borrowed bytes after
        // parsing must still be rejected before returning any glyph outline,
        // because the Font object no longer owns an immutable glyf snapshot.
        writeI16Test(bytes, glyf_offset, 1);
        try std.testing.expectError(error.BadSfnt, font.glyphBounds(1));
        try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 1));
    }
}

test "glyph outline API revalidates borrowed glyf checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var outline = try font.glyphOutline(allocator, 1);
    outline.deinit();

    const glyf_offset: usize = @intCast(try sfntTableOffset(bytes, "glyf"));
    const glyph_one = glyf_offset + 12;
    // Keep the simple glyph grammar valid while changing a borrowed bounding
    // box after parse. Lazy outline loading must reject the glyf table because
    // it no longer matches the SFNT checksum that Font.parse accepted.
    writeI16Test(bytes, glyph_one + 6, 600);
    try std.testing.expectError(error.BadSfnt, font.glyphBounds(1));
    try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 1));
}

test "simple glyf programs and coordinate streams validate at parse time" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        bytes[glyph_one + 14] = 0xb1; // Reserved flag bit 7 must not be set.
        try updateSfntTableChecksum(bytes, "glyf");

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        bytes[glyph_one + 15] = 0x61; // OVERLAP_SIMPLE is only valid on the first logical point.
        try updateSfntTableChecksum(bytes, "glyf");

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const glyf_offset = try sfntTableOffset(bytes, "glyf");
        const glyph_one = glyf_offset + 12;
        bytes[glyph_one + 14] = 0x79; // Repeats OVERLAP_SIMPLE onto points 1 and 2.
        bytes[glyph_one + 15] = 2;
        try updateSfntTableChecksum(bytes, "glyf");

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
    }

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

test "metric headers require positive line advance" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const hhea_offset: usize = @intCast(try sfntTableOffset(bytes, "hhea"));
        writeI16Test(bytes, hhea_offset + 4, 100);
        writeI16Test(bytes, hhea_offset + 6, 200);
        writeI16Test(bytes, hhea_offset + 8, 100); // ascender - descender + lineGap == 0.

        try std.testing.expectError(error.InvalidMetrics, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset: usize = @intCast(try sfntTableOffset(bytes, "vhea"));
        writeI16Test(bytes, vhea_offset + 4, -50);
        writeI16Test(bytes, vhea_offset + 6, 50);
        writeI16Test(bytes, vhea_offset + 8, 0);
        try updateSfntTableChecksum(bytes, "vhea");

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(0));
    }
}

test "metric headers reject trailing bytes" {
    var hhea: [37]u8 = .{0} ** 37;
    writeU32Test(&hhea, 0, 0x00010000);
    writeI16Test(&hhea, 4, 800);
    writeI16Test(&hhea, 6, -200);
    writeU16Test(&hhea, 34, 1);

    try validateMetricHeader(&hhea, .{
        .tag = .{ 'h', 'h', 'e', 'a' },
        .checksum = 0,
        .offset = 0,
        .length = 36,
    }, 0x00010000);
    try std.testing.expectError(error.BadSfnt, validateMetricHeader(&hhea, .{
        .tag = .{ 'h', 'h', 'e', 'a' },
        .checksum = 0,
        .offset = 0,
        .length = hhea.len,
    }, 0x00010000));

    var vhea: [37]u8 = .{0} ** 37;
    writeU32Test(&vhea, 0, 0x00011000);
    writeI16Test(&vhea, 4, 800);
    writeI16Test(&vhea, 6, -200);
    writeU16Test(&vhea, 34, 1);

    try validateVerticalMetricHeader(&vhea, .{
        .tag = .{ 'v', 'h', 'e', 'a' },
        .checksum = 0,
        .offset = 0,
        .length = 36,
    });
    try std.testing.expectError(error.BadSfnt, validateVerticalMetricHeader(&vhea, .{
        .tag = .{ 'v', 'h', 'e', 'a' },
        .checksum = 0,
        .offset = 0,
        .length = vhea.len,
    }));
}

test "horizontal metrics revalidate borrowed hhea bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = try font.horizontalMetrics(1);
    try std.testing.expectEqual(@as(u16, 800), initial.advance_width);

    const hhea_offset: usize = @intCast(try sfntTableOffset(bytes, "hhea"));
    writeU16Test(bytes, hhea_offset + 24, 1); // Reserved hhea fields must remain zero.
    try std.testing.expectError(error.InvalidMetrics, font.horizontalMetrics(1));

    writeU16Test(bytes, hhea_offset + 24, 0);
    writeI16Test(bytes, hhea_offset + 4, 100);
    writeI16Test(bytes, hhea_offset + 6, 200);
    writeI16Test(bytes, hhea_offset + 8, 100);
    try std.testing.expectError(error.InvalidMetrics, font.horizontalMetrics(1));

    writeI16Test(bytes, hhea_offset + 4, 800);
    writeI16Test(bytes, hhea_offset + 6, -200);
    writeI16Test(bytes, hhea_offset + 8, 0);
    writeU16Test(bytes, hhea_offset + 34, 1);
    try std.testing.expectError(error.InvalidMetrics, font.horizontalMetrics(1));
}

test "horizontal metrics revalidate borrowed hmtx checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = try font.horizontalMetrics(1);
    try std.testing.expectEqual(@as(u16, 800), initial.advance_width);

    const hmtx_offset: usize = @intCast(try sfntTableOffset(bytes, "hmtx"));
    // This mutation keeps the hmtx table length and metric count valid, and
    // without checksum revalidation the lazy API would return a new advance
    // width that Font.parse never authenticated.
    writeU16Test(bytes, hmtx_offset + 4, 700);
    try std.testing.expectError(error.BadSfnt, font.horizontalMetrics(1));
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
        try updateSfntTableChecksum(bytes, "vmtx");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(1));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset = try sfntTableOffset(bytes, "vhea");
        writeU16Test(bytes, vhea_offset + 34, 0);
        try updateSfntTableChecksum(bytes, "vhea");
        var zero_count = try Font.parse(allocator, bytes);
        defer zero_count.deinit();
        try std.testing.expectError(error.InvalidMetrics, zero_count.verticalMetrics(0));

        writeU16Test(bytes, vhea_offset + 34, 3); // More full vertical metrics than maxp.numGlyphs.
        try updateSfntTableChecksum(bytes, "vhea");
        var too_many = try Font.parse(allocator, bytes);
        defer too_many.deinit();
        try std.testing.expectError(error.InvalidMetrics, too_many.verticalMetrics(0));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableTag(bytes, "vmtx", "zzzz");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(0));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableTag(bytes, "vhea", "vhdz");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(0));
    }

    {
        const bytes = try test_font.buildVerticalMetricsTtf(allocator);
        defer allocator.free(bytes);
        const vhea_offset = try sfntTableOffset(bytes, "vhea");
        writeU16Test(bytes, vhea_offset + 24, 1); // Reserved fields must be zero.
        try updateSfntTableChecksum(bytes, "vhea");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(0));
    }
}

test "vertical metrics revalidate borrowed vmtx checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = (try font.verticalMetrics(0)) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 1000), initial.advance_height);

    const vmtx_offset: usize = @intCast(try sfntTableOffset(bytes, "vmtx"));
    writeU16Test(bytes, vmtx_offset, 900);
    try std.testing.expectError(error.BadSfnt, font.verticalMetrics(0));
}

test "vertical metrics API revalidates borrowed vhea and vmtx bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVerticalMetricsTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expect(font.hasVerticalMetrics());
    const first = (try font.verticalMetrics(0)).?;
    try std.testing.expectEqual(@as(u16, 1000), first.advance_height);
    try std.testing.expectEqual(@as(i16, 0), first.top_side_bearing);

    const second = (try font.verticalMetrics(1)).?;
    try std.testing.expectEqual(@as(u16, 1000), second.advance_height);
    try std.testing.expectEqual(@as(i16, 0), second.top_side_bearing);
    try std.testing.expectError(error.InvalidGlyph, font.verticalMetrics(2));

    const vhea_offset: usize = @intCast(try sfntTableOffset(bytes, "vhea"));
    writeU16Test(bytes, vhea_offset + 24, 1); // Reserved vhea fields must remain zero.
    try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(1));

    writeU16Test(bytes, vhea_offset + 24, 0);
    writeI16Test(bytes, vhea_offset + 4, 100);
    writeI16Test(bytes, vhea_offset + 6, 200);
    writeI16Test(bytes, vhea_offset + 8, 100);
    try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(1));

    writeI16Test(bytes, vhea_offset + 4, 800);
    writeI16Test(bytes, vhea_offset + 6, -200);
    writeI16Test(bytes, vhea_offset + 8, 0);
    writeU16Test(bytes, vhea_offset + 34, 2); // The borrowed vmtx table has only one full metric.
    try std.testing.expectError(error.InvalidMetrics, font.verticalMetrics(1));
}

test "vertical metrics API reports absence without requiring vertical tables" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expect(!font.hasVerticalMetrics());
    try std.testing.expectEqual(@as(?VerticalMetrics, null), try font.verticalMetrics(0));
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

test "simple glyf summaries must not exceed maxp maxima" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{
        .{ .maxp_field_offset = @as(usize, 6), .underreported_value = @as(u16, 2) }, // maxPoints < glyph 1's three points.
        .{ .maxp_field_offset = @as(usize, 8), .underreported_value = @as(u16, 0) }, // maxContours < glyph 1's one contour.
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        writeU16Test(bytes, maxp_offset + case.maxp_field_offset, case.underreported_value);
        try updateSfntTableChecksum(bytes, "maxp");

        try std.testing.expectError(error.InvalidGlyph, Font.parse(allocator, bytes));
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
    try updateSfntTableChecksum(bytes, "glyf");
    try updateSfntTableChecksum(bytes, "maxp");

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
        const original = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(original);
        const bytes = try allocator.alloc(u8, original.len + 4);
        defer allocator.free(bytes);
        @memcpy(bytes[0..original.len], original);
        @memset(bytes[original.len..], 0);
        try setSfntTableLength(bytes, "maxp", 33); // v1.0 maxp has no extension payload.
        try updateSfntTableChecksum(bytes, "maxp");
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

    {
        const original = try test_font.buildMinimalOtf(allocator);
        defer allocator.free(original);
        const bytes = try allocator.alloc(u8, original.len + 4);
        defer allocator.free(bytes);
        @memcpy(bytes[0..original.len], original);
        @memset(bytes[original.len..], 0);
        try setSfntTableLength(bytes, "maxp", 7); // v0.5 maxp is exactly version + numGlyphs.
        try updateSfntTableChecksum(bytes, "maxp");
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "TrueType maxp maxZones is tolerated for shaping compatibility" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    inline for (.{ 0, 1, 2, 3 }) |max_zones| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const maxp_offset = try sfntTableOffset(bytes, "maxp");
        // OpenType restricts maxZones to 1 or 2, but HarfBuzz/FreeType tolerate
        // shaping-only subset fonts with stale hinting maxima. Keep the field
        // readable in maxpInfo(), but do not reject an otherwise usable face.
        writeU16Test(bytes, maxp_offset + 14, max_zones);
        try updateSfntTableChecksum(bytes, "maxp");
        var font = try Font.parse(allocator, bytes);
        font.deinit();
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

test "OpenType layout-only subsets do not require CFF outlines for shaping" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildLayoutOnlyOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqual(FontFormat.opentype_cff, font.format);
    try std.testing.expect(!font.hasOutlineData());
    try std.testing.expectError(error.MissingTable, font.glyphOutline(allocator, 1));
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

test "CFF glyph outlines revalidate borrowed CharStrings count" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalOtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const cff_offset = try sfntTableOffset(bytes, "CFF ");
    const cff_length = try sfntTableLength(bytes, "CFF ");
    const info = try cff_mod.parseInfo(bytes[cff_offset .. cff_offset + cff_length]);

    // Mutate only the borrowed CFF payload after Font.parse. Glyph 0 still has
    // a valid charstring, so this regression exercises full-table revalidation
    // rather than per-request bounds checking in cff.appendGlyphOutline.
    writeU16Test(bytes, cff_offset + info.charstrings_offset, 1);

    try std.testing.expectError(error.BadSfnt, font.glyphOutline(allocator, 0));
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

    inline for (.{
        .{ .field_offset = @as(usize, 44), .write_value = @as(u16, 0x0080) }, // macStyle reserved bits.
        .{ .field_offset = @as(usize, 46), .write_value = @as(u16, 0) }, // lowestRecPPEM is a positive pixel size.
        .{ .field_offset = @as(usize, 48), .write_value = @as(u16, 3) }, // fontDirectionHint must remain in -2..2.
    }) |case| {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        writeU16Test(bytes, head_offset + case.field_offset, case.write_value);
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
        var post: [46]u8 = .{0} ** 46;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "A.alt");
        post[44] = 1; // Unreferenced trailing custom Pascal string.
        post[45] = 'B';
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        var post: [44]u8 = .{0} ** 44;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "bad/-"); // Slash is not valid in `post` glyph names.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        // Custom glyph-name text is optional metadata, so malformed text must
        // not prevent otherwise valid outlines, cmap, metrics, or shaping from
        // being used. The dedicated accessor remains strict because it exposes
        // that borrowed text to callers.
        _ = try font.postInfo();
        _ = try font.decorationMetrics();
        try std.testing.expectError(error.BadSfnt, font.glyphName(1));
    }

    {
        var post: [39]u8 = .{0} ** 39;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 0; // A production Mongolian font encodes “no name” this way.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        // The OpenType recommendation is to use standard index 0 (.notdef)
        // when no custom name exists. FreeType, FontTools, and HarfBuzz also
        // accept this deployed zero-length Pascal-string representation, so
        // expose it as absence rather than inventing or returning an empty name.
        try std.testing.expectEqual(@as(?[]const u8, null), try font.glyphName(1));
    }

    {
        var post: [44]u8 = .{0} ** 44;
        writePostHeaderTest(&post, 0x00020000);
        writeU16Test(&post, 32, 2);
        writeU16Test(&post, 34, 0);
        writeU16Test(&post, 36, 258);
        post[38] = 5;
        @memcpy(post[39..44], "ae-ar"); // Production Arabic fonts use hyphenated glyph names.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectEqualStrings("ae-ar", (try font.glyphName(1)).?);
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
        var post: [37]u8 = .{0} ** 37;
        writePostHeaderTest(&post, 0x00025000);
        writeU16Test(&post, 32, 2);
        post[34] = 0;
        post[35] = 0;
        post[36] = 0; // Format 2.5 has no trailing payload after deltas.
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
        var post: [38]u8 = .{0} ** 38;
        writePostHeaderTest(&post, 0x00040000);
        writeU16Test(&post, 32, 0xffff);
        writeU16Test(&post, 34, 'A');
        post[36] = 0;
        post[37] = 0; // Format 4.0 has no payload after glyph character codes.
        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
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

test "post glyph names are exposed and revalidated from borrowed bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var post: [44]u8 = .{0} ** 44;
    writePostHeaderTest(&post, 0x00020000);
    writeU16Test(&post, 32, 2);
    writeU16Test(&post, 34, 0); // glyph 0 uses the standard .notdef name.
    writeU16Test(&post, 36, 258); // glyph 1 uses the first custom Pascal string.
    post[38] = 5;
    @memcpy(post[39..44], "A.alt");

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectEqualStrings(".notdef", (try font.glyphName(0)).?);
    try std.testing.expectEqualStrings("A.alt", (try font.glyphName(1)).?);
    try std.testing.expectError(error.InvalidGlyph, font.glyphName(2));

    const post_offset = try sfntTableOffset(bytes, "post");
    bytes[post_offset + 43] = '/';
    // `post` custom names are borrowed from the original SFNT buffer. A caller
    // mutating that buffer after Font.parse must not make the public API return
    // a name that the parser would reject if it saw the bytes now.
    try std.testing.expectError(error.BadSfnt, font.glyphName(1));
}

test "post glyph names revalidate borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

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
    defer font.deinit();

    try std.testing.expectEqualStrings("A.alt", (try font.glyphName(1)).?);

    const post_offset = try sfntTableOffset(bytes, "post");
    // Keep the Pascal string grammar valid while changing the borrowed custom
    // name after parse. The lazy public API must reject the table because its
    // SFNT checksum no longer matches the parsed font map.
    bytes[post_offset + 39] = 'B';
    try std.testing.expectError(error.BadSfnt, font.glyphName(1));
}

test "post glyph names support standard aliases and absent-name formats" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        var post: [36]u8 = .{0} ** 36;
        writePostHeaderTest(&post, 0x00025000);
        writeU16Test(&post, 32, 2);
        post[34] = 0; // glyph 0 -> standard name 0.
        post[35] = 35; // glyph 1 + 35 -> standard name 36 ("A").

        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqualStrings(".notdef", (try font.glyphName(0)).?);
        try std.testing.expectEqualStrings("A", (try font.glyphName(1)).?);
    }

    {
        var post: [32]u8 = .{0} ** 32;
        writePostHeaderTest(&post, 0x00030000);

        const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        try std.testing.expectEqual(@as(?[]const u8, null), try font.glyphName(1));
    }
}

test "font decoration metrics prefer post underline and OS/2 strikeout" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var post: [32]u8 = .{0} ** 32;
    writePostHeaderTest(&post, 0x00030000);
    writeI16Test(&post, 8, -125);
    writeI16Test(&post, 10, 45);

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const metrics = try font.decorationMetrics();
    try std.testing.expectEqual(FontDecorationMetricSource.font, metrics.underline_source);
    try std.testing.expectEqual(@as(i16, -125), metrics.underline_position);
    try std.testing.expectEqual(@as(i16, 45), metrics.underline_thickness);
    try std.testing.expectEqual(FontDecorationMetricSource.fallback, metrics.strikeout_source);
    try std.testing.expect(metrics.strikeout_thickness > 0);

    const scaled = try font.scaledDecorationMetrics(20);
    try std.testing.expectApproxEqAbs(@as(f32, -2.5), scaled.underline_position, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), scaled.underline_thickness, 0.001);
}

test "font decoration metrics read OS/2 strikeout and fallback invalid underline" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(bytes);
    const os2_offset: usize = @intCast(try sfntTableOffset(bytes, "OS/2"));
    writeI16Test(bytes, os2_offset + 26, 70);
    writeI16Test(bytes, os2_offset + 28, 330);
    try updateSfntTableChecksum(bytes, "OS/2");

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const metrics = try font.decorationMetrics();
    try std.testing.expectEqual(FontDecorationMetricSource.fallback, metrics.underline_source);
    try std.testing.expectEqual(FontDecorationMetricSource.font, metrics.strikeout_source);
    try std.testing.expectEqual(@as(i16, 330), metrics.strikeout_position);
    try std.testing.expectEqual(@as(i16, 70), metrics.strikeout_thickness);
}

test "font script metrics read OS/2 superscript and subscript values" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildScriptMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const metrics = (try font.scriptMetrics()) orelse return error.MissingScriptMetrics;
    try std.testing.expectEqual(@as(i16, 640), metrics.superscript_x_size);
    try std.testing.expectEqual(@as(i16, 630), metrics.superscript_y_size);
    try std.testing.expectEqual(@as(i16, 13), metrics.superscript_x_offset);
    try std.testing.expectEqual(@as(i16, 360), metrics.superscript_y_offset);
    try std.testing.expectEqual(@as(i16, 620), metrics.subscript_x_size);
    try std.testing.expectEqual(@as(i16, 610), metrics.subscript_y_size);
    try std.testing.expectEqual(@as(i16, 11), metrics.subscript_x_offset);
    try std.testing.expectEqual(@as(i16, 140), metrics.subscript_y_offset);

    const scaled = (try font.scaledScriptMetrics(20)) orelse return error.MissingScaledScriptMetrics;
    try std.testing.expectApproxEqAbs(@as(f32, 12.8), scaled.superscript_x_size, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12.6), scaled.superscript_y_size, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.26), scaled.superscript_x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7.2), scaled.superscript_y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12.4), scaled.subscript_x_size, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12.2), scaled.subscript_y_size, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.22), scaled.subscript_x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.8), scaled.subscript_y_offset, 0.001);
}

test "font script metrics handle missing and mutated OS/2 tables" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const minimal = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(minimal);
    var minimal_font = try Font.parse(allocator, minimal);
    defer minimal_font.deinit();
    try std.testing.expect((try minimal_font.scriptMetrics()) == null);

    const bytes = try test_font.buildScriptMetricsTtf(allocator);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();
    _ = try font.scriptMetrics();
    const os2_offset: usize = @intCast(try sfntTableOffset(bytes, "OS/2"));
    writeI16Test(bytes, os2_offset + 20, 631);
    try std.testing.expectError(error.BadSfnt, font.scriptMetrics());
}

test "font decoration metrics revalidate borrowed table checksums" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    var post: [32]u8 = .{0} ** 32;
    writePostHeaderTest(&post, 0x00030000);
    writeI16Test(&post, 8, -100);
    writeI16Test(&post, 10, 40);

    const bytes = try test_font.buildMinimalTtfWithPost(allocator, &post);
    defer allocator.free(bytes);
    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    _ = try font.decorationMetrics();
    const post_offset = try sfntTableOffset(bytes, "post");
    writeI16Test(bytes, post_offset + 10, 41);
    try std.testing.expectError(error.BadSfnt, font.decorationMetrics());
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
    try std.testing.expectError(error.BadSfnt, Font.faceCount(overlapping));

    const unaligned = try test_font.buildMinimalTtc(allocator);
    defer allocator.free(unaligned);
    writeU32Test(unaligned, 12, 18);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(unaligned));

    const unselected_bad_face = try test_font.buildNamedTtc(allocator);
    defer allocator.free(unselected_bad_face);
    writeU32Test(unselected_bad_face, 16, 16); // Second face aliases TTC offset metadata.
    try std.testing.expectError(error.BadSfnt, Font.faceCount(unselected_bad_face));

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

test "SFNT table directory rejects non-printable tags" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        bytes[12] = 0x1f; // Control bytes are not legal OpenType tag data.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        bytes[12] = 0x7f; // DEL/non-printable tag byte.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        bytes[12] = 0x80; // Non-ASCII private tags are not portable SFNT tags.
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory offsets must be long aligned" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(bytes);
    const cmap_offset = try sfntTableOffset(bytes, "cmap");
    try setSfntTableOffset(bytes, "cmap", cmap_offset + 1);

    try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
}

test "SFNT table padding bytes must be zero" {
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
        const head_offset: usize = @intCast(try sfntTableOffset(bytes, "head"));
        const head_length: usize = @intCast(try sfntTableLength(bytes, "head"));
        try std.testing.expectEqual(@as(usize, 2), (4 - (head_length & 3)) & 3);

        // This byte is outside the declared head table length, so the table
        // checksum remains valid. It is still physical SFNT padding and must be
        // zero to avoid hiding attacker-controlled bytes between tables.
        bytes[head_offset + head_length] = 0x7f;
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
}

test "SFNT table directory checksums match borrowed table bytes" {
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
        const hhea_offset = try sfntTableOffset(bytes, "hhea");
        bytes[hhea_offset + 4] +%= 1;
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);
        const head_offset = try sfntTableOffset(bytes, "head");
        // head.checkSumAdjustment is explicitly ignored for the per-table
        // directory checksum; mutating any other head byte must still be caught.
        writeU32Test(bytes, head_offset + 8, 0xffff_ffff);
        var font = try Font.parse(allocator, bytes);
        font.deinit();

        bytes[head_offset + 18] +%= 1;
        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
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

test "single-byte name strings must decode to UTF-8 ASCII" {
    var bytes: [21]u8 = .{0} ** 21;
    writeU16Test(&bytes, 0, 0);
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 18);
    writeNameRecordTest(&bytes, 6, 1, 0, 0, @intFromEnum(NameId.family), 3, 0);
    bytes[18] = 'M';
    bytes[19] = 'a';
    bytes[20] = 'c';

    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings("Mac", (try readNameString(&bytes, nameTableRecord(bytes.len), @intFromEnum(NameId.family), &out)).?);

    // Platform 1 strings are not intrinsically UTF-8; bytes above ASCII depend
    // on a legacy Macintosh encoding table this API does not implement.
    bytes[19] = 0x8e;
    try std.testing.expectError(error.InvalidName, readNameString(&bytes, nameTableRecord(bytes.len), @intFromEnum(NameId.family), &out));
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

test "name table records must be sorted by complete key" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildNamedTtf(allocator);
        defer allocator.free(bytes);
        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try test_font.buildNamedTtf(allocator);
        defer allocator.free(bytes);
        const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
        const subfamily = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.subfamily));
        // Duplicate platform/encoding/language/nameID tuples are ambiguous:
        // two records would have the same lookup score, so the returned string
        // would depend on table order rather than a stable OpenType key.
        writeU16Test(bytes, subfamily + 6, @intFromEnum(NameId.family));
        try updateSfntTableChecksum(bytes, "name");

        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }

    {
        const bytes = try test_font.buildNamedTtf(allocator);
        defer allocator.free(bytes);
        const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
        const family = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.family));
        const subfamily = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.subfamily));
        // Reordering keys without changing storage still leaves every string
        // individually valid. The directory itself is malformed because nameID
        // 2 appears before nameID 1 for the same platform/encoding/language.
        writeU16Test(bytes, family + 6, @intFromEnum(NameId.subfamily));
        writeU16Test(bytes, subfamily + 6, @intFromEnum(NameId.family));
        try updateSfntTableChecksum(bytes, "name");

        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }
}

test "PostScript name strings validate FontName syntax" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "CangjieSans-Regular");
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var out: [64]u8 = undefined;
        try std.testing.expectEqualStrings("CangjieSans-Regular", (try font.nameString(.postscript_name, &out)).?);
    }

    {
        const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "Bad Name");
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var out: [64]u8 = undefined;
        try std.testing.expectError(error.InvalidName, font.nameString(.postscript_name, &out));
    }

    {
        const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "Bad/Name");
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        var out: [64]u8 = undefined;
        try std.testing.expectError(error.InvalidName, font.nameString(.postscript_name, &out));
    }
}

test "lazy PostScript name lookup revalidates borrowed bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "CangjieSans-Regular");
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("CangjieSans-Regular", (try font.nameString(.postscript_name, &out)).?);

    const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
    const record = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.postscript_name));
    const storage_offset: usize = @intCast(try bin.readU16At(bytes, name_offset + 4));
    const string_offset: usize = @intCast(try bin.readU16At(bytes, record + 10));
    bytes[name_offset + storage_offset + string_offset + 1] = ' ';

    try std.testing.expectError(error.BadSfnt, font.nameString(.postscript_name, &out));
}

test "lazy name lookup revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithPostScript(allocator, "Cangjie Sans", "Regular", "Cangjie Sans Regular", "CangjieSans-Regular");
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("Cangjie Sans", (try font.nameString(.family, &out)).?);

    const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
    const record = try nameRecordOffsetForId(bytes, name_offset, @intFromEnum(NameId.family));
    const storage_offset: usize = @intCast(try bin.readU16At(bytes, name_offset + 4));
    const string_offset: usize = @intCast(try bin.readU16At(bytes, record + 10));
    // Keep the UTF-16 string well-formed while changing user-facing metadata
    // after parse. The public lookup must reject the table because its SFNT
    // checksum no longer matches the parsed font map.
    bytes[name_offset + storage_offset + string_offset + 1] = 'D';
    try std.testing.expectError(error.BadSfnt, font.nameString(.family, &out));
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

test "name table format 1 validates language tag syntax" {
    var bytes: [36]u8 = .{0} ** 36;
    writeU16Test(&bytes, 0, 1); // format 1 name table.
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 24);
    writeNameRecordTest(&bytes, 6, 3, 1, 0x8000, @intFromEnum(NameId.family), 2, 0);
    writeU16Test(&bytes, 18, 1); // one LangTagRecord.
    writeU16Test(&bytes, 20, 10);
    writeU16Test(&bytes, 22, 2);
    bytes[25] = 'A';
    bytes[27] = 'e';
    bytes[29] = 'n';
    bytes[31] = '-';
    bytes[33] = 'U';
    bytes[35] = 'S';

    var out: [8]u8 = undefined;
    try std.testing.expectEqualStrings("A", (try readNameString(&bytes, nameTableRecord(bytes.len), @intFromEnum(NameId.family), &out)).?);

    var underscore = bytes;
    underscore[31] = '_';
    try std.testing.expectError(error.InvalidName, validateNameTable(&underscore, nameTableRecord(underscore.len)));

    var trailing_separator = bytes;
    trailing_separator[33] = 0;
    trailing_separator[35] = '-';
    try std.testing.expectError(error.InvalidName, validateNameTable(&trailing_separator, nameTableRecord(trailing_separator.len)));

    var single_primary = bytes;
    writeU16Test(&single_primary, 20, 2);
    single_primary[25] = 'x';
    try std.testing.expectError(error.InvalidName, validateNameTable(&single_primary, nameTableRecord(single_primary.len)));

    var numeric_primary = bytes;
    numeric_primary[27] = '1';
    try std.testing.expectError(error.InvalidName, validateNameTable(&numeric_primary, nameTableRecord(numeric_primary.len)));
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

test "gzip SVG payload validation checks stream integrity and decoded XML" {
    const valid = try vort.encodeGzipFixedAlloc(std.testing.allocator, "<svg><g/></svg>");
    defer std.testing.allocator.free(valid);
    try validateSvgDocumentPayload(std.testing.allocator, valid);

    const wrong_root = try vort.encodeGzipFixedAlloc(std.testing.allocator, "<g/>");
    defer std.testing.allocator.free(wrong_root);
    try std.testing.expectError(error.BadSfnt, validateSvgDocumentPayload(std.testing.allocator, wrong_root));

    const bad_crc = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(bad_crc);
    bad_crc[bad_crc.len - 8] ^= 1;
    try std.testing.expectError(error.BadSfnt, validateSvgDocumentPayload(std.testing.allocator, bad_crc));

    const bad_isize = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(bad_isize);
    bad_isize[bad_isize.len - 4] +%= 1;
    try std.testing.expectError(error.BadSfnt, validateSvgDocumentPayload(std.testing.allocator, bad_isize));

    try std.testing.expectError(error.BadSfnt, validateSvgDocumentPayload(std.testing.allocator, &.{ 0x1f, 0x8b, 0x08 }));

    // Vort consults ISIZE before allocation, so an advertised gzip bomb is
    // rejected by the 16 MiB SVG limit without attempting that allocation.
    const oversized = try std.testing.allocator.dupe(u8, valid);
    defer std.testing.allocator.free(oversized);
    std.mem.writeInt(u32, oversized[oversized.len - 4 ..][0..4], @intCast(max_svg_document_size + 1), .little);
    try std.testing.expectError(error.BadSfnt, validateSvgDocumentPayload(std.testing.allocator, oversized));
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

test "SVG public document lookup revalidates byte-range ownership" {
    var bytes: [48]u8 = .{0} ** 48;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 2); // two SVGDocumentRecords.
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 26); // First document: [26, 32) relative to the list.
    writeU32Test(&bytes, 20, 6);
    writeU16Test(&bytes, 24, 2);
    writeU16Test(&bytes, 26, 2);
    writeU32Test(&bytes, 28, 32); // Second document is initially disjoint: [32, 38).
    writeU32Test(&bytes, 32, 6);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..48], "<svg/>");

    const font = svgOnlyFont(&bytes);
    const original = (try font.svgGlyphDocument(2)).?;
    try std.testing.expectEqualSlices(u8, "<svg/>", original.data);

    // Font instances borrow caller-owned SFNT bytes. Mutating a later
    // SVGDocumentRecord into a partial byte overlap must be caught by the
    // public lookup path, not just by parse-time validation.
    writeU32Test(&bytes, 28, 30);
    try std.testing.expectError(error.BadSfnt, font.svgGlyphDocument(2));
}

test "SVG public document lookup revalidates borrowed XML payloads" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 2); // two SVGDocumentRecords.
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 26);
    writeU32Test(&bytes, 20, 6);
    writeU16Test(&bytes, 24, 2);
    writeU16Test(&bytes, 26, 2);
    writeU32Test(&bytes, 28, 32);
    writeU32Test(&bytes, 32, 8);
    @memcpy(bytes[36..42], "<svg/>");
    @memcpy(bytes[42..50], "<svg/>  ");

    const font = svgOnlyFont(&bytes);
    const original = (try font.svgGlyphDocument(1)).?;
    try std.testing.expectEqualSlices(u8, "<svg/>", original.data);

    // Lazy lookup must validate every advertised payload, not just the record
    // whose glyph range matched this call. Otherwise a mutated unrequested
    // document can stay hidden until a later glyph happens to select it.
    @memcpy(bytes[42..50], "<g></g> ");
    try std.testing.expectError(error.BadSfnt, font.svgGlyphDocument(1));

    @memcpy(bytes[42..50], "<svg/>  ");
    @memcpy(bytes[36..42], "<g></>");
    try std.testing.expectError(error.BadSfnt, font.svgGlyphDocument(1));
}

test "SVG public document lookup revalidates borrowed table checksum" {
    var bytes: [32]u8 = .{0} ** 32;
    writeU16Test(&bytes, 0, 0); // SVG table version.
    writeU32Test(&bytes, 2, 10); // SVGDocumentListOffset.
    writeU16Test(&bytes, 10, 1); // one SVGDocumentRecord.
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 1);
    writeU32Test(&bytes, 16, 14); // Document starts at byte 24.
    writeU32Test(&bytes, 20, 8);
    @memcpy(bytes[24..32], "<svg/>  ");

    const font = svgOnlyFont(&bytes);
    const original = (try font.svgGlyphDocument(1)).?;
    try std.testing.expectEqualSlices(u8, "<svg/>  ", original.data);

    // Keep the XML payload valid while changing only trailing whitespace after
    // construction. Lazy lookup must reject the borrowed SVG table because its
    // SFNT checksum no longer matches the parsed table map.
    bytes[31] = '\n';
    try std.testing.expectError(error.BadSfnt, font.svgGlyphDocument(1));
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

test "CPAL palette lookup revalidates borrowed label name IDs" {
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
    writeU16Test(&bytes, 28, 0xffff);
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

    var font = cpalOnlyFont(&bytes);
    const cpal_record = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = name_offset };
    font.cpal = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = try sfnt.checksum.table(&bytes, cpal_record), .offset = 0, .length = name_offset };
    font.name = .{ .tag = .{ 'n', 'a', 'm', 'e' }, .checksum = 0, .offset = name_offset, .length = bytes.len - name_offset };

    const color = (try font.paletteColor(0, 0)).?;
    try std.testing.expectEqual(@as(u8, 30), color.red);
    try std.testing.expectEqual(@as(u8, 20), color.green);
    try std.testing.expectEqual(@as(u8, 10), color.blue);
    try std.testing.expectEqual(@as(u8, 40), color.alpha);

    // Font deliberately borrows caller-owned SFNT bytes. Mutating only the
    // borrowed name table keeps CPAL's checksum valid while making its v1 label
    // reference dangle; the lazy color API must still observe that metadata
    // failure.
    writeU16Test(&bytes, name_offset + 12, 257);
    try std.testing.expectError(error.InvalidName, font.paletteColor(0, 0));
}

test "CPAL palette entry labels public API revalidates borrowed names" {
    const allocator = std.testing.allocator;

    var bytes: [54]u8 = .{0} ** 54;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 1);
    writeU16Test(&bytes, 4, 1);
    writeU16Test(&bytes, 6, 1);
    writeU32Test(&bytes, 8, 30);
    writeU16Test(&bytes, 12, 0);
    writeU32Test(&bytes, 14, 0);
    writeU32Test(&bytes, 18, 0);
    writeU32Test(&bytes, 22, 28);
    writeU16Test(&bytes, 28, 256);
    bytes[30] = 10;
    bytes[31] = 20;
    bytes[32] = 30;
    bytes[33] = 40;

    const name_offset = 34;
    writeU16Test(&bytes, name_offset + 0, 0);
    writeU16Test(&bytes, name_offset + 2, 1);
    writeU16Test(&bytes, name_offset + 4, 18);
    writeUtf16NameRecordTest(&bytes, name_offset + 6, 256, 2, 0);
    bytes[name_offset + 19] = 'E';

    var font = cpalOnlyFont(&bytes);
    const cpal_record = TableRecord{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = name_offset };
    font.cpal = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = try sfnt.checksum.table(&bytes, cpal_record), .offset = 0, .length = name_offset };
    font.name = .{ .tag = .{ 'n', 'a', 'm', 'e' }, .checksum = 0, .offset = name_offset, .length = bytes.len - name_offset };

    const labels = try font.paletteEntryLabels(allocator);
    defer allocator.free(labels);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    try std.testing.expectEqual(@as(?u16, 256), labels[0]);

    writeU16Test(&bytes, name_offset + 12, 257);
    try std.testing.expectError(error.InvalidName, font.paletteEntryLabels(allocator));
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

test "COLR public APIs revalidate borrowed glyph references" {
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
    writeU16Test(&colr_v0_with_cpal, 22, 0);
    writeSingleEntryCpalTest(&colr_v0_with_cpal, 24);

    const colr_v0_font = colrCpalOnlyFont(&colr_v0_with_cpal, 24);
    const layers = try colr_v0_font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 1), layers.len);
    try std.testing.expectEqual(@as(glyph_mod.GlyphId, 1), layers[0].glyph_id);

    // The Font caches only the COLR TableRecord; a caller can still mutate the
    // borrowed layer glyph bytes after construction. The lazy API must reject
    // that cross-table violation before returning a ColorLayer.
    writeU16Test(&colr_v0_with_cpal, 20, 16);
    try std.testing.expectError(error.BadSfnt, colr_v0_font.colorLayers(allocator, 1));

    var colr_v1_with_cpal: [92]u8 = .{0} ** 92;
    writeU16Test(&colr_v1_with_cpal, 0, 1); // COLR version 1.
    writeU32Test(&colr_v1_with_cpal, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&colr_v1_with_cpal, 18, 55); // LayerListOffset.
    writeU32Test(&colr_v1_with_cpal, 34, 1); // one BaseGlyphPaintRecord.
    writeU16Test(&colr_v1_with_cpal, 38, 1); // base glyph.
    writeU32Test(&colr_v1_with_cpal, 40, 10); // PaintGlyph at byte 44.
    colr_v1_with_cpal[44] = 10; // PaintGlyph.
    writeU24Test(&colr_v1_with_cpal, 45, 6); // Child PaintSolid follows PaintGlyph.
    writeU16Test(&colr_v1_with_cpal, 48, 1); // PaintGlyph glyph id.
    colr_v1_with_cpal[50] = 2; // PaintSolid.
    writeU16Test(&colr_v1_with_cpal, 51, 0);
    writeF2Dot14Test(&colr_v1_with_cpal, 53, 1.0);
    writeU32Test(&colr_v1_with_cpal, 55, 1); // one LayerList paint.
    writeU32Test(&colr_v1_with_cpal, 59, 8); // LayerList-relative PaintSolid at byte 63.
    colr_v1_with_cpal[63] = 2;
    writeU16Test(&colr_v1_with_cpal, 64, 0);
    writeF2Dot14Test(&colr_v1_with_cpal, 66, 1.0);
    writeSingleEntryCpalTest(&colr_v1_with_cpal, 74);

    const colr_v1_font = colrCpalOnlyFont(&colr_v1_with_cpal, 74);
    const paint = try colr_v1_font.colorPaint(1);
    try std.testing.expect(paint != null);
    try std.testing.expect((try colr_v1_font.colorPaintLayer(0)) != null);

    // PaintGlyph carries a glyph ID independently of the selected base glyph.
    // Mutating it past maxp.numGlyphs must be caught by colorPaint().
    writeU16Test(&colr_v1_with_cpal, 48, 16);
    try std.testing.expectError(error.BadSfnt, colr_v1_font.colorPaint(1));
    writeU16Test(&colr_v1_with_cpal, 48, 1);

    // LayerList is a separate lazy public entry point into the COLR v1 graph.
    // Mutating a layer paint to name an invalid glyph must be rejected there
    // even though the requested layer index itself is in range.
    colr_v1_with_cpal[63] = 10; // PaintGlyph inside the layer graph.
    writeU24Test(&colr_v1_with_cpal, 64, 6);
    writeU16Test(&colr_v1_with_cpal, 67, 16);
    colr_v1_with_cpal[69] = 2;
    writeU16Test(&colr_v1_with_cpal, 70, 0);
    writeF2Dot14Test(&colr_v1_with_cpal, 72, 1.0);
    try std.testing.expectError(error.BadSfnt, colr_v1_font.colorPaintLayer(0));
}

test "COLR public APIs revalidate borrowed palette references" {
    const allocator = std.testing.allocator;

    var colr_v0_with_cpal: [52]u8 = .{0} ** 52;
    writeU16Test(&colr_v0_with_cpal, 0, 0); // COLR version 0.
    writeU16Test(&colr_v0_with_cpal, 2, 2); // two BaseGlyphRecords.
    writeU32Test(&colr_v0_with_cpal, 4, 14);
    writeU32Test(&colr_v0_with_cpal, 8, 26);
    writeU16Test(&colr_v0_with_cpal, 12, 2);
    writeU16Test(&colr_v0_with_cpal, 14, 1); // selected base glyph.
    writeU16Test(&colr_v0_with_cpal, 16, 0);
    writeU16Test(&colr_v0_with_cpal, 18, 1);
    writeU16Test(&colr_v0_with_cpal, 20, 2); // unrequested base glyph.
    writeU16Test(&colr_v0_with_cpal, 22, 1);
    writeU16Test(&colr_v0_with_cpal, 24, 1);
    writeU16Test(&colr_v0_with_cpal, 26, 1);
    writeU16Test(&colr_v0_with_cpal, 28, 0);
    writeU16Test(&colr_v0_with_cpal, 30, 2);
    writeU16Test(&colr_v0_with_cpal, 32, 0);
    writeSingleEntryCpalTest(&colr_v0_with_cpal, 34);

    const colr_v0_font = colrCpalOnlyFont(&colr_v0_with_cpal, 34);
    const layers = try colr_v0_font.colorLayers(allocator, 1);
    defer allocator.free(layers);
    try std.testing.expectEqual(@as(usize, 1), layers.len);

    // The selected glyph's layer still uses palette index 0. Mutating only an
    // unrequested layer past CPAL must still be rejected because COLR's layer
    // array is global borrowed metadata accepted as a whole at parse time.
    writeU16Test(&colr_v0_with_cpal, 32, 1);
    try std.testing.expectError(error.BadSfnt, colr_v0_font.colorLayers(allocator, 1));

    var colr_v1_base_with_cpal: [78]u8 = .{0} ** 78;
    writeU16Test(&colr_v1_base_with_cpal, 0, 1); // COLR version 1.
    writeU32Test(&colr_v1_base_with_cpal, 14, 34); // BaseGlyphListOffset.
    writeU32Test(&colr_v1_base_with_cpal, 34, 2);
    writeU16Test(&colr_v1_base_with_cpal, 38, 1);
    writeU32Test(&colr_v1_base_with_cpal, 40, 16); // selected PaintSolid at byte 50.
    writeU16Test(&colr_v1_base_with_cpal, 44, 2);
    writeU32Test(&colr_v1_base_with_cpal, 46, 21); // unrequested PaintSolid at byte 55.
    colr_v1_base_with_cpal[50] = 2;
    writeU16Test(&colr_v1_base_with_cpal, 51, 0);
    writeF2Dot14Test(&colr_v1_base_with_cpal, 53, 1.0);
    colr_v1_base_with_cpal[55] = 2;
    writeU16Test(&colr_v1_base_with_cpal, 56, 0);
    writeF2Dot14Test(&colr_v1_base_with_cpal, 58, 1.0);
    writeSingleEntryCpalTest(&colr_v1_base_with_cpal, 60);

    const colr_v1_base_font = colrCpalOnlyFont(&colr_v1_base_with_cpal, 60);
    try std.testing.expect((try colr_v1_base_font.colorPaint(1)) != null);

    // `colorPaint(1)` reads only the first base glyph, but the borrowed COLR v1
    // base paint list must remain globally consistent with CPAL.
    writeU16Test(&colr_v1_base_with_cpal, 56, 1);
    try std.testing.expectError(error.BadSfnt, colr_v1_base_font.colorPaint(1));

    var colr_v1_layers_with_cpal: [74]u8 = .{0} ** 74;
    writeU16Test(&colr_v1_layers_with_cpal, 0, 1); // COLR version 1.
    writeU32Test(&colr_v1_layers_with_cpal, 18, 34); // LayerListOffset.
    writeU32Test(&colr_v1_layers_with_cpal, 34, 2);
    writeU32Test(&colr_v1_layers_with_cpal, 38, 12); // selected layer PaintSolid at byte 46.
    writeU32Test(&colr_v1_layers_with_cpal, 42, 17); // sibling layer PaintSolid at byte 51.
    colr_v1_layers_with_cpal[46] = 2;
    writeU16Test(&colr_v1_layers_with_cpal, 47, 0);
    writeF2Dot14Test(&colr_v1_layers_with_cpal, 49, 1.0);
    colr_v1_layers_with_cpal[51] = 2;
    writeU16Test(&colr_v1_layers_with_cpal, 52, 0);
    writeF2Dot14Test(&colr_v1_layers_with_cpal, 54, 1.0);
    writeSingleEntryCpalTest(&colr_v1_layers_with_cpal, 56);

    const colr_v1_layers_font = colrCpalOnlyFont(&colr_v1_layers_with_cpal, 56);
    try std.testing.expect((try colr_v1_layers_font.colorPaintLayer(0)) != null);

    // LayerList is a global paint array; a malformed sibling layer should not
    // be hidden merely because the requested layer still names a valid color.
    writeU16Test(&colr_v1_layers_with_cpal, 52, 1);
    try std.testing.expectError(error.BadSfnt, colr_v1_layers_font.colorPaintLayer(0));
}

test "COLR foreground palette sentinel is valid in v0 and v1" {
    var v0: [18]u8 = .{0} ** 18;
    writeU16Test(&v0, 0, 0);
    writeU16Test(&v0, 2, 0);
    writeU32Test(&v0, 4, 14);
    writeU32Test(&v0, 8, 14);
    writeU16Test(&v0, 12, 1);
    writeU16Test(&v0, 14, 1);
    writeU16Test(&v0, 16, 0xffff);
    const colr = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = v0.len };
    try validateColrPaletteBounds(&v0, colr, null);

    var v1: [49]u8 = .{0} ** 49;
    writeU16Test(&v1, 0, 1);
    writeU32Test(&v1, 14, 34);
    writeU32Test(&v1, 34, 1);
    writeU16Test(&v1, 38, 1);
    writeU32Test(&v1, 40, 10);
    v1[44] = 2;
    writeU16Test(&v1, 45, 0xffff);
    writeF2Dot14Test(&v1, 47, 1);
    const colr_v1 = TableRecord{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = v1.len };
    try validateColrPaletteBounds(&v1, colr_v1, null);
}

test "TTC v2 DSIG descriptor validates range and null consistency" {
    var valid_empty: [40]u8 = .{0} ** 40;
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

    var out_of_bounds: [40]u8 = .{0} ** 40;
    writeTagTest(&out_of_bounds, 0, "ttcf");
    writeU32Test(&out_of_bounds, 4, 0x00020000);
    writeU32Test(&out_of_bounds, 8, 1);
    writeU32Test(&out_of_bounds, 12, 28);
    writeTagTest(&out_of_bounds, 16, "DSIG");
    writeU32Test(&out_of_bounds, 20, 8);
    writeU32Test(&out_of_bounds, 24, 36);
    try std.testing.expectError(error.BadSfnt, Font.faceCount(&out_of_bounds));

    var valid_dsig: [44]u8 = .{0} ** 44;
    writeTagTest(&valid_dsig, 0, "ttcf");
    writeU32Test(&valid_dsig, 4, 0x00020000);
    writeU32Test(&valid_dsig, 8, 1);
    writeU32Test(&valid_dsig, 12, 28);
    writeTagTest(&valid_dsig, 16, "DSIG");
    writeU32Test(&valid_dsig, 20, 4);
    writeU32Test(&valid_dsig, 24, 40);
    try std.testing.expectEqual(@as(usize, 1), try Font.faceCount(&valid_dsig));
}

test "TTC v2 DSIG payload cannot alias faces or SFNT tables" {
    const allocator = std.testing.allocator;

    {
        const bytes = try buildMinimalTtcV2WithDsigTest(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        font.deinit();
    }

    {
        const bytes = try buildMinimalTtcV2WithDsigTest(allocator);
        defer allocator.free(bytes);
        const dsig_offset = try bin.readU32At(bytes, 24);
        writeU32Test(bytes, 12, dsig_offset); // Face offset points into the collection DSIG payload.

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }

    {
        const bytes = try buildMinimalTtcV2WithDsigTest(allocator);
        defer allocator.free(bytes);
        const dsig_offset = try bin.readU32At(bytes, 24);
        try setSfntTableOffsetAtTest(bytes, 28, "head", dsig_offset);
        try setSfntTableLengthAtTest(bytes, 28, "head", 4);

        try std.testing.expectError(error.BadSfnt, Font.parse(allocator, bytes));
    }
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
    writeF16Dot16Test(&valid_with_instance, 40, 400.0); // one coordinate

    const valid_font = fvarOnlyFont(&valid_with_instance);
    const axes = try valid_font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 1), axes.len);
    try std.testing.expectEqualStrings("wght", &axes[0].tag);

    var bad_count_size_pairs = valid_with_instance;
    writeU16Test(&bad_count_size_pairs, 6, 3);
    const bad_count_size_pairs_font = fvarOnlyFont(&bad_count_size_pairs);
    try std.testing.expectError(error.BadSfnt, bad_count_size_pairs_font.variationAxes(allocator));

    var padded_axis_record: [38]u8 = .{0} ** 38;
    writeU32Test(&padded_axis_record, 0, 0x00010000);
    writeU16Test(&padded_axis_record, 4, 16);
    writeU16Test(&padded_axis_record, 6, 2);
    writeU16Test(&padded_axis_record, 8, 1);
    writeU16Test(&padded_axis_record, 10, 22); // fvar AxisRecord is fixed-width: padding is not meaningful.
    writeFvarAxisTest(&padded_axis_record, 16, "wght", 100.0, 400.0, 900.0, 256);
    try std.testing.expectError(error.BadSfnt, fvarOnlyFont(&padded_axis_record).variationAxes(allocator));

    var ambiguous_instance_size: [45]u8 = .{0} ** 45;
    writeU32Test(&ambiguous_instance_size, 0, 0x00010000);
    writeU16Test(&ambiguous_instance_size, 4, 16);
    writeU16Test(&ambiguous_instance_size, 6, 2);
    writeU16Test(&ambiguous_instance_size, 8, 1);
    writeU16Test(&ambiguous_instance_size, 10, 20);
    writeU16Test(&ambiguous_instance_size, 12, 1);
    writeU16Test(&ambiguous_instance_size, 14, 9); // Not coordinates-only and not coordinates plus PostScript name ID.
    writeFvarAxisTest(&ambiguous_instance_size, 16, "wght", 100.0, 400.0, 900.0, 256);
    try std.testing.expectError(error.BadSfnt, fvarOnlyFont(&ambiguous_instance_size).variationAxes(allocator));
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

    var hidden_duplicate_tags = duplicate_tags;
    writeU16Test(&hidden_duplicate_tags, 36 + 16, 0x0001);
    const hidden_duplicate_font = fvarOnlyFont(&hidden_duplicate_tags);
    const axes = try hidden_duplicate_font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqualSlices(u8, "wght", &axes[0].tag);
    try std.testing.expectEqualSlices(u8, "wght", &axes[1].tag);
    try std.testing.expectEqual(@as(u16, 0), axes[0].flags);
    try std.testing.expectEqual(@as(u16, 1), axes[1].flags);

    const normalized = try hidden_duplicate_font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 700.0 },
    });
    defer allocator.free(normalized);
    try std.testing.expectEqual(@as(usize, 2), normalized.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), normalized[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), normalized[1], 0.0001);
}

test "fvar public axes API revalidates borrowed axis name references" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqual(@as(u16, 256), axes[0].name_id);

    const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
    // Leave fvar itself unchanged so this test isolates the cross-table name
    // reference contract. Axis name id 256 is the sixth synthetic name record.
    writeU16Test(bytes, name_offset + 6 + 5 * 12 + 6, 400);
    try std.testing.expectError(error.InvalidName, font.variationAxes(allocator));
}

test "fvar public axes API revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 2), axes.len);
    try std.testing.expectEqual(@as(f32, 100.0), axes[0].min_value);

    const fvar_offset: usize = @intCast(try sfntTableOffset(bytes, "fvar"));
    // Keep the axis range ordered and name references valid while changing
    // user-visible variation metadata after parse. The lazy API must reject the
    // borrowed fvar table because its SFNT checksum no longer matches.
    writeF16Dot16Test(bytes, fvar_offset + 20, 200.0);
    try std.testing.expectError(error.BadSfnt, font.variationAxes(allocator));
}

test "fvar public axes API revalidates all table metadata" {
    const allocator = std.testing.allocator;

    var bytes: [44]u8 = .{0} ** 44;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 1);
    writeU16Test(&bytes, 10, 20);
    writeU16Test(&bytes, 12, 1);
    writeU16Test(&bytes, 14, 8);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeU16Test(&bytes, 36, 300); // subfamilyNameID.
    writeU16Test(&bytes, 38, 0); // flags.
    writeF16Dot16Test(&bytes, 40, 400.0); // instance coordinate.

    const font = fvarOnlyFont(&bytes);
    const axes = try font.variationAxes(allocator);
    defer allocator.free(axes);
    try std.testing.expectEqual(@as(usize, 1), axes.len);
    try std.testing.expectEqual(@as(u16, 0), axes[0].flags);

    var reserved_axis_flags = bytes;
    writeU16Test(&reserved_axis_flags, 32, 0x0002); // Only HIDDEN_AXIS is defined.
    try std.testing.expectError(error.BadSfnt, fvarOnlyFont(&reserved_axis_flags).variationAxes(allocator));

    var invalid_axis_tag = bytes;
    invalid_axis_tag[16] = 0x1f; // Axis tags share OpenType's printable ASCII tag contract.
    try std.testing.expectError(error.BadSfnt, fvarOnlyFont(&invalid_axis_tag).variationAxes(allocator));

    var reserved_instance_flags = bytes;
    writeU16Test(&reserved_instance_flags, 38, 1); // fvar instance flags are reserved.
    try std.testing.expectError(error.BadSfnt, fvarOnlyFont(&reserved_instance_flags).variationAxes(allocator));

    var coordinate_past_axis_range = bytes;
    writeF16Dot16Test(&coordinate_past_axis_range, 40, 950.0);
    try std.testing.expectError(error.BadSfnt, fvarOnlyFont(&coordinate_past_axis_range).variationAxes(allocator));
}

test "normalized variation coordinates reject duplicate and unknown public tags" {
    const allocator = std.testing.allocator;

    var bytes: [56]u8 = .{0} ** 56;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 2);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeFvarAxisTest(&bytes, 36, "wdth", 50.0, 100.0, 200.0, 257);

    const font = fvarOnlyFont(&bytes);
    const normalized = try font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 700.0 },
        .{ .tag = .{ 'w', 'd', 't', 'h' }, .value = 125.0 },
    });
    defer allocator.free(normalized);
    try std.testing.expectEqual(@as(usize, 2), normalized.len);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), normalized[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), normalized[1], 0.0001);

    try std.testing.expectError(error.BadSfnt, font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 650.0 },
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = 700.0 },
    }));
    try std.testing.expectError(error.BadSfnt, font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'W', 'G', 'H', 'T' }, .value = 700.0 },
    }));
    try std.testing.expectError(error.BadSfnt, font.normalizedVariationCoordinates(allocator, &.{
        .{ .tag = .{ 'w', 'g', 'h', 't' }, .value = std.math.nan(f32) },
    }));
}

test "normalized variation coordinates quantize final locations to F2Dot14" {
    // A one-third negative location is not exactly representable in f32 or
    // F2Dot14. Quantization belongs at the public design-to-location boundary
    // so all downstream gvar and ItemVariationStore consumers see one value.
    try std.testing.expectEqual(@as(f32, -0.33331298828125), quantizeNormalizedF2Dot14(-1.0 / 3.0));
    try std.testing.expectEqual(@as(f32, 0.4000244140625), quantizeNormalizedF2Dot14(0.4));
    try std.testing.expectEqual(@as(f32, 0.10003662109375), quantizeNormalizedF2Dot14(0.1));
    try std.testing.expectEqual(@as(f32, -1.0), quantizeNormalizedF2Dot14(-1.0));
    try std.testing.expectEqual(@as(f32, 1.0), quantizeNormalizedF2Dot14(1.0));
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
        try updateSfntTableChecksum(bytes, "STAT");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        try std.testing.expectError(error.InvalidName, font.statAxisValues(allocator));
    }

    {
        const bytes = try test_font.buildVariableTtf(allocator);
        defer allocator.free(bytes);
        try setSfntTableTag(bytes, "name", "namx");
        try std.testing.expectError(error.InvalidName, Font.parse(allocator, bytes));
    }
}

test "STAT design axes public API revalidates borrowed metadata" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    {
        const bytes = try test_font.buildMinimalTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const axes = try font.statDesignAxes(allocator);
        defer allocator.free(axes);
        try std.testing.expectEqual(@as(usize, 0), axes.len);

        const values = try font.statAxisValues(allocator);
        defer font.freeStatAxisValues(allocator, values);
        try std.testing.expectEqual(@as(usize, 0), values.len);
        try std.testing.expectEqual(@as(?u16, null), try font.statElidedFallbackNameId(allocator));
    }

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const axes = try font.statDesignAxes(allocator);
        defer allocator.free(axes);
        try std.testing.expectEqual(@as(usize, 2), axes.len);
        try std.testing.expectEqualStrings("wght", &axes[0].tag);
        try std.testing.expectEqual(@as(u16, 256), axes[0].name_id);
        try std.testing.expectEqual(@as(u16, 0), axes[0].ordering);
        try std.testing.expectEqualStrings("wdth", &axes[1].tag);
        try std.testing.expectEqual(@as(u16, 257), axes[1].name_id);
        try std.testing.expectEqual(@as(u16, 1), axes[1].ordering);

        const values = try font.statAxisValues(allocator);
        defer font.freeStatAxisValues(allocator, values);
        try std.testing.expectEqual(@as(usize, 1), values.len);
        try std.testing.expectEqual(@as(u16, 1), values[0].format);
        try std.testing.expectEqual(@as(?u16, 0), values[0].axis_index);
        try std.testing.expectEqual(@as(u16, 2), values[0].name_id);
        try std.testing.expectApproxEqAbs(@as(f32, 400.0), values[0].value.?, 0.001);
        try std.testing.expectEqual(@as(?u16, 2), try font.statElidedFallbackNameId(allocator));
    }

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const name_offset: usize = @intCast(try sfntTableOffset(bytes, "name"));
        // Leave STAT itself unchanged so this block isolates the cross-table
        // name-reference contract. Axis name id 256 is the sixth synthetic
        // name record shared with the variable-font fixture.
        writeU16Test(bytes, name_offset + 6 + 5 * 12 + 6, 400);
        try std.testing.expectError(error.InvalidName, font.statDesignAxes(allocator));

        writeU16Test(bytes, name_offset + 6 + 1 * 12 + 6, 401);
        try std.testing.expectError(error.InvalidName, font.statAxisValues(allocator));
        try std.testing.expectError(error.InvalidName, font.statElidedFallbackNameId(allocator));
    }

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const axes = try font.statDesignAxes(allocator);
        defer allocator.free(axes);
        try std.testing.expectEqual(@as(u16, 0), axes[0].ordering);

        const stat_offset: usize = @intCast(try sfntTableOffset(bytes, "STAT"));
        // Keep STAT structurally valid while changing a user-facing ordering
        // value after parse. The lazy API must reject it because the borrowed
        // STAT table no longer matches the SFNT checksum.
        writeU16Test(bytes, stat_offset + 26, 2);
        try std.testing.expectError(error.BadSfnt, font.statDesignAxes(allocator));
        try std.testing.expectError(error.BadSfnt, font.statAxisValues(allocator));
        try std.testing.expectError(error.BadSfnt, font.statElidedFallbackNameId(allocator));
    }

    {
        const bytes = try test_font.buildVariableStatTtf(allocator);
        defer allocator.free(bytes);

        var font = try Font.parse(allocator, bytes);
        defer font.deinit();

        const stat_offset: usize = @intCast(try sfntTableOffset(bytes, "STAT"));
        writeTagTest(bytes, stat_offset + 28, "opsz"); // STAT axis order no longer matches fvar.
        try std.testing.expectError(error.BadSfnt, font.statDesignAxes(allocator));
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
    // Stale named-instance UI metadata does not invalidate the axis controls
    // used by shaping, but the complete instance metadata API stays strict.
    try validateFvarAxisNameReferences(&missing_subfamily, fvar, &names);
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

test "avar public mapping rejects out-of-range axis indexes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.25), try font.mapVariationCoordinate(0, 0.5), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), try font.mapVariationCoordinate(1, 0.5), 0.0001);
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(2, 0.5));
}

test "avar public mapping revalidates borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.25), try font.mapVariationCoordinate(0, 0.5), 0.0001);

    const avar_offset: usize = @intCast(try sfntTableOffset(bytes, "avar"));
    // Keep the segment map ordered and anchored while changing the mapped
    // midpoint after Font.parse. The lazy API must reject the borrowed avar
    // table because its SFNT checksum no longer matches.
    writeF2Dot14Test(bytes, avar_offset + 20, 0.375);
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, 0.5));
}

test "avar public mapping validates normalized coordinates" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildVariableTtf(allocator);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, -1.0), try font.mapVariationCoordinate(0, -1.0), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), try font.mapVariationCoordinate(0, 1.0), 0.0001);
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, 1.0001));
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, -1.0001));
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, std.math.inf(f32)));
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(0, std.math.nan(f32)));
}

test "avar public mapping revalidates axis indexes and segment anchors" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU32Test(&bytes, 0, 0x00010000);
    writeU16Test(&bytes, 4, 16);
    writeU16Test(&bytes, 6, 2);
    writeU16Test(&bytes, 8, 2);
    writeU16Test(&bytes, 10, 20);
    writeFvarAxisTest(&bytes, 16, "wght", 100.0, 400.0, 900.0, 256);
    writeFvarAxisTest(&bytes, 36, "wdth", 50.0, 100.0, 200.0, 257);

    const avar_offset = 56;
    writeU16Test(&bytes, avar_offset + 0, 1);
    writeU16Test(&bytes, avar_offset + 2, 0);
    writeU16Test(&bytes, avar_offset + 4, 0);
    writeU16Test(&bytes, avar_offset + 6, 0);

    var no_fvar_axis_maps = bytes;
    writeU16Test(&no_fvar_axis_maps, avar_offset + 6, 1);
    const no_fvar = avarOnlyFont(no_fvar_axis_maps[avar_offset..]);
    try std.testing.expectError(error.BadSfnt, no_fvar.mapVariationCoordinate(0, 0.25));

    var malformed_map: [92]u8 = .{0} ** 92;
    @memcpy(malformed_map[0..bytes.len], &bytes);
    writeU16Test(&malformed_map, avar_offset + 6, 2);
    writeU16Test(&malformed_map, avar_offset + 8, 3);
    writeF2Dot14Test(&malformed_map, avar_offset + 10, -1.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 12, -1.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 14, 0.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 16, 0.25); // Default coordinate must map to itself.
    writeF2Dot14Test(&malformed_map, avar_offset + 18, 1.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 20, 1.0);
    writeU16Test(&malformed_map, avar_offset + 22, 3);
    writeF2Dot14Test(&malformed_map, avar_offset + 24, -1.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 26, -1.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 28, 0.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 30, 0.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 32, 1.0);
    writeF2Dot14Test(&malformed_map, avar_offset + 34, 1.0);

    const font = fvarAvarOnlyFont(&malformed_map, avar_offset);
    // `mapVariationCoordinate` reparses borrowed avar bytes on every call so
    // mutations after Font.parse cannot bypass the parse-time segment-map
    // contract, even when asking for a different axis.
    try std.testing.expectError(error.BadSfnt, font.mapVariationCoordinate(1, 0.25));
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

    var with_map: [59]u8 = .{0} ** 59;
    @memcpy(with_map[0..bytes.len], &bytes);
    writeU32Test(&with_map, 8, 54); // AdvanceWidthMappingOffset follows the store.
    with_map[54] = 0; // DeltaSetIndexMap format 0.
    with_map[55] = 0; // one-byte entries, one inner-index bit.
    writeU16Test(&with_map, 56, 1); // mapCount.
    with_map[58] = 0; // outerIndex 0, innerIndex 0.
    const hvar_with_map = TableRecord{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = with_map.len };
    try validateMetricVariationTable(&with_map, hvar_with_map, 1, 20);

    var map_aliases_store = with_map;
    writeU32Test(&map_aliases_store, 8, 20); // A map must not reinterpret ItemVariationStore bytes.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&map_aliases_store, hvar_with_map, 1, 20));

    var maps_alias_each_other = with_map;
    writeU32Test(&maps_alias_each_other, 12, 54); // Duplicate DeltaSetIndexMap payload.
    try validateMetricVariationTable(&maps_alias_each_other, hvar_with_map, 1, 20);

    var peak_outside_normalized_space = bytes;
    writeI16Test(&peak_outside_normalized_space, 38, 0x4001);
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&peak_outside_normalized_space, hvar, 1, 20));

    var reversed_region = bytes;
    writeF2Dot14Test(&reversed_region, 36, 0.5); // regionStartCoord > peakCoord.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&reversed_region, hvar, 1, 20));
}

test "VariationStore child payloads do not alias each other" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU32Test(&bytes, 4, 20); // ItemVariationStore offset.

    writeU16Test(&bytes, 20, 1); // ItemVariationStore format.
    writeU32Test(&bytes, 22, 16); // VariationRegionList follows both ItemVariationData offsets.
    writeU16Test(&bytes, 26, 2); // itemVariationDataCount.
    writeU32Test(&bytes, 28, 28); // First ItemVariationData.
    writeU32Test(&bytes, 32, 38); // Second ItemVariationData is adjacent to the first.

    writeU16Test(&bytes, 36, 1); // axisCount.
    writeU16Test(&bytes, 38, 1); // regionCount.
    writeF2Dot14Test(&bytes, 40, -1.0);
    writeF2Dot14Test(&bytes, 42, 0.0);
    writeF2Dot14Test(&bytes, 44, 1.0);

    writeU16Test(&bytes, 48, 1); // itemCount.
    writeU16Test(&bytes, 50, 1); // wordDeltaCount.
    writeU16Test(&bytes, 52, 1); // regionIndexCount.
    writeU16Test(&bytes, 54, 0); // regionIndexes[0].
    writeI16Test(&bytes, 56, 7); // delta row.

    writeU16Test(&bytes, 58, 0); // Empty second ItemVariationData is adjacent and valid.
    writeU16Test(&bytes, 60, 0);
    writeU16Test(&bytes, 62, 0);

    const hvar = TableRecord{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateMetricVariationTable(&bytes, hvar, 1, 20);

    var item_data_alias = bytes;
    writeU32Test(&item_data_alias, 32, 28); // Duplicate ItemVariationData offset.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&item_data_alias, hvar, 1, 20));

    var region_alias: [42]u8 = .{0} ** 42;
    writeU16Test(&region_alias, 0, 1);
    writeU16Test(&region_alias, 2, 0);
    writeU32Test(&region_alias, 4, 20); // ItemVariationStore offset.
    writeU16Test(&region_alias, 20, 1); // ItemVariationStore format.
    writeU32Test(&region_alias, 22, 16); // Empty VariationRegionList.
    writeU16Test(&region_alias, 26, 1); // itemVariationDataCount.
    writeU32Test(&region_alias, 28, 16); // ItemVariationData aliases the region-list header.
    const hvar_zero_axis = TableRecord{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = region_alias.len };
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&region_alias, hvar_zero_axis, 0, 20));
}

test "VariationStore permits zero-region data with zero-width rows" {
    var bytes: [42]u8 = .{0} ** 42;
    writeU16Test(&bytes, 0, 1);
    writeU16Test(&bytes, 2, 0);
    writeU32Test(&bytes, 4, 20); // ItemVariationStore offset.

    writeU16Test(&bytes, 20, 1); // ItemVariationStore format.
    writeU32Test(&bytes, 22, 12); // Empty VariationRegionList.
    writeU16Test(&bytes, 26, 1); // itemVariationDataCount.
    writeU32Test(&bytes, 28, 16); // ItemVariationData follows region list.

    writeU16Test(&bytes, 32, 0); // axisCount.
    writeU16Test(&bytes, 34, 0); // regionCount.

    writeU16Test(&bytes, 36, 3); // itemCount with zero-width delta rows.
    writeU16Test(&bytes, 38, 0); // wordDeltaCount.
    writeU16Test(&bytes, 40, 0); // regionIndexCount.

    const hvar = TableRecord{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = bytes.len };
    try validateMetricVariationTable(&bytes, hvar, 0, 20);
}

test "Metric variation DeltaSetIndexMaps own disjoint top-level payloads" {
    var hvar_bytes: [62]u8 = .{0} ** 62;
    writeMetricVariationHeaderWithOneMap(&hvar_bytes, 20, 28);
    writeItemVariationStoreWithOneItem(&hvar_bytes, 28);
    const hvar = TableRecord{ .tag = .{ 'H', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = hvar_bytes.len };
    try validateMetricVariationTable(&hvar_bytes, hvar, 1, 20);

    var map_aliases_store = hvar_bytes;
    writeU32Test(&map_aliases_store, 8, 28); // advanceWidthMappingOffset aliases ItemVariationStore.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&map_aliases_store, hvar, 1, 20));

    var duplicate_maps = hvar_bytes;
    writeU32Test(&duplicate_maps, 12, 20); // lsbMappingOffset reuses advanceWidthMappingOffset.
    try validateMetricVariationTable(&duplicate_maps, hvar, 1, 20);

    var vvar_bytes: [66]u8 = .{0} ** 66;
    writeU16Test(&vvar_bytes, 0, 1);
    writeU16Test(&vvar_bytes, 2, 0);
    writeU32Test(&vvar_bytes, 4, 32); // ItemVariationStore offset.
    writeU32Test(&vvar_bytes, 20, 24); // VVAR-only vorgMappingOffset.
    writeDeltaSetIndexMapWithOneEntry(&vvar_bytes, 24);
    writeItemVariationStoreWithOneItem(&vvar_bytes, 32);
    const vvar = TableRecord{ .tag = .{ 'V', 'V', 'A', 'R' }, .checksum = 0, .offset = 0, .length = vvar_bytes.len };
    try validateMetricVariationTable(&vvar_bytes, vvar, 1, 24);

    var fourth_map_aliases_store = vvar_bytes;
    writeU32Test(&fourth_map_aliases_store, 20, 32); // vorgMappingOffset aliases ItemVariationStore.
    try std.testing.expectError(error.BadSfnt, validateMetricVariationTable(&fourth_map_aliases_store, vvar, 1, 24));
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

test "STAT design axes may differ from fvar presentation axes" {
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
    try validateStatTable(std.testing.allocator, &mismatched, stat, fvar, &names);
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

    var invalid_axis_tag = bytes;
    invalid_axis_tag[28] = 0x7f; // STAT design-axis tags must also be printable OpenType tags.
    try std.testing.expectError(error.BadSfnt, validateStatTable(std.testing.allocator, &invalid_axis_tag, stat, null, &names));
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

test "STAT AxisValue offset array may be out of payload order" {
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
    try validateStatTable(std.testing.allocator, &decreasing_offsets, stat, null, &names);

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

test "STAT format 4 AxisValue coordinate sets tolerate platform duplicates" {
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
    try validateStatTable(std.testing.allocator, &duplicate_coordinate_set, stat, null, &names);
}

test "macOS platform UI fonts parse for text metrics" {
    if (@import("builtin").target.os.tag != .macos) return error.SkipZigTest;
    const paths = [_][]const u8{
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    };
    var checked: usize = 0;
    for (paths) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(256 * 1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer std.testing.allocator.free(bytes);
        var font = try Font.parse(std.testing.allocator, bytes);
        defer font.deinit();
        try std.testing.expect(font.glyph_count > 0);
        checked += 1;
    }
    try std.testing.expect(checked > 0);
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

test "OS/2 style attributes revalidate borrowed table bytes" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = try font.styleAttributes();
    try std.testing.expectEqual(@as(u16, 400), initial.weight);
    try std.testing.expectEqual(@as(u16, 5), initial.width);

    const os2_offset = try sfntTableOffset(bytes, "OS/2");
    writeU16Test(bytes, os2_offset + 6, 10);
    try std.testing.expectError(error.BadSfnt, font.styleAttributes());

    writeU16Test(bytes, os2_offset + 6, 5);
    writeU16Test(bytes, os2_offset + 62, 0x0060);
    try std.testing.expectError(error.BadSfnt, font.styleAttributes());
}

test "OS/2 style attributes revalidate borrowed table checksum" {
    const allocator = std.testing.allocator;
    const test_font = @import("test_font.zig");

    const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Regular", "Metric Sans Regular", 400, 5, false, false);
    defer allocator.free(bytes);

    var font = try Font.parse(allocator, bytes);
    defer font.deinit();

    const initial = try font.styleAttributes();
    try std.testing.expectEqual(@as(u16, 400), initial.weight);
    try std.testing.expectEqual(@as(u16, 5), initial.width);

    const os2_offset: usize = @intCast(try sfntTableOffset(bytes, "OS/2"));
    // Keep OS/2 style metadata in its valid range while changing the borrowed
    // payload after Font.parse. The lazy API must reject the table because its
    // SFNT directory checksum no longer matches the parsed font map.
    writeU16Test(bytes, os2_offset + 4, 500);
    try std.testing.expectError(error.BadSfnt, font.styleAttributes());
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
        try updateSfntTableChecksum(bytes, "OS/2");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const attributes = try font.styleAttributes();
        try std.testing.expect(!attributes.italic);
        try std.testing.expect(!attributes.bold);
    }

    {
        const bytes = try test_font.buildNamedTtfWithStyle(allocator, "Metric Sans", "Bold", "Metric Sans Bold", 700, 5, false, true);
        defer allocator.free(bytes);
        const os2_offset = try sfntTableOffset(bytes, "OS/2");
        // REGULAR contradicts named style bits such as BOLD/ITALIC/OBLIQUE and
        // is present in legacy fonts. The named style bits remain authoritative
        // for style matching.
        writeU16Test(bytes, os2_offset + 62, 0x0060);
        try updateSfntTableChecksum(bytes, "OS/2");
        var font = try Font.parse(allocator, bytes);
        defer font.deinit();
        const attributes = try font.styleAttributes();
        try std.testing.expect(attributes.bold);
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
    const gdef_record: TableRecord = .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = 0, .offset = 0, .length = data.len };
    const gdef_checksum = sfnt.checksum.table(data, gdef_record) catch 0;
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
        .gdef = .{ .tag = .{ 'G', 'D', 'E', 'F' }, .checksum = gdef_checksum, .offset = 0, .length = data.len },
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
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn os2OnlyFont(data: []const u8, declared_length: usize) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const os2_record: TableRecord = .{ .tag = .{ 'O', 'S', '/', '2' }, .checksum = 0, .offset = 0, .length = declared_length };
    const os2_checksum = sfnt.checksum.table(data, os2_record) catch 0;
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
        .hdmx = null,
        .ltsh = null,
        .ltag = null,
        .loca = null,
        .cmap = dummy_table,
        .kern = null,
        .kerx = null,
        .mort = null,
        .morx = null,
        .os2 = .{ .tag = .{ 'O', 'S', '/', '2' }, .checksum = os2_checksum, .offset = 0, .length = declared_length },
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
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn colrOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const colr_record: TableRecord = .{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = data.len };
    const colr_checksum = sfnt.checksum.table(data, colr_record) catch 0;
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
        .colr = .{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = colr_checksum, .offset = 0, .length = data.len },
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
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn colrCpalOnlyFont(data: []const u8, colr_length: usize) Font {
    var font = colrOnlyFont(data);
    const colr_record: TableRecord = .{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = 0, .offset = 0, .length = colr_length };
    const colr_checksum = sfnt.checksum.table(data, colr_record) catch 0;
    font.colr = .{ .tag = .{ 'C', 'O', 'L', 'R' }, .checksum = colr_checksum, .offset = 0, .length = colr_length };
    const cpal_record: TableRecord = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = colr_length, .length = data.len - colr_length };
    const cpal_checksum = sfnt.checksum.table(data, cpal_record) catch 0;
    font.cpal = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = cpal_checksum, .offset = colr_length, .length = data.len - colr_length };
    return font;
}

fn cpalOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const cpal_record: TableRecord = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = 0, .offset = 0, .length = data.len };
    const cpal_checksum = sfnt.checksum.table(data, cpal_record) catch 0;
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
        .cpal = .{ .tag = .{ 'C', 'P', 'A', 'L' }, .checksum = cpal_checksum, .offset = 0, .length = data.len },
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
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn svgOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const svg_record: TableRecord = .{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = 0, .offset = 0, .length = data.len };
    const svg_checksum = sfnt.checksum.table(data, svg_record) catch 0;
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
        .svg = .{ .tag = .{ 'S', 'V', 'G', ' ' }, .checksum = svg_checksum, .offset = 0, .length = data.len },
        .sbix = null,
        .cblc = null,
        .cbdt = null,
        .eblc = null,
        .ebdt = null,
        .glyf = null,
        .cff = null,
        .cff_parsed = null,
        .cff2 = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn sbixOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const sbix_record: TableRecord = .{ .tag = .{ 's', 'b', 'i', 'x' }, .checksum = 0, .offset = 0, .length = data.len };
    const sbix_checksum = sfnt.checksum.table(data, sbix_record) catch 0;
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
        .sbix = .{ .tag = .{ 's', 'b', 'i', 'x' }, .checksum = sbix_checksum, .offset = 0, .length = data.len },
        .cblc = null,
        .cbdt = null,
        .eblc = null,
        .ebdt = null,
        .glyf = null,
        .cff = null,
        .cff_parsed = null,
        .cff2 = null,
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn fvarOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const fvar_record: TableRecord = .{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = data.len };
    const fvar_checksum = sfnt.checksum.table(data, fvar_record) catch 0;
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
        .fvar = .{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = fvar_checksum, .offset = 0, .length = data.len },
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
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn avarOnlyFont(data: []const u8) Font {
    var font = fvarOnlyFont(data);
    font.fvar = null;
    const avar_record: TableRecord = .{ .tag = .{ 'a', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = data.len };
    const avar_checksum = sfnt.checksum.table(data, avar_record) catch 0;
    font.avar = .{ .tag = .{ 'a', 'v', 'a', 'r' }, .checksum = avar_checksum, .offset = 0, .length = data.len };
    return font;
}

fn fvarAvarOnlyFont(data: []const u8, fvar_length: usize) Font {
    var font = fvarOnlyFont(data);
    const fvar_record: TableRecord = .{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = 0, .offset = 0, .length = fvar_length };
    const fvar_checksum = sfnt.checksum.table(data, fvar_record) catch 0;
    font.fvar = .{ .tag = .{ 'f', 'v', 'a', 'r' }, .checksum = fvar_checksum, .offset = 0, .length = fvar_length };
    const avar_record: TableRecord = .{ .tag = .{ 'a', 'v', 'a', 'r' }, .checksum = 0, .offset = fvar_length, .length = data.len - fvar_length };
    const avar_checksum = sfnt.checksum.table(data, avar_record) catch 0;
    font.avar = .{ .tag = .{ 'a', 'v', 'a', 'r' }, .checksum = avar_checksum, .offset = fvar_length, .length = data.len - fvar_length };
    return font;
}

fn kernOnlyFont(data: []const u8) Font {
    const empty_tables: []TableRecord = &.{};
    const empty_cmaps: []CmapSubtable = &.{};
    const dummy_table: TableRecord = .{ .tag = .{ 0, 0, 0, 0 }, .checksum = 0, .offset = 0, .length = 0 };
    const kern_record: TableRecord = .{ .tag = .{ 'k', 'e', 'r', 'n' }, .checksum = 0, .offset = 0, .length = data.len };
    const kern_checksum = sfnt.checksum.table(data, kern_record) catch 0;
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
        .hdmx = null,
        .ltsh = null,
        .ltag = null,
        .loca = null,
        .cmap = dummy_table,
        .kern = .{ .tag = .{ 'k', 'e', 'r', 'n' }, .checksum = kern_checksum, .offset = 0, .length = data.len },
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
        .cmap_subtables = empty_cmaps,
        .owned_tables = empty_tables,
        .allocator = std.testing.allocator,
    };
}

fn updateSfntTableChecksum(bytes: []u8, comptime table_tag: []const u8) FontError!void {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, 4);
    for (0..table_count) |index| {
        const record_offset = 12 + index * 16;
        if (record_offset + 16 > bytes.len) return error.BadSfnt;
        if (!std.mem.eql(u8, bytes[record_offset .. record_offset + 4], table_tag)) continue;
        const record = TableRecord{
            .tag = .{ bytes[record_offset], bytes[record_offset + 1], bytes[record_offset + 2], bytes[record_offset + 3] },
            .checksum = 0,
            .offset = try bin.readU32At(bytes, record_offset + 8),
            .length = try bin.readU32At(bytes, record_offset + 12),
        };
        const value = if (bin.tagEq(record.tag, "head"))
            try sfnt.checksum.head(bytes, record)
        else
            try sfnt.checksum.table(bytes, record);
        writeU32Test(bytes, record_offset + 4, value);
        return;
    }
    return error.MissingTable;
}

fn setSfntTableLength(bytes: []u8, comptime table_tag: []const u8, length: u32) FontError!void {
    return setSfntTableLengthAtTest(bytes, 0, table_tag, length);
}

fn setSfntTableLengthAtTest(bytes: []u8, sfnt_offset: usize, comptime table_tag: []const u8, length: u32) FontError!void {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, sfnt_offset + 4);
    for (0..table_count) |index| {
        const record_offset = sfnt_offset + 12 + index * 16;
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
    return setSfntTableOffsetAtTest(bytes, 0, table_tag, offset);
}

fn setSfntTableOffsetAtTest(bytes: []u8, sfnt_offset: usize, comptime table_tag: []const u8, offset: u32) FontError!void {
    if (table_tag.len != 4) @compileError("SFNT table tags must be four bytes");
    const table_count = try bin.readU16At(bytes, sfnt_offset + 4);
    for (0..table_count) |index| {
        const record_offset = sfnt_offset + 12 + index * 16;
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

const name_record_start_for_test: usize = 6;
const name_record_size_for_test: usize = 12;

fn nameRecordOffsetForId(bytes: []const u8, name_offset: usize, name_id: u16) FontError!usize {
    if (name_offset + 6 > bytes.len) return error.BadSfnt;
    const count = try bin.readU16At(bytes, name_offset + 2);
    for (0..count) |index| {
        const record_offset = name_offset + name_record_start_for_test + index * name_record_size_for_test;
        if (record_offset + name_record_size_for_test > bytes.len) return error.BadSfnt;
        if (try bin.readU16At(bytes, record_offset + 6) == name_id) return record_offset;
    }
    return error.InvalidName;
}

fn nameTableRecord(length: usize) TableRecord {
    return .{ .tag = .{ 'n', 'a', 'm', 'e' }, .checksum = 0, .offset = 0, .length = length };
}

fn buildMinimalTtcV2WithDsigTest(allocator: std.mem.Allocator) ![]u8 {
    const test_font = @import("test_font.zig");

    const ttf = try test_font.buildMinimalTtf(allocator);
    defer allocator.free(ttf);

    const face_offset: usize = 28;
    const dsig_offset = face_offset + ttf.len;
    var bytes = try allocator.alloc(u8, dsig_offset + 4);
    @memset(bytes, 0);
    writeTagTest(bytes, 0, "ttcf");
    writeU32Test(bytes, 4, 0x00020000);
    writeU32Test(bytes, 8, 1);
    writeU32Test(bytes, 12, face_offset);
    writeTagTest(bytes, 16, "DSIG");
    writeU32Test(bytes, 20, 4);
    writeU32Test(bytes, 24, @intCast(dsig_offset));
    @memcpy(bytes[face_offset..][0..ttf.len], ttf);
    writeTagTest(bytes, dsig_offset, "SIG!");

    const table_count = try bin.readU16At(bytes, face_offset + 4);
    for (0..table_count) |index| {
        const record_offset = face_offset + 12 + index * 16 + 8;
        const table_offset = try bin.readU32At(bytes, record_offset);
        writeU32Test(bytes, record_offset, table_offset + @as(u32, @intCast(face_offset)));
    }
    return bytes;
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
    return NameIdIndex.initForTest(name_ids);
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

fn writeMetricVariationHeaderWithOneMap(bytes: []u8, map_offset: usize, store_offset: usize) void {
    writeU16Test(bytes, 0, 1);
    writeU16Test(bytes, 2, 0);
    writeU32Test(bytes, 4, @intCast(store_offset)); // ItemVariationStore offset.
    writeU32Test(bytes, 8, @intCast(map_offset)); // First DeltaSetIndexMap offset.
    writeDeltaSetIndexMapWithOneEntry(bytes, map_offset);
}

fn writeDeltaSetIndexMapWithOneEntry(bytes: []u8, offset: usize) void {
    bytes[offset + 0] = 0; // format 0.
    bytes[offset + 1] = 0; // one-byte entry, one inner-index bit.
    writeU16Test(bytes, offset + 2, 1); // mapCount.
    bytes[offset + 4] = 0; // outerIndex 0, innerIndex 0.
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
