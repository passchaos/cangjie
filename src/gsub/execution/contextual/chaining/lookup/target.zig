//! One ChainContextSubst candidate at a fixed glyph position.

const std = @import("std");
const accelerator = @import("../../../../accelerator/root.zig");
const chaining_class = @import("../class/root.zig");
const chaining_coverage = @import("../coverage/root.zig");
const chaining_glyph = @import("../glyph/root.zig");
const model = @import("../../model.zig");
const options = @import("../../../../runtime/options.zig");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const ParsedCoverage = accelerator.model.ChainingCoverageSubtable;
pub const Result = model.ApplyResult;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    subtable_offset: usize,
    parsed_coverage: ?ParsedCoverage,
    glyphs: *std.ArrayList(GlyphId),
    position: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!Result {
    return switch (try view.readU16(subtable_offset)) {
        1 => chaining_glyph.at(
            Executor,
            view,
            subtable_offset,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        ),
        2 => chaining_class.at(
            Executor,
            view,
            subtable_offset,
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        ),
        3 => chaining_coverage.at(
            Executor,
            view,
            parsed_coverage orelse
                (try accelerator.build.chaining_coverage.parser.parse(
                    view,
                    subtable_offset,
                ) orelse return .{}),
            glyphs,
            position,
            allocator,
            lookup_flag,
            run,
        ),
        else => .{},
    };
}
