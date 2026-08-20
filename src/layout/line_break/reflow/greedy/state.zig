//! Persistent logical state and explicit rollback points for greedy reflow.

const std = @import("std");

const automatic_hyphens = @import("../automatic_hyphens.zig");
const line_break_opportunity = @import("../../opportunity.zig");
const opportunities = @import("../opportunities.zig");
const paragraph_types = @import("../../../types/paragraph.zig");
const regions = @import("../regions.zig");
const unicode = @import("../../../../unicode.zig");

pub const Advance = enum {
    line,
    complete,
};

/// Persistent logical state for greedy line selection.
///
/// The state owns only analysis that may be tailored for the active reflow and
/// pending automatic-hyphen decisions. Shaped glyphs, runs, and committed line
/// records remain in the caller's output buffer. Keeping these two ownership
/// domains separate lets retained callers pause after any committed line
/// without copying the paragraph's immutable shaping input.
pub const State = struct {
    allocator: std.mem.Allocator,
    initialized: bool = false,
    complete: bool = false,
    max_width: f32 = 0,
    alignment: paragraph_types.TextAlign = .left,
    uses_exclusions: bool = false,
    max_lines: usize = 0,
    line_start: usize = 0,
    line_byte_start: usize = 0,
    line_width: f32 = 0,
    last_break: opportunities.Candidate = .{},
    y: f32 = 0,
    index: usize = 0,
    line_in_paragraph: usize = 0,
    region_height: f32 = 0,
    active_region: regions.LineRegion = .{
        .x = 0,
        .width = 0,
        .indent = 0,
    },
    consecutive_hyphenated_lines: usize = 0,
    terminal_emergency_line_committed: bool = false,
    selected_automatic_hyphens: std.ArrayList(automatic_hyphens.Selected) = .empty,
    space_advance: f32 = 1,
    fallback_tab_interval: f32 = 1,
    owned_graphemes: ?[]unicode.GraphemeCluster = null,
    grapheme_clusters: []const unicode.GraphemeCluster = &.{},
    owned_line_breaks: ?[]line_break_opportunity.Opportunity = null,
    effective_line_breaks: ?[]const line_break_opportunity.Opportunity = null,
    line_breaks: opportunities.Cursor = undefined,

    pub fn init(allocator: std.mem.Allocator) State {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *State) void {
        if (self.owned_line_breaks) |items| self.allocator.free(items);
        if (self.owned_graphemes) |items| self.allocator.free(items);
        self.selected_automatic_hyphens.deinit(self.allocator);
        self.* = undefined;
    }

    pub const Checkpoint = struct {
        initialized: bool,
        complete: bool,
        line_start: usize,
        line_byte_start: usize,
        line_width: f32,
        last_break: opportunities.Candidate,
        y: f32,
        index: usize,
        line_in_paragraph: usize,
        region_height: f32,
        active_region: regions.LineRegion,
        consecutive_hyphenated_lines: usize,
        terminal_emergency_line_committed: bool,
        line_breaks: opportunities.Cursor,
        selected_automatic_hyphens: []automatic_hyphens.Selected,

        pub fn deinit(
            self: *Checkpoint,
            allocator: std.mem.Allocator,
        ) void {
            allocator.free(self.selected_automatic_hyphens);
            self.* = undefined;
        }
    };

    pub fn save(self: *const State) !Checkpoint {
        return .{
            .initialized = self.initialized,
            .complete = self.complete,
            .line_start = self.line_start,
            .line_byte_start = self.line_byte_start,
            .line_width = self.line_width,
            .last_break = self.last_break,
            .y = self.y,
            .index = self.index,
            .line_in_paragraph = self.line_in_paragraph,
            .region_height = self.region_height,
            .active_region = self.active_region,
            .consecutive_hyphenated_lines = self.consecutive_hyphenated_lines,
            .terminal_emergency_line_committed = self.terminal_emergency_line_committed,
            .line_breaks = self.line_breaks,
            .selected_automatic_hyphens = try self.allocator.dupe(
                automatic_hyphens.Selected,
                self.selected_automatic_hyphens.items,
            ),
        };
    }

    pub fn restore(
        self: *State,
        checkpoint: Checkpoint,
    ) !void {
        try self.selected_automatic_hyphens.ensureTotalCapacity(
            self.allocator,
            checkpoint.selected_automatic_hyphens.len,
        );
        self.selected_automatic_hyphens.clearRetainingCapacity();
        self.selected_automatic_hyphens.appendSliceAssumeCapacity(
            checkpoint.selected_automatic_hyphens,
        );
        self.initialized = checkpoint.initialized;
        self.complete = checkpoint.complete;
        self.capture(
            checkpoint.line_start,
            checkpoint.line_byte_start,
            checkpoint.line_width,
            checkpoint.last_break,
            checkpoint.y,
            checkpoint.index,
            checkpoint.line_in_paragraph,
            checkpoint.region_height,
            checkpoint.active_region,
            checkpoint.consecutive_hyphenated_lines,
            checkpoint.terminal_emergency_line_committed,
            checkpoint.line_breaks,
        );
    }

    pub fn capture(
        self: *State,
        line_start: usize,
        line_byte_start: usize,
        line_width: f32,
        last_break: opportunities.Candidate,
        y: f32,
        index: usize,
        line_in_paragraph: usize,
        region_height: f32,
        active_region: regions.LineRegion,
        consecutive_hyphenated_lines: usize,
        terminal_emergency_line_committed: bool,
        line_breaks: opportunities.Cursor,
    ) void {
        self.line_start = line_start;
        self.line_byte_start = line_byte_start;
        self.line_width = line_width;
        self.last_break = last_break;
        self.y = y;
        self.index = index;
        self.line_in_paragraph = line_in_paragraph;
        self.region_height = region_height;
        self.active_region = active_region;
        self.consecutive_hyphenated_lines =
            consecutive_hyphenated_lines;
        self.terminal_emergency_line_committed =
            terminal_emergency_line_committed;
        self.line_breaks = line_breaks;
    }
};
