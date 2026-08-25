const std = @import("std");
const test_font = @import("test_font");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const output_path = args.next() orelse ".";
    if (args.next() != null) return error.InvalidArguments;
    var output = try std.Io.Dir.cwd().createDirPathOpen(
        init.io,
        output_path,
        .{},
    );
    defer output.close(init.io);

    try test_font.writeGlyphNameFixtures(
        init.io,
        init.gpa,
        output,
    );
    try test_font.writeAttributeFixtures(
        init.io,
        init.gpa,
        output,
    );
}
