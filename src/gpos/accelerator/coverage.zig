//! Owned Coverage sidecars for repeatedly probed GPOS subtables.

const std = @import("std");
const GlyphId = @import("../../glyph.zig").GlyphId;
const layout = @import("../../opentype/layout.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;
const max_direct_glyphs = 4096;

pub const Owned = union(enum) {
    glyphs: []const GlyphId,
    ranges: []const layout.GlyphRangeRecord,
    direct: []const u16,

    pub fn build(
        view: View,
        coverage_offset: usize,
        allocator: std.mem.Allocator,
    ) (Error || std.mem.Allocator.Error)!Owned {
        return switch (try view.readU16(coverage_offset)) {
            1 => coverage: {
                const count = try view.readU16(coverage_offset + 2);
                const glyphs = try allocator.alloc(GlyphId, count);
                errdefer allocator.free(glyphs);
                for (glyphs, 0..) |*glyph, glyph_index| {
                    glyph.* = try view.readU16(
                        coverage_offset + 4 + glyph_index * 2,
                    );
                }
                break :coverage try buildDirectFromGlyphs(
                    glyphs,
                    allocator,
                ) orelse .{ .glyphs = glyphs };
            },
            2 => coverage: {
                const count = try view.readU16(coverage_offset + 2);
                const ranges =
                    try allocator.alloc(layout.GlyphRangeRecord, count);
                errdefer allocator.free(ranges);
                for (ranges, 0..) |*range, range_index| {
                    const record = coverage_offset + 4 + range_index * 6;
                    range.* = .{
                        .start = try view.readU16(record),
                        .end = try view.readU16(record + 2),
                        .value = try view.readU16(record + 4),
                    };
                }
                break :coverage try buildDirectFromRanges(
                    ranges,
                    allocator,
                ) orelse .{ .ranges = ranges };
            },
            else => error.UnsupportedGpos,
        };
    }

    /// Build a sequence of required Offset16 Coverage children.
    ///
    /// The returned slice and every Coverage payload belong to `allocator`.
    pub fn buildSequence(
        view: View,
        base_offset: usize,
        offsets_pos: usize,
        count: usize,
        allocator: std.mem.Allocator,
    ) (Error || std.mem.Allocator.Error)![]const Owned {
        const coverages = try allocator.alloc(Owned, count);
        var built_count: usize = 0;
        errdefer {
            for (coverages[0..built_count]) |coverage| {
                coverage.deinit(allocator);
            }
            allocator.free(coverages);
        }
        for (coverages, 0..) |*coverage, coverage_index| {
            const coverage_offset = try table.offset.required16(
                view,
                base_offset,
                try view.readU16(offsets_pos + coverage_index * 2),
            );
            coverage.* = try build(view, coverage_offset, allocator);
            built_count += 1;
        }
        return coverages;
    }

    pub fn deinit(self: Owned, allocator: std.mem.Allocator) void {
        switch (self) {
            inline else => |items| allocator.free(items),
        }
    }

    pub fn deinitSequence(
        coverages: []const Owned,
        allocator: std.mem.Allocator,
    ) void {
        for (coverages) |coverage| coverage.deinit(allocator);
        allocator.free(coverages);
    }

    pub fn index(self: Owned, glyph: GlyphId) ?usize {
        switch (self) {
            .glyphs => |glyphs| {
                var low: usize = 0;
                var high = glyphs.len;
                while (low < high) {
                    const middle = low + (high - low) / 2;
                    if (glyph < glyphs[middle]) {
                        high = middle;
                    } else if (glyph > glyphs[middle]) {
                        low = middle + 1;
                    } else {
                        return middle;
                    }
                }
                return null;
            },
            .ranges => |ranges| {
                var low: usize = 0;
                var high = ranges.len;
                while (low < high) {
                    const middle = low + (high - low) / 2;
                    if (glyph <= ranges[middle].end) {
                        high = middle;
                    } else {
                        low = middle + 1;
                    }
                }
                if (low >= ranges.len or glyph < ranges[low].start) return null;
                return @as(usize, ranges[low].value) +
                    (@as(usize, glyph) - ranges[low].start);
            },
            .direct => |indexes| {
                if (glyph >= indexes.len) return null;
                const one_based = indexes[glyph];
                return if (one_based == 0) null else one_based - 1;
            },
        }
    }
};

fn buildDirectFromGlyphs(
    glyphs: []const GlyphId,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!?Owned {
    if (glyphs.len == 0 or glyphs.len > std.math.maxInt(u16)) return null;
    const last: usize = glyphs[glyphs.len - 1];
    if (last >= max_direct_glyphs) return null;
    const direct = try allocator.alloc(u16, last + 1);
    @memset(direct, 0);
    for (glyphs, 0..) |glyph, index| direct[glyph] = @intCast(index + 1);
    allocator.free(glyphs);
    return .{ .direct = direct };
}

fn buildDirectFromRanges(
    ranges: []const layout.GlyphRangeRecord,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!?Owned {
    if (ranges.len == 0) return null;
    const last: usize = ranges[ranges.len - 1].end;
    if (last >= max_direct_glyphs) return null;
    const direct = try allocator.alloc(u16, last + 1);
    @memset(direct, 0);
    for (ranges) |range| {
        var glyph: usize = range.start;
        while (glyph <= range.end) : (glyph += 1) {
            const index = @as(usize, range.value) + glyph - range.start;
            if (index >= std.math.maxInt(u16)) {
                allocator.free(direct);
                return null;
            }
            direct[glyph] = @intCast(index + 1);
        }
    }
    allocator.free(ranges);
    return .{ .direct = direct };
}
