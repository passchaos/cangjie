//! Cangjie is a modern, cross-platform font and text processing stack.
//!
//! The supported surface is deliberately grouped by responsibility. Import a
//! domain namespace instead of searching a flat package containing hundreds of
//! unrelated font-table, shaping, editor, and renderer declarations.

pub const font = @import("api/font/root.zig");
pub const text = @import("api/text/root.zig");
pub const shaping = @import("api/shaping/root.zig");
pub const paragraph = @import("api/paragraph/root.zig");
pub const render = @import("api/render/root.zig");

test {
    _ = @import("font/face/open.zig");
}
pub const debug = @import("api/debug/root.zig");

/// Repository-owned fixtures and parity boundaries. Applications should not
/// depend on this namespace.
pub const testing = struct {
    pub const test_font = @import("test_font.zig");
    pub const font_container = @import("font/container/root.zig").testing;
    pub const shaping_cluster = @import("unicode/grapheme/shaping_cluster.zig");
};

test {
    _ = @import("tests/root/root.zig");
    _ = @import("layout/tests/cjk_justification.zig");
    _ = @import("layout/tests/dictionary_breaking.zig");
    _ = @import("layout/tests/hyphenation.zig");
    _ = @import("layout/tests/positioning_break_safety.zig");
    _ = @import("shaping/context/tests.zig");
    _ = @import("text/attributed/tests.zig");
    @import("std").testing.refAllDecls(@This());
}
