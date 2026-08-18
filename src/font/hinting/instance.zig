//! Owning TrueType hinting state for one PPEM and rendering target.

const std = @import("std");

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
    twilight_point_count: usize,

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

        @memset(functions, .{});
        @memset(instructions, .{});
        @memset(storage, 0);
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
            .twilight_point_count = source.limits.max_twilight_points,
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
