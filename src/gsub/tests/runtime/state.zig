//! GSUB run-lifetime state preparation contracts.

const std = @import("std");
const acceleration = @import("../../accelerator/root.zig");
const state = @import("../../runtime/state.zig");
const table = @import("../../table/root.zig");

test "run state shares limits and leaves digest policy to table binding" {
    var storage = state.Storage{};
    const plain = try state.prepare(.{}, 3, &storage);
    try std.testing.expect(plain.operations_left != null);
    try std.testing.expect(plain.max_glyph_count != null);
    try std.testing.expect(plain.glyph_mutation_generation == null);
}

test "table-bound state ignores foreign accelerator cache policy" {
    var bytes = [_]u8{0} ** 10;
    var storage = state.Storage{};
    const sidecars = [_]acceleration.Lookup{.{
        .table_uses_run_digest_cache = true,
    }};
    const prepared = try state.prepareForTable(
        table.View{
            .data = &bytes,
            .offset = 0,
            .length = bytes.len,
            .assume_validated = true,
        },
        .{ .lookup_accelerators = &sidecars },
        3,
        &storage,
    );
    try std.testing.expect(prepared.glyph_mutation_generation == null);
}
