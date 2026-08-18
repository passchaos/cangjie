//! Inline-axis alignment shared by vertical column construction and refitting.

const std = @import("std");

const TextAlign = @import("../types/paragraph.zig").TextAlign;

pub fn origin(
    max_inline_size: f32,
    indent: f32,
    inline_size: f32,
    alignment: TextAlign,
) f32 {
    if (max_inline_size <= 0 or !std.math.isFinite(max_inline_size)) {
        return indent;
    }
    const available = @max(0, max_inline_size - indent);
    const slack = @max(0, available - inline_size);
    return indent + switch (alignment) {
        .start => 0,
        .center => slack / 2,
        .end => slack,
        .left, .right, .justify => unreachable,
    };
}
