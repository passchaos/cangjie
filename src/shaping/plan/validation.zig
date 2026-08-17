//! Validation shared by public shaping and paragraph request boundaries.

const std = @import("std");

const plan = @import("root.zig");
const unicode = @import("../../unicode.zig");

pub fn input(
    text: []const u8,
    font_size: f32,
    options: plan.ShapeOptions,
) !void {
    try utf8(text);
    try utf8(options.context_before);
    try utf8(options.context_after);
    try fontSize(font_size);
    try features(options.features);
    try variationCoords(options.normalized_variation_coords);
}

pub fn utf8(text: []const u8) !void {
    // Utf8Iterator assumes valid input. Reject malformed bytes before cache
    // keys are built or any caller-owned output buffer can be mutated.
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
}

pub fn fontSize(font_size: f32) !void {
    // Font size participates in scaling and cache identity. NaN, infinity, or
    // non-positive values would make downstream layout geometry ill-defined.
    if (!std.math.isFinite(font_size) or font_size <= 0) {
        return error.InvalidFontSize;
    }
}

pub fn features(overrides: []const unicode.FeatureOverride) !void {
    for (overrides, 0..) |feature, index| {
        if (!isOpenTypeTag(feature.tag)) return error.InvalidFeatureTag;
        for (overrides[0..index]) |previous| {
            if (previous.tag == feature.tag) {
                return error.DuplicateFeatureTag;
            }
        }
    }
}

pub fn variationCoords(coords: []const f32) !void {
    for (coords) |coord| {
        if (!std.math.isFinite(coord) or coord < -1 or coord > 1) {
            return error.BadSfnt;
        }
    }
}

fn isOpenTypeTag(tag_value: u32) bool {
    inline for (0..4) |shift_index| {
        const shift: u5 = @intCast((3 - shift_index) * 8);
        const byte: u8 = @intCast((tag_value >> shift) & 0xff);
        if (byte < 0x20 or byte > 0x7e) return false;
    }
    return true;
}
