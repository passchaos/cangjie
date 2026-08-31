//! Homogeneous ExtensionSubst lookup strategy selection.
//!
//! Extension wrappers only widen payload offsets. Header validation owns the
//! complete wrapper/payload preflight before this module chooses one wrapped
//! lookup strategy, preserving lookup-level atomicity.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const contextual_context =
    @import("../../contextual/context/root.zig");
const contextual_chaining_class =
    @import("../../contextual/chaining/class/root.zig");
const contextual_chaining_glyph =
    @import("../../contextual/chaining/glyph/root.zig");
const direct_alternate = @import("../../direct/alternate/root.zig");
const direct_multiple = @import("../../direct/multiple/root.zig");
const direct_reverse = @import("../../direct/reverse/root.zig");
const direct_single = @import("../../direct/single/root.zig");
const options = @import("../../../runtime/options.zig");
const runtime_dispatch = @import("../../../runtime/dispatch.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded } ||
    std.mem.Allocator.Error;
pub const Options = options.Options;
pub const View = table.View;

/// Execute a homogeneous wrapped lookup, returning `false` for mixed or
/// unsupported wrapper kinds that require the caller's per-subtable fallback.
pub fn apply(
    comptime Executor: type,
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    const wrapped_type = if (runtime_dispatch.extensionType(
        lookup_index,
        run,
    )) |sidecar|
        sidecar.extension_lookup_type orelse 0
    else
        try accelerator.build.lookup.extension.commonType(
            view,
            lookup_offset,
            subtable_count,
        ) orelse 0;

    switch (wrapped_type) {
        1 => try direct_single.extensionLookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        2 => try direct_multiple.extensionLookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        3 => try direct_alternate.extensionLookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            allocator,
            lookup_flag,
            run,
        ),
        5 => {
            if (runtime_dispatch.contextClass(
                lookup_index,
                run,
            )) |sidecar| {
                try contextual_context.acceleratedClassLookup(
                    Executor,
                    view,
                    subtable_count,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                    sidecar,
                );
            } else {
                try contextual_context.extensionLookup(
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
        },
        6 => {
            if (runtime_dispatch.chainingGlyph(
                lookup_index,
                run,
            )) |sidecar| {
                try contextual_chaining_glyph.acceleratedLookup(
                    Executor,
                    view,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                    sidecar,
                );
            } else if (runtime_dispatch.chainingClass(
                lookup_index,
                run,
            )) |sidecar| {
                try contextual_chaining_class.acceleratedLookup(
                    Executor,
                    view,
                    subtable_count,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                    sidecar,
                );
            } else if (runtime_dispatch.chainingCoverage(
                lookup_index,
                run,
            )) |sidecar| {
                try Executor.applyChainingLookup(
                    view,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                    sidecar,
                );
            } else {
                try Executor.applyExtensionChainingLookup(
                    view,
                    lookup_offset,
                    subtable_count,
                    glyphs,
                    allocator,
                    lookup_flag,
                    run,
                );
            }
        },
        8 => try direct_reverse.extensionLookup(
            view,
            lookup_offset,
            subtable_count,
            glyphs,
            lookup_flag,
            run,
            runtime_dispatch.reverseChaining(lookup_index, run),
        ),
        else => return false,
    }
    return true;
}
