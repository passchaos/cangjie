//! Concrete TrueType size-program inputs and retained state.
//!
//! Coordinates consumed by the interpreter use signed 26.6 fixed point
//! integers, matching FreeType and the OpenType instruction contract. The
//! source borrows validated font tables; `Instance` copies mutable CVT,
//! storage, definitions, and retained graphics state.

const std = @import("std");

pub const Error = error{
    BadSfnt,
    InvalidHintPpem,
    InvalidHintScale,
    HintExecutionLimitExceeded,
    HintStackOverflow,
    HintStackUnderflow,
    HintCallStackOverflow,
    InvalidHintDefinition,
    TooManyHintDefinitions,
    InvalidHintJump,
    InvalidHintStorage,
    InvalidHintCvt,
    InvalidHintOperand,
    StaleHintingInstance,
    UnsupportedHintGlyph,
    DivideByZero,
    UnsupportedHintInstruction,
} || std.mem.Allocator.Error;

pub const Program = enum(u2) {
    font,
    control_value,
    glyph,
};

pub const Limits = struct {
    max_storage: usize,
    max_function_defs: usize,
    max_instruction_defs: usize,
    max_stack_elements: usize,
    max_twilight_points: usize,
};

pub const Source = struct {
    /// Optional owning-face identity used to reject cross-face transactions.
    /// Standalone VM tests use zero.
    face_identity: usize = 0,
    units_per_em: u16,
    font_program: []const u8,
    control_value_program: []const u8,
    glyph_program: []const u8 = &.{},
    /// Big-endian signed FUnit values borrowed directly from `cvt `.
    control_value_data: []const u8,
    limits: Limits,
};

pub const Target = enum {
    /// Standard anti-aliased grayscale target.
    normal,
    /// Lighter anti-aliased hinting.
    light,
    /// Horizontal RGB/BGR subpixel outline target.
    lcd,
    /// Vertical RGB/BGR subpixel outline target.
    vertical_lcd,
    /// Strong full-pixel monochrome target.
    mono,

    pub fn isSmooth(self: Target) bool {
        return self != .mono;
    }

    pub fn isVerticalLcd(self: Target) bool {
        return self == .vertical_lcd;
    }

    pub fn isGrayscaleClearType(self: Target) bool {
        return self == .normal or self == .light;
    }
};

pub const RoundMode = enum {
    half_grid,
    grid,
    double_grid,
    down_to_grid,
    up_to_grid,
    off,
    super,
    super_45,
};

/// Graphics-state fields that survive `prep` and seed every glyph program.
pub const RetainedGraphicsState = struct {
    auto_flip: bool = true,
    control_value_cutin: i32 = 68,
    delta_base: i32 = 9,
    delta_shift: i32 = 3,
    instruct_control: u8 = 0,
    min_distance: i32 = 64,
    scan_control: bool = false,
    scan_type: i32 = 0,
    single_width_cutin: i32 = 0,
    single_width: i32 = 0,
    scale_16_16: i32 = 0,
    ppem: u16 = 0,
    target: Target = .normal,
};

pub fn scaleFUnits(value: i32, scale_16_16: i32) i32 {
    const product = @as(i64, value) * @as(i64, scale_16_16);
    // OpenType/FreeType fixed multiplication rounds by adding 0.5 ulp before
    // shifting. Apply the sign after magnitude rounding so negative values use
    // the same nearest convention.
    const magnitude: u64 = @intCast(if (product < 0) -product else product);
    const rounded: i64 = @intCast((magnitude + 0x8000) >> 16);
    return clampI64ToI32(if (product < 0) -rounded else rounded);
}

pub fn mulDiv(a: i32, b: i32, c: i32) Error!i32 {
    if (c == 0) return error.DivideByZero;
    const product = @as(i64, a) * @as(i64, b);
    return clampI64ToI32(@divTrunc(product, @as(i64, c)));
}

pub fn floor26Dot6(value: i32) i32 {
    return value & ~@as(i32, 63);
}

pub fn ceil26Dot6(value: i32) i32 {
    return (value +| 63) & ~@as(i32, 63);
}

fn clampI64ToI32(value: i64) i32 {
    if (value <= std.math.minInt(i32)) return std.math.minInt(i32);
    if (value >= std.math.maxInt(i32)) return std.math.maxInt(i32);
    return @intCast(value);
}

test "26.6 scaling follows signed nearest fixed multiplication" {
    try std.testing.expectEqual(@as(i32, 640), scaleFUnits(1000, 41943));
    try std.testing.expectEqual(@as(i32, -640), scaleFUnits(-1000, 41943));
    try std.testing.expectEqual(@as(i32, 64), floor26Dot6(127));
    try std.testing.expectEqual(@as(i32, -128), floor26Dot6(-65));
    try std.testing.expectEqual(@as(i32, 128), ceil26Dot6(65));
}
