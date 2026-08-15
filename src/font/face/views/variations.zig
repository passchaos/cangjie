//! Variable-font axis discovery and coordinate normalization.

const std = @import("std");

const font_mod = @import("../../../font.zig");

pub const View = opaque {
    pub fn axes(
        self: *const View,
        allocator: std.mem.Allocator,
    ) font_mod.FontError![]font_mod.VariationAxis {
        return font(self).variationAxes(allocator);
    }

    pub fn normalize(
        self: *const View,
        allocator: std.mem.Allocator,
        coordinates: []const font_mod.VariationCoordinate,
    ) font_mod.FontError![]f32 {
        return font(self).normalizedVariationCoordinates(
            allocator,
            coordinates,
        );
    }

    pub fn map(
        self: *const View,
        axis_index: usize,
        normalized: f32,
    ) font_mod.FontError!f32 {
        return font(self).mapVariationCoordinate(axis_index, normalized);
    }

    pub fn instances(
        self: *const View,
        allocator: std.mem.Allocator,
    ) font_mod.FontError![]font_mod.VariationInstance {
        return font(self).variationInstances(allocator);
    }

    pub fn freeInstances(
        self: *const View,
        allocator: std.mem.Allocator,
        instances_value: []font_mod.VariationInstance,
    ) void {
        font(self).freeVariationInstances(allocator, instances_value);
    }
};

fn font(view: *const View) *const font_mod.Font {
    return @ptrCast(@alignCast(view));
}
