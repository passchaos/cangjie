//! TrueType code-range, definition, and bounded call-stack management.

const types = @import("types.zig");

pub const Definition = struct {
    program: types.Program = .font,
    start: usize = 0,
    end: usize = 0,
    key: i32 = 0,
    active: bool = false,
};

pub const Definitions = struct {
    functions: []Definition,
    instructions: []Definition,

    pub fn clear(self: Definitions) void {
        @memset(self.functions, .{});
        @memset(self.instructions, .{});
    }

    pub fn define(
        self: Definitions,
        instruction: bool,
        key: i32,
        program_value: types.Program,
        start: usize,
        end: usize,
    ) types.Error!void {
        const definitions = if (instruction)
            self.instructions
        else
            self.functions;
        if (key >= 0) {
            const direct: usize = @intCast(key);
            if (direct < definitions.len and
                (!definitions[direct].active or
                    definitions[direct].key == key))
            {
                definitions[direct] = .{
                    .program = program_value,
                    .start = start,
                    .end = end,
                    .key = key,
                    .active = true,
                };
                return;
            }
        }
        var free_index: ?usize = null;
        var index = definitions.len;
        while (index > 0) {
            index -= 1;
            const existing = definitions[index];
            if (existing.active and existing.key == key) {
                definitions[index] = .{
                    .program = program_value,
                    .start = start,
                    .end = end,
                    .key = key,
                    .active = true,
                };
                return;
            }
            if (!existing.active and free_index == null) free_index = index;
        }
        const target = free_index orelse
            return error.TooManyHintDefinitions;
        definitions[target] = .{
            .program = program_value,
            .start = start,
            .end = end,
            .key = key,
            .active = true,
        };
    }

    pub fn get(
        self: Definitions,
        instruction: bool,
        key: i32,
    ) types.Error!Definition {
        const definitions = if (instruction)
            self.instructions
        else
            self.functions;
        if (key >= 0) {
            const direct: usize = @intCast(key);
            if (direct < definitions.len) {
                const value = definitions[direct];
                if (value.active and value.key == key) return value;
            }
        }
        var index = definitions.len;
        while (index > 0) {
            index -= 1;
            const value = definitions[index];
            if (value.active and value.key == key) return value;
        }
        return error.InvalidHintDefinition;
    }
};

pub const Cursor = struct {
    sources: [3][]const u8,
    initial_program: types.Program,
    program: types.Program,
    pc: usize = 0,
    calls: [32]Call = undefined,
    call_len: usize = 0,

    const Call = struct {
        caller_program: types.Program,
        return_pc: usize,
        definition: Definition,
        remaining: usize,
    };

    pub fn init(source: types.Source, program_value: types.Program) Cursor {
        return .{
            .sources = .{
                source.font_program,
                source.control_value_program,
                source.glyph_program,
            },
            .initial_program = program_value,
            .program = program_value,
        };
    }

    pub fn reset(self: *Cursor, program_value: types.Program) void {
        self.initial_program = program_value;
        self.program = program_value;
        self.pc = 0;
        self.call_len = 0;
    }

    pub fn bytes(self: Cursor) []const u8 {
        return self.sources[@intFromEnum(self.program)];
    }

    pub fn enter(
        self: *Cursor,
        definition: Definition,
        count: usize,
    ) types.Error!void {
        if (count == 0) return;
        if (self.call_len >= self.calls.len) {
            return error.HintCallStackOverflow;
        }
        self.calls[self.call_len] = .{
            .caller_program = self.program,
            .return_pc = self.pc,
            .definition = definition,
            .remaining = count,
        };
        self.call_len += 1;
        self.program = definition.program;
        self.pc = definition.start;
    }

    pub fn leave(self: *Cursor) types.Error!void {
        if (self.call_len == 0) return error.InvalidHintDefinition;
        var call = self.calls[self.call_len - 1];
        if (call.remaining > 1) {
            call.remaining -= 1;
            self.calls[self.call_len - 1] = call;
            self.program = call.definition.program;
            self.pc = call.definition.start;
            return;
        }
        self.call_len -= 1;
        self.program = call.caller_program;
        self.pc = call.return_pc;
    }
};

test "definitions support direct and sparse keys" {
    const std = @import("std");
    var functions: [3]Definition = .{Definition{}} ** 3;
    var instructions: [2]Definition = .{Definition{}} ** 2;
    const definitions = Definitions{
        .functions = &functions,
        .instructions = &instructions,
    };
    try definitions.define(false, 1, .font, 4, 8);
    try definitions.define(false, 42, .font, 9, 12);
    try std.testing.expectEqual(@as(usize, 4), (try definitions.get(false, 1)).start);
    try std.testing.expectEqual(@as(usize, 9), (try definitions.get(false, 42)).start);
}
