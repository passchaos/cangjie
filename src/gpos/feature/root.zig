//! GPOS feature activation, planning, and validation surface.

pub const plan = @import("plan/root.zig");
pub const run_selection = @import("run_selection.zig");
pub const selection = @import("selection.zig");
pub const validation = @import("validation.zig");

pub const LookupPlan = plan.LookupPlan;
pub const LookupPlanEntry = plan.LookupPlanEntry;
pub const PlanIdentity = plan.PlanIdentity;
