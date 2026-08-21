//! Preserve-GID COLRv1 filtering without relocating the Paint DAG.
//!
//! The generated table keeps every validated source byte at its original
//! offset and compacts only the fixed-width BaseGlyphPaintRecord directory.
//! Selected root offsets are copied verbatim, so every Paint/Layer/variation
//! byte and every relative reference remains stable.

const std = @import("std");

const bin = @import("../../binary.zig");
const colr_v1 = @import("../tables/color/colr/v1.zig");
const glyph_mod = @import("../../glyph.zig");

const GlyphId = glyph_mod.GlyphId;

pub fn buildAlloc(
    allocator: std.mem.Allocator,
    source: []const u8,
    retained: []const bool,
) ![]u8 {
    const table = colr_v1.Table{ .offset = 0, .length = source.len };
    const list = (try colr_v1.bases.read(source, table)) orelse
        return error.InvalidFontSubset;
    var selected_count: usize = 0;
    for (0..list.record_count) |index| {
        const record = try colr_v1.bases.recordAt(source, table, list, index);
        if (record.glyph_id < retained.len and retained[record.glyph_id]) {
            selected_count += 1;
        }
    }
    const output = try allocator.dupe(u8, source);
    errdefer allocator.free(output);
    std.mem.writeInt(u32, output[list.start..][0..4], @intCast(selected_count), .big);
    var output_index: usize = 0;
    for (0..list.record_count) |index| {
        const source_record = list.records_start + index * 6;
        const glyph_id = try bin.readU16At(source, source_record);
        if (glyph_id >= retained.len or !retained[glyph_id]) continue;
        const output_record = list.records_start + output_index * 6;
        @memcpy(output[output_record..][0..6], source[source_record..][0..6]);
        output_index += 1;
    }
    return output;
}

/// Collect outline and PaintColrGlyph targets reachable from one base glyph.
pub fn referencesAlloc(
    allocator: std.mem.Allocator,
    source: []const u8,
    base_glyph: GlyphId,
    glyph_count: u16,
) ![]GlyphId {
    const table = colr_v1.Table{ .offset = 0, .length = source.len };
    const list = (try colr_v1.bases.read(source, table)) orelse
        return try allocator.alloc(GlyphId, 0);
    const seen = try allocator.alloc(bool, glyph_count);
    defer allocator.free(seen);
    @memset(seen, false);
    const pending = try allocator.alloc(GlyphId, glyph_count);
    defer allocator.free(pending);
    const references = try allocator.alloc(GlyphId, glyph_count);
    errdefer allocator.free(references);
    var pending_len: usize = 1;
    var references_len: usize = 0;
    pending[0] = base_glyph;
    seen[base_glyph] = true;

    var cursor: usize = 0;
    while (cursor < pending_len) : (cursor += 1) {
        const paint_offset = (try colr_v1.bases.paintOffsetForGlyph(
            source,
            table,
            list,
            pending[cursor],
        )) orelse continue;
        var visitor = ReferenceVisitor{
            .glyph_count = glyph_count,
            .seen = seen,
            .pending = pending,
            .pending_len = &pending_len,
            .references = references,
            .references_len = &references_len,
        };
        try colr_v1.paint.walkGraph(source, table, paint_offset, &visitor);
    }
    if (references_len == 0) {
        allocator.free(references);
        return try allocator.alloc(GlyphId, 0);
    }
    return try allocator.realloc(references, references_len);
}

const ReferenceVisitor = struct {
    glyph_count: u16,
    seen: []bool,
    pending: []GlyphId,
    pending_len: *usize,
    references: []GlyphId,
    references_len: *usize,

    pub fn visit(
        self: *ReferenceVisitor,
        data: []const u8,
        _: colr_v1.Table,
        offset: usize,
        info: colr_v1.paint.FormatInfo,
    ) colr_v1.Error!void {
        const glyph_id: ?GlyphId = switch (info.kind) {
            .glyph => try bin.readU16At(data, offset + 4),
            .colr_glyph => try bin.readU16At(data, offset + 1),
            else => null,
        };
        const value = glyph_id orelse return;
        if (value >= self.glyph_count) return error.BadSfnt;
        if (self.seen[value]) return;
        self.seen[value] = true;
        self.references[self.references_len.*] = value;
        self.references_len.* += 1;
        if (info.kind == .colr_glyph) {
            self.pending[self.pending_len.*] = value;
            self.pending_len.* += 1;
        }
    }
};
