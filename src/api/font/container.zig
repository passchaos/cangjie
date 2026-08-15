//! Modern web-font and collection container decoding.

const std = @import("std");

const impl = @import("../../font_container.zig");
const face_mod = @import("../../font/face/root.zig");

pub const Error = impl.Error;
pub const Format = impl.Format;
pub const default_max_decoded_size = impl.default_max_decoded_size;

pub const decodeAlloc = impl.decodeFontContainerAlloc;
pub const detectFormat = impl.detectFormat;

/// Owns decoded SFNT bytes and the parsed face that borrows them.
pub const OwnedFace = struct {
    /// Source-visible ownership state; callers should use `face` and `deinit`.
    allocator: std.mem.Allocator,
    bytes: []u8,
    parsed_face: face_mod.Face,

    pub fn load(
        allocator: std.mem.Allocator,
        data: []const u8,
        max_decoded_size: usize,
    ) !OwnedFace {
        return loadIndex(allocator, data, 0, max_decoded_size);
    }

    pub fn loadIndex(
        allocator: std.mem.Allocator,
        data: []const u8,
        face_index: usize,
        max_decoded_size: usize,
    ) !OwnedFace {
        const bytes = try decodeAlloc(allocator, data, max_decoded_size);
        errdefer allocator.free(bytes);
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .parsed_face = try face_mod.Face.parseIndex(
                allocator,
                bytes,
                face_index,
            ),
        };
    }

    pub fn deinit(self: *OwnedFace) void {
        const allocator = self.allocator;
        self.parsed_face.deinit();
        allocator.free(self.bytes);
        self.* = undefined;
    }

    pub fn face(self: *const OwnedFace) *const face_mod.Face {
        return &self.parsed_face;
    }
};
