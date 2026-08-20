//! Trusted accelerated-dispatch identity and capability contracts.

const std = @import("std");
const acceleration = @import("../../../accelerator/root.zig");
const accelerated = @import("../../../execution/lookup/accelerated.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Binding = struct {
    pub fn applyNested(
        _: accelerated.View,
        _: *std.ArrayList(GlyphId),
        _: usize,
        _: u16,
        _: std.mem.Allocator,
        _: accelerated.Options,
    ) accelerated.Error!@import("../../../execution/contextual/model.zig").Change {
        return error.BadGsub;
    }

    pub fn validateNested(
        _: accelerated.View,
        _: usize,
    ) (@import("../../../table/root.zig").coverage.Error ||
        error{ InvalidShapingInput, ShapingLimitExceeded })!void {
        return error.BadGsub;
    }

    pub fn applyChainingLookup(
        _: accelerated.View,
        _: usize,
        _: u16,
        _: *std.ArrayList(GlyphId),
        _: std.mem.Allocator,
        _: u16,
        _: accelerated.Options,
        _: *const accelerated.Lookup,
    ) accelerated.Error!void {
        return error.BadGsub;
    }
};

test "accelerated GSUB dispatch declines missing and foreign sidecars" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);

    const view = accelerated.View{
        .data = &.{},
        .offset = 0,
        .length = 0,
        .assume_validated = true,
    };
    try std.testing.expect(!try accelerated.apply(
        Binding,
        view,
        12,
        0,
        &glyphs,
        allocator,
        .{},
        null,
    ));

    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 24,
        .lookup_type = 4,
        .subtable_count = 1,
    }};
    try std.testing.expect(!try accelerated.apply(
        Binding,
        view,
        12,
        0,
        &glyphs,
        allocator,
        .{ .lookup_accelerators = &sidecars },
        null,
    ));
    try std.testing.expectEqualSlices(GlyphId, &.{7}, glyphs.items);
}

test "accelerated GSUB chaining uses a comptime nested binding" {
    const allocator = std.testing.allocator;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 7);

    // A non-empty approximate digest forces the coverage-chaining path to its
    // statically bound executor. The sentinel error proves this module does
    // not hide recursive dispatch behind an erased runtime callback.
    var digest = @import("../../../../glyph_digest.zig").GlyphDigest.empty();
    digest.add(7);
    const sidecars = [_]acceleration.Lookup{.{
        .lookup_offset = 12,
        .lookup_type = 6,
        .lookup_flag = 0,
        .subtable_count = 1,
        .chaining_coverage_only = true,
        .chaining_input_digest = digest,
    }};
    const view = accelerated.View{
        .data = &.{},
        .offset = 0,
        .length = 0,
        .assume_validated = true,
    };
    try std.testing.expectError(
        error.BadGsub,
        accelerated.apply(
            Binding,
            view,
            12,
            0,
            &glyphs,
            allocator,
            .{ .lookup_accelerators = &sidecars },
            null,
        ),
    );
}
