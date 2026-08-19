//! Shared reconstruction of glyph-indexed byte arrays and their offsets.

const std = @import("std");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error;

pub const Encoding = enum {
    short_div_by_two,
    long,
    cff_1,
    cff_2,
    cff_3,
    cff_4,

    pub fn width(self: Encoding) usize {
        return switch (self) {
            .short_div_by_two, .cff_2 => 2,
            .long, .cff_4 => 4,
            .cff_1 => 1,
            .cff_3 => 3,
        };
    }

    pub fn divisor(self: Encoding) usize {
        return if (self == .short_div_by_two) 2 else 1;
    }

    pub fn bias(self: Encoding) usize {
        return switch (self) {
            .cff_1, .cff_2, .cff_3, .cff_4 => 1,
            else => 0,
        };
    }

    fn maxEncoded(self: Encoding) u64 {
        return switch (self.width()) {
            1 => std.math.maxInt(u8),
            2 => std.math.maxInt(u16),
            3 => 0x00ff_ffff,
            4 => std.math.maxInt(u32),
            else => unreachable,
        };
    }

    pub fn maxDataLength(self: Encoding) u64 {
        return (self.maxEncoded() - self.bias()) * self.divisor();
    }
};

pub const Result = struct {
    data: []u8,
    offsets: []u32,
    encoding: Encoding,

    pub fn deinit(self: Result, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.free(self.offsets);
    }
};

pub fn rebuild(
    allocator: std.mem.Allocator,
    base_data: []const u8,
    base_offsets: []const u32,
    replacements: []const ?[]const u8,
    initial_encoding: Encoding,
    available_encodings: []const Encoding,
    max_output_size: usize,
) Error!Result {
    if (base_offsets.len != replacements.len + 1 or available_encodings.len == 0) {
        return error.BadSfnt;
    }
    var previous: usize = 0;
    for (base_offsets) |raw| {
        const current: usize = raw;
        if (current < previous or current > base_data.len) return error.BadSfnt;
        previous = current;
    }

    var encoding = initial_encoding;
    var total = try outputLength(base_offsets, replacements, encoding);
    if (total > encoding.maxDataLength()) {
        var found = false;
        for (available_encodings) |candidate| {
            if (candidate.width() < initial_encoding.width()) continue;
            const candidate_total = try outputLength(base_offsets, replacements, candidate);
            if (candidate_total <= candidate.maxDataLength()) {
                encoding = candidate;
                total = candidate_total;
                found = true;
                break;
            }
        }
        if (!found) return error.BadSfnt;
    }
    if (total > max_output_size or total > std.math.maxInt(u32)) return error.BadSfnt;

    const output = try allocator.alloc(u8, total);
    errdefer allocator.free(output);
    const output_offsets = try allocator.alloc(u32, replacements.len + 1);
    errdefer allocator.free(output_offsets);
    var cursor: usize = 0;
    for (replacements, 0..) |replacement, glyph_id| {
        output_offsets[glyph_id] = @intCast(cursor);
        const start: usize = base_offsets[glyph_id];
        const end: usize = base_offsets[glyph_id + 1];
        const selected = replacement orelse base_data[start..end];
        @memcpy(output[cursor..][0..selected.len], selected);
        cursor += selected.len;
        const padding = paddingFor(selected.len, encoding.divisor());
        @memset(output[cursor..][0..padding], 0);
        cursor += padding;
    }
    output_offsets[replacements.len] = @intCast(cursor);
    std.debug.assert(cursor == output.len);
    return .{ .data = output, .offsets = output_offsets, .encoding = encoding };
}

fn outputLength(
    base_offsets: []const u32,
    replacements: []const ?[]const u8,
    encoding: Encoding,
) Error!usize {
    var total: usize = 0;
    for (replacements, 0..) |replacement, glyph_id| {
        const length = if (replacement) |bytes| bytes.len else @as(usize, base_offsets[glyph_id + 1] - base_offsets[glyph_id]);
        total = std.math.add(usize, total, length) catch return error.BadSfnt;
        total = std.math.add(
            usize,
            total,
            paddingFor(length, encoding.divisor()),
        ) catch return error.BadSfnt;
    }
    return total;
}

fn paddingFor(length: usize, divisor: usize) usize {
    return if (divisor == 1) 0 else (divisor - length % divisor) % divisor;
}

pub fn writeEncodedOffsets(
    destination: []u8,
    byte_offset: usize,
    values: []const u32,
    encoding: Encoding,
) Error!void {
    const width = encoding.width();
    const needed = std.math.mul(usize, values.len, width) catch return error.BadSfnt;
    if (byte_offset > destination.len or needed > destination.len - byte_offset) {
        return error.BadSfnt;
    }
    for (values, 0..) |value, index| {
        if (value % encoding.divisor() != 0) return error.BadSfnt;
        const encoded = @as(u64, value / encoding.divisor()) + encoding.bias();
        if (encoded > encoding.maxEncoded()) return error.BadSfnt;
        writeSized(destination, byte_offset + index * width, width, @intCast(encoded));
    }
}

fn writeSized(data: []u8, offset: usize, width: usize, value: u32) void {
    var remaining = value;
    var index = width;
    while (index != 0) {
        index -= 1;
        data[offset + index] = @truncate(remaining);
        remaining >>= 8;
    }
}
