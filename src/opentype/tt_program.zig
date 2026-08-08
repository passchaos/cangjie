const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const Kind = enum {
    /// The TrueType `fpgm` table. Its definitions are available to later
    /// size and glyph programs when a bytecode interpreter is present.
    font,
    /// The TrueType `prep` table. FreeType calls this the CVT program because
    /// it runs after scaling CVT values for a size.
    control_value,
};

pub const Instruction = struct {
    offset: usize,
    opcode: u8,
    length: usize,
    immediate: []const u8 = &.{},
    push_value_count: ?u16 = null,
    push_words: bool = false,

    pub fn isPush(self: Instruction) bool {
        return self.push_value_count != null;
    }
};

pub const Info = struct {
    kind: Kind,
    bytecode: []const u8,
    instructions: []Instruction,
};

pub fn validate(bytecode: []const u8) Error!void {
    var cursor: usize = 0;
    while (cursor < bytecode.len) {
        const inst = try instructionAt(bytecode, cursor);
        cursor += inst.length;
    }
}

pub fn info(allocator: std.mem.Allocator, kind: Kind, bytecode: []const u8) Error!Info {
    var count: usize = 0;
    var cursor: usize = 0;
    while (cursor < bytecode.len) {
        const inst = try instructionAt(bytecode, cursor);
        cursor += inst.length;
        count += 1;
    }

    const instructions = try allocator.alloc(Instruction, count);
    errdefer allocator.free(instructions);
    cursor = 0;
    for (instructions) |*inst| {
        inst.* = try instructionAt(bytecode, cursor);
        cursor += inst.length;
    }
    return .{ .kind = kind, .bytecode = bytecode, .instructions = instructions };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    allocator.free(value.instructions);
}

fn instructionAt(bytecode: []const u8, offset: usize) Error!Instruction {
    if (offset >= bytecode.len) return error.BadSfnt;
    const opcode = bytecode[offset];
    return switch (opcode) {
        0x40 => try nPushInstruction(bytecode, offset, opcode, false),
        0x41 => try nPushInstruction(bytecode, offset, opcode, true),
        0xb0...0xb7 => try fixedPushInstruction(bytecode, offset, opcode, false, opcode - 0xb0 + 1),
        0xb8...0xbf => try fixedPushInstruction(bytecode, offset, opcode, true, opcode - 0xb8 + 1),
        else => .{ .offset = offset, .opcode = opcode, .length = 1 },
    };
}

fn nPushInstruction(bytecode: []const u8, offset: usize, opcode: u8, words: bool) Error!Instruction {
    if (2 > bytecode.len - offset) return error.BadSfnt;
    const count: usize = bytecode[offset + 1];
    const immediate_len = if (words) count * 2 else count;
    if (immediate_len > bytecode.len - offset - 2) return error.BadSfnt;
    return .{
        .offset = offset,
        .opcode = opcode,
        .length = 2 + immediate_len,
        .immediate = bytecode[offset + 2 .. offset + 2 + immediate_len],
        .push_value_count = @intCast(count),
        .push_words = words,
    };
}

fn fixedPushInstruction(bytecode: []const u8, offset: usize, opcode: u8, words: bool, count_u8: u8) Error!Instruction {
    const count: usize = count_u8;
    const immediate_len = if (words) count * 2 else count;
    if (immediate_len > bytecode.len - offset - 1) return error.BadSfnt;
    return .{
        .offset = offset,
        .opcode = opcode,
        .length = 1 + immediate_len,
        .immediate = bytecode[offset + 1 .. offset + 1 + immediate_len],
        .push_value_count = count_u8,
        .push_words = words,
    };
}

test "TrueType programs expose fixed and variable push instructions" {
    const bytes = [_]u8{
        0xb1, 0x01, 0x02, // PUSHB[2]
        0x41, 0x02, 0x00, 0x03, 0xff, 0xfe, // NPUSHW[2]
        0x2d, // ENDF (ordinary one-byte opcode to this structural parser)
    };

    const parsed = try info(std.testing.allocator, .font, &bytes);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(Kind.font, parsed.kind);
    try std.testing.expectEqual(@as(usize, 3), parsed.instructions.len);
    try std.testing.expectEqual(@as(u8, 0xb1), parsed.instructions[0].opcode);
    try std.testing.expectEqual(@as(?u16, 2), parsed.instructions[0].push_value_count);
    try std.testing.expect(!parsed.instructions[0].push_words);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, parsed.instructions[0].immediate);
    try std.testing.expectEqual(@as(u8, 0x41), parsed.instructions[1].opcode);
    try std.testing.expect(parsed.instructions[1].push_words);
    try std.testing.expectEqual(@as(usize, 6), parsed.instructions[1].length);
    try std.testing.expect(!parsed.instructions[2].isPush());
}

test "TrueType program validation rejects truncated push immediates" {
    try std.testing.expectError(error.BadSfnt, validate(&.{ 0xb2, 0x01, 0x02 }));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 0x40, 0x02, 0x01 }));
    try std.testing.expectError(error.BadSfnt, validate(&.{ 0x41, 0x01, 0x00 }));
}
