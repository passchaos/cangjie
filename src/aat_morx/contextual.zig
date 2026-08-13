const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;
const gsub = @import("../gsub.zig");
const state_table = @import("state_table.zig");

pub const Error = state_table.Error;

const set_mark: u16 = 0x8000;
const no_lookup: u16 = 0xffff;

pub fn apply(
    data: []const u8,
    offset: usize,
    length: usize,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    operations_left: *usize,
) Error!void {
    if (length < 20) return error.BadSfnt;
    const class_count: usize = @intCast(try state_table.readU32(data, offset));
    const class_table_offset: usize = @intCast(try state_table.readU32(data, offset + 4));
    const state_array_offset: usize = @intCast(try state_table.readU32(data, offset + 8));
    const entry_table_offset: usize = @intCast(try state_table.readU32(data, offset + 12));
    const substitution_offset: usize = @intCast(try state_table.readU32(data, offset + 16));
    if (class_count < 4 or
        class_table_offset > length or
        state_array_offset > length or
        entry_table_offset > length or
        substitution_offset > length)
    {
        return error.BadSfnt;
    }

    var state: usize = 0;
    var index: usize = 0;
    var mark: usize = 0;
    var mark_set = false;
    while (true) {
        if (operations_left.* == 0) return error.BadSfnt;
        operations_left.* -= 1;

        const class = if (index < glyphs.items.len)
            try state_table.classForGlyph(data, offset, length, class_table_offset, glyphs.items[index])
        else
            state_table.class_end_of_text;
        const current_entry = try state_table.entry(
            data,
            offset,
            length,
            state_array_offset,
            entry_table_offset,
            class_count,
            state,
            class,
            8,
        );

        // CoreText and HarfBuzz suppress the implicit end-of-text action until
        // a transition has explicitly established a marked glyph.
        if (index < glyphs.items.len or mark_set) {
            if (current_entry.payload != no_lookup and mark_set and mark < glyphs.items.len) {
                try replaceFromLookup(
                    data,
                    offset,
                    length,
                    substitution_offset,
                    current_entry.payload,
                    glyph_count,
                    glyphs,
                    options,
                    mark,
                );
            }

            if (current_entry.payload_2 != no_lookup and glyphs.items.len != 0) {
                try replaceFromLookup(
                    data,
                    offset,
                    length,
                    substitution_offset,
                    current_entry.payload_2,
                    glyph_count,
                    glyphs,
                    options,
                    @min(index, glyphs.items.len - 1),
                );
            }
        }

        if (current_entry.flags & set_mark != 0) {
            mark_set = index < glyphs.items.len;
            mark = index;
        }

        state = current_entry.new_state;
        if (index >= glyphs.items.len) break;
        if (current_entry.flags & state_table.dont_advance == 0) index += 1;
    }
}

fn replaceFromLookup(
    data: []const u8,
    offset: usize,
    length: usize,
    substitution_offset: usize,
    lookup_index: u16,
    glyph_count: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.LookupOptions,
    glyph_index: usize,
) Error!void {
    if (glyph_index >= glyphs.items.len) return;
    const offset_slot = std.math.mul(usize, lookup_index, 4) catch return error.BadSfnt;
    const slot_relative = std.math.add(usize, substitution_offset, offset_slot) catch return error.BadSfnt;
    if (slot_relative > length or length - slot_relative < 4) return error.BadSfnt;
    const lookup_relative: usize = @intCast(try state_table.readU32(data, offset + slot_relative));
    const lookup_offset = std.math.add(usize, substitution_offset, lookup_relative) catch return error.BadSfnt;
    if (lookup_offset > length) return error.BadSfnt;

    const replacement = (try state_table.lookupGlyphValueBounded(
        data,
        offset + lookup_offset,
        length - lookup_offset,
        glyphs.items[glyph_index],
        glyph_count,
    )) orelse return;
    if (replacement >= glyph_count) return error.BadSfnt;

    glyphs.items[glyph_index] = replacement;
    if (options.glyph_substituted) |values| values.items[glyph_index] = true;
    if (options.glyph_stage_substituted) |values| values.items[glyph_index] = true;
}

test "rejects a non-advancing contextual state cycle" {
    // This is the minimized topology of upstream MORX-24: every live glyph
    // selects an entry that returns to state zero without advancing.
    const data = [_]u8{
        0x00, 0x00, 0x00, 0x05, // class count
        0x00, 0x00, 0x00, 0x14, // class lookup
        0x00, 0x00, 0x00, 0x1c, // state array
        0x00, 0x00, 0x00, 0x26, // entry table
        0x00, 0x00, 0x00, 0x2e, // substitution list
        0x00, 0x08, 0x00, 0x02,
        0x00, 0x01, 0x00, 0x04, // glyph 2 belongs to class 4
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, // all five state cells select entry zero
        0x00, 0x00,
        0x40, 0x00,
        0xff, 0xff, 0xff, 0xff, // no actions, DontAdvance
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 2);

    var operations_left = try state_table.operationBudget(glyphs.items.len);
    try std.testing.expectError(error.BadSfnt, apply(&data, 0, data.len, 3, &glyphs, .{}, &operations_left));
}
