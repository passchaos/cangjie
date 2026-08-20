//! Position-major ChainContextSubst lookup execution surface.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const accelerated = @import("accelerated.zig");
const direct = @import("direct.zig");
const extension = @import("extension.zig");
const chaining_class = @import("../class/root.zig");
const chaining_coverage = @import("../coverage/root.zig");
const chaining_glyph = @import("../glyph/root.zig");
const options = @import("../../../../runtime/options.zig");
const table = @import("../../../../table/root.zig");
pub const target = @import("target.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const Error = target.Error;
pub const Lookup = accelerator.Lookup;
pub const Options = options.Options;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    sidecar: ?*const Lookup,
) Error!void {
    if (sidecar) |parsed| {
        return accelerated.apply(
            Executor,
            view,
            lookup_offset,
            glyphs,
            allocator,
            lookup_flag,
            run,
            parsed,
        );
    }
    return direct.apply(
        Executor,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

pub const applyExtension = extension.apply;

pub fn subtable(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    return switch (try view.readU16(subtable_offset)) {
        1 => chaining_glyph.subtable(
            Executor,
            view,
            subtable_offset,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        2 => chaining_class.subtable(
            Executor,
            view,
            subtable_offset,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        3 => chaining_coverage.subtable(
            Executor,
            view,
            subtable_offset,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        else => error.UnsupportedGsub,
    };
}

pub const at = target.apply;
