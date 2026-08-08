const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

const max_stack = 96;
const max_nesting_depth = 16;
const max_operations = 1_000_000;

pub const Info = struct {
    charstring_count: usize = 0,
    byte_count: usize = 0,
    number_count: usize = 0,
    operator_count: usize = 0,
    unknown_operator_count: usize = 0,
    local_subr_call_count: usize = 0,
    global_subr_call_count: usize = 0,
    hint_mask_count: usize = 0,
    stem_count: usize = 0,
    max_depth: u8 = 0,
    has_return: bool = false,
    has_endchar: bool = false,
    has_blend: bool = false,
    has_vsindex: bool = false,
};

/// Scan a CFF2/Type2 charstring and recursively visit subroutines reachable
/// through literal `callsubr`/`callgsubr` operands.
///
/// The supplied context type must provide:
/// - `localSubr(operand: i32) Error!?[]const u8`
/// - `globalSubr(operand: i32) Error!?[]const u8`
///
/// This is deliberately a structural scanner, not an outline interpreter: it
/// validates byte-stream bounds, tracks stack discipline for subroutine calls,
/// skips hint masks using the current stem count, and records features needed
/// by the later CFF2 executor. Geometry operators only clear the transient
/// operand stack because their coordinates are irrelevant for metadata scans.
pub fn scan(comptime Context: type, context: *Context, bytes: []const u8) Error!Info {
    var scanner = Scanner(Context){ .context = context };
    _ = try scanner.runCharString(bytes, 0);
    return scanner.info;
}

const Termination = enum {
    none,
    @"return",
    endchar,
};

const Value = struct {
    value: i32,
    integer: bool,
};

fn Scanner(comptime Context: type) type {
    return struct {
        context: *Context,
        stack: [max_stack]Value = undefined,
        stack_len: usize = 0,
        operation_count: usize = 0,
        info: Info = .{},

        const Self = @This();

        fn runCharString(self: *Self, bytes: []const u8, depth: u8) Error!Termination {
            if (depth > max_nesting_depth) return error.BadSfnt;
            self.info.charstring_count += 1;
            self.info.byte_count += bytes.len;
            self.info.max_depth = @max(self.info.max_depth, depth);

            var offset: usize = 0;
            while (offset < bytes.len) {
                self.operation_count += 1;
                if (self.operation_count > max_operations) return error.BadSfnt;

                const b = bytes[offset];
                offset += 1;
                if (b == 28 or b >= 32) {
                    try self.push(try readNumber(bytes, &offset, b));
                    self.info.number_count += 1;
                    continue;
                }

                const termination = try self.operator(bytes, &offset, b, depth);
                switch (termination) {
                    .none => {},
                    .@"return", .endchar => return termination,
                }
            }
            return .none;
        }

        fn operator(self: *Self, bytes: []const u8, offset: *usize, b: u8, depth: u8) Error!Termination {
            self.info.operator_count += 1;
            switch (b) {
                1, 3, 18, 23 => {
                    self.readStemHints();
                    return .none;
                },
                4, 5, 6, 7, 8, 21, 22, 24, 25, 26, 27, 30, 31 => {
                    self.clearStack();
                    return .none;
                },
                10 => return try self.callSubr(.local, depth),
                11 => {
                    self.info.has_return = true;
                    self.clearStack();
                    return .@"return";
                },
                12 => {
                    if (offset.* >= bytes.len) return error.BadSfnt;
                    const escaped = bytes[offset.*];
                    offset.* += 1;
                    return self.escapedOperator(escaped);
                },
                14 => {
                    self.info.has_endchar = true;
                    self.clearStack();
                    return .endchar;
                },
                15 => {
                    _ = try self.popInteger();
                    self.info.has_vsindex = true;
                    self.clearStack();
                    return .none;
                },
                16 => {
                    // Full blend evaluation depends on the ItemVariationStore.
                    // A scanner only needs to know that blend was present; the
                    // executor will apply deltas with coordinates later.
                    if (self.stack_len == 0) return error.BadSfnt;
                    self.info.has_blend = true;
                    self.clearStack();
                    return .none;
                },
                19, 20 => {
                    self.readStemHints();
                    const mask_len = (self.info.stem_count + 7) / 8;
                    if (mask_len > bytes.len - offset.*) return error.BadSfnt;
                    offset.* += mask_len;
                    self.info.hint_mask_count += 1;
                    return .none;
                },
                29 => return try self.callSubr(.global, depth),
                else => {
                    // FreeType/fontations tolerate reserved operators by
                    // dropping the current operands. Keep that compatibility in
                    // the structural pass while still surfacing a diagnostic
                    // count to callers.
                    self.info.unknown_operator_count += 1;
                    self.clearStack();
                    return .none;
                },
            }
        }

        fn escapedOperator(self: *Self, op: u8) Termination {
            switch (op) {
                0, 1, 2, 6, 7, 12, 16, 17, 33, 34, 35, 36, 37 => {},
                else => self.info.unknown_operator_count += 1,
            }
            self.clearStack();
            return .none;
        }

        const SubrKind = enum { local, global };

        fn callSubr(self: *Self, kind: SubrKind, depth: u8) Error!Termination {
            const operand = try self.popInteger();
            const subr = switch (kind) {
                .local => blk: {
                    self.info.local_subr_call_count += 1;
                    break :blk (try self.context.localSubr(operand)) orelse return error.BadSfnt;
                },
                .global => blk: {
                    self.info.global_subr_call_count += 1;
                    break :blk (try self.context.globalSubr(operand)) orelse return error.BadSfnt;
                },
            };
            const termination = try self.runCharString(subr, depth + 1);
            return switch (termination) {
                .none => error.BadSfnt,
                .@"return" => .none,
                .endchar => .endchar,
            };
        }

        fn push(self: *Self, value: Value) Error!void {
            if (self.stack_len == self.stack.len) return error.BadSfnt;
            self.stack[self.stack_len] = value;
            self.stack_len += 1;
        }

        fn popInteger(self: *Self) Error!i32 {
            if (self.stack_len == 0) return error.BadSfnt;
            self.stack_len -= 1;
            const value = self.stack[self.stack_len];
            if (!value.integer) return error.BadSfnt;
            return value.value;
        }

        fn readStemHints(self: *Self) void {
            self.info.stem_count += self.stack_len / 2;
            self.clearStack();
        }

        fn clearStack(self: *Self) void {
            self.stack_len = 0;
        }
    };
}

fn readNumber(bytes: []const u8, offset: *usize, first: u8) Error!Value {
    return switch (first) {
        28 => blk: {
            if (offset.* + 2 > bytes.len) return error.BadSfnt;
            const value: i32 = @as(i16, @bitCast(std.mem.readInt(u16, bytes[offset.*..][0..2], .big)));
            offset.* += 2;
            break :blk .{ .value = value, .integer = true };
        },
        32...246 => .{ .value = @as(i32, first) - 139, .integer = true },
        247...250 => blk: {
            if (offset.* >= bytes.len) return error.BadSfnt;
            const value = (@as(i32, first) - 247) * 256 + bytes[offset.*] + 108;
            offset.* += 1;
            break :blk .{ .value = value, .integer = true };
        },
        251...254 => blk: {
            if (offset.* >= bytes.len) return error.BadSfnt;
            const value = -((@as(i32, first) - 251) * 256 + bytes[offset.*] + 108);
            offset.* += 1;
            break :blk .{ .value = value, .integer = true };
        },
        255 => blk: {
            if (offset.* + 4 > bytes.len) return error.BadSfnt;
            const value = std.mem.readInt(i32, bytes[offset.*..][0..4], .big);
            offset.* += 4;
            break :blk .{ .value = value, .integer = false };
        },
        else => unreachable,
    };
}

test "CFF2 charstring scanner follows local and global subrs" {
    const Context = struct {
        pub fn localSubr(_: *@This(), operand: i32) Error!?[]const u8 {
            if (operand != -107) return null;
            return &.{11};
        }

        pub fn globalSubr(_: *@This(), operand: i32) Error!?[]const u8 {
            if (operand != -107) return null;
            return &.{11};
        }
    };

    var context = Context{};
    const parsed = try scan(Context, &context, &.{ 32, 10, 32, 29, 14 });
    try std.testing.expectEqual(@as(usize, 3), parsed.charstring_count);
    try std.testing.expectEqual(@as(usize, 7), parsed.byte_count);
    try std.testing.expectEqual(@as(usize, 2), parsed.number_count);
    try std.testing.expectEqual(@as(usize, 5), parsed.operator_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.local_subr_call_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.global_subr_call_count);
    try std.testing.expectEqual(@as(u8, 1), parsed.max_depth);
    try std.testing.expect(parsed.has_return);
    try std.testing.expect(parsed.has_endchar);
}

test "CFF2 charstring scanner skips hint masks" {
    const Context = struct {
        pub fn localSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }

        pub fn globalSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }
    };

    var context = Context{};
    // Two hstem pairs followed by one-byte hintmask payload and endchar.
    const parsed = try scan(Context, &context, &.{ 139, 140, 141, 142, 1, 19, 0xff, 14 });
    try std.testing.expectEqual(@as(usize, 2), parsed.stem_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.hint_mask_count);
    try std.testing.expect(parsed.has_endchar);
}
