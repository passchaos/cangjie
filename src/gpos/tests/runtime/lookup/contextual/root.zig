//! Contextual lookup-execution test group.

test {
    _ = @import("chaining/root.zig");
    _ = @import("context.zig");
    _ = @import("context_class_accelerated.zig");
    _ = @import("matching.zig");
}
