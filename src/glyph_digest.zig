const std = @import("std");
const GlyphId = @import("glyph.zig").GlyphId;

/// A compact approximate set for glyph coverage prefilters.
///
/// This follows HarfBuzz's hb_set_digest_t shape: three 64-bit bit-pattern
/// masks over different glyph-id shifts. It is intentionally allowed to have
/// false positives, but must not have false negatives.
pub const GlyphDigest = struct {
    const shifts = [_]u6{ 4, 0, 6 };
    const mask_bits: u64 = 64;
    const mask_index_mask: u64 = mask_bits - 1;
    const one: u64 = 1;
    const all: u64 = std.math.maxInt(u64);

    masks: [shifts.len]u64 = [_]u64{0} ** shifts.len,

    pub fn empty() GlyphDigest {
        return .{};
    }

    pub fn full() GlyphDigest {
        return .{ .masks = [_]u64{all} ** shifts.len };
    }

    pub fn isEmpty(self: GlyphDigest) bool {
        return self.masks[0] == 0;
    }

    pub fn add(self: *GlyphDigest, glyph: GlyphId) void {
        const g = @as(u64, glyph);
        inline for (shifts, 0..) |shift, i| {
            const bit: u6 = @intCast((g >> shift) & mask_index_mask);
            self.masks[i] |= one << bit;
        }
    }

    pub fn addRange(self: *GlyphDigest, start: GlyphId, end: GlyphId) void {
        if (end < start) return;
        const a = @as(u64, start);
        const b = @as(u64, end);
        inline for (shifts, 0..) |shift, i| {
            if ((b >> shift) - (a >> shift) >= mask_index_mask) {
                self.masks[i] = all;
            } else {
                const first_bit: u6 = @intCast((a >> shift) & mask_index_mask);
                const last_bit: u6 = @intCast((b >> shift) & mask_index_mask);
                const first = one << first_bit;
                const last = one << last_bit;
                self.masks[i] |= last +% (last -% first) -% @as(u64, @intFromBool(last < first));
            }
        }
    }

    pub fn unionWith(self: *GlyphDigest, other: GlyphDigest) void {
        inline for (0..shifts.len) |i| {
            self.masks[i] |= other.masks[i];
        }
    }

    pub fn words(self: GlyphDigest) [shifts.len]u64 {
        return self.masks;
    }

    pub fn fromWords(words_value: [shifts.len]u64) GlyphDigest {
        return .{ .masks = words_value };
    }

    pub fn mayHave(self: GlyphDigest, glyph: GlyphId) bool {
        const g = @as(u64, glyph);
        inline for (shifts, 0..) |shift, i| {
            const bit: u6 = @intCast((g >> shift) & mask_index_mask);
            if ((self.masks[i] & (one << bit)) == 0) return false;
        }
        return true;
    }

    pub fn mayIntersect(self: GlyphDigest, other: GlyphDigest) bool {
        inline for (0..shifts.len) |i| {
            if ((self.masks[i] & other.masks[i]) == 0) return false;
        }
        return true;
    }
};

test "GlyphDigest tracks individual glyphs" {
    var digest = GlyphDigest.empty();
    try std.testing.expect(digest.isEmpty());
    digest.add(2);
    digest.add(300);
    try std.testing.expect(!digest.isEmpty());
    try std.testing.expect(digest.mayHave(2));
    try std.testing.expect(digest.mayHave(300));
}

test "GlyphDigest tracks ranges and intersections" {
    var range = GlyphDigest.empty();
    range.addRange(10, 12);
    try std.testing.expect(range.mayHave(10));
    try std.testing.expect(range.mayHave(11));
    try std.testing.expect(range.mayHave(12));

    var other = GlyphDigest.empty();
    other.add(200);
    try std.testing.expect(!range.mayIntersect(other));

    other.add(11);
    try std.testing.expect(range.mayIntersect(other));
}
