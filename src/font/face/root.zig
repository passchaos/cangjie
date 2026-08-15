//! Stable public handles for parsed faces and their common capability views.
//!
//! The parser implementation is intentionally not the public type. Keeping the
//! handle opaque prevents table records, shaping executors, cache proofs, and
//! renderer fast paths from becoming API merely because they are fields or
//! methods of the implementation object.

const std = @import("std");

const font_mod = @import("../../font.zig");
const Font = font_mod.Font;

pub const Properties = struct {
    format: font_mod.FontFormat,
    units_per_em: u16,
    glyph_count: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
};

/// A parsed, zero-copy font face.
///
/// The handle owns parser bookkeeping but borrows the supplied SFNT/TTC bytes.
/// Those bytes must therefore remain alive and unchanged until `deinit`.
pub const Face = opaque {
    /// Parse the first face in a standalone SFNT or collection.
    pub fn parse(
        allocator: std.mem.Allocator,
        data: []const u8,
    ) font_mod.FontError!*Face {
        return parseIndex(allocator, data, 0);
    }

    /// Parse one zero-based face from a standalone SFNT or collection.
    pub fn parseIndex(
        allocator: std.mem.Allocator,
        data: []const u8,
        face_index: usize,
    ) font_mod.FontError!*Face {
        const implementation = try allocator.create(Font);
        errdefer allocator.destroy(implementation);
        implementation.* = try Font.parseFace(allocator, data, face_index);
        return backend.faceMut(implementation);
    }

    pub fn count(data: []const u8) font_mod.FontError!usize {
        return Font.faceCount(data);
    }

    pub fn deinit(self: *Face) void {
        const implementation = backend.fontMut(self);
        const allocator = implementation.allocator;
        implementation.deinit();
        allocator.destroy(implementation);
    }

    pub fn properties(self: *const Face) Properties {
        const implementation = backend.font(self);
        return .{
            .format = implementation.format,
            .units_per_em = implementation.units_per_em,
            .glyph_count = implementation.glyph_count,
            .ascender = implementation.ascender,
            .descender = implementation.descender,
            .line_gap = implementation.line_gap,
        };
    }

    pub fn glyphs(self: *const Face) *const Glyphs {
        return @ptrCast(self);
    }

    pub fn metrics(self: *const Face) *const Metrics {
        return @ptrCast(self);
    }

    pub fn names(self: *const Face) *const Names {
        return @ptrCast(self);
    }

    pub fn variations(self: *const Face) *const Variations {
        return @ptrCast(self);
    }

    pub fn color(self: *const Face) *const Color {
        return @ptrCast(self);
    }
};

/// An ordered fallback list. The slice and every face are borrowed.
pub const Cascade = struct {
    faces: []const *const Face,

    pub fn init(faces: []const *const Face) Cascade {
        return .{ .faces = faces };
    }

    pub fn len(self: Cascade) usize {
        return self.faces.len;
    }

    pub fn isEmpty(self: Cascade) bool {
        return self.faces.len == 0;
    }
};

pub const Glyphs = @import("views/glyphs.zig").View;
pub const Metrics = @import("views/metrics.zig").View;
pub const Names = @import("views/names.zig").View;
pub const Variations = @import("views/variations.zig").View;
pub const Color = @import("views/color.zig").View;

/// Internal conversion boundary shared by shaping, databases, and rendering.
///
/// Every public handle is a pointer-only view over the same heap-allocated
/// `Font`; no view may add fields or change alignment. Slice casts are valid
/// because they rewrite only the pointee type of each pointer-sized element.
pub const backend = struct {
    pub fn font(face_value: *const Face) *const Font {
        return @ptrCast(@alignCast(face_value));
    }

    pub fn fontMut(face_value: *Face) *Font {
        return @ptrCast(@alignCast(face_value));
    }

    pub fn face(font_value: *const Font) *const Face {
        return @ptrCast(font_value);
    }

    pub fn faceMut(font_value: *Font) *Face {
        return @ptrCast(font_value);
    }

    pub fn fonts(face_values: []const *const Face) []const *const Font {
        return @as(
            [*]const *const Font,
            @ptrCast(face_values.ptr),
        )[0..face_values.len];
    }

    pub fn faces(font_values: []const *const Font) []const *const Face {
        return @as(
            [*]const *const Face,
            @ptrCast(font_values.ptr),
        )[0..font_values.len];
    }
};
