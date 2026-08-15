//! OpenType SVG render and parse-boundary integration-test group.

test {
    _ = @import("../../../../font/tests/svg/root.zig");
    _ = @import("fills.zig");
    _ = @import("strokes_and_color.zig");
    _ = @import("validation.zig");
}
