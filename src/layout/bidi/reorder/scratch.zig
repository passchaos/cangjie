//! Reusable storage for line-local bidi permutation.
//!
//! Paragraph layout repeatedly visits arrays proportional to the glyph count.
//! Keeping those arrays beside the reusable layout output avoids allocating and
//! freeing the same ownership map and visual transaction on every layout call.

const std = @import("std");

const GlyphPosition = @import("../../glyph_position.zig").GlyphPosition;
const run_types = @import("../../types/runs.zig");
const mapping = @import("mapping.zig");
const runs = @import("runs.zig");

pub const Scratch = struct {
    old_runs: std.ArrayList(run_types.CascadeRun) = .empty,
    old_glyphs: std.ArrayList(GlyphPosition) = .empty,
    glyph_run_indices: std.ArrayList(usize) = .empty,
    glyph_cluster_index: std.ArrayList(mapping.ClusterEntry) = .empty,
    seen: std.ArrayList(bool) = .empty,
    visual_run_indices: std.ArrayList(usize) = .empty,
    line_levels: std.ArrayList(u8) = .empty,
    visual_order: std.ArrayList(usize) = .empty,

    pub fn deinit(self: *Scratch, allocator: std.mem.Allocator) void {
        self.visual_order.deinit(allocator);
        self.line_levels.deinit(allocator);
        self.visual_run_indices.deinit(allocator);
        self.seen.deinit(allocator);
        self.glyph_cluster_index.deinit(allocator);
        self.glyph_run_indices.deinit(allocator);
        self.old_glyphs.deinit(allocator);
        self.old_runs.deinit(allocator);
        self.* = .{};
    }

    /// Move the logical output aside and build its two permutation indexes.
    ///
    /// `applyLines` cannot reorder in place: later visual lines still refer to
    /// logical indexes and a visual font run can split into several fragments.
    /// Swapping list owners instead of copying their contents also gives the
    /// destination the capacity retained from the preceding transaction.
    pub fn begin(
        self: *Scratch,
        allocator: std.mem.Allocator,
        output_runs: *std.ArrayList(run_types.CascadeRun),
        output_glyphs: *std.ArrayList(GlyphPosition),
    ) !void {
        self.clear();
        std.mem.swap(std.ArrayList(run_types.CascadeRun), &self.old_runs, output_runs);
        std.mem.swap(std.ArrayList(GlyphPosition), &self.old_glyphs, output_glyphs);
        errdefer self.rollback(output_runs, output_glyphs);
        try runs.buildGlyphRunIndicesInto(
            allocator,
            &self.glyph_run_indices,
            self.old_runs.items,
            self.old_glyphs.items.len,
        );
        try mapping.buildClusterIndexInto(
            allocator,
            &self.glyph_cluster_index,
            self.old_glyphs.items,
        );
        try self.seen.resize(allocator, self.old_glyphs.items.len);
        @memset(self.seen.items, false);
        try output_glyphs.ensureTotalCapacity(allocator, self.old_glyphs.items.len);
        try self.visual_run_indices.ensureTotalCapacity(
            allocator,
            self.old_glyphs.items.len,
        );
    }

    /// Restore the exact logical lists if a later permutation step fails.
    pub fn rollback(
        self: *Scratch,
        output_runs: *std.ArrayList(run_types.CascadeRun),
        output_glyphs: *std.ArrayList(GlyphPosition),
    ) void {
        output_runs.clearRetainingCapacity();
        output_glyphs.clearRetainingCapacity();
        std.mem.swap(
            std.ArrayList(run_types.CascadeRun),
            &self.old_runs,
            output_runs,
        );
        std.mem.swap(
            std.ArrayList(GlyphPosition),
            &self.old_glyphs,
            output_glyphs,
        );
    }

    fn clear(self: *Scratch) void {
        self.old_runs.clearRetainingCapacity();
        self.old_glyphs.clearRetainingCapacity();
        self.glyph_run_indices.clearRetainingCapacity();
        self.glyph_cluster_index.clearRetainingCapacity();
        self.seen.clearRetainingCapacity();
        self.visual_run_indices.clearRetainingCapacity();
        self.line_levels.clearRetainingCapacity();
        self.visual_order.clearRetainingCapacity();
    }
};

test "reorder scratch retains capacity while replacing its snapshot" {
    var scratch: Scratch = .{};
    defer scratch.deinit(std.testing.allocator);
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
        .{ .glyph_id = 2, .codepoint = 'B', .cluster = 1, .x_advance = 1 },
        .{ .glyph_id = 3, .codepoint = 'C', .cluster = 2, .x_advance = 1 },
    };
    var output_glyphs = std.ArrayList(GlyphPosition).empty;
    defer output_glyphs.deinit(std.testing.allocator);
    try output_glyphs.appendSlice(std.testing.allocator, &glyphs);
    var output_runs = std.ArrayList(run_types.CascadeRun).empty;
    defer output_runs.deinit(std.testing.allocator);
    try scratch.begin(std.testing.allocator, &output_runs, &output_glyphs);
    const glyph_capacity = scratch.old_glyphs.capacity;
    const output_capacity = output_glyphs.capacity;
    try std.testing.expectEqualSlices(usize, &.{
        runs.no_run,
        runs.no_run,
        runs.no_run,
    }, scratch.glyph_run_indices.items);

    try output_glyphs.appendSlice(std.testing.allocator, glyphs[0..2]);
    try scratch.begin(std.testing.allocator, &output_runs, &output_glyphs);
    try std.testing.expectEqual(glyph_capacity, output_glyphs.capacity);
    try std.testing.expectEqual(output_capacity, scratch.old_glyphs.capacity);
    try std.testing.expectEqual(@as(usize, 2), scratch.seen.items.len);
    try std.testing.expectEqual(@as(usize, 0), output_glyphs.items.len);
}

test "failed scratch preparation restores output ownership" {
    var scratch: Scratch = .{};
    defer scratch.deinit(std.testing.allocator);
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .x_advance = 1 },
    };
    var output_glyphs = std.ArrayList(GlyphPosition).empty;
    defer output_glyphs.deinit(std.testing.allocator);
    try output_glyphs.appendSlice(std.testing.allocator, &glyphs);
    var output_runs = std.ArrayList(run_types.CascadeRun).empty;
    defer output_runs.deinit(std.testing.allocator);
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        scratch.begin(failing.allocator(), &output_runs, &output_glyphs),
    );
    try std.testing.expectEqualSlices(
        GlyphPosition,
        &glyphs,
        output_glyphs.items,
    );
    try std.testing.expectEqual(@as(usize, 0), output_runs.items.len);
}
