//! Checked TrueType instruction decoding.

const std = @import("std");
const types = @import("types.zig");

pub const Instruction = struct {
    pc: usize,
    opcode: u8,
    next_pc: usize,
    operands: []const u8 = &.{},
    words: bool = false,

    pub fn operandCount(self: Instruction) usize {
        return if (self.words) self.operands.len / 2 else self.operands.len;
    }

    pub fn operand(self: Instruction, index: usize) types.Error!i32 {
        if (index >= self.operandCount()) return error.BadSfnt;
        if (!self.words) return self.operands[index];
        const start = index * 2;
        return std.mem.readInt(i16, self.operands[start..][0..2], .big);
    }
};

/// Decode one variable-length instruction. The VM inlines this in its hot
/// fetch loop; bounded-definition scans reuse the same checked implementation.
pub inline fn next(bytecode: []const u8, pc: usize) types.Error!Instruction {
    if (pc >= bytecode.len) return error.BadSfnt;
    const opcode = bytecode[pc];
    return switch (opcode) {
        0x40 => variablePush(bytecode, pc, false),
        0x41 => variablePush(bytecode, pc, true),
        0xb0...0xb7 => fixedPush(
            bytecode,
            pc,
            false,
            opcode - 0xb0 + 1,
        ),
        0xb8...0xbf => fixedPush(
            bytecode,
            pc,
            true,
            opcode - 0xb8 + 1,
        ),
        else => .{ .pc = pc, .opcode = opcode, .next_pc = pc + 1 },
    };
}

fn variablePush(
    bytecode: []const u8,
    pc: usize,
    words: bool,
) types.Error!Instruction {
    if (pc + 1 >= bytecode.len) return error.BadSfnt;
    const count: usize = bytecode[pc + 1];
    const length = count * if (words) @as(usize, 2) else 1;
    const start = pc + 2;
    if (start > bytecode.len or length > bytecode.len - start) {
        return error.BadSfnt;
    }
    return .{
        .pc = pc,
        .opcode = bytecode[pc],
        .next_pc = start + length,
        .operands = bytecode[start .. start + length],
        .words = words,
    };
}

fn fixedPush(
    bytecode: []const u8,
    pc: usize,
    words: bool,
    count_value: u8,
) types.Error!Instruction {
    const count: usize = count_value;
    const length = count * if (words) @as(usize, 2) else 1;
    const start = pc + 1;
    if (start > bytecode.len or length > bytecode.len - start) {
        return error.BadSfnt;
    }
    return .{
        .pc = pc,
        .opcode = bytecode[pc],
        .next_pc = start + length,
        .operands = bytecode[start .. start + length],
        .words = words,
    };
}

test "decoder preserves signed word operands" {
    const instruction = try next(&.{ 0xb9, 0xff, 0xfe, 0x00, 0x03 }, 0);
    try std.testing.expectEqual(@as(usize, 2), instruction.operandCount());
    try std.testing.expectEqual(@as(i32, -2), try instruction.operand(0));
    try std.testing.expectEqual(@as(i32, 3), try instruction.operand(1));
}
