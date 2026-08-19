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
};

const Mapping = struct {
    codepoint: u21,
    glyph_id: GlyphId,
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

    fn deinit(self: *ModifiedTables) void {
        self.allocator.free(self.head);
        self.allocator.free(self.cmap);
        self.allocator.free(self.glyf);
        self.allocator.free(self.loca);
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

    var modified = try buildModifiedTables(
        allocator,
        face,
        glyf_source,
        glyf_info.offset,
        locations,
        retained,
        mappings,
        options.max_output_bytes,
    );
    defer modified.deinit();

    var payloads = try std.ArrayList(TablePayload).initCapacity(
        allocator,
        tables.len,
    );
    defer payloads.deinit(allocator);
    for (tables) |table| {
        if (dropTable(table.tag)) continue;
        const data = if (std.mem.eql(u8, &table.tag, "head"))
            modified.head
        else if (std.mem.eql(u8, &table.tag, "cmap"))
            modified.cmap
        else if (std.mem.eql(u8, &table.tag, "glyf"))
            modified.glyf
        else if (std.mem.eql(u8, &table.tag, "loca"))
            modified.loca
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
        "CBDT".*, "CBLC".*, "COLR".*, "EBDT".*, "EBLC".*,
        "SVG ".*, "VARC".*, "bdat".*, "bloc".*, "sbix".*,
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

fn dropTable(tag: [4]u8) bool {
    // A modified font cannot retain its source digital signature or incremental
    // transfer maps. The latter describe patches against the original bytes.
    return std.mem.eql(u8, &tag, "DSIG") or
        std.mem.eql(u8, &tag, "IFT ") or
        std.mem.eql(u8, &tag, "IFTX");
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

fn buildModifiedTables(
    allocator: std.mem.Allocator,
    face: *const face_mod.Face,
    glyf_source: []const u8,
    glyf_absolute_offset: usize,
    locations: []const font_mod.GlyphLocationInfo,
    retained: []const bool,
    mappings: []const Mapping,
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

    const cmap = try buildCmapAlloc(allocator, mappings);
    errdefer allocator.free(cmap);
    if (cmap.len > max_output_bytes)
        return error.FontSubsetOutputLimitExceeded;
    return .{
        .allocator = allocator,
        .head = head,
        .cmap = cmap,
        .glyf = glyf,
        .loca = loca,
    };
}

fn buildCmapAlloc(allocator: std.mem.Allocator, mappings: []const Mapping) ![]u8 {
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
    const total_len = try addChecked(12, subtable_len);
    if (total_len > std.math.maxInt(u32) or group_count > std.math.maxInt(u32))
        return error.FontSubsetOutputLimitExceeded;
    const bytes = try allocator.alloc(u8, total_len);
    @memset(bytes, 0);
    writeU16(bytes, 2, 1);
    writeU16(bytes, 4, 3);
    writeU16(bytes, 6, 10);
    writeU32(bytes, 8, 12);
    const sub = 12;
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
    return bytes;
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

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
