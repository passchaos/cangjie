//! Direct and accelerated OpenType SingleSubst execution surface.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const mutation = @import("../../../runtime/mutation.zig");
const table = @import("../../../table/root.zig");
const lookup_executor = @import("lookup.zig");
const subtable_executor = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Entry = accelerator.model.SingleEntry;
const Options = filtering.Options;
const Single = accelerator.model.SingleSubstitution;
const View = table.View;

pub fn lookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    return lookup_executor.apply(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn extensionLookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    return lookup_executor.applyExtension(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn entries(
    mappings: []const Entry,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) void {
    for (glyphs.items, 0..) |*glyph, glyph_index| {
        if (!filtering.sourceFeatureAllowsGlyph(run, glyph_index)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, glyph.*)) continue;
        const mapping = entryForGlyph(mappings, glyph.*) orelse continue;
        glyph.* = mapping.to;
        mutation.markSubstituted(run, glyph_index);
    }
}

pub fn entryForGlyph(
    mappings: []const Entry,
    glyph: GlyphId,
) ?Entry {
    var low: usize = 0;
    var high = mappings.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const candidate = mappings[middle].from;
        if (glyph < candidate) {
            high = middle;
        } else if (glyph > candidate) {
            low = middle + 1;
        } else {
            return mappings[middle];
        }
    }
    return null;
}

pub fn subtable(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) Error!void {
    return subtable_executor.apply(
        view,
        subtable_offset,
        glyphs,
        lookup_flag,
        run,
    );
}

pub fn at(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    return subtable_executor.applyAt(
        view,
        subtable_offset,
        glyphs,
        glyph_index,
        lookup_flag,
        run,
    );
}

pub fn acceleratedAt(
    view: View,
    single: Single,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    run: Options,
) Error!bool {
    return subtable_executor.applyAcceleratedAt(
        view,
        single,
        glyphs,
        glyph_index,
        run,
    );
}
