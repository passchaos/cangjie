//! UTF-8 paragraph facade and per-line UAX #9 reordering.
//!
//! Resolution is scalar-indexed so public maps remain compact. Line operations
//! take scalar ranges whose boundaries must coincide with decoded UTF-8
//! scalars; callers such as paragraph layout derive those ranges from source
//! byte offsets.

const std = @import("std");

const property_data = @import("data.zig");
const resolver = @import("resolver.zig");

pub const unicode_version = property_data.unicode_version;
pub const Class = property_data.Class;
pub const BaseDirection = resolver.BaseDirection;

pub const Scalar = struct {
    codepoint: u21,
    byte_start: usize,
    byte_len: u3,
};

pub const Paragraph = struct {
    allocator: std.mem.Allocator,
    base_level: u8,
    scalars: []Scalar,
    classes: []Class,
    levels: []u8,

    pub fn deinit(self: *Paragraph) void {
        self.allocator.free(self.levels);
        self.allocator.free(self.classes);
        self.allocator.free(self.scalars);
        self.* = undefined;
    }

    pub fn scalarIndexForByte(self: Paragraph, byte_offset: usize) ?usize {
        var low: usize = 0;
        var high = self.scalars.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            if (self.scalars[mid].byte_start < byte_offset) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        if (low < self.scalars.len and
            self.scalars[low].byte_start == byte_offset) return low;
        if (low == self.scalars.len and
            (self.scalars.len == 0 or
                byte_offset == self.scalars[self.scalars.len - 1].byte_start +
                    self.scalars[self.scalars.len - 1].byte_len))
        {
            return low;
        }
        return null;
    }

    /// Applies L1 to one visual line without changing paragraph-wide levels.
    pub fn lineLevels(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
    ) ![]u8 {
        return self.lineLevelsRetaining(
            allocator,
            scalar_start,
            scalar_end,
            &.{},
        );
    }

    /// Applies L1 while assigning selected X9 scalars their preceding level.
    ///
    /// Layout uses this only when a normally removed control acquires visual
    /// content (currently a materialized U+00AD discretionary hyphen).
    pub fn lineLevelsRetaining(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
        retained: []const usize,
    ) ![]u8 {
        if (scalar_start > scalar_end or scalar_end > self.levels.len) {
            return error.InvalidScalarRange;
        }
        const result = try allocator.dupe(
            u8,
            self.levels[scalar_start..scalar_end],
        );
        resetLineLevels(
            self.classes[scalar_start..scalar_end],
            result,
            self.base_level,
        );
        for (retained) |scalar_index| {
            if (scalar_index < scalar_start or scalar_index >= scalar_end) {
                return error.InvalidScalarRange;
            }
            if (result[scalar_index - scalar_start] != resolver.removed_level) {
                continue;
            }
            result[scalar_index - scalar_start] =
                self.inheritedLevel(scalar_index);
        }
        return result;
    }

    /// Returns scalar indexes in L2 visual order for one resolved line.
    pub fn visualOrder(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
    ) ![]usize {
        return self.visualOrderRetaining(
            allocator,
            scalar_start,
            scalar_end,
            &.{},
        );
    }

    pub fn visualOrderRetaining(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
        retained: []const usize,
    ) ![]usize {
        const levels = try self.lineLevelsRetaining(
            allocator,
            scalar_start,
            scalar_end,
            retained,
        );
        defer allocator.free(levels);
        var retained_count: usize = 0;
        for (levels) |level| retained_count += @intFromBool(
            level != resolver.removed_level,
        );
        const order = try allocator.alloc(usize, retained_count);
        var output_index: usize = 0;
        for (levels, 0..) |level, index| {
            if (level == resolver.removed_level) continue;
            order[output_index] = scalar_start + index;
            output_index += 1;
        }
        reorderVisual(
            order,
            levels,
            scalar_start,
        );
        return order;
    }

    pub fn fullVisualOrder(
        self: Paragraph,
        allocator: std.mem.Allocator,
    ) ![]usize {
        return self.visualOrder(allocator, 0, self.scalars.len);
    }

    pub fn directionForScalar(self: Paragraph, scalar_index: usize) ?BaseDirection {
        if (scalar_index >= self.levels.len) return null;
        return if (self.levels[scalar_index] & 1 == 0) .ltr else .rtl;
    }

    pub fn visualCodepoint(
        self: Paragraph,
        scalar_index: usize,
    ) ?u21 {
        if (scalar_index >= self.scalars.len) return null;
        const codepoint = self.scalars[scalar_index].codepoint;
        return if (self.levels[scalar_index] & 1 != 0)
            mirroredCodepoint(codepoint)
        else
            codepoint;
    }

    fn inheritedLevel(self: Paragraph, scalar_index: usize) u8 {
        var previous = scalar_index;
        while (previous > 0) {
            previous -= 1;
            const level = self.levels[previous];
            if (level != resolver.removed_level) return level;
        }
        return self.base_level;
    }
};

pub fn resolve(
    allocator: std.mem.Allocator,
    text: []const u8,
    base_direction: BaseDirection,
) !Paragraph {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;

    var scalar_list = std.ArrayList(Scalar).empty;
    defer scalar_list.deinit(allocator);
    var inputs = std.ArrayList(resolver.Input).empty;
    defer inputs.deinit(allocator);

    var cursor: usize = 0;
    while (cursor < text.len) {
        const start = cursor;
        const codepoint = decodeValid(text, &cursor);
        try scalar_list.append(allocator, .{
            .codepoint = codepoint,
            .byte_start = start,
            .byte_len = @intCast(cursor - start),
        });
        try inputs.append(allocator, .{
            .codepoint = codepoint,
            .class = property_data.class(codepoint),
        });
    }

    var scratch = resolver.Scratch.init(allocator);
    defer scratch.deinit();
    const base_level = try scratch.resolve(inputs.items, base_direction);
    const scalars = try scalar_list.toOwnedSlice(allocator);
    errdefer allocator.free(scalars);
    const classes = try allocator.dupe(Class, scratch.initialTypes());
    errdefer allocator.free(classes);
    const levels = try allocator.dupe(u8, scratch.resolvedLevels());
    errdefer allocator.free(levels);
    return .{
        .allocator = allocator,
        .base_level = base_level,
        .scalars = scalars,
        .classes = classes,
        .levels = levels,
    };
}

pub fn classForCodepoint(codepoint: u21) Class {
    return property_data.class(codepoint);
}

pub fn mirroredCodepoint(codepoint: u21) u21 {
    return property_data.mirrored(codepoint);
}

fn resetLineLevels(
    classes: []const Class,
    levels: []u8,
    base_level: u8,
) void {
    std.debug.assert(classes.len == levels.len);
    var index = classes.len;
    while (index > 0) {
        index -= 1;
        const value = classes[index];
        if (isRemovedByX9(value)) continue;
        if (value == .ws or isIsolateInitiator(value) or value == .pdi) {
            levels[index] = base_level;
            continue;
        }
        break;
    }
}

fn reorderVisual(
    order: []usize,
    levels: []const u8,
    scalar_start: usize,
) void {
    var max_level: u8 = 0;
    var minimum_odd: u8 = 0xff;
    for (levels) |level| {
        if (level == resolver.removed_level) continue;
        max_level = @max(max_level, level);
        if (level & 1 != 0) minimum_odd = @min(minimum_odd, level);
    }
    if (minimum_odd == 0xff) return;

    var level = max_level;
    while (true) : (level -= 1) {
        var cursor: usize = 0;
        while (cursor < order.len) {
            if (levels[order[cursor] - scalar_start] < level) {
                cursor += 1;
                continue;
            }
            const start = cursor;
            while (cursor < order.len and
                levels[order[cursor] - scalar_start] >= level)
            {
                cursor += 1;
            }
            std.mem.reverse(usize, order[start..cursor]);
        }
        if (level == minimum_odd) break;
    }
}

fn isRemovedByX9(value: Class) bool {
    return switch (value) {
        .rle, .lre, .rlo, .lro, .pdf, .bn => true,
        else => false,
    };
}

fn isIsolateInitiator(value: Class) bool {
    return value == .lri or value == .rli or value == .fsi;
}

fn decodeValid(text: []const u8, cursor: *usize) u21 {
    const start = cursor.*;
    const first = text[start];
    if (first < 0x80) {
        cursor.* = start + 1;
        return first;
    }
    const second = text[start + 1];
    if (first < 0xe0) {
        cursor.* = start + 2;
        return (@as(u21, first & 0x1f) << 6) |
            @as(u21, second & 0x3f);
    }
    const third = text[start + 2];
    if (first < 0xf0) {
        cursor.* = start + 3;
        return (@as(u21, first & 0x0f) << 12) |
            (@as(u21, second & 0x3f) << 6) |
            @as(u21, third & 0x3f);
    }
    const fourth = text[start + 3];
    cursor.* = start + 4;
    return (@as(u21, first & 0x07) << 18) |
        (@as(u21, second & 0x3f) << 12) |
        (@as(u21, third & 0x3f) << 6) |
        @as(u21, fourth & 0x3f);
}

test "paragraph levels reorder each line independently" {
    var paragraph = try resolve(
        std.testing.allocator,
        "abc אבג xyz",
        .ltr,
    );
    defer paragraph.deinit();
    const order = try paragraph.visualOrder(
        std.testing.allocator,
        0,
        paragraph.scalars.len,
    );
    defer std.testing.allocator.free(order);
    try std.testing.expectEqualSlices(
        usize,
        &.{ 0, 1, 2, 3, 6, 5, 4, 7, 8, 9, 10 },
        order,
    );
}
