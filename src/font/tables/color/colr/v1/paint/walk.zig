//! Shared structural traversal of COLR v1 Paint DAGs.

const std = @import("std");

const bin = @import("../../../../../../binary.zig");
const bases = @import("../bases.zig");
const core = @import("core.zig");
const guard_mod = @import("guard.zig");
const layers = @import("../layers.zig");
const types = @import("types.zig");

/// Visit every Paint record reachable from one root.
///
/// The walker owns structural concerns shared by all semantic passes: record
/// grammar, typed-byte ownership, recursion limits, LayerList expansion, and
/// both Composite children. `visitor.visit` runs after those proofs and before
/// descendants, so it can safely inspect the complete current record while
/// retaining its own narrow semantic state.
pub fn walk(
    data: []const u8,
    table: types.Table,
    offset: usize,
    visitor: anytype,
) types.Error!void {
    var guard = guard_mod.Guard{};
    return walkRecord(data, table, offset, &guard, visitor);
}

/// Visit every BaseGlyphList and LayerList root, resetting graph-local
/// recursion and ownership state between roots. Root headers may be shared,
/// while each independently reachable DAG still receives complete validation.
pub fn walkAll(
    data: []const u8,
    table: types.Table,
    visitor: anytype,
) types.Error!void {
    return walkAllWithForbiddenRange(data, table, null, visitor);
}

/// Walk all roots while rejecting Paint payloads that overlap an externally
/// owned byte range, such as COLR's variation-map/store payload.
pub fn walkAllWithForbiddenRange(
    data: []const u8,
    table: types.Table,
    forbidden_range: ?types.Range,
    visitor: anytype,
) types.Error!void {
    if (try bases.read(data, table)) |base_list| {
        for (0..base_list.record_count) |index| {
            var guard = guard_mod.Guard{
                .forbidden_range = forbidden_range,
            };
            try walkRecord(
                data,
                table,
                try bases.paintOffsetAt(data, table, base_list, index),
                &guard,
                visitor,
            );
        }
    }
    if (try layers.read(data, table)) |layer_list| {
        for (0..layer_list.layer_count) |index| {
            var guard = guard_mod.Guard{
                .forbidden_range = forbidden_range,
            };
            try walkRecord(
                data,
                table,
                try layers.paintOffset(
                    data,
                    table,
                    layer_list,
                    @intCast(index),
                ),
                &guard,
                visitor,
            );
        }
    }
}

/// Validate one complete Paint graph when no additional record semantics are
/// needed. Public lazy entry points use this to re-establish the same graph
/// grammar and ownership invariants as parse-time semantic passes.
pub fn validate(
    data: []const u8,
    table: types.Table,
    offset: usize,
) types.Error!void {
    var visitor = ValidationVisitor{};
    return walk(data, table, offset, &visitor);
}

fn walkRecord(
    data: []const u8,
    table: types.Table,
    offset: usize,
    guard: *guard_mod.Guard,
    visitor: anytype,
) types.Error!void {
    const info = try core.validateRecord(data, table, offset);
    try guard.enter(offset);
    defer guard.leave();
    try guard.claimPaintRecord(data, table, offset, info);

    try visitor.visit(data, table, offset, info);
    switch (info.kind) {
        .colr_layers => try walkLayers(
            data,
            table,
            offset,
            guard,
            visitor,
        ),
        .glyph, .single_child => try walkRecord(
            data,
            table,
            try core.childOffset(
                data,
                table,
                offset,
                info.min_size,
                1,
            ),
            guard,
            visitor,
        ),
        .composite => {
            try walkRecord(
                data,
                table,
                try core.childOffset(
                    data,
                    table,
                    offset,
                    info.min_size,
                    1,
                ),
                guard,
                visitor,
            );
            try walkRecord(
                data,
                table,
                try core.childOffset(
                    data,
                    table,
                    offset,
                    info.min_size,
                    5,
                ),
                guard,
                visitor,
            );
        },
        .solid, .colr_glyph, .color_line, .terminal => {},
    }
}

fn walkLayers(
    data: []const u8,
    table: types.Table,
    offset: usize,
    guard: *guard_mod.Guard,
    visitor: anytype,
) types.Error!void {
    const layer_count: usize = data[offset + 1];
    if (layer_count == 0) return;
    const first_layer_index: usize =
        @intCast(try bin.readU32At(data, offset + 2));
    const list = (try layers.read(data, table)) orelse return error.BadSfnt;
    if (first_layer_index > list.layer_count or
        layer_count > list.layer_count - first_layer_index)
    {
        return error.BadSfnt;
    }
    for (0..layer_count) |relative_index| {
        try walkRecord(
            data,
            table,
            try layers.paintOffset(
                data,
                table,
                list,
                @intCast(first_layer_index + relative_index),
            ),
            guard,
            visitor,
        );
    }
}

const ValidationVisitor = struct {
    pub fn visit(
        _: *const ValidationVisitor,
        _: []const u8,
        _: types.Table,
        _: usize,
        _: types.FormatInfo,
    ) types.Error!void {}
};

test "walker follows layers and both composite branches" {
    var bytes: [96]u8 = .{0} ** 96;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 18, 34);
    writeU32(&bytes, 34, 2);
    writeU32(&bytes, 38, 12);
    writeU32(&bytes, 42, 17);
    bytes[46] = 2;
    writeI16(&bytes, 49, 0x4000);
    bytes[51] = 32;
    writeU24(&bytes, 52, 8);
    bytes[55] = 3;
    writeU24(&bytes, 56, 13);
    bytes[59] = 2;
    writeI16(&bytes, 62, 0x4000);
    bytes[64] = 11;
    writeU16(&bytes, 65, 1);
    bytes[70] = 1;
    bytes[71] = 2;
    writeU32(&bytes, 72, 0);

    const Visitor = struct {
        count: usize = 0,

        pub fn visit(
            self: *@This(),
            _: []const u8,
            _: types.Table,
            _: usize,
            _: types.FormatInfo,
        ) types.Error!void {
            self.count += 1;
        }
    };
    var visitor = Visitor{};
    try walk(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        70,
        &visitor,
    );
    try std.testing.expectEqual(@as(usize, 5), visitor.count);
}

test "all-roots walk covers BaseGlyphList and LayerList" {
    var bytes: [64]u8 = .{0} ** 64;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 18, 49);

    writeU32(&bytes, 34, 1);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 10);
    bytes[44] = 2;
    writeI16(&bytes, 47, 0x4000);

    writeU32(&bytes, 49, 1);
    writeU32(&bytes, 53, 8);
    bytes[57] = 11;
    writeU16(&bytes, 58, 1);

    const Visitor = struct {
        count: usize = 0,

        pub fn visit(
            self: *@This(),
            _: []const u8,
            _: types.Table,
            _: usize,
            _: types.FormatInfo,
        ) types.Error!void {
            self.count += 1;
        }
    };
    var visitor = Visitor{};
    try walkAll(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        &visitor,
    );
    try std.testing.expectEqual(@as(usize, 2), visitor.count);
}

test "all-roots walk resets ownership state for shared roots" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 2);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 16);
    writeU16(&bytes, 44, 2);
    writeU32(&bytes, 46, 16);
    bytes[50] = 2;
    writeI16(&bytes, 53, 0x4000);

    var visitor = ValidationVisitor{};
    try walkAll(
        &bytes,
        .{ .offset = 0, .length = bytes.len },
        &visitor,
    );
}

test "all-roots walk applies forbidden ownership to every root" {
    var bytes: [56]u8 = .{0} ** 56;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 14, 34);
    writeU32(&bytes, 34, 1);
    writeU16(&bytes, 38, 1);
    writeU32(&bytes, 40, 10);
    bytes[44] = 2;
    writeI16(&bytes, 47, 0x4000);

    var visitor = ValidationVisitor{};
    try std.testing.expectError(
        error.BadSfnt,
        walkAllWithForbiddenRange(
            &bytes,
            .{ .offset = 0, .length = bytes.len },
            .{ .start = 44, .end = 49 },
            &visitor,
        ),
    );
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeI16(bytes: []u8, offset: usize, value: i16) void {
    std.mem.writeInt(i16, bytes[offset..][0..2], value, .big);
}

fn writeU24(bytes: []u8, offset: usize, value: u32) void {
    bytes[offset] = @intCast((value >> 16) & 0xff);
    bytes[offset + 1] = @intCast((value >> 8) & 0xff);
    bytes[offset + 2] = @intCast(value & 0xff);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}
