//! Direct nested GSUB target adapters.
//!
//! Contextual records target one glyph but cardinality-changing and ligature
//! lookups need the real mutable run. These adapters normalize each concrete
//! executor's change type into the contextual record model.

const std = @import("std");
const direct_ligature = @import("../../direct/ligature/root.zig");
const direct_multiple = @import("../../direct/multiple/root.zig");
const model = @import("../model.zig");
const options = @import("../../../runtime/options.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Change = model.Change;
pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn multiple(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?Change {
    const change = try direct_multiple.at(
        view,
        subtable_offset,
        glyphs,
        glyph_index,
        allocator,
        lookup_flag,
        run,
    ) orelse return null;
    return .{
        .removed_len = change.removed_len,
        .inserted_len = change.inserted_len,
    };
}

pub fn ligature(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?Change {
    const change = try direct_ligature.at(
        view,
        subtable_offset,
        glyphs,
        glyph_index,
        allocator,
        lookup_flag,
        run,
    ) orelse return null;
    return .{
        .removed_len = change.removed_len,
        .inserted_len = change.inserted_len,
        .component_offsets = change.component_offsets,
        .component_count = change.component_count,
    };
}
