//! Whole-lookup MultipleSubst ordering and ExtensionSubst wrappers.

const std = @import("std");
const accelerator = @import("../../../accelerator/root.zig");
const filtering = @import("../../../runtime/filtering.zig");
const limits = @import("../../../runtime/limits.zig");
const table = @import("../../../table/root.zig");
const replacement = @import("replacement.zig");
const subtable = @import("subtable.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Error = table.coverage.Error ||
    limits.Error ||
    std.mem.Allocator.Error;
const Options = filtering.Options;
const View = table.View;

pub fn apply(
    view: View,
    lookup_offset: usize,
    subtable_count: u16,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
) Error!void {
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
) Error!void {
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
) Error!void {
    if (subtable_count == 1) {
        const child = lookup_offset + try view.readU16(lookup_offset + 6);
        const subtable_offset = switch (kind) {
            .direct => child,
            .extension => try extensionPayload(view, child),
        };
        return subtable.apply(
            view,
            subtable_offset,
            glyphs,
            allocator,
            lookup_flag,
            run,
        );
    }

    var glyph_index: usize = 0;
    while (glyph_index < glyphs.items.len) {
        if (!filtering.sourceFeatureAllowsGlyph(run, glyph_index) or
            filtering.lookupIgnoresGlyph(
                lookup_flag,
                run,
                glyphs.items[glyph_index],
            ))
        {
            glyph_index += 1;
            continue;
        }

        var change: ?replacement.Change = null;
        for (0..subtable_count) |subtable_index| {
            const child = lookup_offset + try view.readU16(
                lookup_offset + 6 + subtable_index * 2,
            );
            const subtable_offset = switch (kind) {
                .direct => child,
                .extension => try extensionPayload(view, child),
            };
            change = try subtable.applyAt(
                view,
                subtable_offset,
                glyphs,
                glyph_index,
                allocator,
                lookup_flag,
                run,
            );
            if (change != null) break;
        }
        if (change) |applied| {
            glyph_index += applied.inserted_len;
        } else {
            glyph_index += 1;
        }
    }
}

fn extensionPayload(view: View, wrapper: usize) Error!usize {
    return accelerator.build.lookup.extension.payload(view, wrapper, 2);
}
