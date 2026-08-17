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
    const cluster_index = try buildClusterIndex(allocator, glyphs);
    defer allocator.free(cluster_index);
    const seen = try allocator.alloc(bool, glyphs.len);
    defer allocator.free(seen);
    @memset(seen, false);

    var order = std.ArrayList(usize).empty;
    errdefer order.deinit(allocator);
    try order.ensureTotalCapacity(allocator, glyphs.len);
    const base_direction: unicode.BidiClass = if (rtl) .rtl else .ltr;
    for (lines) |line| {
        const line_start = line.glyph_start;
        const line_end = line.glyph_start + line.glyph_len;
        if (line.byte_len != 0 and line_start < line_end) {
            var map = try unicode.buildBidiMap(
                allocator,
                text[line.byte_start .. line.byte_start + line.byte_len],
                base_direction,
            );
            defer map.deinit();
            for (map.items) |item_value| {
                var item = item_value;
                item.byte_start += line.byte_start;
                appendItem(
                    cluster_index,
                    seen,
                    line_start,
                    line_end,
                    item,
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
    for (glyphs, entries, 0..) |glyph, *entry, glyph_index| {
        entry.* = .{
            .cluster = if (glyph.isAutomaticHyphen() and glyph_index != 0)
                glyphs[glyph_index - 1].cluster
            else
                glyph.cluster,
            .glyph_index = glyph_index,
        };
    }
    std.sort.heap(ClusterEntry, entries, {}, entryLessThan);
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
