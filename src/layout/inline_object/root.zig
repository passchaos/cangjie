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
                    line.y + line.baseline + glyph.y_offset - baseline;
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
