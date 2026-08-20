const std = @import("std");

const max_variation_coords = 32;

pub const Engine = enum {
    cangjie,
    freetype,
    compare_freetype,

    pub fn fromName(name: []const u8) ?Engine {
        if (std.mem.eql(u8, name, "cangjie")) return .cangjie;
        if (std.mem.eql(u8, name, "freetype")) return .freetype;
        if (std.mem.eql(u8, name, "compare-freetype")) return .compare_freetype;
        return null;
    }

    pub fn label(self: Engine) []const u8 {
        return switch (self) {
            .cangjie => "cangjie",
            .freetype => "freetype",
            .compare_freetype => "compare-freetype",
        };
    }
};

pub const Mode = enum {
    charmap,
    metrics,
    bitmap,
    outline,
    outline_session,
    raster,
    raster_reuse,
    raster_prepared,

    pub fn fromName(name: []const u8) ?Mode {
        if (std.mem.eql(u8, name, "charmap")) return .charmap;
        if (std.mem.eql(u8, name, "metrics")) return .metrics;
        if (std.mem.eql(u8, name, "bitmap")) return .bitmap;
        if (std.mem.eql(u8, name, "outline")) return .outline;
        if (std.mem.eql(u8, name, "outline-session")) return .outline_session;
        if (std.mem.eql(u8, name, "raster")) return .raster;
        if (std.mem.eql(u8, name, "raster-reuse")) return .raster_reuse;
        if (std.mem.eql(u8, name, "raster-prepared")) return .raster_prepared;
        return null;
    }

    pub fn label(self: Mode) []const u8 {
        return switch (self) {
            .charmap => "charmap",
            .metrics => "metrics",
            .bitmap => "bitmap",
            .outline => "outline",
            .outline_session => "outline-session",
            .raster => "raster",
            .raster_reuse => "raster-reuse",
            .raster_prepared => "raster-prepared",
        };
    }
};

pub const BuiltinFont = enum {
    minimal,
    gvar_compound,
    cff2_variation,
    cbdt_bgra,

    pub fn fromName(name: []const u8) ?BuiltinFont {
        if (std.mem.eql(u8, name, "minimal")) return .minimal;
        if (std.mem.eql(u8, name, "gvar-compound")) return .gvar_compound;
        if (std.mem.eql(u8, name, "cff2-variation")) return .cff2_variation;
        if (std.mem.eql(u8, name, "cbdt-bgra")) return .cbdt_bgra;
        return null;
    }

    pub fn label(self: BuiltinFont) []const u8 {
        return switch (self) {
            .minimal => "builtin:minimal",
            .gvar_compound => "builtin:gvar-compound",
            .cff2_variation => "builtin:cff2-variation",
            .cbdt_bgra => "builtin:cbdt-bgra",
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

pub const Options = struct {
    engine: Engine = .cangjie,
    mode: Mode = .outline,
    output_format: OutputFormat = .text,
    font_path: ?[]const u8 = null,
    builtin_font: BuiltinFont = .gvar_compound,
    glyph_id: ?u16 = null,
    codepoint: u21 = 'A',
    font_size: f32 = 200,
    target_size: u32 = 256,
    samples_per_axis: u8 = 4,
    iterations: usize = 10_000,
    warmup: usize = 1_000,
    samples: usize = 1,
    dirty_rect: bool = false,
    variation_coord_buf: [max_variation_coords]f32 = undefined,
    variation_coord_count: usize = 0,

    pub fn fontLabel(self: Options) []const u8 {
        if (self.font_path) |path| return path;
        return self.builtin_font.label();
    }

    pub fn normalizedVariationCoords(self: *const Options) []const f32 {
        return self.variation_coord_buf[0..self.variation_coord_count];
    }
};

pub fn parse(args: []const []const u8) !Options {
    var options = Options{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--engine")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.engine = Engine.fromName(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.mode = Mode.fromName(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--format")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.output_format = OutputFormat.fromName(args[i]) orelse return error.InvalidArguments;
        } else if (std.mem.eql(u8, arg, "--font")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.font_path = args[i];
        } else if (std.mem.eql(u8, arg, "--builtin")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.builtin_font = BuiltinFont.fromName(args[i]) orelse return error.InvalidArguments;
            options.font_path = null;
        } else if (std.mem.eql(u8, arg, "--glyph-id")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.glyph_id = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--codepoint")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.codepoint = try parseCodepoint(args[i]);
        } else if (std.mem.eql(u8, arg, "--font-size")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.font_size = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--target-size")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.target_size = try std.fmt.parseInt(u32, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--samples-per-axis")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.samples_per_axis = try std.fmt.parseInt(u8, args[i], 10);
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
        } else if (std.mem.eql(u8, arg, "--dirty-rect")) {
            options.dirty_rect = true;
        } else if (std.mem.eql(u8, arg, "--variation") or std.mem.eql(u8, arg, "--variations")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try parseVariationCoords(&options, args[i]);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.InvalidArguments;
        } else {
            return error.InvalidArguments;
        }
    }
    if (!std.math.isFinite(options.font_size) or options.font_size <= 0) return error.InvalidArguments;
    if (options.target_size == 0 or options.samples_per_axis == 0 or options.iterations == 0 or options.samples == 0) return error.InvalidArguments;
    if ((options.engine == .freetype or options.engine == .compare_freetype) and
        (options.mode == .outline_session or
            options.mode == .raster_prepared)) return error.InvalidArguments;
    return options;
}

fn parsePositiveUsize(text: []const u8) !usize {
    const value = try std.fmt.parseInt(usize, text, 10);
    if (value == 0) return error.InvalidArguments;
    return value;
}

fn parseCodepoint(text: []const u8) !u21 {
    const has_unicode_prefix = std.mem.startsWith(u8, text, "U+") or std.mem.startsWith(u8, text, "u+");
    const raw = if (has_unicode_prefix) text[2..] else text;
    const has_hex_prefix = std.mem.startsWith(u8, raw, "0x") or std.mem.startsWith(u8, raw, "0X");
    const radix: u8 = if (has_unicode_prefix or has_hex_prefix) 16 else 10;
    const digits = if (has_hex_prefix) raw[2..] else raw;
    const value = try std.fmt.parseInt(u32, digits, radix);
    if (value > 0x10ffff or (value >= 0xd800 and value <= 0xdfff)) return error.InvalidArguments;
    return @intCast(value);
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

pub fn printUsage(args: []const []const u8) void {
    const exe = if (args.len > 0) args[0] else "glyph-bench";
    std.debug.print(
        \\usage: {s} [--engine cangjie|freetype|compare-freetype] [--mode outline|outline-session|raster|raster-reuse|raster-prepared] [--font font.ttf|font.otf] [--builtin minimal|gvar-compound|cff2-variation] [--glyph-id n|--codepoint U+XXXX]
        \\
        \\options:
        \\  --engine NAME        cangjie, freetype, or compare-freetype; default cangjie
        \\  --mode NAME          outline, outline-session, raster, raster-reuse, or raster-prepared; default outline
        \\  --format text|tsv    output format, default text
        \\  --font PATH          use a real font
        \\  --builtin NAME       use an in-repo fixture, default gvar-compound
        \\  --glyph-id N         glyph id to benchmark
        \\  --codepoint VALUE    Unicode scalar when glyph id is not supplied; decimal, 0xHEX, or U+HEX
        \\  --font-size PX       raster font size, default 200
        \\  --target-size PX     raster target size, default 256
        \\  --samples-per-axis N Cangjie raster supersamples per axis, default 4
        \\  --iterations N       measured iterations, default 10000
        \\  --warmup N           unmeasured warmup iterations, default 1000
        \\  --samples N          independent measured samples, default 1
        \\  --dirty-rect         for reused/prepared raster, clear and hash only the clipped glyph rectangle
        \\  --variation CSV      normalized variation coordinates, e.g. 0.5,-0.25
        \\
        \\examples:
        \\  zig build glyph-bench -Doptimize=ReleaseFast -- --engine compare-freetype --mode outline --font ./font.ttf --glyph-id 42 --format tsv
        \\  zig build glyph-bench -Doptimize=ReleaseFast -- --engine compare-freetype --mode raster --font ./font.ttf --glyph-id 42 --samples-per-axis 4 --format tsv
        \\
    , .{exe});
}

test "parse codepoint accepts documented decimal and hexadecimal forms" {
    try std.testing.expectEqual(@as(u21, 'A'), try parseCodepoint("65"));
    try std.testing.expectEqual(@as(u21, 'A'), try parseCodepoint("0x41"));
    try std.testing.expectEqual(@as(u21, 'A'), try parseCodepoint("0X41"));
    try std.testing.expectEqual(@as(u21, 'A'), try parseCodepoint("U+41"));
    try std.testing.expectEqual(@as(u21, 'A'), try parseCodepoint("u+41"));
    try std.testing.expectEqual(@as(u21, 0x1f600), try parseCodepoint("U+1F600"));
}

test "parse codepoint rejects non-scalar values" {
    try std.testing.expectError(error.InvalidArguments, parseCodepoint("U+D800"));
    try std.testing.expectError(error.InvalidArguments, parseCodepoint("U+110000"));
}

test "parse accepts dirty rectangle benchmark mode" {
    const options = try parse(&.{ "glyph-bench", "--mode", "raster-prepared", "--dirty-rect" });
    try std.testing.expect(options.dirty_rect);
}

test "parse accepts reused raster dirty rectangle mode" {
    const options = try parse(&.{ "glyph-bench", "--mode", "raster-reuse", "--dirty-rect" });
    try std.testing.expectEqual(Mode.raster_reuse, options.mode);
    try std.testing.expect(options.dirty_rect);
}
