//! Font-run ownership repair for synthetic ellipsis tails.

const run_types = @import("../../types/runs.zig");

pub const Template = run_types.CascadeRun;

/// Drop or clip runs beyond `glyph_count`, then attach an empty synthetic tail
/// run using the terminal source run's font instance.
///
/// The returned run can be extended after dots are appended. This operation is
/// infallible: a removed terminal template frees one existing run slot, while a
/// surviving terminal template is necessarily the compatible contiguous tail.
pub fn prepare(
    buffer: anytype,
    glyph_count: usize,
    template: Template,
) !usize {
    var kept: usize = 0;
    for (buffer.runs.items) |source| {
        if (source.glyph_start >= glyph_count) continue;
        var run = source;
        if (run.glyph_start + run.glyph_len > glyph_count) {
            run.glyph_len = glyph_count - run.glyph_start;
        }
        buffer.runs.items[kept] = run;
        kept += 1;
    }
    buffer.runs.shrinkRetainingCapacity(kept);

    if (kept != 0) {
        const last = &buffer.runs.items[kept - 1];
        if (last.glyph_start + last.glyph_len == glyph_count and
            sameInstance(last.*, template))
        {
            return kept - 1;
        }
    }

    var synthetic = template;
    synthetic.glyph_start = glyph_count;
    synthetic.glyph_len = 0;
    synthetic.x_offset = 0;
    synthetic.y_offset = 0;
    try buffer.runs.ensureUnusedCapacity(buffer.allocator, 1);
    buffer.runs.appendAssumeCapacity(synthetic);
    return buffer.runs.items.len - 1;
}

fn sameInstance(lhs: Template, rhs: Template) bool {
    return lhs.font == rhs.font and
        lhs.font_index == rhs.font_index and
        @as(u32, @bitCast(lhs.font_size)) ==
            @as(u32, @bitCast(rhs.font_size)) and
        lhs.variation_coord_start == rhs.variation_coord_start and
        lhs.variation_coord_len == rhs.variation_coord_len;
}

test "prepare reserves a run across a fontless tail gap" {
    const std = @import("std");
    const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;

    const Buffer = struct {
        allocator: std.mem.Allocator,
        glyphs: std.ArrayList(GlyphPosition) = .empty,
        runs: std.ArrayList(Template) = .empty,
    };
    var buffer = Buffer{ .allocator = std.testing.allocator };
    defer buffer.runs.deinit(buffer.allocator);
    defer buffer.glyphs.deinit(buffer.allocator);
    try buffer.glyphs.appendSlice(buffer.allocator, &.{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 10 },
        .{
            .glyph_id = 0,
            .codepoint = '\t',
            .cluster = 1,
            .x_advance = 20,
            .flags = .{ .tab = true },
        },
    });
    const template = Template{
        // Identity only; the pure run-topology helper never dereferences it.
        .font = @ptrFromInt(0x1000),
        .font_index = 2,
        .font_size = 20,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    };
    try buffer.runs.append(buffer.allocator, template);
    // Force capacity to exactly the occupied count. The implementation must
    // not rely on removing another run before attaching the synthetic tail.
    buffer.runs.shrinkAndFree(buffer.allocator, buffer.runs.items.len);

    const index = try prepare(&buffer, 2, template);
    try std.testing.expectEqual(@as(usize, 1), index);
    try std.testing.expectEqual(@as(usize, 2), buffer.runs.items.len);
    try std.testing.expectEqual(@as(usize, 2), buffer.runs.items[index].glyph_start);
    try std.testing.expectEqual(@as(usize, 0), buffer.runs.items[index].glyph_len);
}

test "prepare reuses a compatible contiguous terminal run" {
    const std = @import("std");
    const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;

    const Buffer = struct {
        allocator: std.mem.Allocator,
        glyphs: std.ArrayList(GlyphPosition) = .empty,
        runs: std.ArrayList(Template) = .empty,
    };
    var buffer = Buffer{ .allocator = std.testing.allocator };
    defer buffer.runs.deinit(buffer.allocator);
    defer buffer.glyphs.deinit(buffer.allocator);
    const template = Template{
        // Identity only; the pure run-topology helper never dereferences it.
        .font = @ptrFromInt(0x1000),
        .font_index = 3,
        .font_size = 20,
        .glyph_start = 0,
        .glyph_len = 1,
        .x_offset = 0,
    };
    try buffer.runs.append(buffer.allocator, template);

    const index = try prepare(&buffer, 1, template);
    try std.testing.expectEqual(@as(usize, 0), index);
    try std.testing.expectEqual(@as(usize, 1), buffer.runs.items.len);
}
