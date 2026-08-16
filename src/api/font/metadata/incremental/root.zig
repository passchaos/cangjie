//! Incremental Font Transfer and patch metadata.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");
const ift = @import("../../../../opentype/ift.zig");

pub const PatchMap = font.IftPatchMapInfo;
pub const TablePatch = font.IftTableKeyedPatchInfo;
pub const GlyphPatch = font.IftGlyphKeyedPatchInfo;

pub const Inspection = struct {
    face: *const face_mod.Face,

    fn implementation(self: Inspection) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn patchMap(self: Inspection) font.FontError!?PatchMap {
        return self.implementation().iftPatchMapInfo();
    }

    pub fn extensionPatchMap(self: Inspection) font.FontError!?PatchMap {
        return self.implementation().iftxPatchMapInfo();
    }
};

pub fn inspect(face: *const face_mod.Face) Inspection {
    return .{ .face = face };
}

pub fn parseTablePatch(
    allocator: std.mem.Allocator,
    patch_data: []const u8,
) !TablePatch {
    return ift.tableKeyedPatchInfo(
        allocator,
        patch_data,
        0,
        patch_data.len,
    );
}

pub fn freeTablePatch(
    allocator: std.mem.Allocator,
    patch: TablePatch,
) void {
    ift.freeTableKeyedPatchInfo(allocator, patch);
}

/// Parse a glyph-keyed patch. `brotli_stream` borrows `patch_data`.
pub fn parseGlyphPatch(patch_data: []const u8) !GlyphPatch {
    return ift.glyphKeyedPatchInfo(patch_data, 0, patch_data.len);
}
