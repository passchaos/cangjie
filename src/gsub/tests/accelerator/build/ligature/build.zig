//! LigatureSubst owned-model builder contracts.

const std = @import("std");
const ligature = @import("../../../../accelerator/build/ligature/root.zig");
const table = @import("../../../../table/root.zig");

test "ligature builder preserves authored definition preference" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 42;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 34);
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, 8);

    writeU16(&bytes, 8, 2);
    writeU16(&bytes, 10, 6);
    writeU16(&bytes, 12, 14);
    writeU16(&bytes, 14, 40);
    writeU16(&bytes, 16, 2);
    writeU16(&bytes, 18, 2);
    writeU16(&bytes, 22, 50);
    writeU16(&bytes, 24, 3);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 3);
    writeCoverage1(&bytes, 34, 1);

    const result = try ligature.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer {
        allocator.free(result.components);
        allocator.free(result.definitions);
        allocator.free(result.set_slots);
        allocator.free(result.sets);
    }

    try std.testing.expectEqual(@as(usize, 1), result.sets.len);
    try std.testing.expectEqual(@as(usize, 2), result.definitions.len);
    try std.testing.expectEqual(@as(u16, 40), result.definitions[0].ligature);
    try std.testing.expectEqualSlices(
        u16,
        &.{ 2, 2, 3 },
        result.components[0..3],
    );
    try std.testing.expectEqualSlices(
        u16,
        &.{2},
        ligature.requiredSecondComponents(result),
    );
    try std.testing.expect(result.first_component_digest.mayHave(1));
    try std.testing.expectEqual(
        result.sets[0],
        ligature.index.find(result.sets, result.set_slots, 1).?,
    );
}

test "builder appends a sorted exact index for few required seconds" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 60;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 50);
    writeU16(&bytes, 4, 3);
    writeU16(&bytes, 6, 12);
    writeU16(&bytes, 8, 22);
    writeU16(&bytes, 10, 40);

    writeU16(&bytes, 12, 1);
    writeU16(&bytes, 14, 4);
    writeTwoComponentLigature(&bytes, 16, 40, 9);

    writeU16(&bytes, 22, 2);
    writeU16(&bytes, 24, 6);
    writeU16(&bytes, 26, 12);
    writeTwoComponentLigature(&bytes, 28, 50, 7);
    writeTwoComponentLigature(&bytes, 34, 51, 9);

    writeU16(&bytes, 40, 1);
    writeU16(&bytes, 42, 4);
    writeTwoComponentLigature(&bytes, 44, 60, 8);

    writeU16(&bytes, 50, 1);
    writeU16(&bytes, 52, 3);
    writeU16(&bytes, 54, 1);
    writeU16(&bytes, 56, 2);
    writeU16(&bytes, 58, 3);

    const result = try ligature.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer {
        allocator.free(result.components);
        allocator.free(result.definitions);
        allocator.free(result.set_slots);
        allocator.free(result.sets);
    }

    // The first four values remain the authored definition payload; only the
    // sorted, deduplicated tail belongs to the optional exact prefilter.
    try std.testing.expectEqualSlices(
        u16,
        &.{ 9, 7, 9, 8, 7, 8, 9 },
        result.components,
    );
    try std.testing.expectEqual(@as(u32, 4), result.required_second_start);
    try std.testing.expectEqual(@as(u16, 3), result.required_second_len);
    try std.testing.expectEqualSlices(
        u16,
        &.{ 7, 8, 9 },
        ligature.requiredSecondComponents(result),
    );
    try std.testing.expect(!ligature.requiredSecondUsesDigest(result));
    try std.testing.expect(!result.prefilter_second);
    for (result.definitions, &[_]u16{ 9, 7, 9, 8 }) |definition, second| {
        try std.testing.expectEqual(
            second,
            result.components[definition.component_start],
        );
    }
}

test "required second range rejects stale bounds" {
    try std.testing.expectEqual(
        @as(usize, 0),
        ligature.requiredSecondComponents(.{
            .components = &.{ 1, 2 },
            .required_second_start = 2,
            .required_second_len = 1,
        }).len,
    );
}

test "required second range rejects noncanonical exact metadata" {
    try std.testing.expectEqual(
        @as(usize, 0),
        ligature.requiredSecondComponents(.{
            .components = &.{ 1, 3, 2 },
            .required_second_start = 1,
            .required_second_len = 2,
        }).len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        ligature.requiredSecondComponents(.{
            .components = &([_]u16{1} **
                (ligature.max_exact_required_seconds + 1)),
            .required_second_start = 0,
            .required_second_len = ligature.max_exact_required_seconds + 1,
        }).len,
    );
}

test "required second digest survives compact component storage" {
    const digest = ligature.requiredSecondDigest(.{
        .components = &.{
            0x0001, 0, 0, 0,
            0x0004, 0, 0, 0,
            0x0001, 0, 0, 0,
        },
        .required_second_start = 0,
        .required_second_len = 0x800c,
    }).?;
    try std.testing.expect(digest.mayHave(2));
    try std.testing.expect(!digest.mayHave(3));
}

test "builder keeps digest encoding for high competition" {
    const allocator = std.testing.allocator;
    const definition_count = ligature.min_competing_for_required_second + 1;
    const header_len = 8;
    const set_len = 2 + definition_count * 2;
    const definitions_start = header_len + set_len;
    const coverage_start = definitions_start + definition_count * 6;
    var bytes: [coverage_start + 6]u8 = @splat(0);

    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, @intCast(coverage_start));
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, @intCast(header_len));
    writeU16(&bytes, header_len, @intCast(definition_count));
    for (0..definition_count) |index| {
        const definition_offset = definitions_start + index * 6;
        writeU16(
            &bytes,
            header_len + 2 + index * 2,
            @intCast(definition_offset - header_len),
        );
        writeTwoComponentLigature(
            &bytes,
            definition_offset,
            @intCast(1000 + index),
            @intCast(20 + index % 4),
        );
    }
    writeCoverage1(&bytes, coverage_start, 1);

    const result = try ligature.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer {
        allocator.free(result.components);
        allocator.free(result.definitions);
        allocator.free(result.set_slots);
        allocator.free(result.sets);
    }

    try std.testing.expect(ligature.requiredSecondUsesDigest(result));
    try std.testing.expectEqual(
        @as(u32, @intCast(definition_count)),
        result.required_second_start,
    );
    try std.testing.expectEqual(
        definition_count + 12,
        result.components.len,
    );
    const digest = ligature.requiredSecondDigest(result).?;
    for (20..24) |second| {
        try std.testing.expect(digest.mayHave(@intCast(second)));
    }
    try std.testing.expect(!result.prefilter_second);
}

test "builder keeps generic policy above the exact cardinality cap" {
    const allocator = std.testing.allocator;
    const definition_count = ligature.max_exact_required_seconds + 1;
    const header_len = 8;
    const set_len = 2 + definition_count * 2;
    const definitions_start = header_len + set_len;
    const coverage_start = definitions_start + definition_count * 6;
    var bytes: [coverage_start + 6]u8 = @splat(0);

    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, @intCast(coverage_start));
    writeU16(&bytes, 4, 1);
    writeU16(&bytes, 6, @intCast(header_len));
    writeU16(&bytes, header_len, @intCast(definition_count));
    for (0..definition_count) |index| {
        const definition_offset = definitions_start + index * 6;
        writeU16(
            &bytes,
            header_len + 2 + index * 2,
            @intCast(definition_offset - header_len),
        );
        writeTwoComponentLigature(
            &bytes,
            definition_offset,
            @intCast(1000 + index),
            @intCast(20 + index),
        );
    }
    writeCoverage1(&bytes, coverage_start, 1);

    const result = try ligature.build(.{
        .data = &bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    }, 0, allocator);
    defer {
        allocator.free(result.components);
        allocator.free(result.definitions);
        allocator.free(result.set_slots);
        allocator.free(result.sets);
    }

    try std.testing.expectEqual(@as(u16, 0), result.required_second_len);
    try std.testing.expectEqual(definition_count, result.components.len);
    try std.testing.expect(!result.prefilter_second);
}

fn writeCoverage1(bytes: []u8, offset: usize, glyph: u16) void {
    writeU16(bytes, offset, 1);
    writeU16(bytes, offset + 2, 1);
    writeU16(bytes, offset + 4, glyph);
}

fn writeTwoComponentLigature(
    bytes: []u8,
    offset: usize,
    replacement: u16,
    second: u16,
) void {
    writeU16(bytes, offset, replacement);
    writeU16(bytes, offset + 2, 2);
    writeU16(bytes, offset + 4, second);
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}
