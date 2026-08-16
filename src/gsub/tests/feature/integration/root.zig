//! Whole-table GSUB feature integration test group.

pub fn suite(comptime Bindings: type) type {
    return @import("selection.zig").suite(Bindings);
}
