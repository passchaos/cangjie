const std = @import("std");
const cangjie = @import("cangjie");

const max_feature_overrides = 16;
const max_variation_coords = 32;
pub const default_harfrust_bin = "hr-shape";

pub const Engine = enum {
    cangjie,
    coretext,
    harfrust,
    harfbuzz,
    compare_harfrust,
    compare_harfbuzz,

    pub fn fromName(name: []const u8) ?Engine {
        if (std.mem.eql(u8, name, "cangjie")) return .cangjie;
        if (std.mem.eql(u8, name, "coretext")) return .coretext;
        if (std.mem.eql(u8, name, "harfrust")) return .harfrust;
        if (std.mem.eql(u8, name, "harfbuzz")) return .harfbuzz;
        if (std.mem.eql(u8, name, "compare-harfrust")) return .compare_harfrust;
        if (std.mem.eql(u8, name, "compare-harfbuzz")) return .compare_harfbuzz;
        return null;
    }

    pub fn label(self: Engine) []const u8 {
        return switch (self) {
            .cangjie => "cangjie",
            .coretext => "coretext",
            .harfrust => "harfrust",
            .harfbuzz => "harfbuzz",
            .compare_harfrust => "compare-harfrust",
            .compare_harfbuzz => "compare-harfbuzz",
        };
    }
};

pub const BuiltinFont = enum {
    minimal,
    minimal_gsub,
    script_feature,

    pub fn fromName(name: []const u8) ?BuiltinFont {
        if (std.mem.eql(u8, name, "minimal")) return .minimal;
        if (std.mem.eql(u8, name, "minimal-gsub")) return .minimal_gsub;
        if (std.mem.eql(u8, name, "script-feature")) return .script_feature;
        return null;
    }

    pub fn label(self: BuiltinFont) []const u8 {
        return switch (self) {
            .minimal => "builtin:minimal",
            .minimal_gsub => "builtin:minimal-gsub",
            .script_feature => "builtin:script-feature",
        };
    }
};

pub const OutputFormat = enum {
    text,
    tsv,

    pub fn fromName(name: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, name, "text")) return .text;
        if (std.mem.eql(u8, name, "tsv")) return .tsv;
        return null;
    }
};

pub const Direction = enum {
    ltr,
    rtl,
    ttb,
    btt,

    pub fn textDirection(self: Direction) cangjie.TextDirection {
        return switch (self) {
            .ltr, .ttb => .ltr,
            .rtl, .btt => .rtl,
        };
    }

    pub fn writingMode(self: Direction) cangjie.WritingMode {
        return switch (self) {
            .ltr, .rtl => .horizontal_tb,
            .ttb => .vertical_rl,
            .btt => .vertical_lr,
        };
    }

    pub fn textOrientation(self: Direction) cangjie.TextOrientation {
        return switch (self) {
            .ltr, .rtl => .mixed,
            .ttb, .btt => .upright,
        };
    }

    pub fn label(self: Direction) []const u8 {
        return switch (self) {
            .ltr => "ltr",
            .rtl => "rtl",
            .ttb => "ttb",
            .btt => "btt",
        };
    }
};

pub const Options = struct {
    engine: Engine = .cangjie,
    output_format: OutputFormat = .text,
    font_path: ?[]const u8 = null,
    harfrust_bin: []const u8 = default_harfrust_bin,
    harfrust_bin_explicit: bool = false,
    builtin_font: BuiltinFont = .script_feature,
    text: []const u8 = "A",
    text_path: ?[]const u8 = null,
    text_lines: []const []const u8 = &.{},
    size: f32 = 20,
    iterations: usize = 10_000,
    warmup: usize = 1_000,
    samples: usize = 1,
    direction: Direction = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    normalize_clusters_to_graphemes: bool = false,
    script_tag: ?cangjie.OpenTypeScriptTag = null,
    language_tag: ?cangjie.OpenTypeLanguageTag = null,
    script_position: cangjie.ScriptPosition = .normal,
    use_caches: bool = true,
    use_shaped_cache: bool = false,
    profile: bool = false,
    profile_fast_path: bool = false,
    line_summary: bool = false,
    glyph_summary: bool = false,
    not_found_variation_selector_glyph: ?u32 = null,
    feature_override_buf: [max_feature_overrides]cangjie.FeatureOverride = undefined,
    feature_override_count: usize = 0,
    variation_coord_buf: [max_variation_coords]f32 = undefined,
    variation_coord_count: usize = 0,

    pub fn fontLabel(self: Options) []const u8 {
        if (self.font_path) |path| return path;
        return self.builtin_font.label();
    }

    pub fn textLabel(self: Options) []const u8 {
        if (self.text_path) |path| return path;
        return "inline";
    }

    pub fn featureOverrides(self: *const Options) []const cangjie.FeatureOverride {
        return self.feature_override_buf[0..self.feature_override_count];
    }

    pub fn featureOverrideCount(self: Options) usize {
        return self.feature_override_count;
    }

    pub fn normalizedVariationCoords(self: *const Options) []const f32 {
        return self.variation_coord_buf[0..self.variation_coord_count];
    }
};

pub fn writeFeatureTag(buf: *[4]u8, tag: u32) void {
    buf[0] = @intCast((tag >> 24) & 0xff);
    buf[1] = @intCast((tag >> 16) & 0xff);
    buf[2] = @intCast((tag >> 8) & 0xff);
    buf[3] = @intCast(tag & 0xff);
}

pub fn parse(args: []const []const u8) !Options {
    var options = Options{};

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--engine")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.engine = Engine.fromName(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.output_format = OutputFormat.fromName(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--font")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.font_path = args[i];
        } else if (std.mem.eql(u8, arg, "--harfrust-bin")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.harfrust_bin = args[i];
            options.harfrust_bin_explicit = true;
        } else if (std.mem.eql(u8, arg, "--builtin")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.builtin_font = BuiltinFont.fromName(args[i]) orelse return error.InvalidArguments;
            options.font_path = null;
        } else if (std.mem.eql(u8, arg, "--text")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.text = args[i];
            options.text_path = null;
        } else if (std.mem.eql(u8, arg, "--text-file")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.text_path = args[i];
        } else if (std.mem.eql(u8, arg, "--size")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.size = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--iterations")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.iterations = try parsePositiveUsize(args[i]);
        } else if (std.mem.eql(u8, arg, "--warmup")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.warmup = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--samples")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.samples = try parsePositiveUsize(args[i]);
        } else if (std.mem.eql(u8, arg, "--direction")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.direction = parseDirection(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--language")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.language_tag = parseLanguageTag(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--no-bidi-reorder")) {
            options.reorder_bidi = false;
        } else if (std.mem.eql(u8, arg, "--script-position")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.script_position = parseScriptPosition(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--script")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.script_tag = parseScriptTag(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--no-caches")) {
            options.use_caches = false;
            options.use_shaped_cache = false;
        } else if (std.mem.eql(u8, arg, "--shaped-cache")) {
            options.use_shaped_cache = true;
        } else if (std.mem.eql(u8, arg, "--profile")) {
            options.profile = true;
        } else if (std.mem.eql(u8, arg, "--profile-fast-path")) {
            options.profile = true;
            options.profile_fast_path = true;
        } else if (std.mem.eql(u8, arg, "--line-summary")) {
            options.line_summary = true;
        } else if (std.mem.eql(u8, arg, "--glyph-summary")) {
            options.line_summary = true;
            options.glyph_summary = true;
        } else if (std.mem.eql(u8, arg, "--enable-feature")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try appendFeatureOverride(&options, args[i], true);
        } else if (std.mem.eql(u8, arg, "--disable-feature")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try appendFeatureOverride(&options, args[i], false);
        } else if (std.mem.eql(u8, arg, "--variation") or std.mem.eql(u8, arg, "--variations")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try parseVariationCoords(&options, args[i]);
        } else if (std.mem.eql(u8, arg, "--not-found-variation-selector-glyph")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.not_found_variation_selector_glyph = try parseGlyphCodepoint(args[i]);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
        i += 1;
    }

    if (!std.math.isFinite(options.size) or options.size <= 0) return error.InvalidArguments;
    if ((options.engine == .coretext or options.engine == .harfrust or options.engine == .harfbuzz or options.engine == .compare_harfrust or options.engine == .compare_harfbuzz) and options.font_path == null) return error.InvalidArguments;
    return options;
}

fn parseVariationCoords(options: *Options, text: []const u8) !void {
    options.variation_coord_count = 0;
    if (text.len == 0) return;
    var it = std.mem.splitScalar(u8, text, ',');
    while (it.next()) |raw_item| {
        const item = std.mem.trim(u8, raw_item, " \t\r\n");
        if (item.len == 0) return error.InvalidArguments;
        if (options.variation_coord_count >= options.variation_coord_buf.len) return error.InvalidArguments;
        const value = try std.fmt.parseFloat(f32, item);
        if (!std.math.isFinite(value) or value < -1 or value > 1) return error.InvalidArguments;
        options.variation_coord_buf[options.variation_coord_count] = value;
        options.variation_coord_count += 1;
    }
}

fn parsePositiveUsize(text: []const u8) !usize {
    const value = try std.fmt.parseInt(usize, text, 10);
    if (value == 0) return error.InvalidArguments;
    return value;
}

fn parseGlyphCodepoint(text: []const u8) !u32 {
    const value = try std.fmt.parseInt(u32, text, 10);
    if (value == std.math.maxInt(u32)) return error.InvalidArguments;
    return value;
}

fn appendFeatureOverride(options: *Options, tag_text: []const u8, enabled: bool) !void {
    if (tag_text.len != 4) return error.InvalidArguments;
    if (options.feature_override_count >= options.feature_override_buf.len) return error.InvalidArguments;
    const tag_value = runtimeOpenTypeTag(tag_text[0..4]);
    for (options.feature_override_buf[0..options.feature_override_count]) |existing| {
        if (existing.tag == tag_value) return error.InvalidArguments;
    }
    options.feature_override_buf[options.feature_override_count] = .{
        .tag = tag_value,
        .enabled = enabled,
    };
    options.feature_override_count += 1;
}

fn runtimeOpenTypeTag(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

fn parseDirection(text: []const u8) ?Direction {
    if (std.mem.eql(u8, text, "ltr")) return .ltr;
    if (std.mem.eql(u8, text, "rtl")) return .rtl;
    if (std.mem.eql(u8, text, "ttb")) return .ttb;
    if (std.mem.eql(u8, text, "btt")) return .btt;
    return null;
}

fn parseLanguageTag(text: []const u8) ?cangjie.OpenTypeLanguageTag {
    if (std.ascii.eqlIgnoreCase(text, "dflt")) return .dflt;
    if (std.ascii.eqlIgnoreCase(text, "ara")) return .ara;
    if (std.ascii.eqlIgnoreCase(text, "jan")) return .jan;
    if (std.ascii.eqlIgnoreCase(text, "kor")) return .kor;
    if (std.ascii.eqlIgnoreCase(text, "zhh")) return .zhh;
    if (std.ascii.eqlIgnoreCase(text, "zhs")) return .zhs;
    if (std.ascii.eqlIgnoreCase(text, "zht")) return .zht;
    if (std.ascii.eqlIgnoreCase(text, "hin")) return .hin;
    if (std.ascii.eqlIgnoreCase(text, "dhv") or std.ascii.eqlIgnoreCase(text, "dv")) return .dhv;
    return cangjie.openTypeLanguageTagForLocale(text);
}

pub fn harfrustLanguageArgument(tag_value: cangjie.OpenTypeLanguageTag) ?[]const u8 {
    return switch (tag_value) {
        .dflt => null,
        .ara => "ar",
        .jan => "ja",
        .kor => "ko",
        .zhh => "zh-Hant-HK",
        .zhs => "zh-Hans",
        .zht => "zh-Hant",
        .hin => "hi",
        .dhv => "dv",
    };
}

fn parseScriptPosition(text: []const u8) ?cangjie.ScriptPosition {
    if (std.mem.eql(u8, text, "normal")) return .normal;
    if (std.mem.eql(u8, text, "superscript")) return .superscript;
    if (std.mem.eql(u8, text, "subscript")) return .subscript;
    return null;
}

fn parseScriptTag(text: []const u8) ?cangjie.OpenTypeScriptTag {
    if (text.len != 4) return null;
    const tag_value = runtimeOpenTypeTag(text[0..4]);
    return std.enums.fromInt(cangjie.OpenTypeScriptTag, tag_value);
}

pub fn printUsage(args: []const []const u8) void {
    const exe = if (args.len > 0) args[0] else "shape-bench";
    std.debug.print(
        \\usage: {s} [--font font.ttf|font.ttc] [--builtin minimal|minimal-gsub|script-feature] [--text text|--text-file path] [--size px] [--iterations n] [--warmup n]
        \\
        \\options:
        \\  --engine cangjie|coretext|harfrust|harfbuzz|compare-harfrust|compare-harfbuzz
        \\                               shaping engine, default cangjie
        \\  --format text|tsv            output format, default text
        \\  --font PATH                  use a real TTF/OTF/TTC font
        \\  --harfrust-bin PATH          hr-shape binary for --engine harfrust; defaults to $HOME/Work/harfrust/target/release/hr-shape when present, else PATH lookup
        \\  --builtin NAME               use an in-repo smoke fixture, default script-feature
        \\  --text TEXT                  input text, default "A"
        \\  --text-file PATH             read input text from a UTF-8 file
        \\  --size PX                    font size, default 20
        \\  --iterations N               measured iterations, default 10000
        \\  --warmup N                   unmeasured warmup iterations, default 1000
        \\  --samples N                  independent measured samples, default 1
        \\  --direction ltr|rtl|ttb|btt  shaping direction, default ltr
        \\  --language dflt|ara|jan|kor|zhh|zhs|zht|hin|dhv|dv
        \\                               force an OpenType language system
        \\  --no-bidi-reorder            keep logical glyph order after shaping
        \\  --script-position normal|superscript|subscript
        \\  --script TAG                 force a 4-byte OpenType script tag, e.g. arab
        \\  --no-caches                  bypass glyph metric and cmap caches
        \\  --shaped-cache               cache complete shaped runs
        \\  --profile                    collect Cangjie stage timings
        \\  --profile-fast-path          collect timings while keeping validated lookup accelerators active
        \\  --line-summary               print per-line glyph counts and checksums for the first measured iteration
        \\  --glyph-summary              include per-line glyph id lists with --line-summary
        \\  --enable-feature TAG         enable one OpenType feature tag for Cangjie
        \\  --disable-feature TAG        disable one OpenType feature tag for Cangjie
        \\  --variation CSV              comma-separated normalized variation coordinates, e.g. 0.5,-0.25
        \\  --not-found-variation-selector-glyph GLYPH
        \\                               make unsupported variation selectors visible as a zero-advance synthetic glyph
        \\
        \\examples:
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --iterations 50000
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --font /System/Library/Fonts/Supplemental/Arial.ttf --text "Hello world"
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --engine coretext --font /System/Library/Fonts/Supplemental/Arial.ttf --text "Hello world"
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --engine harfrust --font ~/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام"
        \\
    , .{exe});
}
