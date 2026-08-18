//! Flat span, grapheme, and word-start emission.

const std = @import("std");

const draft = @import("draft.zig");
const paragraph_types = @import("../../types/paragraph.zig");
const styled_paragraph = @import("../../styled_paragraph.zig");
const vertical_align = @import("../vertical_align.zig");
const types = @import("types.zig");

pub fn appendLine(
    allocator: std.mem.Allocator,
    layout: paragraph_types.ParagraphLayout,
    line: paragraph_types.ParagraphLine,
    line_index: usize,
    drafts: []const draft.Grapheme,
    style_spans: ?[]const styled_paragraph.Span,
    word_start_bytes: []const usize,
    spans: *std.ArrayList(types.Span),
    graphemes: *std.ArrayList(types.Grapheme),
    word_starts: *std.ArrayList(usize),
) !void {
    var previous_on_line: ?usize = null;
    var start: usize = 0;
    while (start < drafts.len) {
        var end = start + 1;
        while (end < drafts.len and
            sameSpanKey(drafts[start], drafts[end]) and
            drafts[end - 1].byteEnd() == drafts[end].byte_start)
        {
            end += 1;
        }

        var min_x = drafts[start].position;
        var max_x = drafts[start].position + drafts[start].width;
        for (drafts[start..end]) |item| {
            min_x = @min(
                min_x,
                @min(item.position, item.position + item.width),
            );
            max_x = @max(
                max_x,
                @max(item.position, item.position + item.width),
            );
        }

        const grapheme_start = graphemes.items.len;
        const word_start_start = word_starts.items.len;
        for (drafts[start..end], 0..) |item, relative_index| {
            try graphemes.append(allocator, .{
                .byte_start = item.byte_start,
                .byte_len = item.byte_len,
                .inline_position = item.position - min_x,
                .width = item.width,
                .authored_ligature_caret = item.authored_ligature_caret,
            });
            if (containsSorted(word_start_bytes, item.byte_start)) {
                try word_starts.append(allocator, relative_index);
            }
        }

        const run = if (drafts[start].run_index) |run_index| run: {
            if (run_index >= layout.runs.len) {
                return error.InvalidParagraphLayout;
            }
            const source = layout.runs[run_index];
            break :run types.FontRun{
                .run_index = run_index,
                .font = source.font,
                .cascade_index = source.font_index,
                .font_size = source.font_size,
            };
        } else null;
        const block_bounds = if (run) |font_run| block: {
            const source_run = layout.runs[font_run.run_index];
            const alignment = if (style_spans) |source_spans|
                (styled_paragraph.spanForCluster(
                    source_spans,
                    drafts[start].byte_start,
                ) orelse return error.InvalidStyleSpans).vertical_align
            else
                .baseline;
            const metrics = @import("../../line_break/reflow/geometry.zig")
                .defaultBaselineMetrics(
                @import("../../types/runs.zig").fontForBackend(source_run),
                source_run.font_size,
            );
            const baseline =
                line.y + line.baseline +
                vertical_align.fontOffset(line, source_run, alignment);
            break :block paragraph_types.TextRect{
                .x = min_x,
                .y = baseline - metrics.ascent,
                .width = @max(0, max_x - min_x),
                .height = metrics.ascent + metrics.descent,
            };
        } else paragraph_types.TextRect{
            .x = min_x,
            .y = line.y,
            .width = @max(0, max_x - min_x),
            .height = line.height,
        };
        const span_index = spans.items.len;
        try spans.append(allocator, .{
            .line_index = line_index,
            .font_run = run,
            .style_index = drafts[start].style_index,
            .direction = drafts[start].direction,
            .byte_start = drafts[start].byte_start,
            .byte_len = drafts[end - 1].byteEnd() -
                drafts[start].byte_start,
            .bounds = block_bounds,
            .grapheme_start = grapheme_start,
            .grapheme_len = end - start,
            .word_start_start = word_start_start,
            .word_start_len = word_starts.items.len - word_start_start,
            .previous_on_line = previous_on_line,
        });
        if (previous_on_line) |previous| {
            spans.items[previous].next_on_line = span_index;
        }
        previous_on_line = span_index;
        start = end;
    }
}

fn sameSpanKey(lhs: draft.Grapheme, rhs: draft.Grapheme) bool {
    return lhs.run_index == rhs.run_index and
        lhs.style_index == rhs.style_index and
        lhs.direction == rhs.direction;
}

fn containsSorted(values: []const usize, target: usize) bool {
    return std.sort.binarySearch(
        usize,
        values,
        target,
        compareUsize,
    ) != null;
}

fn compareUsize(target: usize, value: usize) std.math.Order {
    return std.math.order(target, value);
}
