//! SingleSubst format primitives for whole runs and contextual targets.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const mutation = @import("../../../runtime/mutation.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error;
const Options = filtering.Options;
const Single = accelerator.model.SingleSubstitution;
const View = table.View;

pub fn apply(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
) Error!void {
    return applyWithMatched(
        view,
        subtable_offset,
        glyphs,
        lookup_flag,
        run,
        null,
    );
}

pub fn applyWithMatched(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    lookup_flag: u16,
    run: Options,
    matched: ?[]bool,
) Error!void {
    const format = try view.readU16(subtable_offset);
    const coverage_offset = try requiredCoverage(view, subtable_offset);
    const delta = if (format == 1)
        try view.readI16(subtable_offset + 4)
    else
        0;
    const glyph_count = if (format == 2)
        try view.readU16(subtable_offset + 4)
    else
        0;
    if (format != 1 and format != 2) return error.UnsupportedGsub;

    for (glyphs.items, 0..) |*glyph, glyph_index| {
        if (matched) |items| {
            if (items[glyph_index]) continue;
        }
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index)) continue;
        if (filtering.lookupIgnoresGlyph(lookup_flag, run, glyph.*)) continue;
        const coverage = try table.coverage.index(
            view,
            coverage_offset,
            glyph.*,
        ) orelse continue;

        if (format == 1) {
            glyph.* = applyDelta(glyph.*, delta);
        } else {
            if (coverage >= glyph_count) continue;
            glyph.* = try view.readU16(
                subtable_offset + 6 + coverage * 2,
            );
        }
        mutation.markSubstituted(run, glyph_index);
        if (matched) |items| items[glyph_index] = true;
    }
}

pub fn applyAt(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    lookup_flag: u16,
    run: Options,
) Error!bool {
    if (glyph_index >= glyphs.items.len) return false;
    if (filtering.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs.items[glyph_index],
    )) return false;

    const format = try view.readU16(subtable_offset);
    const coverage_offset = try requiredCoverage(view, subtable_offset);
    switch (format) {
        1 => {
            const delta = try view.readI16(subtable_offset + 4);
            if (try table.coverage.index(
                view,
                coverage_offset,
                glyphs.items[glyph_index],
            ) == null) return false;
            glyphs.items[glyph_index] = applyDelta(
                glyphs.items[glyph_index],
                delta,
            );
        },
        2 => {
            const glyph_count = try view.readU16(subtable_offset + 4);
            const coverage = try table.coverage.index(
                view,
                coverage_offset,
                glyphs.items[glyph_index],
            ) orelse return false;
            if (coverage >= glyph_count) return false;
            glyphs.items[glyph_index] = try view.readU16(
                subtable_offset + 6 + coverage * 2,
            );
        },
        else => return error.UnsupportedGsub,
    }
    mutation.markSubstituted(run, glyph_index);
    return true;
}

pub fn applyAcceleratedAt(
    view: View,
    single: Single,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    run: Options,
) Error!bool {
    if (!single.enabled or glyph_index >= glyphs.items.len) return false;
    if (single.dense_mapping.len != 0) {
        const glyph = glyphs.items[glyph_index];
        if (glyph >= single.dense_mapping.len) return false;
        const encoded = single.dense_mapping[glyph];
        if (encoded == 0) return false;
        glyphs.items[glyph_index] = encoded - 1;
        mutation.markSubstituted(run, glyph_index);
        return true;
    }
    if (single.single_mapping) {
        if (glyphs.items[glyph_index] != single.single_from) return false;
        glyphs.items[glyph_index] = single.single_to;
    } else switch (single.subst_format) {
        1 => {
            if (try table.coverage.index(
                view,
                single.coverage_offset,
                glyphs.items[glyph_index],
            ) == null) return false;
            glyphs.items[glyph_index] = applyDelta(
                glyphs.items[glyph_index],
                single.delta,
            );
        },
        2 => {
            const coverage = try table.coverage.index(
                view,
                single.coverage_offset,
                glyphs.items[glyph_index],
            ) orelse return false;
            if (coverage >= single.glyph_count) return false;
            glyphs.items[glyph_index] = try view.readU16(
                single.substitutes_pos + coverage * 2,
            );
        },
        else => return false,
    }
    mutation.markSubstituted(run, glyph_index);
    return true;
}

fn requiredCoverage(view: View, subtable_offset: usize) Error!usize {
    return table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
}

fn applyDelta(glyph: GlyphId, delta: i16) GlyphId {
    return @bitCast(@as(i16, @bitCast(glyph)) +% delta);
}
