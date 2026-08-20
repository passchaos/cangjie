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
        const angle = if ((os2.selection & 0x0200) != 0)
            if (try font.postInfo()) |post| post.italic_angle else null
        else
            null;
        return attributesFromOs2(
            os2.weight_class,
            os2.width_class,
            os2.selection,
            angle,
        );
    }
    return attributesFromMacStyle((try font.headInfo()).mac_style);
}

pub fn readImmutableFace(
    font: *const font_mod.Font,
) font_mod.FontError!Attributes {
    // Attributes need only three OS/2 style fields and the optional post
    // angle. Parse-time validation has already proved both tables for the
    // immutable Face contract, so avoid materializing their much larger
    // public inspection records on every classification lookup.
    if (try font_mod.immutable_face_backend.os2Style(font)) |os2| {
        const angle = if (os2.oblique)
            try font_mod.immutable_face_backend.postItalicAngle(font)
        else
            null;
        const selection = @as(u16, @intFromBool(os2.italic)) |
            (@as(u16, @intFromBool(os2.oblique)) << 9);
        return attributesFromOs2(os2.weight, os2.width, selection, angle);
    }
    return attributesFromMacStyle(
        try font_mod.immutable_face_backend.headMacStyle(font),
    );
}

fn attributesFromOs2(
    weight: u16,
    width: u16,
    selection: u16,
    oblique_angle: ?f32,
) Attributes {
    return .{
        .stretch = Stretch.fromWidthClass(width),
        .style = if ((selection & 0x0001) != 0)
            .italic
        else if ((selection & 0x0200) != 0)
            .{ .oblique = oblique_angle }
        else
            .normal,
        .weight = .{ .value = @floatFromInt(weight) },
    };
}

fn attributesFromMacStyle(mac_style: u16) Attributes {
    return .{
        .style = if ((mac_style & 0x0002) != 0) .italic else .normal,
        .weight = if ((mac_style & 0x0001) != 0) .bold else .normal,
    };
}
