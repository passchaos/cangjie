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
    const system_font_raster_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/system_font_raster_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });

    const test_step = b.step("test", "Run cangjie font tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(system_font_raster_tests).step);

    const system_font_raster_test_step = b.step("system-font-raster-test", "Run macOS system font raster regression tests");
    system_font_raster_test_step.dependOn(&b.addRunArtifact(system_font_raster_tests).step);

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

    const harfbuzz_c = b.addTranslateC(.{
        .root_source_file = b.path("tools/shape_bench/harfbuzz.h"),
        .target = target,
        .optimize = optimize,
    });
    harfbuzz_c.linkSystemLibrary("harfbuzz", .{});

    const shape_bench_mod = b.createModule(.{
        .root_source_file = b.path("tools/shape_bench.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cangjie", .module = mod },
            .{ .name = "harfbuzz", .module = harfbuzz_c.createModule() },
        },
    });
    if (target.result.os.tag == .macos) {
        shape_bench_mod.linkFramework("CoreFoundation", .{});
        shape_bench_mod.linkFramework("CoreGraphics", .{});
        shape_bench_mod.linkFramework("CoreText", .{});
    }

    const shape_bench_exe = b.addExecutable(.{
        .name = "cangjie-shape-bench",
        .root_module = shape_bench_mod,
    });

    const shape_bench_step = b.step("shape-bench", "Benchmark Cangjie text shaping");
    const shape_bench_cmd = b.addRunArtifact(shape_bench_exe);
    shape_bench_step.dependOn(&shape_bench_cmd.step);
    if (b.args) |args| {
        shape_bench_cmd.addArgs(args);
    }
}
