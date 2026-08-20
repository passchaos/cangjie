//! Private-DICT parameters that control Type2 blue-zone hinting.

const fixed = @import("fixed.zig");

pub const max_blue_values = 7;

pub const BlueValues = struct {
    values: [max_blue_values][2]fixed.Fixed = [_][2]fixed.Fixed{.{ .{}, .{} }} ** max_blue_values,
    len: u8 = 0,

    /// Private-DICT blue arrays use delta encoding across all operands.
    pub fn setDeltas(self: *BlueValues, deltas: []const f32) error{InvalidHintParams}!void {
        self.* = .{};
        var current = fixed.Fixed.zero;
        var pair: [2]fixed.Fixed = undefined;
        for (deltas, 0..) |delta, index| {
            if (index >= max_blue_values * 2) break;
            const value = fixed.Fixed.fromF32(delta);
            current = current.add(value);
            pair[index & 1] = current;
            if ((index & 1) != 0) {
                self.values[self.len] = pair;
                self.len += 1;
            }
        }
    }

    pub fn slice(self: *const BlueValues) []const [2]fixed.Fixed {
        return self.values[0..self.len];
    }
};

pub const Params = struct {
    blues: BlueValues = .{},
    family_blues: BlueValues = .{},
    other_blues: BlueValues = .{},
    family_other_blues: BlueValues = .{},
    blue_scale: fixed.Fixed = fixed.Fixed.fromF32(0.039625),
    blue_shift: fixed.Fixed = fixed.Fixed.fromInt(7),
    blue_fuzz: fixed.Fixed = fixed.Fixed.one,
    language_group: i32 = 0,
};

test "Type2 blue values decode a delta prefix" {
    const std = @import("std");
    var values = BlueValues{};
    try values.setDeltas(&.{ -15, 15, 536, 11 });
    try std.testing.expectEqual(@as(i32, -15 << 16), values.slice()[0][0].bits);
    try std.testing.expectEqual(@as(i32, 0), values.slice()[0][1].bits);
    try std.testing.expectEqual(@as(i32, 536 << 16), values.slice()[1][0].bits);
    try std.testing.expectEqual(@as(i32, 547 << 16), values.slice()[1][1].bits);
}
