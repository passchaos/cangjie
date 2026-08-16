//! CursivePos execution.

const chain = @import("cursive/chain.zig");
const execute = @import("cursive/execute.zig");

pub const Adjustment = execute.Adjustment;
pub const Anchor = execute.Anchor;
pub const Error = execute.Error;
pub const Options = execute.Options;
pub const Parsed = execute.Parsed;
pub const View = execute.View;

pub const build = execute.build;
pub const deinit = execute.deinit;
pub const collect = execute.collect;
pub const collectParsed = execute.collectParsed;
pub const collectAt = execute.collectAt;
pub const appendJoin = chain.appendJoin;
