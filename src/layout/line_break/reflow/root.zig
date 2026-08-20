//! Paragraph reflow integration surface.
//!
//! Greedy line selection, including the resumable breaker state, lives in
//! `greedy.zig`. Keeping this root intentionally small prevents paragraph
//! callers from depending on the breaker's internal transaction machinery.

const greedy = @import("greedy.zig");
const orchestration = @import("orchestration.zig");

pub const BaselineMetrics = greedy.BaselineMetrics;
pub const alignedLineX = greedy.alignedLineX;
pub const applyPendingJustification = greedy.applyPendingJustification;
pub const advanceGreedy = greedy.advance;
pub const beginGreedy = greedy.begin;
pub const build = orchestration.build;
pub const buildWithJstfShrinkage = orchestration.buildWithJstfShrinkage;
pub const defaultBaselineMetrics = greedy.defaultBaselineMetrics;
pub const GreedyAdvance = greedy.Advance;
pub const GreedyState = greedy.State;
pub const refreshGreedyRegion = greedy.refreshRegion;
pub const resolvedAlignment = greedy.resolvedAlignment;
pub const runRangeForGlyphs = greedy.runRangeForGlyphs;
