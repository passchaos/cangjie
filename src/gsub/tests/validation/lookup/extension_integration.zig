//! ExtensionSubst Offset32 execution-chain integration contracts.
//!
//! Lookup validation owns normal preflight. These tests intentionally enter
//! lower shaping and nested-execution helpers directly to prove malicious
//! wrappers still fail before mutating glyphs when callers bypass that layer.

const std = @import("std");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub fn suite(comptime Bindings: type) type {
    return struct {
        test "GSUB low-level extension paths reject escaping payloads atomically" {
            var bytes = [_]u8{0} ** 8;
            writeExtension(&bytes, 0xffff_fffe);
            try expectExtensionRejection(Bindings, &bytes);
        }

        test "GSUB low-level extension paths reject wrapper-header aliases atomically" {
            var bytes = [_]u8{0} ** 8;
            // In-range as a byte address, but inside the wrapper's fixed
            // ExtensionOffset field rather than at a child subtable.
            writeExtension(&bytes, 4);
            try expectExtensionRejection(Bindings, &bytes);
        }
    };
}

fn expectExtensionRejection(
    comptime Bindings: type,
    bytes: []const u8,
) !void {
    const allocator = std.testing.allocator;
    const view = table.View{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
    };
    var glyphs = std.ArrayList(GlyphId).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);

    try std.testing.expectError(
        error.BadGsub,
        Bindings.payload(view, 0, 1),
    );
    try std.testing.expectError(
        error.BadGsub,
        Bindings.validate(view, 0),
    );
    try std.testing.expectError(
        error.BadGsub,
        Bindings.apply(
            view,
            0,
            &glyphs,
            allocator,
            0,
            .{},
        ),
    );
    try std.testing.expectError(
        error.BadGsub,
        Bindings.applyNested(
            view,
            0,
            &glyphs,
            0,
            allocator,
            0,
            .{},
        ),
    );
    try std.testing.expectEqualSlices(GlyphId, &.{5}, glyphs.items);
}

fn writeExtension(bytes: []u8, payload: u32) void {
    std.mem.writeInt(u16, bytes[0..2], 1, .big);
    std.mem.writeInt(u16, bytes[2..4], 1, .big);
    std.mem.writeInt(u32, bytes[4..8], payload, .big);
}
