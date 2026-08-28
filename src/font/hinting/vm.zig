//! Bounded TrueType font, size, and glyph-program interpreter.
//!
//! Font and size programs construct reusable PPEM state.  Glyph programs can
//! additionally attach private twilight/glyph working zones; point movement
//! then remains isolated until the caller commits a successful run.

const std = @import("std");

const decode = @import("decode.zig");
const compatibility_mod = @import("glyph/compatibility.zig");
const glyph_opcodes = @import("glyph/opcodes.zig");
const zones = @import("glyph/zones.zig");
const program_mod = @import("program.zig");
const stack_mod = @import("stack.zig");
const types = @import("types.zig");

const max_executed_instructions: usize = 1_000_000;

pub const Vm = struct {
    source: types.Source,
    cursor: program_mod.Cursor,
    definitions: program_mod.Definitions,
    stack: stack_mod.Stack,
    cvt: []i32,
    storage: []i32,
    graphics: *types.RetainedGraphicsState,
    twilight: ?zones.Zone = null,
    glyph: ?zones.Zone = null,
    point_scale_16_16: i32 = 0,
    executed: usize = 0,
    backward_jumps: usize = 0,
    loop_calls: usize = 0,
    transient: zones.GraphicsState = .{},
    compatibility: compatibility_mod.State = .{},
    is_compound: bool = false,
    line_vector_cache: zones.LineVectorCache = .{},

    pub fn init(
        source: types.Source,
        definitions: program_mod.Definitions,
        stack_values: []i32,
        cvt: []i32,
        storage: []i32,
        graphics: *types.RetainedGraphicsState,
    ) Vm {
        return .{
            .source = source,
            .cursor = program_mod.Cursor.init(source, .font),
            .definitions = definitions,
            .stack = .{ .values = stack_values },
            .cvt = cvt,
            .storage = storage,
            .graphics = graphics,
            .compatibility = compatibility_mod.State.init(
                source.interpreter,
                graphics.target,
                graphics.instruct_control,
                source.tricky,
            ),
        };
    }

    pub fn run(self: *Vm, program_value: types.Program) types.Error!void {
        self.cursor.reset(program_value);
        self.stack.clear();
        self.executed = 0;
        self.backward_jumps = 0;
        self.loop_calls = 0;
        self.transient = .{};
        if (program_value == .glyph) {
            self.compatibility.beginGlyph(self.is_compound);
        } else {
            // Font and prep programs always run without v40 movement hacks.
            self.compatibility = .{};
        }
        // Zone bindings and their owners stay stable for an entire program.
        // Build this adapter once; its state fields are pointers, so scalar
        // opcodes below still update what later point opcodes observe.
        var point_runtime = self.pointRuntime();
        while (true) {
            const bytecode = self.cursor.bytes();
            if (self.cursor.pc >= bytecode.len) {
                if (self.cursor.call_len != 0) {
                    return error.InvalidHintDefinition;
                }
                return;
            }
            const opcode = bytecode[self.cursor.pc];
            // The only variable-length TrueType instructions are pushes. Keep
            // their checked decode separate so ordinary one-byte opcodes do
            // not construct and pass an Instruction record.
            if (opcode == 0x40 or opcode == 0x41 or
                (opcode >= 0xb0 and opcode <= 0xbf))
            {
                const instruction = try decode.next(
                    bytecode,
                    self.cursor.pc,
                );
                self.cursor.pc = instruction.next_pc;
                try self.accountInstruction();
                try self.pushOperands(instruction);
                continue;
            }
            self.cursor.pc += 1;
            try self.accountInstruction();
            try self.dispatch(opcode, &point_runtime);
        }
    }

    inline fn accountInstruction(self: *Vm) types.Error!void {
        self.executed += 1;
        if (self.executed > max_executed_instructions) {
            return error.HintExecutionLimitExceeded;
        }
    }

    fn pushOperands(
        self: *Vm,
        instruction: decode.Instruction,
    ) types.Error!void {
        const count = instruction.operandCount();
        if (count > self.stack.values.len - self.stack.len) {
            return error.HintStackOverflow;
        }
        if (instruction.words) {
            for (0..count) |index| {
                const start = index * 2;
                self.stack.values[self.stack.len + index] = std.mem.readInt(
                    i16,
                    instruction.operands[start..][0..2],
                    .big,
                );
            }
        } else {
            // The range was checked by decode.next, so one capacity proof is
            // sufficient for the complete byte operand batch. Bound the
            // destination to the batch: Zig's multi-slice loop requires equal
            // lengths, while the stack normally has additional spare slots.
            for (
                instruction.operands,
                self.stack.values[self.stack.len..][0..count],
            ) |value, *destination| {
                destination.* = value;
            }
        }
        self.stack.len += count;
    }

    pub fn attachZones(
        self: *Vm,
        twilight: zones.Zone,
        glyph: zones.Zone,
        point_scale_16_16: i32,
        is_compound: bool,
    ) types.Error!void {
        try twilight.validate();
        try glyph.validate();
        self.twilight = twilight;
        self.glyph = glyph;
        self.point_scale_16_16 = point_scale_16_16;
        self.is_compound = is_compound;
    }

    fn dispatch(
        self: *Vm,
        opcode: u8,
        point_runtime: *glyph_opcodes.Runtime,
    ) types.Error!void {
        if (opcode >= 0xc0) {
            return point_runtime.relativeMove(opcode);
        }
        if (glyph_opcodes.handles(opcode)) {
            if (!try point_runtime.handle(opcode)) unreachable;
            return;
        }
        switch (opcode) {
            0x00, 0x01 => {
                const vector = zones.Vector.axis((opcode & 1) == 0);
                self.transient.projection = vector;
                self.transient.dual_projection = vector;
                self.transient.freedom = vector;
            },
            0x02, 0x03 => {
                const vector = zones.Vector.axis((opcode & 1) == 0);
                self.transient.projection = vector;
                self.transient.dual_projection = vector;
            },
            0x04, 0x05 => self.transient.freedom = zones.Vector.axis((opcode & 1) == 0),
            0x0e => self.transient.freedom = self.transient.projection,
            0x10...0x12 => {
                const value = try self.stack.popIndex();
                switch (opcode) {
                    0x10 => self.transient.rp0 = value,
                    0x11 => self.transient.rp1 = value,
                    0x12 => self.transient.rp2 = value,
                    else => unreachable,
                }
            },
            0x13...0x16 => {
                const value = try self.stack.pop();
                if (value < 0 or value > 1) return error.InvalidHintOperand;
                const zone_index: u8 = @intCast(value);
                switch (opcode) {
                    0x13 => self.transient.zp0 = zone_index,
                    0x14 => self.transient.zp1 = zone_index,
                    0x15 => self.transient.zp2 = zone_index,
                    0x16 => {
                        self.transient.zp0 = zone_index;
                        self.transient.zp1 = zone_index;
                        self.transient.zp2 = zone_index;
                    },
                    else => unreachable,
                }
            },
            0x17 => {
                const loop = try self.stack.popIndex();
                if (loop == 0) return error.InvalidHintOperand;
                self.transient.loop = loop;
            },
            0x18 => self.transient.round_mode = .grid,
            0x19 => self.transient.round_mode = .half_grid,
            0x1a => self.graphics.min_distance = try self.stack.pop(),
            0x1b => try self.skipToEif(),
            0x1c => try self.jump(true),
            0x1d => self.graphics.control_value_cutin = try self.stack.pop(),
            0x1e => self.graphics.single_width_cutin = try self.stack.pop(),
            0x1f => self.graphics.single_width = types.scaleFUnits(
                try self.stack.pop(),
                self.graphics.scale_16_16,
            ),

            0x20 => try self.stack.duplicate(),
            0x21 => _ = try self.stack.pop(),
            0x22 => self.stack.clear(),
            0x23 => try self.stack.swap(),
            0x24 => try self.stack.push(@intCast(self.stack.depth())),
            0x25 => try self.stack.copyIndex(),
            0x26 => try self.stack.moveIndex(),
            0x2a => try self.loopCall(),
            0x2b => try self.call(1),
            0x2c => try self.define(false),
            0x2d => try self.cursor.leave(),
            0x3d => self.transient.round_mode = .double_grid,

            0x42 => try self.writeStorage(),
            0x43 => try self.readStorage(),
            0x44 => try self.writeCvtPixels(),
            0x45 => try self.readCvt(),
            0x4b => try self.stack.push(self.graphics.ppem),
            0x4c => try self.stack.push(if (self.source.interpreter == .classic)
                self.graphics.ppem
            else
                @min(
                    @as(i32, std.math.maxInt(i32)),
                    @as(i32, self.graphics.ppem) * 64,
                )),
            0x4d => self.graphics.auto_flip = true,
            0x4e => self.graphics.auto_flip = false,
            0x4f => _ = try self.stack.pop(),

            0x50 => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a < b;
                }
            }.call),
            0x51 => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a <= b;
                }
            }.call),
            0x52 => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a > b;
                }
            }.call),
            0x53 => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a >= b;
                }
            }.call),
            0x54 => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a == b;
                }
            }.call),
            0x55 => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a != b;
                }
            }.call),
            0x56 => try self.oddEven(true),
            0x57 => try self.oddEven(false),
            0x58 => if (try self.stack.pop() == 0) try self.skipFalseBranch(),
            0x59 => {},
            0x5a => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a != 0 and b != 0;
                }
            }.call),
            0x5b => try self.binaryBoolean(struct {
                fn call(a: i32, b: i32) bool {
                    return a != 0 or b != 0;
                }
            }.call),
            0x5c => try self.stack.push(
                @intFromBool(try self.stack.pop() == 0),
            ),
            0x5e => self.graphics.delta_base = try self.stack.pop(),
            0x5f => {
                const shift = try self.stack.pop();
                if (shift < 0 or shift > 6) {
                    return error.InvalidHintOperand;
                }
                self.graphics.delta_shift = shift;
            },
            0x60 => try self.binaryArithmetic(struct {
                fn call(a: i32, b: i32) types.Error!i32 {
                    return a +% b;
                }
            }.call),
            0x61 => try self.binaryArithmetic(struct {
                fn call(a: i32, b: i32) types.Error!i32 {
                    return a -% b;
                }
            }.call),
            0x62 => try self.binaryArithmetic(struct {
                fn call(a: i32, b: i32) types.Error!i32 {
                    return types.mulDiv(a, 64, b);
                }
            }.call),
            0x63 => try self.binaryArithmetic(struct {
                fn call(a: i32, b: i32) types.Error!i32 {
                    return types.mulDivNearest(a, b, 64);
                }
            }.call),
            0x64 => {
                const value = try self.stack.pop();
                try self.stack.push(if (value == std.math.minInt(i32))
                    std.math.minInt(i32)
                else if (value < 0)
                    -value
                else
                    value);
            },
            0x65 => try self.stack.push(-%(try self.stack.pop())),
            0x66 => try self.stack.push(types.floor26Dot6(try self.stack.pop())),
            0x67 => try self.stack.push(types.ceil26Dot6(try self.stack.pop())),
            0x68...0x6b => try self.stack.push(
                self.round26Dot6(try self.stack.pop()),
            ),
            0x6c...0x6f => {},
            0x70 => try self.writeCvtFUnits(),
            0x73...0x75 => try self.deltaC(opcode),
            0x76 => try self.setSuperRound(false),
            0x77 => try self.setSuperRound(true),
            0x78 => try self.jump(try self.stack.pop() != 0),
            0x79 => try self.jump(try self.stack.pop() == 0),
            0x7a => self.transient.round_mode = .off,
            0x7c => self.transient.round_mode = .up_to_grid,
            0x7d => self.transient.round_mode = .down_to_grid,
            0x7e, 0x7f => _ = try self.stack.pop(),
            0x85 => try self.scanControl(),
            0x88 => try self.getInfo(),
            0x89 => try self.define(true),
            0x8a => try self.stack.roll(),
            0x8b => try self.binaryArithmetic(struct {
                fn call(a: i32, b: i32) types.Error!i32 {
                    return @max(a, b);
                }
            }.call),
            0x8c => try self.binaryArithmetic(struct {
                fn call(a: i32, b: i32) types.Error!i32 {
                    return @min(a, b);
                }
            }.call),
            0x8d => self.graphics.scan_type = (try self.stack.pop()) & 0xffff,
            0x8e => try self.instructionControl(),

            0x91 => try self.getVariation(),
            0x92 => try self.stack.push(17),

            // Every remaining standard opcode touches a point zone or relies
            // on projection vectors derived from point geometry.
            else => {
                if (!isCustomizableOpcode(opcode)) {
                    return error.UnsupportedHintInstruction;
                }
                const definition =
                    self.definitions.get(true, opcode) catch
                        return error.UnsupportedHintInstruction;
                try self.cursor.enter(definition, 1);
            },
        }
    }

    fn pointRuntime(self: *Vm) glyph_opcodes.Runtime {
        return .{
            .stack = &self.stack,
            .cvt = self.cvt,
            .retained = self.graphics,
            .transient = &self.transient,
            .compatibility = &self.compatibility,
            .twilight = if (self.twilight) |*value| value else null,
            .glyph = if (self.glyph) |*value| value else null,
            .point_scale_16_16 = self.point_scale_16_16,
            .line_vector_cache = &self.line_vector_cache,
        };
    }

    fn define(self: *Vm, instruction: bool) types.Error!void {
        if (self.cursor.initial_program == .glyph) {
            return error.InvalidHintDefinition;
        }
        const key = try self.stack.pop();
        const start = self.cursor.pc;
        const bytecode = self.cursor.bytes();
        var pc = start;
        while (pc < bytecode.len) {
            const value = try decode.next(bytecode, pc);
            try self.accountSkippedInstruction();
            if (value.opcode == 0x2c or value.opcode == 0x89) {
                return error.InvalidHintDefinition;
            }
            if (value.opcode == 0x2d) {
                if (value.next_pc - start > std.math.maxInt(u16)) {
                    return error.InvalidHintDefinition;
                }
                try self.definitions.define(
                    instruction,
                    key,
                    self.cursor.program,
                    start,
                    value.next_pc,
                );
                self.cursor.pc = value.next_pc;
                return;
            }
            pc = value.next_pc;
        }
        return error.InvalidHintDefinition;
    }

    fn call(self: *Vm, count: usize) types.Error!void {
        const key = try self.stack.pop();
        const definition = try self.definitions.get(false, key);
        try self.cursor.enter(definition, count);
    }

    fn loopCall(self: *Vm) types.Error!void {
        const key = try self.stack.pop();
        const count_value = try self.stack.pop();
        if (count_value <= 0) return;
        const count: usize = @intCast(count_value);
        self.loop_calls += count;
        if (self.loop_calls > self.loopLimit()) {
            return error.HintExecutionLimitExceeded;
        }
        const definition = try self.definitions.get(false, key);
        try self.cursor.enter(definition, count);
    }

    fn jump(self: *Vm, take: bool) types.Error!void {
        const offset = try self.stack.pop();
        if (!take) return;
        const instruction_pc = self.cursor.pc - 1;
        const target_signed = @as(i64, @intCast(instruction_pc)) +
            @as(i64, offset);
        if (target_signed < 0) return error.InvalidHintJump;
        const target: usize = @intCast(target_signed);
        if (target > self.cursor.bytes().len or target == instruction_pc) {
            return error.InvalidHintJump;
        }
        if (target < instruction_pc) {
            self.backward_jumps += 1;
            if (self.backward_jumps > self.loopLimit()) {
                return error.HintExecutionLimitExceeded;
            }
        }
        self.cursor.pc = target;
    }

    fn skipFalseBranch(self: *Vm) types.Error!void {
        const bytecode = self.cursor.bytes();
        var depth: usize = 1;
        var pc = self.cursor.pc;
        while (pc < bytecode.len) {
            const value = try decode.next(bytecode, pc);
            try self.accountSkippedInstruction();
            pc = value.next_pc;
            switch (value.opcode) {
                0x58 => depth += 1,
                0x59 => {
                    depth -= 1;
                    if (depth == 0) {
                        self.cursor.pc = pc;
                        return;
                    }
                },
                0x1b => if (depth == 1) {
                    self.cursor.pc = pc;
                    return;
                },
                else => {},
            }
        }
        return error.InvalidHintJump;
    }

    fn skipToEif(self: *Vm) types.Error!void {
        const bytecode = self.cursor.bytes();
        var depth: usize = 1;
        var pc = self.cursor.pc;
        while (pc < bytecode.len) {
            const value = try decode.next(bytecode, pc);
            try self.accountSkippedInstruction();
            pc = value.next_pc;
            switch (value.opcode) {
                0x58 => depth += 1,
                0x59 => {
                    depth -= 1;
                    if (depth == 0) {
                        self.cursor.pc = pc;
                        return;
                    }
                },
                else => {},
            }
        }
        return error.InvalidHintJump;
    }

    fn writeStorage(self: *Vm) types.Error!void {
        const value = try self.stack.pop();
        const index = try self.stack.popIndex();
        if (index >= self.storage.len) return error.InvalidHintStorage;
        self.storage[index] = value;
    }

    fn readStorage(self: *Vm) types.Error!void {
        const index = try self.stack.popIndex();
        if (index >= self.storage.len) return error.InvalidHintStorage;
        try self.stack.push(self.storage[index]);
    }

    fn writeCvtPixels(self: *Vm) types.Error!void {
        const value = try self.stack.pop();
        const index = try self.stack.popIndex();
        if (index >= self.cvt.len) return error.InvalidHintCvt;
        self.cvt[index] = value;
    }

    fn writeCvtFUnits(self: *Vm) types.Error!void {
        const value = try self.stack.pop();
        const index = try self.stack.popIndex();
        if (index >= self.cvt.len) return error.InvalidHintCvt;
        self.cvt[index] = types.scaleFUnits(
            value,
            self.graphics.scale_16_16,
        );
    }

    fn readCvt(self: *Vm) types.Error!void {
        const index = try self.stack.popIndex();
        if (index >= self.cvt.len) return error.InvalidHintCvt;
        try self.stack.push(self.cvt[index]);
    }

    fn binaryBoolean(
        self: *Vm,
        comptime operation: fn (i32, i32) bool,
    ) types.Error!void {
        const b = try self.stack.pop();
        const a = try self.stack.pop();
        try self.stack.push(@intFromBool(operation(a, b)));
    }

    fn binaryArithmetic(
        self: *Vm,
        comptime operation: fn (i32, i32) types.Error!i32,
    ) types.Error!void {
        const b = try self.stack.pop();
        const a = try self.stack.pop();
        try self.stack.push(try operation(a, b));
    }

    fn round26Dot6(self: Vm, value: i32) i32 {
        return self.transient.round(value);
    }

    fn oddEven(self: *Vm, odd: bool) types.Error!void {
        const rounded = self.round26Dot6(try self.stack.pop());
        const is_odd = ((rounded >> 6) & 1) != 0;
        try self.stack.push(@intFromBool(is_odd == odd));
    }

    fn deltaC(self: *Vm, opcode: u8) types.Error!void {
        const count_value = try self.stack.pop();
        if (count_value < 0) return error.InvalidHintOperand;
        const count: usize = @intCast(count_value);
        if (count > self.stack.depth() / 2) {
            return error.HintStackUnderflow;
        }
        const bias: i32 = self.graphics.delta_base + switch (opcode) {
            0x74 => @as(i32, 16),
            0x75 => @as(i32, 32),
            else => @as(i32, 0),
        };
        for (0..count) |_| {
            const cvt_index = try self.stack.popIndex();
            var packed_delta = try self.stack.pop();
            const target_ppem = ((packed_delta & 0xf0) >> 4) + bias;
            if (target_ppem != @as(i32, self.graphics.ppem)) continue;
            if (cvt_index >= self.cvt.len) return error.InvalidHintCvt;
            packed_delta = (packed_delta & 0x0f) - 8;
            if (packed_delta >= 0) packed_delta += 1;
            const multiplier: i32 =
                @as(i32, 1) << @intCast(6 - self.graphics.delta_shift);
            self.cvt[cvt_index] +%= packed_delta *% multiplier;
        }
    }

    fn setSuperRound(self: *Vm, diagonal: bool) types.Error!void {
        const selector = try self.stack.pop();
        const grid_period: i32 = if (diagonal) 0x2d41 else 0x4000;
        const raw_period = switch (selector & 0xc0) {
            0 => @divTrunc(grid_period, 2),
            0x40, 0xc0 => grid_period,
            0x80 => grid_period * 2,
            else => grid_period,
        };
        const raw_phase = switch (selector & 0x30) {
            0 => 0,
            0x10 => @divTrunc(raw_period, 4),
            0x20 => @divTrunc(raw_period, 2),
            0x30 => @divTrunc(raw_period * 3, 4),
            else => 0,
        };
        const raw_threshold = if ((selector & 0x0f) == 0)
            raw_period - 1
        else
            @divTrunc(((selector & 0x0f) - 4) * raw_period, 8);
        self.transient.super_round_period = raw_period >> 8;
        self.transient.super_round_phase = raw_phase >> 8;
        self.transient.super_round_threshold = raw_threshold >> 8;
        self.transient.round_mode = if (diagonal) .super_45 else .super;
    }

    fn instructionControl(self: *Vm) types.Error!void {
        const selector = try self.stack.pop();
        const value = try self.stack.pop();
        if (selector < 1 or selector > 3) return;
        const flag: u8 = @as(u8, 1) << @intCast(selector - 1);
        if (value != 0 and value != flag) return;
        switch (self.cursor.initial_program) {
            .control_value => {
                self.graphics.instruct_control &= ~flag;
                self.graphics.instruct_control |= @intCast(value);
            },
            .glyph => if (selector == 3) {
                self.compatibility.setGlyphInstructionControl(
                    self.source.interpreter,
                    @intCast(value),
                );
            },
            .font => {},
        }
    }

    fn scanControl(self: *Vm) types.Error!void {
        const value = try self.stack.pop();
        const threshold = value & 0xff;
        if (threshold == 0xff) {
            self.graphics.scan_control = true;
        } else if (threshold == 0) {
            self.graphics.scan_control = false;
        } else {
            if ((value & 0x100) != 0 and
                self.graphics.ppem <= threshold)
            {
                self.graphics.scan_control = true;
            }
            if ((value & 0x800) != 0 and
                self.graphics.ppem > threshold)
            {
                self.graphics.scan_control = false;
            }
        }
    }

    fn getInfo(self: *Vm) types.Error!void {
        const selector = try self.stack.pop();
        var result: i32 = 0;
        if ((selector & 1) != 0) {
            result = self.source.interpreter.advertisedVersion();
        }
        if ((selector & (1 << 3)) != 0 and
            self.source.normalized_coords.len != 0)
        {
            result |= 1 << 10;
        }
        // FreeType v40 reports ClearType capabilities instead of the classic
        // grayscale bit, even for its normal grayscale render target.
        if (self.source.interpreter == .classic and
            (selector & (1 << 5)) != 0 and
            self.graphics.target.isSmooth())
        {
            result |= 1 << 12;
        }
        if (self.source.interpreter == .cleartype and
            self.graphics.target != .mono)
        {
            if ((selector & (1 << 6)) != 0) result |= 1 << 13;
            if ((selector & (1 << 8)) != 0 and
                self.graphics.target.isVerticalLcd())
            {
                result |= 1 << 15;
            }
            if ((selector & (1 << 10)) != 0) result |= 1 << 17;
            if ((selector & (1 << 11)) != 0) result |= 1 << 18;
            if ((selector & (1 << 12)) != 0 and
                self.graphics.target.isGrayscaleClearType())
            {
                result |= 1 << 19;
            }
        }
        try self.stack.push(result);
    }

    fn getVariation(self: *Vm) types.Error!void {
        for (self.source.normalized_coords) |coordinate| {
            if (!std.math.isFinite(coordinate) or
                coordinate < -1 or coordinate > 1)
            {
                return error.InvalidHintOperand;
            }
            try self.stack.push(@intFromFloat(
                @round(coordinate * 16384.0),
            ));
        }
    }

    fn loopLimit(self: Vm) usize {
        return 300 + 22 * self.cvt.len;
    }

    fn accountSkippedInstruction(self: *Vm) types.Error!void {
        self.executed += 1;
        if (self.executed > max_executed_instructions) {
            return error.HintExecutionLimitExceeded;
        }
    }
};

fn isCustomizableOpcode(opcode: u8) bool {
    return switch (opcode) {
        0x28, 0x7b, 0x83, 0x84, 0x8f, 0x90, 0x93...0xaf => true,
        else => false,
    };
}

test "byte pushes fill only the unused stack prefix" {
    var stack_values: [8]i32 = undefined;
    var graphics = types.RetainedGraphicsState{
        .scale_16_16 = 0x10000,
        .ppem = 16,
    };
    const source = types.Source{
        .units_per_em = 1000,
        .font_program = &.{ 0xb2, 7, 8, 9 },
        .control_value_program = &.{},
        .control_value_data = &.{},
        .limits = .{
            .max_storage = 0,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = stack_values.len,
            .max_twilight_points = 0,
        },
    };
    var vm = Vm.init(
        source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );

    try vm.run(.font);
    try std.testing.expectEqual(@as(usize, 3), vm.stack.depth());
    try std.testing.expectEqualSlices(i32, &.{ 7, 8, 9 }, vm.stack.values[0..3]);
}

test "font definitions execute from prep with bounded state" {
    var function_defs: [2]program_mod.Definition =
        .{program_mod.Definition{}} ** 2;
    var instruction_defs: [1]program_mod.Definition =
        .{program_mod.Definition{}} ** 1;
    var stack_values: [16]i32 = undefined;
    var cvt = [_]i32{0};
    var storage = [_]i32{0};
    var graphics = types.RetainedGraphicsState{
        .scale_16_16 = 0x10000,
        .ppem = 16,
    };
    const source = types.Source{
        .units_per_em = 1000,
        // Function 0 adds 2.
        .font_program = &.{ 0xb0, 0, 0x2c, 0xb0, 2, 0x60, 0x2d },
        // Push 40, call function 0, store result at storage[0].
        .control_value_program = &.{ 0xb0, 40, 0xb0, 0, 0x2b, 0xb0, 0, 0x23, 0x42 },
        .control_value_data = &.{ 0, 0 },
        .limits = .{
            .max_storage = 1,
            .max_function_defs = 2,
            .max_instruction_defs = 1,
            .max_stack_elements = 16,
            .max_twilight_points = 0,
        },
    };
    var vm = Vm.init(
        source,
        .{
            .functions = &function_defs,
            .instructions = &instruction_defs,
        },
        &stack_values,
        &cvt,
        &storage,
        &graphics,
    );
    vm.definitions.clear();
    try vm.run(.font);
    try vm.run(.control_value);
    try std.testing.expectEqual(@as(i32, 42), storage[0]);
}

test "definition scanner ignores ENDF bytes inside push immediates" {
    var function_defs: [1]program_mod.Definition =
        .{program_mod.Definition{}} ** 1;
    var stack_values: [8]i32 = undefined;
    var graphics = types.RetainedGraphicsState{
        .scale_16_16 = 0x10000,
        .ppem = 16,
    };
    const source = types.Source{
        .units_per_em = 1000,
        // FDEF0 pushes byte 0x2D as data, pops it, and then ends.
        .font_program = &.{ 0xb0, 0, 0x2c, 0xb0, 0x2d, 0x21, 0x2d },
        .control_value_program = &.{},
        .control_value_data = &.{},
        .limits = .{
            .max_storage = 0,
            .max_function_defs = 1,
            .max_instruction_defs = 0,
            .max_stack_elements = 8,
            .max_twilight_points = 0,
        },
    };
    var vm = Vm.init(
        source,
        .{ .functions = &function_defs, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );
    vm.definitions.clear();
    try vm.run(.font);
    try std.testing.expectEqual(
        @as(usize, source.font_program.len),
        (try vm.definitions.get(false, 0)).end,
    );
}

test "GETINFO advertises selected interpreter capabilities" {
    var stack_values: [4]i32 = undefined;
    var graphics = types.RetainedGraphicsState{
        .scale_16_16 = 0x10000,
        .ppem = 16,
        .target = .normal,
    };
    const selector: u16 =
        1 | (1 << 3) | (1 << 5) | (1 << 6) | (1 << 8) |
        (1 << 10) | (1 << 11) | (1 << 12);
    const source = types.Source{
        .units_per_em = 1000,
        .font_program = &.{},
        .control_value_program = &.{},
        .normalized_coords = &.{0},
        .glyph_program = &.{
            0xb8,
            @intCast(selector >> 8),
            @truncate(selector),
            0x88,
        },
        .control_value_data = &.{},
        .limits = .{
            .max_storage = 0,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = stack_values.len,
            .max_twilight_points = 0,
        },
    };
    var vm = Vm.init(
        source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );

    try vm.run(.glyph);
    try std.testing.expectEqual(@as(usize, 1), vm.stack.depth());
    try std.testing.expectEqual(
        @as(i32, 35 | (1 << 10) | (1 << 12)),
        vm.stack.values[0],
    );

    var clear_type_source = source;
    clear_type_source.interpreter = .cleartype;
    vm = Vm.init(
        clear_type_source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );
    try vm.run(.glyph);
    try std.testing.expectEqual(
        @as(i32, 40 | (1 << 10) | (1 << 13) |
            (1 << 17) | (1 << 18) | (1 << 19)),
        vm.stack.values[0],
    );

    graphics.target = .vertical_lcd;
    vm = Vm.init(
        clear_type_source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );
    try vm.run(.glyph);
    try std.testing.expectEqual(
        @as(i32, 40 | (1 << 10) | (1 << 13) |
            (1 << 15) | (1 << 17) | (1 << 18)),
        vm.stack.values[0],
    );

    graphics.target = .mono;
    vm = Vm.init(
        clear_type_source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );
    try vm.run(.glyph);
    try std.testing.expectEqual(
        @as(i32, 40 | (1 << 10)),
        vm.stack.values[0],
    );
}

test "MPS follows selected interpreter point-size contract" {
    var stack_values: [2]i32 = undefined;
    var graphics = types.RetainedGraphicsState{
        .scale_16_16 = 0x10000,
        .ppem = 16,
    };
    var source = types.Source{
        .units_per_em = 1000,
        .font_program = &.{},
        .control_value_program = &.{},
        .glyph_program = &.{0x4c},
        .control_value_data = &.{},
        .limits = .{
            .max_storage = 0,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = stack_values.len,
            .max_twilight_points = 0,
        },
    };
    var vm = Vm.init(
        source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );
    try vm.run(.glyph);
    try std.testing.expectEqual(@as(i32, 16), vm.stack.values[0]);

    source.interpreter = .cleartype;
    vm = Vm.init(
        source,
        .{ .functions = &.{}, .instructions = &.{} },
        &stack_values,
        &.{},
        &.{},
        &graphics,
    );
    try vm.run(.glyph);
    try std.testing.expectEqual(@as(i32, 1024), vm.stack.values[0]);
}
