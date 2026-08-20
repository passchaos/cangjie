//! Whole-lookup ExtensionPos execution with per-kind precedence.

const std = @import("std");
const cursive = @import("../cursive.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const marks = @import("../marks/root.zig");
const model = @import("model.zig");
const pair = @import("../pair/root.zig");
const positioning = @import("../../../positioning/root.zig");
const scratch = @import("scratch.zig");
const single = @import("../single.zig");
const table = @import("../../../table/root.zig");

const Adjustment = model.Adjustment;
const CollectFn = model.CollectFn;
const Error = model.Error;
const Options = model.Options;
const View = model.View;

pub fn collectSingle(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    if (glyphs.len == 0) return;
    var matched_stack: [scratch.stack_capacity]bool = undefined;
    const matched_scratch =
        try scratch.Bool.init(allocator, glyphs.len, &matched_stack);
    defer matched_scratch.deinit(allocator);
    @memset(matched_scratch.items, false);

    for (0..subtable_count) |subtable_index| {
        const wrapper = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(lookup_offset + 6 + subtable_index * 2),
        );
        try single.collectSubtable(
            view,
            try positioning.lookup.dispatch.extensionPayload(view, wrapper, 1),
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            matched_scratch.items,
        );
    }
}

pub fn collectMixed(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime collectContext: CollectFn,
    comptime collectChaining: CollectFn,
) Error!void {
    var single_stack: [scratch.stack_capacity]bool = undefined;
    const single_matched =
        try scratch.Bool.init(allocator, glyphs.len, &single_stack);
    defer single_matched.deinit(allocator);
    @memset(single_matched.items, false);

    var pair_stack: [scratch.stack_capacity]bool = undefined;
    const pair_matched =
        try scratch.Bool.init(allocator, glyphs.len, &pair_stack);
    defer pair_matched.deinit(allocator);
    @memset(pair_matched.items, false);

    var consumes_stack: [scratch.stack_capacity]bool = undefined;
    const pair_consumes_second =
        try scratch.Bool.init(allocator, glyphs.len, &consumes_stack);
    defer pair_consumes_second.deinit(allocator);
    @memset(pair_consumes_second.items, false);

    for (0..subtable_count) |subtable_index| {
        const wrapper = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(lookup_offset + 6 + subtable_index * 2),
        );
        const wrapper_format = try view.readU16(wrapper);
        if (wrapper_format != 1) return error.UnsupportedGpos;
        const wrapped_type = try view.readU16(wrapper + 2);
        if (wrapped_type == 9) return error.UnsupportedGpos;
        const payload = try table.offset.extensionPayload(
            view,
            wrapper,
            try view.readU32(wrapper + 4),
        );

        switch (wrapped_type) {
            1 => try single.collectSubtable(
                view,
                payload,
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
                single_matched.items,
            ),
            2 => {
                if (glyphs.len < 2) continue;
                var first_index: usize = 0;
                const parsed = try positioning.lookup.pair.parse(view, payload);
                while (first_index + 1 < glyphs.len) {
                    var matched_value_2 =
                        pair_matched.items[first_index] and
                        pair_consumes_second.items[first_index];
                    if (!pair_matched.items[first_index] and
                        try pair.generic.collectAtParsed(
                            view,
                            parsed,
                            glyphs,
                            first_index,
                            adjustments,
                            allocator,
                            lookup_flag,
                            run,
                        ))
                    {
                        pair_matched.items[first_index] = true;
                        matched_value_2 = parsed.value_format_2 != 0;
                        pair_consumes_second.items[first_index] =
                            matched_value_2;
                    }
                    first_index = pair.generic.advanceAfterPair(
                        glyphs,
                        first_index,
                        lookup_flag,
                        run,
                        matched_value_2,
                    );
                }
            },
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
}
