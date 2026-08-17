//! Font database query and indexed-face records.

const face_mod = @import("../face/root.zig");

pub const Style = enum {
    normal,
    italic,
    oblique,
};

pub const FaceInfo = struct {
    face: *const face_mod.Face,
    family: []const u8,
    subfamily: []const u8,
    full_name: []const u8,
    postscript_name: []const u8,
    weight: u16 = 400,
    stretch: u16 = 100,
    style: Style = .normal,
};

pub const Query = struct {
    family: []const u8,
    postscript_name: ?[]const u8 = null,
    weight: u16 = 400,
    stretch: u16 = 100,
    style: Style = .normal,
};
