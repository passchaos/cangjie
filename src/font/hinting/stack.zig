//! Bounded TrueType interpreter value stack.

const types = @import("types.zig");

pub const Stack = struct {
    values: []i32,
    len: usize = 0,

    pub fn clear(self: *Stack) void {
        self.len = 0;
    }

    pub fn depth(self: Stack) usize {
        return self.len;
    }

    pub fn push(self: *Stack, value: i32) types.Error!void {
        if (self.len >= self.values.len) return error.HintStackOverflow;
        self.values[self.len] = value;
        self.len += 1;
    }

    pub fn pop(self: *Stack) types.Error!i32 {
        if (self.len == 0) return error.HintStackUnderflow;
        self.len -= 1;
        return self.values[self.len];
    }

    pub fn popIndex(self: *Stack) types.Error!usize {
        const value = try self.pop();
        if (value < 0) return error.InvalidHintOperand;
        return @intCast(value);
    }

    pub fn duplicate(self: *Stack) types.Error!void {
        if (self.len == 0) return error.HintStackUnderflow;
        try self.push(self.values[self.len - 1]);
    }

    pub fn swap(self: *Stack) types.Error!void {
        if (self.len < 2) return error.HintStackUnderflow;
        const top = self.len - 1;
        const previous = self.len - 2;
        const temporary = self.values[top];
        self.values[top] = self.values[previous];
        self.values[previous] = temporary;
    }

    pub fn copyIndex(self: *Stack) types.Error!void {
        const index = try self.popIndex();
        if (index == 0 or index > self.len) return error.InvalidHintOperand;
        try self.push(self.values[self.len - index]);
    }

    pub fn moveIndex(self: *Stack) types.Error!void {
        const index = try self.popIndex();
        if (index == 0 or index > self.len) return error.InvalidHintOperand;
        const source = self.len - index;
        const value = self.values[source];
        var cursor = source;
        while (cursor + 1 < self.len) : (cursor += 1) {
            self.values[cursor] = self.values[cursor + 1];
        }
        self.len -= 1;
        try self.push(value);
    }

    pub fn roll(self: *Stack) types.Error!void {
        if (self.len < 3) return error.HintStackUnderflow;
        const a = try self.pop();
        const b = try self.pop();
        const c = try self.pop();
        try self.push(b);
        try self.push(a);
        try self.push(c);
    }
};

test "bounded stack supports indexed movement" {
    const std = @import("std");
    var values: [8]i32 = undefined;
    var stack = Stack{ .values = &values };
    try stack.push(10);
    try stack.push(20);
    try stack.push(30);
    try stack.push(2);
    try stack.copyIndex();
    try std.testing.expectEqual(@as(i32, 20), try stack.pop());
    try stack.push(3);
    try stack.moveIndex();
    try std.testing.expectEqual(@as(i32, 10), try stack.pop());
}
