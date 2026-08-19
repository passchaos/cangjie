//! Inline-axis alignment shared by vertical column construction and refitting.

const std = @import("std");

const TextAlign = @import("../types/paragraph.zig").TextAlign;
const TextDirection = @import("../../shaping/pipeline/types.zig").TextDirection;

pub fn origin(
    max_inline_size: f32,
    indent: f32,
    inline_size: f32,
    alignment: TextAlign,
    direction: TextDirection,
) f32 {
    if (max_inline_size <= 0 or !std.math.isFinite(max_inline_size)) {
        return if (direction == .ltr) indent else 0;
    }
    const available = @max(0, max_inline_size - indent);
    return originInRegion(
        if (direction == .ltr) indent else 0,
        available,
        inline_size,
        alignment,
        direction,
    );
}

pub fn originInRegion(
    inline_start: f32,
    available: f32,
    inline_size: f32,
    alignment: TextAlign,
    direction: TextDirection,
) f32 {
    if (!std.math.isFinite(available)) return inline_start;
    const slack = @max(0, available - inline_size);
    return inline_start + switch (alignment) {
        .start, .justify => if (direction == .ltr) 0 else slack,
        .center => slack / 2,
        .end => if (direction == .ltr) slack else 0,
        .left, .right => unreachable,
    };
}
