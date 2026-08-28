//! Canonical COLRv0 layer and CPAL color summary for reference benchmarks.

const std = @import("std");
const cangjie = @import("cangjie");
const ft = @import("freetype");

pub fn cangjieChecksum(
    allocator: std.mem.Allocator,
    face: *const cangjie.font.Face,
    glyph_id: cangjie.font.GlyphId,
) !u64 {
    _ = allocator;
    return (try face.color().layerSummary(
        glyph_id,
        0,
        .{ .red = 0, .green = 0, .blue = 0, .alpha = 255 },
    )).checksum;
}

pub fn freeTypeChecksum(face: ft.FT_Face, glyph_id: ft.FT_UInt) !u64 {
    var palette_data = std.mem.zeroes(ft.FT_Palette_Data);
    if (ft.FT_Palette_Data_Get(face, &palette_data) != 0) {
        return error.FreeTypeFailed;
    }
    var palette: [*c]ft.FT_Color = null;
    if (ft.FT_Palette_Select(face, 0, &palette) != 0 or palette == null) {
        return error.FreeTypeFailed;
    }

    var iterator = std.mem.zeroes(ft.FT_LayerIterator);
    var layer_glyph: ft.FT_UInt = 0;
    var color_index: ft.FT_UInt = 0;
    if (ft.FT_Get_Color_Glyph_Layer(
        face,
        glyph_id,
        &layer_glyph,
        &color_index,
        &iterator,
    ) == 0) return error.MissingColorGlyph;
    var hasher = startHasher(iterator.num_layers);
    var layer_count: usize = 0;
    while (true) {
        const canonical_glyph: u32 = layer_glyph;
        const canonical_color_index: u32 = color_index;
        hasher.update(std.mem.asBytes(&canonical_glyph));
        hasher.update(std.mem.asBytes(&canonical_color_index));
        if (color_index == 0xffff) {
            hasher.update(&foreground);
        } else {
            if (color_index >= palette_data.num_palette_entries) {
                return error.FreeTypeFailed;
            }
            const entry = palette[color_index];
            hasher.update(&.{ entry.red, entry.green, entry.blue, entry.alpha });
        }
        layer_count += 1;
        if (ft.FT_Get_Color_Glyph_Layer(
            face,
            glyph_id,
            &layer_glyph,
            &color_index,
            &iterator,
        ) == 0) break;
    }
    if (layer_count != iterator.num_layers) return error.FreeTypeFailed;
    return hasher.final();
}

fn startHasher(layer_count: usize) std.hash.Wyhash {
    var hasher = std.hash.Wyhash.init(0);
    const count: u32 = @intCast(layer_count);
    hasher.update(std.mem.asBytes(&count));
    return hasher;
}

const foreground = [4]u8{ 0, 0, 0, 255 };
