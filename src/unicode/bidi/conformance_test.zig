//! Full Unicode 17 `BidiTest` and `BidiCharacterTest` conformance gate.

const std = @import("std");

const resolver = @import("resolver.zig");
const test_data = @embedFile("conformance.bin");

const Header = struct {
    expectation_count: usize,
    type_case_count: usize,
    character_case_count: usize,
};

const Expectation = struct {
    levels: []const u8,
    order: []const u8,
};

pub fn run() !void {
    const header = parseHeader();
    try std.testing.expectEqual(@as(usize, 1328), header.expectation_count);
    try std.testing.expectEqual(@as(usize, 770241), header.type_case_count);
    try std.testing.expectEqual(@as(usize, 91707), header.character_case_count);

    var offset: usize = 20;
    const expectations = try std.testing.allocator.alloc(
        Expectation,
        header.expectation_count,
    );
    defer std.testing.allocator.free(expectations);
    for (expectations) |*expectation| {
        const level_count = test_data[offset];
        const order_count = test_data[offset + 1];
        offset += 2;
        expectation.levels = test_data[offset..][0..level_count];
        offset += level_count;
        expectation.order = test_data[offset..][0..order_count];
        offset += order_count;
    }

    var scratch = resolver.Scratch.init(std.testing.allocator);
    defer scratch.deinit();
    var inputs: [256]resolver.Input = undefined;
    var actual_order: [256]usize = undefined;

    for (0..header.type_case_count) |case_index| {
        const mode: resolver.BaseDirection = switch (test_data[offset]) {
            0 => .ltr,
            1 => .rtl,
            2 => .auto,
            else => return error.InvalidFixture,
        };
        const expectation_index = std.mem.readInt(
            u16,
            test_data[offset + 1 ..][0..2],
            .little,
        );
        const count = test_data[offset + 3];
        offset += 4;
        for (inputs[0..count], test_data[offset..][0..count]) |*input, value| {
            input.* = .{
                .codepoint = 0,
                .class = @enumFromInt(value),
            };
        }
        offset += count;

        const base_level = try scratch.resolve(inputs[0..count], mode);
        const expected = expectations[expectation_index];
        if (!std.mem.eql(u8, scratch.resolvedLevels(), expected.levels)) {
            std.debug.print(
                "BidiTest case={d} base={d} input={any} expected={any} actual={any}\n",
                .{
                    case_index,
                    base_level,
                    test_data[offset - count .. offset],
                    expected.levels,
                    scratch.resolvedLevels(),
                },
            );
            return error.BidiLevelMismatch;
        }
        const order_count = reorder(
            scratch.resolvedLevels(),
            actual_order[0..count],
        );
        if (!equalOrder(actual_order[0..order_count], expected.order)) {
            std.debug.print(
                "BidiTest reorder case={d} expected={any} actual={any}\n",
                .{
                    case_index,
                    expected.order,
                    actual_order[0..order_count],
                },
            );
            return error.BidiOrderMismatch;
        }
    }

    for (0..header.character_case_count) |case_index| {
        const mode: resolver.BaseDirection = switch (test_data[offset]) {
            0 => .ltr,
            1 => .rtl,
            2 => .auto,
            else => return error.InvalidFixture,
        };
        const expected_base = test_data[offset + 1];
        const count = test_data[offset + 2];
        const expected_order_count = test_data[offset + 3];
        offset += 4;
        const expected_levels = test_data[offset..][0..count];
        offset += count;
        for (inputs[0..count]) |*input| {
            const codepoint: u21 = @intCast(std.mem.readInt(
                u32,
                test_data[offset..][0..4],
                .little,
            ));
            offset += 4;
            input.* = .{
                .codepoint = codepoint,
                .class = @import("data.zig").class(codepoint),
            };
        }
        const expected_order = test_data[offset..][0..expected_order_count];
        offset += expected_order_count;

        const actual_base = try scratch.resolve(inputs[0..count], mode);
        if (actual_base != expected_base or
            !std.mem.eql(u8, scratch.resolvedLevels(), expected_levels))
        {
            std.debug.print(
                "BidiCharacterTest case={d} base={d}/{d} expected={any} actual={any}\n",
                .{
                    case_index,
                    expected_base,
                    actual_base,
                    expected_levels,
                    scratch.resolvedLevels(),
                },
            );
            return error.BidiLevelMismatch;
        }
        const order_count = reorder(
            scratch.resolvedLevels(),
            actual_order[0..count],
        );
        if (!equalOrder(actual_order[0..order_count], expected_order)) {
            std.debug.print(
                "BidiCharacterTest reorder case={d} expected={any} actual={any}\n",
                .{
                    case_index,
                    expected_order,
                    actual_order[0..order_count],
                },
            );
            return error.BidiOrderMismatch;
        }
    }
    try std.testing.expectEqual(test_data.len, offset);
}

fn parseHeader() Header {
    if (test_data.len < 20 or
        !std.mem.eql(u8, test_data[0..4], "CJBT") or
        test_data[4] != 1 or test_data[5] != 17 or
        test_data[6] != 0 or test_data[7] != 0)
    {
        @panic("invalid Unicode bidi conformance fixture");
    }
    return .{
        .expectation_count = std.mem.readInt(
            u32,
            test_data[8..12],
            .little,
        ),
        .type_case_count = std.mem.readInt(
            u32,
            test_data[12..16],
            .little,
        ),
        .character_case_count = std.mem.readInt(
            u32,
            test_data[16..20],
            .little,
        ),
    };
}

fn reorder(levels: []const u8, output: []usize) usize {
    var count: usize = 0;
    var max_level: u8 = 0;
    var minimum_odd: u8 = 0xff;
    for (levels, 0..) |level, index| {
        if (level == resolver.removed_level) continue;
        output[count] = index;
        count += 1;
        max_level = @max(max_level, level);
        if (level & 1 != 0) minimum_odd = @min(minimum_odd, level);
    }
    if (minimum_odd == 0xff) return count;

    var level = max_level;
    while (true) : (level -= 1) {
        var cursor: usize = 0;
        while (cursor < count) {
            if (levels[output[cursor]] < level) {
                cursor += 1;
                continue;
            }
            const start = cursor;
            while (cursor < count and levels[output[cursor]] >= level) {
                cursor += 1;
            }
            std.mem.reverse(usize, output[start..cursor]);
        }
        if (level == minimum_odd) break;
    }
    return count;
}

fn equalOrder(actual: []const usize, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    for (actual, expected) |lhs, rhs| {
        if (lhs != rhs) return false;
    }
    return true;
}
