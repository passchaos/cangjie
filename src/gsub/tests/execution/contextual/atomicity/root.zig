//! Root-bound contextual lookup atomicity test group.

pub fn lookupSuite(comptime Bindings: type) type {
    return @import("lookup.zig").suite(Bindings);
}
