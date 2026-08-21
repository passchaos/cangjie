//! Bounded, preserve-GID TrueType subsetting for document embedding.
//!
//! The subset keeps the source glyph-count and glyph IDs stable while making
//! every unretained `glyf` entry empty. This deliberately trades a larger
//! `loca`/metric domain for a simple and auditable contract: callers can keep
//! already-shaped glyph IDs and PDF CIDToGIDMap values without rewriting any
//! text. Compound components are retained transitively.

const std = @import("std");

const bin = @import("../../binary.zig");
const core_api = @import("../../api/font/metadata/core/root.zig");
const face_mod = @import("../face/root.zig");
const compound = @import("../tables/truetype/glyf/compound.zig");
const font_mod = @import("../../font.zig");
const glyph_mod = @import("../../glyph.zig");

pub const GlyphId = glyph_mod.GlyphId;

pub const Options = struct {
    /// Caller-supplied glyph IDs before `.notdef` and compound closure.
    max_requested_glyphs: usize = 65_535,
    /// Complete retained set, including glyph zero and compound components.
    max_retained_glyphs: usize = 65_535,
    /// Total compound edges visited while computing the closure.
    max_component_edges: usize = 1_000_000,
    /// Conservative source-font maximum accepted from `maxp`.
    max_component_depth: u16 = 64,
    /// Default-cmap records scanned while rebuilding a selected-only cmap.
    max_cmap_mappings: usize = 1_000_000,
    max_output_bytes: usize = 64 * 1024 * 1024,
    /// Keep fvar/avar/gvar and metric-variation tables. The preserve-GID
    /// contract leaves glyph domains stable, so these tables remain valid for
    /// retained glyphs while empty unretained outlines are unreachable by cmap.
    preserve_variations: bool = true,
    /// Rebuild retained cmap format-14 default/non-default UVS records.
    preserve_unicode_variation_sequences: bool = true,
    /// Retain COLRv0 base/layer records and close over every referenced layer
    /// glyph. COLRv1 remains unsupported because its paint graph requires a
    /// distinct recursive closure and serializer.
    preserve_color_layers: bool = true,
    /// Retain validated SVG documents that cover retained glyph IDs. Documents
    /// are emitted as one-glyph records so removed IDs are never advertised.
    preserve_svg_documents: bool = true,
    /// Retain Apple sbix PNG strikes. Location-table CBDT/EBDT families remain
    /// unsupported until their index-subtable rewrite is implemented.
    preserve_sbix_strikes: bool = true,
};

pub const Result = struct {
    allocator: std.mem.Allocator,
    program: []u8,
    retained_glyphs: []GlyphId,
    source_glyph_count: u16,

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.program);
        self.allocator.free(self.retained_glyphs);
        self.* = undefined;
    }

    /// Transfer the generated program into the common owning Face wrapper.
    /// Retained-glyph evidence is released because its ownership remains a
    /// subset-build concern, while the returned face owns the program bytes.
    pub fn intoOwnedFace(self: *Result) !@import("../../api/font/container.zig").OwnedFace {
        const owned = try @import("../../api/font/container.zig").OwnedFace
            .adoptSfnt(self.allocator, self.program);
        self.allocator.free(self.retained_glyphs);
        self.program = &.{};
        self.retained_glyphs = &.{};
        self.* = undefined;
        return owned;
    }
};

const Mapping = struct {
    codepoint: u21,
    glyph_id: GlyphId,
};

const VariationMapping = struct {
    selector: u21,
    codepoint: u21,
    glyph_id: GlyphId,
    kind: font_mod.VariationSequenceKind,
};

const TablePayload = struct {
    tag: [4]u8,
    data: []const u8,
};

const ModifiedTables = struct {
    allocator: std.mem.Allocator,
    head: []u8,
    cmap: []u8,
    glyf: []u8,
    loca: []u8,
    colr: ?[]u8,
    svg: ?[]u8,
    sbix: ?[]u8,

    fn deinit(self: *ModifiedTables) void {
        self.allocator.free(self.head);
        self.allocator.free(self.cmap);
        self.allocator.free(self.glyf);
        self.allocator.free(self.loca);
        if (self.colr) |colr| self.allocator.free(colr);
        if (self.svg) |svg| self.allocator.free(svg);
        if (self.sbix) |sbix| self.allocator.free(sbix);
        self.* = undefined;
    }
};

/// Build a deterministic standalone TrueType subset while preserving GIDs.
///
/// The face and `glyph_ids` are borrowed. The result owns both its program and
/// sorted retained-GID evidence. Color/bitmap/SVG/VARC outline indirections are
/// rejected for now because they require additional glyph-closure grammars.
pub fn trueTypeAlloc(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    glyph_ids: []const GlyphId,
    options: Options,
) !Result {
    try validateOptions(options);
    if (face.properties().format != .truetype)
        return error.UnsupportedFontSubset;
    if (glyph_ids.len > options.max_requested_glyphs)
        return error.FontSubsetGlyphLimitExceeded;

    const core = core_api.inspect(face);
    const maxp = try core.maxProfile();
    if (maxp.glyph_count == 0) return error.UnsupportedFontSubset;
    if ((maxp.max_component_depth orelse return error.UnsupportedFontSubset) >
        options.max_component_depth)
    {
        return error.FontSubsetComponentLimitExceeded;
    }

    const tables = try core.tables(allocator);
    defer allocator.free(tables);
    try validateTableProfile(tables);
    const has_colr_v0 = try validateColorProfile(
        face,
        tables,
        options.preserve_color_layers,
    );
    const glyf_info = findTable(tables, "glyf") orelse
        return error.UnsupportedFontSubset;

    const glyf_source = (try core.tableData("glyf".*)) orelse
        return error.UnsupportedFontSubset;
    const locations = try core.glyphLocations(allocator);
    defer allocator.free(locations);
    if (locations.len != maxp.glyph_count) return error.InvalidFontSubset;

    const retained = try allocator.alloc(bool, maxp.glyph_count);
    defer allocator.free(retained);
    @memset(retained, false);
    var retained_ids = try std.ArrayList(GlyphId).initCapacity(allocator, @min(@as(usize, maxp.glyph_count), glyph_ids.len + 1));
    defer retained_ids.deinit(allocator);
    var closure = try std.ArrayList(GlyphId).initCapacity(
        allocator,
        glyph_ids.len + 1,
    );
    defer closure.deinit(allocator);
    if (try retainGlyph(allocator, &retained_ids, retained, 0, options)) {
        closure.appendAssumeCapacity(0);
    }
    for (glyph_ids) |glyph_id| {
        if (glyph_id >= maxp.glyph_count) return error.InvalidFontSubsetGlyph;
        if (try retainGlyph(
            allocator,
            &retained_ids,
            retained,
            glyph_id,
            options,
        )) {
            try closure.append(allocator, glyph_id);
        }
    }

    var component_edges: usize = 0;
    var cursor: usize = 0;
    while (cursor < closure.items.len) : (cursor += 1) {
        const glyph_id = closure.items[cursor];
        if (has_colr_v0) {
            const layers = try face.color().layers(allocator, glyph_id);
            defer allocator.free(layers);
            for (layers) |layer| {
                if (try retainGlyph(
                    allocator,
                    &retained_ids,
                    retained,
                    layer.glyph_id,
                    options,
                )) {
                    try closure.append(allocator, layer.glyph_id);
                }
            }
        }
        const glyph_data = try glyphBytes(
            glyf_source,
            glyf_info.offset,
            locations[glyph_id],
        );
        if (glyph_data.len == 0) continue;
        if (glyph_data.len < 10) return error.InvalidFontSubset;
        if (try bin.readI16At(glyph_data, 0) >= 0) continue;

        const links = try compound.readLinks(
            allocator,
            glyph_data,
            maxp.glyph_count,
        );
        defer allocator.free(links.components);
        component_edges = std.math.add(
            usize,
            component_edges,
            links.components.len,
        ) catch return error.FontSubsetComponentLimitExceeded;
        if (component_edges > options.max_component_edges)
            return error.FontSubsetComponentLimitExceeded;
        for (links.components) |component| {
            if (try retainGlyph(
                allocator,
                &retained_ids,
                retained,
                component.glyph,
                options,
            )) {
                try closure.append(allocator, component.glyph);
            }
        }
    }

    const mappings = try selectedMappingsAlloc(
        allocator,
        face,
        retained,
        options.max_cmap_mappings,
    );
    defer allocator.free(mappings);
    const variation_mappings = if (options.preserve_unicode_variation_sequences)
        try selectedVariationMappingsAlloc(
            allocator,
            face,
            retained,
            options.max_cmap_mappings,
        )
    else
        try allocator.alloc(VariationMapping, 0);
    defer allocator.free(variation_mappings);

    var modified = try buildModifiedTables(
        allocator,
        face,
        glyf_source,
        glyf_info.offset,
        locations,
        retained,
        mappings,
        variation_mappings,
        has_colr_v0,
        options.preserve_svg_documents and findTable(tables, "SVG ") != null,
        options.preserve_sbix_strikes and findTable(tables, "sbix") != null,
        options.max_output_bytes,
    );
    defer modified.deinit();

    var payloads = try std.ArrayList(TablePayload).initCapacity(
        allocator,
        tables.len,
    );
    defer payloads.deinit(allocator);
    for (tables) |table| {
        if (dropTable(table.tag, options)) continue;
        const data = if (std.mem.eql(u8, &table.tag, "head"))
            modified.head
        else if (std.mem.eql(u8, &table.tag, "cmap"))
            modified.cmap
        else if (std.mem.eql(u8, &table.tag, "glyf"))
            modified.glyf
        else if (std.mem.eql(u8, &table.tag, "loca"))
            modified.loca
        else if (std.mem.eql(u8, &table.tag, "COLR"))
            modified.colr orelse return error.InvalidFontSubset
        else if (std.mem.eql(u8, &table.tag, "SVG "))
            modified.svg orelse return error.InvalidFontSubset
        else if (std.mem.eql(u8, &table.tag, "sbix"))
            modified.sbix orelse return error.InvalidFontSubset
        else
            (try core.tableData(table.tag)) orelse
                return error.InvalidFontSubset;
        payloads.appendAssumeCapacity(.{ .tag = table.tag, .data = data });
    }

    const program = try serializeSfntAlloc(
        allocator,
        payloads.items,
        options.max_output_bytes,
    );
    errdefer allocator.free(program);
    const retained_glyphs = try allocator.dupe(GlyphId, retained_ids.items);
    errdefer allocator.free(retained_glyphs);
    std.mem.sort(GlyphId, retained_glyphs, {}, std.sort.asc(GlyphId));

    return .{
        .allocator = allocator,
        .program = program,
        .retained_glyphs = retained_glyphs,
        .source_glyph_count = maxp.glyph_count,
    };
}

fn validateOptions(options: Options) !void {
    if (options.max_requested_glyphs == 0 or
        options.max_retained_glyphs == 0 or
        options.max_component_edges == 0 or
        options.max_component_depth == 0 or
        options.max_cmap_mappings == 0 or
        options.max_output_bytes == 0)
    {
        return error.InvalidFontSubsetOptions;
    }
}

fn validateTableProfile(tables: []const font_mod.FontTableInfo) !void {
    const unsupported = [_][4]u8{
        "CBDT".*, "CBLC".*, "EBDT".*, "EBLC".*,
        "VARC".*, "bdat".*, "bloc".*,
    };
    for (unsupported) |tag| {
        if (findTable(tables, &tag) != null) return error.UnsupportedFontSubset;
    }
    if (findTable(tables, "glyf") == null or
        findTable(tables, "loca") == null or
        findTable(tables, "head") == null or
        findTable(tables, "maxp") == null or
        findTable(tables, "cmap") == null)
    {
        return error.UnsupportedFontSubset;
    }
}

fn validateColorProfile(
    face: *const face_mod.Face,
    tables: []const font_mod.FontTableInfo,
    preserve: bool,
) !bool {
    if (!preserve or findTable(tables, "COLR") == null) return false;
    const colr = (try core_api.inspect(face).tableData("COLR".*)) orelse
        return error.InvalidFontSubset;
    if (colr.len < 2) return error.InvalidFontSubset;
    if (try bin.readU16At(colr, 0) != 0) {
        return error.UnsupportedFontSubset;
    }
    return true;
}

fn dropTable(tag: [4]u8, options: Options) bool {
    // A modified font cannot retain its source digital signature or incremental
    // transfer maps. The latter describe patches against the original bytes.
    if (std.mem.eql(u8, &tag, "DSIG") or
        std.mem.eql(u8, &tag, "IFT ") or
        std.mem.eql(u8, &tag, "IFTX"))
    {
        return true;
    }
    if (!options.preserve_color_layers and
        (std.mem.eql(u8, &tag, "COLR") or
            std.mem.eql(u8, &tag, "CPAL")))
    {
        return true;
    }
    if (!options.preserve_svg_documents and
        std.mem.eql(u8, &tag, "SVG "))
    {
        return true;
    }
    if (!options.preserve_sbix_strikes and
        std.mem.eql(u8, &tag, "sbix"))
    {
        return true;
    }
    if (options.preserve_variations) return false;
    // Dropping the complete variation family turns the emitted program into
    // its default static instance. Never retain gvar/HVAR without fvar (or
    // vice versa): a partial set would expose coordinates with inconsistent
    // outline and metric behavior.
    const variations = [_][4]u8{
        "avar".*, "cvar".*, "fvar".*, "gvar".*, "HVAR".*,
        "MVAR".*, "STAT".*, "VVAR".*,
    };
    for (variations) |variation_tag| {
        if (std.mem.eql(u8, &tag, &variation_tag)) return true;
    }
    return false;
}

fn findTable(
    tables: []const font_mod.FontTableInfo,
    tag: []const u8,
) ?font_mod.FontTableInfo {
    for (tables) |table| {
        if (std.mem.eql(u8, &table.tag, tag)) return table;
    }
    return null;
}

fn retainGlyph(
    allocator: std.mem.Allocator,
    queue: *std.ArrayList(GlyphId),
    retained: []bool,
    glyph_id: GlyphId,
    options: Options,
) !bool {
    if (glyph_id >= retained.len) return error.InvalidFontSubsetGlyph;
    if (retained[glyph_id]) return false;
    if (queue.items.len >= options.max_retained_glyphs)
        return error.FontSubsetGlyphLimitExceeded;
    retained[glyph_id] = true;
    try queue.append(allocator, glyph_id);
    return true;
}

fn glyphBytes(
    glyf: []const u8,
    glyf_absolute_offset: usize,
    location: font_mod.GlyphLocationInfo,
) ![]const u8 {
    if (location.offset < glyf_absolute_offset) return error.InvalidFontSubset;
    const relative = location.offset - glyf_absolute_offset;
    if (relative > glyf.len or location.length > glyf.len - relative)
        return error.InvalidFontSubset;
    return glyf[relative .. relative + location.length];
}

fn selectedMappingsAlloc(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    retained: []const bool,
    max_mappings: usize,
) ![]Mapping {
    const inspection = core_api.inspect(face);
    const charmap = (try inspection.defaultCharmap()) orelse
        return error.UnsupportedFontSubset;
    var mappings = std.ArrayList(Mapping).empty;
    errdefer mappings.deinit(allocator);
    var current = try inspection.firstMapping(charmap);
    var scanned: usize = 0;
    while (current) |mapping| {
        scanned += 1;
        if (scanned > max_mappings)
            return error.FontSubsetCmapLimitExceeded;
        if (mapping.glyph_id < retained.len and retained[mapping.glyph_id]) {
            try mappings.append(allocator, .{
                .codepoint = mapping.codepoint,
                .glyph_id = mapping.glyph_id,
            });
        }
        current = try inspection.nextMapping(charmap, mapping.codepoint);
    }
    return try mappings.toOwnedSlice(allocator);
}

fn selectedVariationMappingsAlloc(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    retained: []const bool,
    max_mappings: usize,
) ![]VariationMapping {
    const font = &face.implementation;
    const selectors = try font.variationSelectors(allocator);
    defer allocator.free(selectors);
    var output = std.ArrayList(VariationMapping).empty;
    errdefer output.deinit(allocator);
    var scanned: usize = 0;
    for (selectors) |selector| {
        const codepoints = try font.variationCodepointsForSelector(
            allocator,
            selector,
        );
        defer allocator.free(codepoints);
        for (codepoints) |codepoint| {
            scanned += 1;
            if (scanned > max_mappings) {
                return error.FontSubsetCmapLimitExceeded;
            }
            const kind = (try font.variationSequenceKind(
                codepoint,
                selector,
            )) orelse continue;
            const glyph_id = try font.glyphIndexWithVariation(
                codepoint,
                selector,
            );
            if (glyph_id >= retained.len or !retained[glyph_id]) continue;
            try output.append(allocator, .{
                .selector = selector,
                .codepoint = codepoint,
                .glyph_id = glyph_id,
                .kind = kind,
            });
        }
    }
    return output.toOwnedSlice(allocator);
}

fn buildModifiedTables(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    glyf_source: []const u8,
    glyf_absolute_offset: usize,
    locations: []const font_mod.GlyphLocationInfo,
    retained: []const bool,
    mappings: []const Mapping,
    variation_mappings: []const VariationMapping,
    has_colr_v0: bool,
    has_svg: bool,
    has_sbix: bool,
    max_output_bytes: usize,
) !ModifiedTables {
    const core = core_api.inspect(face);
    const source_head = (try core.tableData("head".*)) orelse
        return error.InvalidFontSubset;
    const head = try allocator.dupe(u8, source_head);
    errdefer allocator.free(head);
    if (head.len < 54) return error.InvalidFontSubset;
    @memset(head[8..12], 0);
    writeI16(head, 50, 1); // Always emit long loca offsets.

    var glyf_len: usize = 0;
    for (locations, retained) |location, keep| {
        if (!keep or location.empty) continue;
        glyf_len = try align4Checked(try addChecked(glyf_len, location.length));
        if (glyf_len > max_output_bytes)
            return error.FontSubsetOutputLimitExceeded;
    }
    if (glyf_len > std.math.maxInt(u32))
        return error.FontSubsetOutputLimitExceeded;
    const glyf = try allocator.alloc(u8, glyf_len);
    errdefer allocator.free(glyf);
    @memset(glyf, 0);
    const loca_len = std.math.mul(usize, locations.len + 1, 4) catch
        return error.FontSubsetOutputLimitExceeded;
    if (loca_len > max_output_bytes)
        return error.FontSubsetOutputLimitExceeded;
    const loca = try allocator.alloc(u8, loca_len);
    errdefer allocator.free(loca);
    @memset(loca, 0);

    var cursor: usize = 0;
    for (locations, retained, 0..) |location, keep, glyph_index| {
        writeU32(loca, glyph_index * 4, @intCast(cursor));
        if (!keep or location.empty) continue;
        const source = try glyphBytes(
            glyf_source,
            glyf_absolute_offset,
            location,
        );
        @memcpy(glyf[cursor .. cursor + source.len], source);
        cursor = try align4Checked(try addChecked(cursor, source.len));
    }
    writeU32(loca, locations.len * 4, @intCast(cursor));
    if (cursor != glyf.len) return error.InvalidFontSubset;

    const cmap = try buildCmapAlloc(
        allocator,
        mappings,
        variation_mappings,
    );
    errdefer allocator.free(cmap);
    if (cmap.len > max_output_bytes)
        return error.FontSubsetOutputLimitExceeded;
    const colr = if (has_colr_v0)
        try buildColrV0Alloc(allocator, face, retained)
    else
        null;
    errdefer if (colr) |bytes| allocator.free(bytes);
    if (colr) |bytes| {
        if (bytes.len > max_output_bytes) {
            return error.FontSubsetOutputLimitExceeded;
        }
    }
    const svg = if (has_svg)
        try buildSvgAlloc(allocator, face, retained)
    else
        null;
    errdefer if (svg) |bytes| allocator.free(bytes);
    if (svg) |bytes| {
        if (bytes.len > max_output_bytes) {
            return error.FontSubsetOutputLimitExceeded;
        }
    }
    const sbix = if (has_sbix)
        try buildSbixAlloc(allocator, face, retained)
    else
        null;
    errdefer if (sbix) |bytes| allocator.free(bytes);
    if (sbix) |bytes| {
        if (bytes.len > max_output_bytes) {
            return error.FontSubsetOutputLimitExceeded;
        }
    }
    return .{
        .allocator = allocator,
        .head = head,
        .cmap = cmap,
        .glyf = glyf,
        .loca = loca,
        .colr = colr,
        .svg = svg,
        .sbix = sbix,
    };
}

const SbixImage = struct {
    glyph_id: GlyphId,
    origin_x: i16,
    origin_y: i16,
    data: []const u8,
};

fn buildSbixAlloc(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    retained: []const bool,
) ![]u8 {
    const strikes = try face.color().bitmapStrikes(allocator);
    defer allocator.free(strikes);
    const strike_images = try allocator.alloc(
        std.ArrayList(SbixImage),
        strikes.len,
    );
    defer {
        for (strike_images) |*images| {
            for (images.items) |image| allocator.free(image.data);
            images.deinit(allocator);
        }
        allocator.free(strike_images);
    }
    for (strike_images) |*images| images.* = .empty;
    for (strikes, strike_images) |strike, *images| {
        if (strike.source != .sbix) return error.UnsupportedFontSubset;
        for (retained, 0..) |keep, glyph_index| {
            if (!keep) continue;
            const data = (try face.color().bitmapData(
                @intCast(glyph_index),
                @floatFromInt(strike.ppem),
            )) orelse continue;
            const png = switch (data) {
                .png => |image| image,
                else => return error.UnsupportedFontSubset,
            };
            if (png.source != .sbix) return error.UnsupportedFontSubset;
            const owned = try allocator.dupe(u8, png.data);
            errdefer allocator.free(owned);
            try images.append(allocator, .{
                .glyph_id = @intCast(glyph_index),
                .origin_x = png.origin_offset_x,
                .origin_y = png.origin_offset_y,
                .data = owned,
            });
        }
    }
    const glyph_count = face.properties().glyph_count;
    const header_len = try addChecked(8, strikes.len * 4);
    var total_len = header_len;
    for (strike_images) |images| {
        total_len = try addChecked(total_len, 4 + (@as(usize, glyph_count) + 1) * 4);
        for (images.items) |image| total_len = try addChecked(total_len, 8 + image.data.len);
    }
    const output = try allocator.alloc(u8, total_len);
    @memset(output, 0);
    writeU16(output, 0, 1);
    writeU32(output, 4, @intCast(strikes.len));
    var cursor = header_len;
    for (strikes, strike_images, 0..) |strike, images, strike_index| {
        writeU32(output, 8 + strike_index * 4, @intCast(cursor));
        const strike_start = cursor;
        writeU16(output, cursor, strike.ppem);
        writeU16(output, cursor + 2, strike.ppi);
        cursor += 4 + (@as(usize, glyph_count) + 1) * 4;
        var image_index: usize = 0;
        for (0..glyph_count) |glyph_index| {
            writeU32(
                output,
                strike_start + 4 + glyph_index * 4,
                @intCast(cursor - strike_start),
            );
            if (image_index >= images.items.len or
                images.items[image_index].glyph_id != glyph_index) continue;
            const image = images.items[image_index];
            writeI16(output, cursor, image.origin_x);
            writeI16(output, cursor + 2, image.origin_y);
            @memcpy(output[cursor + 4 .. cursor + 8], "png ");
            @memcpy(output[cursor + 8 ..][0..image.data.len], image.data);
            cursor += 8 + image.data.len;
            image_index += 1;
        }
        writeU32(
            output,
            strike_start + 4 + @as(usize, glyph_count) * 4,
            @intCast(cursor - strike_start),
        );
    }
    if (cursor != output.len) return error.InvalidFontSubset;
    return output;
}

const SvgRecord = struct {
    glyph_id: GlyphId,
    data: []const u8,
};

fn buildSvgAlloc(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    retained: []const bool,
) ![]u8 {
    var records = std.ArrayList(SvgRecord).empty;
    defer records.deinit(allocator);
    var owned_payloads = std.ArrayList([]u8).empty;
    defer {
        for (owned_payloads.items) |payload| allocator.free(payload);
        owned_payloads.deinit(allocator);
    }
    for (retained, 0..) |keep, glyph_index| {
        if (!keep) continue;
        var document = (try face.color().svg(
            allocator,
            @intCast(glyph_index),
        )) orelse continue;
        defer document.deinit();
        // Preserve the original validated payload bytes when they are plain
        // XML. Resolved gzip data is also safe to emit as ordinary XML and
        // avoids retaining a compressed container with broader glyph ranges.
        const payload = try allocator.dupe(u8, document.data);
        errdefer allocator.free(payload);
        try owned_payloads.append(allocator, payload);
        try records.append(allocator, .{
            .glyph_id = @intCast(glyph_index),
            .data = payload,
        });
    }
    if (records.items.len > std.math.maxInt(u16)) {
        return error.FontSubsetOutputLimitExceeded;
    }
    const list_offset: usize = 10;
    const records_bytes = try addChecked(2, records.items.len * 12);
    var total_len = try addChecked(list_offset, records_bytes);
    for (records.items) |record| total_len = try addChecked(total_len, record.data.len);
    const output = try allocator.alloc(u8, total_len);
    @memset(output, 0);
    writeU16(output, 0, 0);
    writeU32(output, 2, @intCast(list_offset));
    writeU16(output, list_offset, @intCast(records.items.len));
    var payload_offset = records_bytes;
    for (records.items, 0..) |record, index| {
        const entry = list_offset + 2 + index * 12;
        writeU16(output, entry, record.glyph_id);
        writeU16(output, entry + 2, record.glyph_id);
        writeU32(output, entry + 4, @intCast(payload_offset));
        writeU32(output, entry + 8, @intCast(record.data.len));
        const absolute = list_offset + payload_offset;
        @memcpy(output[absolute .. absolute + record.data.len], record.data);
        payload_offset += record.data.len;
    }
    if (list_offset + payload_offset != output.len) {
        return error.InvalidFontSubset;
    }
    return output;
}

const ColorBase = struct {
    glyph_id: GlyphId,
    first_layer: u16,
    layer_count: u16,
};

fn buildColrV0Alloc(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    retained: []const bool,
) ![]u8 {
    var bases = std.ArrayList(ColorBase).empty;
    defer bases.deinit(allocator);
    var layers = std.ArrayList(font_mod.ColorLayer).empty;
    defer layers.deinit(allocator);
    for (retained, 0..) |keep, glyph_index| {
        if (!keep) continue;
        const glyph_layers = try face.color().layers(
            allocator,
            @intCast(glyph_index),
        );
        defer allocator.free(glyph_layers);
        if (glyph_layers.len == 0) continue;
        if (layers.items.len > std.math.maxInt(u16) or
            glyph_layers.len > std.math.maxInt(u16) - layers.items.len)
        {
            return error.FontSubsetOutputLimitExceeded;
        }
        try bases.append(allocator, .{
            .glyph_id = @intCast(glyph_index),
            .first_layer = @intCast(layers.items.len),
            .layer_count = @intCast(glyph_layers.len),
        });
        try layers.appendSlice(allocator, glyph_layers);
    }
    if (bases.items.len > std.math.maxInt(u16) or
        layers.items.len > std.math.maxInt(u16))
    {
        return error.FontSubsetOutputLimitExceeded;
    }
    const base_offset: usize = 14;
    const layer_offset = try addChecked(base_offset, bases.items.len * 6);
    const total_len = try addChecked(layer_offset, layers.items.len * 4);
    const output = try allocator.alloc(u8, total_len);
    @memset(output, 0);
    writeU16(output, 0, 0);
    writeU16(output, 2, @intCast(bases.items.len));
    writeU32(output, 4, @intCast(base_offset));
    writeU32(output, 8, @intCast(layer_offset));
    writeU16(output, 12, @intCast(layers.items.len));
    for (bases.items, 0..) |base, index| {
        const offset = base_offset + index * 6;
        writeU16(output, offset, base.glyph_id);
        writeU16(output, offset + 2, base.first_layer);
        writeU16(output, offset + 4, base.layer_count);
    }
    for (layers.items, 0..) |layer, index| {
        const offset = layer_offset + index * 4;
        writeU16(output, offset, layer.glyph_id);
        writeU16(output, offset + 2, layer.palette_index);
    }
    return output;
}

fn buildCmapAlloc(
    allocator: std.mem.Allocator,
    mappings: []const Mapping,
    variation_mappings: []const VariationMapping,
) ![]u8 {
    var group_count: usize = 0;
    for (mappings, 0..) |mapping, index| {
        if (index == 0 or
            mapping.codepoint != mappings[index - 1].codepoint + 1 or
            mapping.glyph_id != mappings[index - 1].glyph_id + 1)
        {
            group_count += 1;
        }
    }
    const group_bytes = std.math.mul(usize, group_count, 12) catch
        return error.FontSubsetOutputLimitExceeded;
    const subtable_len = try addChecked(16, group_bytes);
    const format14_len = try format14Length(variation_mappings);
    const encoding_count: usize = if (format14_len == 0) 1 else 2;
    const directory_len = try addChecked(4, encoding_count * 8);
    const total_len = try addChecked(
        try addChecked(directory_len, subtable_len),
        format14_len,
    );
    if (total_len > std.math.maxInt(u32) or group_count > std.math.maxInt(u32))
        return error.FontSubsetOutputLimitExceeded;
    const bytes = try allocator.alloc(u8, total_len);
    @memset(bytes, 0);
    writeU16(bytes, 2, @intCast(encoding_count));
    if (format14_len != 0) {
        writeU16(bytes, 4, 0);
        writeU16(bytes, 6, 5);
        writeU32(bytes, 8, @intCast(directory_len + subtable_len));
        writeU16(bytes, 12, 3);
        writeU16(bytes, 14, 10);
        writeU32(bytes, 16, @intCast(directory_len));
    } else {
        writeU16(bytes, 4, 3);
        writeU16(bytes, 6, 10);
        writeU32(bytes, 8, @intCast(directory_len));
    }
    const sub = directory_len;
    writeU16(bytes, sub, 12);
    writeU32(bytes, sub + 4, @intCast(subtable_len));
    writeU32(bytes, sub + 12, @intCast(group_count));

    var group_index: usize = 0;
    var index: usize = 0;
    while (index < mappings.len) {
        const start = mappings[index];
        var end = index + 1;
        while (end < mappings.len and
            mappings[end].codepoint == mappings[end - 1].codepoint + 1 and
            mappings[end].glyph_id == mappings[end - 1].glyph_id + 1)
        {
            end += 1;
        }
        const group = sub + 16 + group_index * 12;
        writeU32(bytes, group, start.codepoint);
        writeU32(bytes, group + 4, mappings[end - 1].codepoint);
        writeU32(bytes, group + 8, start.glyph_id);
        group_index += 1;
        index = end;
    }
    if (format14_len != 0) {
        try writeFormat14(
            bytes[directory_len + subtable_len ..],
            variation_mappings,
        );
    }
    return bytes;
}

fn format14Length(mappings: []const VariationMapping) !usize {
    if (mappings.len == 0) return 0;
    var selector_count: usize = 0;
    var default_count: usize = 0;
    var non_default_count: usize = 0;
    var previous_selector: ?u21 = null;
    for (mappings) |mapping| {
        if (previous_selector == null or previous_selector.? != mapping.selector) {
            selector_count += 1;
            previous_selector = mapping.selector;
        }
        switch (mapping.kind) {
            .default => default_count += 1,
            .non_default => non_default_count += 1,
        }
    }
    return try addChecked(
        try addChecked(10, selector_count * 11),
        try addChecked(
            if (default_count == 0) 0 else 4 + default_count * 4,
            if (non_default_count == 0) 0 else 4 + non_default_count * 5,
        ),
    );
}

fn writeFormat14(bytes: []u8, mappings: []const VariationMapping) !void {
    const total_len = try format14Length(mappings);
    if (bytes.len != total_len) return error.InvalidFontSubset;
    @memset(bytes, 0);
    writeU16(bytes, 0, 14);
    writeU32(bytes, 2, @intCast(total_len));

    var selector_count: usize = 0;
    var index: usize = 0;
    while (index < mappings.len) {
        selector_count += 1;
        const selector = mappings[index].selector;
        while (index < mappings.len and mappings[index].selector == selector) {
            index += 1;
        }
    }
    writeU32(bytes, 6, @intCast(selector_count));
    var payload = 10 + selector_count * 11;
    index = 0;
    var record_index: usize = 0;
    while (index < mappings.len) : (record_index += 1) {
        const start = index;
        const selector = mappings[index].selector;
        while (index < mappings.len and mappings[index].selector == selector) {
            index += 1;
        }
        const record = 10 + record_index * 11;
        writeU24(bytes, record, selector);
        var default_count: usize = 0;
        var non_default_count: usize = 0;
        for (mappings[start..index]) |mapping| switch (mapping.kind) {
            .default => default_count += 1,
            .non_default => non_default_count += 1,
        };
        if (default_count != 0) {
            writeU32(bytes, record + 3, @intCast(payload));
            writeU32(bytes, payload, @intCast(default_count));
            payload += 4;
            for (mappings[start..index]) |mapping| {
                if (mapping.kind != .default) continue;
                writeU24(bytes, payload, mapping.codepoint);
                bytes[payload + 3] = 0;
                payload += 4;
            }
        }
        if (non_default_count != 0) {
            writeU32(bytes, record + 7, @intCast(payload));
            writeU32(bytes, payload, @intCast(non_default_count));
            payload += 4;
            for (mappings[start..index]) |mapping| {
                if (mapping.kind != .non_default) continue;
                writeU24(bytes, payload, mapping.codepoint);
                writeU16(bytes, payload + 3, mapping.glyph_id);
                payload += 5;
            }
        }
    }
    if (payload != bytes.len) return error.InvalidFontSubset;
}

fn serializeSfntAlloc(
    allocator: std.mem.Allocator,
    tables: []const TablePayload,
    max_output_bytes: usize,
) ![]u8 {
    if (tables.len == 0 or tables.len > std.math.maxInt(u16))
        return error.InvalidFontSubset;
    const record_bytes = std.math.mul(usize, tables.len, 16) catch
        return error.FontSubsetOutputLimitExceeded;
    const directory_len = try addChecked(12, record_bytes);
    var total_len = directory_len;
    for (tables) |table| {
        total_len = try align4Checked(total_len);
        total_len = try addChecked(total_len, table.data.len);
        total_len = try align4Checked(total_len);
        if (total_len > max_output_bytes)
            return error.FontSubsetOutputLimitExceeded;
    }
    const output = try allocator.alloc(u8, total_len);
    errdefer allocator.free(output);
    @memset(output, 0);
    writeU32(output, 0, 0x00010000);
    writeU16(output, 4, @intCast(tables.len));
    const search = searchParameters(tables.len);
    writeU16(output, 6, search.range);
    writeU16(output, 8, search.selector);
    writeU16(output, 10, @intCast(tables.len * 16 - search.range));

    var cursor = directory_len;
    var head_offset: ?usize = null;
    var previous_tag: ?[4]u8 = null;
    for (tables, 0..) |table, index| {
        if (previous_tag) |previous| {
            if (std.mem.order(u8, &previous, &table.tag) != .lt)
                return error.InvalidFontSubset;
        }
        previous_tag = table.tag;
        cursor = try align4Checked(cursor);
        const record = 12 + index * 16;
        @memcpy(output[record .. record + 4], &table.tag);
        writeU32(output, record + 4, checksum(table.data));
        writeU32(output, record + 8, @intCast(cursor));
        writeU32(output, record + 12, @intCast(table.data.len));
        @memcpy(output[cursor .. cursor + table.data.len], table.data);
        if (std.mem.eql(u8, &table.tag, "head")) head_offset = cursor;
        cursor = try align4Checked(try addChecked(cursor, table.data.len));
    }
    if (cursor != output.len) return error.InvalidFontSubset;
    const head = head_offset orelse return error.InvalidFontSubset;
    if (head > output.len or output.len - head < 12)
        return error.InvalidFontSubset;
    const adjustment = @as(u32, 0xb1b0afba) -% checksum(output);
    writeU32(output, head + 8, adjustment);
    return output;
}

fn searchParameters(table_count: usize) struct { range: u16, selector: u16 } {
    var power: usize = 1;
    var selector: u16 = 0;
    while (power * 2 <= table_count) {
        power *= 2;
        selector += 1;
    }
    return .{ .range = @intCast(power * 16), .selector = selector };
}

fn checksum(bytes: []const u8) u32 {
    var result: u32 = 0;
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) {
        var word: u32 = 0;
        for (0..4) |byte_index| {
            word <<= 8;
            if (offset + byte_index < bytes.len)
                word |= bytes[offset + byte_index];
        }
        result +%= word;
    }
    return result;
}

fn addChecked(a: usize, b: usize) !usize {
    return std.math.add(usize, a, b) catch
        error.FontSubsetOutputLimitExceeded;
}

fn align4Checked(value: usize) !usize {
    return (try addChecked(value, 3)) & ~@as(usize, 3);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @truncate(value >> 16);
    bytes[offset + 1] = @truncate(value >> 8);
    bytes[offset + 2] = @truncate(value);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
