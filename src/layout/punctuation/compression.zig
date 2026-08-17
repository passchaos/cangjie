//! Minimal East Asian punctuation compression for overfull lines.
//!
//! Each eligible punctuation glyph contributes at most half its advance, then
//! the caller's normalized policy scales that capacity. Compression first
//! consumes adjacent punctuation gaps (CLREQ's highest-priority case), then
//! distributes any remaining required reduction over unused punctuation
//! capacity. Glyph advances/offsets carry the result so rendering, caret, and
//! selection geometry remain identical.

const std = @import("std");

const GlyphPosition = @import("../glyph_position.zig").GlyphPosition;
const geometry = @import("../line_break/reflow/geometry.zig");
const hanging = @import("hanging.zig");
const unicode = @import("../../unicode.zig");
const line_break_properties =
    @import("../../unicode/line_break/properties.zig");

/// Effective occupied-width reduction available to logical line selection.
///
/// Compressing the punctuation that also hangs reduces its hanging allowance,
/// so that raw side capacity contributes only `(1 - hanging_fraction)` toward
/// fitting. Other punctuation contributes its complete reduction.
pub fn effectiveCapacity(
    glyphs: []const GlyphPosition,
    glyph_start: usize,
    glyph_end: usize,
    compression_fraction: f32,
    hanging_fraction: f32,
) f32 {
    if (compression_fraction <= 0 or glyph_start >= glyph_end) return 0;
    const hanging_index =
        if (hanging.logicalEndAmount(
            glyphs,
            glyph_start,
            glyph_end,
            hanging_fraction,
        ) > 0)
            glyph_end - 1
        else
            null;
    var total: f32 = 0;
    var atom_start = glyph_start;
    while (atom_start < glyph_end) {
        var atom_end = atom_start + 1;
        while (atom_end < glyph_end and
            glyphs[atom_end].cluster == glyphs[atom_start].cluster)
        {
            atom_end += 1;
        }
        const left = sideCapacity(
            glyphs[atom_start],
            compression_fraction,
        ).left;
        const right_index = atom_end - 1;
        const right = sideCapacity(
            glyphs[right_index],
            compression_fraction,
        ).right;
        total += left * effectiveFactor(
            atom_start,
            hanging_index,
            hanging_fraction,
        );
        total += right * effectiveFactor(
            right_index,
            hanging_index,
            hanging_fraction,
        );
        atom_start = atom_end;
    }
    return total;
}

/// Compress every overfull selected line after truncation and before bidi.
///
/// Applying in logical order preserves whether blank space belongs to the
/// glyph's leading or trailing side; bidi then carries the adjusted advance and
/// offset to its physical position. One side-capacity allocation is reserved
/// before any mutation, so allocation failure leaves the output untouched.
pub fn apply(buffer: anytype, options: anytype) !void {
    const compression_fraction =
        options.punctuation.max_compression_fraction;
    if (compression_fraction <= 0 or buffer.lines.items.len == 0) return;
    var max_glyphs: usize = 0;
    for (buffer.lines.items) |line| {
        max_glyphs = @max(max_glyphs, line.glyph_len);
    }
    const sides = try buffer.allocator.alloc(Sides, max_glyphs);
    defer buffer.allocator.free(sides);

    const max_width = if (options.max_width > 0)
        options.max_width
    else
        std.math.inf(f32);
    for (buffer.lines.items) |line| {
        if (line.glyph_len == 0) continue;
        const glyph_end = line.glyph_start + line.glyph_len;
        const glyphs = buffer.glyphs.items[line.glyph_start..glyph_end];
        const available = geometry.lineWidthLimitForIndent(
            max_width,
            line.indent,
        );
        const hanging_amount = hanging.logicalEndAmount(
            buffer.glyphs.items,
            line.glyph_start,
            glyph_end,
            options.punctuation.end_hanging_fraction,
        );
        const occupied = geometry.lineWidth(glyphs) - hanging_amount;
        const required = @max(0, occupied - available);
        if (required <= 0) continue;
        const hanging_index: ?usize =
            if (hanging_amount > 0) glyphs.len - 1 else null;
        const applied = applyToLine(
            glyphs,
            sides[0..glyphs.len],
            required,
            compression_fraction,
            options.punctuation.end_hanging_fraction,
            hanging_index,
        );
        std.debug.assert(applied + 0.001 >= required);
    }
}

fn applyToLine(
    glyphs: []GlyphPosition,
    sides: []Sides,
    required: f32,
    compression_fraction: f32,
    hanging_fraction: f32,
    hanging_index: ?usize,
) f32 {
    std.debug.assert(glyphs.len == sides.len);
    for (glyphs, sides) |glyph, *entry| {
        entry.* = sideCapacity(glyph, compression_fraction);
    }
    restrictToSourceAtomEdges(glyphs, sides);
    var remaining = required;
    var effective_applied: f32 = 0;

    // Highest priority: collapse punctuation-facing punctuation at one source
    // boundary. Draw from the left glyph's right side first, matching CLREQ's
    // preference to remove trailing blank space before leading blank space.
    var index: usize = 0;
    while (index + 1 < glyphs.len and remaining > 0) : (index += 1) {
        if (glyphs[index].cluster == glyphs[index + 1].cluster) continue;
        const left_factor = effectiveFactor(
            index,
            hanging_index,
            hanging_fraction,
        );
        const right_factor = effectiveFactor(
            index + 1,
            hanging_index,
            hanging_fraction,
        );
        const left_effective = sides[index].right * left_factor;
        const right_effective = sides[index + 1].left * right_factor;
        if (left_effective + right_effective <= 0) continue;
        const from_left = if (left_factor > 0)
            @min(sides[index].right, remaining / left_factor)
        else
            0;
        shrinkRight(&glyphs[index], from_left);
        sides[index].right -= from_left;
        const left_reduction = from_left * left_factor;
        remaining -= left_reduction;
        effective_applied += left_reduction;
        const from_right = if (right_factor > 0)
            @min(sides[index + 1].left, remaining / right_factor)
        else
            0;
        shrinkLeft(&glyphs[index + 1], from_right);
        sides[index + 1].left -= from_right;
        const right_reduction = from_right * right_factor;
        remaining -= right_reduction;
        effective_applied += right_reduction;
    }

    // Second priority: all remaining punctuation-side capacity.
    for (glyphs, sides, 0..) |*glyph, *entry, glyph_index| {
        if (remaining <= 0) break;
        const factor = effectiveFactor(
            glyph_index,
            hanging_index,
            hanging_fraction,
        );
        if (factor <= 0) continue;
        const from_left = @min(entry.left, remaining / factor);
        shrinkLeft(glyph, from_left);
        entry.left -= from_left;
        const left_reduction = from_left * factor;
        remaining -= left_reduction;
        effective_applied += left_reduction;
        if (remaining <= 0) break;
        const from_right = @min(entry.right, remaining / factor);
        shrinkRight(glyph, from_right);
        entry.right -= from_right;
        const right_reduction = from_right * factor;
        remaining -= right_reduction;
        effective_applied += right_reduction;
    }
    return effective_applied;
}

const Sides = struct {
    left: f32 = 0,
    right: f32 = 0,
};

fn sideCapacity(glyph: GlyphPosition, fraction: f32) Sides {
    if (glyph.isInlineObject() or glyph.isDiscretionaryHyphen() or
        !line_break_properties.lookup(glyph.codepoint).east_asian or
        glyph.x_advance <= 0)
    {
        return .{};
    }
    const half = glyph.x_advance * 0.5 * fraction;
    return switch (unicode.lineBreakClassForCodepoint(glyph.codepoint)) {
        .open_punctuation => .{ .left = half },
        .close_punctuation,
        .close_parenthesis,
        .exclamation,
        .nonstarter,
        => .{ .right = half },
        .infix_separator => .{
            .left = half / 2,
            .right = half / 2,
        },
        else => .{},
    };
}

fn restrictToSourceAtomEdges(
    glyphs: []const GlyphPosition,
    sides: []Sides,
) void {
    var start: usize = 0;
    while (start < glyphs.len) {
        var end = start + 1;
        while (end < glyphs.len and
            glyphs[end].cluster == glyphs[start].cluster)
        {
            end += 1;
        }
        for (start + 1..end) |index| sides[index].left = 0;
        for (start..end - 1) |index| sides[index].right = 0;
        start = end;
    }
}

fn effectiveFactor(
    glyph_index: usize,
    hanging_index: ?usize,
    hanging_fraction: f32,
) f32 {
    if (hanging_index != null and hanging_index.? == glyph_index) {
        return @max(0, 1 - hanging_fraction);
    }
    return 1;
}

fn shrinkLeft(glyph: *GlyphPosition, amount: f32) void {
    if (amount <= 0) return;
    glyph.x_offset -= amount;
    glyph.x_advance -= amount;
}

fn shrinkRight(glyph: *GlyphPosition, amount: f32) void {
    if (amount <= 0) return;
    glyph.x_advance -= amount;
}

test "compression uses only the reduction needed" {
    var glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x3002, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x300c, .cluster = 3, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 10),
        effectiveCapacity(&glyphs, 0, glyphs.len, 1, 0),
        0.001,
    );
    var sides: [glyphs.len]Sides = undefined;
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        applyToLine(&glyphs, &sides, 3, 1, 0, null),
        0.001,
    );
    try std.testing.expectApproxEqAbs(@as(f32, 7), glyphs[0].x_advance, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), glyphs[1].x_advance, 0.001);
}

test "capacity counts only reusable source-atom edges" {
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x3002, .cluster = 0, .x_advance = 4 },
        .{ .glyph_id = 2, .codepoint = 0x3002, .cluster = 0, .x_advance = 6 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 3),
        effectiveCapacity(&glyphs, 0, glyphs.len, 1, 0),
        0.001,
    );
}

test "hanging reduces effective compression capacity at the same edge" {
    const glyphs = [_]GlyphPosition{
        .{ .glyph_id = 1, .codepoint = 0x4e00, .cluster = 0, .x_advance = 10 },
        .{ .glyph_id = 2, .codepoint = 0x3002, .cluster = 3, .x_advance = 10 },
    };
    try std.testing.expectApproxEqAbs(
        @as(f32, 5),
        effectiveCapacity(&glyphs, 0, glyphs.len, 1, 0),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 2.5),
        effectiveCapacity(&glyphs, 0, glyphs.len, 1, 0.5),
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0),
        effectiveCapacity(&glyphs, 0, glyphs.len, 1, 1),
        0.001,
    );
}
