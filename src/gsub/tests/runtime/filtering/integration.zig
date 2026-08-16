//! LookupFlag/GDEF execution-chain integration contracts.
//!
//! Policy primitives are tested in `runtime/filtering.zig`; this suite proves
//! direct, accelerated, and ExtensionSubst lookup paths carry that policy into
//! actual glyph mutation. Root lookup entry points are bound statically.

const std = @import("std");
const acceleration = @import("../../../accelerator/root.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB execution uses MarkAttachClassDef without glyph classes" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 24;
            writeLookup(&bytes, 1, 0x0100, 8, null);
            writeSingleDelta(&bytes, 8, &.{ 5, 7, 8 }, 10);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 5, 7, 8 });
            var attach_classes = [_]u16{0} ** 9;
            attach_classes[5] = 2;
            attach_classes[7] = 1;

            try Bindings.applyLookup(
                view(&bytes, false),
                0,
                &glyphs,
                allocator,
                .{ .mark_attach_classes = &attach_classes },
            );

            // Attachment classes classify marks even when GlyphClassDef is
            // absent; class-zero ordinary glyphs remain visible.
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 5, 17, 18 },
                glyphs.items,
            );
        }

        test "GSUB direct and accelerated lookup honor mark filtering sets" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 22;
            writeLookup(&bytes, 1, 0x0010, 10, 1);
            writeSingleDelta(&bytes, 10, &.{5}, 10);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 5, 7 });
            const mark_sets = [_][]const GlyphId{ &.{7}, &.{5} };

            try Bindings.applyLookup(
                view(&bytes, false),
                0,
                &glyphs,
                allocator,
                .{ .mark_filtering_sets = &mark_sets },
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 15, 7 },
                glyphs.items,
            );

            // Validated fonts consume decoded variable-header metadata from
            // the exact sidecar instead of reparsing LookupFlag fields.
            glyphs.items[0] = 5;
            const sidecar = try acceleration.build.lookup.one(
                view(&bytes, true),
                0,
                allocator,
            );
            const sidecars = [_]acceleration.Lookup{sidecar};
            defer acceleration.ownership.deinitContents(
                allocator,
                &sidecars,
            );
            try Bindings.applyLookupWithIndex(
                view(&bytes, true),
                0,
                0,
                &glyphs,
                allocator,
                .{
                    .mark_filtering_sets = &mark_sets,
                    .lookup_accelerators = &sidecars,
                    .assume_validated = true,
                },
                null,
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 15, 7 },
                glyphs.items,
            );
        }

        test "GSUB execution rejects a missing mark filtering set atomically" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 22;
            writeLookup(&bytes, 1, 0x0010, 10, 1);
            writeSingleDelta(&bytes, 10, &.{5}, 10);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 5);
            const mark_sets = [_][]const GlyphId{&.{5}};

            try std.testing.expectError(
                error.BadGsub,
                Bindings.applyLookup(
                    view(&bytes, false),
                    0,
                    &glyphs,
                    allocator,
                    .{ .mark_filtering_sets = &mark_sets },
                ),
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{5},
                glyphs.items,
            );
        }

        test "GSUB execution combines mark set and attachment filtering" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 26;
            writeLookup(&bytes, 1, 0x0210, 10, 0);
            writeSingleDelta(&bytes, 10, &.{ 5, 7 }, 10);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.appendSlice(allocator, &.{ 5, 7 });
            var glyph_classes = [_]u16{0} ** 8;
            glyph_classes[5] = 3;
            glyph_classes[7] = 3;
            var attach_classes = [_]u16{0} ** 8;
            attach_classes[5] = 1;
            attach_classes[7] = 2;
            const mark_sets = [_][]const GlyphId{&.{ 5, 7 }};

            try Bindings.applyLookup(
                view(&bytes, false),
                0,
                &glyphs,
                allocator,
                .{
                    .glyph_classes = &glyph_classes,
                    .mark_attach_classes = &attach_classes,
                    .mark_filtering_sets = &mark_sets,
                },
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{ 5, 17 },
                glyphs.items,
            );
        }

        test "GSUB extension execution preserves wrapper LookupFlag" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 28;
            writeLookup(&bytes, 7, 0x0008, 8, null);
            writeU16(&bytes, 8, 1);
            writeU16(&bytes, 10, 1);
            writeU32(&bytes, 12, 8);
            writeSingleDelta(&bytes, 16, &.{3}, 1);

            var glyphs = std.ArrayList(GlyphId).empty;
            defer glyphs.deinit(allocator);
            try glyphs.append(allocator, 3);
            const glyph_classes = [_]u16{ 0, 1, 2, 3 };

            try Bindings.applyLookup(
                view(&bytes, false),
                0,
                &glyphs,
                allocator,
                .{ .glyph_classes = &glyph_classes },
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &.{3},
                glyphs.items,
            );
        }
    };
}

fn view(bytes: []const u8, assume_validated: bool) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = assume_validated,
    };
}

fn writeLookup(
    bytes: []u8,
    lookup_type: u16,
    flag: u16,
    subtable_offset: u16,
    mark_set: ?u16,
) void {
    writeU16(bytes, 0, lookup_type);
    writeU16(bytes, 2, flag);
    writeU16(bytes, 4, 1);
    writeU16(bytes, 6, subtable_offset);
    if (mark_set) |index| writeU16(bytes, 8, index);
}

fn writeSingleDelta(
    bytes: []u8,
    offset: usize,
    glyphs: []const GlyphId,
    delta: i16,
) void {
    const coverage = offset + 6;
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 6);
    writeI16(bytes, offset + 4, delta);
    writeU16(bytes, coverage, 1);
    writeU16(bytes, coverage + 2, @intCast(glyphs.len));
    for (glyphs, 0..) |glyph, index| {
        writeU16(bytes, coverage + 4 + index * 2, glyph);
    }
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    writeU16(bytes, offset, @bitCast(value));
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
