//! OpenType ReverseChainSingleSubst execution surface.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const lookup_executor = @import("lookup.zig");
const matching = @import("matching.zig");
const subtable_executor = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Lookup = accelerator.Lookup;
const View = table.View;

pub fn lookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) Error!void {
    return lookup_executor.apply(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        lookup_flag,
        run,
    );
}

pub fn extensionLookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
    cached: ?*const Lookup,
) Error!void {
    return lookup_executor.applyExtension(
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        lookup_flag,
        run,
        cached,
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

pub fn at(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    return subtable_executor.applyAt(
        view,
        subtable_offset,
        glyphs,
        position,
        lookup_flag,
        run,
    );
}

pub const exactContextKey = matching.exactKey;
