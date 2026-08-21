//! Table-backed LigatureSubst execution for whole runs and contextual targets.

const std = @import("std");
const filtering = @import("../../../../runtime/filtering.zig");
const Options = @import("../../../../runtime/options.zig").Options;
const table = @import("../../../../table/root.zig");
const commit = @import("../commit.zig");
const matching = @import("../matching.zig");
const metadata = @import("../metadata.zig");
const model = @import("../model.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || std.mem.Allocator.Error;
const View = table.View;

const Header = struct {
    coverage_offset: usize,
    set_count: u16,
};

pub fn apply(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    const header = try parseHeader(view, subtable_offset);
    var component_offsets: [model.max_components]usize = undefined;
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) : (glyph_index += 1) {
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) continue;
        _ = try applyAtWithHeader(
            view,
            subtable_offset,
            header,
            glyphs,
            glyph_index,
            allocator,
            lookup_flag,
            run,
            &component_offsets,
        );
    }
}

pub fn applyAt(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?model.Change {
    if (glyph_index >= glyphs.items.len) return null;
    const header = try parseHeader(view, subtable_offset);
    var component_offsets: [model.max_components]usize = undefined;
    return applyAtWithHeader(
        view,
        subtable_offset,
        header,
        glyphs,
        glyph_index,
        allocator,
        lookup_flag,
        run,
        &component_offsets,
    );
}

fn applyAtWithHeader(
    view: View,
    subtable_offset: usize,
    header: Header,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    component_offsets: *[model.max_components]usize,
) Error!?model.Change {
    const first = glyphs.items[glyph_index];
    if (filtering.lookupIgnoresGlyph(lookup_flag, run, first)) return null;
    const covered = try table.coverage.index(
        view,
        header.coverage_offset,
        first,
    ) orelse return null;
    if (covered >= header.set_count) return null;
    const set_offset = table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 6 + covered * 2),
    ) catch return null;
    const found = try matching.directMatch(
        view,
        set_offset,
        glyphs.items[glyph_index..],
        glyph_index,
        lookup_flag,
        run,
        component_offsets,
    ) orelse return null;
    const info = try metadata.componentInfo(
        allocator,
        run,
        glyph_index,
        found,
    );
    metadata.mergeClusters(run, glyph_index, found);
    return commit.apply(glyphs, glyph_index, found, info, run);
}

fn parseHeader(view: View, subtable_offset: usize) Error!Header {
    if (try view.readU16(subtable_offset) != 1) {
        return error.UnsupportedGsub;
    }
    return .{
        .coverage_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .set_count = try view.readU16(subtable_offset + 4),
    };
}
