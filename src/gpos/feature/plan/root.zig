//! Reusable GPOS lookup-plan ownership, construction, and execution.

pub const apply = @import("apply.zig");
pub const build = @import("build.zig");
pub const model = @import("model.zig");

pub const LookupPlan = model.LookupPlan;
pub const LookupPlanEntry = model.LookupPlanEntry;
pub const PlanIdentity = model.PlanIdentity;
pub const applyAfterProof = apply.afterProof;
pub const buildLookupPlan = build.lookupPlan;
