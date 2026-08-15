//! Attachment detection, output-index compaction, and offset propagation.

const std = @import("std");

const aat_kerx = @import("../../../aat_kerx.zig");
const attachment = @import("../../../attachment.zig");
const GlyphPosition = @import("../../../layout/glyph_position.zig").GlyphPosition;
const gpos = @import("../../../gpos.zig");
const pipeline_types = @import("../types.zig");

pub fn hasGpos(adjustments: []const gpos.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type != .none) return true;
    }
    return false;
}

pub fn hasKerx(adjustments: []const aat_kerx.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type != .none and
            adjustment.attachment_parent_index != null)
        {
            return true;
        }
    }
    return false;
}

pub fn hasKerxMarks(adjustments: []const aat_kerx.Adjustment) bool {
    for (adjustments) |adjustment| {
        if (adjustment.attachment_type == .mark and
            adjustment.attachment_parent_index != null)
        {
            return true;
        }
    }
    return false;
}

pub fn linkFor(
    kerx_adjustment: aat_kerx.Adjustment,
    gpos_adjustment: gpos.Adjustment,
) attachment.Link {
    return switch (kerx_adjustment.attachment_type) {
        .none => linkForGpos(gpos_adjustment),
        .mark => .{
            .kind = .mark,
            .parent_index = kerx_adjustment.attachment_parent_index,
        },
        .cursive => .{
            .kind = .cursive,
            .parent_index = kerx_adjustment.attachment_parent_index,
        },
    };
}

/// Compact post-GSUB parent indexes after untouched default-ignorables have
/// been removed from the emitted stream.
pub fn compact(
    links: []attachment.Link,
    output_indices: []const usize,
    output_len: usize,
) void {
    for (output_indices, 0..) |output_index, input_index| {
        if (output_index == std.math.maxInt(usize) or
            output_index >= output_len)
        {
            continue;
        }
        links[output_index] = remap(links[input_index], output_indices);
    }
}

pub fn propagate(
    glyphs: []GlyphPosition,
    links: []attachment.Link,
    options: pipeline_types.LookupOptions,
) void {
    const direction: attachment.Direction = switch (options.shapingDirection()) {
        .ltr => .forward,
        .rtl => .backward,
    };
    const axis: attachment.Axis =
        if (options.writing_mode.isVertical()) .vertical else .horizontal;
    attachment.propagateOffsets(
        GlyphPosition,
        glyphs,
        links,
        direction,
        axis,
    );
}

fn linkForGpos(adjustment: gpos.Adjustment) attachment.Link {
    return switch (adjustment.attachment_type) {
        .none => .{},
        .mark => .{
            .kind = .mark,
            .parent_index = adjustment.attachment_parent_index,
            // MarkPos snapshots the parent's cross-axis placement when its
            // lookup runs. Kerx links deliberately leave this false.
            .cross_axis_resolved = true,
        },
        .cursive => .{
            .kind = .cursive,
            .parent_index = adjustment.attachment_parent_index,
        },
    };
}

fn remap(
    link: attachment.Link,
    output_indices: []const usize,
) attachment.Link {
    const parent = link.parent_index orelse return link;
    if (parent >= output_indices.len) return .{};
    const output_parent = output_indices[parent];
    if (output_parent == std.math.maxInt(usize)) return .{};
    return .{
        .kind = link.kind,
        .parent_index = output_parent,
        .cross_axis_resolved = link.cross_axis_resolved,
    };
}

test "links remap after hidden glyph removal" {
    const removed = std.math.maxInt(usize);
    const output_indices = [_]usize{ 0, removed, 1 };
    var links = [_]attachment.Link{
        .{},
        .{},
        .{ .kind = .mark, .parent_index = 0 },
    };

    compact(&links, &output_indices, 2);

    try std.testing.expectEqual(attachment.Link{}, links[0]);
    try std.testing.expectEqual(
        attachment.Link{ .kind = .mark, .parent_index = 0 },
        links[1],
    );
}
