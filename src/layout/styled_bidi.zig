const std = @import("std");
const unicode = @import("../unicode.zig");

/// Return old glyph indexes in the exact visual order used by paragraph bidi.
///
/// Styled metadata uses this permutation after the ordinary paragraph bidi
/// implementation reorders glyphs and font runs. Computing indexes separately
/// keeps style handling out of the common glyph loop and remains exact when
/// several output glyphs share one source cluster.
pub fn visualPermutation(
    allocator: std.mem.Allocator,
    text: []const u8,
    rtl: bool,
    lines: anytype,
    glyphs: anytype,
) ![]usize {
    var paragraph = try unicode.resolveBidiParagraph(
        allocator,
        text,
        if (rtl) .rtl else .ltr,
    );
    defer paragraph.deinit();
    return visualPermutationResolved(
        allocator,
        paragraph,
        lines,
        glyphs,
    );
}

/// Build the styled sidecar permutation from an already-resolved paragraph.
///
/// Attributed paragraph layout also passes the same resolution to the glyph
/// reorder transaction. Keeping this entry point separate avoids running the
/// complete paragraph-wide UAX #9 resolver twice while leaving the standalone
/// helper convenient for tests and callers that do not own a resolution.
pub fn visualPermutationResolved(
    allocator: std.mem.Allocator,
    paragraph: unicode.BidiParagraph,
    lines: anytype,
    glyphs: anytype,
) ![]usize {
    const cluster_index = try buildClusterIndex(allocator, glyphs);
    defer allocator.free(cluster_index);
    const seen = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(seen);
    @memset(seen, false);

    var order = std.ArrayList(usize).empty;
    errdefer order.deinit(allocator);
    try order.ensureTotalCapacity(allocator, glyphs.len);
    for (lines) |line| {
        const line_start = line.glyph_start;
        const line_end = line.glyph_start + line.glyph_len;
        if (line.byte_len != 0 and line_start < line_end) {
            const scalar_start = paragraph.scalarIndexForByte(
                line.byte_start,
            ) orelse return error.InvalidBidiMap;
            const scalar_end = paragraph.scalarIndexForByte(
                line.byte_start + line.byte_len,
            ) orelse return error.InvalidBidiMap;
            var retained_x9: [1]usize = undefined;
            var retained_x9_count: usize = 0;
            for (glyphs[line_start..line_end]) |glyph| {
                if (!glyph.isDiscretionaryHyphen() or
                    glyph.isAutomaticHyphen())
                {
                    continue;
                }
                retained_x9[0] = paragraph.scalarIndexForByte(
                    glyph.cluster,
                ) orelse return error.InvalidBidiMap;
                retained_x9_count = 1;
                break;
            }
            const retained = retained_x9[0..retained_x9_count];
            const visual_order = try paragraph.visualOrderRetaining(
                allocator,
                scalar_start,
                scalar_end,
                retained,
            );
            defer allocator.free(visual_order);
            const line_levels = try paragraph.lineLevelsRetaining(
                allocator,
                scalar_start,
                scalar_end,
                retained,
            );
            defer allocator.free(line_levels);
            for (visual_order) |scalar_index| {
                const scalar = paragraph.scalars[scalar_index];
                const level = line_levels[scalar_index - scalar_start];
                appendItem(
                    cluster_index,
                    seen,
                    line_start,
                    line_end,
                    .{
                        .logical_index = scalar_index,
                        .visual_index = 0,
                        .byte_start = scalar.byte_start,
                        .byte_len = scalar.byte_len,
                        .codepoint = scalar.codepoint,
                        .visual_codepoint = scalar.codepoint,
                        .direction = if (level & 1 != 0) .rtl else .ltr,
                    },
                    &order,
                );
            }
        }
        for (line_start..line_end) |glyph_index| {
            appendIfUnseen(seen, glyph_index, &order);
        }
    }
    // Wrapping can leave discarded boundary spaces outside every visible line.
    // The ordinary layout keeps them after visible glyphs for source/caret
    // metadata, so the sidecar permutation must preserve the same suffix.
    for (glyphs, 0..) |_, glyph_index| {
        appendIfUnseen(seen, glyph_index, &order);
    }
    if (order.items.len != glyphs.len) return error.InvalidBidiMap;
    return try order.toOwnedSlice(allocator);
}

const ClusterEntry = struct {
    cluster: usize,
    glyph_index: usize,
};

fn buildClusterIndex(
    allocator: std.mem.Allocator,
    glyphs: anytype,
) ![]ClusterEntry {
    const entries = try allocator.alloc(ClusterEntry, glyphs.len);
    var monotone = true;
    for (glyphs, entries, 0..) |glyph, *entry, glyph_index| {
        entry.* = .{
            .cluster = if (glyph.isAutomaticHyphen() and glyph_index != 0)
                glyphs[glyph_index - 1].cluster
            else
                glyph.cluster,
            .glyph_index = glyph_index,
        };
        if (glyph_index != 0 and
            (entry.cluster < entries[glyph_index - 1].cluster or
                (entry.cluster == entries[glyph_index - 1].cluster and
                    entry.glyph_index < entries[glyph_index - 1].glyph_index)))
        {
            monotone = false;
        }
    }
    if (!monotone) std.sort.heap(ClusterEntry, entries, {}, entryLessThan);
    return entries;
}

fn entryLessThan(_: void, lhs: ClusterEntry, rhs: ClusterEntry) bool {
    if (lhs.cluster == rhs.cluster) return lhs.glyph_index < rhs.glyph_index;
    return lhs.cluster < rhs.cluster;
}

fn appendItem(
    entries: []const ClusterEntry,
    seen: []bool,
    allowed_start: usize,
    allowed_end: usize,
    item: unicode.BidiMapItem,
    order: *std.ArrayList(usize),
) void {
    const range = clusterRange(entries, item.byte_start) orelse return;
    if (item.direction == .rtl) {
        var index = range.end;
        while (index > range.start) {
            index -= 1;
            const glyph_index = entries[index].glyph_index;
            if (glyph_index < allowed_start or glyph_index >= allowed_end) continue;
            appendIfUnseen(seen, glyph_index, order);
        }
        return;
    }
    for (entries[range.start..range.end]) |entry| {
        if (entry.glyph_index < allowed_start or entry.glyph_index >= allowed_end) {
            continue;
        }
        appendIfUnseen(seen, entry.glyph_index, order);
    }
}

fn appendIfUnseen(
    seen: []bool,
    glyph_index: usize,
    order: *std.ArrayList(usize),
) void {
    if (glyph_index >= seen.len or seen[glyph_index]) return;
    seen[glyph_index] = true;
    order.appendAssumeCapacity(glyph_index);
}

fn clusterRange(
    entries: []const ClusterEntry,
    cluster: usize,
) ?struct { start: usize, end: usize } {
    var low: usize = 0;
    var high = entries.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (entries[mid].cluster < cluster) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    const start = low;
    while (low < entries.len and entries[low].cluster == cluster) : (low += 1) {}
    if (start == low) return null;
    return .{ .start = start, .end = low };
}

test "styled bidi permutation preserves equal-cluster output order" {
    const Glyph = struct {
        cluster: usize,

        fn isAutomaticHyphen(_: @This()) bool {
            return false;
        }

        fn isDiscretionaryHyphen(_: @This()) bool {
            return false;
        }
    };
    const Line = struct {
        glyph_start: usize,
        glyph_len: usize,
        byte_start: usize,
        byte_len: usize,
    };
    const glyphs = [_]Glyph{
        .{ .cluster = 0 },
        .{ .cluster = 1 },
        .{ .cluster = 1 },
    };
    const lines = [_]Line{.{
        .glyph_start = 0,
        .glyph_len = 3,
        .byte_start = 0,
        .byte_len = "Aא".len,
    }};
    const order = try visualPermutation(
        std.testing.allocator,
        "Aא",
        false,
        &lines,
        &glyphs,
    );
    defer std.testing.allocator.free(order);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 1 }, order);
}

test "styled bidi permutation accepts a shared paragraph resolution" {
    const Glyph = struct {
        cluster: usize,

        fn isAutomaticHyphen(_: @This()) bool {
            return false;
        }

        fn isDiscretionaryHyphen(_: @This()) bool {
            return false;
        }
    };
    const Line = struct {
        glyph_start: usize,
        glyph_len: usize,
        byte_start: usize,
        byte_len: usize,
    };
    const text = "Aא";
    const glyphs = [_]Glyph{
        .{ .cluster = 0 },
        .{ .cluster = 1 },
        .{ .cluster = 1 },
    };
    const lines = [_]Line{.{
        .glyph_start = 0,
        .glyph_len = glyphs.len,
        .byte_start = 0,
        .byte_len = text.len,
    }};
    var paragraph = try unicode.resolveBidiParagraph(
        std.testing.allocator,
        text,
        .ltr,
    );
    defer paragraph.deinit();
    const shared = try visualPermutationResolved(
        std.testing.allocator,
        paragraph,
        &lines,
        &glyphs,
    );
    defer std.testing.allocator.free(shared);
    const standalone = try visualPermutation(
        std.testing.allocator,
        text,
        false,
        &lines,
        &glyphs,
    );
    defer std.testing.allocator.free(standalone);
    try std.testing.expectEqualSlices(usize, standalone, shared);
}

test "styled bidi cluster index preserves an already monotone glyph stream" {
    const Glyph = struct {
        cluster: usize,
        fn isAutomaticHyphen(_: @This()) bool {
            return false;
        }
    };
    const glyphs = [_]Glyph{
        .{ .cluster = 0 },
        .{ .cluster = 2 },
        .{ .cluster = 2 },
        .{ .cluster = 5 },
    };
    const entries = try buildClusterIndex(std.testing.allocator, &glyphs);
    defer std.testing.allocator.free(entries);
    for (entries, 0..) |entry, index| {
        try std.testing.expectEqual(index, entry.glyph_index);
    }
}
