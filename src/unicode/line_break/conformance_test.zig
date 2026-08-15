//! Official Unicode 17 `LineBreakTest.txt` conformance gate.

const std = @import("std");

const test_data = @embedFile("conformance.bin");

pub fn run(comptime line_break: type) !void {
    if (test_data.len < 12 or !std.mem.eql(u8, test_data[0..4], "CJLT") or
        test_data[4] != 2 or test_data[5] != 17 or
        test_data[6] != 0 or test_data[7] != 0)
    {
        return error.InvalidFixture;
    }
    const case_count = std.mem.readInt(u32, test_data[8..12], .little);
    try std.testing.expectEqual(@as(u32, 19338), case_count);

    var fixture_offset: usize = 12;
    for (0..case_count) |case_index| {
        const count = test_data[fixture_offset];
        fixture_offset += 1;
        const expected = test_data[fixture_offset..][0 .. @as(usize, count) + 1];
        fixture_offset += @as(usize, count) + 1;
        const cp_bytes = test_data[fixture_offset..][0 .. @as(usize, count) * 4];
        fixture_offset += @as(usize, count) * 4;

        var utf8: [1024]u8 = undefined;
        var utf8_len: usize = 0;
        var expected_offsets: [256]usize = undefined;
        var expected_count: usize = 0;
        for (0..count) |i| {
            const cp: u21 = @intCast(std.mem.readInt(
                u32,
                cp_bytes[i * 4 ..][0..4],
                .little,
            ));
            utf8_len += try std.unicode.utf8Encode(cp, utf8[utf8_len..]);
            if (expected[i + 1] != 0) {
                expected_offsets[expected_count] = utf8_len;
                expected_count += 1;
            }
        }

        var iterator = line_break.breaksAssumeValid(utf8[0..utf8_len]);
        var actual_count: usize = 0;
        while (iterator.next()) |opportunity| {
            if (actual_count >= expected_count or
                expected_offsets[actual_count] != opportunity.byte_offset)
            {
                std.debug.print(
                    "line case={d} boundary={d} expected={d} actual={d}\n",
                    .{
                        case_index,
                        actual_count,
                        if (actual_count < expected_count)
                            expected_offsets[actual_count]
                        else
                            std.math.maxInt(usize),
                        opportunity.byte_offset,
                    },
                );
                return error.LineBreakConformanceMismatch;
            }
            actual_count += 1;
        }
        try std.testing.expectEqual(expected_count, actual_count);
    }
    try std.testing.expectEqual(test_data.len, fixture_offset);

    // This targeted case protects the transactional handoff between the ASCII
    // prose scanner and the complete LB30 punctuation rule. It was the only
    // official row that exposed a partially committed scanner state.
    var iterator = line_break.breaksAssumeValid("give book(s).");
    const first = iterator.next() orelse return error.MissingLineBreak;
    const end = iterator.next() orelse return error.MissingLineBreak;
    try std.testing.expectEqual(@as(usize, 5), first.byte_offset);
    try std.testing.expectEqual(line_break.BreakKind.soft, first.kind);
    try std.testing.expectEqual(@as(usize, 13), end.byte_offset);
    try std.testing.expectEqual(line_break.BreakKind.hard, end.kind);
    try std.testing.expect(iterator.next() == null);
}
