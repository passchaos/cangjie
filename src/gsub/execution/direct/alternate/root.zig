//! OpenType AlternateSubst execution surface.

const std = @import("std");
const filtering = @import("../../../runtime/filtering.zig");
const table = @import("../../../table/root.zig");
const lookup_executor = @import("lookup.zig");
const subtable_executor = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || error{InvalidShapingInput};
const Options = filtering.Options;
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

pub const randomIndex = subtable_executor.randomIndex;
