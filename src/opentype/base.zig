const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Script = struct {
    tag: [4]u8,
    default_baseline_index: ?u16 = null,
    coordinates: []?i16,
};

pub const Axis = struct {
    baseline_tags: [][4]u8,
    scripts: []Script,
};

pub const Info = struct {
    version: u32,
    horizontal: ?Axis = null,
    vertical: ?Axis = null,
};

pub fn validate(data: []const u8, offset: usize, length: usize) Error!void {
    if (offset > data.len or length > data.len - offset or length < 8) return error.BadSfnt;
    const version = try bin.readU32At(data, offset);
    if (version != 0x00010000 and version != 0x00010001) return error.BadSfnt;
    const horiz_offset: usize = @intCast(try bin.readU16At(data, offset + 4));
    const vert_offset: usize = @intCast(try bin.readU16At(data, offset + 6));
    if (horiz_offset != 0) try validateAxis(data, offset, length, horiz_offset);
    if (vert_offset != 0) try validateAxis(data, offset, length, vert_offset);
}

fn validateAxis(data: []const u8, base_offset: usize, base_length: usize, axis_offset: usize) Error!void {
    if (axis_offset > base_length or base_length - axis_offset < 4) return error.BadSfnt;
    const axis_start = base_offset + axis_offset;
    const tag_list_offset: usize = @intCast(try bin.readU16At(data, axis_start));
    const script_list_offset: usize = @intCast(try bin.readU16At(data, axis_start + 2));
    var baseline_count: usize = 0;
    if (tag_list_offset != 0) baseline_count = try validateBaseTags(data, base_offset, base_length, axis_offset, tag_list_offset);
    if (script_list_offset == 0) return error.BadSfnt;
    try validateBaseScripts(data, base_offset, base_length, axis_offset, script_list_offset, baseline_count);
}

fn validateBaseTags(data: []const u8, base_offset: usize, base_length: usize, axis_offset: usize, tag_list_offset: usize) Error!usize {
    const start = try checkedAxisChildStart(base_offset, base_length, axis_offset, tag_list_offset, 2);
    const count: usize = @intCast(try bin.readU16At(data, start));
    if (count > (base_offset + base_length - (start + 2)) / 4) return error.BadSfnt;
    var previous: ?[4]u8 = null;
    for (0..count) |index| {
        const tag = try bin.readTagAt(data, start + 2 + index * 4);
        if (previous) |last| {
            if (std.mem.order(u8, &last, &tag) != .lt) return error.BadSfnt;
        }
        previous = tag;
    }
    return count;
}

fn validateBaseScripts(data: []const u8, base_offset: usize, base_length: usize, axis_offset: usize, script_list_offset: usize, baseline_count: usize) Error!void {
    const start = try checkedAxisChildStart(base_offset, base_length, axis_offset, script_list_offset, 2);
    const count: usize = @intCast(try bin.readU16At(data, start));
    if (count > (base_offset + base_length - (start + 2)) / 6) return error.BadSfnt;
    var previous_tag: ?[4]u8 = null;
    for (0..count) |index| {
        const record = start + 2 + index * 6;
        const tag = try bin.readTagAt(data, record);
        if (previous_tag) |last| {
            if (std.mem.order(u8, &last, &tag) != .lt) return error.BadSfnt;
        }
        previous_tag = tag;
        const script_offset: usize = @intCast(try bin.readU16At(data, record + 4));
        try validateBaseScript(data, base_offset, base_length, start - base_offset, script_offset, baseline_count);
    }
}

fn validateBaseScript(data: []const u8, base_offset: usize, base_length: usize, script_list_offset: usize, script_offset: usize, baseline_count: usize) Error!void {
    const start = try checkedAxisChildStart(base_offset, base_length, script_list_offset, script_offset, 6);
    const base_values_offset: usize = @intCast(try bin.readU16At(data, start));
    if (base_values_offset != 0) try validateBaseValues(data, base_offset, base_length, start - base_offset, base_values_offset, baseline_count);
}

fn validateBaseValues(data: []const u8, base_offset: usize, base_length: usize, script_offset: usize, values_offset: usize, baseline_count: usize) Error!void {
    const start = try checkedAxisChildStart(base_offset, base_length, script_offset, values_offset, 4);
    const default_index = try bin.readU16At(data, start);
    const count: usize = @intCast(try bin.readU16At(data, start + 2));
    if (count != baseline_count) return error.BadSfnt;
    if (count > 0 and default_index >= count) return error.BadSfnt;
    if (count > (base_offset + base_length - (start + 4)) / 2) return error.BadSfnt;
    for (0..count) |index| {
        const coord_offset: usize = @intCast(try bin.readU16At(data, start + 4 + index * 2));
        if (coord_offset != 0) _ = try readBaseCoord(data, base_offset, base_length, start - base_offset, coord_offset);
    }
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize) Error!Info {
    if (offset > data.len or length > data.len - offset or length < 8) return error.BadSfnt;
    const version = try bin.readU32At(data, offset);
    if (version != 0x00010000 and version != 0x00010001) return error.BadSfnt;
    const horiz_offset: usize = @intCast(try bin.readU16At(data, offset + 4));
    const vert_offset: usize = @intCast(try bin.readU16At(data, offset + 6));

    var result = Info{ .version = version };
    errdefer free(allocator, result);
    if (horiz_offset != 0) result.horizontal = try readAxis(allocator, data, offset, length, horiz_offset);
    if (vert_offset != 0) result.vertical = try readAxis(allocator, data, offset, length, vert_offset);
    return result;
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    if (value.horizontal) |axis| freeAxis(allocator, axis);
    if (value.vertical) |axis| freeAxis(allocator, axis);
}

fn freeAxis(allocator: std.mem.Allocator, axis: Axis) void {
    for (axis.scripts) |script| allocator.free(script.coordinates);
    allocator.free(axis.scripts);
    allocator.free(axis.baseline_tags);
}

fn readAxis(allocator: std.mem.Allocator, data: []const u8, base_offset: usize, base_length: usize, axis_offset: usize) Error!Axis {
    if (axis_offset > base_length or base_length - axis_offset < 4) return error.BadSfnt;
    const axis_start = base_offset + axis_offset;
    const tag_list_offset: usize = @intCast(try bin.readU16At(data, axis_start));
    const script_list_offset: usize = @intCast(try bin.readU16At(data, axis_start + 2));
    if (script_list_offset == 0) return error.BadSfnt;

    const tags = if (tag_list_offset != 0) try readBaseTags(allocator, data, base_offset, base_length, axis_offset, tag_list_offset) else try allocator.alloc([4]u8, 0);
    errdefer allocator.free(tags);
    const scripts = try readBaseScripts(allocator, data, base_offset, base_length, axis_offset, script_list_offset, tags.len);
    errdefer {
        for (scripts) |script| allocator.free(script.coordinates);
        allocator.free(scripts);
    }
    return .{ .baseline_tags = tags, .scripts = scripts };
}

fn readBaseTags(allocator: std.mem.Allocator, data: []const u8, base_offset: usize, base_length: usize, axis_offset: usize, tag_list_offset: usize) Error![][4]u8 {
    const start = try checkedAxisChildStart(base_offset, base_length, axis_offset, tag_list_offset, 2);
    const count: usize = @intCast(try bin.readU16At(data, start));
    if (count > (base_offset + base_length - (start + 2)) / 4) return error.BadSfnt;
    const tags = try allocator.alloc([4]u8, count);
    errdefer allocator.free(tags);
    var previous: ?[4]u8 = null;
    for (tags, 0..) |*tag, index| {
        tag.* = try bin.readTagAt(data, start + 2 + index * 4);
        if (previous) |last| {
            if (std.mem.order(u8, &last, tag) != .lt) return error.BadSfnt;
        }
        previous = tag.*;
    }
    return tags;
}

fn readBaseScripts(allocator: std.mem.Allocator, data: []const u8, base_offset: usize, base_length: usize, axis_offset: usize, script_list_offset: usize, baseline_count: usize) Error![]Script {
    const start = try checkedAxisChildStart(base_offset, base_length, axis_offset, script_list_offset, 2);
    const count: usize = @intCast(try bin.readU16At(data, start));
    if (count > (base_offset + base_length - (start + 2)) / 6) return error.BadSfnt;
    const scripts = try allocator.alloc(Script, count);
    errdefer allocator.free(scripts);
    var initialized: usize = 0;
    errdefer for (scripts[0..initialized]) |script| allocator.free(script.coordinates);

    var previous_tag: ?[4]u8 = null;
    for (scripts, 0..) |*script, index| {
        const record = start + 2 + index * 6;
        const tag = try bin.readTagAt(data, record);
        if (previous_tag) |last| {
            if (std.mem.order(u8, &last, &tag) != .lt) return error.BadSfnt;
        }
        previous_tag = tag;
        const script_offset: usize = @intCast(try bin.readU16At(data, record + 4));
        script.* = try readBaseScript(allocator, data, base_offset, base_length, start - base_offset, script_offset, tag, baseline_count);
        initialized += 1;
    }
    return scripts;
}

fn readBaseScript(allocator: std.mem.Allocator, data: []const u8, base_offset: usize, base_length: usize, script_list_offset: usize, script_offset: usize, tag: [4]u8, baseline_count: usize) Error!Script {
    const start = try checkedAxisChildStart(base_offset, base_length, script_list_offset, script_offset, 6);
    const base_values_offset: usize = @intCast(try bin.readU16At(data, start));
    const coords = try allocator.alloc(?i16, baseline_count);
    errdefer allocator.free(coords);
    @memset(coords, null);
    var default_index: ?u16 = null;
    if (base_values_offset != 0) {
        default_index = try readBaseValues(data, base_offset, base_length, start - base_offset, base_values_offset, coords);
    }
    return .{ .tag = tag, .default_baseline_index = default_index, .coordinates = coords };
}

fn readBaseValues(data: []const u8, base_offset: usize, base_length: usize, script_offset: usize, values_offset: usize, out: []?i16) Error!u16 {
    const start = try checkedAxisChildStart(base_offset, base_length, script_offset, values_offset, 4);
    const default_index = try bin.readU16At(data, start);
    const count: usize = @intCast(try bin.readU16At(data, start + 2));
    if (count != out.len) return error.BadSfnt;
    if (default_index >= count) return error.BadSfnt;
    if (count > (base_offset + base_length - (start + 4)) / 2) return error.BadSfnt;
    for (out, 0..) |*coord, index| {
        const coord_offset: usize = @intCast(try bin.readU16At(data, start + 4 + index * 2));
        coord.* = if (coord_offset == 0) null else try readBaseCoord(data, base_offset, base_length, start - base_offset, coord_offset);
    }
    return default_index;
}

fn readBaseCoord(data: []const u8, base_offset: usize, base_length: usize, parent_offset: usize, coord_offset: usize) Error!i16 {
    const start = try checkedAxisChildStart(base_offset, base_length, parent_offset, coord_offset, 4);
    const format = try bin.readU16At(data, start);
    return switch (format) {
        1 => try bin.readI16At(data, start + 2),
        // Formats 2 and 3 carry additional glyph/device data. For metadata
        // callers that only need baseline coordinates, the coordinate field is
        // still the same first payload word.
        2, 3 => blk: {
            if (base_offset + base_length - start < 6) return error.BadSfnt;
            break :blk try bin.readI16At(data, start + 2);
        },
        else => error.BadSfnt,
    };
}

fn checkedAxisChildStart(base_offset: usize, base_length: usize, parent_offset: usize, child_offset: usize, min_len: usize) Error!usize {
    if (child_offset == 0) return error.BadSfnt;
    if (parent_offset > base_length or child_offset > base_length - parent_offset) return error.BadSfnt;
    const relative = parent_offset + child_offset;
    if (min_len > base_length - relative) return error.BadSfnt;
    return base_offset + relative;
}
