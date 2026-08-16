//! Nested-target ExtensionPos execution.

const std = @import("std");
const cursive = @import("../cursive.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const marks = @import("../marks/root.zig");
const model = @import("model.zig");
const pair = @import("../pair/root.zig");
const positioning = @import("../../../positioning/root.zig");
const single = @import("../single.zig");
const table = @import("../../../table/root.zig");

const Adjustment = model.Adjustment;
const CollectAtFn = model.CollectAtFn;
const Error = model.Error;
const Options = model.Options;
const View = model.View;

pub fn collectAt(
    view: View,
    wrapper: usize,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime collectContextAt: CollectAtFn,
    comptime collectChainingAt: CollectAtFn,
) Error!bool {
    if (target_index >= glyphs.len) return false;
    if (try view.readU16(wrapper) != 1) return error.UnsupportedGpos;
    const wrapped_type = try view.readU16(wrapper + 2);
    if (wrapped_type == 9) return error.UnsupportedGpos;
    const payload = try table.offset.extensionPayload(
        view,
        wrapper,
        try view.readU32(wrapper + 4),
    );
    return switch (wrapped_type) {
        1 => single.collectAt(
            view,
            payload,
            glyphs[target_index],
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        2 => pair.generic.collectAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        3 => cursive.collectAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        4 => marks.base.collectAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
            &.{},
        ),
        5 => marks.ligature.collectAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        6 => marks.mark.collectAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        7 => collectContextAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        8 => collectChainingAt(
            view,
            payload,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        else => false,
    };
}
