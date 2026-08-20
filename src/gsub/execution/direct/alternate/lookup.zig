//! Whole-lookup AlternateSubst ordering and ExtensionSubst wrappers.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const Options = @import("../../../runtime/options.zig").Options;
const table = @import("../../../table/root.zig");
const matched_positions = @import("../../support/matched_positions.zig");
const subtable = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error || error{InvalidShapingInput};
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
    return applyKind(
        .direct,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
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
    return applyKind(
        .extension,
        view,
        lookup_offset,
        subtable_count,
        glyphs,
        allocator,
        lookup_flag,
        run,
    );
}

const Kind = enum { direct, extension };

fn applyKind(
    comptime kind: Kind,
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    var matched_stack: [matched_positions.stack_capacity]bool = undefined;
    const matched = try matched_positions.Scratch.init(
        allocator,
        glyphs.items.len,
        &matched_stack,
    );
    defer matched.deinit(allocator);

    for (0..subtable_count) |subtable_index| {
        const child = lookup_offset + try view.readU16(
            lookup_offset + 6 + subtable_index * 2,
        );
        const subtable_offset = switch (kind) {
            .direct => child,
            .extension => try accelerator.build.lookup.extension.payload(
                view,
                child,
                3,
            ),
        };
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
