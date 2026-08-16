//! SinglePos execution for lookup, subtable, and nested-target paths.

const std = @import("std");
const accelerator = @import("../../accelerator/root.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;
const matching = @import("../matching.zig");
const options = @import("../options.zig");
const output = @import("../output/root.zig");
const positioning = @import("../../positioning/root.zig");
const table = @import("../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error = table.view.Error || error{UnsupportedGpos};
pub const Options = options.Options;
pub const Parsed = accelerator.model.SinglePositionSubtable;
pub const View = table.View;

const stack_matched_capacity = 128;

const MatchScratch = struct {
    items: []bool,
    owned: bool,

    fn init(
        allocator: std.mem.Allocator,
        length: usize,
        stack: []bool,
    ) std.mem.Allocator.Error!MatchScratch {
        if (length <= stack.len) {
            return .{ .items = stack[0..length], .owned = false };
        }
        return .{
            .items = try allocator.alloc(bool, length),
            .owned = true,
        };
    }

    fn deinit(self: MatchScratch, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.items);
    }
};

/// Apply all SinglePos subtables as ordered alternatives per glyph.
pub fn collectLookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (glyphs.len == 0) return;
    var matched_stack: [stack_matched_capacity]bool = undefined;
    const scratch = try MatchScratch.init(
        allocator,
        glyphs.len,
        &matched_stack,
    );
    defer scratch.deinit(allocator);
    @memset(scratch.items, false);

    for (0..subtable_count) |subtable_index| {
        const subtable_offset = try table.offset.required16(
            view,
            lookup_offset,
            try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            ),
        );
        try collectSubtable(
            view,
            subtable_offset,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            scratch.items,
        );
    }
}

pub fn collectSubtable(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    matched: []bool,
) (Error || std.mem.Allocator.Error)!void {
    if (matched.len != glyphs.len) return error.UnsupportedGpos;
    const parsed =
        try positioning.lookup.single.parse(view, subtable_offset);
    for (glyphs, 0..) |glyph, glyph_index| {
        if (matched[glyph_index]) continue;
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
        const value = try valueForGlyph(view, parsed, glyph) orelse continue;
        try output.adjustments.append(
            adjustments,
            allocator,
            glyph_index,
            value,
            false,
        );
        matched[glyph_index] = true;
    }
}

/// Apply one SinglePos subtable independently, as used by ExtensionPos.
pub fn collect(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    const parsed =
        try positioning.lookup.single.parse(view, subtable_offset);
    for (glyphs, 0..) |glyph, glyph_index| {
        if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) continue;
        const value = try valueForGlyph(view, parsed, glyph) orelse continue;
        try output.adjustments.append(
            adjustments,
            allocator,
            glyph_index,
            value,
            false,
        );
    }
}

pub fn collectAt(
    view: View,
    subtable_offset: usize,
    glyph: GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    return collectAtParsed(
        view,
        try positioning.lookup.single.parse(view, subtable_offset),
        glyph,
        target_index,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn collectAtAccelerated(
    view: View,
    subtables: []const Parsed,
    glyph: GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
    for (subtables) |subtable| {
        const value =
            try valueForGlyph(view, subtable, glyph) orelse continue;
        try output.adjustments.append(
            adjustments,
            allocator,
            target_index,
            value,
            false,
        );
        return true;
    }
    return false;
}

fn collectAtParsed(
    view: View,
    parsed: Parsed,
    glyph: GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    if (matching.lookupIgnoresGlyph(lookup_flag, run, glyph)) return false;
    const value = try valueForGlyph(view, parsed, glyph) orelse return false;
    try output.adjustments.append(
        adjustments,
        allocator,
        target_index,
        value,
        false,
    );
    return true;
}

fn valueForGlyph(
    view: View,
    parsed: Parsed,
    glyph: GlyphId,
) Error!?Adjustment {
    const coverage = try table.coverage.index(
        view,
        parsed.coverage_offset,
        glyph,
    ) orelse return null;
    return switch (parsed.pos_format) {
        1 => parsed.value,
        2 => if (coverage < parsed.value_count)
            try positioning.value_record.read(
                view,
                parsed.values_pos + coverage * parsed.value_size,
                parsed.value_format,
                parsed.subtable_offset,
            )
        else
            null,
        else => error.UnsupportedGpos,
    };
}
