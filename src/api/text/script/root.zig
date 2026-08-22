//! Unicode script classification and script-run itemization.

const unicode = @import("../../../unicode.zig");

pub const Script = unicode.Script;
pub const Run = unicode.ScriptRun;

pub const of = unicode.scriptForCodepoint;
pub const extensionsContain = unicode.scriptExtensionsContain;
pub const extensionsCount = unicode.scriptExtensionsCount;
pub const hasExplicitExtensions = unicode.hasExplicitScriptExtensions;
pub const collectRuns = unicode.itemizeScriptRuns;
