//! Rectangular paragraph exclusions resolved into one line fragment.

const std = @import("std");

/// A half-open paragraph-space rectangle unavailable to wrapped text.
///
/// `x`/`y` identify the physical left/top edge. Width and height are
/// nonnegative, and every field must be finite. Boundary-only contact with a
/// line band does not count as overlap.
pub const Exclusion = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const Region = struct {
    x: f32,
    width: f32,
};

pub const Resolution = union(enum) {
    available: Region,
    blocked_until: f32,
};

pub fn validate(items: []const Exclusion) !void {
    for (items) |item| {
        if (!std.math.isFinite(item.x) or
            !std.math.isFinite(item.y) or
            !std.math.isFinite(item.width) or
            !std.math.isFinite(item.height) or
            item.width < 0 or item.height < 0)
        {
            return error.InvalidParagraphOptions;
        }
    }
}

pub fn resolve(
    allocator: std.mem.Allocator,
    items: []const Exclusion,
    container_x: f32,
    container_width: f32,
    line_top: f32,
    line_height: f32,
    rtl: bool,
) !Resolution {
    if (items.len == 0 or
        container_width <= 0 or
        line_height <= 0)
    {
        return .{ .available = .{
            .x = container_x,
            .width = container_width,
        } };
    }

    var intervals = std.ArrayList(Region).empty;
    defer intervals.deinit(allocator);
    var blocked_until = std.math.inf(f32);
    for (items) |item| {
        if (item.width == 0 or item.height == 0 or
            item.y >= line_top + line_height or
            item.y + item.height <= line_top)
        {
            continue;
        }
        const left = @max(container_x, item.x);
        const right = @min(
            container_x + container_width,
            item.x + item.width,
        );
        if (right <= left) continue;
        try intervals.append(allocator, .{
            .x = left,
            .width = right - left,
        });
        blocked_until = @min(blocked_until, item.y + item.height);
    }
    return resolveIntervals(
        intervals.items,
        container_x,
        container_width,
        rtl,
        blocked_until,
    );
}

/// Resolve a positive-down inline fragment for one physical vertical column.
///
/// This is the axis transpose of `resolve`: exclusions intersecting the
/// column's x band contribute unavailable y intervals. A fully blocked column
/// returns the nearest physical edge in `block_direction` so vertical flow can
/// advance its block cursor without creating an empty source column.
pub fn resolveVertical(
    allocator: std.mem.Allocator,
    items: []const Exclusion,
    container_y: f32,
    container_height: f32,
    column_left: f32,
    column_width: f32,
    block_direction: enum { left_to_right, right_to_left },
) !Resolution {
    if (items.len == 0 or
        container_height <= 0 or
        column_width <= 0)
    {
        return .{ .available = .{
            .x = container_y,
            .width = container_height,
        } };
    }

    var intervals = std.ArrayList(Region).empty;
    defer intervals.deinit(allocator);
    var blocked_until = std.math.inf(f32);
    for (items) |item| {
        if (item.width == 0 or item.height == 0 or
            item.x >= column_left + column_width or
            item.x + item.width <= column_left)
        {
            continue;
        }
        const top = @max(container_y, item.y);
        const bottom = @min(
            container_y + container_height,
            item.y + item.height,
        );
        if (bottom <= top) continue;
        try intervals.append(allocator, .{
            .x = top,
            .width = bottom - top,
        });
        blocked_until = switch (block_direction) {
            .left_to_right => @min(blocked_until, item.x + item.width),
            // `column_left` is the physical left edge. Advancing one RL band
            // places the next left edge immediately before the exclusion.
            .right_to_left => if (std.math.isInf(blocked_until))
                item.x - column_width
            else
                @max(blocked_until, item.x - column_width),
        };
    }
    return resolveIntervals(
        intervals.items,
        container_y,
        container_height,
        false,
        blocked_until,
    );
}

fn resolveIntervals(
    intervals: []Region,
    container_start: f32,
    container_size: f32,
    prefer_end: bool,
    blocked_until: f32,
) Resolution {
    if (intervals.len == 0) {
        return .{ .available = .{
            .x = container_start,
            .width = container_size,
        } };
    }
    std.sort.heap(Region, intervals, {}, regionLessThan);

    var cursor = container_start;
    var best = Region{ .x = container_start, .width = 0 };
    for (intervals) |interval| {
        if (interval.x > cursor) {
            chooseBest(&best, .{
                .x = cursor,
                .width = interval.x - cursor,
            }, prefer_end);
        }
        cursor = @max(cursor, interval.x + interval.width);
        if (cursor >= container_start + container_size) break;
    }
    if (cursor < container_start + container_size) {
        chooseBest(&best, .{
            .x = cursor,
            .width = container_start + container_size - cursor,
        }, prefer_end);
    }
    if (best.width > 0) return .{ .available = best };
    return .{ .blocked_until = blocked_until };
}

fn chooseBest(best: *Region, candidate: Region, rtl: bool) void {
    if (candidate.width > best.width or
        (candidate.width == best.width and
            ((rtl and candidate.x > best.x) or
                (!rtl and candidate.x < best.x))))
    {
        best.* = candidate;
    }
}

fn regionLessThan(_: void, lhs: Region, rhs: Region) bool {
    if (lhs.x != rhs.x) return lhs.x < rhs.x;
    return lhs.width < rhs.width;
}

test "vertical exclusion resolution transposes block and inline axes" {
    const items = [_]Exclusion{.{
        .x = 0,
        .y = 0,
        .width = 20,
        .height = 30,
    }};
    const fragment = try resolveVertical(
        std.testing.allocator,
        &items,
        0,
        100,
        0,
        20,
        .left_to_right,
    );
    try std.testing.expectEqual(
        Resolution{ .available = .{ .x = 30, .width = 70 } },
        fragment,
    );
    const blocked = try resolveVertical(
        std.testing.allocator,
        &items,
        0,
        30,
        0,
        20,
        .left_to_right,
    );
    try std.testing.expectEqual(
        Resolution{ .blocked_until = 20 },
        blocked,
    );
    const blocked_rl = try resolveVertical(
        std.testing.allocator,
        &items,
        0,
        30,
        0,
        20,
        .right_to_left,
    );
    try std.testing.expectEqual(
        Resolution{ .blocked_until = -20 },
        blocked_rl,
    );
}
