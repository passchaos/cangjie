//! OpenType LigatureSubst execution surface.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const matching = @import("matching.zig");
const metadata = @import("metadata.zig");
const model = @import("model.zig");
const accelerated_run = @import("run/accelerated.zig");
const direct_run = @import("run/direct.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || std.mem.Allocator.Error;
const Ligature = accelerator.model.LigatureSubstitution;
const View = table.View;

pub const Change = model.Change;
pub const Match = model.Match;
pub const max_components = model.max_components;

pub fn subtable(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return direct_run.apply(
        view,
        subtable_offset,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn at(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?Change {
    return direct_run.applyAt(
        view,
        subtable_offset,
        glyphs,
        glyph_index,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn accelerated(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) std.mem.Allocator.Error!void {
    return accelerated_run.apply(
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn acceleratedPrefiltered(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) std.mem.Allocator.Error!void {
    return accelerated_run.applyPrefiltered(
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub noinline fn acceleratedRequiredSecond(
    ligature: Ligature,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) std.mem.Allocator.Error!void {
    return accelerated_run.applyRequiredSecond(
        ligature,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub const directMatch = matching.directMatch;
pub const acceleratedMatch = matching.acceleratedMatch;
pub const acceleratedPrefilteredMatch =
    matching.acceleratedPrefilteredMatch;
pub const requiredSecondComponents = matching.requiredSecondComponents;
pub const setForGlyph = matching.setForGlyph;
pub const componentInfo = metadata.componentInfo;
