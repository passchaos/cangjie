const std = @import("std");
const run_types = @import("types/runs.zig");
const ellipsis_runs = @import("line_break/reflow/ellipsis_runs.zig");
const reflow_regions = @import("line_break/reflow/regions.zig");
const tabs = @import("paragraph/tabs.zig");
const styled_paragraph = @import("styled_paragraph.zig");
const unicode = @import("../unicode.zig");

pub const Metadata = styled_paragraph.GlyphMetadata;

/// Storage for glyph-parallel attributed paragraph state.
///
/// This sidecar is deliberately separate from the general layout buffer:
/// ordinary shaping should not pay for another list header or touch style
/// state on every buffer reset. Callers reuse one instance alongside their
/// `LayoutBuffer` only when attributed paragraph layout is requested.
pub const Buffer = struct {
    allocator: std.mem.Allocator,
    metadata: std.ArrayList(Metadata) = .empty,
    content_widths: ?@import("types/paragraph.zig").ContentWidths = null,

    pub fn init(allocator: std.mem.Allocator) Buffer {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Buffer) void {
        self.metadata.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *Buffer) void {
        self.metadata.clearRetainingCapacity();
        self.content_widths = null;
    }

    pub fn glyphMetadata(self: *const Buffer) []const Metadata {
        return self.metadata.items;
    }

    pub fn contentWidths(
        self: *const Buffer,
    ) ?@import("types/paragraph.zig").ContentWidths {
        return self.content_widths;
    }
};

pub fn rebuild(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    glyphs: anytype,
    spans: []const styled_paragraph.Span,
) !void {
    list.clearRetainingCapacity();
    try list.ensureTotalCapacity(allocator, glyphs.len);
    for (glyphs) |glyph| {
        const span = styled_paragraph.spanForCluster(spans, glyph.cluster) orelse
            return error.InvalidStyleSpans;
        list.appendAssumeCapacity(.{
            .style_index = span.style_index,
            .layout_spacing = if (glyph.isInlineObject())
                0
            else if (glyph.isTab())
                0
            else if (isWordSpacingCodepoint(glyph.codepoint))
                span.word_spacing
            else if (!isMandatoryLineBreak(glyph.codepoint))
                span.letter_spacing
            else
                0,
            .minimum_line_height = span.minimum_line_height,
        });
    }
}

pub fn applySpacing(
    metadata: []const Metadata,
    glyphs: anytype,
) !void {
    if (metadata.len != glyphs.len) return error.InvalidStyleSpans;
    for (glyphs, metadata) |*glyph, item| {
        glyph.x_advance += item.layout_spacing;
    }
}

/// Rebuild the glyph-parallel sidecar after paragraph reflow inserts automatic
/// line-end hyphens. Existing source glyph metadata remains byte-for-byte
/// unchanged; an insertion inherits paint and minimum height from the style at
/// its source boundary, but never inherits letter/word spacing.
pub fn insertAutomaticHyphenMetadata(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    glyphs: anytype,
    spans: []const styled_paragraph.Span,
) !void {
    var automatic_count: usize = 0;
    for (glyphs) |glyph| {
        automatic_count += @intFromBool(glyph.isAutomaticHyphen());
    }
    if (automatic_count == 0) return;
    const retained_source_count = glyphs.len - automatic_count;
    if (retained_source_count > list.items.len) {
        return error.InvalidStyleSpans;
    }
    for (glyphs) |glyph| {
        if (glyph.isAutomaticHyphen() and
            spanForBoundary(spans, glyph.cluster) == null)
        {
            return error.InvalidStyleSpans;
        }
    }

    const old = try allocator.dupe(Metadata, list.items);
    defer allocator.free(old);
    try list.ensureTotalCapacity(allocator, glyphs.len);
    list.clearRetainingCapacity();
    var old_index: usize = 0;
    for (glyphs) |glyph| {
        if (glyph.isAutomaticHyphen()) {
            const span = spanForBoundary(spans, glyph.cluster).?;
            list.appendAssumeCapacity(.{
                .style_index = span.style_index,
                .layout_spacing = 0,
                .minimum_line_height = span.minimum_line_height,
            });
            continue;
        }
        std.debug.assert(old_index < old.len);
        list.appendAssumeCapacity(old[old_index]);
        old_index += 1;
    }
    // `max_lines` truncation may have removed a source suffix before this
    // pass. The unused tail belongs to omitted glyphs and is intentionally
    // discarded when the rebuilt list adopts `glyphs.len`.
    std.debug.assert(old_index == retained_source_count);
}

pub fn synchronizeAfterTruncation(
    list: *std.ArrayList(Metadata),
    glyph_count: usize,
) !void {
    if (list.items.len < glyph_count) return error.InvalidStyleSpans;
    list.shrinkRetainingCapacity(glyph_count);
}

fn replaceTailWithSynthetic(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    glyph_count: usize,
    synthetic_count: usize,
    terminal: ?Metadata,
) !void {
    if (glyph_count < synthetic_count) return error.InvalidStyleSpans;
    try synchronizeAfterTruncation(list, glyph_count - synthetic_count);
    for (0..synthetic_count) |_| {
        try appendEllipsisStyle(list, allocator, terminal);
    }
    if (list.items.len != glyph_count) return error.InvalidStyleSpans;
}

pub fn appendEllipsis(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    buffer: anytype,
    max_width: f32,
    alignment: anytype,
    alignedLineX: anytype,
    options: anytype,
) !void {
    if (list.items.len != buffer.glyphs.items.len) {
        return error.InvalidStyleSpans;
    }
    if (buffer.lines.items.len == 0 or buffer.runs.items.len == 0) return;

    const line = &buffer.lines.items[buffer.lines.items.len - 1];
    const ellipsis_count: usize = 3;
    const run_index = line.run_start + line.run_len - 1;
    const run_template = buffer.runs.items[run_index];
    const font = run_types.fontForBackend(run_template);
    const dot_metrics = try font.horizontalMetrics(try font.glyphIndex('.'));
    const dot_advance = @as(f32, @floatFromInt(dot_metrics.advance_width)) *
        (run_template.font_size /
            @as(f32, @floatFromInt(font.units_per_em)));
    const ellipsis_width = dot_advance * @as(f32, @floatFromInt(ellipsis_count));
    const space_advance = defaultSpaceAdvance(buffer.glyphs.items);
    const fallback_tab_interval =
        @as(f32, @floatFromInt(@max(1, options.tab_width))) *
        space_advance;
    const region = reflow_regions.stored(line.*, max_width);
    const width_limit = region.width;
    // Optical punctuation hanging is invalid once ellipsis changes the
    // terminal glyph. Restore the full advance sum before fitting the dots.
    line.width = tabs.recomputeRangeWithTerminal(
        buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        options.tab_stops,
        fallback_tab_interval,
        space_advance,
        ellipsis_width,
    );
    // Capture paint and minimum-line-height state before the fit loop can
    // remove every visible glyph. Synthetic dots intentionally do not inherit
    // source letter/word spacing.
    const ellipsis_style = terminalStyle(list.items, buffer.glyphs.items.len);
    // Reserve both parallel streams before mutating either one. Once the fit
    // loop starts, all remaining operations are infallible apart from font
    // lookups already completed above, so an allocation failure cannot leave
    // glyphs and metadata at different lengths.
    try buffer.glyphs.ensureTotalCapacity(
        buffer.allocator,
        buffer.glyphs.items.len + ellipsis_count,
    );
    try list.ensureTotalCapacity(allocator, list.items.len + ellipsis_count);

    // A discretionary hyphen describes continuation onto another visible
    // line. Ellipsis ends the visible text instead, so remove that glyph before
    // ordinary fit trimming even when the dots already fit beside it.
    while (line.glyph_len > 0 and
        buffer.glyphs.items[
            line.glyph_start + line.glyph_len - 1
        ].isDiscretionaryHyphen())
    {
        const remove_index = line.glyph_start + line.glyph_len - 1;
        line.width -= buffer.glyphs.items[remove_index].x_advance;
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        line.width = tabs.recomputeRangeWithTerminal(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
            options.tab_stops,
            fallback_tab_interval,
            space_advance,
            ellipsis_width,
        );
    }

    while (line.glyph_len > 0 and line.width > width_limit) {
        const remove_index = line.glyph_start + line.glyph_len - 1;
        line.width -= buffer.glyphs.items[remove_index].x_advance;
        _ = buffer.glyphs.pop();
        line.glyph_len -= 1;
        line.width = tabs.recomputeRangeWithTerminal(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
            options.tab_stops,
            fallback_tab_interval,
            space_advance,
            ellipsis_width,
        );
    }

    const dot_glyph = try font.glyphIndex('.');
    const cluster = if (line.glyph_len > 0)
        buffer.glyphs.items[line.glyph_start + line.glyph_len - 1].cluster
    else
        0;
    const synthetic_run_index = try ellipsis_runs.prepare(
        buffer,
        buffer.glyphs.items.len,
        run_template,
    );
    for (0..ellipsis_count) |_| {
        try buffer.glyphs.append(buffer.allocator, .{
            .glyph_id = dot_glyph,
            .codepoint = '.',
            .cluster = cluster,
            .x_advance = dot_advance,
        });
        line.glyph_len += 1;
    }
    buffer.runs.items[synthetic_run_index].glyph_len += ellipsis_count;
    line.width = 0;
    for (buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len]) |glyph| {
        line.width += glyph.x_advance;
    }
    try replaceTailWithSynthetic(
        list,
        allocator,
        buffer.glyphs.items.len,
        ellipsis_count,
        ellipsis_style,
    );
    line.run_len = runCountForGlyphs(
        buffer.runs.items,
        line.glyph_start,
        line.glyph_start + line.glyph_len,
    );
    const final_alignment =
        if (tabs.contains(
            buffer.glyphs.items[line.glyph_start .. line.glyph_start + line.glyph_len],
        ))
            line.resolved_alignment orelse alignment
        else
            alignment;
    line.resolved_alignment = final_alignment;
    line.x = region.x + alignedLineX(
        @min(line.width, region.width),
        region.width,
        final_alignment,
    );
}

fn defaultSpaceAdvance(glyphs: anytype) f32 {
    for (glyphs) |glyph| {
        if (glyph.codepoint == ' ') return @max(glyph.x_advance, 1);
    }
    for (glyphs) |glyph| {
        if (!glyph.isTab() and
            glyph.codepoint != '\n' and
            glyph.x_advance > 0)
        {
            return glyph.x_advance;
        }
    }
    return 1;
}

pub fn reorderByPermutation(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    order: []const usize,
) !void {
    if (list.items.len != order.len) return error.InvalidStyleSpans;
    const old = try allocator.dupe(Metadata, list.items);
    defer allocator.free(old);
    var visual = std.ArrayList(Metadata).empty;
    defer visual.deinit(allocator);
    try visual.ensureTotalCapacity(allocator, order.len);
    for (order) |old_index| {
        if (old_index >= old.len) return error.InvalidStyleSpans;
        visual.appendAssumeCapacity(old[old_index]);
    }
    try replaceVisual(list, allocator, visual.items, order.len);
}

fn minimumLineHeight(
    metadata: []const Metadata,
    glyph_count: usize,
    glyph_start: usize,
    glyph_end: usize,
    initial: f32,
) f32 {
    if (metadata.len != glyph_count or
        glyph_start > glyph_end or
        glyph_end > metadata.len)
    {
        return initial;
    }
    var result = initial;
    for (metadata[glyph_start..glyph_end]) |item| {
        if (item.minimum_line_height) |minimum| {
            result = @max(result, minimum);
        }
    }
    return result;
}

pub fn applyMinimumLineHeights(
    metadata: []const Metadata,
    glyph_count: usize,
    lines: anytype,
) void {
    if (metadata.len != glyph_count) return;
    var y_shift: f32 = 0;
    for (lines) |*line| {
        line.y += y_shift;
        const original_height = line.height;
        const minimum = minimumLineHeight(
            metadata,
            glyph_count,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
            line.height,
        );
        if (minimum > line.height) {
            const natural_height = line.ascent + line.descent + line.leading;
            const extra_leading = @max(0, minimum - natural_height);
            line.ascent += extra_leading / 2;
            line.leading += extra_leading / 2;
            line.height = line.ascent + line.descent + line.leading;
            line.baseline = line.ascent;
        }
        // Existing paragraph-spacing and hard-break gaps are encoded in the
        // original y positions. Shift later lines only by this strut's growth.
        y_shift += line.height - original_height;
    }
}

fn replaceVisual(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    visual: []const Metadata,
    glyph_count: usize,
) !void {
    if (visual.len != glyph_count) return error.InvalidStyleSpans;
    list.clearRetainingCapacity();
    try list.appendSlice(allocator, visual);
}

fn terminalStyle(
    metadata: []const Metadata,
    glyph_count: usize,
) ?Metadata {
    if (metadata.len != glyph_count or metadata.len == 0) return null;
    return metadata[metadata.len - 1];
}

fn appendEllipsisStyle(
    list: *std.ArrayList(Metadata),
    allocator: std.mem.Allocator,
    terminal: ?Metadata,
) !void {
    const style = terminal orelse return;
    try list.append(allocator, .{
        .style_index = style.style_index,
        .layout_spacing = 0,
        .minimum_line_height = style.minimum_line_height,
    });
}

fn spanForBoundary(
    spans: []const styled_paragraph.Span,
    boundary: usize,
) ?styled_paragraph.Span {
    if (spans.len == 0) return null;
    // Automatic hyphens are attached to the preceding fragment. At a style
    // boundary, use that fragment's style rather than the next source glyph.
    for (spans) |span| {
        if (boundary > span.byte_start and boundary <= span.byteEnd()) {
            return span;
        }
    }
    return styled_paragraph.spanForCluster(spans, boundary);
}

fn isWordSpacingCodepoint(codepoint: u21) bool {
    return codepoint == ' ';
}

fn isMandatoryLineBreak(codepoint: u21) bool {
    return switch (unicode.lineBreakClassForCodepoint(codepoint)) {
        .mandatory, .carriage_return, .line_feed, .next_line => true,
        else => false,
    };
}

fn runCountForGlyphs(runs: anytype, glyph_start: usize, glyph_end: usize) usize {
    var count: usize = 0;
    for (runs) |run| {
        const run_end = run.glyph_start + run.glyph_len;
        if (run_end <= glyph_start or run.glyph_start >= glyph_end) continue;
        count += 1;
    }
    return count;
}

test "styled buffer stays inactive for ordinary glyph streams" {
    const metadata = [_]Metadata{};
    try std.testing.expectEqual(
        @as(f32, 12),
        minimumLineHeight(&metadata, 2, 0, 2, 12),
    );
}

test "styled ellipsis preserves paint but not source spacing" {
    var list = std.ArrayList(Metadata).empty;
    defer list.deinit(std.testing.allocator);
    try appendEllipsisStyle(&list, std.testing.allocator, .{
        .style_index = 7,
        .layout_spacing = 4,
        .minimum_line_height = 20,
    });
    try std.testing.expectEqual(@as(u32, 7), list.items[0].style_index);
    try std.testing.expectEqual(@as(f32, 0), list.items[0].layout_spacing);
}
