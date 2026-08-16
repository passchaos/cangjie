//! Coverage lookup prefilter contracts.

const std = @import("std");
const accelerator =
    @import("../../../../../../accelerator/root.zig");
const GlyphDigest = @import("../../../../../../../glyph_digest.zig").GlyphDigest;
const lookup =
    @import("../../../../../../runtime/lookup/contextual/chaining/coverage/lookup.zig");

test "chaining glyph digest activates only for amortized runs" {
    var digest = GlyphDigest.empty();
    digest.add(20);
    try std.testing.expect(!digest.mayHave(21));
    try std.testing.expect(!lookup.usesGlyphDigest(15));
    try std.testing.expect(lookup.usesGlyphDigest(16));

    // Digest collisions are allowed; exact candidate groups remain
    // authoritative after the approximate prefilter.
    var collision: ?u16 = null;
    var glyph: usize = 0;
    while (glyph <= std.math.maxInt(u16)) : (glyph += 1) {
        const candidate: u16 = @intCast(glyph);
        if (candidate != 20 and digest.mayHave(candidate)) {
            collision = candidate;
            break;
        }
    }
    try std.testing.expect(collision != null);
    const groups = [_]accelerator.glyph_groups.Group{
        .{ .glyph = 20, .subtable_indices = &.{0} },
    };
    try std.testing.expect(
        accelerator.glyph_groups.find(&groups, &.{}, collision.?) == null,
    );
}
