//! Owning TrueType hinting state for one PPEM and rendering target.

const std = @import("std");

const glyph_executor = @import("glyph/executor.zig");
const outline = @import("outline.zig");
const program = @import("program.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

pub const Instance = struct {
    allocator: std.mem.Allocator,
    source: types.Source,
    ppem: u16,
    target: types.Target,
    scale_16_16: i32,
    functions: []program.Definition,
    instructions: []program.Definition,
    cvt: []i32,
    storage: []i32,
    stack: []i32,
    graphics: types.RetainedGraphicsState,
    twilight_points: []outline.Point,
    twilight_original: []outline.Point,
    twilight_unscaled: []outline.Point,
    twilight_flags: []outline.PointFlag,

    /// Construct and execute `fpgm`, then reset size graphics/storage and run
    /// `prep`, following the FreeType size lifecycle.
    pub fn init(
        allocator: std.mem.Allocator,
        source: types.Source,
        ppem: u16,
        target: types.Target,
    ) types.Error!Instance {
        if (ppem == 0) return error.InvalidHintPpem;
        if (source.units_per_em < 16 or source.units_per_em > 16_384) {
            return error.InvalidHintScale;
        }
        if ((source.control_value_data.len & 1) != 0) {
            return error.BadSfnt;
        }
        const scale_16_16 = try scaleForPpem(ppem, source.units_per_em);
        const functions = try allocator.alloc(
            program.Definition,
            source.limits.max_function_defs,
        );
        errdefer allocator.free(functions);
        const instructions = try allocator.alloc(
            program.Definition,
            source.limits.max_instruction_defs,
        );
        errdefer allocator.free(instructions);
        const cvt = try allocator.alloc(
            i32,
            source.control_value_data.len / 2,
        );
        errdefer allocator.free(cvt);
        const storage = try allocator.alloc(
            i32,
            source.limits.max_storage,
        );
        errdefer allocator.free(storage);
        const stack = try allocator.alloc(
            i32,
            try compatibleStackSize(source.limits.max_stack_elements),
        );
        errdefer allocator.free(stack);
        // FreeType reserves four extra phantom-compatible entries in the
        // twilight zone.  Real glyph programs in the field rely on that
        // historical allowance despite maxTwilightPoints describing fewer.
        const twilight_point_count = std.math.add(
            usize,
            source.limits.max_twilight_points,
            4,
        ) catch return error.InvalidHintScale;
        const twilight_points = try allocator.alloc(
            outline.Point,
            twilight_point_count,
        );
        errdefer allocator.free(twilight_points);
        const twilight_original = try allocator.alloc(
            outline.Point,
            twilight_point_count,
        );
        errdefer allocator.free(twilight_original);
        const twilight_unscaled = try allocator.alloc(
            outline.Point,
            twilight_point_count,
        );
        errdefer allocator.free(twilight_unscaled);
        const twilight_flags = try allocator.alloc(
            outline.PointFlag,
            twilight_point_count,
        );
        errdefer allocator.free(twilight_flags);

        @memset(functions, .{});
        @memset(instructions, .{});
        @memset(storage, 0);
        @memset(twilight_points, .{ .x = 0, .y = 0 });
        @memset(twilight_original, .{ .x = 0, .y = 0 });
        @memset(twilight_unscaled, .{ .x = 0, .y = 0 });
        @memset(twilight_flags, .{});
        loadScaledCvt(cvt, source.control_value_data, scale_16_16);

        var result = Instance{
            .allocator = allocator,
            .source = source,
            .ppem = ppem,
            .target = target,
            .scale_16_16 = scale_16_16,
            .functions = functions,
            .instructions = instructions,
            .cvt = cvt,
            .storage = storage,
            .stack = stack,
            .graphics = defaultGraphics(scale_16_16, ppem, target),
            .twilight_points = twilight_points,
            .twilight_original = twilight_original,
            .twilight_unscaled = twilight_unscaled,
            .twilight_flags = twilight_flags,
        };
        var interpreter = result.vm();
        interpreter.definitions.clear();
        try interpreter.run(.font);

        // FreeType rebuilds the size CVT from font data, then resets graphics,
        // twilight, and storage before prep. Font-program writes therefore do
        // not leak into the retained size state.
        loadScaledCvt(result.cvt, source.control_value_data, scale_16_16);
        result.graphics = defaultGraphics(scale_16_16, ppem, target);
        @memset(result.storage, 0);
        interpreter = result.vm();
        try interpreter.run(.control_value);
        return result;
    }

    pub fn deinit(self: *Instance) void {
        self.allocator.free(self.twilight_flags);
        self.allocator.free(self.twilight_unscaled);
        self.allocator.free(self.twilight_original);
        self.allocator.free(self.twilight_points);
        self.allocator.free(self.stack);
        self.allocator.free(self.storage);
        self.allocator.free(self.cvt);
        self.allocator.free(self.instructions);
        self.allocator.free(self.functions);
        self.* = undefined;
    }

    pub fn isEnabled(self: *const Instance) bool {
        return (self.graphics.instruct_control & 1) == 0;
    }

    pub fn controlValues(self: *const Instance) []const i32 {
        return self.cvt;
    }

    pub fn storageValues(self: *const Instance) []const i32 {
        return self.storage;
    }

    pub fn graphicsState(
        self: *const Instance,
    ) types.RetainedGraphicsState {
        return self.graphics;
    }

    /// Execute the transaction's glyph program and atomically commit every
    /// mutable VM surface.  On any error, points, flags, CVT, storage, retained
    /// graphics state, and the persistent twilight zone remain unchanged.
    pub fn executeGlyph(
        self: *Instance,
        transaction: *outline.Transaction,
    ) types.Error!void {
        return glyph_executor.execute(
            self.allocator,
            .{
                .source = self.source,
                .definitions = .{
                    .functions = self.functions,
                    .instructions = self.instructions,
                },
                .stack = self.stack,
                .cvt = self.cvt,
                .storage = self.storage,
                .graphics = self.graphics,
                .twilight = .{
                    .points = self.twilight_points,
                    .original = self.twilight_original,
                    .unscaled = self.twilight_unscaled,
                    .flags = self.twilight_flags,
                },
            },
            transaction,
        );
    }

    fn vm(self: *Instance) vm_mod.Vm {
        return vm_mod.Vm.init(
            self.source,
            .{
                .functions = self.functions,
                .instructions = self.instructions,
            },
            self.stack,
            self.cvt,
            self.storage,
            &self.graphics,
        );
    }
};

fn scaleForPpem(ppem: u16, units_per_em: u16) types.Error!i32 {
    const numerator =
        @as(u64, ppem) * 64 * 65_536 + units_per_em / 2;
    const value = numerator / units_per_em;
    if (value == 0 or value > std.math.maxInt(i32)) {
        return error.InvalidHintScale;
    }
    return @intCast(value);
}

/// FreeType-compatible bounded allowance for deployed fonts that under-report
/// `maxStackElements` (notably some programs that NPUSH 255 values while
/// declaring 153). This remains a fixed allocation derived from maxp.
fn compatibleStackSize(declared: usize) types.Error!usize {
    const margin = @max(declared / 2, 128);
    return std.math.add(usize, declared, margin) catch
        error.InvalidHintScale;
}

fn loadScaledCvt(
    output: []i32,
    data: []const u8,
    scale_16_16: i32,
) void {
    std.debug.assert(data.len == output.len * 2);
    var offset: usize = 0;
    for (output) |*value| {
        const base = std.mem.readInt(
            i16,
            data[offset..][0..2],
            .big,
        );
        value.* = types.scaleFUnits(base, scale_16_16);
        offset += 2;
    }
}

fn defaultGraphics(
    scale_16_16: i32,
    ppem: u16,
    target: types.Target,
) types.RetainedGraphicsState {
    return .{
        .scale_16_16 = scale_16_16,
        .ppem = ppem,
        .target = target,
    };
}

test "instance scales CVT and retains prep writes" {
    const source = types.Source{
        .units_per_em = 1000,
        .font_program = &.{},
        // WCVTP storage: cvt[0] = 96; WS storage[0] = 7.
        .control_value_program = &.{ 0xb1, 0, 96, 0x44, 0xb1, 0, 7, 0x42 },
        .control_value_data = &.{ 0x00, 0x0a },
        .limits = .{
            .max_storage = 1,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = 8,
            .max_twilight_points = 0,
        },
    };
    var instance = try Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    try std.testing.expectEqual(@as(i32, 96), instance.controlValues()[0]);
    try std.testing.expectEqual(@as(i32, 7), instance.storageValues()[0]);
}

test "instance executes prep control flow and instruction control" {
    const source = types.Source{
        .units_per_em = 1000,
        .font_program = &.{},
        // MPPEM == 16 => storage[0] = 9, then disable glyph instructions.
        .control_value_program = &.{
            0x4b, 0xb0, 16, 0x54, 0x58,
            0xb1, 0,    9,  0x42, 0x59,
            0xb1, 1,    1,  0x8e,
        },
        .control_value_data = &.{},
        .limits = .{
            .max_storage = 1,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = 8,
            .max_twilight_points = 0,
        },
    };
    var instance = try Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    try std.testing.expectEqual(@as(i32, 9), instance.storageValues()[0]);
    try std.testing.expect(!instance.isEnabled());
}

test "font-program CVT writes reset before prep" {
    const source = types.Source{
        .units_per_em = 1000,
        .font_program = &.{ 0xb1, 0, 99, 0x44 },
        .control_value_program = &.{},
        .control_value_data = &.{ 0x00, 0x0a },
        .limits = .{
            .max_storage = 0,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = 4,
            .max_twilight_points = 0,
        },
    };
    var instance = try Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    // 10 FUnits at 16 PPEM / 1000 UPEM rounds to 10 in 26.6. The temporary
    // fpgm value 99 must not survive the size CVT rebuild.
    try std.testing.expectEqual(@as(i32, 10), instance.controlValues()[0]);
}

test "instance reports point-only and bounded VM failures" {
    const Base = struct {
        fn source(prep: []const u8, stack: usize) types.Source {
            return .{
                .units_per_em = 1000,
                .font_program = &.{},
                .control_value_program = prep,
                .control_value_data = &.{},
                .limits = .{
                    .max_storage = 0,
                    .max_function_defs = 0,
                    .max_instruction_defs = 0,
                    .max_stack_elements = stack,
                    .max_twilight_points = 0,
                },
            };
        }
    };
    try std.testing.expectError(
        error.UnsupportedHintInstruction,
        Instance.init(
            std.testing.allocator,
            Base.source(&.{0x2e}, 1), // MDAP[0] needs a glyph point zone.
            16,
            .normal,
        ),
    );
    var oversized_push: [132]u8 = .{0} ** 132;
    oversized_push[0] = 0x40; // NPUSHB[130].
    oversized_push[1] = 130;
    try std.testing.expectError(
        error.HintStackOverflow,
        Instance.init(
            std.testing.allocator,
            Base.source(&oversized_push, 1),
            16,
            .normal,
        ),
    );
    try std.testing.expectError(
        error.InvalidHintJump,
        Instance.init(
            std.testing.allocator,
            Base.source(&.{ 0xb0, 0, 0x1c }, 2),
            16,
            .normal,
        ),
    );
}

test "glyph execution moves points and commits VM working state" {
    const source = glyphTestSource(0x1234);
    var instance = try Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    const instructions = &.{
        0xb0, 0, 0x2f, // MDAP[round] point 0: 35 -> 64.
        0xb1, 1, 0, 0x3f, // MIAP[round] point 1 to CVT[0]: 96 -> 64.
        0xb0, 2, 0xc4, // MDRP[round] point 2 relative to point 1: -> 128.
        0xb1, 64, 2, 0x38, // SHPIX point 2 by +1px: -> 192.
        0xb0, 2, 0x46, // GC[current] point 2.
        0xb0, 0, 0x23, 0x42, // storage[0] = projected coordinate.
    };
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        instructions,
    );
    defer transaction.deinit();

    try instance.executeGlyph(&transaction);
    try std.testing.expectEqual(@as(i32, 64), transaction.points[0].x);
    try std.testing.expectEqual(@as(i32, 64), transaction.points[1].x);
    try std.testing.expectEqual(@as(i32, 192), transaction.points[2].x);
    try std.testing.expect(transaction.flags[0].touched_x);
    try std.testing.expect(transaction.flags[1].touched_x);
    try std.testing.expect(transaction.flags[2].touched_x);
    try std.testing.expectEqual(
        @as(i32, 192),
        instance.storageValues()[0],
    );
}

test "failed glyph execution rolls back points CVT and storage" {
    const source = glyphTestSource(0x5678);
    var instance = try Instance.init(
        std.testing.allocator,
        source,
        16,
        .normal,
    );
    defer instance.deinit();
    const instructions = &.{
        0xb1, 0, 77, 0x44, // Tentative CVT write.
        0xb1, 0, 9, 0x42, // Tentative storage write.
        0xb0, 99, 0x45, // Invalid CVT read forces rollback.
    };
    var transaction = try glyphTestTransaction(
        std.testing.allocator,
        source.face_identity,
        instructions,
    );
    defer transaction.deinit();
    const before_points = try std.testing.allocator.dupe(
        outline.Point,
        transaction.points,
    );
    defer std.testing.allocator.free(before_points);
    const before_flags = try std.testing.allocator.dupe(
        outline.PointFlag,
        transaction.flags,
    );
    defer std.testing.allocator.free(before_flags);
    const before_cvt = instance.controlValues()[0];
    const before_storage = instance.storageValues()[0];

    try std.testing.expectError(
        error.InvalidHintCvt,
        instance.executeGlyph(&transaction),
    );
    try std.testing.expectEqualSlices(
        outline.Point,
        before_points,
        transaction.points,
    );
    try std.testing.expectEqualSlices(
        outline.PointFlag,
        before_flags,
        transaction.flags,
    );
    try std.testing.expectEqual(before_cvt, instance.controlValues()[0]);
    try std.testing.expectEqual(
        before_storage,
        instance.storageValues()[0],
    );
}

fn glyphTestSource(face_identity: usize) types.Source {
    return .{
        .face_identity = face_identity,
        .units_per_em = 1024,
        .font_program = &.{},
        .control_value_program = &.{},
        .control_value_data = &.{ 0, 64 },
        .limits = .{
            .max_storage = 1,
            .max_function_defs = 0,
            .max_instruction_defs = 0,
            .max_stack_elements = 16,
            .max_twilight_points = 2,
        },
    };
}

fn glyphTestTransaction(
    allocator: std.mem.Allocator,
    face_identity: usize,
    instructions: []const u8,
) !outline.Transaction {
    const source_points = [_]outline.Point{
        .{ .x = 35, .y = 0 },
        .{ .x = 96, .y = 0 },
        .{ .x = 150, .y = 0 },
        .{ .x = 0, .y = 0 },
        .{ .x = 640, .y = 0 },
        .{ .x = 0, .y = 640 },
        .{ .x = 0, .y = -640 },
    };
    const points = try allocator.dupe(outline.Point, &source_points);
    errdefer allocator.free(points);
    const original = try allocator.dupe(outline.Point, &source_points);
    errdefer allocator.free(original);
    const unscaled = try allocator.dupe(outline.Point, &source_points);
    errdefer allocator.free(unscaled);
    const flags = try allocator.alloc(outline.PointFlag, source_points.len);
    errdefer allocator.free(flags);
    @memset(flags, .{ .on_curve = true });
    const contours = try allocator.dupe(u16, &.{2});
    errdefer allocator.free(contours);
    return .{
        .allocator = allocator,
        .face_identity = face_identity,
        .target = .normal,
        .glyph_id = 1,
        .real_point_count = 3,
        .points = points,
        .original = original,
        .unscaled = unscaled,
        .flags = flags,
        .contours = contours,
        .instructions = instructions,
        .scale_16_16 = 0x10000,
    };
}
