const std = @import("std");
const cangjie = @import("cangjie");

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
    font_path: ?[]const u8 = null,
    builtin_font: BuiltinFont = .script_feature,
    text: []const u8 = "A",
    size: f32 = 20,
    iterations: usize = 10_000,
    warmup: usize = 1_000,
    direction: cangjie.TextDirection = .ltr,
    script_position: cangjie.ScriptPosition = .normal,
    use_caches: bool = true,

    pub fn fontLabel(self: Options) []const u8 {
        if (self.font_path) |path| return path;
        return self.builtin_font.label();
    }
};

pub fn parse(args: []const []const u8) !Options {
    var options = Options{};

    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--font")) {
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
        } else if (std.mem.eql(u8, arg, "--direction")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.direction = parseDirection(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--script-position")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.script_position = parseScriptPosition(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--no-caches")) {
            options.use_caches = false;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
        i += 1;
    }

    if (!std.math.isFinite(options.size) or options.size <= 0) return error.InvalidArguments;
    return options;
}

fn parsePositiveUsize(text: []const u8) !usize {
    const value = try std.fmt.parseInt(usize, text, 10);
    if (value == 0) return error.InvalidArguments;
    return value;
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
        \\usage: {s} [--font font.ttf|font.ttc] [--builtin minimal|minimal-gsub|script-feature] [--text text] [--size px] [--iterations n] [--warmup n]
        \\
        \\options:
        \\  --font PATH                  use a real TTF/OTF/TTC font
        \\  --builtin NAME               use an in-repo smoke fixture, default script-feature
        \\  --text TEXT                  input text, default "A"
        \\  --size PX                    font size, default 20
        \\  --iterations N               measured iterations, default 10000
        \\  --warmup N                   unmeasured warmup iterations, default 1000
        \\  --direction ltr|rtl          shaping direction, default ltr
        \\  --script-position normal|superscript|subscript
        \\  --no-caches                  bypass glyph metric and cmap caches
        \\
        \\examples:
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --iterations 50000
        \\  zig build shape-bench -Doptimize=ReleaseFast -- --font /System/Library/Fonts/Supplemental/Arial.ttf --text "Hello world"
        \\
    , .{exe});
}
