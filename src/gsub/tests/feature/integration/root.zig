//! Whole-table GSUB feature integration test group.

pub fn applicationSuite(comptime Bindings: type) type {
    return @import("application.zig").suite(Bindings);
}

pub fn selectionSuite(comptime Bindings: type) type {
    return @import("selection.zig").suite(Bindings);
}
