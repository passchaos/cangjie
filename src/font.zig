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
const hinting = @import("font/hinting/root.zig");
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
const font_metrics = @import("font/metrics/root.zig");
const presentation_metrics = font_metrics.presentation;
const outline_modules = @import("font/outline/root.zig");
const cff_outline = outline_modules.cff;
const outline_geometry = outline_modules.geometry;
const outline_numeric = outline_modules.numeric;
const truetype_outline = outline_modules.truetype;
const bitmap_mod = @import("font/tables/bitmap/root.zig");
const cmap_mod = @import("font/tables/cmap/root.zig");
const color_tables = @import("font/tables/color/root.zig");
const kerning_tables = @import("font/tables/kerning/root.zig");
const kern_mod = kerning_tables.kern;
const layout_tables = @import("font/tables/layout/root.zig");
const gdef_mod = layout_tables.gdef;
const jstf_mod = layout_tables.jstf;
const core_tables = @import("font/tables/core/root.zig");
const head_mod = core_tables.head;
const maxp_mod = core_tables.maxp;
const metadata_tables = @import("font/tables/metadata/root.zig");
const os2_mod = metadata_tables.os2;
const post_mod = metadata_tables.post;
const metric_tables = @import("font/tables/metrics/root.zig");
const variation_tables = @import("font/tables/variations/root.zig");
const avar_mod = variation_tables.avar;
const fvar_mod = variation_tables.fvar;
const gvar_validation = variation_tables.gvar;
const metric_variation_validation = variation_tables.metrics;
const stat_mod = variation_tables.stat;
const truetype_tables = @import("font/tables/truetype/root.zig");
const loca_mod = truetype_tables.loca;
const glyf_mod = truetype_tables.glyf;
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

const Transform = outline_geometry.Transform;
const clampF32ToI16 = outline_numeric.clampF32ToI16;
const clampF32ToU16 = outline_numeric.clampF32ToU16;
const clampI32ToI16 = outline_numeric.clampI32ToI16;
const clampI32ToU16 = outline_numeric.clampI32ToU16;
const roundOpenTypeF32 = outline_numeric.roundOpenType;
const roundedGlyphPosition = outline_numeric.roundedGlyphPosition;

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
    InvalidMarkGlyphSet,
    CompoundDepthExceeded,
    InvalidName,
} || cff_mod.CffError || gpos_mod.GposError || gsub_mod.GsubError || std.mem.Allocator.Error || error{EndOfStream};

pub const FontFormat = core_tables.Format;

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
pub const TrueTypeHintingInstance = hinting.Instance;
pub const TrueTypeHintingTarget = hinting.Target;
pub const TrueTypeHintingError = hinting.Error;
pub const TrueTypePointTransaction = hinting.PointTransaction;
pub const TrueTypePixelOutline = hinting.PixelOutline;
pub const VarcInfo = varc_mod.Info;

pub const FontTableInfo = struct {
    tag: [4]u8,
    checksum: u32,
    offset: usize,
    length: usize,
};

pub const FontHeaderInfo = core_tables.HeaderInfo;
pub const MaxProfileInfo = core_tables.MaxProfileInfo;

pub const MetricHeaderInfo = metric_tables.Header;
pub const HorizontalMetricInfo = metric_tables.Horizontal;

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

pub const VerticalMetricInfo = metric_tables.Vertical;

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

pub const PostInfo = post_mod.Info;

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
pub const JstfInfo = jstf_mod.Info;
pub const JstfLanguageInfo = jstf_mod.Language;
pub const JstfLookupListInfo = jstf_mod.LookupList;
pub const JstfMaxLookupInfo = jstf_mod.MaxLookup;
pub const JstfPriorityInfo = jstf_mod.Priority;
pub const JstfScriptInfo = jstf_mod.Script;

pub const GaspRange = gasp_mod.Range;
pub const GaspInfo = gasp_mod.Info;

pub const KerxInfo = kerx_mod.Info;
pub const KerxPairInfo = kerx_mod.Pair;
pub const KerxSubtableInfo = kerx_mod.Subtable;
pub const MorxChainInfo = morx_mod.Chain;
pub const MorxFeatureInfo = morx_mod.Feature;
pub const MorxInfo = morx_mod.Info;
pub const MorxSubtableInfo = morx_mod.Subtable;

pub const KernTableDialect = kern_mod.Dialect;
pub const KernSubtableInfo = kern_mod.Subtable;
pub const KernInfo = kern_mod.Info;

pub const CharmapInfo = cmap_mod.Info;

pub const CharmapMapping = cmap_iter.Mapping;

pub const NameId = name_mod.NameId;
pub const NameEncoding = name_mod.Encoding;
pub const NameLanguageTagInfo = name_mod.LanguageTagInfo;
pub const NameRecordInfo = name_mod.RecordInfo;

pub const StyleAttributes = os2_mod.Style;
pub const Os2Info = os2_mod.Info;

pub const FontDecorationMetricSource = presentation_metrics.Source;
pub const ScaledFontDecorationMetrics = presentation_metrics.ScaledDecoration;
pub const ScaledFontScriptMetrics = presentation_metrics.ScaledScript;
pub const FontScriptMetrics = presentation_metrics.Script;
pub const FontDecorationMetrics = presentation_metrics.Decoration;

pub const VerticalMetrics = metric_tables.Vertical;

pub const VariationAxis = fvar_mod.Axis;
pub const VariationCoordinate = fvar_mod.Coordinate;

pub const VariationSequenceKind = cmap_variation.SequenceKind;

pub const VariationInstance = fvar_mod.Instance;

pub const StatDesignAxis = stat_mod.DesignAxis;
pub const StatAxisValue = stat_mod.AxisValue;
pub const StatAxisValueCoordinate = stat_mod.AxisValueCoordinate;

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

pub const GlyphClass = gdef_mod.GlyphClass;
pub const LigatureCaret = gdef_mod.LigatureCaret;
pub const AttachmentPoint = gdef_mod.AttachmentPoint;

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

const CmapSubtable = cmap_mod.Subtable;

pub const GdefLookupMetadata = struct {
    glyph_classes: ?[]u16 = null,
    mark_attach_classes: ?[]u16 = null,
    mark_filtering_sets: ?[][]glyph_mod.GlyphId = null,
    variation_store_data: ?[]u8 = null,
    variation_store: ?gpos_mod.VariationStore = null,

    pub fn deinit(self: *GdefLookupMetadata, allocator: std.mem.Allocator) void {
        if (self.glyph_classes) |classes| allocator.free(classes);
        if (self.mark_attach_classes) |classes| allocator.free(classes);
        if (self.mark_filtering_sets) |sets| {
            gdef_mod.freeMarkSets(allocator, sets);
        }
        if (self.variation_store_data) |data| allocator.free(data);
        self.* = .{};
    }

    pub fn glyphClass(self: GdefLookupMetadata, glyph_id: glyph_mod.GlyphId) GlyphClass {
        const classes = self.glyph_classes orelse return .unclassified;
        const index: usize = glyph_id;
        if (index >= classes.len) return .unclassified;
        return std.enums.fromInt(GlyphClass, classes[index]) orelse .unclassified;
    }

    fn applyToGsubOptions(self: GdefLookupMetadata, options: *gsub_mod.runtime.Options) void {
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
        return try kern_mod.kerningAfterProof(
            self.font.data,
            kern,
            left,
            right,
        );
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

const LigatureCaretContourContext = struct {
    font: *const Font,
    allocator: std.mem.Allocator,
};

fn resolveLigatureCaretContourPoint(
    opaque_context: *const anyopaque,
    glyph_id: glyph_mod.GlyphId,
    point_index: u16,
    normalized_coords: []const f32,
) gdef_mod.LigatureCaretError!?f32 {
    const context: *const LigatureCaretContourContext =
        @ptrCast(@alignCast(opaque_context));
    const point = context.font.glyphContourPoint(
        context.allocator,
        glyph_id,
        point_index,
        normalized_coords,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.BadSfnt,
    };
    // Horizontal text uses the ordinary glyf origin (0, 0), so format 2's
    // origin adjustment is exactly the point's x coordinate.
    return if (point) |value| value.x else null;
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
    jstf: ?TableRecord,
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
        const jstf = sfnt.find(records, "JSTF");
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
        const format = try maxp_mod.selectFormat(
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
        try head_mod.validate(data, head, format);
        try maxp_mod.validate(data, maxp, format);
        const head_info = try head_mod.info(data, head);
        const maxp_info = try maxp_mod.info(data, maxp);

        const glyph_count = maxp_info.glyph_count;
        if (post) |post_table| try post_mod.validate(data, post_table, glyph_count, .{
            .compat_ttc_face = is_ttc_face,
            // Glyph names are optional metadata and do not affect cmap,
            // shaping, metrics, or outlines. Keep parse-time validation
            // structural; the public glyphName API performs strict text
            // validation before exposing a borrowed custom name.
            .custom_name_validation = .structural_only,
        });
        const horizontal_header = if (has_horizontal_metrics)
            try metric_tables.validateHorizontal(
                data,
                hhea.?,
                hmtx.?,
                glyph_count,
            )
        else
            null;
        _ = metric_tables.validateVertical(
            data,
            glyph_count,
            vhea,
            vmtx,
        ) catch |err| switch (err) {
            // Vertical metrics are optional for horizontal UI text. Some widely
            // deployed fallback CJK fonts ship a present-but-unusable vhea/vmtx
            // pair (for example, zero vertical line metrics) while their cmap,
            // hhea/hmtx and glyf outlines are valid. Accept those fonts for
            // horizontal shaping/rasterization; callers that explicitly request
            // vertical metrics still revalidate and receive InvalidMetrics.
            error.InvalidMetrics => {},
            else => return err,
        };
        if (os2) |os2_table| try os2_mod.validate(data, os2_table);
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
            try fvar_mod.validate(data, fvar_table);
            break :blk @intCast((try fvar_mod.info(data, fvar_table)).axis_count);
        } else null;
        if (avar) |avar_table| try avar_mod.validate(data, avar_table, fvar);
        const cvt_value_count = if (cvt) |cvt_table| try validateCvtTable(cvt_table) else null;
        if (fpgm) |fpgm_table| try validateTrueTypeProgramTable(data, fpgm_table);
        if (prep) |prep_table| try validateTrueTypeProgramTable(data, prep_table);
        if (kern) |kern_table| {
            try kern_mod.validate(data, kern_table, glyph_count);
        }
        if (kerx) |kerx_table| try validateKerxTable(data, kerx_table, glyph_count);
        if (hdmx) |hdmx_table| try validateHdmxTable(data, hdmx_table, glyph_count);
        if (ltsh) |ltsh_table| try validateLtshTable(data, ltsh_table, glyph_count);
        if (ltag) |ltag_table| try validateLtagTable(data, ltag_table);
        if (gasp) |gasp_table| try validateGaspTable(data, gasp_table);

        const units_per_em = head_info.units_per_em;
        const index_to_loc_format = head_info.index_to_loc_format;
        const number_of_h_metrics =
            if (horizontal_header) |header| header.long_metric_count else 0;
        const ascender = if (horizontal_header) |header|
            header.ascender
        else
            @as(i16, @intCast(units_per_em));
        const descender =
            if (horizontal_header) |header| header.descender else 0;
        const line_gap =
            if (horizontal_header) |header| header.line_gap else 0;
        const cff_parsed: ?CffParsedInfo = if (format == .opentype_cff and cff != null) blk: {
            const cff_table = cff.?;
            const parsed = try cff_mod.parse(data[cff_table.offset .. cff_table.offset + cff_table.length]);
            if (parsed.info.charstrings_count != glyph_count) return error.BadSfnt;
            break :blk parsed;
        } else null;
        if (format == .opentype_cff and cff2 != null) try validateCff2Table(data, cff2.?);
        if (format == .truetype and has_glyf_outlines) {
            const limits = try maxp_info.trueTypeLimits();
            try loca_mod.validate(
                data,
                loca.?,
                glyf.?,
                glyph_count,
                index_to_loc_format,
            );
            try glyf_mod.validate(
                allocator,
                data,
                loca.?,
                glyf.?,
                glyph_count,
                index_to_loc_format,
                .{
                    .max_points = limits.max_points,
                    .max_contours = limits.max_contours,
                    .max_component_elements = limits.max_component_elements,
                    .max_component_depth = limits.max_component_depth,
                },
            );
        }
        const gvar_target_context: ?GvarGlyphTargetContext = if (format == .truetype and has_glyf_outlines)
            .{ .loca = loca.?, .glyf = glyf.?, .index_to_loc_format = index_to_loc_format }
        else
            null;
        try validateVariationDataTablesWithCvar(data, glyph_count, fvar, gvar, hvar, mvar, vvar, cvar, cvt_value_count, gvar_target_context);
        try validateVariationNameReferences(allocator, data, fvar, stat, name, .{ .compat_ttc_face = is_ttc_face });
        if (gdef) |gdef_table| {
            try gdef_mod.validate(
                data,
                gdef_table,
                glyph_count,
                if (fvar_axis_count) |count| count else null,
            );
        }
        if (gsub) |gsub_table| try gsub_mod.validateGlyphBoundsForShaping(data, gsub_table.offset, gsub_table.length, glyph_count);
        if (gpos) |gpos_table| try gpos_mod.validateGlyphBounds(data, gpos_table.offset, gpos_table.length, glyph_count);
        if (jstf) |jstf_table| {
            try jstf_mod.validate(
                data,
                jstf_table,
                gsub,
                gpos,
                glyph_count,
            );
        }
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
        const cmap_subtables = try cmap_mod.parse(
            allocator,
            data,
            cmap,
            glyph_count,
        );
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
            .jstf = jstf,
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
        const fvar_info = try fvar_mod.info(self.data, fvar);
        try sfnt.checksum.validate(self.data, gvar);
        try gvar_mod.validate(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count);
        return try gvar_mod.info(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count);
    }

    /// Read per-glyph metadata from the optional TrueType `gvar` table.
    pub fn gvarGlyphInfo(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?GvarGlyphInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gvar = self.gvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        const fvar_info = try fvar_mod.info(self.data, fvar);
        try sfnt.checksum.validate(self.data, gvar);
        return try gvar_mod.glyphInfo(self.data, gvar.offset, gvar.length, self.glyph_count, fvar_info.axis_count, glyph_id);
    }

    /// Read tuple metadata for a glyph variation entry in the optional `gvar` table.
    pub fn gvarTupleInfo(self: *const Font, glyph_id: glyph_mod.GlyphId, tuple_index: usize) FontError!?GvarTupleInfo {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gvar = self.gvar orelse return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        const fvar_info = try fvar_mod.info(self.data, fvar);
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
            .revalidate => (try fvar_mod.info(self.data, fvar)).axis_count,
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
        return cff_outline.boundsFromCff2(bounds);
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
            outline.bounds = cff_outline.boundsFromCff2(bounds_info);
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
        try fvar_mod.validate(self.data, fvar);
        try sfnt.checksum.validate(self.data, cvt);
        const cvt_value_count = try validateCvtTable(cvt);
        try sfnt.checksum.validate(self.data, cvar);
        const fvar_info = try fvar_mod.info(self.data, fvar);
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

    /// Execute the embedded TrueType font and control-value programs for one
    /// PPEM. Mutable VM state is owned by the result while fpgm/prep bytes stay
    /// borrowed from this face.
    ///
    /// Glyph point-zone execution is not exposed by this first hinting slice;
    /// size programs containing point-only opcodes return
    /// `UnsupportedHintInstruction` instead of silently ignoring them. The
    /// current instance represents the default variation location; cvar and
    /// GETVARIATION join the API with normalized-coordinate ownership.
    pub fn hintingInstance(
        self: *const Font,
        allocator: std.mem.Allocator,
        ppem: u16,
        target: TrueTypeHintingTarget,
    ) (FontError || hinting.Error)!TrueTypeHintingInstance {
        if (self.format != .truetype) return error.UnsupportedGlyph;
        const head_info = try self.headInfo();
        const maxp_info = try self.maxpInfo();
        const cvt_data = if (self.cvt) |cvt| blk: {
            try sfnt.checksum.validate(self.data, cvt);
            _ = try validateCvtTable(cvt);
            break :blk self.data[cvt.offset .. cvt.offset + cvt.length];
        } else &.{};
        const font_program = if (self.fpgm) |fpgm| blk: {
            try sfnt.checksum.validate(self.data, fpgm);
            try validateTrueTypeProgramTable(self.data, fpgm);
            break :blk self.data[fpgm.offset .. fpgm.offset + fpgm.length];
        } else &.{};
        const control_value_program = if (self.prep) |prep| blk: {
            try sfnt.checksum.validate(self.data, prep);
            try validateTrueTypeProgramTable(self.data, prep);
            break :blk self.data[prep.offset .. prep.offset + prep.length];
        } else &.{};
        return hinting.Instance.init(
            allocator,
            .{
                .face_identity = @intFromPtr(self),
                .units_per_em = head_info.units_per_em,
                .font_program = font_program,
                .control_value_program = control_value_program,
                .control_value_data = cvt_data,
                .limits = .{
                    .max_storage = maxp_info.max_storage orelse
                        return error.BadSfnt,
                    .max_function_defs = maxp_info.max_function_defs orelse
                        return error.BadSfnt,
                    .max_instruction_defs = maxp_info.max_instruction_defs orelse
                        return error.BadSfnt,
                    .max_stack_elements = maxp_info.max_stack_elements orelse
                        return error.BadSfnt,
                    .max_twilight_points = maxp_info.max_twilight_points orelse
                        return error.BadSfnt,
                },
            },
            ppem,
            target,
        );
    }

    /// Decode one default-instance simple glyf outline into a raw point
    /// transaction suitable for TrueType glyph-program execution.
    ///
    /// Compound and variable glyphs remain explicit errors until their
    /// component/gvar deltas can enter the same atomic transaction.
    pub fn hintingPointTransaction(
        self: *const Font,
        allocator: std.mem.Allocator,
        instance: *const TrueTypeHintingInstance,
        glyph_id: glyph_mod.GlyphId,
    ) (FontError || hinting.Error)!TrueTypePointTransaction {
        if (self.format != .truetype) return error.UnsupportedHintGlyph;
        if (instance.source.face_identity != @intFromPtr(self)) {
            return error.StaleHintingInstance;
        }
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        // Revalidate the complete outline stack because the transaction
        // exposes borrowed glyph bytecode and point topology to the VM.
        const loca = self.loca orelse return error.MissingTable;
        const glyf = self.glyf orelse return error.MissingTable;
        try sfnt.checksum.validate(self.data, self.maxp);
        try sfnt.checksum.validate(self.data, loca);
        try sfnt.checksum.validate(self.data, glyf);
        const limits = try (try self.maxpInfo()).trueTypeLimits();
        try loca_mod.validate(
            self.data,
            loca,
            glyf,
            self.glyph_count,
            self.index_to_loc_format,
        );
        try glyf_mod.validate(
            allocator,
            self.data,
            loca,
            glyf,
            self.glyph_count,
            self.index_to_loc_format,
            .{
                .max_points = limits.max_points,
                .max_contours = limits.max_contours,
                .max_component_elements = limits.max_component_elements,
                .max_component_depth = limits.max_component_depth,
            },
        );
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return error.UnsupportedHintGlyph;
        const contour_count = try bin.readI16At(data, 0);
        if (contour_count < 0 or self.gvar != null) {
            return error.UnsupportedHintGlyph;
        }
        const horizontal = try self.horizontalMetrics(glyph_id);
        const bounds = try self.glyphBoundsFromParsedTables(glyph_id);
        const vertical = (try self.verticalMetrics(glyph_id)) orelse
            VerticalMetrics{
                .advance_height = self.units_per_em,
                .top_side_bearing = 0,
            };
        return hinting.outline.decodeSimple(
            allocator,
            glyph_id,
            data,
            @intCast(contour_count),
            .{
                .bounds = bounds,
                .advance_width = horizontal.advance_width,
                .left_side_bearing = horizontal.left_side_bearing,
                .vertical_advance = vertical.advance_height,
                .top_side_bearing = vertical.top_side_bearing,
            },
            instance.scale_16_16,
        );
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
        try fvar_mod.validate(self.data, fvar);
        try sfnt.checksum.validate(self.data, mvar);
        const fvar_info = try fvar_mod.info(self.data, fvar);
        try metric_variation_validation.validateMvar(
            self.data,
            mvar,
            fvar_info.axis_count,
        );
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
        const table = switch (kind) {
            .hvar => self.hvar orelse return null,
            .vvar => self.vvar orelse return null,
        };
        const fvar = self.fvar orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.data, fvar);
        try fvar_mod.validate(self.data, fvar);
        try sfnt.checksum.validate(self.data, table);
        const fvar_info = try fvar_mod.info(self.data, fvar);
        switch (kind) {
            .hvar => try metric_variation_validation.validateHvar(
                self.data,
                table,
                fvar_info.axis_count,
            ),
            .vvar => try metric_variation_validation.validateVvar(
                self.data,
                table,
                fvar_info.axis_count,
            ),
        }
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

    /// Read validated OpenType `JSTF` scripts, languages, and priorities.
    pub fn jstfInfo(
        self: *const Font,
        allocator: std.mem.Allocator,
    ) FontError!?JstfInfo {
        const jstf = self.jstf orelse return null;
        try sfnt.checksum.validate(self.data, jstf);
        return try jstf_mod.info(
            allocator,
            self.data,
            jstf,
            self.gsub,
            self.gpos,
            self.glyph_count,
        );
    }

    pub fn freeJstfInfo(
        _: *const Font,
        allocator: std.mem.Allocator,
        info_value: JstfInfo,
    ) void {
        jstf_mod.free(allocator, info_value);
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
        try head_mod.validate(self.data, self.head, self.format);
        return try head_mod.info(self.data, self.head);
    }

    /// Read validated metadata from the SFNT `maxp` table.
    ///
    /// TrueType outlines expose the complete version-1.0 maximum-profile
    /// payload; CFF-backed OpenType faces expose the version-0.5 glyph count
    /// and leave TrueType-only maxima as null.
    pub fn maxpInfo(self: *const Font) FontError!MaxProfileInfo {
        try sfnt.checksum.validate(self.data, self.maxp);
        try maxp_mod.validate(self.data, self.maxp, self.format);
        return try maxp_mod.info(self.data, self.maxp);
    }

    /// Read validated metadata from the SFNT `hhea` table.
    pub fn horizontalHeaderInfo(self: *const Font) FontError!MetricHeaderInfo {
        const hhea = self.hhea orelse return error.MissingTable;
        const hmtx = self.hmtx orelse return error.MissingTable;
        try sfnt.checksum.validate(self.data, hhea);
        return try metric_tables.validateHorizontal(
            self.data,
            hhea,
            hmtx,
            self.glyph_count,
        );
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
        return (try metric_tables.validateVertical(
            self.data,
            self.glyph_count,
            vhea,
            vmtx,
        )).?;
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
        try cmap_mod.validatePublicScalar(codepoint);
        const subtable = try self.subtableForCharmap(charmap);
        if (!cmap_mod.supportsGlyphLookup(subtable.format)) {
            return error.UnsupportedCmap;
        }
        return try self.glyphIndexInSubtable(subtable, codepoint);
    }

    /// Return the first non-missing mapping in a selected charmap.
    pub fn firstCharmapMapping(self: *const Font, charmap: CharmapInfo) FontError!?CharmapMapping {
        return try self.nextMappingAfter(charmap, null);
    }

    /// Return the next non-missing mapping after `codepoint` in a selected charmap.
    pub fn nextCharmapMapping(self: *const Font, charmap: CharmapInfo, codepoint: u21) FontError!?CharmapMapping {
        try cmap_mod.validatePublicScalar(codepoint);
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
        try cmap_mod.validatePublicScalar(codepoint);
        const chosen = self.selectedCmapSubtable() orelse return error.UnsupportedCmap;
        return try self.glyphIndexInSubtable(chosen, codepoint);
    }

    fn nextMappingAfter(self: *const Font, charmap: CharmapInfo, after: ?u21) FontError!?CharmapMapping {
        const subtable = try self.subtableForCharmap(charmap);
        if (!cmap_mod.supportsGlyphLookup(subtable.format)) {
            return error.UnsupportedCmap;
        }
        try self.validateCmapLookupSubtable(subtable);
        if (cmap_mod.isMacintoshRoman(subtable)) {
            return try self.nextMacintoshRomanMappingAfter(subtable, after);
        }
        return try cmap_iter.next(self.data, subtable.offset, subtable.length, subtable.format, after);
    }

    fn glyphIndexInSubtable(self: *const Font, subtable: CmapSubtable, codepoint: u21) FontError!glyph_mod.GlyphId {
        try self.validateCmapLookupSubtable(subtable);
        const mapped_codepoint: u21 = if (cmap_mod.isMacintoshRoman(subtable))
            macintosh_encoding.unicodeToRomanByte(
                codepoint,
                (try cmap_mod.language(
                    self.data,
                    subtable.offset,
                    subtable.length,
                    subtable.format,
                )) orelse 0,
            ) orelse return 0
        else
            codepoint;
        return try self.glyphIndexInValidatedSubtable(subtable, mapped_codepoint);
    }

    fn glyphIndexInValidatedSubtable(self: *const Font, subtable: CmapSubtable, codepoint: u21) FontError!glyph_mod.GlyphId {
        return try cmap_mod.glyph(self.data, subtable, codepoint);
    }

    fn nextMacintoshRomanMappingAfter(self: *const Font, subtable: CmapSubtable, after: ?u21) FontError!?CharmapMapping {
        const language = (try cmap_mod.language(
            self.data,
            subtable.offset,
            subtable.length,
            subtable.format,
        )) orelse 0;
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
            if (!cmap_mod.supportsGlyphLookup(subtable.format)) continue;
            if (best == null or
                cmap_mod.score(subtable) > cmap_mod.score(best.?))
            {
                best = subtable;
            }
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
            .language = try cmap_mod.language(
                self.data,
                subtable.offset,
                subtable.length,
                subtable.format,
            ),
        };
    }

    fn validateCmapLookupSubtable(self: *const Font, subtable: CmapSubtable) FontError!void {
        const relative_offset = try cmap_mod.relativeOffset(
            self.cmap,
            subtable.offset,
        );
        if (subtable.length > self.cmap.length - relative_offset) return error.BadSfnt;
        try sfnt.checksum.validate(self.data, self.cmap);
        try cmap_mod.validateCachedEncodingRecord(
            self.data,
            self.cmap,
            subtable,
            relative_offset,
        );
        const format = try bin.readU16At(self.data, subtable.offset);
        if (format != subtable.format) return error.BadSfnt;
        const length = try cmap_mod.subtableLength(
            self.data,
            self.cmap,
            relative_offset,
            format,
        );
        if (length != subtable.length) return error.BadSfnt;

        // Font keeps borrowed SFNT bytes and cached cmap directory entries.
        // Re-running the checksum, directory, structural, and maxp glyph-id
        // checks before lookup prevents post-parse byte mutations from
        // returning a glyph id that the originally validated cmap could not
        // have produced.
        try cmap_mod.validate(
            self.data,
            subtable.offset,
            subtable.length,
            subtable.format,
            subtable.platform_id,
            subtable.encoding_id,
        );
        try cmap_mod.validateGlyphIds(
            self.data,
            subtable.offset,
            subtable.length,
            subtable.format,
            self.glyph_count,
        );
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
            metric.* = try metric_tables.horizontal(
                self.data,
                hmtx,
                metric_count,
                @intCast(glyph_index),
            );
        }
        return metrics;
    }

    fn validateHorizontalMetricsForRead(self: *const Font) FontError!u16 {
        const hhea = self.hhea orelse return error.MissingTable;
        const hmtx = self.hmtx orelse return error.MissingTable;
        const header = try metric_tables.validateHorizontal(
            self.data,
            hhea,
            hmtx,
            self.glyph_count,
        );
        const current_metric_count = header.long_metric_count;
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
        return try metric_tables.horizontal(
            self.data,
            hmtx,
            metric_count,
            glyph_id,
        );
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
            metric.* = try metric_tables.vertical(
                self.data,
                context.vmtx.?,
                metric_count,
                @intCast(glyph_index),
            );
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
        const header = (try metric_tables.validateVertical(
            self.data,
            self.glyph_count,
            vhea,
            vmtx,
        )) orelse return .{
            .vhea = null,
            .vmtx = null,
            .metric_count = null,
        };
        try sfnt.checksum.validate(self.data, vhea);
        try sfnt.checksum.validate(self.data, vmtx);
        return .{
            .vhea = vhea,
            .vmtx = vmtx,
            .metric_count = header.long_metric_count,
        };
    }

    /// Return vertical metrics following the vmtx compression rule. Fonts
    /// without a paired vhea/vmtx table return null; malformed or post-parse
    /// mutated vertical metrics report InvalidMetrics instead of falling back
    /// to horizontal advances.
    pub fn verticalMetrics(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!?VerticalMetrics {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const context = try self.verticalMetricTablesForRead();
        const metric_count = context.metric_count orelse return null;
        return try metric_tables.vertical(
            self.data,
            context.vmtx.?,
            metric_count,
            glyph_id,
        );
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
        try cmap_mod.validatePublicScalar(codepoint);
        try cmap_mod.validatePublicVariationSelector(variation_selector);
        for (self.cmap_subtables) |subtable| {
            if (subtable.format != 14) continue;
            try self.validateCmapLookupSubtable(subtable);
            return switch (try cmap_mod.variationGlyph(
                self.data,
                subtable.offset,
                subtable.length,
                codepoint,
                variation_selector,
                self.glyph_count,
            )) {
                .none => null,
                .explicit_glyph => |glyph_id| glyph_id,
                .use_default => try self.glyphIndex(codepoint),
            };
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
        try cmap_mod.validatePublicScalar(codepoint);
        const subtable = self.variationSelectorSubtable() orelse return try allocator.alloc(u21, 0);
        try self.validateCmapLookupSubtable(subtable);
        return try cmap_variation.selectorsForCodepoint(allocator, self.data, subtable.offset, subtable.length, codepoint);
    }

    /// Enumerate base codepoints that are defined for a variation selector.
    pub fn variationCodepointsForSelector(self: *const Font, allocator: std.mem.Allocator, variation_selector: u21) FontError![]u21 {
        try cmap_mod.validatePublicVariationSelector(variation_selector);
        const subtable = self.variationSelectorSubtable() orelse return try allocator.alloc(u21, 0);
        try self.validateCmapLookupSubtable(subtable);
        return try cmap_variation.codepointsForSelector(allocator, self.data, subtable.offset, subtable.length, variation_selector);
    }

    /// Classify a Unicode variation sequence as default, non-default, or absent.
    pub fn variationSequenceKind(self: *const Font, codepoint: u21, variation_selector: u21) FontError!?VariationSequenceKind {
        try cmap_mod.validatePublicScalar(codepoint);
        try cmap_mod.validatePublicVariationSelector(variation_selector);
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
        try kern_mod.validate(self.data, kern, self.glyph_count);
        return try kern_mod.kerningAfterProof(
            self.data,
            kern,
            left,
            right,
        );
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
        try kern_mod.validate(self.data, kern, self.glyph_count);
        return try kern_mod.info(allocator, self.data, kern);
    }

    pub fn freeKernInfo(_: *const Font, allocator: std.mem.Allocator, info: KernInfo) void {
        kern_mod.free(allocator, info);
    }

    fn applyGsub(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator) FontError!void {
        return try self.applyGsubWithOptions(glyphs, allocator, .{});
    }

    /// Apply GSUB to a mutable glyph-id stream. GDEF glyph classes are expanded
    /// into a dense temporary array so lookup flags can skip bases, ligatures,
    /// or marks consistently across all lookup formats.
    fn applyGsubWithOptions(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options) FontError!void {
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

    fn applyGsubWithOptionsUsingGdef(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
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

    fn applyGsubWithOptionsUsingGdefForShaping(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
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

    fn applyGsubWithOptionsUsingGdefAfterProof(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
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
        options: gsub_mod.runtime.Options,
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

    fn selectGsubLookupsForShaping(self: *const Font, allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError![]u16 {
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
        options: gsub_mod.runtime.Options,
        gdef_metadata: GdefLookupMetadata,
    ) FontError![]u16 {
        const gsub = self.gsub orelse return try allocator.alloc(u16, 0);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.feature.selectedLookupIndices(
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
        options: gsub_mod.runtime.Options,
        gdef_metadata: GdefLookupMetadata,
    ) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.feature.applySelectedSource(
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

    fn hasGsubRandomFeatureWithAcceleratorsForShaping(self: *const Font, accelerators: []const gsub_mod.acceleration.Lookup) ?bool {
        const gsub = self.gsub orelse return false;
        return gsub_mod.acceleration.hasRandomFeature(self.data, gsub.offset, gsub.length, accelerators);
    }

    fn gsubLookupAcceleratorsForShaping(self: *const Font, allocator: std.mem.Allocator) FontError![]gsub_mod.acceleration.Lookup {
        const gsub = self.gsub orelse return try allocator.alloc(gsub_mod.acceleration.Lookup, 0);
        try sfnt.checksum.validate(self.data, gsub);
        return try gsub_mod.acceleration.build(self.data, gsub.offset, gsub.length, allocator);
    }

    fn gsubFeatureLookupPlanForShaping(self: *const Font, allocator: std.mem.Allocator, applications: []const gsub_mod.feature.Application, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!gsub_mod.feature.LookupPlan {
        const gsub = self.gsub orelse return .{ .entries = try allocator.alloc(gsub_mod.feature.LookupPlanEntry, 0) };
        try sfnt.checksum.validate(self.data, gsub);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.feature.buildLookupPlan(self.data, gsub.offset, gsub.length, applications, allocator, gsub_options);
    }

    fn gsubMergedFeatureLookupPlanForShaping(self: *const Font, allocator: std.mem.Allocator, applications: []const gsub_mod.feature.Application, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!gsub_mod.feature.MergedLookupPlan {
        const gsub = self.gsub orelse return .{
            .lookups = try allocator.alloc(gsub_mod.feature.MergedLookup, 0),
            .lookup_offsets = try allocator.alloc(usize, 0),
        };
        try sfnt.checksum.validate(self.data, gsub);
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        return try gsub_mod.feature.buildMergedLookupPlan(self.data, gsub.offset, gsub.length, applications, allocator, gsub_options);
    }

    fn applyGsubFeatureWithOptions(self: *const Font, feature_tag: u32, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options) FontError!void {
        return try self.applyGsubFeatureSequenceWithOptions(&.{.{ .tag = feature_tag }}, glyphs, allocator, options);
    }

    fn applyGsubSourceFeatureWithOptions(self: *const Font, feature_tag: u32, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options) FontError!void {
        return try self.applyGsubFeatureSequenceWithOptions(&.{.{ .tag = feature_tag, .source_scoped = true }}, glyphs, allocator, options);
    }

    fn applyGsubFeatureSequenceWithOptions(self: *const Font, applications: []const gsub_mod.feature.Application, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try gsub_mod.validateGlyphBoundsForShaping(self.data, gsub.offset, gsub.length, self.glyph_count);
        var gdef_metadata = try self.gdefLookupMetadataForShaping(allocator);
        defer gdef_metadata.deinit(allocator);
        try self.applyGsubFeatureSequenceWithOptionsUsingGdef(applications, glyphs, allocator, options, gdef_metadata);
    }

    fn applyGsubFeatureSequenceWithOptionsUsingGdef(self: *const Font, applications: []const gsub_mod.feature.Application, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try gsub_mod.validateGlyphBoundsForShaping(self.data, gsub.offset, gsub.length, self.glyph_count);
        try self.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(applications, glyphs, allocator, options, gdef_metadata);
        try self.validateGlyphRun(glyphs.items);
    }

    fn applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(self: *const Font, applications: []const gsub_mod.feature.Application, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        try sfnt.checksum.validate(self.data, gsub);
        try self.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(applications, glyphs, allocator, options, gdef_metadata);
    }

    fn applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(self: *const Font, applications: []const gsub_mod.feature.Application, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.feature.applySequence(self.data, gsub.offset, gsub.length, applications, glyphs, allocator, gsub_options);
    }

    fn applyGsubFeatureLookupPlanUsingGdefAfterProof(self: *const Font, plan: gsub_mod.feature.LookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.feature.applyLookupPlan(self.data, gsub.offset, gsub.length, plan, glyphs, allocator, gsub_options);
    }

    /// Continue an internal multi-stage shaping run after its glyph/source
    /// metadata was validated by the first stage. SingleSubst format 1 may
    /// temporarily leave maxp's renderable range before a later lookup maps the
    /// ID back, so this boundary proves metadata cardinality rather than final
    /// glyph bounds. The complete shaper validates the run before GPOS/metrics.
    /// Keep this narrower than the public defensive entry point above: callers
    /// must not pass a freshly constructed or externally mutated glyph run.
    fn applyGsubFeatureLookupPlanUsingGdefAfterRunProof(self: *const Font, plan: gsub_mod.feature.LookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.feature.applyLookupPlanAfterMetadataProof(
            self.data,
            gsub.offset,
            gsub.length,
            plan,
            glyphs,
            allocator,
            gsub_options,
        );
    }

    fn applyGsubMergedFeatureLookupPlanUsingGdefAfterProof(self: *const Font, plan: gsub_mod.feature.MergedLookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        try self.validateGlyphRun(glyphs.items);
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.feature.applyMergedLookupPlan(self.data, gsub.offset, gsub.length, plan, glyphs, allocator, gsub_options);
    }

    fn applyGsubMergedFeatureLookupPlanUsingGdefAfterRunProof(self: *const Font, plan: gsub_mod.feature.MergedLookupPlan, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options, gdef_metadata: GdefLookupMetadata) FontError!void {
        const gsub = self.gsub orelse return;
        var gsub_options = options;
        gsub_options.assume_validated = true;
        gdef_metadata.applyToGsubOptions(&gsub_options);
        try gsub_mod.feature.applyMergedLookupPlanAfterMetadataProof(
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

    fn applyAatSubstitutionForShaping(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options) FontError!void {
        if (self.morx != null) return try self.applyMorxForShaping(glyphs, allocator, options);
        try self.validateGlyphRun(glyphs.items);
        const mort = self.mort orelse return;
        try sfnt.checksum.validate(self.data, mort);
        try aat_mort.apply(allocator, self.data, mort.offset, mort.length, self.glyph_count, glyphs, options);
    }

    fn applyMorxForShaping(self: *const Font, glyphs: *std.ArrayList(glyph_mod.GlyphId), allocator: std.mem.Allocator, options: gsub_mod.runtime.Options) FontError!void {
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

    fn collectJstfMaxAdjustmentsForShaping(
        self: *const Font,
        lookup_offsets: []const usize,
        glyphs: []const glyph_mod.GlyphId,
        adjustments: *std.ArrayList(gpos_mod.Adjustment),
        allocator: std.mem.Allocator,
        options: gpos_mod.LookupOptions,
        gdef_metadata: GdefLookupMetadata,
    ) FontError!void {
        try self.validateGlyphRun(glyphs);
        const jstf = self.jstf orelse return;
        try sfnt.checksum.validate(self.data, jstf);
        var gpos_options = options;
        gpos_options.assume_validated = true;
        gpos_options.lookup_accelerators = null;
        gpos_options.selected_lookups = null;
        gdef_metadata.applyToGposOptions(&gpos_options);
        try gpos_mod.collectDetachedLookups(
            self.data,
            jstf.offset,
            jstf.length,
            lookup_offsets,
            glyphs,
            adjustments,
            allocator,
            gpos_options,
        );
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
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const table = self.data[gdef.offset .. gdef.offset + gdef.length];

        const glyph_class_def_offset = gdef_header.glyph_class_def_offset;
        if (glyph_class_def_offset != 0) {
            try gdef_mod.validateChildOffset(
                glyph_class_def_offset,
                gdef.length,
                gdef_header.length,
            );
            const classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(classes);
            try gdef_mod.readClassDefDense(
                table,
                glyph_class_def_offset,
                self.glyph_count,
                classes,
                true,
            );
            metadata.glyph_classes = classes;
        }

        const mark_attach_class_def_offset =
            gdef_header.mark_attach_class_def_offset;
        if (mark_attach_class_def_offset != 0) {
            try gdef_mod.validateChildOffset(
                mark_attach_class_def_offset,
                gdef.length,
                gdef_header.length,
            );
            const attach_classes = try allocator.alloc(u16, self.glyph_count);
            errdefer allocator.free(attach_classes);
            try gdef_mod.readClassDefDense(
                table,
                mark_attach_class_def_offset,
                self.glyph_count,
                attach_classes,
                false,
            );
            metadata.mark_attach_classes = attach_classes;
        }

        if (try self.markFilteringSets(allocator)) |sets| {
            metadata.mark_filtering_sets = sets;
        }
        if (gdef_header.item_variation_store_offset) |raw_offset| {
            const store_offset: usize = @intCast(raw_offset);
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
        try post_mod.validate(self.data, post, self.glyph_count, .{
            .custom_name_validation = .structural_only,
        });
        return try post_mod.info(self.data, post);
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
        try post_mod.validate(self.data, post, self.glyph_count, .{
            .custom_name_validation = .allow_empty,
        });
        return try post_mod.glyphName(self.data, post, glyph_id);
    }

    pub fn decorationMetrics(self: *const Font) FontError!FontDecorationMetrics {
        if (self.post) |post| {
            try sfnt.checksum.validate(self.data, post);
            try post_mod.validate(self.data, post, self.glyph_count, .{
                .custom_name_validation = .structural_only,
            });
        }
        if (self.os2) |os2| {
            try sfnt.checksum.validate(self.data, os2);
            _ = try os2_mod.style(self.data, os2);
        }
        return try presentation_metrics.decoration(
            self.data,
            self.post,
            self.os2,
            self.units_per_em,
            self.ascender,
            self.descender,
        );
    }

    pub fn scaledDecorationMetrics(self: *const Font, font_size: f32) FontError!ScaledFontDecorationMetrics {
        return (try self.decorationMetrics()).scale(font_size, self.units_per_em);
    }

    pub fn scriptMetrics(self: *const Font) FontError!?FontScriptMetrics {
        const os2 = self.os2 orelse return null;
        try sfnt.checksum.validate(self.data, os2);
        _ = try os2_mod.style(self.data, os2);
        return try presentation_metrics.script(self.data, os2);
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
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const glyph_class_def_offset = gdef_header.glyph_class_def_offset;
        if (glyph_class_def_offset == 0) return .unclassified;
        // Font owns only borrowed bytes. Re-check the same top-level child
        // offset contract enforced at parse time so post-parse mutations cannot
        // make GDEF public APIs reinterpret header fields as ClassDef payloads.
        try gdef_mod.validateChildOffset(
            glyph_class_def_offset,
            gdef.length,
            gdef_header.length,
        );
        const class = try gdef_mod.classValue(
            self.data[gdef.offset .. gdef.offset + gdef.length],
            glyph_class_def_offset,
            glyph_id,
        );
        try gdef_mod.validateGlyphClassValue(class);
        return @enumFromInt(class);
    }

    /// Enumerate all valid glyph IDs assigned to one GDEF GlyphClassDef class.
    ///
    /// `.unclassified` is the complement of every explicit class assignment
    /// across `0..glyph_count`; missing GDEF/ClassDef therefore returns all
    /// glyph IDs for that class and an empty slice for the other classes.
    pub fn glyphsInClass(
        self: *const Font,
        allocator: std.mem.Allocator,
        requested: GlyphClass,
    ) FontError![]glyph_mod.GlyphId {
        try gdef_mod.validateGlyphClassValue(@intFromEnum(requested));
        const gdef = self.gdef orelse
            return self.glyphClassFallback(allocator, requested);
        try sfnt.checksum.validate(self.data, gdef);
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const offset = gdef_header.glyph_class_def_offset;
        if (offset == 0) {
            return self.glyphClassFallback(allocator, requested);
        }
        try gdef_mod.validateChildOffset(
            offset,
            gdef.length,
            gdef_header.length,
        );
        try gdef_mod.validate(
            self.data,
            gdef,
            self.glyph_count,
            try self.gdefVariationAxisCount(gdef_header),
        );
        return gdef_mod.glyphsInClass(
            allocator,
            self.data[gdef.offset .. gdef.offset + gdef.length],
            offset,
            self.glyph_count,
            requested,
        ) catch |err| switch (err) {
            error.BadSfnt => return error.BadSfnt,
            error.EndOfStream => return error.EndOfStream,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    pub fn markAttachClass(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!u16 {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gdef = self.gdef orelse return 0;
        try sfnt.checksum.validate(self.data, gdef);
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const mark_attach_class_def_offset =
            gdef_header.mark_attach_class_def_offset;
        if (mark_attach_class_def_offset == 0) return 0;
        try gdef_mod.validateChildOffset(
            mark_attach_class_def_offset,
            gdef.length,
            gdef_header.length,
        );
        return try gdef_mod.classValue(
            self.data[gdef.offset .. gdef.offset + gdef.length],
            mark_attach_class_def_offset,
            glyph_id,
        );
    }

    /// Return the GDEF AttachList contour-point indexes for one glyph.
    ///
    /// The returned slice is allocator-owned and remains sorted in authored
    /// order. Missing GDEF/AttachList data and uncovered glyphs return an empty
    /// slice.
    pub fn attachmentPoints(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
    ) FontError![]AttachmentPoint {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        const gdef = self.gdef orelse
            return allocator.alloc(AttachmentPoint, 0);
        try sfnt.checksum.validate(self.data, gdef);
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const attach_list_offset = gdef_header.attach_list_offset;
        if (attach_list_offset == 0) {
            return allocator.alloc(AttachmentPoint, 0);
        }
        try gdef_mod.validateChildOffset(
            attach_list_offset,
            gdef.length,
            gdef_header.length,
        );
        // This public reader retains the borrowed-byte lifecycle contract used
        // by glyph classes and ligature carets: post-parse mutations cannot
        // bypass maxp, Coverage, child-offset, or point-order validation.
        try gdef_mod.validate(
            self.data,
            gdef,
            self.glyph_count,
            try self.gdefVariationAxisCount(gdef_header),
        );
        return gdef_mod.readAttachmentPoints(
            allocator,
            self.data[gdef.offset .. gdef.offset + gdef.length],
            attach_list_offset,
            glyph_id,
        ) catch |err| switch (err) {
            error.BadSfnt => return error.BadSfnt,
            error.EndOfStream => return error.EndOfStream,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    /// Return GDEF LigCaretList positions for one glyph.
    ///
    /// CaretValue format 1 uses its authored coordinate, format 2 resolves a
    /// TrueType contour point at the requested variation instance, and format
    /// 3 evaluates VariationIndex against GDEF 1.3's ItemVariationStore.
    /// Ordinary Device deltas are PPEM-dependent and intentionally remain zero
    /// in this resolution-independent font-unit API.
    pub fn ligatureCarets(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        normalized_coords: []const f32,
    ) FontError![]LigatureCaret {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        const gdef = self.gdef orelse
            return try allocator.alloc(LigatureCaret, 0);
        try sfnt.checksum.validate(self.data, gdef);
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const lig_caret_list_offset = gdef_header.lig_caret_list_offset;
        if (lig_caret_list_offset == 0) {
            return try allocator.alloc(LigatureCaret, 0);
        }
        try gdef_mod.validateChildOffset(
            lig_caret_list_offset,
            gdef.length,
            gdef_header.length,
        );
        const table = self.data[gdef.offset .. gdef.offset + gdef.length];
        const variation_axis_count =
            try self.gdefVariationAxisCount(gdef_header);
        // Revalidate the complete child grammar against maxp before lazy reads;
        // Font borrows bytes and callers may mutate them after parse.
        try gdef_mod.validate(
            self.data,
            gdef,
            self.glyph_count,
            variation_axis_count,
        );
        const context = LigatureCaretContourContext{
            .font = self,
            .allocator = allocator,
        };
        return gdef_mod.readLigatureCarets(
            allocator,
            table,
            lig_caret_list_offset,
            glyph_id,
            .{
                .normalized_coords = normalized_coords,
                .item_variation_store_offset = if (gdef_header.item_variation_store_offset) |offset|
                    if (offset == 0) null else @intCast(offset)
                else
                    null,
                .contour_context = &context,
                .resolve_contour_point = resolveLigatureCaretContourPoint,
            },
        ) catch |err| switch (err) {
            error.UnavailableContourPoint, error.NonCanonicalCaretOrder => try allocator.alloc(LigatureCaret, 0),
            error.BadSfnt => return error.BadSfnt,
            error.EndOfStream => return error.EndOfStream,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    fn gdefVariationAxisCount(
        self: *const Font,
        gdef_header: gdef_mod.Header,
    ) FontError!?usize {
        const offset =
            gdef_header.item_variation_store_offset orelse return null;
        if (offset == 0) return null;
        const fvar = self.fvar orelse return error.BadSfnt;
        try sfnt.checksum.validate(self.data, fvar);
        return (try fvar_mod.info(self.data, fvar)).axis_count;
    }

    fn glyphClassFallback(
        self: *const Font,
        allocator: std.mem.Allocator,
        requested: GlyphClass,
    ) FontError![]glyph_mod.GlyphId {
        if (requested != .unclassified) {
            return allocator.alloc(glyph_mod.GlyphId, 0);
        }
        const glyphs = try allocator.alloc(
            glyph_mod.GlyphId,
            self.glyph_count,
        );
        for (glyphs, 0..) |*glyph_id, index| glyph_id.* = @intCast(index);
        return glyphs;
    }

    pub fn markGlyphSetCount(self: *const Font) FontError!usize {
        const resolved = try self.gdefMarkSetsView();
        return if (resolved) |view|
            try gdef_mod.markSetCount(view.table, view.offset)
        else
            0;
    }

    pub fn markGlyphSet(
        self: *const Font,
        allocator: std.mem.Allocator,
        set_index: usize,
    ) FontError![]glyph_mod.GlyphId {
        const view = try self.gdefMarkSetsView() orelse
            return error.InvalidMarkGlyphSet;
        return gdef_mod.readMarkSet(
            allocator,
            view.table,
            view.offset,
            set_index,
        ) catch |err| switch (err) {
            error.InvalidMarkGlyphSet => return error.InvalidMarkGlyphSet,
            error.BadSfnt => return error.BadSfnt,
            error.EndOfStream => return error.EndOfStream,
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    const GdefMarkSetsView = struct {
        table: []const u8,
        offset: usize,
    };

    fn gdefMarkSetsView(self: *const Font) FontError!?GdefMarkSetsView {
        const gdef = self.gdef orelse return null;
        try sfnt.checksum.validate(self.data, gdef);
        const gdef_header = try gdef_mod.header(self.data, gdef);
        const offset =
            gdef_header.mark_glyph_sets_def_offset orelse return null;
        if (offset == 0) return null;
        try gdef_mod.validateChildOffset(
            offset,
            gdef.length,
            gdef_header.length,
        );
        try gdef_mod.validate(
            self.data,
            gdef,
            self.glyph_count,
            try self.gdefVariationAxisCount(gdef_header),
        );
        return .{
            .table = self.data[gdef.offset .. gdef.offset + gdef.length],
            .offset = offset,
        };
    }

    fn markFilteringSets(self: *const Font, allocator: std.mem.Allocator) FontError!?[][]glyph_mod.GlyphId {
        const gdef = self.gdef orelse return null;
        try sfnt.checksum.validate(self.data, gdef);
        const gdef_header = try gdef_mod.header(self.data, gdef);
        // MarkGlyphSetsDef was added in GDEF 1.2.  Version 1.0/1.1 tables may
        // still be longer than the base header because their earlier offsets
        // point to subtables placed immediately after it; reading byte 12 as a
        // mark-set offset in those fonts misinterprets subtable data and can
        // make otherwise valid fonts fail shaping.
        const mark_glyph_sets_def_offset =
            gdef_header.mark_glyph_sets_def_offset orelse return null;
        if (mark_glyph_sets_def_offset == 0) return null;
        try gdef_mod.validateChildOffset(
            mark_glyph_sets_def_offset,
            gdef.length,
            gdef_header.length,
        );
        const table = self.data[gdef.offset .. gdef.offset + gdef.length];
        // Mark-filtering sets are assembled lazily for GSUB/GPOS lookup flags
        // from borrowed SFNT bytes. Recheck the parse-time maxp glyph bound
        // contract here so post-parse mutations cannot inject an out-of-range
        // mark set that shaping would later treat as a valid filter class.
        try gdef_mod.validateMarkSets(
            table,
            mark_glyph_sets_def_offset,
            self.glyph_count,
        );
        return try gdef_mod.readMarkSets(
            allocator,
            table,
            mark_glyph_sets_def_offset,
        );
    }

    pub fn styleAttributes(self: *const Font) FontError!StyleAttributes {
        const os2 = self.os2 orelse return .{};
        try sfnt.checksum.validate(self.data, os2);
        return try os2_mod.style(self.data, os2);
    }

    /// Read validated metadata from the optional SFNT `OS/2` table.
    pub fn os2Info(self: *const Font) FontError!?Os2Info {
        const os2 = self.os2 orelse return null;
        try sfnt.checksum.validate(self.data, os2);
        return try os2_mod.info(self.data, os2);
    }

    pub fn variationAxes(self: *const Font, allocator: std.mem.Allocator) FontError![]VariationAxis {
        const fvar = self.fvar orelse return try allocator.alloc(VariationAxis, 0);
        // Font owns borrowed bytes. Re-apply the full fvar table contract at
        // this public API boundary so post-parse mutations cannot expose axis
        // records whose reserved flags, duplicate tags, or instance payloads
        // would have been rejected during Font.parse.
        try sfnt.checksum.validate(self.data, fvar);
        try fvar_mod.validate(self.data, fvar);
        if (self.name) |name| {
            // This API exposes only axes. A stale named-instance label must not
            // prevent design coordinates from reaching otherwise valid fvar,
            // avar, and glyph-variation data; variationInstances() separately
            // keeps the complete instance-name contract strict.
            const name_index = try readNameIdIndex(self.data, name);
            try fvar_mod.validateAxisNameReferences(self.data, fvar, &name_index);
        }
        return try fvar_mod.readAxes(allocator, self.data, fvar);
    }

    pub fn mapVariationCoordinate(self: *const Font, axis_index: usize, normalized: f32) FontError!f32 {
        // This remains a public normalized-coordinate contract even when the
        // face has no avar table and mapping is therefore the identity.
        try validateNormalizedVariationCoordinate(normalized);
        const avar = self.avar orelse return normalized;
        try sfnt.checksum.validate(self.data, avar);
        if (self.fvar) |fvar| try sfnt.checksum.validate(self.data, fvar);
        return try avar_mod.map(
            self.data,
            avar,
            self.fvar,
            axis_index,
            normalized,
        );
    }

    pub fn normalizedVariationCoordinates(self: *const Font, allocator: std.mem.Allocator, coordinates: []const VariationCoordinate) FontError![]f32 {
        const axes = try self.variationAxes(allocator);
        defer allocator.free(axes);
        try fvar_mod.validateCoordinates(axes, coordinates);

        const normalized = try allocator.alloc(f32, axes.len);
        errdefer allocator.free(normalized);
        for (axes, 0..) |axis, index| {
            const user_value = fvar_mod.coordinateValueForAxis(axis, coordinates) orelse axis.default_value;
            const mapped = try self.mapVariationCoordinate(index, axis.normalize(user_value));
            // OpenType variation consumers operate at F2Dot14 locations.
            // HarfBuzz first rounds fvar/avar design coordinates into this
            // domain; retaining an unquantized f32 here can move a gvar phantom
            // metric across a half-unit boundary even though GDEF/HVAR later
            // quantize the same location independently.
            normalized[index] = fvar_mod.quantizeNormalized(mapped);
        }
        return normalized;
    }

    pub fn variationInstances(self: *const Font, allocator: std.mem.Allocator) FontError![]VariationInstance {
        const fvar = self.fvar orelse return try allocator.alloc(VariationInstance, 0);
        try sfnt.checksum.validate(self.data, fvar);
        try fvar_mod.validate(self.data, fvar);
        if (self.name) |name| {
            const name_index = try readNameIdIndex(self.data, name);
            try fvar_mod.validateNameReferences(self.data, fvar, &name_index);
        }
        return try fvar_mod.readInstances(allocator, self.data, fvar);
    }

    pub fn freeVariationInstances(_: *const Font, allocator: std.mem.Allocator, instances: []VariationInstance) void {
        fvar_mod.freeInstances(allocator, instances);
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
        try stat_mod.validate(allocator, self.data, stat, self.fvar, name_index);
        return try stat_mod.readElidedFallbackNameId(self.data, stat);
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
        try stat_mod.validate(allocator, self.data, stat, self.fvar, name_index);
        return try stat_mod.readDesignAxes(allocator, self.data, stat);
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
        try stat_mod.validate(allocator, self.data, stat, self.fvar, name_index);
        return try stat_mod.readAxisValues(allocator, self.data, stat);
    }

    pub fn freeStatAxisValues(_: *const Font, allocator: std.mem.Allocator, values: []StatAxisValue) void {
        stat_mod.freeAxisValues(allocator, values);
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
        try loca_mod.validate(self.data, loca, glyf, self.glyph_count, self.index_to_loc_format);

        const locations = try allocator.alloc(GlyphLocationInfo, self.glyph_count);
        errdefer allocator.free(locations);
        for (locations, 0..) |*location, glyph_index| {
            const start = try loca_mod.offset(self.data, loca, self.index_to_loc_format, glyph_index);
            const end = try loca_mod.offset(self.data, loca, self.index_to_loc_format, glyph_index + 1);
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
            try maxp_mod.validate(self.data, self.maxp, self.format);
            try loca_mod.validate(self.data, loca, glyf, self.glyph_count, self.index_to_loc_format);
            return try self.glyphBoundsFromParsedTables(glyph_id);
        }
        if (self.cff2) |cff2| {
            try sfnt.checksum.validate(self.data, cff2);
            try validateCff2Table(self.data, cff2);
            const bounds = (try cff2_mod.charStringBoundsInfo(self.data, cff2.offset, cff2.length, glyph_id, self.glyph_count)) orelse return error.InvalidGlyph;
            return cff_outline.boundsFromCff2(bounds);
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
            try maxp_mod.validate(self.data, self.maxp, self.format);
            const limits =
                try (try maxp_mod.info(self.data, self.maxp)).trueTypeLimits();
            try loca_mod.validate(self.data, loca, glyf, self.glyph_count, self.index_to_loc_format);
            // The SFNT bytes are borrowed from the caller. Re-run the same glyf
            // grammar and component-graph validation enforced by Font.parse so
            // a post-parse mutation cannot be observed only by the particular
            // glyph whose outline is requested.
            try glyf_mod.validate(
                allocator,
                self.data,
                loca,
                glyf,
                self.glyph_count,
                self.index_to_loc_format,
                .{
                    .max_points = limits.max_points,
                    .max_contours = limits.max_contours,
                    .max_component_elements = limits.max_component_elements,
                    .max_component_depth = limits.max_component_depth,
                },
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
        if (try truetype_outline.simple.append(&outline, null, data, @intCast(contour_count), Transform.identity(), variation)) |phantom| {
            truetype_outline.variation.applyMetricDeltas(&outline, default_bounds, metrics, phantom);
        }
        return outline;
    }

    fn simpleGlyphVariationContext(self: *const Font, glyph_id: glyph_mod.GlyphId, normalized_coords: []const f32, read_mode: OutlineReadMode) FontError!?truetype_outline.simple.Variation {
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
            truetype_outline.variation.applyMetricDeltas(&outline, default_bounds, metrics, phantom);
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

    fn glyphContourPoint(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        point_index: usize,
        normalized_coords: []const f32,
    ) FontError!?glyph_mod.Point {
        return self.glyphContourPointForReadMode(
            allocator,
            glyph_id,
            point_index,
            normalized_coords,
            .revalidate,
        );
    }

    fn glyphContourPointForShaping(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        point_index: usize,
        normalized_coords: []const f32,
    ) FontError!?glyph_mod.Point {
        return self.glyphContourPointForReadMode(
            allocator,
            glyph_id,
            point_index,
            normalized_coords,
            .parsed,
        );
    }

    fn glyphContourPointForReadMode(
        self: *const Font,
        allocator: std.mem.Allocator,
        glyph_id: glyph_mod.GlyphId,
        point_index: usize,
        normalized_coords: []const f32,
        read_mode: OutlineReadMode,
    ) FontError!?glyph_mod.Point {
        if (glyph_id >= self.glyph_count) return error.InvalidGlyph;
        try validateNormalizedVariationCoordinateSlice(normalized_coords);
        if (self.format != .truetype) return null;
        if (read_mode.shouldRevalidate()) {
            try self.validateContourPointTables(allocator);
        }
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return null;

        const metrics = try self.horizontalMetricsForReadMode(
            glyph_id,
            read_mode,
        );
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
                read_mode,
            );
        }
        return if (point_index < points.items.len) points.items[point_index] else null;
    }

    fn validateContourPointTables(
        self: *const Font,
        allocator: std.mem.Allocator,
    ) FontError!void {
        const loca = self.loca orelse return error.MissingTable;
        const glyf = self.glyf orelse return error.MissingTable;
        try sfnt.checksum.validate(self.data, self.maxp);
        try sfnt.checksum.validate(self.data, loca);
        try sfnt.checksum.validate(self.data, glyf);
        try maxp_mod.validate(self.data, self.maxp, self.format);
        const limits =
            try (try maxp_mod.info(self.data, self.maxp)).trueTypeLimits();
        try loca_mod.validate(
            self.data,
            loca,
            glyf,
            self.glyph_count,
            self.index_to_loc_format,
        );
        try glyf_mod.validate(
            allocator,
            self.data,
            loca,
            glyf,
            self.glyph_count,
            self.index_to_loc_format,
            .{
                .max_points = limits.max_points,
                .max_contours = limits.max_contours,
                .max_component_elements = limits.max_component_elements,
                .max_component_depth = limits.max_component_depth,
            },
        );
        if (self.gvar) |gvar| {
            try sfnt.checksum.validate(self.data, gvar);
            const axis_count = try self.fvarAxisCountForReadMode(.revalidate);
            try gvar_validation.validate(
                self.data,
                gvar,
                self.glyph_count,
                axis_count,
                .{
                    .loca = loca,
                    .glyf = glyf,
                    .index_to_loc_format = self.index_to_loc_format,
                },
            );
        }
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
                outline.bounds = cff_outline.boundsFromCff2(bounds_info);
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
            const child_transform = parent_transform.mul(outline_geometry.fromVarc(component_transform));
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
        outline_geometry.transformPathCommands(outline.commands.items[command_start..], transform);
    }

    fn gvarTargetCount(self: *const Font, glyph_id: glyph_mod.GlyphId) FontError!usize {
        if (self.format != .truetype) return error.UnsupportedGlyph;
        const loca = self.loca orelse return error.MissingTable;
        const glyf = self.glyf orelse return error.MissingTable;
        return try gvar_validation.targetCount(self.data, .{
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
        return try loca_mod.offset(
            self.data,
            loca,
            self.index_to_loc_format,
            glyph_id,
        );
    }

    fn appendGlyphOutline(self: *const Font, outline: *glyph_mod.GlyphOutline, points: ?*std.ArrayList(glyph_mod.Point), glyph_id: glyph_mod.GlyphId, transform: Transform, depth: u8) FontError!void {
        if (depth > 8) return error.CompoundDepthExceeded;
        const data = try self.glyphData(glyph_id);
        if (data.len == 0) return;
        const contour_count = try bin.readI16At(data, 0);
        if (contour_count >= 0) {
            // Simple glyf outlines store contour end points plus compressed
            // point deltas. Compound outlines recurse into component glyphs.
            _ = try truetype_outline.simple.append(outline, points, data, @intCast(contour_count), transform, null);
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
            _ = try truetype_outline.simple.append(outline, points, data, @intCast(contour_count), transform, variation);
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
            const component = try truetype_outline.compound.readComponent(&r);
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
            if (!component.hasMore()) break;
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
        point_match: glyf_mod.PointMatch,
    ) FontError!void {
        const child_point_start = points.items.len;
        const child_command_start = outline.commands.items.len;
        try self.appendGlyphOutline(outline, points, component_glyph, transform, depth);
        try truetype_outline.compound.placePointMatched(outline, points, parent_point_start, child_point_start, child_command_start, point_match);
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
            const component = try truetype_outline.compound.readComponent(&r);
            switch (component.placement) {
                .offset => |offset| {
                    const component_delta = if (maybe_deltas) |deltas| truetype_outline.variation.deltaForPoint(deltas, component_index) else gvar_mod.Point{ .x = 0, .y = 0 };
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
                    try truetype_outline.compound.placePointMatched(outline, points, parent_point_start, child_point_start, child_command_start, point_match);
                },
            }
            if (!component.hasMore()) break;
        }
    }
};

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
    pub const collectJstfMaxAdjustmentsForShaping = Font.collectJstfMaxAdjustmentsForShaping;
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

fn validateKerxTable(data: []const u8, kerx: TableRecord, glyph_count: u16) FontError!void {
    return try kerx_mod.validate(data, kerx.offset, kerx.length, glyph_count);
}

fn validateMorxTable(data: []const u8, morx: TableRecord, glyph_count: u16) FontError!void {
    return try morx_mod.validate(data, morx.offset, morx.length, glyph_count);
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
        fvar_mod.validateAxisNameReferences(data, fvar_table, name_index) catch |err| switch (err) {
            error.InvalidName => if (!options.compat_ttc_face) return err,
            else => return err,
        };
    }
    if (stat) |stat_table| {
        stat_mod.validate(allocator, data, stat_table, fvar, name_index) catch |err| switch (err) {
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

const GvarGlyphTargetContext = gvar_validation.TargetContext;

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
    const fvar_info = try fvar_mod.info(data, fvar orelse return error.BadSfnt);
    if (gvar) |table| {
        try gvar_validation.validate(
            data,
            table,
            glyph_count,
            fvar_info.axis_count,
            gvar_target_context,
        );
    }
    if (hvar) |table| {
        try metric_variation_validation.validateHvar(
            data,
            table,
            fvar_info.axis_count,
        );
    }
    if (vvar) |table| {
        try metric_variation_validation.validateVvar(
            data,
            table,
            fvar_info.axis_count,
        );
    }
    if (mvar) |table| {
        try metric_variation_validation.validateMvar(
            data,
            table,
            fvar_info.axis_count,
        );
    }
    if (cvar) |table| try validateCvarTable(data, table, fvar_info.axis_count, cvt_value_count orelse return error.BadSfnt);
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
        (try fvar_mod.info(data, fvar orelse return error.BadSfnt)).axis_count
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
