const std = @import("std");

const GlyphId = @import("glyph.zig").GlyphId;
const ankr = @import("opentype/ankr.zig");
const kerx = @import("opentype/kerx.zig");
const state_table = @import("aat_morx/state_table.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const AttachmentType = enum {
    none,
    mark,
    cursive,
};

pub const Adjustment = struct {
    x_advance: i32 = 0,
    x_offset: i32 = 0,
    y_advance: i32 = 0,
    y_offset: i32 = 0,
    /// A simple cross-stream subtable assigned (rather than added to) this
    /// glyph's minor-axis offset. Vertical layout uses this to replace its
    /// synthesized origin before attachment propagation.
    cross_stream_assigned: bool = false,
    /// The format-1 -0x8000 action clears both the attachment and the
    /// cross-stream coordinate, including the preinstalled vertical origin.
    cross_stream_reset: bool = false,
    attachment_type: AttachmentType = .none,
    attachment_parent_index: ?usize = null,
};

pub const Summary = struct {
    has_cross_stream_adjustment: bool = false,
};

pub const AnkrTable = struct {
    offset: usize,
    length: usize,
};

const Direction = enum { forward, backward };

const push: u16 = 0x8000;
const dont_advance: u16 = 0x4000;
const reset: u16 = 0x2000;
const no_action: u16 = 0xffff;
const stack_capacity = 8;

/// Apply output-side `kerx` subtables to one post-GSUB glyph stream.
///
/// The result is a dense, glyph-indexed sidecar in font units. Keeping the
/// ordered executor separate from final GlyphPosition construction makes its
/// stack/action invariants independently testable. Cross-stream format 1
/// actions are order-sensitive with simple format 0/2/6 assignments and format
/// 4 attachments, so all output-side operations share this one table walk.
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
    requested_kerning: bool,
    simple_pair_eligible: []const bool,
    ankr_table: ?AnkrTable,
) Error!Summary {
    if (table_offset > data.len or table_length > data.len - table_offset or table_length < 8) return error.BadSfnt;
    if (try readU16(data, table_offset) < 2 or try readU16(data, table_offset) > 4) return error.BadSfnt;
    if (try readU16(data, table_offset + 2) != 0) return error.BadSfnt;
    if (simple_pair_eligible.len != glyphs.len) return error.BadSfnt;
    const subtable_count: usize = @intCast(try readU32(data, table_offset + 4));

    try out.resize(allocator, glyphs.len);
    @memset(out.items, .{});
    errdefer {
        @memset(out.items, .{});
        out.clearRetainingCapacity();
    }

    var operations_left = try state_table.operationBudget(glyphs.len);
    var summary = Summary{};
    var cross_stream_initialized = false;
    var previous_cross_stream_adjustment = false;
    var subtable_relative: usize = 8;
    for (0..subtable_count) |_| {
        if (subtable_relative > table_length or table_length - subtable_relative < 12) return error.BadSfnt;
        const subtable_start = table_offset + subtable_relative;
        const subtable_length: usize = @intCast(try readU32(data, subtable_start));
        const coverage = try readU32(data, subtable_start + 4);
        const tuple_count = try readU32(data, subtable_start + 8);
        if (subtable_length < 12 or subtable_length > table_length - subtable_relative) return error.BadSfnt;
        const format = coverage & 0xff;
        const axis_matches = ((coverage & 0x80000000) != 0) == vertical;
        const cross_stream = (coverage & 0x40000000) != 0;
        const not_variable = (coverage & 0x20000000) == 0;
        const simple_cross_stream = requested_kerning and
            (format == 0 or format == 2 or format == 6) and
            cross_stream and
            (coverage & 0x10000000) == 0 and
            tuple_count == 0;
        const format1_enabled = format == 1 and (requested_kerning or cross_stream);
        const format4_enabled = format == 4;
        const applies = axis_matches and not_variable and
            (simple_cross_stream or format1_enabled or format4_enabled);

        if (applies and cross_stream and !cross_stream_initialized) {
            initializeCrossStreamAttachments(
                out.items,
                direction_backward,
            );
            cross_stream_initialized = true;
        }

        if (simple_cross_stream and axis_matches and not_variable) {
            const changed = try applySimpleCrossStream(
                data,
                table_offset,
                table_length,
                subtable_relative,
                glyph_count,
                glyphs,
                simple_pair_eligible,
                out.items,
                vertical,
            );
            previous_cross_stream_adjustment = changed or previous_cross_stream_adjustment;
            summary.has_cross_stream_adjustment = previous_cross_stream_adjustment;
        } else if (format1_enabled and axis_matches and not_variable) {
            var format1_summary = Summary{};
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
                cross_stream,
                &format1_summary,
                &operations_left,
            );
            previous_cross_stream_adjustment = format1_summary.has_cross_stream_adjustment or
                previous_cross_stream_adjustment;
            summary.has_cross_stream_adjustment = previous_cross_stream_adjustment;
        } else if (format4_enabled and axis_matches and not_variable) {
            try applyFormat4(
                data,
                subtable_start,
                subtable_length,
                glyph_count,
                glyphs,
                out.items,
                if (((coverage & 0x10000000) != 0) != direction_backward) .backward else .forward,
                ankr_table,
                &operations_left,
            );
        }
        subtable_relative += subtable_length;
    }
    if (subtable_relative != table_length) return error.BadSfnt;
    return summary;
}

fn initializeCrossStreamAttachments(adjustments: []Adjustment, backward: bool) void {
    if (backward) {
        for (adjustments, 0..) |*adjustment, index| {
            // HarfBuzz marks every slot as cursive, including the edge whose
            // relative parent falls outside the buffer. Format-1 actions test
            // the attachment type before adding to that edge glyph.
            adjustment.attachment_type = .cursive;
            adjustment.attachment_parent_index = if (index + 1 < adjustments.len) index + 1 else null;
        }
    } else {
        for (adjustments, 0..) |*adjustment, index| {
            adjustment.attachment_type = .cursive;
            adjustment.attachment_parent_index = if (index > 0) index - 1 else null;
        }
    }
}

fn applySimpleCrossStream(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    subtable_relative: usize,
    glyph_count: usize,
    glyphs: []const GlyphId,
    eligible: []const bool,
    adjustments: []Adjustment,
    vertical: bool,
) Error!bool {
    if (glyphs.len != eligible.len or glyphs.len != adjustments.len) return error.BadSfnt;
    var changed = false;
    var previous: ?usize = null;
    for (glyphs, eligible, 0..) |glyph, participates, index| {
        if (!participates) continue;
        if (previous) |left_index| {
            const value = (try kerx.simpleSubtableKerning(
                data,
                table_offset,
                table_length,
                glyph_count,
                subtable_relative,
                glyphs[left_index],
                glyph,
            )) orelse return error.BadSfnt;
            if (value != 0) {
                if (vertical) {
                    adjustments[index].x_offset = value;
                } else {
                    adjustments[index].y_offset = value;
                }
                adjustments[index].cross_stream_assigned = true;
                adjustments[index].cross_stream_reset = false;
                changed = true;
            }
        }
        previous = index;
    }
    return changed;
}

fn applyFormat4(
    data: []const u8,
    subtable_start: usize,
    subtable_length: usize,
    glyph_count: usize,
    glyphs: []const GlyphId,
    adjustments: []Adjustment,
    direction: Direction,
    ankr_table: ?AnkrTable,
    operations_left: *usize,
) Error!void {
    if (subtable_length < 32 or glyphs.len != adjustments.len) return error.BadSfnt;
    const machine_start = subtable_start + 12;
    const machine_length = subtable_length - 12;
    const class_count: usize = @intCast(try readU32(data, machine_start));
    const class_table_offset: usize = @intCast(try readU32(data, machine_start + 4));
    const state_array_offset: usize = @intCast(try readU32(data, machine_start + 8));
    const entry_table_offset: usize = @intCast(try readU32(data, machine_start + 12));
    const flags = try readU32(data, machine_start + 16);
    const action_type = flags >> 30;
    const action_offset: usize = @intCast(flags & 0x00ff_ffff);
    if ((flags & 0x3f00_0000) != 0 or
        class_count < 4 or
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

    var state: usize = 0;
    var cursor: usize = 0;
    var mark: usize = 0;
    var mark_set = false;
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
        if ((current_entry.flags & ~(push | dont_advance)) != 0) return error.BadSfnt;
        if (current_entry.new_state >= maxStateCount(state_array_offset, entry_table_offset, class_count)) return error.BadSfnt;

        if (mark_set and current_entry.payload != no_action) {
            if (logical_index) |glyph_index| {
                switch (action_type) {
                    2 => try applyCoordinateAttachment(
                        data,
                        machine_start,
                        machine_length,
                        action_offset,
                        current_entry.payload,
                        mark,
                        glyph_index,
                        adjustments,
                    ),
                    1 => try applyAnkrAttachment(
                        data,
                        machine_start,
                        machine_length,
                        action_offset,
                        current_entry.payload,
                        mark,
                        glyph_index,
                        glyphs,
                        glyph_count,
                        adjustments,
                        ankr_table orelse return error.BadSfnt,
                    ),
                    // Control-point actions need outline callbacks and remain
                    // deliberately unsupported.
                    0 => {},
                    else => return error.BadSfnt,
                }
            }
        }
        if ((current_entry.flags & push) != 0) {
            if (logical_index) |glyph_index| {
                mark_set = true;
                mark = glyph_index;
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

fn applyAnkrAttachment(
    data: []const u8,
    machine_start: usize,
    machine_length: usize,
    action_offset: usize,
    action_index: u16,
    mark_index: usize,
    current_index: usize,
    glyphs: []const GlyphId,
    glyph_count: usize,
    adjustments: []Adjustment,
    ankr_table: AnkrTable,
) Error!void {
    const anchor_index = std.math.mul(usize, action_index, 4) catch return error.BadSfnt;
    const relative = std.math.add(usize, action_offset, anchor_index) catch return error.BadSfnt;
    if (relative > machine_length or machine_length - relative < 4) return error.BadSfnt;
    const mark_anchor_index: usize = try readU16(data, machine_start + relative);
    const current_anchor_index: usize = try readU16(data, machine_start + relative + 2);
    const mark_anchor = try ankr.anchor(
        data,
        ankr_table.offset,
        ankr_table.length,
        glyph_count,
        glyphs[mark_index],
        mark_anchor_index,
    );
    const current_anchor = try ankr.anchor(
        data,
        ankr_table.offset,
        ankr_table.length,
        glyph_count,
        glyphs[current_index],
        current_anchor_index,
    );
    adjustments[current_index].x_offset = @as(i32, mark_anchor.x) - current_anchor.x;
    adjustments[current_index].y_offset = @as(i32, mark_anchor.y) - current_anchor.y;
    adjustments[current_index].cross_stream_assigned = false;
    adjustments[current_index].cross_stream_reset = false;
    adjustments[current_index].attachment_type = .mark;
    adjustments[current_index].attachment_parent_index = mark_index;
}

fn applyCoordinateAttachment(
    data: []const u8,
    machine_start: usize,
    machine_length: usize,
    action_offset: usize,
    action_index: u16,
    mark_index: usize,
    current_index: usize,
    adjustments: []Adjustment,
) Error!void {
    const coordinate_index = std.math.mul(usize, action_index, 8) catch return error.BadSfnt;
    const relative = std.math.add(usize, action_offset, coordinate_index) catch return error.BadSfnt;
    if (relative > machine_length or machine_length - relative < 8) return error.BadSfnt;
    const mark_x: i32 = try readI16(data, machine_start + relative);
    const mark_y: i32 = try readI16(data, machine_start + relative + 2);
    const current_x: i32 = try readI16(data, machine_start + relative + 4);
    const current_y: i32 = try readI16(data, machine_start + relative + 6);
    adjustments[current_index].x_offset = mark_x - current_x;
    adjustments[current_index].y_offset = mark_y - current_y;
    adjustments[current_index].cross_stream_assigned = false;
    adjustments[current_index].cross_stream_reset = false;
    adjustments[current_index].attachment_type = .mark;
    adjustments[current_index].attachment_parent_index = mark_index;
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
    cross_stream: bool,
    summary: *Summary,
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
                if (cross_stream) {
                    if (value == std.math.minInt(i16)) {
                        adjustments[glyph_index].attachment_type = .none;
                        adjustments[glyph_index].attachment_parent_index = null;
                        adjustments[glyph_index].cross_stream_assigned = false;
                        adjustments[glyph_index].cross_stream_reset = true;
                        if (vertical) {
                            adjustments[glyph_index].x_offset = 0;
                        } else {
                            adjustments[glyph_index].y_offset = 0;
                        }
                    } else if (adjustments[glyph_index].attachment_type != .none) {
                        if (vertical) {
                            adjustments[glyph_index].x_offset = std.math.add(i32, adjustments[glyph_index].x_offset, value) catch return error.BadSfnt;
                        } else {
                            adjustments[glyph_index].y_offset = std.math.add(i32, adjustments[glyph_index].y_offset, value) catch return error.BadSfnt;
                        }
                        summary.has_cross_stream_adjustment = true;
                    }
                } else if (vertical) {
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
    _ = try collectAdjustments(
        &bytes,
        0,
        bytes.len,
        2,
        &.{ 1, 1 },
        &adjustments,
        std.testing.allocator,
        false,
        false,
        true,
        &.{ true, true },
        null,
    );

    try std.testing.expectEqual(@as(usize, 2), adjustments.items.len);
    try std.testing.expectEqual(@as(i32, -30), adjustments.items[0].x_advance);
    try std.testing.expectEqual(@as(i32, -30), adjustments.items[0].x_offset);
    try std.testing.expectEqual(@as(i32, 0), adjustments.items[1].x_advance);
    try std.testing.expectEqual(@as(i32, 0), adjustments.items[1].x_offset);

    // Re-running into retained scratch must overwrite rather than accumulate.
    _ = try collectAdjustments(
        &bytes,
        0,
        bytes.len,
        2,
        &.{1},
        &adjustments,
        std.testing.allocator,
        false,
        false,
        true,
        &.{true},
        null,
    );
    try std.testing.expectEqual(@as(usize, 1), adjustments.items.len);
    try std.testing.expectEqual(Adjustment{}, adjustments.items[0]);
}

test "ordered cross-stream subtables preserve assignment and action order" {
    var bytes = [_]u8{0} ** 160;
    writeU16Test(&bytes, 0, 2);
    writeU32Test(&bytes, 4, 2);

    // First assign -20 to the second glyph through a simple format-0 pair.
    writeU32Test(&bytes, 8, 40);
    writeU32Test(&bytes, 12, 0x4000_0000);
    writeU32Test(&bytes, 20, 1);
    writeU32Test(&bytes, 24, 6);
    writeU32Test(&bytes, 32, 0);
    writeU16Test(&bytes, 36, 1);
    writeU16Test(&bytes, 38, 1);
    writeI16Test(&bytes, 40, -20);

    writeFormat1SubtableTest(&bytes, 48);
    // Process the state machine backwards so it pushes the second glyph and
    // then applies its action there when visiting the first glyph.
    writeU32Test(&bytes, 52, 0x5000_0001);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    const summary = try collectAdjustments(
        &bytes,
        0,
        bytes.len,
        2,
        &.{ 1, 1 },
        &adjustments,
        std.testing.allocator,
        false,
        false,
        true,
        &.{ true, true },
        null,
    );

    try std.testing.expect(summary.has_cross_stream_adjustment);
    try std.testing.expectEqual(@as(i32, 0), adjustments.items[0].y_offset);
    try std.testing.expectEqual(@as(i32, -50), adjustments.items[1].y_offset);

    // Reverse subtable order: the later simple assignment replaces the second
    // glyph's prior state-machine value instead of accumulating with it.
    var reversed = [_]u8{0} ** 160;
    writeU16Test(&reversed, 0, 2);
    writeU32Test(&reversed, 4, 2);
    writeFormat1SubtableTest(&reversed, 8);
    writeU32Test(&reversed, 12, 0x5000_0001);
    writeU32Test(&reversed, 120, 40);
    writeU32Test(&reversed, 124, 0x4000_0000);
    writeU32Test(&reversed, 132, 1);
    writeU32Test(&reversed, 136, 6);
    writeU32Test(&reversed, 144, 0);
    writeU16Test(&reversed, 148, 1);
    writeU16Test(&reversed, 150, 1);
    writeI16Test(&reversed, 152, -20);

    _ = try collectAdjustments(
        &reversed,
        0,
        reversed.len,
        2,
        &.{ 1, 1 },
        &adjustments,
        std.testing.allocator,
        false,
        false,
        true,
        &.{ true, true },
        null,
    );
    try std.testing.expectEqual(@as(i32, 0), adjustments.items[0].y_offset);
    try std.testing.expectEqual(@as(i32, -20), adjustments.items[1].y_offset);
}

test "format 4 coordinate action attaches current glyph to marked glyph" {
    var bytes = [_]u8{0} ** 116;
    writeU16Test(&bytes, 0, 2);
    writeU32Test(&bytes, 4, 1);
    writeFormat4SubtableTest(&bytes, 8);

    var adjustments = std.ArrayList(Adjustment).empty;
    defer adjustments.deinit(std.testing.allocator);
    _ = try collectAdjustments(
        &bytes,
        0,
        bytes.len,
        2,
        &.{ 1, 1 },
        &adjustments,
        std.testing.allocator,
        false,
        false,
        true,
        &.{ true, true },
        null,
    );

    try std.testing.expectEqual(Adjustment{}, adjustments.items[0]);
    try std.testing.expectEqual(@as(i32, -30), adjustments.items[1].x_offset);
    try std.testing.expectEqual(@as(i32, 25), adjustments.items[1].y_offset);
    try std.testing.expectEqual(@as(?usize, 0), adjustments.items[1].attachment_parent_index);
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

fn writeFormat4SubtableTest(bytes: []u8, offset: usize) void {
    const subtable_length: usize = 108;
    const class_table_offset: usize = 20;
    const state_array_offset: usize = 28;
    const entry_table_offset: usize = 52;
    const action_offset: usize = 88;
    writeU32Test(bytes, offset, subtable_length);
    writeU32Test(bytes, offset + 4, 4);
    writeU32Test(bytes, offset + 12, 4);
    writeU32Test(bytes, offset + 16, class_table_offset);
    writeU32Test(bytes, offset + 20, state_array_offset);
    writeU32Test(bytes, offset + 24, entry_table_offset);
    writeU32Test(bytes, offset + 28, 0x8000_0000 | action_offset);

    writeU16Test(bytes, offset + 12 + class_table_offset, 0);
    writeU16Test(bytes, offset + 12 + class_table_offset + 2, 1);
    writeU16Test(bytes, offset + 12 + class_table_offset + 4, 3);

    for (0..12) |cell| writeU16Test(bytes, offset + 12 + state_array_offset + cell * 2, 0);
    writeU16Test(bytes, offset + 12 + state_array_offset + 3 * 2, 1);
    writeU16Test(bytes, offset + 12 + state_array_offset + (4 + 3) * 2, 2);

    writeEntryTest(bytes, offset + 12 + entry_table_offset, 0, 0, no_action);
    writeEntryTest(bytes, offset + 12 + entry_table_offset + 6, 1, push, no_action);
    writeEntryTest(bytes, offset + 12 + entry_table_offset + 12, 0, 0, 0);

    writeI16Test(bytes, offset + 12 + action_offset, 10);
    writeI16Test(bytes, offset + 12 + action_offset + 2, 20);
    writeI16Test(bytes, offset + 12 + action_offset + 4, 40);
    writeI16Test(bytes, offset + 12 + action_offset + 6, -5);
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
