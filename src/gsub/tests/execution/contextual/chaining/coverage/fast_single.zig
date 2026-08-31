//! ChainContextSubst format-3 direct and accelerated execution contracts.

const std = @import("std");
const accelerator = @import("../../../../../accelerator/root.zig");
const chaining =
    @import("../../../../../execution/contextual/chaining/coverage/root.zig");
const model = @import("../../../../../execution/contextual/model.zig");
const fixture = @import("../../context/fixture.zig");
const Options = @import("../../../../../runtime/options.zig").Options;
const table = @import("../../../../../table/root.zig");

const Executor = struct {
    pub const enable_fast_single = false;

    pub fn applyNested(
        _: table.View,
        glyphs: *std.ArrayList(u16),
        target: usize,
        lookup_index: u16,
        _: std.mem.Allocator,
        _: Options,
    ) !model.Change {
        glyphs.items[target] += @as(u16, lookup_index) + 10;
        return .{};
    }

    pub fn validateNested(_: table.View, _: usize) !void {}
};

test "predecoded single records bypass the generic executor" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    fixture.writeCoverage1(&bytes, 0, 5);
    var parsed = accelerator.model.ChainingCoverageSubtable{
        .input_count = 1,
        .fast_record_count = 1,
    };
    parsed.fast_records[0] = .{
        .sequence_index = 0,
        .accelerator = .{
            .enabled = true,
            .single_mapping = true,
            .single_from = 5,
            .single_to = 9,
        },
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    const result = try chaining.acceleratedNoContextAt(
        Executor,
        validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        null,
        null,
        allocator,
        .{},
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{9}, glyphs.items);
}

test "predecoded single records skip disabled nested lookups" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    fixture.writeCoverage1(&bytes, 0, 5);
    const parsed = oneRecordSubtable(3);
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    var operations_left: usize = 1;

    const result = try chaining.acceleratedNoContextAt(
        Executor,
        validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        null,
        null,
        allocator,
        .{
            .disabled_lookups = &.{3},
            .operations_left = &operations_left,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{5}, glyphs.items);
    try std.testing.expectEqual(@as(usize, 1), operations_left);
}

test "predecoded single records preserve order around disabled lookups" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    fixture.writeCoverage1(&bytes, 0, 5);
    var parsed = accelerator.model.ChainingCoverageSubtable{
        .input_count = 1,
        .fast_record_count = 2,
    };
    parsed.fast_records[0] = .{
        .sequence_index = 0,
        .lookup_index = 3,
        .accelerator = .{
            .enabled = true,
            .single_mapping = true,
            .single_from = 5,
            .single_to = 9,
        },
    };
    parsed.fast_records[1] = .{
        .sequence_index = 0,
        .lookup_index = 4,
        .accelerator = .{
            .enabled = true,
            .single_mapping = true,
            .single_from = 5,
            .single_to = 12,
        },
    };
    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    var operations_left: usize = 1;

    const result = try chaining.acceleratedNoContextAt(
        Executor,
        validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        null,
        null,
        allocator,
        .{
            .disabled_lookups = &.{3},
            .operations_left = &operations_left,
        },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{12}, glyphs.items);
    try std.testing.expectEqual(@as(usize, 0), operations_left);
}

test "predecoded single records obey the nested operation budget" {
    const allocator = std.testing.allocator;
    var bytes = [_]u8{0} ** 24;
    fixture.writeCoverage1(&bytes, 0, 5);
    const parsed = oneRecordSubtable(3);

    var exhausted_glyphs = std.ArrayList(u16).empty;
    defer exhausted_glyphs.deinit(allocator);
    try exhausted_glyphs.append(allocator, 5);
    var exhausted: usize = 0;
    try std.testing.expectError(
        error.ShapingLimitExceeded,
        chaining.acceleratedNoContextAt(
            Executor,
            validatedView(&bytes),
            parsed,
            &exhausted_glyphs,
            0,
            null,
            null,
            allocator,
            .{ .operations_left = &exhausted },
        ),
    );
    try std.testing.expectEqualSlices(u16, &.{5}, exhausted_glyphs.items);

    var glyphs = std.ArrayList(u16).empty;
    defer glyphs.deinit(allocator);
    try glyphs.append(allocator, 5);
    var operations_left: usize = 1;
    const result = try chaining.acceleratedNoContextAt(
        Executor,
        validatedView(&bytes),
        parsed,
        &glyphs,
        0,
        null,
        null,
        allocator,
        .{ .operations_left = &operations_left },
    );
    try std.testing.expect(result.matched);
    try std.testing.expectEqualSlices(u16, &.{9}, glyphs.items);
    try std.testing.expectEqual(@as(usize, 0), operations_left);
}

fn oneRecordSubtable(lookup_index: u16) accelerator.model.ChainingCoverageSubtable {
    var parsed = accelerator.model.ChainingCoverageSubtable{
        .input_count = 1,
        .fast_record_count = 1,
    };
    parsed.fast_records[0] = .{
        .sequence_index = 0,
        .lookup_index = lookup_index,
        .accelerator = .{
            .enabled = true,
            .single_mapping = true,
            .single_from = 5,
            .single_to = 9,
        },
    };
    return parsed;
}

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
