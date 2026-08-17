//! Replay/resume coordination for caller-positioned out-of-flow objects.
//!
//! The resolver owns only reflow policy assembled from caller responses. Text,
//! fonts, shaped content, and final output remain in their existing owners.
//! Each pass is ordinary paragraph layout with concrete options, so one-shot,
//! styled, and retained paths share the same protocol without callbacks or an
//! opaque application layout context inside Cangjie.

const std = @import("std");

const exclusion_mod = @import("exclusions.zig");
const inline_object = @import("../inline_object/root.zig");
const options_mod = @import("options.zig");
const paragraph_types = @import("../types/paragraph.zig");

/// One replay pass and the exact options that must produce its layout.
pub const Pass = struct {
    /// Resolver generation used to reject layouts from an earlier replay.
    generation: u64,
    options: options_mod.Options,
};

/// Source-anchor and line geometry for one unresolved custom object.
pub const PlacementRequest = struct {
    /// Resolver-local token required by `submit`.
    token: u64,
    object_id: u64,
    object_index: usize,
    byte_index: usize,
    line_index: usize,
    /// Fallback top-left position computed at the source marker.
    anchor_x: f32,
    anchor_y: f32,
    /// Physical baseline that owns the marker.
    anchor_baseline_y: f32,
    line_x: f32,
    line_y: f32,
    line_width: f32,
    line_height: f32,
    region_x: f32,
    region_width: f32,
};

pub const Step = union(enum) {
    /// All visible custom objects have absolute placements.
    complete,
    /// The caller must submit geometry, then produce another `pass`.
    place: PlacementRequest,
};

/// Concrete state machine for custom float/out-of-flow placement.
///
/// Typical retained usage:
///
/// 1. `begin(base_options)`.
/// 2. Obtain `pass()` and call `ShapedParagraph.layout` with `pass.options`.
/// 3. Call `next(pass, layout)`.
/// 4. On `.place`, calculate application-owned geometry and `submit` it.
/// 5. Repeat until `.complete`.
///
/// Adding a response can change later anchors because its exclusion is folded
/// into the next ordinary reflow pass. Previously submitted absolute geometry
/// stays fixed. Hidden objects after truncation never yield.
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    base_options: options_mod.Options = undefined,
    effective_exclusions: std.ArrayList(exclusion_mod.Exclusion) = .empty,
    effective_placements: std.ArrayList(inline_object.Placement) = .empty,
    base_placement_count: usize = 0,
    generation: u64 = 0,
    next_token: u64 = 1,
    active: bool = false,
    complete: bool = false,
    pending: ?PlacementRequest = null,

    pub fn init(allocator: std.mem.Allocator) Resolver {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Resolver) void {
        self.effective_placements.deinit(self.allocator);
        self.effective_exclusions.deinit(self.allocator);
        self.* = undefined;
    }

    /// Start a new independent placement session.
    ///
    /// Existing static exclusions and caller-authored custom placements are
    /// copied into resolver storage. All other borrowed option slices retain
    /// their original lifetime requirements.
    pub fn begin(
        self: *Resolver,
        options: options_mod.Options,
    ) !void {
        try options_mod.validate(options);
        // `resolvedOptions` intentionally exposes resolver-owned slices. Take
        // snapshots before capacity growth or clearing so callers can feed
        // those options directly into a new session on the same resolver.
        const input_exclusions = try self.allocator.dupe(
            exclusion_mod.Exclusion,
            options.exclusions,
        );
        defer self.allocator.free(input_exclusions);
        const input_placements = try self.allocator.dupe(
            inline_object.Placement,
            options.out_of_flow_placements,
        );
        defer self.allocator.free(input_placements);

        try self.effective_exclusions.ensureTotalCapacity(
            self.allocator,
            input_exclusions.len,
        );
        try self.effective_placements.ensureTotalCapacity(
            self.allocator,
            input_placements.len,
        );

        self.effective_exclusions.clearRetainingCapacity();
        self.effective_exclusions.appendSliceAssumeCapacity(
            input_exclusions,
        );
        self.effective_placements.clearRetainingCapacity();
        self.effective_placements.appendSliceAssumeCapacity(
            input_placements,
        );
        self.base_placement_count = input_placements.len;
        self.base_options = options;
        self.pending = null;
        self.active = true;
        self.complete = false;
        self.bumpGeneration();
    }

    /// Return options for the current replay generation.
    ///
    /// The borrowed resolver-owned slices remain valid until `submit`, `begin`,
    /// or `deinit`. A pending request must be submitted before another pass can
    /// be produced.
    pub fn pass(self: *const Resolver) !Pass {
        if (!self.active) return error.OutOfFlowResolverNotActive;
        if (self.pending != null) return error.OutOfFlowPlacementPending;
        var options = self.base_options;
        options.exclusions = self.effective_exclusions.items;
        options.out_of_flow_placements = self.effective_placements.items;
        return .{
            .generation = self.generation,
            .options = options,
        };
    }

    /// Inspect a layout produced by `pass`.
    ///
    /// Reusing a stale pass is rejected so an application cannot accidentally
    /// submit geometry derived before a prior exclusion changed reflow.
    pub fn next(
        self: *Resolver,
        pass_value: Pass,
        layout: paragraph_types.ParagraphLayout,
    ) !Step {
        if (!self.active or pass_value.generation != self.generation) {
            return error.StaleOutOfFlowPass;
        }
        if (self.pending) |request| return .{ .place = request };
        if (self.complete) return .complete;

        for (self.effective_placements.items[self.base_placement_count..]) |placement| {
            if (visiblePositionedObject(
                layout.inline_objects,
                placement.byte_index,
            ) == null) {
                // A placement accepted from a visible pass must remain visible.
                // Otherwise a caller could receive `.complete` for a layout
                // that silently dropped an already positioned object because
                // its own exclusion changed truncation or line limits.
                return error.ResolvedOutOfFlowObjectHidden;
            }
        }

        // Yield in stable UTF-8 source order. Final per-line bidi may reorder
        // positioned objects physically, but it must not reorder the caller's
        // placement protocol.
        for (self.base_options.inline_objects, 0..) |object, object_index| {
            if (object.kind != .custom_out_of_flow or
                self.hasPlacement(object.byte_index))
            {
                continue;
            }
            const positioned = visiblePositionedObject(
                layout.inline_objects,
                object.byte_index,
            ) orelse continue; // Truncated or otherwise not visible.
            if (positioned.line_index >= layout.lines.len) {
                return error.InvalidOutOfFlowLayout;
            }
            if (object.id != positioned.id) {
                return error.InvalidOutOfFlowLayout;
            }
            const line = layout.lines[positioned.line_index];
            const request = PlacementRequest{
                .token = self.next_token,
                .object_id = positioned.id,
                .object_index = object_index,
                .byte_index = positioned.byte_index,
                .line_index = positioned.line_index,
                .anchor_x = positioned.anchor_x,
                .anchor_y = positioned.anchor_y,
                .anchor_baseline_y = line.y + line.baseline,
                .line_x = line.x,
                .line_y = line.y,
                .line_width = line.width,
                .line_height = line.height,
                .region_x = line.region_x,
                .region_width = line.region_width,
            };
            self.next_token +%= 1;
            if (self.next_token == 0) self.next_token = 1;
            self.pending = request;
            return .{ .place = request };
        }
        self.complete = true;
        return .complete;
    }

    /// Commit the caller's response and advance to a new replay generation.
    pub fn submit(
        self: *Resolver,
        request: PlacementRequest,
        resolution: inline_object.Resolution,
    ) !void {
        const pending = self.pending orelse
            return error.NoPendingOutOfFlowPlacement;
        if (request.token != pending.token or
            request.object_id != pending.object_id or
            request.object_index != pending.object_index or
            request.byte_index != pending.byte_index)
        {
            return error.StaleOutOfFlowRequest;
        }
        try inline_object.validateGeometry(resolution.geometry);
        if (resolution.exclusion) |item| {
            try exclusion_mod.validate(&.{item});
        }

        try self.effective_placements.ensureTotalCapacity(
            self.allocator,
            self.effective_placements.items.len + 1,
        );
        if (resolution.exclusion != null) {
            try self.effective_exclusions.ensureTotalCapacity(
                self.allocator,
                self.effective_exclusions.items.len + 1,
            );
        }

        self.effective_placements.appendAssumeCapacity(.{
            .byte_index = pending.byte_index,
            .geometry = resolution.geometry,
        });
        if (resolution.exclusion) |item| {
            self.effective_exclusions.appendAssumeCapacity(item);
        }
        self.pending = null;
        self.complete = false;
        self.bumpGeneration();
    }

    /// Return final layout options after `next` reports `.complete`.
    ///
    /// Resolver-owned slices remain valid until the next `begin`, `submit`, or
    /// `deinit`.
    pub fn resolvedOptions(self: *const Resolver) !options_mod.Options {
        if (!self.active or self.pending != null) {
            return error.OutOfFlowPlacementIncomplete;
        }
        if (!self.complete) return error.OutOfFlowPlacementIncomplete;
        return (try self.pass()).options;
    }

    pub fn placements(
        self: *const Resolver,
    ) []const inline_object.Placement {
        return self.effective_placements.items;
    }

    pub fn exclusions(
        self: *const Resolver,
    ) []const exclusion_mod.Exclusion {
        return self.effective_exclusions.items;
    }

    fn hasPlacement(self: *const Resolver, byte_index: usize) bool {
        for (self.effective_placements.items) |placement| {
            if (placement.byte_index == byte_index) return true;
        }
        return false;
    }

    fn bumpGeneration(self: *Resolver) void {
        self.generation +%= 1;
        if (self.generation == 0) self.generation = 1;
    }
};

fn visiblePositionedObject(
    positioned_objects: []const inline_object.Positioned,
    byte_index: usize,
) ?inline_object.Positioned {
    for (positioned_objects) |positioned| {
        if (positioned.byte_index == byte_index) return positioned;
    }
    return null;
}
