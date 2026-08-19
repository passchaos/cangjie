//! Liang-pattern and exception resource parsing.

const std = @import("std");
const model = @import("model.zig");

pub const Error = std.mem.Allocator.Error || error{
    EmptyHyphenationPatterns,
    InvalidHyphenationPattern,
    InvalidHyphenationException,
    InvalidUtf8,
    HyphenationDictionaryTooLarge,
    DuplicateHyphenationException,
    DuplicateHyphenationMapping,
};

pub fn init(
    allocator: std.mem.Allocator,
    patterns: []const u8,
    exceptions: []const u8,
    options: model.Options,
) Error!model.Storage {
    var storage = try initEmpty(allocator, options);
    errdefer storage.deinit();
    try parsePatterns(&storage, patterns);
    try parseExceptions(&storage, exceptions);
    try finish(&storage);
    return storage;
}

pub fn initCombined(
    allocator: std.mem.Allocator,
    data: []const u8,
    options: model.Options,
) Error!model.Storage {
    if (!std.unicode.utf8ValidateSlice(data)) return error.InvalidUtf8;
    var storage = try initEmpty(allocator, options);
    errdefer storage.deinit();

    var patterns_done = false;
    var saw_pattern = false;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) {
            if (saw_pattern) patterns_done = true;
            continue;
        }
        if (line[0] == '%' or line[0] == '#') continue;
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        while (tokens.next()) |token| {
            if (patterns_done) {
                try parseExceptionToken(&storage, token);
            } else {
                try parsePatternToken(&storage, token);
                saw_pattern = true;
            }
        }
    }
    try finish(&storage);
    return storage;
}

fn initEmpty(
    allocator: std.mem.Allocator,
    options: model.Options,
) Error!model.Storage {
    const mappings = try allocator.dupe(model.Mapping, options.mappings);
    errdefer allocator.free(mappings);
    std.sort.heap(model.Mapping, mappings, {}, model.mappingLessThan);
    if (mappings.len > 1) {
        for (mappings[1..], mappings[0 .. mappings.len - 1]) |current, previous| {
            if (current.from == previous.from) {
                return error.DuplicateHyphenationMapping;
            }
        }
    }
    var nodes = std.ArrayList(model.Node).empty;
    errdefer nodes.deinit(allocator);
    try nodes.append(allocator, .{});
    return .{
        .allocator = allocator,
        .nodes = nodes,
        .mappings = mappings,
        .left_min = options.left_min,
        .right_min = options.right_min,
    };
}

fn finish(storage: *model.Storage) Error!void {
    if (storage.nodes.items.len == 1 and
        storage.nodes.items[0].edges.items.len == 0)
    {
        return error.EmptyHyphenationPatterns;
    }
    std.sort.heap(
        model.Exception,
        storage.exceptions.items,
        {},
        model.exceptionLessThan,
    );
    if (storage.exceptions.items.len > 1) {
        for (
            storage.exceptions.items[1..],
            storage.exceptions.items[0 .. storage.exceptions.items.len - 1],
        ) |current, previous| {
            if (model.scalarSlicesEqual(current.word, previous.word)) {
                return error.DuplicateHyphenationException;
            }
        }
    }
}

fn parsePatterns(storage: *model.Storage, data: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(data)) return error.InvalidUtf8;
    var tokens = std.mem.tokenizeAny(u8, data, " \t\r\n");
    while (tokens.next()) |token| {
        if (token[0] == '%' or token[0] == '#') continue;
        try parsePatternToken(storage, token);
    }
}

fn parseExceptions(storage: *model.Storage, data: []const u8) Error!void {
    if (!std.unicode.utf8ValidateSlice(data)) return error.InvalidUtf8;
    var tokens = std.mem.tokenizeAny(u8, data, " \t\r\n");
    while (tokens.next()) |token| {
        if (token[0] == '%' or token[0] == '#') continue;
        try parseExceptionToken(storage, token);
    }
}

fn parsePatternToken(
    storage: *model.Storage,
    token: []const u8,
) Error!void {
    if (token.len == 0 or !std.unicode.utf8ValidateSlice(token)) {
        return error.InvalidHyphenationPattern;
    }
    var letters = std.ArrayList(u21).empty;
    defer letters.deinit(storage.allocator);
    var weights = std.ArrayList(u8).empty;
    defer weights.deinit(storage.allocator);
    try weights.append(storage.allocator, 0);

    var iterator = std.unicode.Utf8Iterator{ .bytes = token, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint >= '0' and codepoint <= '9') {
            weights.items[weights.items.len - 1] =
                @intCast(codepoint - '0');
            continue;
        }
        if (codepoint == '-' or model.isAsciiWhitespace(codepoint)) {
            return error.InvalidHyphenationPattern;
        }
        try letters.append(
            storage.allocator,
            model.normalizedCodepoint(storage.mappings, codepoint),
        );
        try weights.append(storage.allocator, 0);
    }
    if (letters.items.len == 0) {
        return error.InvalidHyphenationPattern;
    }

    var node_index: u32 = 0;
    for (letters.items) |codepoint| {
        node_index = try childForInsert(storage, node_index, codepoint);
    }
    const node = &storage.nodes.items[node_index];
    for (weights.items, 0..) |value, position| {
        if (value == 0) continue;
        const cast_position = std.math.cast(u16, position) orelse
            return error.HyphenationDictionaryTooLarge;
        if (model.findWeight(node.weights.items, cast_position)) |index| {
            node.weights.items[index].value =
                @max(node.weights.items[index].value, value);
        } else {
            try node.weights.append(storage.allocator, .{
                .position = cast_position,
                .value = value,
            });
        }
    }
    std.mem.sort(
        model.Weight,
        node.weights.items,
        {},
        model.weightLessThan,
    );
}

fn parseExceptionToken(
    storage: *model.Storage,
    token: []const u8,
) Error!void {
    if (token.len == 0 or !std.unicode.utf8ValidateSlice(token)) {
        return error.InvalidHyphenationException;
    }
    var word = std.ArrayList(u21).empty;
    defer word.deinit(storage.allocator);
    var boundaries = std.ArrayList(u16).empty;
    defer boundaries.deinit(storage.allocator);
    var iterator = std.unicode.Utf8Iterator{ .bytes = token, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint == '-') {
            if (word.items.len == 0) {
                return error.InvalidHyphenationException;
            }
            const boundary = std.math.cast(u16, word.items.len) orelse
                return error.HyphenationDictionaryTooLarge;
            if (boundaries.items.len != 0 and
                boundaries.items[boundaries.items.len - 1] == boundary)
            {
                return error.InvalidHyphenationException;
            }
            try boundaries.append(storage.allocator, boundary);
            continue;
        }
        if ((codepoint >= '0' and codepoint <= '9') or
            codepoint == '.' or model.isAsciiWhitespace(codepoint))
        {
            return error.InvalidHyphenationException;
        }
        try word.append(
            storage.allocator,
            model.normalizedCodepoint(storage.mappings, codepoint),
        );
    }
    if (word.items.len == 0 or
        (boundaries.items.len != 0 and
            boundaries.items[boundaries.items.len - 1] == word.items.len))
    {
        return error.InvalidHyphenationException;
    }

    const owned_word = try word.toOwnedSlice(storage.allocator);
    errdefer storage.allocator.free(owned_word);
    const owned_boundaries = try boundaries.toOwnedSlice(storage.allocator);
    errdefer storage.allocator.free(owned_boundaries);
    try storage.exceptions.append(storage.allocator, .{
        .word = owned_word,
        .boundaries = owned_boundaries,
    });
}

fn childForInsert(
    storage: *model.Storage,
    parent_index: u32,
    codepoint: u21,
) Error!u32 {
    if (model.findEdge(
        storage.nodes.items[parent_index].edges.items,
        codepoint,
    )) |edge| {
        return edge.child;
    }
    const child = std.math.cast(u32, storage.nodes.items.len) orelse
        return error.HyphenationDictionaryTooLarge;
    try storage.nodes.append(storage.allocator, .{});
    try storage.nodes.items[parent_index].edges.append(
        storage.allocator,
        .{ .codepoint = codepoint, .child = child },
    );
    std.mem.sort(
        model.Edge,
        storage.nodes.items[parent_index].edges.items,
        {},
        model.edgeLessThan,
    );
    return child;
}
