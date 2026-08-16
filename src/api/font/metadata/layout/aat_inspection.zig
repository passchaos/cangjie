//! Apple Advanced Typography table inspection.

const std = @import("std");

const face_mod = @import("../../../../font/face/root.zig");
const font = @import("../../../../font.zig");

pub const View = struct {
    face: *const face_mod.Face,

    fn implementation(self: View) *const font.Font {
        return face_mod.backend.font(self.face);
    }

    pub fn anchors(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.AnkrInfo {
        return self.implementation().ankrInfo(allocator);
    }

    pub fn freeAnchors(
        self: View,
        allocator: std.mem.Allocator,
        info: font.AnkrInfo,
    ) void {
        self.implementation().freeAnkrInfo(allocator, info);
    }

    pub fn features(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError![]font.FeatureNameInfo {
        return self.implementation().featFeatures(allocator);
    }

    pub fn freeFeatures(
        self: View,
        allocator: std.mem.Allocator,
        features_value: []font.FeatureNameInfo,
    ) void {
        self.implementation().freeFeatFeatures(
            allocator,
            features_value,
        );
    }

    pub fn tracking(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.TrackTableInfo {
        return self.implementation().trakInfo(allocator);
    }

    pub fn freeTracking(
        self: View,
        allocator: std.mem.Allocator,
        info: font.TrackTableInfo,
    ) void {
        self.implementation().freeTrakInfo(allocator, info);
    }

    pub fn extendedKerning(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.KerxInfo {
        return self.implementation().kerxInfo(allocator);
    }

    pub fn freeExtendedKerning(
        self: View,
        allocator: std.mem.Allocator,
        info: font.KerxInfo,
    ) void {
        self.implementation().freeKerxInfo(allocator, info);
    }

    pub fn glyphMetamorphosis(
        self: View,
        allocator: std.mem.Allocator,
    ) font.FontError!?font.MorxInfo {
        return self.implementation().morxInfo(allocator);
    }

    pub fn freeGlyphMetamorphosis(
        self: View,
        allocator: std.mem.Allocator,
        info: font.MorxInfo,
    ) void {
        self.implementation().freeMorxInfo(allocator, info);
    }
};

pub fn inspect(face: *const face_mod.Face) View {
    return .{ .face = face };
}
