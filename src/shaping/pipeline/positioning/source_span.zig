//! Public UTF-8 source extents for post-substitution glyphs.

const ligature_provenance = @import("../../../ligature_provenance.zig");

pub const Span = struct {
    start: usize,
    end: usize,
};

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
    const std = @import("std");
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
