//! GSUB run-lifetime state preparation contracts.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");
const state = @import("../../runtime/state.zig");

test "run state shares limits and enables digest generation only when useful" {
    var storage = state.Storage{};
    const plain = try state.prepare(.{}, 3, &storage);
    try std.testing.expect(plain.operations_left != null);
    try std.testing.expect(plain.max_glyph_count != null);
    try std.testing.expect(plain.glyph_mutation_generation == null);

    const sidecars = [_]acceleration.Lookup{.{
        .table_uses_run_digest_cache = true,
    }};
    var cached_storage = state.Storage{};
    const cached = try state.prepare(
        .{ .lookup_accelerators = &sidecars },
        3,
        &cached_storage,
    );
    try std.testing.expect(cached.glyph_mutation_generation != null);
    try std.testing.expectEqual(
        @as(usize, 0),
        cached.glyph_mutation_generation.?.*,
    );
}
