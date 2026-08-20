//! Modern web-font and collection container decoding.

const std = @import("std");
const Font = @import("../../font.zig").Font;
const binary = @import("binary.zig");
const dfont = @import("dfont.zig");
const types = @import("types.zig");
const woff1 = @import("woff1.zig");
const woff2 = @import("woff2.zig");

pub const Error = types.Error;
pub const Format = types.Format;
pub const default_max_decoded_size = types.default_max_decoded_size;

pub const OwnedFace = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    face: Font,

    pub fn load(allocator: std.mem.Allocator, data: []const u8, max_decoded_size: usize) !OwnedFace {
        return loadFace(allocator, data, 0, max_decoded_size);
    }

    pub fn loadFace(allocator: std.mem.Allocator, data: []const u8, face_index: usize, max_decoded_size: usize) !OwnedFace {
        const bytes = try decodeFontContainerAlloc(allocator, data, max_decoded_size);
        errdefer allocator.free(bytes);
        return .{ .allocator = allocator, .bytes = bytes, .face = try Font.parseFace(allocator, bytes, face_index) };
    }

    pub fn deinit(self: *OwnedFace) void {
        self.face.deinit();
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub fn detectFormat(data: []const u8) Error!Format {
    if (data.len < 4) return error.InvalidContainer;
    const signature = binary.readU32(data, 0);
    return switch (signature) {
        0x00010000, 0x74727565, 0x4f54544f, 0x74746366 => .sfnt,
        0x00000100 => .dfont,
        0x774f4646 => .woff1,
        0x774f4632 => .woff2,
        else => {
            if (data.len >= 16) {
                const data_start: usize = signature;
                const map_start: usize = binary.readU32(data, 4);
                const data_len: usize = binary.readU32(data, 8);
                const map_len: usize = binary.readU32(data, 12);
                if (data_start <= data.len and data_len <= data.len - data_start and
                    map_start <= data.len and map_len <= data.len - map_start and
                    data_len != 0 and map_len >= 28 and
                    !binary.rangesOverlap(data_start, data_start + data_len, map_start, map_start + map_len))
                {
                    return .dfont;
                }
            }
            return error.UnsupportedContainer;
        },
    };
}

pub fn decodeFontContainerAlloc(allocator: std.mem.Allocator, data: []const u8, max_decoded_size: usize) ![]u8 {
    return switch (try detectFormat(data)) {
        .sfnt => if (data.len > max_decoded_size) error.OutputTooLarge else try allocator.dupe(u8, data),
        .dfont => try dfont.decodeAlloc(allocator, data, max_decoded_size),
        .woff1 => try woff1.decodeAlloc(allocator, data, max_decoded_size),
        .woff2 => try woff2.decodeAlloc(allocator, data, max_decoded_size),
    };
}

pub const testing = struct {
    pub const buildWoff1 = @import("test_support.zig").buildWoff1;
    pub const buildDfont = @import("test_support.zig").buildDfont;
};

test {
    _ = @import("tests.zig");
}
