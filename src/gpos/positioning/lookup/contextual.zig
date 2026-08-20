//! ContextPos and ChainContextPos table grammar.
//!
//! This surface owns bounds-checked navigation of the variable-length context
//! layouts. Glyph matching, nested-lookup recursion, and adjustment mutation
//! remain in the GPOS runtime because they require shaping-run state.

const chaining = @import("contextual/chaining.zig");
const context = @import("contextual/context.zig");
const model = @import("contextual/model.zig");

pub const Error = model.Error;
pub const View = model.View;

pub const RuleSetList = model.RuleSetList;
pub const RuleSet = model.RuleSet;
pub const CoverageRegion = model.CoverageRegion;
pub const PositionRecord = model.PositionRecord;
pub const PositionRecords = model.PositionRecords;
pub const ContextGlyph = model.ContextGlyph;
pub const ContextClass = model.ContextClass;
pub const ContextCoverage = model.ContextCoverage;
pub const Context = model.Context;
pub const ChainingGlyph = model.ChainingGlyph;
pub const ChainingClass = model.ChainingClass;
pub const ChainingCoverage = model.ChainingCoverage;
pub const Chaining = model.Chaining;
pub const ContextRule = model.ContextRule;
pub const ChainingRule = model.ChainingRule;

pub const parseContext = context.parse;
pub const parseContextForValidation = context.parseForValidation;
pub const parseChaining = chaining.parse;
pub const parseChainingForValidation = chaining.parseForValidation;
pub const parseChainingCoverage = chaining.parseCoverage;
pub const parseRuleSet = model.parseRuleSet;
pub const parseRuleSetForValidation = model.parseRuleSetForValidation;
pub const parseContextRule = context.parseRule;
pub const parseContextRuleForValidation = context.parseRuleForValidation;
pub const parseChainingRule = chaining.parseRule;
pub const parseChainingRuleForValidation = chaining.parseRuleForValidation;
