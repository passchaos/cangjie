//! Transactional insertion of selected automatic line-end hyphens.
//!
//! Greedy reflow selects opportunities against the immutable logical glyph
//! stream. Only after all line ranges are known do we grow the glyph array and
//! rewrite glyph/run/line indexes in one pass. This avoids invalidating the
//! reflow cursor and keeps every synthetic hyphen owned by the same cascade
//! run that supplied its metrics.

const std = @import("std");

const discretionary_hyphen = @import("../../discretionary_hyphen.zig");
const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const geometry = @import("geometry.zig");

pub const Selected = struct {
    line_index: usize,
    insert_index: usize,
    run_index: usize,
    glyph: GlyphPosition,
};

pub fn appendSelected(
    selected: *std.ArrayList(Selected),
    allocator: std.mem.Allocator,
    line_index: usize,
    insert_index: usize,
    candidate: @import("opportunities.zig").AutomaticHyphen,
) !void {
    try selected.append(allocator, .{
        .line_index = line_index,
        .insert_index = insert_index,
        .run_index = candidate.run_index,
        .glyph = discretionary_hyphen.synthetic(
            candidate.resolved,
            candidate.byte_offset,
            candidate.vertical,
        ),
    });
}

/// Shift pending absolute indexes after a still-uncommitted glyph replacement.
pub fn shiftAfterReplacement(
    selected: []Selected,
    old_range_end: usize,
    glyph_delta: isize,
    runs: anytype,
) void {
    if (glyph_delta == 0) return;
    for (selected) |*item| {
        if (item.insert_index >= old_range_end) {
            item.insert_index = addSigned(item.insert_index, glyph_delta);
        }
        // `line_transaction.replaceRange` may split/rebuild runs. Resolve the
        // owner again from the shifted insertion boundary rather than carrying
        // a stale run-array index into materialization.
        if (item.insert_index == 0) continue;
        item.run_index = runIndexForGlyph(
            runs,
            item.insert_index - 1,
        ) orelse item.run_index;
    }
}

/// Materialize selected hyphens without exposing a partially updated buffer on
/// allocation failure. The selection list is monotone in logical glyph order;
/// debug assertions guard that reflow invariant before in-place index updates.
pub fn materialize(buffer: anytype, selected: []const Selected) !void {
    if (selected.len == 0) return;

    for (selected, 0..) |item, index| {
        std.debug.assert(item.line_index < buffer.lines.items.len);
        std.debug.assert(item.run_index < buffer.runs.items.len);
        std.debug.assert(item.insert_index <= buffer.glyphs.items.len);
        if (index != 0) {
            std.debug.assert(
                selected[index - 1].insert_index <= item.insert_index,
            );
            std.debug.assert(
                selected[index - 1].line_index < item.line_index,
            );
        }
    }

    try buffer.glyphs.ensureTotalCapacity(
        buffer.allocator,
        buffer.glyphs.items.len + selected.len,
    );

    var inserted: usize = 0;
    for (selected) |item| {
        const index = item.insert_index + inserted;
        buffer.glyphs.insertAssumeCapacity(index, item.glyph);

        // Runs before the owner shift with the insertion. The owning run grows
        // around it, while later runs shift one glyph to preserve coverage.
        for (buffer.runs.items, 0..) |*run, run_index| {
            if (run_index < item.run_index) continue;
            if (run_index == item.run_index) {
                run.glyph_len += 1;
            } else {
                run.glyph_start += 1;
            }
        }

        for (buffer.lines.items, 0..) |*line, line_index| {
            if (line_index < item.line_index) continue;
            if (line_index == item.line_index) {
                line.glyph_len += 1;
            } else {
                line.glyph_start += 1;
            }
        }
        inserted += 1;
    }

    // Insertion can split one cascade run into several visual ranges only
    // after bidi. Before reordering it simply extends the owning logical run,
    // so recomputing line intersections is sufficient here.
    for (buffer.lines.items) |*line| {
        const range = geometry.runRangeForGlyphs(
            buffer.runs.items,
            line.glyph_start,
            line.glyph_start + line.glyph_len,
        );
        line.run_start = range.start;
        line.run_len = range.len;
    }
}

fn runIndexForGlyph(runs: anytype, glyph_index: usize) ?usize {
    for (runs, 0..) |run, run_index| {
        if (glyph_index >= run.glyph_start and
            glyph_index < run.glyph_start + run.glyph_len)
        {
            return run_index;
        }
    }
    return null;
}

fn addSigned(value: usize, delta: isize) usize {
    if (delta >= 0) return value + @as(usize, @intCast(delta));
    return value - @as(usize, @intCast(-delta));
}

test "pending hyphen indexes follow a prior glyph replacement" {
    const Run = struct {
        glyph_start: usize,
        glyph_len: usize,
    };
    var selected = [_]Selected{.{
        .line_index = 0,
        .insert_index = 4,
        .run_index = 1,
        .glyph = .{
            .glyph_id = 1,
            .codepoint = '-',
            .cluster = 4,
            .x_advance = 3,
        },
    }};
    const runs = [_]Run{
        .{ .glyph_start = 0, .glyph_len = 2 },
        .{ .glyph_start = 2, .glyph_len = 3 },
    };

    shiftAfterReplacement(&selected, 3, -1, &runs);
    try std.testing.expectEqual(@as(usize, 3), selected[0].insert_index);
    try std.testing.expectEqual(@as(usize, 1), selected[0].run_index);
}

test "materialization shifts glyph run and line ranges atomically" {
    const Run = struct {
        glyph_start: usize,
        glyph_len: usize,
    };
    const Line = struct {
        glyph_start: usize,
        glyph_len: usize,
        run_start: usize,
        run_len: usize,
    };
    const Buffer = struct {
        allocator: std.mem.Allocator,
        glyphs: std.ArrayList(GlyphPosition),
        runs: std.ArrayList(Run),
        lines: std.ArrayList(Line),
    };

    var buffer = Buffer{
        .allocator = std.testing.allocator,
        .glyphs = .empty,
        .runs = .empty,
        .lines = .empty,
    };
    defer buffer.lines.deinit(buffer.allocator);
    defer buffer.runs.deinit(buffer.allocator);
    defer buffer.glyphs.deinit(buffer.allocator);
    try buffer.glyphs.appendSlice(buffer.allocator, &.{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 5 },
        .{ .glyph_id = 2, .codepoint = 'B', .cluster = 1, .x_advance = 5 },
        .{ .glyph_id = 3, .codepoint = 'C', .cluster = 2, .x_advance = 5 },
    });
    try buffer.runs.appendSlice(buffer.allocator, &.{
        .{ .glyph_start = 0, .glyph_len = 2 },
        .{ .glyph_start = 2, .glyph_len = 1 },
    });
    try buffer.lines.appendSlice(buffer.allocator, &.{
        .{ .glyph_start = 0, .glyph_len = 1, .run_start = 0, .run_len = 1 },
        .{ .glyph_start = 1, .glyph_len = 2, .run_start = 0, .run_len = 2 },
    });

    try materialize(&buffer, &.{
        .{
            .line_index = 0,
            .insert_index = 1,
            .run_index = 0,
            .glyph = .{
                .glyph_id = 9,
                .codepoint = 0x2010,
                .cluster = 1,
                .x_advance = 3,
                .flags = .{
                    .discretionary_hyphen = true,
                    .automatic_hyphen = true,
                },
            },
        },
        .{
            .line_index = 1,
            .insert_index = 3,
            .run_index = 1,
            .glyph = .{
                .glyph_id = 10,
                .codepoint = 0x2010,
                .cluster = 3,
                .x_advance = 3,
                .flags = .{
                    .discretionary_hyphen = true,
                    .automatic_hyphen = true,
                },
            },
        },
    });

    try std.testing.expectEqual(@as(usize, 5), buffer.glyphs.items.len);
    try std.testing.expect(buffer.glyphs.items[1].isAutomaticHyphen());
    try std.testing.expect(buffer.glyphs.items[4].isAutomaticHyphen());
    try std.testing.expectEqual(@as(usize, 3), buffer.runs.items[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 3), buffer.runs.items[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 2), buffer.runs.items[1].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), buffer.lines.items[0].glyph_len);
    try std.testing.expectEqual(@as(usize, 2), buffer.lines.items[1].glyph_start);
    try std.testing.expectEqual(@as(usize, 3), buffer.lines.items[1].glyph_len);
}
