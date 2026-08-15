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
pub const OwnedFace = opaque {
    pub fn load(
        allocator: std.mem.Allocator,
        data: []const u8,
        max_decoded_size: usize,
    ) !*OwnedFace {
        return loadIndex(allocator, data, 0, max_decoded_size);
    }

    pub fn loadIndex(
        allocator: std.mem.Allocator,
        data: []const u8,
        face_index: usize,
        max_decoded_size: usize,
    ) !*OwnedFace {
        const bytes = try decodeAlloc(allocator, data, max_decoded_size);
        errdefer allocator.free(bytes);
        const owned = try allocator.create(Implementation);
        errdefer allocator.destroy(owned);
        owned.* = .{
            .allocator = allocator,
            .bytes = bytes,
            .face = try face_mod.Face.parseIndex(
                allocator,
                bytes,
                face_index,
            ),
        };
        return @ptrCast(owned);
    }

    pub fn deinit(self: *OwnedFace) void {
        const owned = implementation(self);
        const allocator = owned.allocator;
        owned.face.deinit();
        allocator.free(owned.bytes);
        allocator.destroy(owned);
    }

    pub fn face(self: *const OwnedFace) *const face_mod.Face {
        return implementationConst(self).face;
    }
};

const Implementation = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,
    face: *face_mod.Face,
};

fn implementation(owned: *OwnedFace) *Implementation {
    return @ptrCast(@alignCast(owned));
}

fn implementationConst(owned: *const OwnedFace) *const Implementation {
    return @ptrCast(@alignCast(owned));
}
