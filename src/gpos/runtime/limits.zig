//! Safety limits shared by GPOS validation and execution.

const options_module = @import("options.zig");

/// Maximum number of PosLookupRecord edges in one contextual call stack.
/// ExtensionPos wrappers do not add depth because they are part of the lookup
/// selected by the record rather than another record edge.
pub const max_context_depth: usize = 16;

pub const Error = error{UnsupportedGpos};
pub const Options = options_module.Options;

/// Enter one nested contextual lookup while preserving GPOS's existing public
/// error contract. Checking before addition also makes hostile `usize` option
/// values safe instead of relying on arithmetic overflow behavior.
pub fn enterContext(run: Options) Error!Options {
    if (run.context_depth >= max_context_depth) {
        return error.UnsupportedGpos;
    }
    var nested = run;
    nested.context_depth = run.context_depth + 1;
    return nested;
}
