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
    if (intervals.items.len == 0) {
        return .{ .available = .{
            .x = container_x,
            .width = container_width,
        } };
    }
    std.sort.heap(Region, intervals.items, {}, regionLessThan);

    var cursor = container_x;
    var best = Region{ .x = container_x, .width = 0 };
    for (intervals.items) |interval| {
        if (interval.x > cursor) {
            chooseBest(&best, .{
                .x = cursor,
                .width = interval.x - cursor,
            }, rtl);
        }
        cursor = @max(cursor, interval.x + interval.width);
        if (cursor >= container_x + container_width) break;
    }
    if (cursor < container_x + container_width) {
        chooseBest(&best, .{
            .x = cursor,
            .width = container_x + container_width - cursor,
        }, rtl);
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
