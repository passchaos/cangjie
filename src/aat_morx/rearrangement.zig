const std = @import("std");

const GlyphId = @import("../glyph.zig").GlyphId;
const gsub = @import("../gsub.zig");
const ligature_provenance = @import("../ligature_provenance.zig");
const shaping_metadata = @import("../shaping_metadata.zig");
const state_table = @import("state_table.zig");

pub const Error = state_table.Error;

const mark_first: u16 = 0x8000;
const mark_last: u16 = 0x2000;
const verb_mask: u16 = 0x000f;
const max_context = 64;

pub fn apply(
    data: []const u8,
    offset: usize,
    length: usize,
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    operations_left: *usize,
) Error!void {
    if (length < 16) return error.BadSfnt;
    const class_count: usize = @intCast(try state_table.readU32(data, offset));
    const class_table_offset: usize = @intCast(try state_table.readU32(data, offset + 4));
    const state_array_offset: usize = @intCast(try state_table.readU32(data, offset + 8));
    const entry_table_offset: usize = @intCast(try state_table.readU32(data, offset + 12));
    if (class_count < 4 or class_table_offset > length or state_array_offset > length or entry_table_offset > length) {
        return error.BadSfnt;
    }

    var state: usize = 0;
    var index: usize = 0;
    var start: usize = 0;
    var end: usize = 0;

    // A malformed state machine can otherwise keep taking DontAdvance
    // transitions forever. Mirror HarfBuzz's buffer-wide operation allowance:
    // legitimate epsilon-heavy machines retain ample room, while an untrusted
    // cycle still terminates independently of the font's state topology.
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
            4,
        );
        const flags = current_entry.flags;

        if (flags & mark_first != 0) start = index;
        if (flags & mark_last != 0) end = @min(index + 1, glyphs.items.len);

        const verb = flags & verb_mask;
        if (verb != 0 and start < end) {
            applyVerb(glyphs, options, start, end, @min(index + 1, glyphs.items.len), verb);
        }

        state = current_entry.new_state;
        if (index >= glyphs.items.len) break;
        if (flags & state_table.dont_advance == 0) index += 1;
    }
}

pub fn applyVerb(
    glyphs: *std.ArrayList(GlyphId),
    options: gsub.runtime.Options,
    start: usize,
    end: usize,
    current_end: usize,
    verb: u16,
) void {
    // Each nibble describes how many glyphs move from one edge to the other.
    // The value three means two glyphs in reversed order. This literal table
    // is the AAT verb contract, not a font-specific substitution map.
    const edge_map = [16]u8{
        0x00, 0x10, 0x01, 0x11,
        0x20, 0x30, 0x02, 0x03,
        0x12, 0x13, 0x21, 0x31,
        0x22, 0x32, 0x23, 0x33,
    };
    const edge = edge_map[verb];
    const left_code = edge >> 4;
    const right_code = edge & 0x0f;
    const left_count: usize = @min(@as(usize, 2), left_code);
    const right_count: usize = @min(@as(usize, 2), right_code);
    const count = end - start;
    if (count < left_count + right_count or count > max_context) return;

    if (options.glyph_cluster_indices) |clusters| {
        if (options.cluster_level.isMonotone()) {
            // HarfBuzz first includes the current state-machine position and
            // then the marked span. The first range can extend past `end` when
            // the action is delayed until a later glyph or end-of-text.
            shaping_metadata.mergeMonotoneClusters(clusters.items, start, current_end);
            shaping_metadata.mergeMonotoneClusters(clusters.items, start, end);
        }
    }

    rearrangeSlice(GlyphId, glyphs.items, start, end, left_count, right_count, left_code == 3, right_code == 3);
    if (options.glyph_source_indices) |values| {
        rearrangeSlice(usize, values.items, start, end, left_count, right_count, left_code == 3, right_code == 3);
    }
    if (options.glyph_cluster_indices) |values| {
        rearrangeSlice(usize, values.items, start, end, left_count, right_count, left_code == 3, right_code == 3);
    }
    if (options.glyph_substituted) |values| {
        rearrangeSlice(bool, values.items, start, end, left_count, right_count, left_code == 3, right_code == 3);
    }
    if (options.glyph_stage_substituted) |values| {
        rearrangeSlice(bool, values.items, start, end, left_count, right_count, left_code == 3, right_code == 3);
    }
    if (options.ligature_components) |store| {
        rearrangeSlice(ligature_provenance.Info, store.infos.items, start, end, left_count, right_count, left_code == 3, right_code == 3);
    }
}

fn rearrangeSlice(
    comptime T: type,
    values: []T,
    start: usize,
    end: usize,
    left_count: usize,
    right_count: usize,
    reverse_left: bool,
    reverse_right: bool,
) void {
    const count = end - start;
    std.debug.assert(count <= max_context);
    var original: [max_context]T = undefined;
    @memcpy(original[0..count], values[start..end]);

    var output: usize = start;
    for (0..right_count) |index| {
        const source = if (reverse_right) count - 1 - index else count - right_count + index;
        values[output] = original[source];
        output += 1;
    }
    for (left_count..count - right_count) |source| {
        values[output] = original[source];
        output += 1;
    }
    for (0..left_count) |index| {
        const source = if (reverse_left) left_count - 1 - index else index;
        values[output] = original[source];
        output += 1;
    }
    std.debug.assert(output == end);
}

test "moves the final marked pair with parallel metadata" {
    // This compact state machine marks every A+B pair and applies verb 1 at
    // end-of-text. The last A therefore moves after B, matching MORX-10.
    const data = [_]u8{
        0x00, 0x00, 0x00, 0x06, // class count
        0x00, 0x00, 0x00, 0x10, // class lookup
        0x00, 0x00, 0x00, 0x1c, // state array
        0x00, 0x00, 0x00, 0x28, // entry table
        0x00, 0x08, 0x00, 0x02,
        0x00, 0x02, 0x00, 0x04,
        0x00, 0x05, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x01,
        0x00, 0x02, 0x00, 0x03,
        0x00, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xa0, 0x00,
        0x00, 0x00, 0x20, 0x00,
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.appendSlice(std.testing.allocator, &.{ 2, 3, 2, 3, 2, 3 });

    var sources = std.ArrayList(usize).empty;
    defer sources.deinit(std.testing.allocator);
    try sources.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4, 5 });

    var clusters = std.ArrayList(usize).empty;
    defer clusters.deinit(std.testing.allocator);
    try clusters.appendSlice(std.testing.allocator, &.{ 0, 1, 2, 3, 4, 5 });

    var substituted = std.ArrayList(bool).empty;
    defer substituted.deinit(std.testing.allocator);
    try substituted.appendSlice(std.testing.allocator, &.{ false, true, false, true, false, true });

    var stage_substituted = std.ArrayList(bool).empty;
    defer stage_substituted.deinit(std.testing.allocator);
    try stage_substituted.appendSlice(std.testing.allocator, &.{ true, false, true, false, true, false });

    var ligatures = ligature_provenance.Store{};
    defer ligatures.deinit(std.testing.allocator);
    try ligatures.infos.resize(std.testing.allocator, glyphs.items.len);
    @memset(ligatures.infos.items, .{});
    ligatures.infos.items[4].flags.synthetic_base = true;

    var operations_left = try state_table.operationBudget(glyphs.items.len);
    try apply(&data, 0, data.len, &glyphs, .{
        .glyph_source_indices = &sources,
        .glyph_cluster_indices = &clusters,
        .glyph_substituted = &substituted,
        .glyph_stage_substituted = &stage_substituted,
        .ligature_components = &ligatures,
    }, &operations_left);

    try std.testing.expectEqualSlices(GlyphId, &.{ 2, 3, 2, 3, 3, 2 }, glyphs.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 5, 4 }, sources.items);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 4, 4 }, clusters.items);
    try std.testing.expectEqualSlices(bool, &.{ false, true, false, true, true, false }, substituted.items);
    try std.testing.expectEqualSlices(bool, &.{ true, false, true, false, false, true }, stage_substituted.items);
    try std.testing.expect(!ligatures.infos.items[4].flags.synthetic_base);
    try std.testing.expect(ligatures.infos.items[5].flags.synthetic_base);
}

test "rejects a non-advancing state cycle" {
    const data = [_]u8{
        0x00, 0x00, 0x00, 0x04, // class count
        0x00, 0x00, 0x00, 0x10, // class lookup
        0x00, 0x00, 0x00, 0x18, // state array
        0x00, 0x00, 0x00, 0x20, // entry table
        0x00, 0x08, 0x00, 0x02, // format 8, first glyph 2
        0x00, 0x01, 0x00, 0x03, // one glyph in class 3
        0x00, 0x00, 0x00, 0x00, // every class selects entry zero
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x40, 0x00, // start state plus DontAdvance
    };

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(std.testing.allocator);
    try glyphs.append(std.testing.allocator, 2);

    var operations_left = try state_table.operationBudget(glyphs.items.len);
    try std.testing.expectError(error.BadSfnt, apply(&data, 0, data.len, &glyphs, .{}, &operations_left));
}
