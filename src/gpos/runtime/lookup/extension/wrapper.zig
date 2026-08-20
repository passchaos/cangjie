//! Full-run execution of one ExtensionPos wrapper.

const std = @import("std");
const cursive = @import("../cursive.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const marks = @import("../marks/root.zig");
const model = @import("model.zig");
const pair = @import("../pair/root.zig");
const single = @import("../single.zig");
const table = @import("../../../table/root.zig");

const Adjustment = model.Adjustment;
const CollectFn = model.CollectFn;
const Error = model.Error;
const Options = model.Options;
const View = model.View;

pub fn collect(
    view: View,
    wrapper: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime collectContext: CollectFn,
    comptime collectChaining: CollectFn,
) Error!void {
    if (try view.readU16(wrapper) != 1) return error.UnsupportedGpos;
    const wrapped_type = try view.readU16(wrapper + 2);
    if (wrapped_type == 9) return error.UnsupportedGpos;
    const payload = try table.offset.extensionPayload(
        view,
        wrapper,
        try view.readU32(wrapper + 4),
    );
    switch (wrapped_type) {
        1 => try single.collect(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        2 => try pair.generic.collect(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        3 => try cursive.collect(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        4 => try marks.base.collect(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        5 => try marks.ligature.collect(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        6 => try marks.mark.collect(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        7 => try collectContext(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        8 => try collectChaining(
            view,
            payload,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
        ),
        else => {},
    }
}
