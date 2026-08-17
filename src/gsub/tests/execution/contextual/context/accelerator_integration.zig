//! Context coverage accelerator root-dispatch integration contracts.
//!
//! This suite proves generic/accelerated parity, authored candidate order,
//! defensive direct-slot validation, and sparse-index fallback together.

const std = @import("std");
const acceleration = @import("../../../../accelerator/root.zig");
const context = @import("../../../../execution/contextual/context/root.zig");
const options = @import("../../../../runtime/options.zig");
const table = @import("../../../../table/root.zig");
const GlyphId = @import("../../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "ContextSubst coverage accelerator preserves order filtering and cardinality" {
            const allocator = std.testing.allocator;
            var bytes = [_]u8{0} ** 140;
            writeTable(&bytes);
            var glyph_classes = [_]u16{0} ** 22;
            glyph_classes[9] = 3;
            const run = options.Options{ .glyph_classes = &glyph_classes };
            const view = table.View{
                .data = &bytes,
                .offset = 0,
                .length = bytes.len,
                .assume_validated = true,
            };
            const context_lookup = 18;

            var generic = std.ArrayList(GlyphId).empty;
            defer generic.deinit(allocator);
            try generic.appendSlice(allocator, &.{ 1, 9, 2, 1, 9, 2 });
            try Bindings.applyLookup(
                view,
                context_lookup,
                &generic,
                allocator,
                run,
            );

            const sidecar = try acceleration.build.lookup.one(
                view,
                context_lookup,
                allocator,
            );
            const sidecars = [_]acceleration.Lookup{sidecar};
            defer acceleration.ownership.deinitContents(
                allocator,
                &sidecars,
            );
            try std.testing.expect(sidecar.context_group_slots.len > 1);
            const slot = sidecar.context_group_slots[1];
            try std.testing.expect(slot != 0);
            try std.testing.expectEqualSlices(
                u16,
                &.{ 0, 1 },
                sidecar.context_groups[slot - 1].subtable_indices,
            );

            var accelerated = std.ArrayList(GlyphId).empty;
            defer accelerated.deinit(allocator);
            try accelerated.appendSlice(
                allocator,
                &.{ 1, 9, 2, 1, 9, 2 },
            );
            try context.acceleratedCoverageLookup(
                Bindings.Executor,
                view,
                &accelerated,
                allocator,
                0x0008,
                .{
                    .glyph_classes = &glyph_classes,
                    .assume_validated = true,
                },
                &sidecar,
            );

            const expected = [_]GlyphId{
                1, 9, 20, 21,
                1, 9, 20, 21,
            };
            try std.testing.expectEqualSlices(
                GlyphId,
                &expected,
                generic.items,
            );
            try std.testing.expectEqualSlices(
                GlyphId,
                &expected,
                accelerated.items,
            );

            try expectCorruptSlotsRejected(
                Bindings,
                view,
                sidecar,
                &glyph_classes,
                allocator,
            );
            try expectSparseFallback(
                Bindings,
                &bytes,
                view,
                context_lookup,
                &glyph_classes,
                allocator,
            );
        }
    };
}

fn expectCorruptSlotsRejected(
    comptime Bindings: type,
    view: table.View,
    sidecar: acceleration.Lookup,
    glyph_classes: []const u16,
    allocator: std.mem.Allocator,
) !void {
    var invalid = sidecar;
    var invalid_index_slots = [_]u16{ 0, 2 };
    invalid.context_group_slots = &invalid_index_slots;
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ 1, 2 });
    try std.testing.expectError(
        error.BadGsub,
        context.acceleratedCoverageLookup(
            Bindings.Executor,
            view,
            &glyphs,
            allocator,
            0x0008,
            .{
                .glyph_classes = glyph_classes,
                .assume_validated = true,
            },
            &invalid,
        ),
    );

    var wrong_key_slots = [_]u16{ 0, 0, 1 };
    invalid.context_group_slots = &wrong_key_slots;
    glyphs.clearRetainingCapacity();
    try glyphs.appendSlice(allocator, &.{ 2, 2 });
    try std.testing.expectError(
        error.BadGsub,
        context.acceleratedCoverageLookup(
            Bindings.Executor,
            view,
            &glyphs,
            allocator,
            0x0008,
            .{
                .glyph_classes = glyph_classes,
                .assume_validated = true,
            },
            &invalid,
        ),
    );
}

fn expectSparseFallback(
    comptime Bindings: type,
    bytes: []u8,
    view: table.View,
    context_lookup: usize,
    glyph_classes: []const u16,
    allocator: std.mem.Allocator,
) !void {
    const high = acceleration.build.context_coverage.max_direct_group_slots;
    writeCoverage1(bytes, 28 + 16, high);
    writeCoverage1(bytes, 56 + 16, high);
    const sidecar = try acceleration.build.lookup.one(
        view,
        context_lookup,
        allocator,
    );
    const sidecars = [_]acceleration.Lookup{sidecar};
    defer acceleration.ownership.deinitContents(allocator, &sidecars);
    try std.testing.expectEqual(
        @as(usize, 0),
        sidecar.context_group_slots.len,
    );

    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.appendSlice(allocator, &.{ high, 9, 2 });
    try context.acceleratedCoverageLookup(
        Bindings.Executor,
        view,
        &glyphs,
        allocator,
        0x0008,
        .{
            .glyph_classes = glyph_classes,
            .assume_validated = true,
        },
        &sidecar,
    );
    try std.testing.expectEqualSlices(
        GlyphId,
        &.{ high, 9, 20, 21 },
        glyphs.items,
    );
}

fn writeTable(bytes: []u8) void {
    writeU32(bytes, 0, 0x00010000);
    writeU16(bytes, 8, 10);
    writeU16(bytes, 10, 3);
    writeU16(bytes, 12, 8);
    writeU16(bytes, 14, 74);
    writeU16(bytes, 16, 106);

    const lookup = 18;
    writeU16(bytes, lookup, 5);
    writeU16(bytes, lookup + 2, 0x0008);
    writeU16(bytes, lookup + 4, 2);
    writeU16(bytes, lookup + 6, 10);
    writeU16(bytes, lookup + 8, 38);
    writeCoverageContext(bytes, 28, 1, 1);
    writeCoverageContext(bytes, 56, 0, 2);

    const multiple_lookup = 84;
    writeU16(bytes, multiple_lookup, 2);
    writeU16(bytes, multiple_lookup + 4, 1);
    writeU16(bytes, multiple_lookup + 6, 8);
    const multiple = 92;
    writeU16(bytes, multiple, 1);
    writeU16(bytes, multiple + 2, 12);
    writeU16(bytes, multiple + 4, 1);
    writeU16(bytes, multiple + 6, 18);
    writeCoverage1(bytes, multiple + 12, 2);
    writeU16(bytes, multiple + 18, 2);
    writeU16(bytes, multiple + 20, 20);
    writeU16(bytes, multiple + 22, 21);
    writeSingleDeltaLookup(bytes, 116, 1, 10);
}

fn writeCoverageContext(
    bytes: []u8,
    offset: usize,
    sequence_index: u16,
    nested_lookup: u16,
) void {
    writeU16(bytes, offset, 3);
    writeU16(bytes, offset + 2, 2);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 16);
    writeU16(bytes, offset + 8, 22);
    writeU16(bytes, offset + 10, sequence_index);
    writeU16(bytes, offset + 12, nested_lookup);
    writeCoverage1(bytes, offset + 16, 1);
    writeCoverage1(bytes, offset + 22, 2);
}

fn writeSingleDeltaLookup(
    bytes: []u8,
    offset: usize,
    glyph: GlyphId,
    delta: i16,
) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 4, 1);
    writeU16(bytes, offset + 6, 8);
    writeU16(bytes, offset + 8, 1);
    writeU16(bytes, offset + 10, 6);
    writeI16(bytes, offset + 12, delta);
    writeCoverage1(bytes, offset + 14, glyph);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: GlyphId) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
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
