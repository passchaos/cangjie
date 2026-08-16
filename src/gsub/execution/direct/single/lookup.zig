//! Whole-lookup SingleSubst ordering and ExtensionSubst wrappers.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const table = @import("../../../table/root.zig");
const Options = @import("../../../runtime/options.zig").Options;
const matched_positions = @import("../../support/matched_positions.zig");
const subtable = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const View = table.View;

pub fn apply(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (subtable_count == 1) {
        const subtable_offset = lookup_offset +
            try view.readU16(lookup_offset + 6);
        return subtable.apply(
            view,
            subtable_offset,
            glyphs,
            lookup_flag,
            run,
        );
    }

    var matched_stack: [matched_positions.stack_capacity]bool = undefined;
    const matched = try matched_positions.Scratch.init(
        allocator,
        glyphs.items.len,
        &matched_stack,
    );
    defer matched.deinit(allocator);

    for (0..subtable_count) |subtable_index| {
        const subtable_offset = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        try subtable.applyWithMatched(
            view,
            subtable_offset,
            glyphs,
            lookup_flag,
            run,
            matched.items,
        );
    }
}

pub fn applyExtension(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (subtable_count == 1) {
        const wrapper = lookup_offset + try view.readU16(lookup_offset + 6);
        return subtable.apply(
            view,
            try extensionPayload(view, wrapper),
            glyphs,
            lookup_flag,
            run,
        );
    }

    var matched_stack: [matched_positions.stack_capacity]bool = undefined;
    const matched = try matched_positions.Scratch.init(
        allocator,
        glyphs.items.len,
        &matched_stack,
    );
    defer matched.deinit(allocator);

    for (0..subtable_count) |subtable_index| {
        const wrapper = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        try subtable.applyWithMatched(
            view,
            try extensionPayload(view, wrapper),
            glyphs,
            lookup_flag,
            run,
            matched.items,
        );
    }
}

fn extensionPayload(view: View, wrapper: usize) Error!usize {
    return accelerator.build.lookup.extension.payload(view, wrapper, 1);
}
