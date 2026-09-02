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
    scalars: []const Scalar,
    classes: []const Class,
    levels: []const u8,
    owner: Owner = .allocator,

    const Owner = enum { allocator, borrowed };

    pub fn deinit(self: *Paragraph) void {
        if (self.owner == .allocator) {
            self.allocator.free(self.levels);
            self.allocator.free(self.classes);
            self.allocator.free(self.scalars);
        }
        self.* = undefined;
    }

    /// Return a non-owning copy of this resolved paragraph.
    ///
    /// The returned value may be deinitialized safely, but doing so releases
    /// no storage. Its slices remain valid only until the paragraph that owns
    /// them is deinitialized or replaces its backing storage. This is useful
    /// for caches that must retain ownership while lending a short-lived value
    /// to existing paragraph consumers.
    pub fn borrowed(self: Paragraph) Paragraph {
        var view = self;
        view.owner = .borrowed;
        return view;
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
        var result = std.ArrayList(u8).empty;
        errdefer result.deinit(allocator);
        try self.fillLineLevelsRetaining(
            allocator,
            scalar_start,
            scalar_end,
            retained,
            &result,
        );
        return try result.toOwnedSlice(allocator);
    }

    /// Fill reusable caller-owned scratch with this line's effective levels.
    ///
    /// The returned view is `result.items`; it remains borrowed from `result`
    /// only until that list is mutated. This narrow no-X9-retention form lets
    /// direct glyph consumers apply L2 to their own parallel records without
    /// materializing a scalar-index permutation.
    pub fn lineLevelsInto(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
        result: *std.ArrayList(u8),
    ) !void {
        return self.fillLineLevelsRetaining(
            allocator,
            scalar_start,
            scalar_end,
            &.{},
            result,
        );
    }

    fn fillLineLevelsRetaining(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
        retained: []const usize,
        result: *std.ArrayList(u8),
    ) !void {
        if (scalar_start > scalar_end or scalar_end > self.levels.len) {
            return error.InvalidScalarRange;
        }
        result.clearRetainingCapacity();
        try result.appendSlice(
            allocator,
            self.levels[scalar_start..scalar_end],
        );
        resetLineLevels(
            self.classes[scalar_start..scalar_end],
            result.items,
            self.base_level,
        );
        for (retained) |scalar_index| {
            if (scalar_index < scalar_start or scalar_index >= scalar_end) {
                return error.InvalidScalarRange;
            }
            if (result.items[scalar_index - scalar_start] !=
                resolver.removed_level)
            {
                continue;
            }
            result.items[scalar_index - scalar_start] =
                self.inheritedLevel(scalar_index);
        }
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
        var levels = std.ArrayList(u8).empty;
        defer levels.deinit(allocator);
        var order = std.ArrayList(usize).empty;
        errdefer order.deinit(allocator);
        try self.visualOrderAndLevelsRetaining(
            allocator,
            scalar_start,
            scalar_end,
            retained,
            &levels,
            &order,
        );
        return try order.toOwnedSlice(allocator);
    }

    /// Compute L1 levels and L2 order together into caller-owned storage.
    ///
    /// Both results derive from exactly the same adjusted levels. Paragraph
    /// layout needs both for direction/mirroring, so exposing the transaction
    /// avoids applying L1 twice and allocating two arrays for every line.
    pub fn visualOrderAndLevelsRetaining(
        self: Paragraph,
        allocator: std.mem.Allocator,
        scalar_start: usize,
        scalar_end: usize,
        retained: []const usize,
        levels: *std.ArrayList(u8),
        order: *std.ArrayList(usize),
    ) !void {
        try self.fillLineLevelsRetaining(
            allocator,
            scalar_start,
            scalar_end,
            retained,
            levels,
        );
        var retained_count: usize = 0;
        for (levels.items) |level| retained_count += @intFromBool(
            level != resolver.removed_level,
        );
        order.clearRetainingCapacity();
        try order.ensureTotalCapacity(allocator, retained_count);
        for (levels.items, 0..) |level, index| {
            if (level == resolver.removed_level) continue;
            order.appendAssumeCapacity(scalar_start + index);
        }
        reorderVisual(
            order.items,
            levels.items,
            scalar_start,
        );
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

/// Resolve into caller-owned arrays and reusable UAX #9 scratch.
///
/// The returned paragraph borrows all three arrays and remains valid only
/// until `scalars`, `inputs`, or `scratch` is reused. This is intended for
/// layout transactions that consume the resolution synchronously; `resolve`
/// above remains the owning public contract.
fn resolveInto(
    allocator: std.mem.Allocator,
    text: []const u8,
    base_direction: BaseDirection,
    scalars: *std.ArrayList(Scalar),
    inputs: *std.ArrayList(resolver.Input),
    scratch: *resolver.Scratch,
) !Paragraph {
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;

    scalars.clearRetainingCapacity();
    inputs.clearRetainingCapacity();
    try scalars.ensureTotalCapacity(allocator, text.len);
    try inputs.ensureTotalCapacity(allocator, text.len);
    var cursor: usize = 0;
    while (cursor < text.len) {
        const start = cursor;
        const codepoint = decodeValid(text, &cursor);
        scalars.appendAssumeCapacity(.{
            .codepoint = codepoint,
            .byte_start = start,
            .byte_len = @intCast(cursor - start),
        });
        inputs.appendAssumeCapacity(.{
            .codepoint = codepoint,
            .class = property_data.class(codepoint),
        });
    }

    const base_level = try scratch.resolve(inputs.items, base_direction);
    return .{
        .allocator = allocator,
        .base_level = base_level,
        .scalars = scalars.items,
        .classes = scratch.initialTypes(),
        .levels = scratch.resolvedLevels(),
        .owner = .borrowed,
    };
}

/// Reusable ownership for synchronous paragraph resolution.
///
/// This remains internal to layout; the public `resolve` result owns an
/// independent snapshot whose lifetime is not coupled to future resolutions.
pub const Storage = struct {
    allocator: std.mem.Allocator,
    scalars: std.ArrayList(Scalar) = .empty,
    inputs: std.ArrayList(resolver.Input) = .empty,
    scratch: resolver.Scratch,

    pub fn init(allocator: std.mem.Allocator) Storage {
        return .{
            .allocator = allocator,
            .scratch = .init(allocator),
        };
    }

    pub fn deinit(self: *Storage) void {
        self.scratch.deinit();
        self.inputs.deinit(self.allocator);
        self.scalars.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn resolve(
        self: *Storage,
        text: []const u8,
        base_direction: BaseDirection,
    ) !Paragraph {
        return resolveInto(
            self.allocator,
            text,
            base_direction,
            &self.scalars,
            &self.inputs,
            &self.scratch,
        );
    }
};

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

test "reusable paragraph resolution matches owning resolution" {
    const text = "abc \u{2067}אבג 12\u{2069}";
    var owned = try resolve(std.testing.allocator, text, .auto);
    defer owned.deinit();
    var storage = Storage.init(std.testing.allocator);
    defer storage.deinit();
    var borrowed = try storage.resolve(text, .auto);
    defer borrowed.deinit();
    try std.testing.expectEqual(Paragraph.Owner.borrowed, borrowed.owner);
    try std.testing.expectEqual(owned.base_level, borrowed.base_level);
    try std.testing.expectEqualSlices(Class, owned.classes, borrowed.classes);
    try std.testing.expectEqualSlices(u8, owned.levels, borrowed.levels);
    try std.testing.expectEqual(owned.scalars.len, borrowed.scalars.len);
    for (owned.scalars, borrowed.scalars) |expected, actual| {
        try std.testing.expectEqualDeep(expected, actual);
    }
}

test "combined line transaction matches separate levels and order" {
    var paragraph = try resolve(
        std.testing.allocator,
        "abc \u{202e}(12)\u{202c} \u{00ad}אבג",
        .ltr,
    );
    defer paragraph.deinit();
    const retained_scalar = paragraph.scalarIndexForByte(
        std.mem.indexOf(u8, "abc \u{202e}(12)\u{202c} \u{00ad}אבג", "\u{00ad}").?,
    ).?;
    const retained = [_]usize{retained_scalar};
    const expected_levels = try paragraph.lineLevelsRetaining(
        std.testing.allocator,
        0,
        paragraph.scalars.len,
        &retained,
    );
    defer std.testing.allocator.free(expected_levels);
    const expected_order = try paragraph.visualOrderRetaining(
        std.testing.allocator,
        0,
        paragraph.scalars.len,
        &retained,
    );
    defer std.testing.allocator.free(expected_order);

    var levels = std.ArrayList(u8).empty;
    defer levels.deinit(std.testing.allocator);
    var order = std.ArrayList(usize).empty;
    defer order.deinit(std.testing.allocator);
    try paragraph.visualOrderAndLevelsRetaining(
        std.testing.allocator,
        0,
        paragraph.scalars.len,
        &retained,
        &levels,
        &order,
    );
    try std.testing.expectEqualSlices(u8, expected_levels, levels.items);
    try std.testing.expectEqualSlices(usize, expected_order, order.items);
}
