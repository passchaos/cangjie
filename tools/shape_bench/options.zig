const std = @import("std");
const cangjie = @import("cangjie");

const max_feature_overrides = 16;

pub const Engine = enum {
    cangjie,
    coretext,

    pub fn fromName(name: []const u8) ?Engine {
        if (std.mem.eql(u8, name, "cangjie")) return .cangjie;
        if (std.mem.eql(u8, name, "coretext")) return .coretext;
        return null;
    }

    pub fn label(self: Engine) []const u8 {
        return switch (self) {
            .cangjie => "cangjie",
            .coretext => "coretext",
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

pub const Options = struct {
    engine: Engine = .cangjie,
    font_path: ?[]const u8 = null,
    builtin_font: BuiltinFont = .script_feature,
    text: []const u8 = "A",
    text_path: ?[]const u8 = null,
    text_lines: []const []const u8 = &.{},
    size: f32 = 20,
    iterations: usize = 10_000,
    warmup: usize = 1_000,
    samples: usize = 1,
    direction: cangjie.TextDirection = .ltr,
    reorder_bidi: bool = true,
    script_position: cangjie.ScriptPosition = .normal,
    use_caches: bool = true,
    use_shaped_cache: bool = false,
    profile: bool = false,
    line_summary: bool = false,
    glyph_summary: bool = false,
    feature_override_buf: [max_feature_overrides]cangjie.FeatureOverride = undefined,
    feature_override_count: usize = 0,

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
};

pub fn parse(args: []const []const u8) !Options {
    var options = Options{};

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--engine")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.engine = Engine.fromName(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--font")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.font_path = args[i];
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
        } else if (std.mem.eql(u8, arg, "--no-bidi-reorder")) {
            options.reorder_bidi = false;
        } else if (std.mem.eql(u8, arg, "--script-position")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.script_position = parseScriptPosition(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--no-caches")) {
            options.use_caches = false;
            options.use_shaped_cache = false;
        } else if (std.mem.eql(u8, arg, "--shaped-cache")) {
            options.use_shaped_cache = true;
        } else if (std.mem.eql(u8, arg, "--profile")) {
            options.profile = true;
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
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
        i += 1;
    }

    if (!std.math.isFinite(options.size) or options.size <= 0) return error.InvalidArguments;
    if (options.engine == .coretext and options.font_path == null) return error.InvalidArguments;
    return options;
}

fn parsePositiveUsize(text: []const u8) !usize {
    const value = try std.fmt.parseInt(usize, text, 10);
    if (value == 0) return error.InvalidArguments;
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

fn parseDirection(text: []const u8) ?cangjie.TextDirection {
    if (std.mem.eql(u8, text, "ltr")) return .ltr;
    if (std.mem.eql(u8, text, "rtl")) return .rtl;
    return null;
}

fn parseScriptPosition(text: []const u8) ?cangjie.ScriptPosition {
    if (std.mem.eql(u8, text, "normal")) return .normal;
    if (std.mem.eql(u8, text, "superscript")) return .superscript;
    if (std.mem.eql(u8, text, "subscript")) return .subscript;
    return null;
}

pub fn printUsage(args: []const []const u8) void {
    const exe = if (args.len > 0) args[0] else "shape-bench";
    std.debug.print(
        \\usage: {s} [--font font.ttf|font.ttc] [--builtin minimal|minimal-gsub|script-feature] [--text text|--text-file path] [--size px] [--iterations n] [--warmup n]
        \\
        \\options:
        \\  --engine cangjie|coretext    shaping engine, default cangjie
        \\  --font PATH                  use a real TTF/OTF/TTC font
        \\  --builtin NAME               use an in-repo smoke fixture, default script-feature
        \\  --text TEXT                  input text, default "A"
        \\  --text-file PATH             read input text from a UTF-8 file
        \\  --size PX                    font size, default 20
        \\  --iterations N               measured iterations, default 10000
        \\  --warmup N                   unmeasured warmup iterations, default 1000
        \\  --samples N                  independent measured samples, default 1
        \\  --direction ltr|rtl          shaping direction, default ltr
        \\  --no-bidi-reorder            keep logical glyph order after shaping
        \\  --script-position normal|superscript|subscript
        \\  --no-caches                  bypass glyph metric and cmap caches
        \\  --shaped-cache               cache complete shaped runs
        \\  --profile                    collect Cangjie stage timings
        \\  --line-summary               print per-line glyph counts and checksums for the first measured iteration
        \\  --glyph-summary              include per-line glyph id lists with --line-summary
        \\  --enable-feature TAG         enable one OpenType feature tag for Cangjie
        \\  --disable-feature TAG        disable one OpenType feature tag for Cangjie
        \\
        \\examples:
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --iterations 50000
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --font /System/Library/Fonts/Supplemental/Arial.ttf --text "Hello world"
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --engine coretext --font /System/Library/Fonts/Supplemental/Arial.ttf --text "Hello world"
        \\
    , .{exe});
}
