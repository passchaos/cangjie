const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_harfbuzz = b.option(bool, "enable-harfbuzz", "Build shape-bench with the HarfBuzz reference engine") orelse false;
    const harfbuzz_prefix = b.option([]const u8, "harfbuzz-prefix", "Prefix containing HarfBuzz include/ and lib/");
    const harfbuzz_include_dir = b.option([]const u8, "harfbuzz-include-dir", "Directory containing hb.h and hb-ot.h");
    const harfbuzz_lib_dir = b.option([]const u8, "harfbuzz-lib-dir", "Directory containing libharfbuzz");
    const imx_dep = b.dependency("imx", .{
        .target = target,
        .optimize = optimize,
    });
    const vort_dep = b.dependency("vort", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("cangjie", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "imx", .module = imx_dep.module("imx") },
            .{ .name = "vort", .module = vort_dep.module("vort") },
        },
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

    const line_break_bench_exe = b.addExecutable(.{
        .name = "cangjie-line-break-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/line_break_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "line_break",
                    .module = b.createModule(.{
                        .root_source_file = b.path("src/text/line_break.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            },
        }),
    });

    const line_break_bench_step = b.step("line-break-bench", "Benchmark streaming Unicode line breaking");
    const line_break_bench_cmd = b.addRunArtifact(line_break_bench_exe);
    line_break_bench_step.dependOn(&line_break_bench_cmd.step);
    if (b.args) |args| {
        line_break_bench_cmd.addArgs(args);
    }

    const reflow_bench_exe = b.addExecutable(.{
        .name = "cangjie-reflow-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/reflow_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });

    const reflow_bench_step = b.step("reflow-bench", "Compare repeated shaping with retained paragraph reflow");
    const reflow_bench_cmd = b.addRunArtifact(reflow_bench_exe);
    reflow_bench_step.dependOn(&reflow_bench_cmd.step);
    if (b.args) |args| {
        reflow_bench_cmd.addArgs(args);
    }

    const freetype_c = b.addTranslateC(.{
        .root_source_file = b.path("tools/glyph_bench/freetype.h"),
        .target = target,
        .optimize = optimize,
    });
    freetype_c.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });

    const shape_bench_options = b.addOptions();
    shape_bench_options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    const shape_bench_mod = b.createModule(.{
        .root_source_file = b.path("tools/shape_bench.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cangjie", .module = mod },
            .{ .name = "shape_bench_options", .module = shape_bench_options.createModule() },
        },
    });
    if (enable_harfbuzz) {
        const harfbuzz_c = b.addTranslateC(.{
            .root_source_file = b.path("tools/shape_bench/harfbuzz.h"),
            .target = target,
            .optimize = optimize,
        });
        if (harfbuzz_prefix) |prefix| {
            const include_dir = b.fmt("{s}/include/harfbuzz", .{prefix});
            const lib_dir = b.fmt("{s}/lib", .{prefix});
            harfbuzz_c.addSystemIncludePath(.{ .cwd_relative = include_dir });
            shape_bench_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
            shape_bench_mod.addRPath(.{ .cwd_relative = lib_dir });
        }
        if (harfbuzz_include_dir) |include_dir| {
            harfbuzz_c.addSystemIncludePath(.{ .cwd_relative = include_dir });
        }
        if (harfbuzz_lib_dir) |lib_dir| {
            shape_bench_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
            shape_bench_mod.addRPath(.{ .cwd_relative = lib_dir });
        }
        if (harfbuzz_prefix == null and harfbuzz_include_dir == null) {
            harfbuzz_c.linkSystemLibrary("harfbuzz", .{ .use_pkg_config = .force });
        }
        shape_bench_mod.linkSystemLibrary("harfbuzz", .{
            .use_pkg_config = if (harfbuzz_prefix == null and harfbuzz_lib_dir == null) .force else .no,
        });
        shape_bench_mod.addImport("harfbuzz", harfbuzz_c.createModule());
    }
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

    const glyph_bench_exe = b.addExecutable(.{
        .name = "cangjie-glyph-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/glyph_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
                .{ .name = "freetype", .module = freetype_c.createModule() },
            },
        }),
    });

    const glyph_bench_step = b.step("glyph-bench", "Benchmark Cangjie glyph outline/raster hot paths");
    const glyph_bench_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_bench_step.dependOn(&glyph_bench_cmd.step);
    if (b.args) |args| {
        glyph_bench_cmd.addArgs(args);
    }

    const bench_smoke_step = b.step("bench-smoke", "Run quick TSV smoke checks for benchmark tools");
    const shape_bench_smoke_cmd = b.addRunArtifact(shape_bench_exe);
    shape_bench_smoke_cmd.addArgs(&.{
        "--engine",     "cangjie",
        "--format",     "tsv",
        "--builtin",    "script-feature",
        "--text",       "A",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&shape_bench_smoke_cmd.step);

    const glyph_outline_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_outline_smoke_cmd.addArgs(&.{
        "--mode",       "outline",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
        "--variation",  "0.5",
    });
    bench_smoke_step.dependOn(&glyph_outline_smoke_cmd.step);

    const glyph_freetype_outline_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_freetype_outline_smoke_cmd.addArgs(&.{
        "--engine",     "freetype",
        "--mode",       "outline",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_freetype_outline_smoke_cmd.step);

    const glyph_freetype_raster_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_freetype_raster_smoke_cmd.addArgs(&.{
        "--engine",     "freetype",
        "--mode",       "raster",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_freetype_raster_smoke_cmd.step);

    const glyph_compare_freetype_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_compare_freetype_smoke_cmd.addArgs(&.{
        "--engine",     "compare-freetype",
        "--mode",       "outline",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_compare_freetype_smoke_cmd.step);

    const glyph_compare_freetype_raster_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_compare_freetype_raster_smoke_cmd.addArgs(&.{
        "--engine",     "compare-freetype",
        "--mode",       "raster",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_compare_freetype_raster_smoke_cmd.step);

    const glyph_raster_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_smoke_cmd.addArgs(&.{
        "--mode",             "raster",
        "--format",           "tsv",
        "--builtin",          "gvar-compound",
        "--iterations",       "1",
        "--warmup",           "0",
        "--samples",          "1",
        "--samples-per-axis", "2",
        "--variation",        "0.5",
    });
    bench_smoke_step.dependOn(&glyph_raster_smoke_cmd.step);

    const glyph_raster_reuse_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_reuse_smoke_cmd.addArgs(&.{
        "--mode",       "raster-reuse",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
        "--variation",  "0.5",
    });
    bench_smoke_step.dependOn(&glyph_raster_reuse_smoke_cmd.step);

    const glyph_raster_prepared_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_prepared_smoke_cmd.addArgs(&.{
        "--mode",       "raster-prepared",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
        "--variation",  "0.5",
    });
    bench_smoke_step.dependOn(&glyph_raster_prepared_smoke_cmd.step);
}
