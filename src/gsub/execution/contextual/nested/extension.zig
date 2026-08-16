//! Nested ExtensionSubst dispatch at one contextual target.

const std = @import("std");
const chaining_lookup = @import("../chaining/lookup/root.zig");
const contextual_context = @import("../context/root.zig");
const direct = @import("direct.zig");
const direct_single = @import("../../direct/single/root.zig");
const extension_payload =
    @import("../../../accelerator/build/lookup/extension.zig");
const model = @import("../model.zig");
const options = @import("../../../runtime/options.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Change = model.Change;
pub const Error = direct.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn applyAt(
    comptime Executor: type,
    view: View,
    wrapper: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?Change {
    if (try view.readU16(wrapper) != 1) return error.UnsupportedGsub;
    const wrapped_type = try view.readU16(wrapper + 2);
    if (wrapped_type == 7) return error.UnsupportedGsub;
    const payload = try extension_payload.payload(
        view,
        wrapper,
        wrapped_type,
    );

    // ExtensionSubst changes addressing only. Apply cardinality-changing
    // payloads to the real target so later SequenceLookupRecords can remap
    // positions from the actual mutation shape.
    return switch (wrapped_type) {
        1 => if (try direct_single.at(
            view,
            payload,
            glyphs,
            glyph_index,
            lookup_flag,
            run,
        )) .{} else null,
        2 => direct.multiple(
            view,
            payload,
            glyphs,
            glyph_index,
            allocator,
            lookup_flag,
            run,
        ),
        4 => direct.ligature(
            view,
            payload,
            glyphs,
            glyph_index,
            allocator,
            lookup_flag,
            run,
        ),
        5 => if ((try contextual_context.at(
            Executor,
            view,
            payload,
            glyphs,
            glyph_index,
            allocator,
            lookup_flag,
            run,
        )).matched) .{} else null,
        6 => if ((try chaining_lookup.at(
            Executor,
            view,
            payload,
            null,
            glyphs,
            glyph_index,
            allocator,
            lookup_flag,
            run,
        )).matched) .{} else null,
        else => null,
    };
}
