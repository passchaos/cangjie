const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("cangjie", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = mod,
    });

    const test_step = b.step("test", "Run cangjie font tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const render_text_exe = b.addExecutable(.{
        .name = "cangjie-render-text",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/render_text.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });

    const render_text_step = b.step("render-text", "Render text from a TTF/OTF font into a grayscale PGM image");
    const render_text_cmd = b.addRunArtifact(render_text_exe);
    render_text_step.dependOn(&render_text_cmd.step);
    if (b.args) |args| {
        render_text_cmd.addArgs(args);
    }
}
