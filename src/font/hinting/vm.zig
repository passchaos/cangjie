//! Bounded TrueType size-program interpreter.
//!
//! This engine intentionally covers only operations valid without a glyph
//! point zone. It executes `fpgm` and `prep` to construct reusable PPEM state.
//! Point movement/measurement opcodes return `UnsupportedHintInstruction`
//! rather than silently degrading to no-ops; the raw glyph transaction will
//! extend the same dispatcher in a subsequent slice.

const std = @import("std");

const decode = @import("decode.zig");
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
    executed: usize = 0,
    backward_jumps: usize = 0,
    loop_calls: usize = 0,
    projection_vector: Vector = .{},
    freedom_vector: Vector = .{},
    round_mode: types.RoundMode = .grid,
    super_round_period: i32 = 64,
    super_round_phase: i32 = 0,
    super_round_threshold: i32 = 32,

    const Vector = struct {
        x: i32 = 0x4000,
        y: i32 = 0,
    };

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
        };
    }

    pub fn run(self: *Vm, program_value: types.Program) types.Error!void {
        self.cursor.reset(program_value);
        self.stack.clear();
        self.executed = 0;
        self.backward_jumps = 0;
        self.loop_calls = 0;
        self.projection_vector = .{};
        self.freedom_vector = .{};
        self.round_mode = .grid;
        self.super_round_period = 64;
        self.super_round_phase = 0;
        self.super_round_threshold = 32;
        while (true) {
            const bytecode = self.cursor.bytes();
            if (self.cursor.pc >= bytecode.len) {
                if (self.cursor.call_len != 0) {
                    return error.InvalidHintDefinition;
                }
                return;
            }
            const instruction = try decode.next(bytecode, self.cursor.pc);
            self.cursor.pc = instruction.next_pc;
            self.executed += 1;
            if (self.executed > max_executed_instructions) {
                return error.HintExecutionLimitExceeded;
            }
            try self.dispatch(instruction);
        }
    }

    fn dispatch(
        self: *Vm,
        instruction: decode.Instruction,
    ) types.Error!void {
        const opcode = instruction.opcode;
        if (instruction.operandCount() != 0 or
            opcode == 0x40 or opcode == 0x41 or
            (opcode >= 0xb0 and opcode <= 0xbf))
        {
            for (0..instruction.operandCount()) |index| {
                try self.stack.push(try instruction.operand(index));
            }
            return;
        }
        switch (opcode) {
            // Projection/freedom vectors reset per program but can participate
            // in prep control flow before that program ends.
            0x00, 0x01 => {
                const vector = axisVector(opcode);
                self.projection_vector = vector;
                self.freedom_vector = vector;
            },
            0x02, 0x03 => self.projection_vector = axisVector(opcode),
            0x04, 0x05 => self.freedom_vector = axisVector(opcode),
            0x0a => self.projection_vector = try self.popVector(),
            0x0b => self.freedom_vector = try self.popVector(),
            0x0c => {
                try self.stack.push(self.projection_vector.x);
                try self.stack.push(self.projection_vector.y);
            },
            0x0d => {
                try self.stack.push(self.freedom_vector.x);
                try self.stack.push(self.freedom_vector.y);
            },
            0x0e => self.freedom_vector = self.projection_vector,

            // Reference points, zones, and loop values do not persist from
            // prep to glyph execution. Validate/pop them without claiming a
            // usable point zone yet.
            0x10...0x12, 0x17 => _ = try self.stack.pop(),
            0x13...0x16 => {
                const zone = try self.stack.pop();
                if (zone != 0 and zone != 1) {
                    return error.InvalidHintOperand;
                }
            },
            0x18 => self.round_mode = .grid,
            0x19 => self.round_mode = .half_grid,
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
            0x3d => self.round_mode = .double_grid,

            0x42 => try self.writeStorage(),
            0x43 => try self.readStorage(),
            0x44 => try self.writeCvtPixels(),
            0x45 => try self.readCvt(),
            0x4b => try self.stack.push(self.graphics.ppem),
            0x4c => try self.stack.push(
                @min(
                    @as(i32, std.math.maxInt(i32)),
                    @as(i32, self.graphics.ppem) * 64,
                ),
            ),
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
                    return types.mulDiv(a, b, 64);
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
            0x7a => self.round_mode = .off,
            0x7c => self.round_mode = .up_to_grid,
            0x7d => self.round_mode = .down_to_grid,
            0x7e => _ = try self.stack.pop(),
            0x7f => {}, // AA is obsolete and ignored by FreeType.
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

            // GETVARIATION/GETDATA need normalized coordinate ownership, which
            // is added together with cvar and glyph point execution.
            0x91, 0x92 => return error.UnsupportedHintInstruction,

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
        return switch (self.round_mode) {
            .off => value,
            .grid => (value +| 32) & ~@as(i32, 63),
            .half_grid => (value & ~@as(i32, 63)) +% 32,
            .double_grid => (value +| 16) & ~@as(i32, 31),
            .down_to_grid => types.floor26Dot6(value),
            .up_to_grid => types.ceil26Dot6(value),
            .super, .super_45 => blk: {
                const period = self.super_round_period;
                if (period <= 0) break :blk value;
                const phase = self.super_round_phase;
                const threshold = self.super_round_threshold;
                break :blk @divFloor(
                    value - phase + threshold,
                    period,
                ) * period + phase;
            },
        };
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
        self.super_round_period = raw_period >> 8;
        self.super_round_phase = raw_phase >> 8;
        self.super_round_threshold = raw_threshold >> 8;
        self.round_mode = if (diagonal) .super_45 else .super;
    }

    fn instructionControl(self: *Vm) types.Error!void {
        const selector = try self.stack.pop();
        const value = try self.stack.pop();
        if (selector < 1 or selector > 3) return;
        const flag: u8 = @as(u8, 1) << @intCast(selector - 1);
        if (value != 0 and value != flag) return;
        if (self.cursor.initial_program != .control_value) return;
        self.graphics.instruct_control &= ~flag;
        self.graphics.instruct_control |= @intCast(value);
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
        if ((selector & 1) != 0) result = 40;
        if (self.graphics.target.isSmooth()) {
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

    fn loopLimit(self: Vm) usize {
        return 300 + 22 * self.cvt.len;
    }

    fn popVector(self: *Vm) types.Error!Vector {
        const y: i16 = @truncate(try self.stack.pop());
        const x: i16 = @truncate(try self.stack.pop());
        return .{ .x = x, .y = y };
    }

    fn accountSkippedInstruction(self: *Vm) types.Error!void {
        self.executed += 1;
        if (self.executed > max_executed_instructions) {
            return error.HintExecutionLimitExceeded;
        }
    }
};

fn axisVector(opcode: u8) Vm.Vector {
    return if ((opcode & 1) == 0)
        .{ .x = 0, .y = 0x4000 }
    else
        .{};
}

fn isCustomizableOpcode(opcode: u8) bool {
    return switch (opcode) {
        0x28, 0x7b, 0x83, 0x84, 0x8f, 0x90, 0x93...0xaf => true,
        else => false,
    };
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
