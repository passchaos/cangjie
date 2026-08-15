//! Unicode 17 bidirectional paragraph resolution (UAX #9).
//!
//! This module resolves one scalar-indexed paragraph. UTF-8 decoding, public
//! byte mappings, and per-line L1/L2 reordering live in the facade so the core
//! algorithm can also consume the property-only `BidiTest.txt` fixture.

const std = @import("std");

const property_data = @import("data.zig");

pub const Class = property_data.Class;
pub const max_explicit_level: u8 = 125;
pub const removed_level: u8 = 0xff;

pub const BaseDirection = enum {
    ltr,
    rtl,
    auto,
};

pub const Input = struct {
    codepoint: u21,
    class: Class,
};

const Override = enum {
    neutral,
    ltr,
    rtl,
};

const StackEntry = struct {
    level: u8,
    override: Override,
    isolate: bool,
};

const Run = struct {
    level: u8,
    start: usize,
    end: usize,
    sos: Class = .on,
    eos: Class = .on,
    starts_with_pdi: bool = false,
    ends_with_isolate: bool = false,
    in_sequence: bool = false,
    next: ?usize = null,
};

const BracketPair = struct {
    open: usize,
    close: usize,
};

pub const Scratch = struct {
    allocator: std.mem.Allocator,
    initial_types: std.ArrayList(Class) = .empty,
    types: std.ArrayList(Class) = .empty,
    levels: std.ArrayList(u8) = .empty,
    runs: std.ArrayList(Run) = .empty,
    indices: std.ArrayList(usize) = .empty,
    sequence_types: std.ArrayList(Class) = .empty,
    bracket_pairs: std.ArrayList(BracketPair) = .empty,

    pub fn init(allocator: std.mem.Allocator) Scratch {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Scratch) void {
        self.bracket_pairs.deinit(self.allocator);
        self.sequence_types.deinit(self.allocator);
        self.indices.deinit(self.allocator);
        self.runs.deinit(self.allocator);
        self.levels.deinit(self.allocator);
        self.types.deinit(self.allocator);
        self.initial_types.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn resolve(
        self: *Scratch,
        inputs: []const Input,
        base_direction: BaseDirection,
    ) std.mem.Allocator.Error!u8 {
        self.clearRetainingCapacity();
        try self.initial_types.ensureTotalCapacity(self.allocator, inputs.len);
        try self.types.ensureTotalCapacity(self.allocator, inputs.len);
        try self.levels.ensureTotalCapacity(self.allocator, inputs.len);
        for (inputs) |input| {
            self.initial_types.appendAssumeCapacity(input.class);
            self.types.appendAssumeCapacity(input.class);
            self.levels.appendAssumeCapacity(0);
        }

        resolveFirstStrongIsolates(self.types.items);
        const base_level: u8 = switch (base_direction) {
            .ltr => 0,
            .rtl => 1,
            .auto => defaultLevel(self.types.items),
        };
        if (inputs.len == 0) return base_level;
        if (isPureLtr(self.initial_types.items, base_level)) {
            @memset(self.levels.items, 0);
            return base_level;
        }

        resolveExplicit(self.types.items, self.levels.items, base_level);
        try self.resolveRuns(base_level);
        for (self.runs.items, 0..) |run, run_index| {
            if (run.in_sequence) continue;
            try self.resolveSequence(inputs, run_index);
        }
        // L1 resets paragraph/segment separators and the trailing formatting
        // context that immediately precedes them. The conformance suites expect
        // this line-ready form rather than raw X/I levels.
        resetParagraphLevels(
            self.initial_types.items,
            self.levels.items,
            base_level,
        );
        for (self.initial_types.items, 0..) |value, index| {
            if (isRemovedByX9(value)) self.levels.items[index] = removed_level;
        }
        return base_level;
    }

    pub fn resolvedLevels(self: *const Scratch) []const u8 {
        return self.levels.items;
    }

    pub fn initialTypes(self: *const Scratch) []const Class {
        return self.initial_types.items;
    }

    fn clearRetainingCapacity(self: *Scratch) void {
        self.initial_types.clearRetainingCapacity();
        self.types.clearRetainingCapacity();
        self.levels.clearRetainingCapacity();
        self.runs.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
        self.sequence_types.clearRetainingCapacity();
        self.bracket_pairs.clearRetainingCapacity();
    }

    fn resolveRuns(
        self: *Scratch,
        base_level: u8,
    ) std.mem.Allocator.Error!void {
        const types = self.types.items;
        const levels = self.levels.items;
        var start: usize = 0;
        while (start < types.len and isRemovedByX9(types[start])) : (start += 1) {}
        if (start == types.len) return;

        var run_start = start;
        var level = levels[start];
        var cursor = start + 1;
        while (cursor < types.len) : (cursor += 1) {
            if (isRemovedByX9(types[cursor])) continue;
            if (levels[cursor] == level) continue;
            try self.runs.append(self.allocator, .{
                .level = level,
                .start = run_start,
                .end = cursor,
            });
            run_start = cursor;
            level = levels[cursor];
        }
        try self.runs.append(self.allocator, .{
            .level = level,
            .start = run_start,
            .end = types.len,
        });

        for (self.runs.items) |*run| {
            while (run.start < run.end and isRemovedByX9(types[run.start])) {
                run.start += 1;
            }
            while (run.end > run.start and isRemovedByX9(types[run.end - 1])) {
                run.end -= 1;
            }
            if (run.start == run.end) continue;
            run.starts_with_pdi = types[run.start] == .pdi;

            var previous_level = base_level;
            var index = run.start;
            while (index > 0) {
                index -= 1;
                if (isRemovedByX9(types[index])) continue;
                previous_level = levels[index];
                break;
            }
            run.sos = typeFromLevel(@max(previous_level, run.level));

            if (isIsolateInitiator(self.initial_types.items[run.end - 1])) {
                run.ends_with_isolate = true;
                run.eos = typeFromLevel(@max(base_level, run.level));
            } else {
                var next_level = base_level;
                index = run.end;
                while (index < types.len) : (index += 1) {
                    if (isRemovedByX9(types[index])) continue;
                    next_level = levels[index];
                    break;
                }
                run.eos = typeFromLevel(@max(next_level, run.level));
            }
        }

        for (self.runs.items, 0..) |*run, run_index| {
            if (!run.ends_with_isolate) continue;
            var next_index = run_index + 1;
            while (next_index < self.runs.items.len) : (next_index += 1) {
                const candidate = &self.runs.items[next_index];
                if (!candidate.starts_with_pdi or
                    candidate.level != run.level) continue;
                run.next = next_index;
                candidate.in_sequence = true;
                break;
            }
        }
    }

    fn resolveSequence(
        self: *Scratch,
        inputs: []const Input,
        first_run_index: usize,
    ) std.mem.Allocator.Error!void {
        self.indices.clearRetainingCapacity();
        self.sequence_types.clearRetainingCapacity();
        var run_index = first_run_index;
        const sequence_level = self.runs.items[first_run_index].level;
        const sos = self.runs.items[first_run_index].sos;
        var eos = sos;
        while (true) {
            const run = self.runs.items[run_index];
            var index = run.start;
            while (index < run.end) : (index += 1) {
                if (isRemovedByX9(self.types.items[index])) continue;
                try self.indices.append(self.allocator, index);
                try self.sequence_types.append(
                    self.allocator,
                    self.types.items[index],
                );
            }
            eos = run.eos;
            run_index = run.next orelse break;
        }
        if (self.indices.items.len == 0) return;

        resolveWeak(self.sequence_types.items, sos, eos);
        try self.resolveNeutral(inputs, sequence_level, sos, eos);
        resolveImplicit(
            self.sequence_types.items,
            self.indices.items,
            self.levels.items,
            sequence_level,
        );
    }

    fn resolveNeutral(
        self: *Scratch,
        inputs: []const Input,
        sequence_level: u8,
        sos: Class,
        eos: Class,
    ) std.mem.Allocator.Error!void {
        try self.resolveBrackets(inputs, sequence_level, sos);
        const types = self.sequence_types.items;
        const embedding = typeFromLevel(sequence_level);
        var previous = sos;
        var cursor: usize = 0;
        while (cursor < types.len) {
            if (!isNeutralOrIsolate(types[cursor])) {
                previous = types[cursor];
                cursor += 1;
                continue;
            }
            const start = cursor;
            while (cursor < types.len and isNeutralOrIsolate(types[cursor])) {
                cursor += 1;
            }
            const next = if (cursor == types.len) eos else types[cursor];
            const leading = strongForNeutral(previous);
            const trailing = strongForNeutral(next);
            const resolved = if (leading == trailing) leading else embedding;
            @memset(types[start..cursor], resolved);
            previous = resolved;
        }
    }

    fn resolveBrackets(
        self: *Scratch,
        inputs: []const Input,
        sequence_level: u8,
        sos: Class,
    ) std.mem.Allocator.Error!void {
        self.bracket_pairs.clearRetainingCapacity();
        var stack_opening: [63]u21 = undefined;
        var stack_position: [63]usize = undefined;
        var depth: usize = 0;
        for (self.indices.items, 0..) |input_index, sequence_index| {
            if (self.sequence_types.items[sequence_index] != .on) continue;
            const bracket = property_data.bracket(inputs[input_index].codepoint) orelse continue;
            if (bracket.is_open) {
                if (depth == stack_opening.len) break;
                stack_opening[depth] = bracket.opening;
                stack_position[depth] = sequence_index;
                depth += 1;
                continue;
            }
            var stack_index = depth;
            while (stack_index > 0) {
                stack_index -= 1;
                if (stack_opening[stack_index] != bracket.opening) continue;
                try self.bracket_pairs.append(self.allocator, .{
                    .open = stack_position[stack_index],
                    .close = sequence_index,
                });
                depth = stack_index;
                break;
            }
        }
        if (self.bracket_pairs.items.len == 0) return;
        std.sort.heap(
            BracketPair,
            self.bracket_pairs.items,
            {},
            bracketPairLessThan,
        );

        const types = self.sequence_types.items;
        const embedding = typeFromLevel(sequence_level);
        for (self.bracket_pairs.items) |pair| {
            var pair_direction: Class = .on;
            for (types[pair.open + 1 .. pair.close]) |value| {
                const direction = strongForBracket(value);
                if (direction == .on) continue;
                pair_direction = direction;
                if (direction == embedding) break;
            }
            if (pair_direction == .on) continue;
            if (pair_direction != embedding) {
                pair_direction = sos;
                var index = pair.open;
                while (index > 0) {
                    index -= 1;
                    const direction = strongForBracket(types[index]);
                    if (direction == .on) continue;
                    pair_direction = direction;
                    break;
                }
                if (pair_direction == embedding or pair_direction == .on) {
                    pair_direction = embedding;
                }
            }
            types[pair.open] = pair_direction;
            types[pair.close] = pair_direction;
            applyFollowingNsm(
                types,
                self.initial_types.items,
                self.indices.items,
                pair.open + 1,
                pair_direction,
            );
            applyFollowingNsm(
                types,
                self.initial_types.items,
                self.indices.items,
                pair.close + 1,
                pair_direction,
            );
        }
    }
};

fn resolveFirstStrongIsolates(types: []Class) void {
    for (types, 0..) |*value, index| {
        if (value.* != .fsi) continue;
        value.* = if (firstStrongUntilPdi(types[index + 1 ..]) == 1)
            .rli
        else
            .lri;
    }
}

fn firstStrongUntilPdi(types: []const Class) u8 {
    var isolate_depth: usize = 0;
    for (types) |value| {
        switch (value) {
            .lri, .rli, .fsi => isolate_depth += 1,
            .pdi => {
                if (isolate_depth == 0) return 0;
                isolate_depth -= 1;
            },
            .l => if (isolate_depth == 0) return 0,
            .r, .al => if (isolate_depth == 0) return 1,
            else => {},
        }
    }
    return 0;
}

fn defaultLevel(types: []const Class) u8 {
    var isolate_depth: usize = 0;
    for (types) |value| {
        switch (value) {
            .lri, .rli, .fsi => isolate_depth += 1,
            .pdi => if (isolate_depth != 0) {
                isolate_depth -= 1;
            },
            .l => if (isolate_depth == 0) return 0,
            .r, .al => if (isolate_depth == 0) return 1,
            else => {},
        }
    }
    return 0;
}

fn isPureLtr(types: []const Class, base_level: u8) bool {
    if (base_level != 0) return false;
    for (types) |value| {
        switch (value) {
            .r,
            .al,
            .an,
            .rle,
            .rlo,
            .rli,
            .lre,
            .lro,
            .lri,
            .fsi,
            .pdf,
            .pdi,
            .bn,
            => return false,
            else => {},
        }
    }
    return true;
}

fn resolveExplicit(types: []Class, levels: []u8, base_level: u8) void {
    var stack: [max_explicit_level + 1]StackEntry = undefined;
    var depth: usize = 1;
    stack[0] = .{ .level = base_level, .override = .neutral, .isolate = false };
    var overflow_isolates: usize = 0;
    var overflow_embeddings: usize = 0;
    var valid_isolates: usize = 0;

    for (types, 0..) |*value, index| {
        const original = value.*;
        switch (original) {
            .rle, .lre, .rlo, .lro, .rli, .lri => {
                const current = stack[depth - 1];
                levels[index] = current.level;
                const isolate = isIsolateInitiator(original);
                if (isolate) applyOverride(value, current.override);
                const rtl = original == .rle or original == .rlo or original == .rli;
                const new_level = if (rtl)
                    nextOdd(current.level)
                else
                    nextEven(current.level);
                if (new_level <= max_explicit_level and
                    overflow_isolates == 0 and overflow_embeddings == 0)
                {
                    if (isolate) valid_isolates += 1;
                    stack[depth] = .{
                        .level = new_level,
                        .override = switch (original) {
                            .lro => .ltr,
                            .rlo => .rtl,
                            else => .neutral,
                        },
                        .isolate = isolate,
                    };
                    depth += 1;
                } else if (isolate) {
                    overflow_isolates += 1;
                } else if (overflow_isolates == 0) {
                    overflow_embeddings += 1;
                }
            },
            .pdi => {
                if (overflow_isolates != 0) {
                    overflow_isolates -= 1;
                } else if (valid_isolates != 0) {
                    overflow_embeddings = 0;
                    while (depth > 1 and !stack[depth - 1].isolate) {
                        depth -= 1;
                    }
                    if (depth > 1) depth -= 1;
                    valid_isolates -= 1;
                }
                levels[index] = stack[depth - 1].level;
                applyOverride(value, stack[depth - 1].override);
            },
            .pdf => {
                levels[index] = stack[depth - 1].level;
                if (overflow_isolates != 0) {
                    // PDF inside an overflow isolate has no effect.
                } else if (overflow_embeddings != 0) {
                    overflow_embeddings -= 1;
                } else if (!stack[depth - 1].isolate and depth >= 2) {
                    depth -= 1;
                }
            },
            .b => {
                depth = 1;
                overflow_isolates = 0;
                overflow_embeddings = 0;
                valid_isolates = 0;
                levels[index] = base_level;
            },
            .bn => {},
            else => {
                levels[index] = stack[depth - 1].level;
                applyOverride(value, stack[depth - 1].override);
            },
        }
    }
}

fn resolveWeak(types: []Class, sos: Class, eos: Class) void {
    var previous = sos;
    var previous_strong = sos;
    for (types, 0..) |*value, index| {
        var current = value.*;
        if (current == .nsm) {
            current = switch (previous) {
                .lri, .rli, .fsi, .pdi => .on,
                else => previous,
            };
            value.* = current;
        } else {
            if (isIsolateFormatting(current)) {
                previous = .on;
                continue;
            }
            if (current == .en and previous_strong == .al) {
                current = .an;
                value.* = current;
            } else if (isStrongInitial(current)) {
                previous_strong = current;
                if (current == .al) {
                    current = .r;
                    value.* = current;
                }
            } else if ((current == .es or current == .cs) and
                index + 1 < types.len)
            {
                var next = types[index + 1];
                if (next == .en and previous_strong == .al) next = .an;
                if (previous == .en and next == .en) {
                    current = .en;
                    value.* = current;
                } else if (current == .cs and previous == .an and next == .an) {
                    current = .an;
                    value.* = current;
                }
            }
            previous = current;
        }
    }

    var cursor: usize = 0;
    while (cursor < types.len) {
        if (types[cursor] != .et) {
            cursor += 1;
            continue;
        }
        const start = cursor;
        while (cursor < types.len and types[cursor] == .et) : (cursor += 1) {}
        const before = if (start == 0) sos else types[start - 1];
        const after = if (cursor == types.len) eos else types[cursor];
        if (before == .en or after == .en) @memset(types[start..cursor], .en);
    }

    previous_strong = sos;
    for (types) |*value| {
        switch (value.*) {
            .es, .et, .cs => value.* = .on,
            .en => {
                if (previous_strong == .l) value.* = .l;
            },
            .l, .r => previous_strong = value.*,
            else => {},
        }
    }
}

fn resolveImplicit(
    types: []const Class,
    indices: []const usize,
    levels: []u8,
    sequence_level: u8,
) void {
    for (types, indices) |value, index| {
        if (sequence_level & 1 == 0) {
            levels[index] = sequence_level + switch (value) {
                .r => @as(u8, 1),
                .l => @as(u8, 0),
                else => @as(u8, 2),
            };
        } else {
            levels[index] = sequence_level + if (value == .r) @as(u8, 0) else 1;
        }
    }
}

fn resetParagraphLevels(
    initial_types: []const Class,
    levels: []u8,
    base_level: u8,
) void {
    for (initial_types, 0..) |value, index| {
        if (value != .b and value != .s) continue;
        levels[index] = base_level;
        var previous = index;
        while (previous > 0) {
            previous -= 1;
            const candidate = initial_types[previous];
            if (isRemovedByX9(candidate)) continue;
            if (candidate == .ws or isIsolateInitiator(candidate) or
                candidate == .pdi)
            {
                levels[previous] = base_level;
                continue;
            }
            break;
        }
    }
    var index = initial_types.len;
    while (index > 0) {
        index -= 1;
        const value = initial_types[index];
        if (isRemovedByX9(value)) continue;
        if (value == .ws or isIsolateInitiator(value) or value == .pdi) {
            levels[index] = base_level;
            continue;
        }
        break;
    }
}

fn applyFollowingNsm(
    types: []Class,
    initial_types: []const Class,
    indices: []const usize,
    start: usize,
    direction: Class,
) void {
    var index = start;
    while (index < types.len and initial_types[indices[index]] == .nsm) : (index += 1) {
        types[index] = direction;
    }
}

fn bracketPairLessThan(_: void, lhs: BracketPair, rhs: BracketPair) bool {
    return lhs.open < rhs.open;
}

fn applyOverride(value: *Class, override: Override) void {
    value.* = switch (override) {
        .neutral => value.*,
        .ltr => .l,
        .rtl => .r,
    };
}

fn nextOdd(level: u8) u8 {
    return (level + 1) | 1;
}

fn nextEven(level: u8) u8 {
    return (level + 2) & ~@as(u8, 1);
}

fn typeFromLevel(level: u8) Class {
    return if (level & 1 == 0) .l else .r;
}

fn isRemovedByX9(value: Class) bool {
    return switch (value) {
        .rle, .lre, .rlo, .lro, .pdf, .bn => true,
        else => false,
    };
}

fn isIsolateInitiator(value: Class) bool {
    return value == .lri or value == .rli or value == .fsi;
}

fn isIsolateFormatting(value: Class) bool {
    return isIsolateInitiator(value) or value == .pdi;
}

fn isStrongInitial(value: Class) bool {
    return value == .l or value == .r or value == .al;
}

fn isNeutralOrIsolate(value: Class) bool {
    return switch (value) {
        .b, .s, .ws, .on, .lri, .rli, .fsi, .pdi => true,
        else => false,
    };
}

fn strongForNeutral(value: Class) Class {
    return switch (value) {
        .en, .an => .r,
        else => value,
    };
}

fn strongForBracket(value: Class) Class {
    return switch (value) {
        .en, .an, .al, .r => .r,
        .l => .l,
        else => .on,
    };
}

test {
    try @import("conformance_test.zig").run();
}
