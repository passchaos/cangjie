//! OpenType MultipleSubst execution surface.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const limits = @import("../../../runtime/limits.zig");
const table = @import("../../../table/root.zig");
const lookup_executor = @import("lookup.zig");
const replacement = @import("replacement.zig");
const subtable_executor = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    limits.Error ||
    std.mem.Allocator.Error;
const Multiple = accelerator.model.MultipleSubstitution;
const Options = filtering.Options;
const View = table.View;

pub const Change = replacement.Change;

pub fn lookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
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
) Error!void {
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
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return subtable_executor.apply(
        view,
        subtable_offset,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn accelerated(
    view: View,
    multiple: Multiple,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return subtable_executor.applyAccelerated(
        view,
        multiple,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub const acceleratedAt = subtable_executor.applyAcceleratedAt;

pub fn at(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?Change {
    return subtable_executor.applyAt(
        view,
        subtable_offset,
        glyphs,
        glyph_index,
        allocator,
        lookup_flag,
        run,
    );
}

pub const entryForGlyph = subtable_executor.entryForGlyph;
