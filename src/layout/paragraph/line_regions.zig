//! Explicit per-line regions and replay coordination.
//!
//! A region is paragraph-space geometry selected by the caller for one final
//! visual line. Reflow remains ordinary and deterministic: the resolver grows
//! a prefix of regions, asks the caller to lay out again, then yields the next
//! line's natural geometry as a placement request.

const std = @import("std");

const options_mod = @import("options.zig");
const paragraph_types = @import("../types/paragraph.zig");

pub const Region = struct {
    /// Physical block-axis start: x for vertical paragraphs and the ordinary
    /// horizontal fragment start otherwise.
    x: f32,
    /// Physical inline-axis start. This is y for both current writing-mode
    /// families because vertical inline progression is positive-down.
    y: f32,
    /// Available inline measure: physical width horizontally and height
    /// vertically. The column's block width remains font/object-derived.
    width: f32,
};

pub fn validate(items: []const Region) !void {
    for (items) |item| {
        if (!std.math.isFinite(item.x) or
            !std.math.isFinite(item.y) or
            !std.math.isFinite(item.width) or
            item.width <= 0)
        {
            return error.InvalidParagraphOptions;
        }
    }
}

pub const Pass = struct {
    generation: u64,
    options: options_mod.Options,
};

pub const Request = struct {
    token: u64,
    line_index: usize,
    natural_x: f32,
    natural_y: f32,
    natural_width: f32,
    line_height: f32,
    byte_start: usize,
    byte_len: usize,
};

pub const Step = union(enum) {
    complete,
    place: Request,
};

/// Concrete replay protocol for pagination, columns, and custom containers.
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    base_options: options_mod.Options = undefined,
    regions: std.ArrayList(Region) = .empty,
    generation: u64 = 0,
    next_token: u64 = 1,
    active: bool = false,
    complete: bool = false,
    pending: ?Request = null,

    pub fn init(allocator: std.mem.Allocator) Resolver {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Resolver) void {
        self.regions.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn begin(self: *Resolver, options: options_mod.Options) !void {
        try options_mod.validate(options);
        const input = try self.allocator.dupe(Region, options.line_regions);
        defer self.allocator.free(input);
        try self.regions.ensureTotalCapacity(self.allocator, input.len);
        self.regions.clearRetainingCapacity();
        self.regions.appendSliceAssumeCapacity(input);
        self.base_options = options;
        self.pending = null;
        self.active = true;
        self.complete = false;
        self.bumpGeneration();
    }

    pub fn pass(self: *const Resolver) !Pass {
        if (!self.active) return error.LineRegionResolverNotActive;
        if (self.pending != null) return error.LineRegionPlacementPending;
        var options = self.base_options;
        options.line_regions = self.regions.items;
        return .{ .generation = self.generation, .options = options };
    }

    pub fn next(
        self: *Resolver,
        pass_value: Pass,
        layout: paragraph_types.ParagraphLayout,
    ) !Step {
        if (!self.active or pass_value.generation != self.generation) {
            return error.StaleLineRegionPass;
        }
        if (self.pending) |request| return .{ .place = request };
        if (self.complete) return .complete;

        for (
            layout.lines[0..@min(layout.lines.len, self.regions.items.len)],
            self.regions.items,
        ) |line, region| {
            const matches = if (layout.writing_mode.isVertical())
                sameFloat(line.region_x, region.x) and
                    sameFloat(line.region_inline_start, region.y) and
                    sameFloat(line.region_inline_size, region.width)
            else
                sameFloat(line.region_x, region.x) and
                    sameFloat(line.y, region.y) and
                    sameFloat(line.region_width, region.width);
            if (!matches) {
                return error.InvalidLineRegionLayout;
            }
        }
        // If every produced line has a caller region, this pass is final.
        if (layout.lines.len <= self.regions.items.len) {
            self.complete = true;
            return .complete;
        }
        const line_index = self.regions.items.len;
        const line = layout.lines[line_index];
        const request = Request{
            .token = self.next_token,
            .line_index = line_index,
            .natural_x = line.region_x,
            .natural_y = if (layout.writing_mode.isVertical())
                line.region_inline_start
            else
                line.y,
            .natural_width = if (layout.writing_mode.isVertical())
                line.region_inline_size
            else
                line.region_width,
            .line_height = line.height,
            .byte_start = line.byte_start,
            .byte_len = line.byte_len,
        };
        self.next_token +%= 1;
        if (self.next_token == 0) self.next_token = 1;
        self.pending = request;
        return .{ .place = request };
    }

    pub fn submit(
        self: *Resolver,
        request: Request,
        region: Region,
    ) !void {
        const pending = self.pending orelse
            return error.NoPendingLineRegion;
        if (request.token != pending.token or
            request.line_index != pending.line_index)
        {
            return error.StaleLineRegionRequest;
        }
        try validate(&.{region});
        try self.regions.append(self.allocator, region);
        self.pending = null;
        self.complete = false;
        self.bumpGeneration();
    }

    pub fn resolvedOptions(self: *const Resolver) !options_mod.Options {
        if (!self.active or self.pending != null or !self.complete) {
            return error.LineRegionPlacementIncomplete;
        }
        return (try self.pass()).options;
    }

    pub fn items(self: *const Resolver) []const Region {
        return self.regions.items;
    }

    fn bumpGeneration(self: *Resolver) void {
        self.generation +%= 1;
        if (self.generation == 0) self.generation = 1;
    }
};

fn sameFloat(lhs: f32, rhs: f32) bool {
    return @as(u32, @bitCast(lhs)) == @as(u32, @bitCast(rhs));
}

test "line regions require finite positive measure" {
    try validate(&.{.{ .x = -10, .y = 20, .width = 30 }});
    for ([_]Region{
        .{ .x = std.math.nan(f32), .y = 0, .width = 1 },
        .{ .x = 0, .y = std.math.inf(f32), .width = 1 },
        .{ .x = 0, .y = 0, .width = 0 },
        .{ .x = 0, .y = 0, .width = -1 },
    }) |item| {
        try std.testing.expectError(
            error.InvalidParagraphOptions,
            validate(&.{item}),
        );
    }
}
