//! Root-bound contextual lookup atomicity test group.

pub fn lookupSuite(comptime Bindings: type) type {
    return @import("lookup.zig").suite(Bindings);
}

pub fn nestedSuite(comptime Bindings: type) type {
    return @import("nested.zig").suite(Bindings);
}

pub fn recordsSuite(comptime Bindings: type) type {
    return @import("records.zig").suite(Bindings);
}
