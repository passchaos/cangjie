//! Public GSUB orchestration metadata-preflight contracts.
//!
//! Low-level cardinality rules live in `runtime/metadata.zig`. This suite binds
//! the public apply orchestrator statically to prove malformed sidecars are
//! rejected before table traversal or glyph mutation.

const std = @import("std");
const ligature_provenance = @import("../../../ligature_provenance.zig");
const GlyphId = @import("../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB public apply rejects mismatched source metadata atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 10;
            writeU16(&bytes, 0, 1);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 1, 2 });
            var sources = std.ArrayList(usize).empty;
            defer sources.deinit(allocator);
            try sources.append(allocator, 0);

            try std.testing.expectError(
                error.InvalidShapingInput,
                Bindings.apply(
                    &bytes,
                    0,
                    bytes.len,
                    &glyphs,
                    allocator,
                    .{ .glyph_source_indices = &sources },
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 1, 2 },
                glyphs.items,
            );
        }

        test "GSUB public apply rejects malformed ligature provenance atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 10;
            writeU16(&bytes, 0, 1);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 10);
            var provenance = ligature_provenance.Store{};
            defer provenance.deinit(allocator);
            // A ligature component list must be source-monotone. Construct the
            // malformed detached store directly because its normal builders
            // assert that invariant before publication.
            try provenance.sources.appendSlice(allocator, &.{ 3, 2 });
            try provenance.infos.append(
                allocator,
                .{ .component_count = 2 },
            );

            try std.testing.expectError(
                error.InvalidShapingInput,
                Bindings.apply(
                    &bytes,
                    0,
                    bytes.len,
                    &glyphs,
                    allocator,
                    .{ .ligature_components = &provenance },
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{10},
                glyphs.items,
            );
        }
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
