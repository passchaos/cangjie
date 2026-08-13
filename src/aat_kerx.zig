const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const state_table = @import("aat_morx/state_table.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const Adjustment = struct {
    x_advance: i32 = 0,
    x_offset: i32 = 0,
    y_advance: i32 = 0,
    y_offset: i32 = 0,
};

const Direction = enum { forward, backward };

const push: u16 = 0x8000;
const dont_advance: u16 = 0x4000;
const reset: u16 = 0x2000;
const no_action: u16 = 0xffff;
const stack_capacity = 8;

/// Apply state-machine `kerx` subtables to one post-GSUB glyph stream.
///
/// The result is a dense, glyph-indexed sidecar in font units. Keeping the
/// state executor separate from final GlyphPosition construction makes its
/// stack/action invariants independently testable and leaves room for format 4
/// attachment actions without embedding another state machine in layout.zig.
pub fn collectAdjustments(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    glyphs: []const GlyphId,
    out: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    vertical: bool,
    direction_backward: bool,
) Error!void {
    if (table_offset > data.len or table_length > data.len - table_offset or table_length < 8) return error.BadSfnt;
    if (try readU16(data, table_offset) < 2 or try readU16(data, table_offset) > 4) return error.BadSfnt;
    if (try readU16(data, table_offset + 2) != 0) return error.BadSfnt;
    const subtable_count: usize = @intCast(try readU32(data, table_offset + 4));

    try out.resize(allocator, glyphs.len);
    @memset(out.items, .{});
    errdefer {
        @memset(out.items, .{});
        out.clearRetainingCapacity();
    }

    var operations_left = try state_table.operationBudget(glyphs.len);
    var subtable_relative: usize = 8;
    for (0..subtable_count) |_| {
        if (subtable_relative > table_length or table_length - subtable_relative < 12) return error.BadSfnt;
        const subtable_start = table_offset + subtable_relative;
        const subtable_length: usize = @intCast(try readU32(data, subtable_start));
        const coverage = try readU32(data, subtable_start + 4);
        const tuple_count = try readU32(data, subtable_start + 8);
        if (subtable_length < 12 or subtable_length > table_length - subtable_relative) return error.BadSfnt;
        if ((coverage & 0xff) == 1 and
            ((coverage & 0x80000000) != 0) == vertical and
            (coverage & 0x40000000) == 0 and
            (coverage & 0x20000000) == 0)
        {
            try applyFormat1(
                data,
                subtable_start,
                subtable_length,
                glyph_count,
                glyphs,
                out.items,
                tuple_count,
                if (((coverage & 0x10000000) != 0) != direction_backward) .backward else .forward,
                vertical,
                &operations_left,
            );
        }
        subtable_relative += subtable_length;
    }
    if (subtable_relative != table_length) return error.BadSfnt;
}

fn applyFormat1(
    data: []const u8,
    subtable_start: usize,
    subtable_length: usize,
    glyph_count: usize,
    glyphs: []const GlyphId,
    adjustments: []Adjustment,
    tuple_count_raw: u32,
    direction: Direction,
    vertical: bool,
    operations_left: *usize,
) Error!void {
    if (subtable_length < 32 or glyphs.len != adjustments.len) return error.BadSfnt;
    const machine_start = subtable_start + 12;
    const machine_length = subtable_length - 12;
    const class_count: usize = @intCast(try readU32(data, subtable_start + 12));
    const class_table_offset: usize = @intCast(try readU32(data, subtable_start + 16));
    const state_array_offset: usize = @intCast(try readU32(data, subtable_start + 20));
    const entry_table_offset: usize = @intCast(try readU32(data, subtable_start + 24));
    // Every format-1 offset is based at the embedded state table, immediately
    // after the 12-byte common kerx subtable header.
    const action_from_machine: usize = @intCast(try readU32(data, subtable_start + 28));
    const action_offset = action_from_machine;
    if (class_count < 4 or
        class_table_offset < 20 or
        state_array_offset < 20 or
        entry_table_offset < 20 or
        class_table_offset >= machine_length or
        state_array_offset >= machine_length or
        entry_table_offset >= machine_length or
        action_offset > machine_length)
    {
        return error.BadSfnt;
    }
    try state_table.validateLookupU16(
        data,
        machine_start + class_table_offset,
        machine_length - class_table_offset,
        glyph_count,
    );

    const tuple_count: usize = @max(@as(usize, tuple_count_raw), 1);
    var stack: [stack_capacity]usize = undefined;
    var depth: usize = 0;
    var state: usize = 0;
    var cursor: usize = 0;
    var sent_end_of_text = false;
    while (true) {
        if (operations_left.* == 0) return error.BadSfnt;
        operations_left.* -= 1;
        const at_end = cursor >= glyphs.len;
        const logical_index = if (at_end)
            null
        else if (direction == .backward)
            glyphs.len - 1 - cursor
        else
            cursor;
        const class = if (logical_index) |glyph_index|
            (try state_table.lookupGlyphValueBounded(
                data,
                machine_start + class_table_offset,
                machine_length - class_table_offset,
                glyphs[glyph_index],
                glyph_count,
            )) orelse state_table.class_out_of_bounds
        else
            state_table.class_end_of_text;
        const current_entry = try state_table.entry(
            data,
            machine_start,
            machine_length,
            state_array_offset,
            entry_table_offset,
            class_count,
            state,
            class,
            6,
        );
        if ((current_entry.flags & ~(push | dont_advance | reset)) != 0) return error.BadSfnt;
        if (current_entry.new_state >= maxStateCount(state_array_offset, entry_table_offset, class_count)) return error.BadSfnt;

        if ((current_entry.flags & reset) != 0) depth = 0;
        if ((current_entry.flags & push) != 0) {
            if (logical_index) |glyph_index| {
                if (depth < stack.len) {
                    stack[depth] = glyph_index;
                    depth += 1;
                } else {
                    depth = 0;
                }
            }
        }
        if (current_entry.payload != no_action and depth != 0) {
            var action_index: usize = current_entry.payload;
            var last = false;
            while (!last and depth != 0) {
                const action_stride = std.math.mul(usize, action_index, 2) catch return error.BadSfnt;
                const action_relative = std.math.add(usize, action_offset, action_stride) catch return error.BadSfnt;
                if (action_relative > machine_length or machine_length - action_relative < 2) return error.BadSfnt;
                const value: i32 = try readI16(data, machine_start + action_relative);
                action_index = std.math.add(usize, action_index, tuple_count) catch return error.BadSfnt;
                // The extended `kerx` value table uses a literal 0xFFFF
                // sentinel. Unlike obsolete `kern` format 1, the low bit of a
                // real kerning value is not a terminator marker.
                last = value == -1;
                if (last) break;
                depth -= 1;
                const glyph_index = stack[depth];
                if (vertical) {
                    adjustments[glyph_index].y_advance = std.math.add(i32, adjustments[glyph_index].y_advance, value) catch return error.BadSfnt;
                    adjustments[glyph_index].y_offset = std.math.add(i32, adjustments[glyph_index].y_offset, value) catch return error.BadSfnt;
                } else {
                    adjustments[glyph_index].x_advance = std.math.add(i32, adjustments[glyph_index].x_advance, value) catch return error.BadSfnt;
                    adjustments[glyph_index].x_offset = std.math.add(i32, adjustments[glyph_index].x_offset, value) catch return error.BadSfnt;
                }
            }
        }
        state = current_entry.new_state;

        if (at_end) {
            if (sent_end_of_text or (current_entry.flags & dont_advance) == 0) break;
            sent_end_of_text = true;
        } else if ((current_entry.flags & dont_advance) == 0) {
            cursor += 1;
        }
    }
}

fn maxStateCount(state_array_offset: usize, entry_table_offset: usize, class_count: usize) usize {
    if (class_count == 0 or entry_table_offset <= state_array_offset) return 0;
    return (entry_table_offset - state_array_offset) / (class_count * 2);
}

fn readU16(data: []const u8, offset: usize) Error!u16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(u16, data[offset..][0..2], .big);
}

fn readI16(data: []const u8, offset: usize) Error!i16 {
    if (offset > data.len or data.len - offset < 2) return error.EndOfStream;
    return std.mem.readInt(i16, data[offset..][0..2], .big);
}

fn readU32(data: []const u8, offset: usize) Error!u32 {
    if (offset > data.len or data.len - offset < 4) return error.EndOfStream;
    return std.mem.readInt(u32, data[offset..][0..4], .big);
}

test "format 1 pushes glyphs and consumes a sentinel-terminated action list" {
    var bytes = [_]u8{0} ** 120;
    writeU16Test(&bytes, 0, 2);
    writeU32Test(&bytes, 4, 1);
    writeFormat1SubtableTest(&bytes, 8);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    try collectAdjustments(
        &bytes,
        0,
        bytes.len,
        2,
        &.{ 1, 1 },
        &adjustments,
        std.testing.allocator,
        false,
        false,
    );

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(i32, -30), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i32, -30), adjustments.items[0].x_offset);
    try std.testing.expectEqual(@as(i32, 0), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i32, 0), adjustments.items[1].x_offset);

    // Re-running into retained scratch must overwrite rather than accumulate.
    try collectAdjustments(
        &bytes,
        0,
        bytes.len,
        2,
        &.{1},
        &adjustments,
        std.testing.allocator,
        false,
        false,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(Adjustment{}, adjustments.items[0]);
}

fn writeFormat1SubtableTest(bytes: []u8, offset: usize) void {
    const subtable_length: usize = 112;
    const class_table_offset: usize = 20;
    const state_array_offset: usize = 28;
    const entry_table_offset: usize = 52;
    const action_from_machine: usize = 96;
    writeU32Test(bytes, offset, subtable_length);
    writeU32Test(bytes, offset + 4, 1);
    writeU32Test(bytes, offset + 12, 4);
    writeU32Test(bytes, offset + 16, class_table_offset);
    writeU32Test(bytes, offset + 20, state_array_offset);
    writeU32Test(bytes, offset + 24, entry_table_offset);
    writeU32Test(bytes, offset + 28, action_from_machine);

    // Glyph 1 maps to class 3; glyph 0 defaults to out-of-bounds class 1.
    writeU16Test(bytes, offset + 12 + class_table_offset, 0);
    writeU16Test(bytes, offset + 12 + class_table_offset + 2, 1);
    writeU16Test(bytes, offset + 12 + class_table_offset + 4, 3);

    // Three states x four classes. On the first glyph, entry 1 pushes the
    // index and enters state 1. The second glyph uses entry 2 to execute one
    // action and return to start. All other transitions use inert entry 0.
    for (0..12) |cell| writeU16Test(bytes, offset + 12 + state_array_offset + cell * 2, 0);
    writeU16Test(bytes, offset + 12 + state_array_offset + 3 * 2, 1);
    writeU16Test(bytes, offset + 12 + state_array_offset + (4 + 3) * 2, 2);

    writeEntryTest(bytes, offset + 12 + entry_table_offset, 0, 0, 0xffff);
    writeEntryTest(bytes, offset + 12 + entry_table_offset + 6, 1, push, 0xffff);
    writeEntryTest(bytes, offset + 12 + entry_table_offset + 12, 0, 0, 0);

    writeI16Test(bytes, offset + 12 + action_from_machine, -30);
    writeI16Test(bytes, offset + 12 + action_from_machine + 2, -1);
}

fn writeEntryTest(bytes: []u8, offset: usize, new_state: u16, flags: u16, action: u16) void {
    writeU16Test(bytes, offset, new_state);
    writeU16Test(bytes, offset + 2, flags);
    writeU16Test(bytes, offset + 4, action);
}

fn writeU16Test(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16Test(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU32Test(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
