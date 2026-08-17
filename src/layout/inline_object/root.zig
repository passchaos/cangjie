//! Inline object contracts and paragraph-output positioning.
//!
//! Objects are anchored by U+FFFC OBJECT REPLACEMENT CHARACTER in the source
//! text. Shaping replaces each marker with one synthetic, non-rendering glyph
//! atom. That keeps the object inside Unicode bidi, line breaking, caret, and
//! selection coordinate spaces without asking a font to draw the marker.

const std = @import("std");

pub const object_replacement_character: u21 = 0xfffc;
pub const object_replacement_utf8 = "\xef\xbf\xbc";

pub const Kind = enum {
    /// The object contributes its width and vertical extents to line layout.
    in_flow,
    /// The object is positioned at its source anchor without affecting line
    /// width or line height.
    out_of_flow,
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
    width: f32,
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
    line_index: usize,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    baseline: f32,
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

pub fn find(objects: []const Object, byte_index: usize) ?Object {
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
        return objects[low];
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

/// Rebuild positioned object output after final line-level bidi ordering.
pub fn position(buffer: anytype, objects: []const Object) !void {
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
        var pen_x: f32 = line.x;
        const glyph_end = line.glyph_start + line.glyph_len;
        for (buffer.glyphs.items[line.glyph_start..glyph_end]) |glyph| {
            if (glyph.isInlineObject()) {
                const object = find(objects, glyph.cluster) orelse
                    return error.InvalidInlineObjects;
                const baseline = object.resolvedBaseline();
                buffer.inline_objects.appendAssumeCapacity(.{
                    .id = object.id,
                    .kind = object.kind,
                    .byte_index = object.byte_index,
                    .line_index = line_index,
                    .x = pen_x,
                    .y = line.y + line.baseline - baseline,
                    .width = object.width,
                    .height = object.height,
                    .baseline = baseline,
                });
            }
            pen_x += glyph.x_advance;
        }
        line.inline_object_start = output_start;
        line.inline_object_len =
            buffer.inline_objects.items.len - output_start;
    }
    // Truncation may deliberately omit objects after the visible prefix. Every
    // visible synthetic atom must resolve, but invisible source objects need no
    // positioned output record.
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
