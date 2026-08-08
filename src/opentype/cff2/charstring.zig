const std = @import("std");
const glyph_mod = @import("../../glyph.zig");

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

pub const BoundsInfo = struct {
    scan: Info = .{},
    has_bounds: bool = false,
    x_min: f32 = 0,
    y_min: f32 = 0,
    x_max: f32 = 0,
    y_max: f32 = 0,
    move_count: usize = 0,
    line_count: usize = 0,
    curve_count: usize = 0,
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

/// Execute enough of a CFF2/Type2 charstring to compute conservative outline
/// bounds and operation counts.
///
/// Cubic bounds solve the derivative roots for each axis instead of merely
/// including control points. That keeps public glyph bounds tight while still
/// reusing the same operand/subroutine machinery as the outline builder.
pub fn bounds(comptime Context: type, context: *Context, bytes: []const u8) Error!BoundsInfo {
    var executor = BoundsExecutor(Context){ .context = context };
    _ = try executor.runCharString(bytes, 0);
    return executor.bounds_info;
}

pub fn appendOutline(comptime Context: type, context: *Context, allocator: std.mem.Allocator, bytes: []const u8, outline: *glyph_mod.GlyphOutline) Error!BoundsInfo {
    var executor = BoundsExecutor(Context){
        .context = context,
        .allocator = allocator,
        .outline = outline,
    };
    _ = try executor.runCharString(bytes, 0);
    return executor.bounds_info;
}

const Termination = enum {
    none,
    @"return",
    endchar,
};

const Value = struct {
    number: f32,
    integer_value: i32 = 0,
    integer: bool,

    fn int(value: i32) Value {
        return .{
            .number = @as(f32, @floatFromInt(value)),
            .integer_value = value,
            .integer = true,
        };
    }

    fn fixed(raw: i32) Value {
        return .{
            .number = @as(f32, @floatFromInt(raw)) / 65536.0,
            .integer_value = raw,
            .integer = false,
        };
    }
};

fn Scanner(comptime Context: type) type {
    return struct {
        context: *Context,
        stack: [max_stack]Value = undefined,
        stack_len: usize = 0,
        operation_count: usize = 0,
        vs_index: u16 = 0,
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
                    self.vs_index = try popVariationStoreIndex(try self.popInteger());
                    self.info.has_vsindex = true;
                    return .none;
                },
                16 => {
                    try self.applyDefaultBlend();
                    self.info.has_blend = true;
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
            return value.integer_value;
        }

        fn applyDefaultBlend(self: *Self) Error!void {
            const target_count = try self.popInteger();
            const region_count = try contextBlendRegionCount(Context, self.context, self.vs_index);
            try foldDefaultBlend(&self.stack, &self.stack_len, target_count, region_count);
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

fn BoundsExecutor(comptime Context: type) type {
    return struct {
        context: *Context,
        stack: [max_stack]Value = undefined,
        stack_len: usize = 0,
        operation_count: usize = 0,
        x: f32 = 0,
        y: f32 = 0,
        contour_open: bool = false,
        vs_index: u16 = 0,
        allocator: ?std.mem.Allocator = null,
        outline: ?*glyph_mod.GlyphOutline = null,
        bounds_info: BoundsInfo = .{},

        const Self = @This();

        fn runCharString(self: *Self, bytes: []const u8, depth: u8) Error!Termination {
            if (depth > max_nesting_depth) return error.BadSfnt;
            self.bounds_info.scan.charstring_count += 1;
            self.bounds_info.scan.byte_count += bytes.len;
            self.bounds_info.scan.max_depth = @max(self.bounds_info.scan.max_depth, depth);

            var offset: usize = 0;
            while (offset < bytes.len) {
                self.operation_count += 1;
                if (self.operation_count > max_operations) return error.BadSfnt;

                const b = bytes[offset];
                offset += 1;
                if (b == 28 or b >= 32) {
                    try self.push(try readNumber(bytes, &offset, b));
                    self.bounds_info.scan.number_count += 1;
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
            self.bounds_info.scan.operator_count += 1;
            switch (b) {
                1, 3, 18, 23 => {
                    self.readStemHints();
                    return .none;
                },
                4 => {
                    try self.vmoveto();
                    return .none;
                },
                5 => {
                    try self.rlineto();
                    return .none;
                },
                6 => {
                    try self.hlineto();
                    return .none;
                },
                7 => {
                    try self.vlineto();
                    return .none;
                },
                8 => {
                    try self.rrcurveto();
                    return .none;
                },
                10 => return try self.callSubr(.local, depth),
                11 => {
                    self.bounds_info.scan.has_return = true;
                    self.clearStack();
                    return .@"return";
                },
                12 => {
                    if (offset.* >= bytes.len) return error.BadSfnt;
                    const escaped = bytes[offset.*];
                    offset.* += 1;
                    return try self.escapedOperator(escaped);
                },
                14 => {
                    self.bounds_info.scan.has_endchar = true;
                    try self.closeOpenContour();
                    self.clearStack();
                    return .endchar;
                },
                15 => {
                    self.vs_index = try popVariationStoreIndex(try self.popInteger());
                    self.bounds_info.scan.has_vsindex = true;
                    return .none;
                },
                16 => {
                    try self.applyDefaultBlend();
                    self.bounds_info.scan.has_blend = true;
                    return .none;
                },
                19, 20 => {
                    self.readStemHints();
                    const mask_len = (self.bounds_info.scan.stem_count + 7) / 8;
                    if (mask_len > bytes.len - offset.*) return error.BadSfnt;
                    offset.* += mask_len;
                    self.bounds_info.scan.hint_mask_count += 1;
                    return .none;
                },
                21 => {
                    try self.rmoveto();
                    return .none;
                },
                22 => {
                    try self.hmoveto();
                    return .none;
                },
                24 => {
                    try self.rcurveline();
                    return .none;
                },
                25 => {
                    try self.rlinecurve();
                    return .none;
                },
                26 => {
                    try self.vvcurveto();
                    return .none;
                },
                27 => {
                    try self.hhcurveto();
                    return .none;
                },
                29 => return try self.callSubr(.global, depth),
                30 => {
                    try self.vhcurveto();
                    return .none;
                },
                31 => {
                    try self.hvcurveto();
                    return .none;
                },
                else => {
                    self.bounds_info.scan.unknown_operator_count += 1;
                    self.clearStack();
                    return .none;
                },
            }
        }

        fn escapedOperator(self: *Self, op: u8) Error!Termination {
            switch (op) {
                0 => self.clearStack(),
                12 => try self.div(),
                34 => try self.hflex(),
                35 => try self.flex(),
                36 => try self.hflex1(),
                37 => try self.flex1(),
                else => {
                    self.bounds_info.scan.unknown_operator_count += 1;
                    self.clearStack();
                },
            }
            return .none;
        }

        const SubrKind = enum { local, global };

        fn callSubr(self: *Self, kind: SubrKind, depth: u8) Error!Termination {
            const operand = try self.popInteger();
            const subr = switch (kind) {
                .local => blk: {
                    self.bounds_info.scan.local_subr_call_count += 1;
                    break :blk (try self.context.localSubr(operand)) orelse return error.BadSfnt;
                },
                .global => blk: {
                    self.bounds_info.scan.global_subr_call_count += 1;
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

        fn rmoveto(self: *Self) Error!void {
            if (self.stack_len != 2) return error.BadSfnt;
            try self.closeOpenContour();
            self.x += self.stack[0].number;
            self.y += self.stack[1].number;
            try self.moveTo();
            self.clearStack();
        }

        fn hmoveto(self: *Self) Error!void {
            if (self.stack_len != 1) return error.BadSfnt;
            try self.closeOpenContour();
            self.x += self.stack[0].number;
            try self.moveTo();
            self.clearStack();
        }

        fn vmoveto(self: *Self) Error!void {
            if (self.stack_len != 1) return error.BadSfnt;
            try self.closeOpenContour();
            self.y += self.stack[0].number;
            try self.moveTo();
            self.clearStack();
        }

        fn rlineto(self: *Self) Error!void {
            if (self.stack_len < 2 or (self.stack_len & 1) != 0) return error.BadSfnt;
            var i: usize = 0;
            while (i < self.stack_len) : (i += 2) {
                try self.lineBy(self.stack[i].number, self.stack[i + 1].number);
            }
            self.clearStack();
        }

        fn hlineto(self: *Self) Error!void {
            if (self.stack_len == 0) return error.BadSfnt;
            var horizontal = true;
            for (self.stack[0..self.stack_len]) |delta| {
                if (horizontal) try self.lineBy(delta.number, 0) else try self.lineBy(0, delta.number);
                horizontal = !horizontal;
            }
            self.clearStack();
        }

        fn vlineto(self: *Self) Error!void {
            if (self.stack_len == 0) return error.BadSfnt;
            var vertical = true;
            for (self.stack[0..self.stack_len]) |delta| {
                if (vertical) try self.lineBy(0, delta.number) else try self.lineBy(delta.number, 0);
                vertical = !vertical;
            }
            self.clearStack();
        }

        fn rrcurveto(self: *Self) Error!void {
            if (self.stack_len < 6 or self.stack_len % 6 != 0) return error.BadSfnt;
            var i: usize = 0;
            while (i < self.stack_len) : (i += 6) {
                try self.curveByDeltas(self.stack[i].number, self.stack[i + 1].number, self.stack[i + 2].number, self.stack[i + 3].number, self.stack[i + 4].number, self.stack[i + 5].number);
            }
            self.clearStack();
        }

        fn rcurveline(self: *Self) Error!void {
            if (self.stack_len < 8 or ((self.stack_len - 2) % 6) != 0) return error.BadSfnt;
            var i: usize = 0;
            while (i + 2 < self.stack_len) : (i += 6) {
                try self.curveByDeltas(self.stack[i].number, self.stack[i + 1].number, self.stack[i + 2].number, self.stack[i + 3].number, self.stack[i + 4].number, self.stack[i + 5].number);
            }
            try self.lineBy(self.stack[self.stack_len - 2].number, self.stack[self.stack_len - 1].number);
            self.clearStack();
        }

        fn rlinecurve(self: *Self) Error!void {
            if (self.stack_len < 8 or ((self.stack_len - 6) & 1) != 0) return error.BadSfnt;
            var i: usize = 0;
            while (i + 6 < self.stack_len) : (i += 2) {
                try self.lineBy(self.stack[i].number, self.stack[i + 1].number);
            }
            try self.curveByDeltas(self.stack[i].number, self.stack[i + 1].number, self.stack[i + 2].number, self.stack[i + 3].number, self.stack[i + 4].number, self.stack[i + 5].number);
            self.clearStack();
        }

        fn vvcurveto(self: *Self) Error!void {
            var i: usize = 0;
            var dx1: f32 = 0;
            if ((self.stack_len & 1) != 0) {
                dx1 = self.stack[0].number;
                i = 1;
            }
            if (self.stack_len - i < 4 or ((self.stack_len - i) % 4) != 0) return error.BadSfnt;
            while (i < self.stack_len) : (i += 4) {
                try self.curveByDeltas(dx1, self.stack[i].number, self.stack[i + 1].number, self.stack[i + 2].number, 0, self.stack[i + 3].number);
                dx1 = 0;
            }
            self.clearStack();
        }

        fn hhcurveto(self: *Self) Error!void {
            var i: usize = 0;
            var dy1: f32 = 0;
            if ((self.stack_len & 1) != 0) {
                dy1 = self.stack[0].number;
                i = 1;
            }
            if (self.stack_len - i < 4 or ((self.stack_len - i) % 4) != 0) return error.BadSfnt;
            while (i < self.stack_len) : (i += 4) {
                try self.curveByDeltas(self.stack[i].number, dy1, self.stack[i + 1].number, self.stack[i + 2].number, self.stack[i + 3].number, 0);
                dy1 = 0;
            }
            self.clearStack();
        }

        fn vhcurveto(self: *Self) Error!void {
            try self.alternatingCurve(false);
        }

        fn hvcurveto(self: *Self) Error!void {
            try self.alternatingCurve(true);
        }

        fn alternatingCurve(self: *Self, horizontal_first: bool) Error!void {
            if (self.stack_len < 4) return error.BadSfnt;
            var i: usize = 0;
            var horizontal = horizontal_first;
            while (i + 4 <= self.stack_len) {
                const last_curve = self.stack_len - i == 5;
                const d6 = if (last_curve) self.stack[i + 4].number else 0;
                if (horizontal) {
                    try self.curveByDeltas(self.stack[i].number, 0, self.stack[i + 1].number, self.stack[i + 2].number, if (last_curve) d6 else 0, self.stack[i + 3].number);
                } else {
                    try self.curveByDeltas(0, self.stack[i].number, self.stack[i + 1].number, self.stack[i + 2].number, self.stack[i + 3].number, if (last_curve) d6 else 0);
                }
                i += if (last_curve) 5 else 4;
                horizontal = !horizontal;
            }
            if (i != self.stack_len) return error.BadSfnt;
            self.clearStack();
        }

        fn hflex(self: *Self) Error!void {
            if (self.stack_len != 7) return error.BadSfnt;
            const dx1 = self.stack[0].number;
            const dx2 = self.stack[1].number;
            const dy2 = self.stack[2].number;
            const dx3 = self.stack[3].number;
            const dx4 = self.stack[4].number;
            const dx5 = self.stack[5].number;
            const dx6 = self.stack[6].number;
            try self.curveByDeltas(dx1, 0, dx2, dy2, dx3, 0);
            try self.curveByDeltas(dx4, 0, dx5, -dy2, dx6, 0);
            self.clearStack();
        }

        fn flex(self: *Self) Error!void {
            if (self.stack_len != 13) return error.BadSfnt;
            try self.curveByDeltas(self.stack[0].number, self.stack[1].number, self.stack[2].number, self.stack[3].number, self.stack[4].number, self.stack[5].number);
            try self.curveByDeltas(self.stack[6].number, self.stack[7].number, self.stack[8].number, self.stack[9].number, self.stack[10].number, self.stack[11].number);
            self.clearStack();
        }

        fn hflex1(self: *Self) Error!void {
            if (self.stack_len != 9) return error.BadSfnt;
            const dx1 = self.stack[0].number;
            const dy1 = self.stack[1].number;
            const dx2 = self.stack[2].number;
            const dy2 = self.stack[3].number;
            const dx3 = self.stack[4].number;
            const dx4 = self.stack[5].number;
            const dx5 = self.stack[6].number;
            const dy5 = self.stack[7].number;
            const dx6 = self.stack[8].number;
            try self.curveByDeltas(dx1, dy1, dx2, dy2, dx3, 0);
            try self.curveByDeltas(dx4, 0, dx5, dy5, dx6, -(dy1 + dy2 + dy5));
            self.clearStack();
        }

        fn flex1(self: *Self) Error!void {
            if (self.stack_len != 11) return error.BadSfnt;
            const dx1 = self.stack[0].number;
            const dy1 = self.stack[1].number;
            const dx2 = self.stack[2].number;
            const dy2 = self.stack[3].number;
            const dx3 = self.stack[4].number;
            const dy3 = self.stack[5].number;
            const dx4 = self.stack[6].number;
            const dy4 = self.stack[7].number;
            const dx5 = self.stack[8].number;
            const dy5 = self.stack[9].number;
            const d6 = self.stack[10].number;
            const dx_total = dx1 + dx2 + dx3 + dx4 + dx5;
            const dy_total = dy1 + dy2 + dy3 + dy4 + dy5;
            const dx6: f32 = if (@abs(dx_total) > @abs(dy_total)) d6 else -dx_total;
            const dy6: f32 = if (@abs(dx_total) > @abs(dy_total)) -dy_total else d6;
            try self.curveByDeltas(dx1, dy1, dx2, dy2, dx3, dy3);
            try self.curveByDeltas(dx4, dy4, dx5, dy5, dx6, dy6);
            self.clearStack();
        }

        fn div(self: *Self) Error!void {
            if (self.stack_len < 2) return error.BadSfnt;
            const rhs = self.stack[self.stack_len - 1].number;
            if (rhs == 0) return error.BadSfnt;
            const lhs = self.stack[self.stack_len - 2].number;
            self.stack_len -= 2;
            try self.push(.{ .number = lhs / rhs, .integer = false });
        }

        fn lineBy(self: *Self, dx: f32, dy: f32) Error!void {
            self.includePoint(self.x, self.y);
            self.x += dx;
            self.y += dy;
            self.includePoint(self.x, self.y);
            self.bounds_info.line_count += 1;
            if (self.outline) |outline| {
                try outline.commands.append(self.allocator.?, .{ .line_to = .{ .x = self.x, .y = self.y } });
            }
        }

        fn curveByDeltas(self: *Self, dx1: f32, dy1: f32, dx2: f32, dy2: f32, dx3: f32, dy3: f32) Error!void {
            const p0_x = self.x;
            const p0_y = self.y;
            const c0_x = p0_x + dx1;
            const c0_y = p0_y + dy1;
            const c1_x = c0_x + dx2;
            const c1_y = c0_y + dy2;
            const p3_x = c1_x + dx3;
            const p3_y = c1_y + dy3;
            self.includePoint(p0_x, p0_y);
            self.includeCubicExtrema(p0_x, p0_y, c0_x, c0_y, c1_x, c1_y, p3_x, p3_y);
            self.includePoint(p3_x, p3_y);
            self.x = p3_x;
            self.y = p3_y;
            self.bounds_info.curve_count += 1;
            if (self.outline) |outline| {
                try outline.commands.append(self.allocator.?, .{ .cubic_to = .{
                    .c0 = .{ .x = c0_x, .y = c0_y },
                    .c1 = .{ .x = c1_x, .y = c1_y },
                    .end = .{ .x = self.x, .y = self.y },
                } });
            }
        }

        fn includeCubicExtrema(self: *Self, p0_x: f32, p0_y: f32, p1_x: f32, p1_y: f32, p2_x: f32, p2_y: f32, p3_x: f32, p3_y: f32) void {
            var roots: [4]f32 = undefined;
            var root_count: usize = 0;
            appendCubicDerivativeRoots(&roots, &root_count, p0_x, p1_x, p2_x, p3_x);
            appendCubicDerivativeRoots(&roots, &root_count, p0_y, p1_y, p2_y, p3_y);
            for (roots[0..root_count]) |t| {
                self.includePoint(
                    cubicAt(p0_x, p1_x, p2_x, p3_x, t),
                    cubicAt(p0_y, p1_y, p2_y, p3_y, t),
                );
            }
        }

        fn includePoint(self: *Self, x: f32, y: f32) void {
            if (!self.bounds_info.has_bounds) {
                self.bounds_info.has_bounds = true;
                self.bounds_info.x_min = x;
                self.bounds_info.x_max = x;
                self.bounds_info.y_min = y;
                self.bounds_info.y_max = y;
                return;
            }
            self.bounds_info.x_min = @min(self.bounds_info.x_min, x);
            self.bounds_info.x_max = @max(self.bounds_info.x_max, x);
            self.bounds_info.y_min = @min(self.bounds_info.y_min, y);
            self.bounds_info.y_max = @max(self.bounds_info.y_max, y);
        }

        fn moveTo(self: *Self) Error!void {
            self.bounds_info.move_count += 1;
            self.contour_open = true;
            if (self.outline) |outline| {
                try outline.commands.append(self.allocator.?, .{ .move_to = .{ .x = self.x, .y = self.y } });
            }
        }

        fn closeOpenContour(self: *Self) Error!void {
            if (self.contour_open) {
                if (self.outline) |outline| {
                    try outline.commands.append(self.allocator.?, .close);
                }
            }
            self.contour_open = false;
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
            return value.integer_value;
        }

        fn applyDefaultBlend(self: *Self) Error!void {
            const target_count = try self.popInteger();
            const region_count = try contextBlendRegionCount(Context, self.context, self.vs_index);
            try foldDefaultBlend(&self.stack, &self.stack_len, target_count, region_count);
        }

        fn readStemHints(self: *Self) void {
            self.bounds_info.scan.stem_count += self.stack_len / 2;
            self.clearStack();
        }

        fn clearStack(self: *Self) void {
            self.stack_len = 0;
        }
    };
}

fn contextBlendRegionCount(comptime Context: type, context: *Context, vs_index: u16) Error!usize {
    if (@hasDecl(Context, "blendRegionCount")) return try context.blendRegionCount(vs_index);
    return error.BadSfnt;
}

fn popVariationStoreIndex(index: i32) Error!u16 {
    if (index < 0 or index > std.math.maxInt(u16)) return error.BadSfnt;
    return @intCast(index);
}

fn foldDefaultBlend(stack: *[max_stack]Value, stack_len: *usize, target_count_value: i32, region_count: usize) Error!void {
    if (target_count_value < 0) return error.BadSfnt;
    const target_count: usize = @intCast(target_count_value);
    const per_target = region_count + 1;
    if (per_target == 0 or (target_count != 0 and per_target > std.math.maxInt(usize) / target_count)) return error.BadSfnt;
    const operand_count = target_count * per_target;
    if (operand_count > stack_len.*) return error.BadSfnt;
    const start = stack_len.* - operand_count;
    // At the default instance all blend scalars are zero, so the first `n`
    // operands are already the final values. Drop the following delta operands
    // while preserving any unrelated operands below this blend group.
    stack_len.* = start + target_count;
    _ = stack;
}

fn appendCubicDerivativeRoots(roots: *[4]f32, root_count: *usize, p0: f32, p1: f32, p2: f32, p3: f32) void {
    const a = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    const b = 2.0 * (p0 - 2.0 * p1 + p2);
    const c = p1 - p0;
    const epsilon = 0.000001;
    if (@abs(a) <= epsilon) {
        if (@abs(b) <= epsilon) return;
        appendUnitRoot(roots, root_count, -c / b);
        return;
    }
    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0) return;
    if (discriminant <= epsilon) {
        appendUnitRoot(roots, root_count, -b / (2.0 * a));
        return;
    }
    const sqrt_discriminant = @sqrt(discriminant);
    appendUnitRoot(roots, root_count, (-b + sqrt_discriminant) / (2.0 * a));
    appendUnitRoot(roots, root_count, (-b - sqrt_discriminant) / (2.0 * a));
}

fn appendUnitRoot(roots: *[4]f32, root_count: *usize, t: f32) void {
    if (t <= 0 or t >= 1) return;
    for (roots[0..root_count.*]) |existing| {
        if (@abs(existing - t) <= 0.000001) return;
    }
    roots[root_count.*] = t;
    root_count.* += 1;
}

fn cubicAt(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) f32 {
    const mt = 1.0 - t;
    return mt * mt * mt * p0 + 3.0 * mt * mt * t * p1 + 3.0 * mt * t * t * p2 + t * t * t * p3;
}

fn readNumber(bytes: []const u8, offset: *usize, first: u8) Error!Value {
    return switch (first) {
        28 => blk: {
            if (offset.* + 2 > bytes.len) return error.BadSfnt;
            const value: i32 = @as(i16, @bitCast(std.mem.readInt(u16, bytes[offset.*..][0..2], .big)));
            offset.* += 2;
            break :blk Value.int(value);
        },
        32...246 => Value.int(@as(i32, first) - 139),
        247...250 => blk: {
            if (offset.* >= bytes.len) return error.BadSfnt;
            const value = (@as(i32, first) - 247) * 256 + bytes[offset.*] + 108;
            offset.* += 1;
            break :blk Value.int(value);
        },
        251...254 => blk: {
            if (offset.* >= bytes.len) return error.BadSfnt;
            const value = -((@as(i32, first) - 251) * 256 + bytes[offset.*] + 108);
            offset.* += 1;
            break :blk Value.int(value);
        },
        255 => blk: {
            if (offset.* + 4 > bytes.len) return error.BadSfnt;
            const value = std.mem.readInt(i32, bytes[offset.*..][0..4], .big);
            offset.* += 4;
            break :blk Value.fixed(value);
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

test "CFF2 charstring bounds tracks moves and lines" {
    const Context = struct {
        pub fn localSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }

        pub fn globalSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }
    };

    var context = Context{};
    // rmoveto(50, 20); rlineto(100, 0, 0, 30); endchar.
    const parsed = try bounds(Context, &context, &.{ 189, 159, 21, 239, 139, 139, 169, 5, 14 });
    try std.testing.expect(parsed.has_bounds);
    try std.testing.expectEqual(@as(f32, 50), parsed.x_min);
    try std.testing.expectEqual(@as(f32, 20), parsed.y_min);
    try std.testing.expectEqual(@as(f32, 150), parsed.x_max);
    try std.testing.expectEqual(@as(f32, 50), parsed.y_max);
    try std.testing.expectEqual(@as(usize, 1), parsed.move_count);
    try std.testing.expectEqual(@as(usize, 2), parsed.line_count);
    try std.testing.expectEqual(@as(usize, 0), parsed.curve_count);
    try std.testing.expect(parsed.scan.has_endchar);
}

test "CFF2 charstring bounds solves cubic extrema" {
    const Context = struct {
        pub fn localSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }

        pub fn globalSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }
    };

    var context = Context{};
    // rmoveto(0, 0); rrcurveto(50, 100, 0, 0, 50, -100); endchar.
    // Control points reach y=100, but the curve itself peaks at y=75.
    const parsed = try bounds(Context, &context, &.{ 139, 139, 21, 189, 239, 139, 139, 189, 39, 8, 14 });
    try std.testing.expect(parsed.has_bounds);
    try std.testing.expectEqual(@as(f32, 0), parsed.x_min);
    try std.testing.expectEqual(@as(f32, 0), parsed.y_min);
    try std.testing.expectEqual(@as(f32, 100), parsed.x_max);
    try std.testing.expectApproxEqAbs(@as(f32, 75), parsed.y_max, 0.001);
    try std.testing.expectEqual(@as(usize, 1), parsed.move_count);
    try std.testing.expectEqual(@as(usize, 0), parsed.line_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.curve_count);
    try std.testing.expect(parsed.scan.has_endchar);
}

test "CFF2 charstring bounds excludes off-curve controls when monotonic" {
    const Context = struct {
        pub fn localSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }

        pub fn globalSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }
    };

    var context = Context{};
    // rmoveto(0, 0); rrcurveto(0, 100, 100, -100, 100, 0); endchar.
    // The off-curve control reaches y=100, but the curve extrema stay inside.
    const parsed = try bounds(Context, &context, &.{ 139, 139, 21, 139, 239, 239, 39, 239, 139, 8, 14 });
    try std.testing.expect(parsed.has_bounds);
    try std.testing.expectEqual(@as(f32, 0), parsed.x_min);
    try std.testing.expectEqual(@as(f32, 0), parsed.y_min);
    try std.testing.expectEqual(@as(f32, 200), parsed.x_max);
    try std.testing.expectApproxEqAbs(@as(f32, 44.44445), parsed.y_max, 0.001);
    try std.testing.expectEqual(@as(usize, 1), parsed.curve_count);
}

test "CFF2 charstring default blend folds deltas" {
    const Context = struct {
        pub fn blendRegionCount(_: *@This(), vs_index: u16) Error!usize {
            if (vs_index != 0) return error.BadSfnt;
            return 2;
        }

        pub fn localSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }

        pub fn globalSubr(_: *@This(), _: i32) Error!?[]const u8 {
            return null;
        }
    };

    var context = Context{};
    // 50 50 100 1 blend 0 rmoveto; 10 hlineto. At the default instance
    // the blend keeps the default x value (50) and drops the deltas.
    const parsed = try bounds(Context, &context, &.{ 189, 189, 239, 140, 16, 139, 21, 149, 6, 14 });
    try std.testing.expect(parsed.scan.has_blend);
    try std.testing.expect(parsed.has_bounds);
    try std.testing.expectEqual(@as(f32, 50), parsed.x_min);
    try std.testing.expectEqual(@as(f32, 0), parsed.y_min);
    try std.testing.expectEqual(@as(f32, 60), parsed.x_max);
    try std.testing.expectEqual(@as(f32, 0), parsed.y_max);
    try std.testing.expectEqual(@as(usize, 1), parsed.move_count);
    try std.testing.expectEqual(@as(usize, 1), parsed.line_count);
}
