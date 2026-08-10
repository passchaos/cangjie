const std = @import("std");

const retained_use_fixture_hashes = [_][]const u8{
    "23406a60ab081c4fb15e1596ea1cd4f27ae8443e",
    "2a670df15b73a5dc75a5cc491bde5ac93c5077dc",
    "4afb0e8b9a86bb9bd73a1247de4e33fbe3c1fd93",
    "4cce528e99f600ed9c25a2b69e32eb94a03b4ae8",
    "573d3a3177c9a8646e94c8a0d7b224334340946a",
    "6ff0fbead4462d9f229167b4e6839eceb8465058",
    "7c24183f26d60df414578a0a9f5e79ab9d32a22b",
    "dcf774ca21062e7439f98658b18974ea8b956d0c",
    "f518eb6f6b5eec2946c9fbbbde44e45d46f5e2ac",
    "fbb6c84c9e1fe0c39e152fbe845e51fd81f6748e",
};

const retained_compact_use_gates = [_]struct {
    font_hash: []const u8,
    text_file: []const u8,
}{
    .{
        .font_hash = "3c96e7a303c58475a8c750bf4289bbe73784f37d",
        .text_file = "tests/data/use-indic3-tests.txt",
    },
    .{
        .font_hash = "3cc01fede4debd4b7794ccb1b16cdb9987ea7571",
        .text_file = "tests/data/tai-tham-use-syllable-tests.txt",
    },
};

const retained_corpus_parity_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8,
}{
    .{
        .font_file = "fonts/Roboto-Regular.ttf",
        .text_file = "texts/en-words.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/Roboto-Regular.ttf",
        .text_file = "texts/en-thelittleprince.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/Amiri-Regular.ttf",
        .text_file = "texts/fa-words.txt",
        .direction = "rtl",
    },
    .{
        .font_file = "fonts/Amiri-Regular.ttf",
        .text_file = "texts/fa-thelittleprince.txt",
        .direction = "rtl",
    },
    .{
        .font_file = "fonts/SourceSerifVariable-Roman.ttf",
        .text_file = "texts/en-words.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/SourceSerifVariable-Roman.ttf",
        .text_file = "texts/en-thelittleprince.txt",
        .direction = "ltr",
    },
};

const retained_inline_harfbuzz_parity_gates = [_]struct {
    font_hash: []const u8,
    text: []const u8,
    direction: []const u8,
}{
    .{
        .font_hash = "932ad5132c2761297c74e9976fe25b08e5ffa10b",
        .text = "ড় ঢ় ড় ঢ়",
        .direction = "ltr",
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_harfbuzz = b.option(bool, "enable-harfbuzz", "Build shape-bench with the HarfBuzz reference engine") orelse false;
    const harfbuzz_prefix = b.option([]const u8, "harfbuzz-prefix", "Prefix containing HarfBuzz include/ and lib/");
    const harfbuzz_include_dir = b.option([]const u8, "harfbuzz-include-dir", "Directory containing hb.h and hb-ot.h");
    const harfbuzz_lib_dir = b.option([]const u8, "harfbuzz-lib-dir", "Directory containing libharfbuzz");
    const parity_work_root = b.option([]const u8, "parity-work-root", "Root containing local harfbuzz/ and harfrust/ reference checkouts for shaping parity gates") orelse if (b.graph.environ_map.get("HOME")) |home|
        b.fmt("{s}/Work", .{home})
    else
        null;
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

    const shaping_parity_smoke_step = b.step("shaping-parity-smoke", "Run retained HarfBuzz shaping parity smoke gates");
    const shaping_use_parity_smoke_step = b.step("shaping-use-parity-smoke", "Run retained HarfBuzz USE fixture parity smoke gates");
    const shaping_corpus_parity_smoke_step = b.step("shaping-corpus-parity-smoke", "Run retained HarfBuzz Latin, Arabic, and variable-font corpus parity gates");
    if (!enable_harfbuzz) {
        shaping_parity_smoke_step.dependOn(&b.addFail("shaping-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_use_parity_smoke_step.dependOn(&b.addFail("shaping-use-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_corpus_parity_smoke_step.dependOn(&b.addFail("shaping-corpus-parity-smoke requires -Denable-harfbuzz=true").step);
    } else if (parity_work_root == null) {
        shaping_parity_smoke_step.dependOn(&b.addFail("shaping-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_use_parity_smoke_step.dependOn(&b.addFail("shaping-use-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_corpus_parity_smoke_step.dependOn(&b.addFail("shaping-corpus-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
    } else {
        const work_root = parity_work_root.?;
        const harfrust_benches = b.fmt("{s}/harfrust/harfrust/benches", .{work_root});
        const harfbuzz_in_house_fonts = b.fmt("{s}/harfbuzz/test/shape/data/in-house/fonts", .{work_root});

        const dev_parity_cmd = b.addRunArtifact(shape_bench_exe);
        dev_parity_cmd.addArgs(&.{
            "--engine",    "compare-harfbuzz",
            "--font",      b.fmt("{s}/fonts/NotoSansDevanagari-Regular.ttf", .{harfrust_benches}),
            "--text-file", b.fmt("{s}/texts/hi-words.txt", .{harfrust_benches}),
            "--direction", "ltr",
        });
        shaping_parity_smoke_step.dependOn(&dev_parity_cmd.step);

        const duployan_parity_cmd = b.addRunArtifact(shape_bench_exe);
        duployan_parity_cmd.addArgs(&.{
            "--engine",    "compare-harfbuzz",
            "--font",      b.fmt("{s}/harfbuzz/perf/fonts/NotoSansDuployan-Regular.otf", .{work_root}),
            "--text-file", b.fmt("{s}/texts/duployan.txt", .{harfrust_benches}),
            "--direction", "ltr",
        });
        shaping_parity_smoke_step.dependOn(&duployan_parity_cmd.step);

        for (retained_corpus_parity_gates) |gate| {
            const corpus_parity_cmd = b.addRunArtifact(shape_bench_exe);
            corpus_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfrust_benches, gate.font_file }),
                "--text-file", b.fmt("{s}/{s}", .{ harfrust_benches, gate.text_file }),
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&corpus_parity_cmd.step);

            const corpus_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            corpus_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfrust_benches, gate.font_file }),
                "--text-file", b.fmt("{s}/{s}", .{ harfrust_benches, gate.text_file }),
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&corpus_harfrust_parity_cmd.step);
        }
        for (retained_inline_harfbuzz_parity_gates) |gate| {
            const inline_parity_cmd = b.addRunArtifact(shape_bench_exe);
            inline_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text",      gate.text,
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&inline_parity_cmd.step);
        }
        shaping_parity_smoke_step.dependOn(shaping_corpus_parity_smoke_step);

        for (retained_use_fixture_hashes) |hash| {
            const use_parity_cmd = b.addRunArtifact(shape_bench_exe);
            use_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, hash }),
                "--text-file", b.fmt("tests/data/use/{s}.txt", .{hash}),
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&use_parity_cmd.step);

            const use_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            use_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, hash }),
                "--text-file", b.fmt("tests/data/use/{s}.txt", .{hash}),
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&use_harfrust_parity_cmd.step);
        }
        for (retained_compact_use_gates) |gate| {
            const compact_use_parity_cmd = b.addRunArtifact(shape_bench_exe);
            compact_use_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&compact_use_parity_cmd.step);

            const compact_use_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            compact_use_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&compact_use_harfrust_parity_cmd.step);
        }
        shaping_parity_smoke_step.dependOn(shaping_use_parity_smoke_step);
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
