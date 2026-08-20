//! Size-specific Type2 stem-map execution for CFF/CFF2 outlines.
//!
//! This is intentionally independent of the TrueType VM. Type2 native
//! hinting builds a piecewise Y-coordinate map from horizontal stems and blue
//! zones; X remains under the uniform outline scale, matching FreeType's CFF
//! hinter. Hint/counter masks can rebuild and lock the map at path boundaries.

const std = @import("std");
const glyph = @import("../../../glyph.zig");
const map_mod = @import("map.zig");
const program = @import("program.zig");
const fixed = @import("fixed.zig");
const tt_outline = @import("../outline.zig");

pub const Error = error{
    InvalidHintPpem,
    InvalidHintScale,
    InvalidHintProgram,
} || std.mem.Allocator.Error;

pub const Instance = struct {
    ppem: u16,
    units_per_em: u16,
    scale: f32,
    scale_26_6: fixed.Fixed,
    hint_scale: fixed.Fixed,

    pub fn init(ppem: u16, units_per_em: u16) Error!Instance {
        if (ppem == 0) return error.InvalidHintPpem;
        if (units_per_em < 16 or units_per_em > 16_384) {
            return error.InvalidHintScale;
        }
        // FreeType first represents ppem/upem as a font-unit-to-26.6 scale.
        // Its PostScript hinter then rounds and divides that scale by 64.
        const scale_26_6 = fixed.Fixed.fromBits(@as(i32, ppem) * 64)
            .div(fixed.Fixed.fromBits(units_per_em));
        const hint_scale = fixed.Fixed.fromBits(
            @divTrunc(scale_26_6.bits +| 32, 64),
        );
        return .{
            .ppem = ppem,
            .units_per_em = units_per_em,
            .scale = @as(f32, @floatFromInt(ppem)) /
                @as(f32, @floatFromInt(units_per_em)),
            .scale_26_6 = scale_26_6,
            .hint_scale = hint_scale,
        };
    }

    /// Grid-fit one design-space outline to an owning pixel path.
    pub fn hint(
        self: Instance,
        allocator: std.mem.Allocator,
        outline: *const glyph.GlyphOutline,
        hints: *const program.Program,
    ) Error!tt_outline.PixelOutline {
        if (hints.stems.items.len > map_mod.max_hints) {
            return error.InvalidHintProgram;
        }
        var result = tt_outline.PixelOutline{
            .allocator = allocator,
            .glyph_id = outline.glyph_id,
            // FreeType grid-fits horizontal metrics independently of the CFF
            // path map. The public PixelOutline stores pixels, not 26.6 units.
            .advance_width = scaleMetric(outline.advance_width, self.scale_26_6),
            .left_side_bearing = @as(f32, @floatFromInt(outline.left_side_bearing)) * self.scale,
        };
        errdefer result.deinit();
        try result.commands.ensureTotalCapacity(allocator, outline.commands.items.len);

        var execution = Execution.init(self, hints);
        var contour_start: ?glyph.Point = null;
        var pending_line: ?struct { source: glyph.Point, command: glyph.PathCommand } = null;
        for (outline.commands.items, 0..) |command, command_index| {
            execution.applyMasksAt(command_index);
            switch (command) {
                .move_to => |point| {
                    if (pending_line) |line| try result.commands.append(allocator, line.command);
                    pending_line = null;
                    contour_start = point;
                    try result.commands.append(allocator, execution.transformCommand(command));
                },
                .line_to => |point| {
                    if (pending_line) |line| try result.commands.append(allocator, line.command);
                    pending_line = .{
                        .source = point,
                        .command = execution.transformCommand(command),
                    };
                },
                .quad_to, .cubic_to => {
                    if (pending_line) |line| try result.commands.append(allocator, line.command);
                    pending_line = null;
                    try result.commands.append(allocator, execution.transformCommand(command));
                },
                .close => {
                    if (pending_line) |line| {
                        // FreeType's CFF path builder omits a final explicit
                        // line whose character-space endpoint is the move-to.
                        // The close element supplies the same geometric edge
                        // without adding a duplicate outline point.
                        if (contour_start == null or
                            !std.meta.eql(contour_start.?, line.source))
                        {
                            try result.commands.append(allocator, line.command);
                        }
                    }
                    pending_line = null;
                    contour_start = null;
                    try result.commands.append(allocator, .close);
                },
            }
        }
        if (pending_line) |line| try result.commands.append(allocator, line.command);
        return result;
    }
};

fn scaleMetric(metric: u16, scale_26_6: fixed.Fixed) f32 {
    // FT_MulFix rounds to one 26.6 unit before the CFF driver grid-fits the
    // reported advance to a whole pixel. Direct floating-point multiplication
    // loses this observable half-pixel case (for example STIX A at 9 ppem).
    const product = @as(i64, metric) * @as(i64, scale_26_6.bits);
    const value_26_6: i32 = @intCast((product + 0x8000) >> 16);
    return @floatFromInt(@divFloor(value_26_6 + 32, 64));
}

const Execution = struct {
    state: map_mod.State,
    hints: *const program.Program,
    stems: [map_mod.max_hints]map_mod.StemHint = undefined,
    stem_count: usize,
    mask: map_mod.Mask = map_mod.Mask.all(),
    initial_map: map_mod.HintMap,
    map: map_mod.HintMap,
    mask_index: usize = 0,

    fn init(instance: Instance, hints: *const program.Program) Execution {
        const state = map_mod.State.init(hints.hint_params, instance.hint_scale);
        var result = Execution{
            .state = state,
            .hints = hints,
            .stem_count = 0,
            .initial_map = map_mod.HintMap.init(instance.hint_scale),
            .map = map_mod.HintMap.init(instance.hint_scale),
        };
        result.stem_count = map_mod.horizontalStems(hints, &result.stems);
        return result;
    }

    fn applyMasksAt(self: *Execution, command_index: usize) void {
        while (self.mask_index < self.hints.masks.items.len and
            self.hints.masks.items[self.mask_index].path_command_index == command_index)
        {
            const mask_record = self.hints.masks.items[self.mask_index];
            const mask = map_mod.Mask.fromBytes(self.hints.maskBytes(mask_record));
            if (mask_record.kind == .hint) {
                if (!std.meta.eql(self.mask, mask)) {
                    self.mask = mask;
                    self.map.valid = false;
                }
            } else {
                // Counter masks do not become the active path mask. Building a
                // temporary map persists the device positions of its stems,
                // locking them for subsequent maps.
                var temporary = map_mod.HintMap.init(self.state.scale);
                temporary.build(
                    &self.state,
                    mask,
                    &self.initial_map,
                    self.stems[0..self.stem_count],
                    .zero,
                    false,
                );
            }
            self.mask_index += 1;
        }
    }

    fn hintedY(self: *Execution, value: f32) f32 {
        if (!self.map.valid) {
            self.map.build(
                &self.state,
                self.mask,
                &self.initial_map,
                self.stems[0..self.stem_count],
                .zero,
                false,
            );
        }
        // Native CFF output is exposed at FreeType's 26.6 precision. Zeroing
        // the low ten 16.16 bits mirrors that truncating conversion.
        const mapped = self.map.transform(fixed.Fixed.fromF32(value));
        return fixed.Fixed.fromBits(mapped.bits & ~@as(i32, 0x3ff)).toF32();
    }

    fn point(self: *Execution, value: glyph.Point) glyph.Point {
        return .{ .x = scaleCoordinate(value.x, self.state.scale), .y = self.hintedY(value.y) };
    }

    fn transformCommand(self: *Execution, command: glyph.PathCommand) glyph.PathCommand {
        return switch (command) {
            .move_to => |value| .{ .move_to = self.point(value) },
            .line_to => |value| .{ .line_to = self.point(value) },
            .quad_to => |value| .{ .quad_to = .{
                .control = self.point(value.control),
                .end = self.point(value.end),
            } },
            .cubic_to => |value| .{ .cubic_to = .{
                .c0 = self.point(value.c0),
                .c1 = self.point(value.c1),
                .end = self.point(value.end),
            } },
            .close => .close,
        };
    }
};

fn scaleCoordinate(value: f32, hint_scale: fixed.Fixed) f32 {
    const scaled = fixed.Fixed.fromF32(value).mul(hint_scale);
    return fixed.Fixed.fromBits(scaled.bits & ~@as(i32, 0x3ff)).toF32();
}

test "Type2 instance grid-fits horizontal stems and uniformly scales X" {
    var hints = program.Program.init(std.testing.allocator);
    defer hints.deinit();
    try hints.appendStems(.vertical, &.{ 100, 70 });
    try hints.appendStems(.horizontal, &.{ 0, 60 });

    var outline = glyph.GlyphOutline.init(std.testing.allocator, 1, .{
        .x_min = 100,
        .y_min = 0,
        .x_max = 170,
        .y_max = 60,
    }, 500, 100);
    defer outline.deinit();
    try outline.commands.append(std.testing.allocator, .{ .move_to = .{ .x = 100, .y = 0 } });
    try outline.commands.append(std.testing.allocator, .{ .line_to = .{ .x = 170, .y = 60 } });
    const instance = try Instance.init(10, 1000);
    var pixel = try instance.hint(std.testing.allocator, &outline, &hints);
    defer pixel.deinit();
    try std.testing.expectEqual(@as(f32, 0.984375), switch (pixel.commands.items[0]) {
        .move_to => |point| point.x,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqual(@as(f32, 1.6875), switch (pixel.commands.items[1]) {
        .line_to => |point| point.x,
        else => return error.TestUnexpectedResult,
    });
    try std.testing.expectEqual(@as(f32, 0.59375), switch (pixel.commands.items[1]) {
        .line_to => |point| point.y,
        else => return error.TestUnexpectedResult,
    });
}
