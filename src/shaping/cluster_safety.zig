//! Source-boundary safety accumulated while shaping.
//!
//! Context matching operates on mutable glyph and source arrays, while
//! paragraph wrapping consumes immutable UTF-8 positions. Script shapers may
//! insert synthetic sources or canonically decompose one source into several,
//! so source-array indexes cannot be retained across shaping stages. UTF-8
//! byte offsets are immutable and therefore form the stable identity used by
//! this sidecar.

const std = @import("std");

pub const SourceBoundaries = struct {
    /// Bits are local to `[byte_base, byte_base + byte_len]`. Storage is
    /// activated only when a boundary exceeds the inline 64-byte mask.
    unsafe_before_byte: std.DynamicBitSetUnmanaged = .{},
    inline_boundaries: u64 = 0,
    byte_base: usize = 0,
    byte_len: usize = 0,
    dense_active: bool = false,
    source_byte_starts: []const usize = &.{},

    pub fn deinit(self: *SourceBoundaries, allocator: std.mem.Allocator) void {
        self.unsafe_before_byte.deinit(allocator);
        self.* = .{};
    }

    pub fn reset(
        self: *SourceBoundaries,
        byte_base: usize,
        byte_len: usize,
        source_byte_starts: []const usize,
    ) void {
        self.byte_base = byte_base;
        self.byte_len = byte_len;
        self.inline_boundaries = 0;
        self.dense_active = false;
        self.source_byte_starts = source_byte_starts;
    }

    /// Rebind after a script shaper reallocates its parallel source arrays.
    /// Existing flags are keyed by byte offset, so only this transient view
    /// changes; no recorded boundary needs migration.
    pub fn bindSourceByteStarts(
        self: *SourceBoundaries,
        source_byte_starts: []const usize,
    ) void {
        self.source_byte_starts = source_byte_starts;
    }

    pub fn markMatchedGlyphs(
        self: *SourceBoundaries,
        allocator: std.mem.Allocator,
        glyph_source_indices: []const usize,
        glyph_indices: []const usize,
    ) std.mem.Allocator.Error!void {
        if (glyph_indices.len < 2) return;
        var first_byte: ?usize = null;
        var last_byte: usize = 0;
        for (glyph_indices) |glyph_index| {
            if (glyph_index >= glyph_source_indices.len) continue;
            const source = glyph_source_indices[glyph_index];
            if (source >= self.source_byte_starts.len) continue;
            const byte_start = self.source_byte_starts[source];
            first_byte = if (first_byte) |first|
                @min(first, byte_start)
            else
                byte_start;
            last_byte = @max(last_byte, byte_start);
        }
        if (first_byte) |first| {
            try self.markByteSpan(allocator, first, last_byte);
        }
    }

    /// Protect every source boundary crossed by a positioning relationship.
    /// Pair, cursive, and mark attachment lookups may skip transparent glyphs
    /// between their endpoints, so endpoint indexes—not physical adjacency—
    /// define the complete unsafe span.
    pub fn markGlyphPair(
        self: *SourceBoundaries,
        allocator: std.mem.Allocator,
        glyph_source_indices: []const usize,
        first_glyph: usize,
        second_glyph: usize,
    ) std.mem.Allocator.Error!void {
        if (first_glyph >= glyph_source_indices.len or
            second_glyph >= glyph_source_indices.len)
        {
            return;
        }
        const first_source = glyph_source_indices[first_glyph];
        const second_source = glyph_source_indices[second_glyph];
        if (first_source >= self.source_byte_starts.len or
            second_source >= self.source_byte_starts.len)
        {
            return;
        }
        const first_byte = self.source_byte_starts[first_source];
        const second_byte = self.source_byte_starts[second_source];
        if (first_byte == second_byte) return;

        // The overwhelming PairPos/cursive case is two adjacent shaping
        // sources. There is exactly one source boundary to protect, so avoid
        // the general range-fill machinery and set that bit directly. Source
        // gaps still use the dense span below to cover ignored glyphs.
        if (first_source +| 1 == second_source or
            second_source +| 1 == first_source)
        {
            try self.markByteBoundary(
                allocator,
                @max(first_byte, second_byte),
            );
            return;
        }
        try self.markByteSpan(
            allocator,
            @min(first_byte, second_byte),
            @max(first_byte, second_byte),
        );
    }

    pub fn markMatchedRegions(
        self: *SourceBoundaries,
        allocator: std.mem.Allocator,
        glyph_source_indices: []const usize,
        backtrack: []const usize,
        input: []const usize,
        lookahead: []const usize,
    ) std.mem.Allocator.Error!void {
        var first_byte: ?usize = null;
        var last_byte: usize = 0;
        for ([_][]const usize{ backtrack, input, lookahead }) |region| {
            for (region) |glyph_index| {
                if (glyph_index >= glyph_source_indices.len) continue;
                const source = glyph_source_indices[glyph_index];
                if (source >= self.source_byte_starts.len) continue;
                const byte_start = self.source_byte_starts[source];
                first_byte = if (first_byte) |first|
                    @min(first, byte_start)
                else
                    byte_start;
                last_byte = @max(last_byte, byte_start);
            }
        }
        if (first_byte) |first| {
            try self.markByteSpan(allocator, first, last_byte);
        }
    }

    pub fn isUnsafeBeforeByte(
        self: *const SourceBoundaries,
        byte_offset: usize,
    ) bool {
        if (byte_offset < self.byte_base) {
            return false;
        }
        const local = byte_offset - self.byte_base;
        if (local > self.byte_len) return false;
        if (!self.dense_active) {
            if (local >= @bitSizeOf(u64)) return false;
            const shift: u6 = @intCast(local);
            return (self.inline_boundaries & (@as(u64, 1) << shift)) != 0;
        }
        if (local >= self.unsafe_before_byte.capacity()) return false;
        return self.unsafe_before_byte.isSet(local);
    }

    fn markByteSpan(
        self: *SourceBoundaries,
        allocator: std.mem.Allocator,
        first_byte: usize,
        last_byte: usize,
    ) std.mem.Allocator.Error!void {
        if (first_byte >= last_byte or self.byte_len == 0) return;
        const segment_end = self.byte_base +| self.byte_len;
        if (last_byte <= self.byte_base or first_byte > segment_end) return;

        // Mark every byte offset between the first and last matched source
        // starts. Only real UTF-8/source cluster starts are queried later; the
        // dense bit range is both cheaper to update and also covers ignored
        // glyphs lying between two participating contextual glyphs.
        const first_local = @min(
            (@max(first_byte, self.byte_base) - self.byte_base) +| 1,
            self.byte_len +| 1,
        );
        const end_local = @min(
            (last_byte - self.byte_base) +| 1,
            self.byte_len +| 1,
        );
        if (first_local >= end_local) return;
        if (!self.dense_active and end_local <= @bitSizeOf(u64)) {
            self.inline_boundaries |= inlineRangeMask(
                first_local,
                end_local,
            );
            return;
        }
        try self.ensureDense(allocator);
        self.unsafe_before_byte.setRangeValue(
            .{ .start = first_local, .end = end_local },
            true,
        );
    }

    fn markByteBoundary(
        self: *SourceBoundaries,
        allocator: std.mem.Allocator,
        byte_offset: usize,
    ) std.mem.Allocator.Error!void {
        if (byte_offset <= self.byte_base) return;
        const local = byte_offset - self.byte_base;
        if (local > self.byte_len) return;
        if (!self.dense_active and local < @bitSizeOf(u64)) {
            const shift: u6 = @intCast(local);
            self.inline_boundaries |= @as(u64, 1) << shift;
            return;
        }
        try self.ensureDense(allocator);
        self.unsafe_before_byte.set(local);
    }

    fn ensureDense(
        self: *SourceBoundaries,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        if (self.dense_active) return;
        const required_capacity = self.byte_len +| 1;
        if (self.unsafe_before_byte.capacity() < required_capacity) {
            try self.unsafe_before_byte.resize(
                allocator,
                required_capacity,
                false,
            );
        }
        self.unsafe_before_byte.unsetAll();
        var pending = self.inline_boundaries;
        while (pending != 0) {
            const boundary: usize = @ctz(pending);
            self.unsafe_before_byte.set(boundary);
            pending &= pending - 1;
        }
        self.dense_active = true;
    }

    fn inlineRangeMask(start: usize, end: usize) u64 {
        std.debug.assert(start < end);
        std.debug.assert(end <= @bitSizeOf(u64));
        const below_end = if (end == @bitSizeOf(u64))
            std.math.maxInt(u64)
        else
            (@as(u64, 1) << @as(u6, @intCast(end))) - 1;
        const below_start = if (start == 0)
            0
        else
            (@as(u64, 1) << @as(u6, @intCast(start))) - 1;
        return below_end & ~below_start;
    }
};

test "matched glyphs mark stable UTF-8 byte boundaries" {
    var safety = SourceBoundaries{};
    defer safety.deinit(std.testing.allocator);
    safety.reset(10, 12, &.{ 10, 11, 13, 16, 20 });

    try safety.markMatchedGlyphs(
        std.testing.allocator,
        &.{ 4, 2, 3, 3 },
        &.{ 0, 1, 2, 3 },
    );
    try std.testing.expect(!safety.isUnsafeBeforeByte(12));
    try std.testing.expect(!safety.isUnsafeBeforeByte(13));
    try std.testing.expect(safety.isUnsafeBeforeByte(16));
    try std.testing.expect(safety.isUnsafeBeforeByte(20));
    try std.testing.expect(!safety.isUnsafeBeforeByte(21));
}

test "chaining regions survive synthetic and decomposed source indexes" {
    var safety = SourceBoundaries{};
    defer safety.deinit(std.testing.allocator);
    safety.reset(0, 9, &.{ 0, 2, 2, 5, 5, 8 });

    // Sources 1 and 2 are two shaping-only components of one original scalar;
    // source 3 is a synthetic dotted circle sharing the next scalar's start.
    try safety.markMatchedRegions(
        std.testing.allocator,
        &.{ 0, 1, 2, 3, 4, 5 },
        &.{0},
        &.{ 1, 2, 3, 4 },
        &.{5},
    );
    try std.testing.expect(!safety.isUnsafeBeforeByte(0));
    try std.testing.expect(safety.isUnsafeBeforeByte(2));
    try std.testing.expect(safety.isUnsafeBeforeByte(5));
    try std.testing.expect(safety.isUnsafeBeforeByte(8));
    try std.testing.expect(!safety.isUnsafeBeforeByte(9));
}

test "positioning relationships protect skipped source boundaries" {
    var safety = SourceBoundaries{};
    defer safety.deinit(std.testing.allocator);
    safety.reset(0, 8, &.{ 0, 2, 5, 7 });

    try safety.markGlyphPair(
        std.testing.allocator,
        &.{ 0, 1, 2, 3 },
        0,
        3,
    );
    try std.testing.expect(!safety.isUnsafeBeforeByte(0));
    try std.testing.expect(safety.isUnsafeBeforeByte(2));
    try std.testing.expect(safety.isUnsafeBeforeByte(5));
    try std.testing.expect(safety.isUnsafeBeforeByte(7));
    try std.testing.expect(!safety.isUnsafeBeforeByte(8));
}

test "reset reuses storage without leaking flags into a shorter run" {
    var safety = SourceBoundaries{};
    defer safety.deinit(std.testing.allocator);
    safety.reset(0, 8, &.{ 0, 7 });
    try safety.markMatchedGlyphs(
        std.testing.allocator,
        &.{ 0, 1 },
        &.{ 0, 1 },
    );
    try std.testing.expect(safety.isUnsafeBeforeByte(7));

    safety.reset(20, 2, &.{ 20, 21 });
    try std.testing.expect(!safety.isUnsafeBeforeByte(20));
    try std.testing.expect(!safety.isUnsafeBeforeByte(21));
    try std.testing.expect(!safety.isUnsafeBeforeByte(7));
}
