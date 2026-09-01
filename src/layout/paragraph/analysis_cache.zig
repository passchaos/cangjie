//! Exact single-entry caches for width-independent paragraph analysis.
//!
//! Layout commonly rebuilds the same document text after style or width
//! changes. UAX #29 grapheme boundaries and the untailored UAX #14 break stream
//! depend only on those bytes, while UAX #9 resolution additionally depends on
//! the requested base direction. The two entries remain independent so a
//! tailored line-break request can still reuse bidi analysis without replacing
//! the generic line-analysis entry.

const std = @import("std");

const opportunity = @import("../line_break/opportunity.zig");
const unicode = @import("../../unicode.zig");

pub const Analysis = struct {
    graphemes: []const unicode.GraphemeCluster,
    line_breaks: []const opportunity.Opportunity,
};

pub const Cache = struct {
    allocator: std.mem.Allocator,
    text: []u8 = &.{},
    graphemes: []unicode.GraphemeCluster = &.{},
    line_breaks: []opportunity.Opportunity = &.{},
    valid: bool = false,
    bidi_text: []u8 = &.{},
    bidi_base_direction: unicode.BidiBaseDirection = .ltr,
    bidi_paragraph: ?unicode.BidiParagraph = null,
    bidi_valid: bool = false,
    bidi_hits: usize = 0,
    bidi_misses: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Cache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Cache) void {
        self.freeCurrentAnalysis();
        self.freeCurrentBidi();
        self.* = undefined;
    }

    /// Discard retained analyses and reset observable cache statistics.
    pub fn clear(self: *Cache) void {
        self.freeCurrentAnalysis();
        self.freeCurrentBidi();
        self.bidi_hits = 0;
        self.bidi_misses = 0;
    }

    /// Return analysis for exactly `text`, replacing the prior entry on miss.
    ///
    /// The caller has already validated the complete styled request. Using the
    /// assume-valid iterators here avoids two redundant UTF-8 validation scans
    /// while retaining their full Unicode state machines. New storage is built
    /// transactionally so allocation failure leaves the old entry usable.
    pub fn get(self: *Cache, text: []const u8) !Analysis {
        if (self.valid and std.mem.eql(u8, self.text, text)) {
            return self.analysis();
        }

        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        var graphemes = std.ArrayList(unicode.GraphemeCluster).empty;
        defer graphemes.deinit(self.allocator);
        var grapheme_iterator = unicode.graphemeClustersAssumeValid(text);
        while (grapheme_iterator.next()) |cluster| {
            try graphemes.append(self.allocator, cluster);
        }
        const owned_graphemes = try graphemes.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned_graphemes);

        var line_breaks = std.ArrayList(opportunity.Opportunity).empty;
        defer line_breaks.deinit(self.allocator);
        var line_break_iterator = unicode.lineBreaksAssumeValid(text);
        while (line_break_iterator.next()) |line_break| {
            try line_breaks.append(
                self.allocator,
                opportunity.fromUnicode(line_break),
            );
        }
        const owned_line_breaks = try line_breaks.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(owned_line_breaks);

        self.freeCurrentAnalysis();
        self.text = owned_text;
        self.graphemes = owned_graphemes;
        self.line_breaks = owned_line_breaks;
        self.valid = true;
        return self.analysis();
    }

    /// Return UAX #9 analysis for the exact text and base direction.
    ///
    /// The returned paragraph borrows the cache entry and may be deinitialized
    /// without releasing it. It remains valid only until the next successful
    /// bidi replacement, `clear`, or `deinit`. Misses, including failed
    /// replacement attempts, are counted when the lookup is attempted. A miss
    /// builds all new ownership before publishing it so any error leaves the
    /// prior entry intact.
    pub fn getBidi(
        self: *Cache,
        text: []const u8,
        base_direction: unicode.BidiBaseDirection,
    ) !unicode.BidiParagraph {
        if (self.bidi_valid and
            self.bidi_base_direction == base_direction and
            std.mem.eql(u8, self.bidi_text, text))
        {
            self.bidi_hits += 1;
            return self.bidi_paragraph.?.borrowed();
        }

        self.bidi_misses += 1;
        var paragraph = try unicode.resolveBidiParagraph(
            self.allocator,
            text,
            base_direction,
        );
        errdefer paragraph.deinit();
        const owned_text = try self.allocator.dupe(u8, text);
        errdefer self.allocator.free(owned_text);

        // This is the commit point: everything below is infallible. Keeping
        // the old entry alive until here also keeps outstanding views valid
        // when construction of a replacement runs out of memory.
        self.freeCurrentBidi();
        self.bidi_text = owned_text;
        self.bidi_base_direction = base_direction;
        self.bidi_paragraph = paragraph;
        self.bidi_valid = true;
        return self.bidi_paragraph.?.borrowed();
    }

    fn analysis(self: *const Cache) Analysis {
        return .{
            .graphemes = self.graphemes,
            .line_breaks = self.line_breaks,
        };
    }

    fn freeCurrentAnalysis(self: *Cache) void {
        if (!self.valid) return;
        self.allocator.free(self.line_breaks);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.text);
        self.text = &.{};
        self.graphemes = &.{};
        self.line_breaks = &.{};
        self.valid = false;
    }

    fn freeCurrentBidi(self: *Cache) void {
        if (!self.bidi_valid) return;
        if (self.bidi_paragraph) |*paragraph| paragraph.deinit();
        self.allocator.free(self.bidi_text);
        self.bidi_text = &.{};
        self.bidi_paragraph = null;
        self.bidi_valid = false;
    }
};

test "analysis cache exact hit performs no allocation" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    const first = try cache.get("日本語、かな。");
    const graphemes_ptr = first.graphemes.ptr;
    const line_breaks_ptr = first.line_breaks.ptr;

    // A cache hit must remain usable even when the next allocation would
    // fail. Besides protecting the fast-path contract, this makes the test
    // independent of allocator implementation details such as spare capacity.
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    cache.allocator = failing.allocator();
    const repeated = try cache.get("日本語、かな。");
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(graphemes_ptr, repeated.graphemes.ptr);
    try std.testing.expectEqual(line_breaks_ptr, repeated.line_breaks.ptr);
    cache.allocator = std.testing.allocator;
}

test "analysis cache replacement is transactional under allocation failure" {
    const allocator = std.testing.allocator;
    var replacement_successes_before_failure: usize = 0;
    while (true) : (replacement_successes_before_failure += 1) {
        var failing = std.testing.FailingAllocator.init(allocator, .{});
        var cache = Cache.init(failing.allocator());
        defer cache.deinit();
        _ = try cache.get("original");

        // Count from the completed seed entry so each iteration targets one
        // allocation in the replacement transaction while retaining a single
        // allocator identity for all owned storage.
        failing.fail_index =
            failing.alloc_index + replacement_successes_before_failure;
        const replacement = cache.get("日本語の段落");
        if (replacement) |analysis| {
            if (failing.has_induced_failure) {
                return error.SwallowedOutOfMemoryError;
            }
            try std.testing.expect(analysis.graphemes.len != 0);
            break;
        } else |err| switch (err) {
            error.OutOfMemory => {
                // `get` builds all three owned slices before publishing. A
                // failed replacement must therefore leave the exact prior
                // entry available, including its no-allocation hit path.
                const previous = try cache.get("original");
                try std.testing.expect(previous.graphemes.len != 0);
                try std.testing.expect(previous.line_breaks.len != 0);
            },
        }
    }
}

test "bidi analysis cache exact hit performs no allocation" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    const text = "abc אבג 12";
    const first = try cache.getBidi(text, .ltr);
    const scalars_ptr = first.scalars.ptr;
    const classes_ptr = first.classes.ptr;
    const levels_ptr = first.levels.ptr;
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_misses);
    try std.testing.expectEqual(@as(usize, 0), cache.bidi_hits);

    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );
    cache.allocator = failing.allocator();
    const repeated = try cache.getBidi(text, .ltr);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(scalars_ptr, repeated.scalars.ptr);
    try std.testing.expectEqual(classes_ptr, repeated.classes.ptr);
    try std.testing.expectEqual(levels_ptr, repeated.levels.ptr);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_misses);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_hits);
    cache.allocator = std.testing.allocator;
}

test "bidi analysis cache keys exact text and base direction" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    const ltr = try cache.getBidi("123", .ltr);
    try std.testing.expectEqual(@as(u8, 0), ltr.base_level);
    const rtl = try cache.getBidi("123", .rtl);
    try std.testing.expectEqual(@as(u8, 1), rtl.base_level);
    const other_text = try cache.getBidi("456", .rtl);
    try std.testing.expectEqual(@as(u8, 1), other_text.base_level);
    try std.testing.expectEqual(@as(usize, 3), cache.bidi_misses);
    try std.testing.expectEqual(@as(usize, 0), cache.bidi_hits);

    const repeated = try cache.getBidi("456", .rtl);
    try std.testing.expectEqual(other_text.levels.ptr, repeated.levels.ptr);
    try std.testing.expectEqual(@as(usize, 3), cache.bidi_misses);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_hits);
}

test "cached bidi analysis matches fresh resolution" {
    const text = "abc \u{2067}אבג 12\u{2069} xyz";
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    inline for (.{
        unicode.BidiBaseDirection.ltr,
        unicode.BidiBaseDirection.rtl,
        unicode.BidiBaseDirection.auto,
    }) |base_direction| {
        const cached = try cache.getBidi(text, base_direction);
        var fresh = try unicode.resolveBidiParagraph(
            std.testing.allocator,
            text,
            base_direction,
        );
        defer fresh.deinit();

        try std.testing.expectEqual(fresh.base_level, cached.base_level);
        try std.testing.expectEqualSlices(
            unicode.ExactBidiClass,
            fresh.classes,
            cached.classes,
        );
        try std.testing.expectEqualSlices(u8, fresh.levels, cached.levels);
        try std.testing.expectEqual(cached.scalars.len, fresh.scalars.len);
        for (fresh.scalars, cached.scalars, 0..) |
            expected_scalar,
            actual_scalar,
            scalar_index,
        | {
            try std.testing.expectEqualDeep(expected_scalar, actual_scalar);
            try std.testing.expectEqual(
                fresh.directionForScalar(scalar_index),
                cached.directionForScalar(scalar_index),
            );
        }
    }
}

test "deinitializing borrowed bidi value leaves cached owner alive" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    var borrowed = try cache.getBidi("abc אבג", .auto);
    const levels_ptr = borrowed.levels.ptr;
    borrowed.deinit();

    const repeated = try cache.getBidi("abc אבג", .auto);
    try std.testing.expectEqual(levels_ptr, repeated.levels.ptr);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_hits);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_misses);

    cache.clear();
    try std.testing.expectEqual(@as(usize, 0), cache.bidi_hits);
    try std.testing.expectEqual(@as(usize, 0), cache.bidi_misses);
    const after_clear = try cache.getBidi("abc אבג", .auto);
    try std.testing.expect(after_clear.levels.len != 0);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_misses);
}

test "invalid UTF-8 bidi miss preserves prior cache entry" {
    var cache = Cache.init(std.testing.allocator);
    defer cache.deinit();

    const original = try cache.getBidi("abc אבג", .ltr);
    const original_scalars = original.scalars.ptr;
    const original_levels = original.levels.ptr;
    try std.testing.expectError(
        error.InvalidUtf8,
        cache.getBidi(&.{0xff}, .rtl),
    );
    try std.testing.expectEqual(@as(usize, 2), cache.bidi_misses);

    const repeated = try cache.getBidi("abc אבג", .ltr);
    try std.testing.expectEqual(original_scalars, repeated.scalars.ptr);
    try std.testing.expectEqual(original_levels, repeated.levels.ptr);
    try std.testing.expectEqual(@as(usize, 1), cache.bidi_hits);
}

test "bidi cache replacement is transactional under allocation failure" {
    const allocator = std.testing.allocator;
    const original_text = "original אבג";
    const replacement_text = "日本語 \u{2067}אבג 12\u{2069}";
    var replacement_successes_before_failure: usize = 0;
    while (true) : (replacement_successes_before_failure += 1) {
        var failing = std.testing.FailingAllocator.init(allocator, .{});
        var cache = Cache.init(failing.allocator());
        defer cache.deinit();

        const original = try cache.getBidi(original_text, .ltr);
        const original_scalars = original.scalars.ptr;
        const original_classes = original.classes.ptr;
        const original_levels = original.levels.ptr;
        const original_base_level = original.base_level;
        failing.fail_index =
            failing.alloc_index + replacement_successes_before_failure;

        const replacement = cache.getBidi(replacement_text, .rtl);
        if (replacement) |paragraph| {
            if (failing.has_induced_failure) {
                return error.SwallowedOutOfMemoryError;
            }
            try std.testing.expect(paragraph.scalars.len != 0);
            try std.testing.expectEqual(@as(usize, 2), cache.bidi_misses);
            break;
        } else |err| switch (err) {
            error.OutOfMemory => {
                // The failed miss is counted, while the old exact entry and
                // its borrowed storage remain available without allocation.
                const previous = try cache.getBidi(original_text, .ltr);
                try std.testing.expectEqual(
                    original_base_level,
                    previous.base_level,
                );
                try std.testing.expectEqual(
                    original_scalars,
                    previous.scalars.ptr,
                );
                try std.testing.expectEqual(
                    original_classes,
                    previous.classes.ptr,
                );
                try std.testing.expectEqual(
                    original_levels,
                    previous.levels.ptr,
                );
                try std.testing.expectEqual(@as(usize, 2), cache.bidi_misses);
                try std.testing.expectEqual(@as(usize, 1), cache.bidi_hits);
            },
            error.InvalidUtf8 => return err,
        }
    }
}
