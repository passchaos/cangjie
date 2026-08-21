//! MultipleSubst format-1 matching for whole runs and contextual targets.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const limits = @import("../../../runtime/limits.zig");
const table = @import("../../../table/root.zig");
const replacement = @import("replacement.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    limits.Error ||
    std.mem.Allocator.Error;
const Entry = accelerator.model.MultipleEntry;
const Multiple = accelerator.model.MultipleSubstitution;
const Options = filtering.Options;
const View = table.View;

const Header = struct {
    coverage_offset: usize,
    sequence_count: u16,
};

pub fn apply(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    const header = try parseHeader(view, subtable_offset);
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) {
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index) or
            filtering.lookupIgnoresGlyph(
                lookup_flag,
                run,
                glyphs.items[glyph_index],
            ))
        {
            glyph_index += 1;
            continue;
        }
        const change = try applyMatchedAt(
            view,
            subtable_offset,
            header,
            glyphs,
            glyph_index,
            allocator,
            run,
        ) orelse {
            glyph_index += 1;
            continue;
        };
        // Inserted glyphs belong to the original target and must not feed back
        // into this lookup. A deletion inserts zero glyphs, so the next
        // original glyph remains at the same physical index.
        glyph_index += change.inserted_len;
    }
}

pub fn applyAccelerated(
    view: View,
    multiple: Multiple,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) {
        if (!filtering.lookupCursorAllowsGlyph(run, glyph_index) or
            filtering.lookupIgnoresGlyph(
                lookup_flag,
                run,
                glyphs.items[glyph_index],
            ))
        {
            glyph_index += 1;
            continue;
        }
        const entry = entryForGlyph(
            multiple.entries,
            glyphs.items[glyph_index],
        ) orelse {
            glyph_index += 1;
            continue;
        };
        const change = try replacement.applyKnown(
            view,
            entry.sequence_offset,
            entry.glyph_count,
            if (entry.glyph_count == 1) entry.single_to else null,
            glyphs,
            glyph_index,
            allocator,
            run,
        );
        glyph_index += change.inserted_len;
    }
}

pub fn applyAt(
    view: View,
    subtable_offset: usize,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!?replacement.Change {
    const header = try parseHeader(view, subtable_offset);
    if (glyph_index >= glyphs.items.len) return null;
    if (filtering.lookupIgnoresGlyph(
        lookup_flag,
        run,
        glyphs.items[glyph_index],
    )) return null;

    return try applyMatchedAt(
        view,
        subtable_offset,
        header,
        glyphs,
        glyph_index,
        allocator,
        run,
    );
}

fn applyMatchedAt(
    view: View,
    subtable_offset: usize,
    header: Header,
    glyphs: *std.ArrayList(GlyphId),
    glyph_index: usize,
    allocator: std.mem.Allocator,
    run: Options,
) Error!?replacement.Change {
    const coverage = try table.coverage.index(
        view,
        header.coverage_offset,
        glyphs.items[glyph_index],
    ) orelse return null;
    if (coverage >= header.sequence_count) return null;
    const sequence_offset = try table.offset.required16(
        view,
        subtable_offset,
        try view.readU16(
            subtable_offset + 6 + coverage * 2,
        ),
    );
    return try replacement.apply(
        view,
        sequence_offset,
        glyphs,
        glyph_index,
        allocator,
        run,
    );
}

fn parseHeader(view: View, subtable_offset: usize) Error!Header {
    if (try view.readU16(subtable_offset) != 1) {
        return error.UnsupportedGsub;
    }
    return .{
        .coverage_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .sequence_count = try view.readU16(subtable_offset + 4),
    };
}

pub fn entryForGlyph(entries: []const Entry, glyph: GlyphId) ?Entry {
    var low: usize = 0;
    var high = entries.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const candidate = entries[middle].glyph;
        if (glyph < candidate) {
            high = middle;
        } else if (glyph > candidate) {
            low = middle + 1;
        } else {
            return entries[middle];
        }
    }
    return null;
}
