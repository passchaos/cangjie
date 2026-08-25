//! Public UTF-8 source extents for post-substitution glyphs.

const std = @import("std");
const ligature_provenance = @import("../../../ligature_provenance.zig");

pub const Span = struct {
    start: usize,
    end: usize,
};

/// Resolve a span after the source stage proved one byte per scalar. The
/// shaping pipeline keeps both glyph sidecars parallel, while ASCII source
/// ends are strictly increasing. Ligature provenance is monotone as well, so
/// its last retained component owns the maximal end instead of requiring the
/// generic defensive scan.
pub inline fn forAsciiGlyph(
    glyph_index: usize,
    source_index: usize,
    cluster_index: usize,
    starts: []const usize,
    ends: []const usize,
    ligature_components: *const ligature_provenance.Store,
) Span {
    std.debug.assert(glyph_index < ligature_components.infos.items.len);
    std.debug.assert(source_index < ends.len);
    std.debug.assert(cluster_index < starts.len);

    const info = ligature_components.infos.items[glyph_index];
    const end = if (info.isLigature()) ligature_end: {
        const sources = ligature_components.componentSources(info) orelse
            break :ligature_end ends[source_index];
        std.debug.assert(sources.len != 0);
        std.debug.assert(sources[sources.len - 1] < ends.len);
        break :ligature_end ends[sources[sources.len - 1]];
    } else ends[source_index];
    return .{ .start = starts[cluster_index], .end = end };
}

pub fn forGlyph(
    glyph_index: usize,
    fallback_source_index: usize,
    fallback_cluster_index: usize,
    starts: []const usize,
    ends: []const usize,
    ligature_components: *const ligature_provenance.Store,
) ?Span {
    const cluster = forIndex(fallback_cluster_index, starts, ends);
    if (glyph_index < ligature_components.infos.items.len and
        ligature_components.infos.items[glyph_index].component_count > 1)
    {
        const info = ligature_components.infos.items[glyph_index];
        var span: ?Span = null;
        const component_sources =
            ligature_components.componentSources(info) orelse return cluster;
        for (component_sources) |component_source| {
            const component_span =
                forIndex(component_source, starts, ends) orelse continue;
            if (span) |*accumulated| {
                accumulated.start =
                    @min(accumulated.start, component_span.start);
                accumulated.end = @max(accumulated.end, component_span.end);
            } else {
                span = component_span;
            }
        }
        if (span) |value| {
            // Components determine the extent, while GSUB cluster ownership
            // determines the public start after reordering or later ligatures.
            return .{
                .start = if (cluster) |owner| owner.start else value.start,
                .end = value.end,
            };
        }
    }
    const span =
        forIndex(fallback_source_index, starts, ends) orelse return cluster;
    const owner = cluster orelse return span;
    return .{ .start = owner.start, .end = span.end };
}

fn forIndex(
    source_index: usize,
    starts: []const usize,
    ends: []const usize,
) ?Span {
    if (starts.len == 0) return null;
    const index = @min(source_index, starts.len - 1);
    const start = starts[index];
    const end = if (index < ends.len) @max(ends[index], start) else start;
    return .{ .start = start, .end = end };
}

test "ligature extents honor a merged cluster owner" {
    const starts = [_]usize{ 0, 3, 6, 9 };
    const ends = [_]usize{ 3, 6, 9, 12 };
    var provenance = ligature_provenance.Store{};
    defer provenance.deinit(std.testing.allocator);
    const info =
        try provenance.addLigature(std.testing.allocator, &.{ 2, 3 });
    try provenance.infos.append(std.testing.allocator, info);

    const span = forGlyph(
        0,
        2,
        1,
        &starts,
        &ends,
        &provenance,
    ).?;

    try std.testing.expectEqual(Span{ .start = 3, .end = 12 }, span);
}

test "ASCII spans use the cluster owner and final ligature component" {
    const starts = [_]usize{ 20, 21, 22, 23 };
    const ends = [_]usize{ 21, 22, 23, 24 };
    var provenance = ligature_provenance.Store{};
    defer provenance.deinit(std.testing.allocator);
    const info = try provenance.addLigature(std.testing.allocator, &.{ 1, 3 });
    try provenance.infos.append(std.testing.allocator, info);

    const span = forAsciiGlyph(0, 1, 0, &starts, &ends, &provenance);
    try std.testing.expectEqual(Span{ .start = 20, .end = 24 }, span);
}
