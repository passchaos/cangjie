//! Point-zone opcode adapter for the generic TrueType interpreter.
//!
//! The main VM owns bytecode decoding, calls, branches, and scalar state.
//! This adapter recognizes only opcodes whose semantics depend on transient
//! vectors or point zones, keeping their stack contracts next to the geometry
//! operations they invoke.

const stack_mod = @import("../stack.zig");
const types = @import("../types.zig");
const compatibility_mod = @import("compatibility.zig");
const geometry = @import("geometry.zig");
const zones = @import("zones.zig");

pub const Runtime = struct {
    stack: *stack_mod.Stack,
    cvt: []i32,
    retained: *types.RetainedGraphicsState,
    transient: *zones.GraphicsState,
    compatibility: *compatibility_mod.State,
    twilight: ?zones.Zone,
    glyph: ?zones.Zone,
    point_scale_16_16: i32,

    /// Return whether `opcode` belongs to the point/vector instruction set.
    pub fn handle(self: *Runtime, opcode: u8) types.Error!bool {
        switch (opcode) {
            0x00, 0x01 => {
                const vector = axisVector(opcode);
                self.transient.projection = vector;
                self.transient.dual_projection = vector;
                self.transient.freedom = vector;
            },
            0x02, 0x03 => {
                const vector = axisVector(opcode);
                self.transient.projection = vector;
                self.transient.dual_projection = vector;
            },
            0x04, 0x05 => self.transient.freedom = axisVector(opcode),
            0x06, 0x07 => {
                const second = try self.stack.popIndex();
                const first = try self.stack.popIndex();
                var context = try self.pointContext();
                const vector = try context.lineVector(
                    first,
                    second,
                    (opcode & 1) != 0,
                );
                self.transient.projection = vector;
                self.transient.dual_projection = vector;
            },
            0x08, 0x09 => {
                const second = try self.stack.popIndex();
                const first = try self.stack.popIndex();
                var context = try self.pointContext();
                self.transient.freedom = try context.lineVector(
                    first,
                    second,
                    (opcode & 1) != 0,
                );
            },
            0x0a => {
                const vector = try self.popVector();
                self.transient.projection = vector;
                self.transient.dual_projection = vector;
            },
            0x0b => self.transient.freedom = try self.popVector(),
            0x0c => {
                try self.stack.push(self.transient.projection.x);
                try self.stack.push(self.transient.projection.y);
            },
            0x0d => {
                try self.stack.push(self.transient.freedom.x);
                try self.stack.push(self.transient.freedom.y);
            },
            0x0e => self.transient.freedom = self.transient.projection,
            0x0f => {
                const b1 = try self.stack.popIndex();
                const b0 = try self.stack.popIndex();
                const a1 = try self.stack.popIndex();
                const a0 = try self.stack.popIndex();
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                try geometry.intersect(
                    &context.twilight,
                    &context.glyph,
                    self.transient,
                    point,
                    a0,
                    a1,
                    b0,
                    b1,
                );
            },

            0x10...0x12 => self.setReference(
                opcode - 0x10,
                try self.stack.popIndex(),
            ),
            0x13...0x15 => try self.setZone(
                opcode - 0x13,
                try self.popZoneIndex(),
            ),
            0x16 => try self.setZone(3, try self.popZoneIndex()),
            0x17 => {
                const loop = try self.stack.popIndex();
                if (loop == 0) return error.InvalidHintOperand;
                self.transient.loop = loop;
            },
            0x27 => {
                const second = try self.stack.popIndex();
                const first = try self.stack.popIndex();
                var context = try self.pointContext();
                try geometry.alignPoints(
                    &context.twilight,
                    &context.glyph,
                    self.transient,
                    first,
                    second,
                    self.compatibility.*,
                );
            },
            0x29 => {
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                try context.untouch(point);
            },
            0x2e, 0x2f => {
                // Report the missing point-zone capability before touching the
                // stack; size-program callers historically rely on this error.
                if (self.glyph == null) {
                    return error.UnsupportedHintInstruction;
                }
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                try context.mdap(point, (opcode & 1) != 0);
            },
            0x30, 0x31 => {
                const x_axis = (opcode & 1) != 0;
                if (self.compatibility.beginIup(x_axis)) {
                    var context = try self.pointContext();
                    try context.interpolateUntouched(x_axis);
                }
            },
            0x32, 0x33 => try self.shiftPointsByReference(opcode),
            0x34, 0x35 => {
                const contour = try self.stack.popIndex();
                var context = try self.pointContext();
                try context.shiftContourByReference(
                    (opcode & 1) != 0,
                    contour,
                );
            },
            0x36, 0x37 => {
                const zone_index = try self.popZoneIndex();
                var context = try self.pointContext();
                try context.shiftZoneByReference(
                    (opcode & 1) != 0,
                    zone_index,
                );
            },
            0x38 => try self.shiftPixels(),
            0x39 => try self.interpolatePoints(),
            0x3a, 0x3b => {
                const distance = try self.stack.pop();
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                try context.moveStackIndirectRelative(
                    point,
                    distance,
                    (opcode & 1) != 0,
                );
            },
            0x3c => try self.alignReferences(),
            0x3e, 0x3f => try self.moveIndirectAbsolute(opcode),
            0x46, 0x47 => {
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                const coordinate = try context.getCoordinate(
                    point,
                    (opcode & 1) != 0,
                );
                try self.stack.push(coordinate);
            },
            0x48 => {
                const value = try self.stack.pop();
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                try context.setCoordinate(point, value);
            },
            0x49, 0x4a => {
                const second = try self.stack.popIndex();
                const first = try self.stack.popIndex();
                var context = try self.pointContext();
                try self.stack.push(try context.measure(
                    first,
                    second,
                    (opcode & 1) != 0,
                ));
            },
            0x5d, 0x71, 0x72 => try self.deltaPoints(opcode),
            0x80 => try self.flipPoints(),
            0x81, 0x82 => {
                const last = try self.stack.popIndex();
                const first = try self.stack.popIndex();
                if (!self.compatibility.postIup()) {
                    var context = try self.pointContext();
                    try context.setCurveRange(
                        first,
                        last,
                        opcode == 0x81,
                    );
                }
            },
            0x86, 0x87 => {
                const second = try self.stack.popIndex();
                const first = try self.stack.popIndex();
                var context = try self.pointContext();
                try geometry.setDualProjectionLine(
                    &context.twilight,
                    &context.glyph,
                    self.transient,
                    first,
                    second,
                    (opcode & 1) != 0,
                );
            },
            0xc0...0xdf => {
                const point = try self.stack.popIndex();
                var context = try self.pointContext();
                try context.mdrp(point, opcode, self.retained.*);
            },
            0xe0...0xff => try self.moveIndirectRelative(opcode),
            else => return false,
        }
        return true;
    }

    fn pointContext(self: *Runtime) types.Error!zones.Context {
        return .{
            .twilight = self.twilight orelse
                return error.UnsupportedHintInstruction,
            .glyph = self.glyph orelse
                return error.UnsupportedHintInstruction,
            .state = self.transient,
            .compatibility = self.compatibility,
            .scale_16_16 = self.point_scale_16_16,
        };
    }

    /// Zone and reference setters remain legal in prep without attached point
    /// arrays; only an instruction that dereferences a point requires zones.
    fn setReference(self: *Runtime, which: u8, value: usize) void {
        switch (which) {
            0 => self.transient.rp0 = value,
            1 => self.transient.rp1 = value,
            2 => self.transient.rp2 = value,
            else => unreachable,
        }
    }

    fn setZone(self: *Runtime, which: u8, value: u8) types.Error!void {
        if (value > 1) return error.InvalidHintOperand;
        switch (which) {
            0 => self.transient.zp0 = value,
            1 => self.transient.zp1 = value,
            2 => self.transient.zp2 = value,
            3 => {
                self.transient.zp0 = value;
                self.transient.zp1 = value;
                self.transient.zp2 = value;
            },
            else => unreachable,
        }
    }

    fn popZoneIndex(self: *Runtime) types.Error!u8 {
        const value = try self.stack.pop();
        if (value != 0 and value != 1) return error.InvalidHintOperand;
        return @intCast(value);
    }

    fn popVector(self: *Runtime) types.Error!zones.Vector {
        const y: i16 = @truncate(try self.stack.pop());
        const x: i16 = @truncate(try self.stack.pop());
        return zones.Vector.normalized(x, y);
    }

    fn shiftPixels(self: *Runtime) types.Error!void {
        const loop = self.transient.loop;
        if (self.stack.depth() < loop + 1) {
            return error.HintStackUnderflow;
        }
        // SHPIX has one fixed operand at the top of the stack (distance),
        // followed by `loop` point operands beneath it. This differs from a
        // tempting "distance, points..." reading of the prose notation and
        // is observable in real ttfautohint-generated function programs.
        const distance = try self.stack.pop();
        var context = try self.pointContext();
        for (0..loop) |_| {
            const point_value = try self.stack.pop();
            if (point_value < 0) continue;
            // FreeType-compatible non-pedantic execution ignores invalid
            // point references in deployed fonts instead of abandoning the
            // complete glyph program.
            context.shiftPixel(@intCast(point_value), distance) catch |err| {
                if (err != error.InvalidHintOperand) return err;
            };
        }
        self.transient.loop = 1;
    }

    fn shiftPointsByReference(
        self: *Runtime,
        opcode: u8,
    ) types.Error!void {
        const loop = self.transient.loop;
        if (loop > self.stack.depth()) return error.HintStackUnderflow;
        var inline_points: [32]usize = undefined;
        const points = if (loop <= inline_points.len)
            inline_points[0..loop]
        else
            return error.HintExecutionLimitExceeded;
        for (points) |*point| point.* = try self.stack.popIndex();
        var context = try self.pointContext();
        try context.shiftPointsByReference((opcode & 1) != 0, points);
        self.transient.loop = 1;
    }

    fn alignReferences(self: *Runtime) types.Error!void {
        const loop = self.transient.loop;
        if (loop > self.stack.depth()) return error.HintStackUnderflow;
        var context = try self.pointContext();
        for (0..loop) |_| {
            try context.alignReference(try self.stack.popIndex());
        }
        self.transient.loop = 1;
    }

    fn interpolatePoints(self: *Runtime) types.Error!void {
        const loop = self.transient.loop;
        if (loop > self.stack.depth()) return error.HintStackUnderflow;
        var context = try self.pointContext();
        for (0..loop) |_| {
            try context.interpolatePoint(try self.stack.popIndex());
        }
        self.transient.loop = 1;
    }

    fn deltaPoints(self: *Runtime, opcode: u8) types.Error!void {
        const count_value = try self.stack.pop();
        if (count_value < 0) return error.InvalidHintOperand;
        const count: usize = @intCast(count_value);
        if (count > self.stack.depth() / 2) {
            return error.HintStackUnderflow;
        }
        const bias = self.retained.delta_base + switch (opcode) {
            0x71 => @as(i32, 16),
            0x72 => @as(i32, 32),
            else => @as(i32, 0),
        };
        for (0..count) |_| {
            const point = try self.stack.popIndex();
            var packed_delta = try self.stack.pop();
            const target_ppem = ((packed_delta & 0xf0) >> 4) + bias;
            if (target_ppem != @as(i32, self.retained.ppem)) continue;
            packed_delta = (packed_delta & 0x0f) - 8;
            if (packed_delta >= 0) packed_delta += 1;
            const multiplier: i32 =
                @as(i32, 1) << @intCast(6 - self.retained.delta_shift);
            const target = switch (self.transient.zp0) {
                0 => self.twilight orelse
                    return error.UnsupportedHintInstruction,
                1 => self.glyph orelse
                    return error.UnsupportedHintInstruction,
                else => return error.InvalidHintOperand,
            };
            if (point >= target.flags.len) continue;
            if (self.compatibility.allowPatternMove(
                self.transient.freedom,
                target.flags[point].touched_y,
            )) {
                var context = try self.pointContext();
                context.deltaPoint(
                    point,
                    packed_delta *| multiplier,
                ) catch |err| {
                    if (err != error.InvalidHintOperand) return err;
                };
            }
        }
    }

    fn flipPoints(self: *Runtime) types.Error!void {
        const loop = self.transient.loop;
        if (loop > self.stack.depth()) return error.HintStackUnderflow;
        for (0..loop) |_| {
            const point = try self.stack.popIndex();
            if (!self.compatibility.postIup()) {
                var context = try self.pointContext();
                try context.flipPoint(point);
            }
        }
        self.transient.loop = 1;
    }

    fn moveIndirectAbsolute(
        self: *Runtime,
        opcode: u8,
    ) types.Error!void {
        const cvt_index = try self.stack.popIndex();
        const point = try self.stack.popIndex();
        if (cvt_index >= self.cvt.len) return error.InvalidHintCvt;
        var context = try self.pointContext();
        try context.miap(
            point,
            self.cvt[cvt_index],
            (opcode & 1) != 0,
            self.retained.*,
        );
    }

    fn moveIndirectRelative(
        self: *Runtime,
        opcode: u8,
    ) types.Error!void {
        const cvt_operand = try self.stack.pop();
        const point = try self.stack.popIndex();
        // Microsoft and FreeType treat CVT index -1 as a synthetic zero
        // entry.  Other negative indices remain invalid.
        const cvt_value: i32 = if (cvt_operand == -1)
            0
        else blk: {
            if (cvt_operand < 0) return error.InvalidHintCvt;
            const index: usize = @intCast(cvt_operand);
            if (index >= self.cvt.len) return error.InvalidHintCvt;
            break :blk self.cvt[index];
        };
        var context = try self.pointContext();
        try context.mirp(
            point,
            cvt_value,
            opcode,
            self.retained.*,
        );
    }
};

fn axisVector(opcode: u8) zones.Vector {
    return zones.Vector.axis((opcode & 1) == 0);
}
