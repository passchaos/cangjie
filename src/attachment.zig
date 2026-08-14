const std = @import("std");

pub const Type = enum {
    none,
    mark,
    cursive,
};

pub const Direction = enum {
    forward,
    backward,
};

pub const Axis = enum {
    horizontal,
    vertical,
};

pub const Link = struct {
    kind: Type = .none,
    parent_index: ?usize = null,
    /// GPOS snapshots a mark parent's cross-axis placement when the lookup
    /// applies. AAT kerx does not, so its mark links retain final propagation
    /// on both axes. Keeping this on the link prevents one engine's timing
    /// semantics from leaking into the other.
    cross_axis_resolved: bool = false,
};

const max_nesting_level = 64;

pub fn propagateOffsets(comptime Position: type, positions: []Position, links: []Link, direction: Direction, axis: Axis) void {
    const len = @min(positions.len, links.len);
    if (len == 0) return;

    switch (direction) {
        .forward => {
            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (links[i].kind != .none) propagateOne(Position, positions[0..len], links[0..len], i, direction, axis, max_nesting_level);
            }
        },
        .backward => {
            var i = len;
            while (i > 0) {
                i -= 1;
                if (links[i].kind != .none) propagateOne(Position, positions[0..len], links[0..len], i, direction, axis, max_nesting_level);
            }
        },
    }
}

fn propagateOne(comptime Position: type, positions: []Position, links: []Link, index: usize, direction: Direction, axis: Axis, depth: usize) void {
    const link = links[index];
    if (link.kind == .none) return;
    links[index] = .{};

    const parent_index = link.parent_index orelse return;
    if (parent_index >= positions.len) return;
    if (depth == 0) return;

    if (links[parent_index].kind != .none) {
        propagateOne(Position, positions, links, parent_index, direction, axis, depth - 1);
    }

    switch (link.kind) {
        .none => {},
        .mark => propagateMarkOffset(
            Position,
            positions,
            index,
            parent_index,
            direction,
            axis,
            link.cross_axis_resolved,
        ),
        .cursive => propagateCursiveOffset(Position, positions, index, parent_index, axis),
    }
}

fn propagateMarkOffset(comptime Position: type, positions: []Position, index: usize, parent_index: usize, direction: Direction, axis: Axis, cross_axis_resolved: bool) void {
    // Mark attachment already captured the parent's cross-axis placement when
    // its GPOS lookup ran. Only the main-axis placement remains deferred until
    // advances and the complete attachment graph are known. Kerx links leave
    // `cross_axis_resolved` false and continue to propagate both axes here.
    switch (axis) {
        .horizontal => {
            positions[index].x_offset += positions[parent_index].x_offset;
            if (!cross_axis_resolved) positions[index].y_offset += positions[parent_index].y_offset;
        },
        .vertical => {
            positions[index].y_offset += positions[parent_index].y_offset;
            if (!cross_axis_resolved) positions[index].x_offset += positions[parent_index].x_offset;
        },
    }

    if (parent_index < index) {
        switch (direction) {
            .forward => {
                var i = parent_index;
                while (i < index) : (i += 1) subtractAdvance(Position, positions, index, i);
            },
            .backward => {
                var i = parent_index + 1;
                while (i <= index) : (i += 1) addAdvance(Position, positions, index, i);
            },
        }
    } else if (parent_index > index) {
        switch (direction) {
            .forward => {
                var i = index;
                while (i < parent_index) : (i += 1) addAdvance(Position, positions, index, i);
            },
            .backward => {
                var i = index + 1;
                while (i <= parent_index) : (i += 1) subtractAdvance(Position, positions, index, i);
            },
        }
    }
}

fn propagateCursiveOffset(comptime Position: type, positions: []Position, index: usize, parent_index: usize, axis: Axis) void {
    switch (axis) {
        .horizontal => positions[index].y_offset += positions[parent_index].y_offset,
        .vertical => positions[index].x_offset += positions[parent_index].x_offset,
    }
}

fn addAdvance(comptime Position: type, positions: []Position, target_index: usize, advance_index: usize) void {
    positions[target_index].x_offset += positions[advance_index].x_advance;
    positions[target_index].y_offset += positions[advance_index].y_advance;
}

fn subtractAdvance(comptime Position: type, positions: []Position, target_index: usize, advance_index: usize) void {
    positions[target_index].x_offset -= positions[advance_index].x_advance;
    positions[target_index].y_offset -= positions[advance_index].y_advance;
}

test "mark attachment offsets accumulate parent offsets and advances" {
    const Position = struct {
        x_advance: f32 = 0,
        y_advance: f32 = 0,
        x_offset: f32 = 0,
        y_offset: f32 = 0,
    };

    var positions = [_]Position{
        .{ .x_advance = 10, .y_offset = 3 },
        .{ .x_advance = 4 },
        .{ .x_offset = 2, .y_offset = 5 },
    };
    var links = [_]Link{
        .{},
        .{},
        .{ .kind = .mark, .parent_index = 0 },
    };

    propagateOffsets(Position, &positions, &links, .forward, .horizontal);

    try std.testing.expectApproxEqAbs(@as(f32, -12), positions[2].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8), positions[2].y_offset, 0.001);
}

test "resolved GPOS mark links leave cross-axis snapshots unchanged" {
    const Position = struct {
        x_advance: f32 = 0,
        y_advance: f32 = 0,
        x_offset: f32 = 0,
        y_offset: f32 = 0,
    };

    var positions = [_]Position{
        .{ .x_advance = 10, .y_offset = 3 },
        .{ .x_advance = 4 },
        .{ .x_offset = 2, .y_offset = 5 },
    };
    var links = [_]Link{
        .{},
        .{},
        .{ .kind = .mark, .parent_index = 0, .cross_axis_resolved = true },
    };

    propagateOffsets(Position, &positions, &links, .forward, .horizontal);

    try std.testing.expectApproxEqAbs(@as(f32, -12), positions[2].x_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), positions[2].y_offset, 0.001);
}

test "attachment offsets propagate through nested chains" {
    const Position = struct {
        x_advance: f32 = 0,
        y_advance: f32 = 0,
        x_offset: f32 = 0,
        y_offset: f32 = 0,
    };

    var positions = [_]Position{
        .{ .y_offset = 778 },
        .{ .y_offset = -169 },
        .{ .y_offset = -11 },
    };
    var links = [_]Link{
        .{},
        .{ .kind = .mark, .parent_index = 0 },
        .{ .kind = .cursive, .parent_index = 0 },
    };

    propagateOffsets(Position, &positions, &links, .backward, .horizontal);

    try std.testing.expectApproxEqAbs(@as(f32, 609), positions[1].y_offset, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 767), positions[2].y_offset, 0.001);
}
