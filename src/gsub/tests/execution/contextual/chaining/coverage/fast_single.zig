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

fn validatedView(bytes: []const u8) table.View {
    return .{
        .data = bytes,
        .offset = 0,
        .length = bytes.len,
        .assume_validated = true,
    };
}
