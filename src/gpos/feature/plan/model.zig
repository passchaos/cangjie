//! Owned value types for reusable GPOS lookup execution plans.

const std = @import("std");

/// One stable LookupList tuple selected for a shaping run.
///
/// Keeping the index and its resolved offset together avoids parallel-slice
/// length hazards. At execution time the tuple is rebound to the exact decoded
/// sidecar allocation before either value is trusted.
pub const LookupPlanEntry = struct {
    lookup_index: u16,
    lookup_offset: usize,
};

/// Source allocation and table range from which a plan was derived.
///
/// This is an identity check rather than a content hash or lifetime guard. The
/// backing byte allocation must remain alive and immutable while a plan is in
/// use, just like the decoded lookup sidecars paired with it at execution.
pub const PlanIdentity = struct {
    data_ptr: [*]const u8,
    data_len: usize,
    table_offset: usize,
    table_length: usize,
    accelerators_addr: usize,
    accelerator_count: usize,
};

/// Allocator-owned canonical lookup traversal for one selection key.
///
/// Variation coordinates are deliberately absent. They affect positioning
/// values at execution time and must therefore continue to come from the live
/// run options rather than becoming stale cache state.
pub const LookupPlan = struct {
    entries: []LookupPlanEntry = &.{},
    /// Null is reserved for caller-created values and the no-table sentinel
    /// returned by higher layers. Only the builder can create an executable
    /// plan, including a safely reusable empty one.
    identity: ?PlanIdentity = null,
    /// Optional higher-level identity for cache owners that distinguish Font
    /// objects even when they share one backing byte allocation. The core table
    /// builder intentionally leaves this unset for its caller to bind.
    font_addr: ?usize = null,

    pub fn deinit(self: *LookupPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.* = .{};
    }
};
