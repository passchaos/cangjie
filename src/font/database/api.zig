//! Public font database wrapper.
//!
//! Discovery owns its imported font bytes. The wrapper converts the internal
//! cascade allocation to public face pointers before it crosses the facade.

const std = @import("std");

const face_mod = @import("../face/root.zig");
const impl = @import("../../database.zig");

pub const FaceInfo = struct {
    face: *const face_mod.Face,
    family: []const u8,
    subfamily: []const u8,
    full_name: []const u8,
    postscript_name: []const u8,
    weight: u16,
    stretch: u16,
    style: Style,
};
pub const ManifestEntry = impl.FontManifestEntry;
pub const Query = impl.FontQuery;
pub const Source = impl.FontSource;
pub const Style = impl.FontStyle;

pub const Database = struct {
    /// Source-visible implementation storage; use the focused methods below.
    implementation: impl.FontDatabase,

    pub fn init(allocator: std.mem.Allocator) Database {
        return .{
            .implementation = impl.FontDatabase.init(allocator),
        };
    }

    pub fn deinit(self: *Database) void {
        self.implementation.deinit();
    }

    pub fn addFace(
        self: *Database,
        face: *const face_mod.Face,
    ) !usize {
        return implMut(self).addFont(face_mod.backend.font(face));
    }

    pub fn addBytes(self: *Database, bytes: []const u8) !usize {
        return implMut(self).addFontBytes(bytes);
    }

    pub fn addBytesWithLimit(
        self: *Database,
        bytes: []const u8,
        max_decoded_size: usize,
    ) !usize {
        return implMut(self).addFontBytesWithLimit(
            bytes,
            max_decoded_size,
        );
    }

    pub fn addCollectionBytes(
        self: *Database,
        bytes: []const u8,
    ) !usize {
        return implMut(self).addFontCollectionBytes(bytes);
    }

    pub fn addCollectionBytesWithLimit(
        self: *Database,
        bytes: []const u8,
        max_decoded_size: usize,
    ) !usize {
        return implMut(self).addFontCollectionBytesWithLimit(
            bytes,
            max_decoded_size,
        );
    }

    pub fn addFile(
        self: *Database,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
        limit: std.Io.Limit,
    ) !usize {
        return implMut(self).addFontFile(io, dir, path, limit);
    }

    pub fn addCollectionFile(
        self: *Database,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
        limit: std.Io.Limit,
    ) !usize {
        return implMut(self).addFontCollectionFile(
            io,
            dir,
            path,
            limit,
        );
    }

    pub fn scanDirectory(
        self: *Database,
        io: std.Io,
        dir: std.Io.Dir,
        limit: std.Io.Limit,
    ) !usize {
        return implMut(self).scanFontDir(io, dir, limit);
    }

    pub fn scanTree(
        self: *Database,
        io: std.Io,
        dir: std.Io.Dir,
        limit: std.Io.Limit,
    ) !usize {
        return implMut(self).scanFontTree(io, dir, limit);
    }

    pub fn scanSources(
        self: *Database,
        io: std.Io,
        root: std.Io.Dir,
        sources: []const Source,
        limit: std.Io.Limit,
    ) !usize {
        return implMut(self).scanFontSources(
            io,
            root,
            sources,
            limit,
        );
    }

    pub fn match(
        self: *const Database,
        query: Query,
    ) ?FaceInfo {
        const info = implConst(self).match(query) orelse return null;
        return .{
            .face = info.face,
            .family = info.family,
            .subfamily = info.subfamily,
            .full_name = info.full_name,
            .postscript_name = info.postscript_name,
            .weight = info.weight,
            .stretch = info.stretch,
            .style = info.style,
        };
    }

    /// The returned pointer slice is allocator-owned; all faces are borrowed
    /// from the database and remain valid only until database deinitialization.
    pub fn facesForText(
        self: *const Database,
        allocator: std.mem.Allocator,
        query: Query,
        text: []const u8,
    ) ![]*const face_mod.Face {
        const fonts = try implConst(self).buildCascadeForText(
            allocator,
            query,
            text,
        );
        return @as(
            [*]*const face_mod.Face,
            @ptrCast(fonts.ptr),
        )[0..fonts.len];
    }

    pub fn cascadeForText(
        self: *const Database,
        allocator: std.mem.Allocator,
        query: Query,
        text: []const u8,
    ) !face_mod.Cascade {
        return .{ .faces = try self.facesForText(allocator, query, text) };
    }

    pub fn layoutAttributed(
        self: *const Database,
        allocator: std.mem.Allocator,
        attributed: anytype,
        default_query: Query,
        max_width: f32,
    ) !@import("../../text/attributed/font_resolution.zig").ResultType(
        @TypeOf(attributed),
    ) {
        return implConst(self).layoutAttributedParagraphUtf8(
            allocator,
            attributed,
            default_query,
            max_width,
        );
    }

    pub fn measureAttributed(
        self: *const Database,
        allocator: std.mem.Allocator,
        attributed: anytype,
        default_query: Query,
        max_width: f32,
    ) !@import("../../layout.zig").TextMetrics {
        return implConst(self).measureAttributedTextUtf8(
            allocator,
            attributed,
            default_query,
            max_width,
        );
    }

    pub fn familyCount(self: *const Database) usize {
        return implConst(self).familyCount();
    }

    pub fn familyNames(
        self: *const Database,
        allocator: std.mem.Allocator,
    ) ![][]const u8 {
        return implConst(self).familyNames(allocator);
    }

    pub fn faceIndices(
        self: *const Database,
        allocator: std.mem.Allocator,
        family: []const u8,
    ) ![]usize {
        return implConst(self).faceIndicesForFamily(allocator, family);
    }

    pub fn manifest(
        self: *const Database,
        allocator: std.mem.Allocator,
    ) ![]ManifestEntry {
        return implConst(self).manifest(allocator);
    }

    pub fn freeManifest(
        allocator: std.mem.Allocator,
        entries: []ManifestEntry,
    ) void {
        impl.FontDatabase.freeManifest(allocator, entries);
    }
};

fn implMut(database: *Database) *impl.FontDatabase {
    return &database.implementation;
}

fn implConst(database: *const Database) *const impl.FontDatabase {
    return &database.implementation;
}
