const std = @import("std");
const test_font = @import("test_font");

pub fn main(init: std.process.Init) !void {
    try test_font.writeGlyphNameFixtures(
        init.io,
        init.gpa,
        std.Io.Dir.cwd(),
    );
    try test_font.writeAttributeFixtures(
        init.io,
        init.gpa,
        std.Io.Dir.cwd(),
    );
}
