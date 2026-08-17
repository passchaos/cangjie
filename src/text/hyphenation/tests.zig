const std = @import("std");
const Dictionary = @import("root.zig").Dictionary;

test "Liang priorities combine and return UTF-8 byte boundaries" {
    // a1b and ab3c overlap at the b/c boundary; the maximum value wins.
    var dictionary = try Dictionary.init(
        std.testing.allocator,
        "a1b ab3c é1x",
        "",
        .{ .left_min = 1, .right_min = 1 },
    );
    defer dictionary.deinit();
    var out = std.ArrayList(usize).empty;
    defer out.deinit(std.testing.allocator);

    try dictionary.hyphenate(std.testing.allocator, "abc", &out);
    try std.testing.expectEqualSlices(usize, &.{ 1, 2 }, out.items);

    try dictionary.hyphenate(std.testing.allocator, "éx", &out);
    try std.testing.expectEqualSlices(usize, &.{"é".len}, out.items);
}

test "exceptions override patterns and minimum fragments" {
    var dictionary = try Dictionary.init(
        std.testing.allocator,
        "a1s s1o o1c c1i i1a a1t t1e",
        "as-so-ci-ate present",
        .{ .left_min = 2, .right_min = 2 },
    );
    defer dictionary.deinit();
    var out = std.ArrayList(usize).empty;
    defer out.deinit(std.testing.allocator);

    try dictionary.hyphenate(std.testing.allocator, "associate", &out);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4, 6 }, out.items);
    try dictionary.hyphenate(std.testing.allocator, "present", &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "combined MuPDF-style files split patterns from exceptions" {
    var dictionary = try Dictionary.initCombined(
        std.testing.allocator,
        \\.as1
        \\so1
        \\
        \\as-so-ciate present
        \\
    ,
        .{ .left_min = 2, .right_min = 2 },
    );
    defer dictionary.deinit();
    var out = std.ArrayList(usize).empty;
    defer out.deinit(std.testing.allocator);
    try dictionary.hyphenate(std.testing.allocator, "associate", &out);
    try std.testing.expectEqualSlices(usize, &.{ 2, 4 }, out.items);
    try dictionary.hyphenate(std.testing.allocator, "present", &out);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "owned Unicode mappings normalize pattern and word scalars" {
    var source_mapping = [_]Dictionary.Mapping{
        .{ .from = 'Ä', .to = 'ä' },
    };
    var dictionary = try Dictionary.init(
        std.testing.allocator,
        "ä1r",
        "",
        .{
            .left_min = 1,
            .right_min = 1,
            .mappings = &source_mapping,
        },
    );
    defer dictionary.deinit();
    // Construction owns the mapping; mutating the source cannot change reads.
    source_mapping[0].to = 'x';
    var out = std.ArrayList(usize).empty;
    defer out.deinit(std.testing.allocator);
    try dictionary.hyphenate(std.testing.allocator, "Är", &out);
    try std.testing.expectEqualSlices(usize, &.{"Ä".len}, out.items);
}

test "dictionary rejects malformed patterns and duplicate exceptions" {
    try std.testing.expectError(
        error.EmptyHyphenationPatterns,
        Dictionary.init(std.testing.allocator, "", "", .{}),
    );
    try std.testing.expectError(
        error.InvalidHyphenationPattern,
        Dictionary.init(std.testing.allocator, "a-b", "", .{}),
    );
    try std.testing.expectError(
        error.DuplicateHyphenationException,
        Dictionary.init(
            std.testing.allocator,
            "a1b",
            "ab ab",
            .{},
        ),
    );
}

test "dictionary construction is atomic under allocation failure" {
    const allocator = std.testing.allocator;
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(
            allocator,
            .{ .fail_index = fail_index },
        );
        const result = Dictionary.init(
            failing.allocator(),
            ".as1 so1 ci1",
            "as-so-ci-ate present",
            .{},
        );
        if (result) |dictionary_value| {
            var dictionary = dictionary_value;
            dictionary.deinit();
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
        }
    }
}
