const std = @import("std");

test {
    std.testing.refAllDecls(@import("text/document/root.zig"));
    std.testing.refAllDecls(@import("api/text/document/root.zig"));
}
