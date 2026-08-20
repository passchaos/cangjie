//! Variable-font axis discovery and coordinate normalization.

const std = @import("std");

const font_mod = @import("../../../font.zig");

pub const View = struct {
    /// Borrowed source-level view backing; use the methods below.
    implementation: *const font_mod.Font,

    pub fn axes(
        self: View,
        allocator: std.mem.Allocator,
    ) font_mod.FontError![]font_mod.VariationAxis {
        return font_mod.immutable_face_backend.variationAxes(
            self.implementation,
            allocator,
        );
    }

    pub fn normalize(
        self: View,
        allocator: std.mem.Allocator,
        coordinates: []const font_mod.VariationCoordinate,
    ) font_mod.FontError![]f32 {
        return font_mod.immutable_face_backend.normalizedVariationCoordinates(
            self.implementation,
            allocator,
            coordinates,
        );
    }

    pub fn map(
        self: View,
        axis_index: usize,
        normalized: f32,
    ) font_mod.FontError!f32 {
        return font_mod.immutable_face_backend.mapVariationCoordinate(
            self.implementation,
            axis_index,
            normalized,
        );
    }

    pub fn instances(
        self: View,
        allocator: std.mem.Allocator,
    ) font_mod.FontError![]font_mod.VariationInstance {
        return font_mod.immutable_face_backend.variationInstances(
            self.implementation,
            allocator,
        );
    }

    pub fn freeInstances(
        self: View,
        allocator: std.mem.Allocator,
        instances_value: []font_mod.VariationInstance,
    ) void {
        self.implementation.freeVariationInstances(
            allocator,
            instances_value,
        );
    }

    /// Summarize axes and named instances without materializing owned arrays.
    pub fn summary(self: View) font_mod.FontError!font_mod.VariationSummary {
        return font_mod.immutable_face_backend.variationSummary(
            self.implementation,
        );
    }
};
