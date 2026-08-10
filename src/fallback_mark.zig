const Font = @import("font.zig").Font;
const GlyphId = @import("glyph.zig").GlyphId;
const unicode = @import("unicode.zig");

const Extents = struct {
    x_bearing: i32,
    y_bearing: i32,
    width: i32,
    height: i32,
};

pub const Base = struct {
    cluster: usize,
    extents: Extents,
    x_offset: i32,
    y_offset: i32,
};

pub const Offset = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const MarkClass = enum(u8) {
    other,
    attached_below_left,
    attached_below,
    attached_above,
    attached_above_right,
    below_left,
    below,
    below_right,
    left,
    right,
    above_left,
    above,
    above_right,
    double_below,
    double_above,
};

pub fn enabled(use_shape: bool, has_gpos_positioning: bool, has_gpos_attachments: bool, mark_attachment: bool, vertical: bool) bool {
    if (use_shape or mark_attachment or has_gpos_attachments) return false;
    if (has_gpos_positioning) return false;
    return !vertical;
}

pub fn baseForGlyph(font: *const Font, glyph_id: GlyphId, cluster: usize, y_offset: f32, advance: f32, scale: f32, forward: bool) !?Base {
    const bounds = font.glyphBounds(glyph_id) catch return null;
    const y_offset_units: i32 = @intFromFloat(@round(y_offset / scale));
    const advance_units: i32 = @intFromFloat(@round(advance / scale));
    return .{
        .cluster = cluster,
        .extents = .{
            .x_bearing = 0,
            .y_bearing = @as(i32, bounds.y_max) + y_offset_units,
            // HarfBuzz uses horizontal advance for fallback mark positioning
            // rather than ink width, so zero-ink and sparse base glyphs still
            // provide a stable attachment region.
            .width = advance_units,
            .height = @as(i32, bounds.y_min) - @as(i32, bounds.y_max),
        },
        .x_offset = if (forward) -advance_units else advance_units,
        .y_offset = 0,
    };
}

pub fn offset(font: *const Font, glyph_id: GlyphId, codepoint: u21, base: *Base, scale: f32) !Offset {
    const class = recategorizedMarkClass(codepoint);
    if (class == .other or class == .left or class == .right) return .{};
    const mark_extents = try glyphExtents(font, glyph_id);
    var base_extents = base.extents;
    var x_offset: i32 = 0;
    switch (class) {
        .double_below, .double_above => {
            x_offset = base_extents.x_bearing + base_extents.width - @divTrunc(mark_extents.width, 2) - mark_extents.x_bearing;
        },
        .attached_below_left, .below_left, .above_left => {
            x_offset = base_extents.x_bearing - mark_extents.x_bearing;
        },
        .attached_above_right, .below_right, .above_right => {
            x_offset = base_extents.x_bearing + base_extents.width - mark_extents.width - mark_extents.x_bearing;
        },
        else => {
            x_offset = base_extents.x_bearing + @divTrunc(base_extents.width - mark_extents.width, 2) - mark_extents.x_bearing;
        },
    }

    const y_gap: i32 = @intCast(@divTrunc(font.units_per_em, 16));
    var y_offset: i32 = 0;
    const attached = markClassIsAttached(class);
    switch (class) {
        .double_below, .below_left, .below, .below_right, .attached_below_left, .attached_below => {
            if (!attached) base_extents.height -= y_gap;
            y_offset = base_extents.y_bearing + base_extents.height - mark_extents.y_bearing;
            if ((y_gap > 0) == (y_offset > 0)) {
                base_extents.height -= y_offset;
                y_offset = 0;
            }
            base_extents.height += mark_extents.height;
        },
        .double_above, .above_left, .above, .above_right, .attached_above, .attached_above_right => {
            if (!attached) {
                base_extents.y_bearing += y_gap;
                base_extents.height -= y_gap;
            }
            y_offset = base_extents.y_bearing - (mark_extents.y_bearing + mark_extents.height);
            if ((y_gap > 0) != (y_offset > 0)) {
                const correction = @divTrunc(-y_offset, 2);
                base_extents.y_bearing += correction;
                base_extents.height -= correction;
                y_offset += correction;
            }
            base_extents.y_bearing -= mark_extents.height;
            base_extents.height += mark_extents.height;
        },
        else => {},
    }
    base.extents = base_extents;
    return .{
        .x = @as(f32, @floatFromInt(x_offset + base.x_offset)) * scale,
        .y = @as(f32, @floatFromInt(y_offset + base.y_offset)) * scale,
    };
}

fn glyphExtents(font: *const Font, glyph_id: GlyphId) !Extents {
    const bounds = try font.glyphBounds(glyph_id);
    return .{
        .x_bearing = @intCast(bounds.x_min),
        .y_bearing = @intCast(bounds.y_max),
        .width = @as(i32, bounds.x_max) - @as(i32, bounds.x_min),
        .height = @as(i32, bounds.y_min) - @as(i32, bounds.y_max),
    };
}

fn markClassIsAttached(class: MarkClass) bool {
    return switch (class) {
        .attached_below_left, .attached_below, .attached_above, .attached_above_right => true,
        else => false,
    };
}

fn recategorizedMarkClass(codepoint: u21) MarkClass {
    var class = unicode.modifiedCombiningClassForShaping(codepoint);
    if (class < 200) {
        if ((codepoint & ~@as(u21, 0xff)) == 0x0e00) {
            if (class == 0) {
                class = switch (codepoint) {
                    0x0e31, 0x0e34...0x0e37, 0x0e47, 0x0e4c...0x0e4e => 232,
                    0x0eb1, 0x0eb4...0x0eb7, 0x0ebb, 0x0ecc...0x0ecd => 230,
                    0x0ebc => 220,
                    else => class,
                };
            } else if (codepoint == 0x0e3a) {
                class = 222;
            }
        }
        class = switch (class) {
            10...18, 20, 22 => 220,
            23 => 214,
            24, 107, 122 => 232,
            25, 19 => 228,
            26, 27, 28, 30, 31, 33, 34, 35, 36, 130 => 230,
            29, 32, 103, 118, 129, 132 => 220,
            else => class,
        };
    }
    return switch (class) {
        200 => .attached_below_left,
        202 => .attached_below,
        214 => .attached_above,
        216 => .attached_above_right,
        218 => .below_left,
        220 => .below,
        222 => .below_right,
        224 => .left,
        226 => .right,
        228 => .above_left,
        230 => .above,
        232 => .above_right,
        233 => .double_below,
        234 => .double_above,
        else => .other,
    };
}
