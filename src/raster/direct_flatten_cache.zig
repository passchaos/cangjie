//! Inline one-entry cache for repeated direct outline flattening.
//!
//! The cache retains only line geometry, not pixels, so every hit still runs
//! the public direct scan converter. All storage is inline: moving or dropping
//! a rasterizer cannot leave self-referential pointers or allocator ownership.

const std = @import("std");
const glyph = @import("../glyph.zig");
const outline_raster = @import("outline.zig");
const scanline = @import("scanline.zig");
const Line = scanline.Line;

pub const max_commands = 64;
pub const max_lines = 128;
const fingerprint_probe_count = 4;

pub const Key = struct {
    glyph_id: glyph.GlyphId,
    command_count: usize,
    x_bits: u32,
    baseline_y_bits: u32,
    font_size_bits: u32,
    hint_size_bits: u32,
    units_per_em: u16,
    orientation: outline_raster.Orientation,
    target_width: u32,
    target_height: u32,

    pub fn init(
        outline: *const glyph.GlyphOutline,
        x: f32,
        baseline_y: f32,
        font_size: f32,
        hint_size: f32,
        units_per_em: u16,
        orientation: outline_raster.Orientation,
        target_width: u32,
        target_height: u32,
    ) Key {
        return .{
            .glyph_id = outline.glyph_id,
            .command_count = outline.commands.items.len,
            .x_bits = @bitCast(x),
            .baseline_y_bits = @bitCast(baseline_y),
            .font_size_bits = @bitCast(font_size),
            .hint_size_bits = @bitCast(hint_size),
            .units_per_em = units_per_em,
            .orientation = orientation,
            .target_width = target_width,
            .target_height = target_height,
        };
    }
};

pub const PreparedGeometry = struct {
    lines: []const scanline.PreparedFillLine,
    bounds: ?scanline.Bounds,
};

pub const Cache = struct {
    valid: bool = false,
    observed: ?Key = null,
    key: Key = undefined,
    command_count: usize = 0,
    line_count: usize = 0,
    prepared_line_count: usize = 0,
    prepared_bounds: ?scanline.Bounds = null,
    fingerprint: [fingerprint_probe_count]u32 = .{0} ** fingerprint_probe_count,
    commands: [max_commands]glyph.PathCommand = undefined,
    lines: [max_lines]Line = undefined,
    prepared_lines: [max_lines]scanline.PreparedFillLine = undefined,

    pub fn lookup(
        self: *Cache,
        key: Key,
        commands: []const glyph.PathCommand,
    ) ?[]const Line {
        if (!self.valid or !std.meta.eql(self.key, key)) {
            self.valid = false;
            return null;
        }
        const current_fingerprint = commandFingerprint(commands);
        if (!std.mem.eql(u32, &current_fingerprint, &self.fingerprint) or
            !commandsEqual(self.commands[0..self.command_count], commands))
        {
            self.valid = false;
            return null;
        }
        return self.lines[0..self.line_count];
    }

    pub fn prepared(self: *const Cache) PreparedGeometry {
        return .{
            .lines = self.prepared_lines[0..self.prepared_line_count],
            .bounds = self.prepared_bounds,
        };
    }

    /// Admit only the second consecutive observation. Ordinary text runs do
    /// not pay to copy every distinct outline into this deliberately tiny cache.
    pub fn shouldInstall(self: *Cache, key: Key) bool {
        if (key.command_count > max_commands) {
            self.observed = null;
            return false;
        }
        if (self.observed) |previous| {
            if (std.meta.eql(previous, key)) {
                self.observed = null;
                return true;
            }
        }
        self.observed = key;
        return false;
    }

    pub fn install(
        self: *Cache,
        key: Key,
        commands: []const glyph.PathCommand,
        lines: []const Line,
    ) void {
        if (commands.len > self.commands.len or lines.len > self.lines.len) {
            return;
        }
        @memcpy(self.commands[0..commands.len], commands);
        @memcpy(self.lines[0..lines.len], lines);
        self.key = key;
        self.command_count = commands.len;
        self.line_count = lines.len;
        self.fingerprint = commandFingerprint(commands);
        self.prepared_bounds = scanline.boundsForTarget(.{
            .width = key.target_width,
            .height = key.target_height,
            .pixels = &.{},
        }, lines);
        self.prepared_line_count = scanline.prepareFillLines(
            self.prepared_lines[0..lines.len],
            lines,
        ).len;
        scanline.sortPreparedFillLinesByYMin(
            self.prepared_lines[0..self.prepared_line_count],
        );
        self.valid = true;
    }
};

threadlocal var thread_cache = Cache{};

pub fn local() *Cache {
    return &thread_cache;
}

fn commandsEqual(
    first: []const glyph.PathCommand,
    second: []const glyph.PathCommand,
) bool {
    if (first.len != second.len) return false;
    for (first, second) |a, b| {
        if (!commandEqual(a, b)) return false;
    }
    return true;
}

fn commandFingerprint(commands: []const glyph.PathCommand) [fingerprint_probe_count]u32 {
    if (commands.len == 0) return .{0} ** fingerprint_probe_count;
    const indices = [_]usize{ 0, commands.len / 3, (commands.len * 2) / 3, commands.len - 1 };
    var result: [fingerprint_probe_count]u32 = undefined;
    inline for (indices, 0..) |index, output_index| {
        result[output_index] = commandProbe(commands[index]);
    }
    return result;
}

fn commandProbe(command: glyph.PathCommand) u32 {
    return switch (command) {
        .move_to => |point| 0x10000000 ^ @as(u32, @bitCast(point.x)) ^
            std.math.rotl(u32, @as(u32, @bitCast(point.y)), 11),
        .line_to => |point| 0x20000000 ^ @as(u32, @bitCast(point.x)) ^
            std.math.rotl(u32, @as(u32, @bitCast(point.y)), 11),
        .quad_to => |curve| 0x30000000 ^ @as(u32, @bitCast(curve.control.x)) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.control.y)), 7) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.end.x)), 13) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.end.y)), 19),
        .cubic_to => |curve| 0x40000000 ^ @as(u32, @bitCast(curve.c0.x)) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.c0.y)), 5) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.c1.x)), 9) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.c1.y)), 13) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.end.x)), 17) ^
            std.math.rotl(u32, @as(u32, @bitCast(curve.end.y)), 21),
        .close => 0x50000000,
    };
}

fn pointEqual(a: glyph.Point, b: glyph.Point) bool {
    return @as(u32, @bitCast(a.x)) == @as(u32, @bitCast(b.x)) and
        @as(u32, @bitCast(a.y)) == @as(u32, @bitCast(b.y));
}

fn commandEqual(a: glyph.PathCommand, b: glyph.PathCommand) bool {
    return switch (a) {
        .move_to => |point| switch (b) {
            .move_to => |other| pointEqual(point, other),
            else => false,
        },
        .line_to => |point| switch (b) {
            .line_to => |other| pointEqual(point, other),
            else => false,
        },
        .quad_to => |curve| switch (b) {
            .quad_to => |other| pointEqual(curve.control, other.control) and
                pointEqual(curve.end, other.end),
            else => false,
        },
        .cubic_to => |curve| switch (b) {
            .cubic_to => |other| pointEqual(curve.c0, other.c0) and
                pointEqual(curve.c1, other.c1) and
                pointEqual(curve.end, other.end),
            else => false,
        },
        .close => switch (b) {
            .close => true,
            else => false,
        },
    };
}

test "direct flatten cache requires two observations and rejects mutation" {
    var cache = Cache{};
    const commands = [_]glyph.PathCommand{
        .{ .move_to = .{ .x = 1, .y = 2 } },
        .{ .line_to = .{ .x = 3, .y = 4 } },
    };
    const lines = [_]Line{.{
        .a = .{ .x = 1, .y = 2 },
        .b = .{ .x = 3, .y = 4 },
    }};
    const key = Key{
        .glyph_id = 1,
        .command_count = commands.len,
        .x_bits = 0,
        .baseline_y_bits = 0,
        .font_size_bits = 0,
        .hint_size_bits = 0,
        .units_per_em = 1000,
        .orientation = .upright,
        .target_width = 64,
        .target_height = 64,
    };
    try std.testing.expect(!cache.shouldInstall(key));
    try std.testing.expect(cache.shouldInstall(key));
    cache.install(key, &commands, &lines);
    try std.testing.expectEqualSlices(Line, &lines, cache.lookup(key, &commands).?);
    var mutated = commands;
    mutated[1] = .{ .line_to = .{ .x = 5, .y = 4 } };
    try std.testing.expect(cache.lookup(key, &mutated) == null);
}

test "direct flatten cache invalidates on geometry changes" {
    var cache = Cache{};
    const commands = [_]glyph.PathCommand{
        .{ .move_to = .{ .x = 1, .y = 2 } },
        .{ .line_to = .{ .x = 3, .y = 4 } },
    };
    const lines = [_]Line{.{
        .a = .{ .x = 1, .y = 2 },
        .b = .{ .x = 3, .y = 4 },
    }};
    var key = Key{
        .glyph_id = 1,
        .command_count = commands.len,
        .x_bits = 0,
        .baseline_y_bits = 0,
        .font_size_bits = 0,
        .hint_size_bits = 0,
        .units_per_em = 1000,
        .orientation = .upright,
        .target_width = 64,
        .target_height = 64,
    };
    cache.install(key, &commands, &lines);
    key.baseline_y_bits = @bitCast(@as(f32, 1));
    try std.testing.expect(cache.lookup(key, &commands) == null);
    try std.testing.expect(!cache.valid);

    cache.install(key, &commands, &lines);
    key.target_width += 1;
    try std.testing.expect(cache.lookup(key, &commands) == null);
}
