//! Construction of logical text spans from final paragraph geometry.

const std = @import("std");

const draft = @import("draft.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const placement = @import("placement.zig");
const source = @import("source.zig");
const spans_impl = @import("spans.zig");
const styled_paragraph = @import("../../styled_paragraph.zig");
const unicode = @import("../../../unicode.zig");
const types = @import("types.zig");

pub const Options = struct {
    /// Base direction used to lay out the paragraph.
    ///
    /// This must match the paragraph shaping option. It cannot be inferred
    /// from final visual glyph order because explicit base direction affects
    /// neutral text and UAX #9 line-level resets.
    direction: types.Direction = .ltr,
};

pub fn build(
    allocator: std.mem.Allocator,
    text: []const u8,
    layout: paragraph_types.ParagraphLayout,
    options: Options,
) !types.TextGeometry {
    return buildInternal(allocator, text, layout, null, options);
}

pub fn buildStyled(
    allocator: std.mem.Allocator,
    text: []const u8,
    layout: paragraph_types.ParagraphLayout,
    spans: []const styled_paragraph.Span,
    options: Options,
) !types.TextGeometry {
    try styled_paragraph.validatePartition(text, spans);
    return buildInternal(allocator, text, layout, spans, options);
}

fn buildInternal(
    allocator: std.mem.Allocator,
    text: []const u8,
    layout: paragraph_types.ParagraphLayout,
    style_spans: ?[]const styled_paragraph.Span,
    options: Options,
) !types.TextGeometry {
    try source.validateLayout(text, layout);

    var bidi = try unicode.resolveBidiParagraph(
        allocator,
        text,
        switch (options.direction) {
            .ltr => .ltr,
            .rtl => .rtl,
        },
    );
    defer bidi.deinit();

    const source_graphemes = try unicode.itemizeGraphemeClusters(
        allocator,
        text,
    );
    defer allocator.free(source_graphemes);
    const owners = try source.buildOwners(allocator, layout);
    defer allocator.free(owners);
    const word_start_bytes = try source.collectWordStarts(allocator, text);
    defer allocator.free(word_start_bytes);

    var output_lines = std.ArrayList(types.Line).empty;
    errdefer output_lines.deinit(allocator);
    var output_spans = std.ArrayList(types.Span).empty;
    errdefer output_spans.deinit(allocator);
    var output_graphemes = std.ArrayList(types.Grapheme).empty;
    errdefer output_graphemes.deinit(allocator);
    var output_word_starts = std.ArrayList(usize).empty;
    errdefer output_word_starts.deinit(allocator);
    var drafts = std.ArrayList(draft.Grapheme).empty;
    defer drafts.deinit(allocator);

    for (layout.lines, 0..) |line, line_index| {
        const line_span_start = output_spans.items.len;
        drafts.clearRetainingCapacity();
        const source_range = source.graphemeRangeForLine(
            source_graphemes,
            line.byte_start,
            line.byteEnd(),
        ) orelse return error.InvalidParagraphLayout;

        const scalar_start = bidi.scalarIndexForByte(line.byte_start) orelse
            return error.InvalidParagraphLayout;
        const scalar_end = bidi.scalarIndexForByte(line.byteEnd()) orelse
            return error.InvalidParagraphLayout;
        const line_levels = try bidi.lineLevels(
            allocator,
            scalar_start,
            scalar_end,
        );
        {
            defer allocator.free(line_levels);
            for (source_graphemes[source_range.start..source_range.end]) |item| {
                const grapheme_scalar_start =
                    bidi.scalarIndexForByte(item.byte_start) orelse
                    return error.InvalidParagraphLayout;
                const grapheme_scalar_end = bidi.scalarIndexForByte(
                    item.byte_start + item.byte_len,
                ) orelse return error.InvalidParagraphLayout;
                try drafts.append(allocator, .{
                    .byte_start = item.byte_start,
                    .byte_len = item.byte_len,
                    .direction = source.directionForLevels(
                        line_levels,
                        scalar_start,
                        grapheme_scalar_start,
                        grapheme_scalar_end,
                        bidi.base_level,
                    ),
                    .run_index = source.ownerForRange(
                        owners,
                        item.byte_start,
                        item.byte_start + item.byte_len,
                    ),
                    .style_index = if (style_spans) |source_spans|
                        source.styleForByte(
                            source_spans,
                            item.byte_start,
                        ) orelse return error.InvalidStyleSpans
                    else
                        null,
                });
            }
        }

        try placement.applyLine(allocator, layout, line, drafts.items);
        placement.resolveMissingPositions(line.x, drafts.items);
        placement.resolveMissingOwners(drafts.items);
        try spans_impl.appendLine(
            allocator,
            layout,
            line,
            line_index,
            drafts.items,
            word_start_bytes,
            &output_spans,
            &output_graphemes,
            &output_word_starts,
        );
        try output_lines.append(allocator, .{
            .byte_start = line.byte_start,
            .byte_len = line.byte_len,
            .bounds = .{
                .x = line.x,
                .y = line.y,
                .width = line.width,
                .height = line.height,
            },
            .span_start = line_span_start,
            .span_len = output_spans.items.len - line_span_start,
        });
    }

    const owned_lines = try output_lines.toOwnedSlice(allocator);
    errdefer allocator.free(owned_lines);
    const owned_spans = try output_spans.toOwnedSlice(allocator);
    errdefer allocator.free(owned_spans);
    const owned_graphemes = try output_graphemes.toOwnedSlice(allocator);
    errdefer allocator.free(owned_graphemes);
    const owned_word_starts = try output_word_starts.toOwnedSlice(allocator);
    return .{
        .allocator = allocator,
        .source_byte_len = text.len,
        .lines = owned_lines,
        .spans = owned_spans,
        .graphemes = owned_graphemes,
        .word_starts = owned_word_starts,
    };
}
