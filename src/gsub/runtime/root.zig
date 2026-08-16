//! GSUB run-lifetime contracts.

pub const dispatch = @import("dispatch.zig");
pub const limits = @import("limits.zig");
pub const metadata = @import("metadata.zig");
pub const options = @import("options.zig");

pub const Limits = limits.Limits;
pub const Options = options.Options;
pub const validateScriptShaperMetadata = metadata.validateScriptShaper;
