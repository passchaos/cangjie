//! Decoration and superscript/subscript metrics independent of `Font` ownership.

const std = @import("std");

const bin = @import("../../binary.zig");
const sfnt = @import("../sfnt/root.zig");

pub const Error = sfnt.Error || error{EndOfStream} || error{InvalidMetrics};

pub const Source = enum {
    font,
    fallback,
};

pub const ScaledDecoration = struct {
    underline_position: f32,
    underline_thickness: f32,
    strikeout_position: f32,
    strikeout_thickness: f32,
};

pub const ScaledScript = struct {
    superscript_x_size: f32,
    superscript_y_size: f32,
    superscript_x_offset: f32,
    superscript_y_offset: f32,
    subscript_x_size: f32,
    subscript_y_size: f32,
    subscript_x_offset: f32,
    subscript_y_offset: f32,
};

pub const Script = struct {
    superscript_x_size: i16,
    superscript_y_size: i16,
    superscript_x_offset: i16,
    superscript_y_offset: i16,
    subscript_x_size: i16,
    subscript_y_size: i16,
    subscript_x_offset: i16,
    subscript_y_offset: i16,

    pub fn scale(
        self: Script,
        font_size: f32,
        units_per_em: u16,
    ) ScaledScript {
        const factor = scaleFactor(font_size, units_per_em);
        return .{
            .superscript_x_size = scaleI16(self.superscript_x_size, factor),
            .superscript_y_size = scaleI16(self.superscript_y_size, factor),
            .superscript_x_offset = scaleI16(
                self.superscript_x_offset,
                factor,
            ),
            .superscript_y_offset = scaleI16(
                self.superscript_y_offset,
                factor,
            ),
            .subscript_x_size = scaleI16(self.subscript_x_size, factor),
            .subscript_y_size = scaleI16(self.subscript_y_size, factor),
            .subscript_x_offset = scaleI16(
                self.subscript_x_offset,
                factor,
            ),
            .subscript_y_offset = scaleI16(
                self.subscript_y_offset,
                factor,
            ),
        };
    }
};

pub const Decoration = struct {
    underline_position: i16,
    underline_thickness: i16,
    strikeout_position: i16,
    strikeout_thickness: i16,
    underline_source: Source = .fallback,
    strikeout_source: Source = .fallback,

    pub fn scale(
        self: Decoration,
        font_size: f32,
        units_per_em: u16,
    ) ScaledDecoration {
        const factor = scaleFactor(font_size, units_per_em);
        return .{
            .underline_position = scaleI16(
                self.underline_position,
                factor,
            ),
            // At display sizes a thinner line disappears under grayscale
            // coverage, so both fallback and font-provided strokes retain the
            // existing half-pixel floor.
            .underline_thickness = @max(
                0.5,
                scaleI16(self.underline_thickness, factor),
            ),
            .strikeout_position = scaleI16(
                self.strikeout_position,
                factor,
            ),
            .strikeout_thickness = @max(
                0.5,
                scaleI16(self.strikeout_thickness, factor),
            ),
        };
    }
};

pub fn decoration(
    data: []const u8,
    post: ?sfnt.Record,
    os2: ?sfnt.Record,
    units_per_em: u16,
    ascender: i16,
    descender: i16,
) Error!Decoration {
    var metrics = fallbackDecoration(units_per_em, ascender, descender);
    if (post) |post_table| {
        const underline = try postDecoration(data, post_table);
        if (underline.thickness > 0) {
            metrics.underline_position = underline.position;
            metrics.underline_thickness = underline.thickness;
            metrics.underline_source = .font;
        }
    }
    if (os2) |os2_table| {
        const strikeout = try os2Strikeout(data, os2_table);
        if (strikeout.thickness > 0) {
            metrics.strikeout_position = strikeout.position;
            metrics.strikeout_thickness = strikeout.thickness;
            metrics.strikeout_source = .font;
        }
    }
    return metrics;
}

pub fn script(data: []const u8, os2: sfnt.Record) Error!Script {
    try sfnt.requireLength(os2, 26);
    const metrics: Script = .{
        .subscript_x_size = try bin.readI16At(data, os2.offset + 10),
        .subscript_y_size = try bin.readI16At(data, os2.offset + 12),
        .subscript_x_offset = try bin.readI16At(data, os2.offset + 14),
        .subscript_y_offset = try bin.readI16At(data, os2.offset + 16),
        .superscript_x_size = try bin.readI16At(data, os2.offset + 18),
        .superscript_y_size = try bin.readI16At(data, os2.offset + 20),
        .superscript_x_offset = try bin.readI16At(data, os2.offset + 22),
        .superscript_y_offset = try bin.readI16At(data, os2.offset + 24),
    };
    if (metrics.subscript_x_size <= 0 or
        metrics.subscript_y_size <= 0 or
        metrics.superscript_x_size <= 0 or
        metrics.superscript_y_size <= 0)
    {
        return error.InvalidMetrics;
    }
    return metrics;
}

const DecorationPair = struct {
    position: i16,
    thickness: i16,
};

fn postDecoration(
    data: []const u8,
    post: sfnt.Record,
) Error!DecorationPair {
    try sfnt.requireLength(post, 12);
    return .{
        .position = try bin.readI16At(data, post.offset + 8),
        .thickness = try bin.readI16At(data, post.offset + 10),
    };
}

fn os2Strikeout(
    data: []const u8,
    os2: sfnt.Record,
) Error!DecorationPair {
    try sfnt.requireLength(os2, 30);
    return .{
        .thickness = try bin.readI16At(data, os2.offset + 26),
        .position = try bin.readI16At(data, os2.offset + 28),
    };
}

fn fallbackDecoration(
    units_per_em: u16,
    ascender: i16,
    descender: i16,
) Decoration {
    const units = @max(@as(i32, @intCast(units_per_em)), 1);
    const thickness = @max(1, @divTrunc(units, 16));
    const underline_position =
        -@as(i32, @max(thickness, @divTrunc(units, 9)));
    const asc = if (ascender > 0)
        @as(i32, ascender)
    else
        @divTrunc(units * 4, 5);
    const desc = if (descender < 0)
        -@as(i32, descender)
    else
        @divTrunc(units, 5);
    const strikeout_position = @max(thickness, @divTrunc(asc * 3, 10));
    return .{
        .underline_position = clampI16(underline_position),
        .underline_thickness = clampI16(thickness),
        .strikeout_position = clampI16(
            @min(strikeout_position, asc + desc),
        ),
        .strikeout_thickness = clampI16(thickness),
    };
}

fn scaleFactor(font_size: f32, units_per_em: u16) f32 {
    const units = @max(@as(f32, @floatFromInt(units_per_em)), 1.0);
    return font_size / units;
}

fn scaleI16(value: i16, factor: f32) f32 {
    return @as(f32, @floatFromInt(value)) * factor;
}

fn clampI16(value: i32) i16 {
    if (value < std.math.minInt(i16)) return std.math.minInt(i16);
    if (value > std.math.maxInt(i16)) return std.math.maxInt(i16);
    return @intCast(value);
}
