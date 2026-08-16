//! Bounds-checked PairPos execution shared by direct and nested lookups.

const std = @import("std");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const matching = @import("../../matching.zig");
const options = @import("../../options.zig");
const output = @import("../../output/root.zig");
const positioning = @import("../../../positioning/root.zig");
const table = @import("../../../table/root.zig");

pub const Adjustment = positioning.Adjustment;
pub const Error = table.view.Error || error{UnsupportedGpos};
pub const Options = options.Options;
pub const Parsed = positioning.lookup.pair.Parsed;
pub const View = table.View;

/// Apply direct PairPos subtables as ordered alternatives for each first glyph.
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
    if (glyphs.len < 2) return;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) {
        var matched_value_2 = false;
        for (0..subtable_count) |subtable_index| {
            const subtable_offset = try table.offset.required16(
                view,
                lookup_offset,
                try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                ),
            );
            const parsed = try positioning.lookup.pair.parse(
                view,
                subtable_offset,
            );
            if (try collectAtParsed(
                view,
                parsed,
                glyphs,
                first_index,
                adjustments,
                allocator,
                lookup_flag,
                run,
            )) {
                matched_value_2 = parsed.value_format_2 != 0;
                break;
            }
        }
        first_index = advanceAfterPair(
            glyphs,
            first_index,
            lookup_flag,
            run,
            matched_value_2,
        );
    }
}

/// Apply homogeneous ExtensionPos(PairPos) wrappers in authored order.
pub fn collectExtensionLookup(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) {
        var matched_value_2 = false;
        for (0..subtable_count) |subtable_index| {
            const wrapper = try table.offset.required16(
                view,
                lookup_offset,
                try view.readU16(
                    lookup_offset + 6 + subtable_index * 2,
                ),
            );
            const payload = try positioning.lookup.dispatch.extensionPayload(
                view,
                wrapper,
                2,
            );
            const parsed = try positioning.lookup.pair.parse(view, payload);
            if (try collectAtParsed(
                view,
                parsed,
                glyphs,
                first_index,
                adjustments,
                allocator,
                lookup_flag,
                run,
            )) {
                matched_value_2 = parsed.value_format_2 != 0;
                break;
            }
        }
        first_index = advanceAfterPair(
            glyphs,
            first_index,
            lookup_flag,
            run,
            matched_value_2,
        );
    }
}

pub fn collect(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!void {
    if (glyphs.len < 2) return;
    const parsed = try positioning.lookup.pair.parse(view, subtable_offset);
    var first_index: usize = 0;
    while (first_index + 1 < glyphs.len) {
        const matched = try collectAtParsed(
            view,
            parsed,
            glyphs,
            first_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
        );
        first_index = advanceAfterPair(
            glyphs,
            first_index,
            lookup_flag,
            run,
            matched and parsed.value_format_2 != 0,
        );
    }
}

pub fn collectAt(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    first_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    return collectAtParsed(
        view,
        try positioning.lookup.pair.parse(view, subtable_offset),
        glyphs,
        first_index,
        adjustments,
        allocator,
        lookup_flag,
        run,
    );
}

pub fn collectAtParsed(
    view: View,
    parsed: Parsed,
    glyphs: []const GlyphId,
    first_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) (Error || std.mem.Allocator.Error)!bool {
    if (first_index + 1 >= glyphs.len) return false;
    if (matching.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs[first_index],
    )) return false;
    const second_index = nextParticipatingGlyph(
        glyphs,
        first_index + 1,
        lookup_flag,
        run,
    ) orelse return false;

    const values = switch (parsed.pos_format) {
        1 => try sparseValues(
            view,
            parsed,
            glyphs[first_index],
            glyphs[second_index],
        ) orelse return false,
        2 => try classValues(
            view,
            parsed,
            glyphs[first_index],
            glyphs[second_index],
        ) orelse return false,
        else => return error.UnsupportedGpos,
    };
    try output.safety.markPairApplication(
        allocator,
        &run,
        glyphs.len,
        first_index,
        second_index,
        values.first,
        values.second,
        parsed.value_format_2 != 0,
    );
    try output.adjustments.append(
        adjustments,
        allocator,
        first_index,
        values.first,
        true,
    );
    try output.adjustments.append(
        adjustments,
        allocator,
        second_index,
        values.second,
        false,
    );
    return true;
}

pub fn advanceAfterPair(
    glyphs: []const GlyphId,
    first_index: usize,
    lookup_flag: u16,
    run: Options,
    has_value_2: bool,
) usize {
    if (!has_value_2) return first_index + 1;
    const second_index = nextParticipatingGlyph(
        glyphs,
        first_index + 1,
        lookup_flag,
        run,
    ) orelse return first_index + 1;
    return second_index + 1;
}

pub fn nextParticipatingGlyph(
    glyphs: []const GlyphId,
    start: usize,
    lookup_flag: u16,
    run: Options,
) ?usize {
    var glyph_index = start;
    while (glyph_index < glyphs.len) : (glyph_index += 1) {
        if (!matching.matchSkipsGlyph(
            lookup_flag,
            run,
            glyphs,
            glyph_index,
        )) return glyph_index;
    }
    return null;
}

const Values = struct {
    first: Adjustment,
    second: Adjustment,
};

fn sparseValues(
    view: View,
    parsed: Parsed,
    first: GlyphId,
    second: GlyphId,
) Error!?Values {
    const pair_set_count = try view.readU16(parsed.subtable_offset + 8);
    const coverage = try table.coverage.index(
        view,
        parsed.coverage_offset,
        first,
    ) orelse return null;
    if (coverage >= pair_set_count) return null;
    const pair_set = try table.offset.required16(
        view,
        parsed.subtable_offset,
        try view.readU16(
            parsed.subtable_offset + 10 + coverage * 2,
        ),
    );
    const pair_count = try view.readU16(pair_set);
    const pair_record = if (view.assume_validated)
        try positioning.lookup.pair.findAfterProof(
            view,
            pair_set,
            pair_count,
            parsed.value_size_1,
            parsed.value_size_2,
            second,
        ) orelse return null
    else
        try positioning.lookup.pair.validatePairSet(
            view,
            pair_set,
            pair_count,
            parsed.value_format_1,
            parsed.value_format_2,
            parsed.value_size_1,
            parsed.value_size_2,
            second,
        ) orelse return null;
    return .{
        .first = try positioning.value_record.read(
            view,
            pair_record + 2,
            parsed.value_format_1,
            pair_set,
        ),
        .second = try positioning.value_record.read(
            view,
            pair_record + 2 + parsed.value_size_1,
            parsed.value_format_2,
            pair_set,
        ),
    };
}

fn classValues(
    view: View,
    parsed: Parsed,
    first: GlyphId,
    second: GlyphId,
) Error!?Values {
    if (try table.coverage.index(
        view,
        parsed.coverage_offset,
        first,
    ) == null) return null;
    const class_1 =
        try table.class_def.value(view, parsed.class_def_1, first);
    const class_2 =
        try table.class_def.value(view, parsed.class_def_2, second);
    if (class_1 >= parsed.class_1_count or class_2 >= parsed.class_2_count) {
        return null;
    }
    const record_size = parsed.value_size_1 + parsed.value_size_2;
    const record = parsed.matrix_offset +
        (@as(usize, class_1) * parsed.class_2_count + class_2) * record_size;
    return .{
        .first = try positioning.value_record.read(
            view,
            record,
            parsed.value_format_1,
            parsed.subtable_offset,
        ),
        .second = try positioning.value_record.read(
            view,
            record + parsed.value_size_1,
            parsed.value_format_2,
            parsed.subtable_offset,
        ),
    };
}
