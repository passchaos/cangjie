//! High-level face attributes used for classification and font matching.

const font_mod = @import("../../font.zig");

/// Relative visual width of a face. Values match the CSS/OpenType `wdth`
/// convention: `1.0` is normal and `0.5` is half width.
pub const Stretch = struct {
    value: f32 = 1.0,

    pub const ultra_condensed: Stretch = .{ .value = 0.5 };
    pub const extra_condensed: Stretch = .{ .value = 0.625 };
    pub const condensed: Stretch = .{ .value = 0.75 };
    pub const semi_condensed: Stretch = .{ .value = 0.875 };
    pub const normal: Stretch = .{ .value = 1.0 };
    pub const semi_expanded: Stretch = .{ .value = 1.125 };
    pub const expanded: Stretch = .{ .value = 1.25 };
    pub const extra_expanded: Stretch = .{ .value = 1.5 };
    pub const ultra_expanded: Stretch = .{ .value = 2.0 };

    pub fn fromWidthClass(width_class: u16) Stretch {
        return switch (width_class) {
            0...1 => .ultra_condensed,
            2 => .extra_condensed,
            3 => .condensed,
            4 => .semi_condensed,
            5 => .normal,
            6 => .semi_expanded,
            7 => .expanded,
            8 => .extra_expanded,
            else => .ultra_expanded,
        };
    }

    pub fn ratio(self: Stretch) f32 {
        return self.value;
    }

    pub fn percentage(self: Stretch) f32 {
        return self.value * 100.0;
    }
};

/// Upright, structurally italic, or mechanically oblique face style.
pub const Style = union(enum) {
    normal,
    italic,
    /// Counter-clockwise degrees from vertical when `post` supplies an angle.
    oblique: ?f32,
};

/// OpenType weight value, normally in the inclusive 1..1000 range.
pub const Weight = struct {
    value: f32 = 400.0,

    pub const thin: Weight = .{ .value = 100.0 };
    pub const extra_light: Weight = .{ .value = 200.0 };
    pub const light: Weight = .{ .value = 300.0 };
    pub const semi_light: Weight = .{ .value = 350.0 };
    pub const normal: Weight = .{ .value = 400.0 };
    pub const medium: Weight = .{ .value = 500.0 };
    pub const semi_bold: Weight = .{ .value = 600.0 };
    pub const bold: Weight = .{ .value = 700.0 };
    pub const extra_bold: Weight = .{ .value = 800.0 };
    pub const black: Weight = .{ .value = 900.0 };
    pub const extra_black: Weight = .{ .value = 950.0 };

    pub fn init(value: f32) Weight {
        return .{ .value = value };
    }
};

pub const Attributes = struct {
    stretch: Stretch = .normal,
    style: Style = .normal,
    weight: Weight = .normal,
};

/// Derive application-facing attributes with the same precedence as Skrifa:
/// OS/2 controls width, weight and italic/oblique bits; `post` contributes only
/// the optional oblique angle. If OS/2 is absent, head.macStyle supplies the
/// legacy italic/bold fallback. Every table read uses Font's public validated
/// inspection methods so borrowed source mutations still fail atomically.
pub fn read(font: *const font_mod.Font) font_mod.FontError!Attributes {
    if (try font.os2Info()) |os2| {
        const style: Style = if ((os2.selection & 0x0001) != 0)
            .italic
        else if ((os2.selection & 0x0200) != 0)
            .{ .oblique = if (try font.postInfo()) |post| post.italic_angle else null }
        else
            .normal;
        return .{
            .stretch = Stretch.fromWidthClass(os2.width_class),
            .style = style,
            .weight = .{ .value = @floatFromInt(os2.weight_class) },
        };
    }

    const head = try font.headInfo();
    return .{
        .style = if ((head.mac_style & 0x0002) != 0) .italic else .normal,
        .weight = if ((head.mac_style & 0x0001) != 0) .bold else .normal,
    };
}
