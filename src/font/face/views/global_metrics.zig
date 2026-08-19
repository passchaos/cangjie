//! Scaled global font metrics matching the high-level Skrifa contract.

const std = @import("std");
const font_mod = @import("../../../font.zig");

pub const Bounds = struct { x_min: f32, y_min: f32, x_max: f32, y_max: f32 };
pub const Decoration = struct { offset: f32, thickness: f32 };

pub const Metrics = struct {
    units_per_em: u16,
    glyph_count: u16,
    is_monospace: bool,
    italic_angle: f32,
    ascent: f32,
    descent: f32,
    leading: f32,
    cap_height: ?f32,
    x_height: ?f32,
    average_width: ?f32,
    max_width: ?f32,
    underline: ?Decoration,
    strikeout: ?Decoration,
    bounds: Bounds,
};

pub fn read(font: *const font_mod.Font, size: ?f32) font_mod.FontError!Metrics {
    const head = try font.headInfo();
    const scale = if (size) |value| blk: {
        if (!std.math.isFinite(value) or value < 0) return error.InvalidMetrics;
        break :blk value / @as(f32, @floatFromInt(head.units_per_em));
    } else 1.0;
    const hhea = try font.horizontalHeaderInfo();
    const os2 = try font.os2Info();
    const post = try font.postInfo();
    var ascent = hhea.ascender;
    var descent = hhea.descender;
    var leading = hhea.line_gap;
    if (os2) |value| {
        if ((value.selection & 0x0080) != 0) {
            ascent = value.typo_ascender;
            descent = value.typo_descender;
            leading = value.typo_line_gap;
        } else if (ascent == 0 and descent == 0) {
            if (value.typo_ascender != 0 or value.typo_descender != 0) {
                ascent = value.typo_ascender;
                descent = value.typo_descender;
                leading = value.typo_line_gap;
            } else {
                ascent = clampU16(value.win_ascent);
                descent = -clampU16(value.win_descent);
                leading = 0;
            }
        }
    }
    const decorations = try font.decorationMetrics();
    return .{
        .units_per_em = head.units_per_em,
        .glyph_count = font.glyph_count,
        .is_monospace = if (post) |value| value.is_fixed_pitch else false,
        .italic_angle = if (post) |value| value.italic_angle else 0,
        .ascent = scaled(ascent, scale),
        .descent = scaled(descent, scale),
        .leading = scaled(leading, scale),
        .cap_height = optionalScaled(os2, true, scale),
        .x_height = optionalScaled(os2, false, scale),
        .average_width = if (os2) |value| scaled(value.x_avg_char_width, scale) else null,
        .max_width = @as(f32, @floatFromInt(hhea.advance_max)) * scale,
        .underline = .{ .offset = scaled(decorations.underline_position, scale), .thickness = scaled(decorations.underline_thickness, scale) },
        .strikeout = .{ .offset = scaled(decorations.strikeout_position, scale), .thickness = scaled(decorations.strikeout_thickness, scale) },
        .bounds = .{ .x_min = scaled(head.bounds.x_min, scale), .y_min = scaled(head.bounds.y_min, scale), .x_max = scaled(head.bounds.x_max, scale), .y_max = scaled(head.bounds.y_max, scale) },
    };
}

fn optionalScaled(os2: ?font_mod.Os2Info, cap: bool, scale: f32) ?f32 {
    const value = os2 orelse return null;
    const raw = if (cap) value.cap_height else value.x_height;
    return if (raw) |metric| scaled(metric, scale) else null;
}
fn scaled(value: i16, scale: f32) f32 {
    return @as(f32, @floatFromInt(value)) * scale;
}
fn clampU16(value: u16) i16 {
    return @intCast(@min(value, @as(u16, std.math.maxInt(i16))));
}
