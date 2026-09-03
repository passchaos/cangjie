//! Inline object contracts and paragraph-output positioning.
//!
//! Objects are anchored by U+FFFC OBJECT REPLACEMENT CHARACTER in the source
//! text. Shaping replaces each marker with one synthetic, non-rendering glyph
//! atom. That keeps the object inside Unicode bidi, line breaking, caret, and
//! selection coordinate spaces without asking a font to draw the marker.

const std = @import("std");

const exclusions = @import("../paragraph/exclusions.zig");

pub const object_replacement_character: u21 = 0xfffc;
pub const object_replacement_utf8 = "\xef\xbf\xbc";

pub const Kind = enum {
    /// The object contributes physical width/height through the active flow
    /// axes: width is horizontal inline or vertical block extent, while height
    /// is horizontal block or vertical inline extent.
    in_flow,
    /// The object is positioned at its source anchor without affecting inline
    /// or block occupancy in either writing mode.
    out_of_flow,
    /// The object yields through `paragraph.OutOfFlowResolver`.
    ///
    /// Direct layout keeps a useful anchor fallback. A resolver lets the
    /// caller replace that fallback with absolute geometry and optionally add
    /// an exclusion before reflow continues.
    custom_out_of_flow,
};

/// Absolute paragraph-space geometry supplied for one custom out-of-flow
/// object.
pub const Geometry = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    /// Baseline measured from the object's top edge. Null uses the bottom.
    baseline: ?f32 = null,

    pub fn resolvedBaseline(self: Geometry) f32 {
        return self.baseline orelse self.height;
    }
};

/// A resolved custom placement keyed by its stable UTF-8 object marker.
pub const Placement = struct {
    byte_index: usize,
    geometry: Geometry,
};

/// Caller response to one custom out-of-flow placement request.
///
/// The optional exclusion is independent from painted object bounds. This
/// supports margins, shape approximations, and objects whose visual geometry
/// should not reserve their complete rectangular bounds.
pub const Resolution = struct {
    geometry: Geometry,
    exclusion: ?exclusions.Exclusion = null,
};

/// One caller-owned object anchored at a U+FFFC source scalar.
///
/// Objects must be ordered by strictly increasing `byte_index`; one source
/// marker owns one object. The index is a UTF-8 byte offset, matching every
/// other public paragraph source coordinate.
pub const Object = struct {
    id: u64,
    kind: Kind = .in_flow,
    byte_index: usize,
    /// Physical object width. It contributes to horizontal inline advance and
    /// to vertical column block extent.
    width: f32,
    /// Physical object height. It contributes to horizontal line metrics and
    /// to vertical positive-down inline advance.
    height: f32,
    /// Baseline measured from the object's top edge. Null uses the bottom edge.
    baseline: ?f32 = null,

    pub fn resolvedBaseline(self: Object) f32 {
        return self.baseline orelse self.height;
    }
};

/// Final object geometry in paragraph coordinates.
pub const Positioned = struct {
    id: u64,
    kind: Kind,
    byte_index: usize,
    /// Final line containing the source marker, even when absolute custom
    /// geometry is painted outside that line.
    line_index: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    baseline: f32,
    /// Source-anchor fallback before any custom absolute placement is applied.
    ///
    /// These fields let a replaying resolver detect that prior exclusions
    /// moved the anchor without conflating that move with caller-owned output
    /// geometry.
    anchor_x: f32,
    anchor_y: f32,
};

/// Location proved while a retained single-object paragraph is permuted.
///
/// The bidi transaction already knows both the final visual glyph index and
/// its owning line. Carrying the accumulated inline pen across that boundary
/// avoids rediscovering the same marker with two binary searches and another
/// glyph-prefix walk during object positioning.
pub const RetainedPositionHint = struct {
    line_index: usize,
    glyph_index: usize,
    pen_inline: f32,
};

pub fn validate(text: []const u8, objects: []const Object) !void {
    var previous_index: ?usize = null;
    for (objects, 0..) |object, object_index| {
        if (previous_index) |previous| {
            if (object.byte_index <= previous) return error.InvalidInlineObjects;
        }
        previous_index = object.byte_index;

        if (!std.math.isFinite(object.width) or object.width < 0 or
            !std.math.isFinite(object.height) or object.height < 0)
        {
            return error.InvalidInlineObjects;
        }
        const baseline = object.resolvedBaseline();
        if (!std.math.isFinite(baseline) or
            baseline < 0 or baseline > object.height)
        {
            return error.InvalidInlineObjects;
        }
        if (object.byte_index > text.len or
            text.len - object.byte_index < object_replacement_utf8.len or
            !std.mem.eql(
                u8,
                text[object.byte_index .. object.byte_index + object_replacement_utf8.len],
                object_replacement_utf8,
            ))
        {
            return error.InvalidInlineObjects;
        }
        // One object must account for every replacement marker. Otherwise an
        // unclaimed marker would silently re-enter font fallback and render as
        // `.notdef`, or a caller could omit an object from retained reflow.
        const search_start = if (object_index == 0)
            0
        else
            objects[object_index - 1].byte_index +
                object_replacement_utf8.len;
        const next_marker = std.mem.indexOfPos(
            u8,
            text,
            search_start,
            object_replacement_utf8,
        ) orelse return error.InvalidInlineObjects;
        if (next_marker != object.byte_index) {
            return error.InvalidInlineObjects;
        }
    }
    const tail_start = if (objects.len == 0)
        0
    else
        objects[objects.len - 1].byte_index +
            object_replacement_utf8.len;
    if (std.mem.indexOfPos(
        u8,
        text,
        tail_start,
        object_replacement_utf8,
    ) != null) {
        return error.InvalidInlineObjects;
    }
}

pub fn indexesMatch(indexes: []const usize, objects: []const Object) bool {
    if (indexes.len != objects.len) return false;
    for (indexes, objects) |index, object| {
        if (index != object.byte_index) return false;
    }
    return true;
}

/// Validate mutable retained-reflow object geometry after preparation already
/// proved every UTF-8 marker and stable byte anchor. This avoids rescanning the
/// immutable paragraph text on each layout while preserving all numeric and
/// ordering checks for caller-supplied geometry.
pub fn validateRetained(indexes: []const usize, objects: []const Object) !void {
    if (indexes.len != objects.len) return error.InvalidInlineObjects;
    for (indexes, objects, 0..) |index, object, object_index| {
        if (object.byte_index != index or
            (object_index != 0 and object.byte_index <= objects[object_index - 1].byte_index) or
            !std.math.isFinite(object.width) or object.width < 0 or
            !std.math.isFinite(object.height) or object.height < 0)
        {
            return error.InvalidInlineObjects;
        }
        const baseline = object.resolvedBaseline();
        if (!std.math.isFinite(baseline) or baseline < 0 or
            baseline > object.height)
        {
            return error.InvalidInlineObjects;
        }
    }
}

pub fn validatePlacements(
    objects: []const Object,
    placements: []const Placement,
) !void {
    for (placements, 0..) |placement, placement_index| {
        try validateGeometry(placement.geometry);
        const object = find(objects, placement.byte_index) orelse
            return error.InvalidOutOfFlowPlacements;
        if (object.kind != .custom_out_of_flow) {
            return error.InvalidOutOfFlowPlacements;
        }
        for (placements[0..placement_index]) |previous| {
            if (previous.byte_index == placement.byte_index) {
                return error.InvalidOutOfFlowPlacements;
            }
        }
    }
}

pub fn validateGeometry(geometry: Geometry) !void {
    if (!std.math.isFinite(geometry.x) or
        !std.math.isFinite(geometry.y) or
        !std.math.isFinite(geometry.width) or
        geometry.width < 0 or
        !std.math.isFinite(geometry.height) or
        geometry.height < 0)
    {
        return error.InvalidOutOfFlowPlacements;
    }
    const baseline = geometry.resolvedBaseline();
    if (!std.math.isFinite(baseline) or
        baseline < 0 or baseline > geometry.height)
    {
        return error.InvalidOutOfFlowPlacements;
    }
}

pub fn find(objects: []const Object, byte_index: usize) ?Object {
    const index = findIndex(objects, byte_index) orelse return null;
    return objects[index];
}

pub fn findIndex(objects: []const Object, byte_index: usize) ?usize {
    var low: usize = 0;
    var high: usize = objects.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (objects[mid].byte_index < byte_index) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low < objects.len and objects[low].byte_index == byte_index) {
        return low;
    }
    return null;
}

pub const VerticalMetrics = struct {
    ascent: f32,
    descent: f32,
};

pub fn verticalMetrics(object: Object) VerticalMetrics {
    const baseline = object.resolvedBaseline();
    return .{
        .ascent = baseline,
        .descent = object.height - baseline,
    };
}

/// Rebuild positioned object output after final line/column ordering.
pub fn position(
    buffer: anytype,
    objects: []const Object,
    placements: []const Placement,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) !void {
    buffer.inline_objects.clearRetainingCapacity();
    if (objects.len == 0) {
        for (buffer.lines.items) |*line| {
            line.inline_object_start = 0;
            line.inline_object_len = 0;
        }
        return;
    }

    try buffer.inline_objects.ensureTotalCapacity(
        buffer.allocator,
        objects.len,
    );
    for (buffer.lines.items, 0..) |*line, line_index| {
        const output_start = buffer.inline_objects.items.len;
        var pen_inline: f32 = if (writing_mode.isVertical())
            line.y
        else
            line.x;
        const glyph_end = line.glyph_start + line.glyph_len;
        for (buffer.glyphs.items[line.glyph_start..glyph_end]) |glyph| {
            if (glyph.isInlineObject()) {
                const object = find(objects, glyph.cluster) orelse
                    return error.InvalidInlineObjects;
                const baseline = object.resolvedBaseline();
                const anchor_x = if (writing_mode.isVertical())
                    line.x + (line.width - object.width) / 2
                else
                    pen_inline;
                const anchor_y = if (writing_mode.isVertical())
                    pen_inline
                else
                    line.y + line.baseline - glyph.y_offset - baseline;
                const placement = if (object.kind == .custom_out_of_flow)
                    findPlacement(placements, object.byte_index)
                else
                    null;
                const geometry = if (placement) |resolved|
                    resolved.geometry
                else
                    Geometry{
                        .x = anchor_x,
                        .y = anchor_y,
                        .width = object.width,
                        .height = object.height,
                        .baseline = object.baseline,
                    };
                buffer.inline_objects.appendAssumeCapacity(.{
                    .id = object.id,
                    .kind = object.kind,
                    .byte_index = object.byte_index,
                    .line_index = line_index,
                    .x = geometry.x,
                    .y = geometry.y,
                    .width = geometry.width,
                    .height = geometry.height,
                    .baseline = geometry.resolvedBaseline(),
                    .anchor_x = anchor_x,
                    .anchor_y = anchor_y,
                });
            }
            pen_inline += if (writing_mode.isVertical())
                glyph.y_advance
            else
                glyph.x_advance;
        }
        line.inline_object_start = output_start;
        line.inline_object_len =
            buffer.inline_objects.items.len - output_start;
    }
    // Truncation may deliberately omit objects after the visible prefix. Every
    // visible synthetic atom must resolve, but invisible source objects need no
    // positioned output record.
}

/// Position one object after the caller has proved the retained simple-layout
/// contract: one matching marker, one output slot, and no custom placement.
/// This avoids a capacity check and binary search on every repeated reflow.
pub fn positionSingleRetained(
    buffer: anytype,
    object: Object,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) void {
    std.debug.assert(object.kind != .custom_out_of_flow);
    std.debug.assert(buffer.inline_objects.capacity >= 1);
    buffer.inline_objects.clearRetainingCapacity();
    const line_index = singleObjectLineIndex(
        buffer.lines.items,
        object.byte_index,
    ) orelse return;
    const line = &buffer.lines.items[line_index];
    const location = singleObjectLocationInLine(
        buffer.glyphs.items,
        line.*,
        object.byte_index,
        writing_mode,
    ) orelse return;
    line.inline_object_start = 0;
    line.inline_object_len = 1;
    const baseline = object.resolvedBaseline();
    const anchor_x = if (writing_mode.isVertical())
        line.x + (line.width - object.width) / 2
    else
        location.pen_inline;
    const anchor_y = if (writing_mode.isVertical())
        location.pen_inline
    else
        line.y + line.baseline -
            buffer.glyphs.items[location.glyph_index].y_offset - baseline;
    buffer.inline_objects.appendAssumeCapacity(.{
        .id = object.id,
        .kind = object.kind,
        .byte_index = object.byte_index,
        .line_index = line_index,
        .x = anchor_x,
        .y = anchor_y,
        .width = object.width,
        .height = object.height,
        .baseline = baseline,
        .anchor_x = anchor_x,
        .anchor_y = anchor_y,
    });
}

/// Position one retained object from a location already verified by the bidi
/// transaction. The caller has also established output capacity and marker
/// identity, so this operation is infallible and performs no source search.
pub fn positionSingleRetainedAt(
    buffer: anytype,
    object: Object,
    hint: RetainedPositionHint,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) void {
    std.debug.assert(object.kind != .custom_out_of_flow);
    positionSingleAt(buffer, object, null, hint, writing_mode);
}

/// Position one pre-resolved custom object in the retained simple path. The
/// absolute paint geometry is caller-owned, so only the marker's line index
/// and fallback anchor need to be recovered from the final visual glyphs.
pub fn positionSingleResolvedRetained(
    buffer: anytype,
    object: Object,
    placement: Placement,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) void {
    std.debug.assert(object.kind == .custom_out_of_flow);
    std.debug.assert(placement.byte_index == object.byte_index);
    std.debug.assert(buffer.inline_objects.capacity >= 1);
    buffer.inline_objects.clearRetainingCapacity();
    const line_index = singleObjectLineIndex(
        buffer.lines.items,
        object.byte_index,
    ) orelse return;
    const line = &buffer.lines.items[line_index];
    const location = singleObjectLocationInLine(
        buffer.glyphs.items,
        line.*,
        object.byte_index,
        writing_mode,
    ) orelse return;
    line.inline_object_start = 0;
    line.inline_object_len = 1;
    const baseline = object.resolvedBaseline();
    const anchor_x = if (writing_mode.isVertical())
        line.x + (line.width - object.width) / 2
    else
        location.pen_inline;
    const anchor_y = if (writing_mode.isVertical())
        location.pen_inline
    else
        line.y + line.baseline -
            buffer.glyphs.items[location.glyph_index].y_offset - baseline;
    buffer.inline_objects.appendAssumeCapacity(.{
        .id = object.id,
        .kind = object.kind,
        .byte_index = object.byte_index,
        .line_index = line_index,
        .x = placement.geometry.x,
        .y = placement.geometry.y,
        .width = placement.geometry.width,
        .height = placement.geometry.height,
        .baseline = placement.geometry.resolvedBaseline(),
        .anchor_x = anchor_x,
        .anchor_y = anchor_y,
    });
}

/// Custom-placement counterpart of `positionSingleRetainedAt`. Absolute paint
/// geometry remains caller-owned; the verified hint supplies only its fallback
/// source anchor and owning line.
pub fn positionSingleResolvedRetainedAt(
    buffer: anytype,
    object: Object,
    placement: Placement,
    hint: RetainedPositionHint,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) void {
    std.debug.assert(object.kind == .custom_out_of_flow);
    std.debug.assert(placement.byte_index == object.byte_index);
    positionSingleAt(buffer, object, placement, hint, writing_mode);
}

fn positionSingleAt(
    buffer: anytype,
    object: Object,
    placement: ?Placement,
    hint: RetainedPositionHint,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) void {
    std.debug.assert(buffer.inline_objects.capacity >= 1);
    std.debug.assert(hint.line_index < buffer.lines.items.len);
    std.debug.assert(hint.glyph_index < buffer.glyphs.items.len);
    std.debug.assert(buffer.glyphs.items[hint.glyph_index].isInlineObject());
    std.debug.assert(buffer.glyphs.items[hint.glyph_index].cluster == object.byte_index);
    buffer.inline_objects.clearRetainingCapacity();
    const line = &buffer.lines.items[hint.line_index];
    line.inline_object_start = 0;
    line.inline_object_len = 1;
    const baseline = object.resolvedBaseline();
    const anchor_x = if (writing_mode.isVertical())
        line.x + (line.width - object.width) / 2
    else
        hint.pen_inline;
    const anchor_y = if (writing_mode.isVertical())
        hint.pen_inline
    else
        line.y + line.baseline -
            buffer.glyphs.items[hint.glyph_index].y_offset - baseline;
    const geometry = if (placement) |resolved| resolved.geometry else Geometry{
        .x = anchor_x,
        .y = anchor_y,
        .width = object.width,
        .height = object.height,
        .baseline = object.baseline,
    };
    buffer.inline_objects.appendAssumeCapacity(.{
        .id = object.id,
        .kind = object.kind,
        .byte_index = object.byte_index,
        .line_index = hint.line_index,
        .x = geometry.x,
        .y = geometry.y,
        .width = geometry.width,
        .height = geometry.height,
        .baseline = geometry.resolvedBaseline(),
        .anchor_x = anchor_x,
        .anchor_y = anchor_y,
    });
}

const SingleObjectLocation = struct {
    glyph_index: usize,
    pen_inline: f32,
};

/// Locate the sole retained object from its source anchor. Line source ranges
/// rule out every other line without walking their glyphs; only the owning
/// line contributes advances before the marker. This is especially important
/// after pure-RTL permutation, where the marker is near the visual start but
/// its source byte remains near the paragraph midpoint.
fn singleObjectLineIndex(
    lines: anytype,
    byte_index: usize,
) ?usize {
    var low: usize = 0;
    var high = lines.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (lines[mid].byte_start <= byte_index)
            low = mid + 1
        else
            high = mid;
    }
    if (low == 0) return null;
    const index = low - 1;
    const line = lines[index];
    if (byte_index - line.byte_start >= line.byte_len) return null;
    return index;
}

fn singleObjectLocationInLine(
    glyphs: anytype,
    line: anytype,
    byte_index: usize,
    writing_mode: @import("../../shaping/pipeline/types.zig").WritingMode,
) ?SingleObjectLocation {
    var pen_inline: f32 = if (writing_mode.isVertical()) line.y else line.x;
    const glyph_end = line.glyph_start + line.glyph_len;
    if (line.glyph_start >= glyph_end) return null;
    const ascending = glyphs[line.glyph_start].cluster <=
        glyphs[glyph_end - 1].cluster;
    var low = line.glyph_start;
    var high = glyph_end;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const cluster = glyphs[mid].cluster;
        if ((ascending and cluster < byte_index) or
            (!ascending and cluster > byte_index))
        {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    if (low >= glyph_end or glyphs[low].cluster != byte_index or
        !glyphs[low].isInlineObject()) return null;

    for (glyphs[line.glyph_start..low]) |glyph| {
        pen_inline += if (writing_mode.isVertical())
            glyph.y_advance
        else
            glyph.x_advance;
    }
    return .{ .glyph_index = low, .pen_inline = pen_inline };
}

test "single resolved retained positioning keeps absolute geometry and anchor" {
    const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
    const ParagraphLine = @import("../types/paragraph.zig").ParagraphLine;
    const Buffer = struct {
        allocator: std.mem.Allocator,
        glyphs: std.ArrayList(GlyphPosition) = .empty,
        lines: std.ArrayList(ParagraphLine) = .empty,
        inline_objects: std.ArrayList(Positioned) = .empty,
    };
    var buffer = Buffer{ .allocator = std.testing.allocator };
    defer buffer.glyphs.deinit(buffer.allocator);
    defer buffer.lines.deinit(buffer.allocator);
    defer buffer.inline_objects.deinit(buffer.allocator);
    try buffer.glyphs.append(buffer.allocator, .{
        .glyph_id = 0,
        .codepoint = object_replacement_character,
        .cluster = 4,
        .source_byte_len = object_replacement_utf8.len,
        .x_advance = 0,
        .flags = .{ .inline_object = true },
    });
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = 0,
        .glyph_len = 1,
        .run_start = 0,
        .run_len = 0,
        .byte_start = 4,
        .byte_len = object_replacement_utf8.len,
        .x = 7,
        .y = 9,
        .width = 0,
        .height = 20,
        .baseline = 15,
        .ascent = 15,
        .descent = 5,
        .leading = 0,
    });
    try buffer.inline_objects.ensureTotalCapacity(buffer.allocator, 1);
    const object = Object{
        .id = 8,
        .kind = .custom_out_of_flow,
        .byte_index = 4,
        .width = 10,
        .height = 12,
        .baseline = 8,
    };
    const placement = Placement{
        .byte_index = 4,
        .geometry = .{
            .x = 31,
            .y = 41,
            .width = 13,
            .height = 17,
            .baseline = 11,
        },
    };
    positionSingleResolvedRetained(
        &buffer,
        object,
        placement,
        .horizontal_tb,
    );
    try std.testing.expectEqual(@as(usize, 1), buffer.inline_objects.items.len);
    const positioned = buffer.inline_objects.items[0];
    try std.testing.expectEqual(@as(f32, 31), positioned.x);
    try std.testing.expectEqual(@as(f32, 41), positioned.y);
    try std.testing.expectEqual(@as(f32, 13), positioned.width);
    try std.testing.expectEqual(@as(f32, 17), positioned.height);
    try std.testing.expectEqual(@as(f32, 11), positioned.baseline);
    try std.testing.expectEqual(@as(f32, 7), positioned.anchor_x);
    try std.testing.expectEqual(@as(f32, 16), positioned.anchor_y);
}

test "verified retained hint positions every single-object kind" {
    const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
    const ParagraphLine = @import("../types/paragraph.zig").ParagraphLine;
    const Buffer = struct {
        allocator: std.mem.Allocator,
        glyphs: std.ArrayList(GlyphPosition) = .empty,
        lines: std.ArrayList(ParagraphLine) = .empty,
        inline_objects: std.ArrayList(Positioned) = .empty,
    };
    var buffer = Buffer{ .allocator = std.testing.allocator };
    defer buffer.glyphs.deinit(buffer.allocator);
    defer buffer.lines.deinit(buffer.allocator);
    defer buffer.inline_objects.deinit(buffer.allocator);
    try buffer.glyphs.appendSlice(buffer.allocator, &.{
        .{ .glyph_id = 1, .codepoint = 'A', .cluster = 0, .source_byte_len = 1, .x_advance = 4 },
        .{ .glyph_id = 0, .codepoint = object_replacement_character, .cluster = 1, .source_byte_len = object_replacement_utf8.len, .x_advance = 6, .y_offset = 2, .flags = .{ .inline_object = true } },
    });
    try buffer.lines.append(buffer.allocator, .{
        .glyph_start = 0,
        .glyph_len = 2,
        .run_start = 0,
        .run_len = 1,
        .byte_start = 0,
        .byte_len = 4,
        .x = 7,
        .y = 9,
        .width = 10,
        .height = 20,
        .baseline = 15,
        .ascent = 15,
        .descent = 5,
        .leading = 0,
    });
    try buffer.inline_objects.ensureTotalCapacity(buffer.allocator, 1);
    const hint: RetainedPositionHint = .{
        .line_index = 0,
        .glyph_index = 1,
        .pen_inline = 11,
    };
    inline for (.{ Kind.in_flow, Kind.out_of_flow }) |kind| {
        const object: Object = .{
            .id = 3,
            .kind = kind,
            .byte_index = 1,
            .width = 6,
            .height = 8,
            .baseline = 5,
        };
        positionSingleRetainedAt(&buffer, object, hint, .horizontal_tb);
        try std.testing.expectEqual(@as(usize, 1), buffer.inline_objects.items.len);
        try std.testing.expectEqual(@as(f32, 11), buffer.inline_objects.items[0].anchor_x);
        try std.testing.expectEqual(@as(f32, 17), buffer.inline_objects.items[0].anchor_y);
    }
    const custom: Object = .{
        .id = 4,
        .kind = .custom_out_of_flow,
        .byte_index = 1,
        .width = 6,
        .height = 8,
        .baseline = 5,
    };
    positionSingleResolvedRetainedAt(&buffer, custom, .{
        .byte_index = 1,
        .geometry = .{ .x = 30, .y = 40, .width = 12, .height = 14, .baseline = 9 },
    }, hint, .horizontal_tb);
    try std.testing.expectEqual(@as(f32, 30), buffer.inline_objects.items[0].x);
    try std.testing.expectEqual(@as(f32, 11), buffer.inline_objects.items[0].anchor_x);
}

fn findPlacement(
    placements: []const Placement,
    byte_index: usize,
) ?Placement {
    for (placements) |placement| {
        if (placement.byte_index == byte_index) return placement;
    }
    return null;
}

test "inline objects require ordered U+FFFC anchors and bounded baselines" {
    const text = "a" ++ object_replacement_utf8 ++ "b";
    try validate(text, &.{.{
        .id = 1,
        .byte_index = 1,
        .width = 10,
        .height = 20,
        .baseline = 12,
    }});
    try std.testing.expectError(error.InvalidInlineObjects, validate(
        "abc",
        &.{.{
            .id = 1,
            .byte_index = 1,
            .width = 10,
            .height = 20,
        }},
    ));
    try std.testing.expectError(error.InvalidInlineObjects, validate(
        text,
        &.{.{
            .id = 1,
            .byte_index = 1,
            .width = 10,
            .height = 20,
            .baseline = 21,
        }},
    ));
}

test "custom out-of-flow placements require matching custom objects" {
    const objects = [_]Object{
        .{
            .id = 1,
            .kind = .custom_out_of_flow,
            .byte_index = 0,
            .width = 10,
            .height = 20,
        },
        .{
            .id = 2,
            .kind = .out_of_flow,
            .byte_index = 3,
            .width = 10,
            .height = 20,
        },
    };
    try validatePlacements(&objects, &.{.{
        .byte_index = 0,
        .geometry = .{
            .x = -5,
            .y = 7,
            .width = 30,
            .height = 40,
            .baseline = 32,
        },
    }});
    try std.testing.expectError(
        error.InvalidOutOfFlowPlacements,
        validatePlacements(&objects, &.{.{
            .byte_index = 3,
            .geometry = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        }}),
    );
    try std.testing.expectError(
        error.InvalidOutOfFlowPlacements,
        validatePlacements(&objects, &.{
            .{
                .byte_index = 0,
                .geometry = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
            },
            .{
                .byte_index = 0,
                .geometry = .{ .x = 1, .y = 1, .width = 1, .height = 1 },
            },
        }),
    );
    try std.testing.expectError(
        error.InvalidOutOfFlowPlacements,
        validatePlacements(&objects, &.{.{
            .byte_index = 0,
            .geometry = .{
                .x = std.math.nan(f32),
                .y = 0,
                .width = 1,
                .height = 1,
            },
        }}),
    );
    try std.testing.expectError(
        error.InvalidOutOfFlowPlacements,
        validatePlacements(&objects, &.{.{
            .byte_index = 0,
            .geometry = .{
                .x = 0,
                .y = 0,
                .width = 1,
                .height = 1,
                .baseline = 2,
            },
        }}),
    );
}
