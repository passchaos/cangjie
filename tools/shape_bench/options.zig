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
    compare_coretext,
    compare_harfrust,
    compare_harfbuzz,

    pub fn fromName(name: []const u8) ?Engine {
        if (std.mem.eql(u8, name, "cangjie")) return .cangjie;
        if (std.mem.eql(u8, name, "coretext")) return .coretext;
        if (std.mem.eql(u8, name, "harfrust")) return .harfrust;
        if (std.mem.eql(u8, name, "harfbuzz")) return .harfbuzz;
        if (std.mem.eql(u8, name, "compare-coretext")) return .compare_coretext;
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
            .compare_coretext => "compare-coretext",
            .compare_harfrust => "compare-harfrust",
            .compare_harfbuzz => "compare-harfbuzz",
        };
    }
};

pub const BuiltinFont = enum {
    minimal,
    minimal_gsub,
    script_feature,
    kerx,
    kerx_format_1,
    kerx_format_2,
    kerx_format_4,
    kerx_format_4_ankr,
    kerx_format_6,
    kerx_cross_format_0,
    kerx_cross_format_2,
    kerx_cross_format_6,
    kerx_cross_vertical_format_0,
    kerx_cross_vertical_format_2,
    kerx_cross_vertical_format_6,
    kerx_cross_format_1,
    kerx_cross_vertical_format_1,
    kerx_cross_format_1_reset,
    mort,

    pub fn fromName(name: []const u8) ?BuiltinFont {
        if (std.mem.eql(u8, name, "minimal")) return .minimal;
        if (std.mem.eql(u8, name, "minimal-gsub")) return .minimal_gsub;
        if (std.mem.eql(u8, name, "script-feature")) return .script_feature;
        if (std.mem.eql(u8, name, "kerx")) return .kerx;
        if (std.mem.eql(u8, name, "kerx-format-1")) return .kerx_format_1;
        if (std.mem.eql(u8, name, "kerx-format-2")) return .kerx_format_2;
        if (std.mem.eql(u8, name, "kerx-format-4")) return .kerx_format_4;
        if (std.mem.eql(u8, name, "kerx-format-4-ankr")) return .kerx_format_4_ankr;
        if (std.mem.eql(u8, name, "kerx-format-6")) return .kerx_format_6;
        if (std.mem.eql(u8, name, "kerx-cross-format-0")) return .kerx_cross_format_0;
        if (std.mem.eql(u8, name, "kerx-cross-format-2")) return .kerx_cross_format_2;
        if (std.mem.eql(u8, name, "kerx-cross-format-6")) return .kerx_cross_format_6;
        if (std.mem.eql(u8, name, "kerx-cross-vertical-format-0")) return .kerx_cross_vertical_format_0;
        if (std.mem.eql(u8, name, "kerx-cross-vertical-format-2")) return .kerx_cross_vertical_format_2;
        if (std.mem.eql(u8, name, "kerx-cross-vertical-format-6")) return .kerx_cross_vertical_format_6;
        if (std.mem.eql(u8, name, "kerx-cross-format-1")) return .kerx_cross_format_1;
        if (std.mem.eql(u8, name, "kerx-cross-vertical-format-1")) return .kerx_cross_vertical_format_1;
        if (std.mem.eql(u8, name, "kerx-cross-format-1-reset")) return .kerx_cross_format_1_reset;
        if (std.mem.eql(u8, name, "mort")) return .mort;
        return null;
    }

    pub fn label(self: BuiltinFont) []const u8 {
        return switch (self) {
            .minimal => "builtin:minimal",
            .minimal_gsub => "builtin:minimal-gsub",
            .script_feature => "builtin:script-feature",
            .kerx => "builtin:kerx",
            .kerx_format_1 => "builtin:kerx-format-1",
            .kerx_format_2 => "builtin:kerx-format-2",
            .kerx_format_4 => "builtin:kerx-format-4",
            .kerx_format_4_ankr => "builtin:kerx-format-4-ankr",
            .kerx_format_6 => "builtin:kerx-format-6",
            .kerx_cross_format_0 => "builtin:kerx-cross-format-0",
            .kerx_cross_format_2 => "builtin:kerx-cross-format-2",
            .kerx_cross_format_6 => "builtin:kerx-cross-format-6",
            .kerx_cross_vertical_format_0 => "builtin:kerx-cross-vertical-format-0",
            .kerx_cross_vertical_format_2 => "builtin:kerx-cross-vertical-format-2",
            .kerx_cross_vertical_format_6 => "builtin:kerx-cross-vertical-format-6",
            .kerx_cross_format_1 => "builtin:kerx-cross-format-1",
            .kerx_cross_vertical_format_1 => "builtin:kerx-cross-vertical-format-1",
            .kerx_cross_format_1_reset => "builtin:kerx-cross-format-1-reset",
            .mort => "builtin:mort",
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
    hide_gsub_table: bool = false,
    export_font_path: ?[]const u8 = null,
    face_index: usize = 0,
    harfrust_bin: []const u8 = default_harfrust_bin,
    harfrust_bin_explicit: bool = false,
    builtin_font: BuiltinFont = .script_feature,
    text: []const u8 = "A",
    text_path: ?[]const u8 = null,
    text_lines: []const []const u8 = &.{},
    text_before: []const u8 = "",
    text_after: []const u8 = "",
    size: f32 = 20,
    font_slant: f32 = 0,
    font_bold_x: f32 = 0,
    font_bold_y: f32 = 0,
    iterations: usize = 10_000,
    warmup: usize = 1_000,
    samples: usize = 1,
    direction: Direction = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    cluster_level: ?cangjie.ClusterLevel = null,
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
    compare_positions: bool = true,
    expected_glyph_ids: ?[]const u8 = null,
    expected_clusters: ?[]const u8 = null,
    expected_x_advances: ?[]const u8 = null,
    expected_y_advances: ?[]const u8 = null,
    expected_x_offsets: ?[]const u8 = null,
    expected_y_offsets: ?[]const u8 = null,
    show_flags: bool = false,
    show_extents: bool = false,
    unsafe_to_concat: bool = false,
    not_found_variation_selector_glyph: ?u32 = null,
    feature_override_buf: [max_feature_overrides]cangjie.FeatureOverride = undefined,
    feature_override_count: usize = 0,
    variation_coord_buf: [max_variation_coords]f32 = undefined,
    variation_coord_count: usize = 0,
    variation_design_coord_buf: [max_variation_coords]cangjie.VariationCoordinate = undefined,
    variation_design_coord_count: usize = 0,

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

    pub fn variationCoordCount(self: *const Options) usize {
        return self.variation_coord_count + self.variation_design_coord_count;
    }

    pub fn normalizedVariationCoords(self: *const Options) []const f32 {
        return self.variation_coord_buf[0..self.variation_coord_count];
    }

    pub fn designVariationCoords(self: *const Options) []const cangjie.VariationCoordinate {
        return self.variation_design_coord_buf[0..self.variation_design_coord_count];
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
        } else if (std.mem.eql(u8, arg, "--hide-gsub-table")) {
            options.hide_gsub_table = true;
        } else if (std.mem.eql(u8, arg, "--export-font")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.export_font_path = args[i];
        } else if (std.mem.eql(u8, arg, "--face-index")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.face_index = try std.fmt.parseInt(usize, args[i], 10);
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
        } else if (std.mem.eql(u8, arg, "--text-before")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.text_before = args[i];
        } else if (std.mem.eql(u8, arg, "--text-after")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.text_after = args[i];
        } else if (std.mem.eql(u8, arg, "--size")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.size = try std.fmt.parseFloat(f32, args[i]);
        } else if (std.mem.eql(u8, arg, "--font-slant")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.font_slant = try parseFiniteFloat(args[i]);
        } else if (std.mem.eql(u8, arg, "--font-bold")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try parseFontBold(&options, args[i]);
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
        } else if (std.mem.eql(u8, arg, "--native-direction-shaping")) {
            options.native_direction_shaping = true;
        } else if (std.mem.eql(u8, arg, "--bot")) {
            options.beginning_of_text = true;
        } else if (std.mem.eql(u8, arg, "--eot")) {
            options.end_of_text = true;
        } else if (std.mem.eql(u8, arg, "--cluster-level")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.cluster_level = parseClusterLevel(args[i]) orelse return error.InvalidArguments;
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
        } else if (std.mem.eql(u8, arg, "--no-positions")) {
            options.compare_positions = false;
        } else if (std.mem.eql(u8, arg, "--expect-glyph-ids")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.expected_glyph_ids = args[i];
        } else if (std.mem.eql(u8, arg, "--expect-clusters")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.expected_clusters = args[i];
        } else if (std.mem.eql(u8, arg, "--expect-x-advances")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.expected_x_advances = args[i];
        } else if (std.mem.eql(u8, arg, "--expect-y-advances")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.expected_y_advances = args[i];
        } else if (std.mem.eql(u8, arg, "--expect-x-offsets")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.expected_x_offsets = args[i];
        } else if (std.mem.eql(u8, arg, "--expect-y-offsets")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            options.expected_y_offsets = args[i];
        } else if (std.mem.eql(u8, arg, "--show-flags")) {
            options.line_summary = true;
            options.glyph_summary = true;
            options.show_flags = true;
        } else if (std.mem.eql(u8, arg, "--show-extents")) {
            options.line_summary = true;
            options.glyph_summary = true;
            options.show_extents = true;
        } else if (std.mem.eql(u8, arg, "--unsafe-to-concat")) {
            options.unsafe_to_concat = true;
        } else if (std.mem.eql(u8, arg, "--enable-feature")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try appendFeatureOverride(&options, args[i], 1);
        } else if (std.mem.eql(u8, arg, "--disable-feature")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            try appendFeatureOverride(&options, args[i], 0);
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
    if (!std.math.isFinite(options.font_slant) or !std.math.isFinite(options.font_bold_x) or !std.math.isFinite(options.font_bold_y)) return error.InvalidArguments;
    if ((options.engine == .coretext or options.engine == .harfrust or options.engine == .harfbuzz or options.engine == .compare_coretext or options.engine == .compare_harfrust or options.engine == .compare_harfbuzz) and options.font_path == null) return error.InvalidArguments;
    return options;
}

fn parseFiniteFloat(text: []const u8) !f32 {
    const value = try std.fmt.parseFloat(f32, text);
    if (!std.math.isFinite(value)) return error.InvalidArguments;
    return value;
}

fn parseFontBold(options: *Options, text: []const u8) !void {
    var parts = std.mem.tokenizeAny(u8, text, " ,");
    const x_text = parts.next() orelse return error.InvalidArguments;
    const x = try parseFiniteFloat(x_text);
    const y = if (parts.next()) |y_text| try parseFiniteFloat(y_text) else x;
    if (parts.next() != null) return error.InvalidArguments;
    options.font_bold_x = x;
    options.font_bold_y = y;
}

fn parseVariationCoords(options: *Options, text: []const u8) !void {
    options.variation_coord_count = 0;
    options.variation_design_coord_count = 0;
    if (text.len == 0) return;
    const design_coords = std.mem.indexOfScalar(u8, text, '=') != null;
    var it = std.mem.splitScalar(u8, text, ',');
    while (it.next()) |raw_item| {
        const item = std.mem.trim(u8, raw_item, " \t\r\n");
        if (item.len == 0) return error.InvalidArguments;
        if (design_coords) {
            if (options.variation_design_coord_count >= options.variation_design_coord_buf.len) return error.InvalidArguments;
            const equals = std.mem.indexOfScalar(u8, item, '=') orelse return error.InvalidArguments;
            const tag_text = item[0..equals];
            if (tag_text.len != 4 or equals + 1 >= item.len) return error.InvalidArguments;
            const value = try std.fmt.parseFloat(f32, item[equals + 1 ..]);
            if (!std.math.isFinite(value)) return error.InvalidArguments;
            options.variation_design_coord_buf[options.variation_design_coord_count] = .{
                .tag = tag_text[0..4].*,
                .value = value,
            };
            options.variation_design_coord_count += 1;
        } else {
            if (std.mem.indexOfScalar(u8, item, '=') != null) return error.InvalidArguments;
            if (options.variation_coord_count >= options.variation_coord_buf.len) return error.InvalidArguments;
            const value = try std.fmt.parseFloat(f32, item);
            if (!std.math.isFinite(value) or value < -1 or value > 1) return error.InvalidArguments;
            options.variation_coord_buf[options.variation_coord_count] = value;
            options.variation_coord_count += 1;
        }
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

fn appendFeatureOverride(options: *Options, text: []const u8, default_value: u32) !void {
    const equals = std.mem.indexOfScalar(u8, text, '=');
    const tag_text = if (equals) |index| text[0..index] else text;
    if (tag_text.len != 4) return error.InvalidArguments;
    const value = if (equals) |index| value: {
        if (index + 1 >= text.len) return error.InvalidArguments;
        break :value try std.fmt.parseInt(u32, text[index + 1 ..], 10);
    } else default_value;
    if (options.feature_override_count >= options.feature_override_buf.len) return error.InvalidArguments;
    const tag_value = runtimeOpenTypeTag(tag_text[0..4]);
    for (options.feature_override_buf[0..options.feature_override_count]) |existing| {
        if (existing.tag == tag_value) return error.InvalidArguments;
    }
    options.feature_override_buf[options.feature_override_count] = .{
        .tag = tag_value,
        .enabled = value != 0,
        .value = if (value == 0) 1 else value,
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

fn parseClusterLevel(text: []const u8) ?cangjie.ClusterLevel {
    if (std.mem.eql(u8, text, "0") or std.mem.eql(u8, text, "monotone-graphemes")) return .monotone_graphemes;
    if (std.mem.eql(u8, text, "1") or std.mem.eql(u8, text, "monotone-characters")) return .monotone_characters;
    if (std.mem.eql(u8, text, "2") or std.mem.eql(u8, text, "characters")) return .characters;
    if (std.mem.eql(u8, text, "3") or std.mem.eql(u8, text, "graphemes")) return .graphemes;
    return null;
}

pub fn clusterLevelArgument(level: cangjie.ClusterLevel) []const u8 {
    return switch (level) {
        .monotone_graphemes => "0",
        .monotone_characters => "1",
        .characters => "2",
        .graphemes => "3",
    };
}

fn parseLanguageTag(text: []const u8) ?cangjie.OpenTypeLanguageTag {
    if (std.ascii.eqlIgnoreCase(text, "dflt")) return .dflt;
    if (std.ascii.eqlIgnoreCase(text, "ara")) return .ara;
    if (std.ascii.eqlIgnoreCase(text, "far") or std.ascii.eqlIgnoreCase(text, "fa")) return .far;
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
        .far => "fa",
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
        \\usage: {s} [--font font.ttf|font.ttc|font.dfont] [--face-index n] [--builtin NAME] [--text text|--text-file path] [--size px] [--iterations n] [--warmup n]
        \\
        \\options:
        \\  --engine cangjie|coretext|harfrust|harfbuzz|compare-coretext|compare-harfrust|compare-harfbuzz
        \\                               shaping engine, default cangjie
        \\  --format text|tsv            output format, default text
        \\  --font PATH                  use a real SFNT/TTC/WOFF/DFONT font
        \\  --hide-gsub-table            hide GSUB from both compared engines
        \\  --export-font PATH           write the selected built-in font and exit
        \\  --face-index N              select face N from a font collection
        \\  --harfrust-bin PATH          hr-shape binary for --engine harfrust; defaults to $HOME/Work/harfrust/target/release/hr-shape when present, else PATH lookup
        \\  --builtin NAME               use an in-repo smoke fixture, default script-feature
        \\  --text TEXT                  input text, default "A"
        \\  --text-file PATH             read input text from a UTF-8 file
        \\  --text-before TEXT           pre-context for item shaping
        \\  --text-after TEXT            post-context for item shaping
        \\  --size PX                    font size, default 20
        \\  --font-slant VALUE           synthetic slant ratio for parity output
        \\  --font-bold VALUE[,Y]        synthetic bold x/y strength ratios
        \\  --iterations N               measured iterations, default 10000
        \\  --warmup N                   unmeasured warmup iterations, default 1000
        \\  --samples N                  independent measured samples, default 1
        \\  --direction ltr|rtl|ttb|btt  shaping direction, default ltr
        \\  --language dflt|ara|far|fa|jan|kor|zhh|zhs|zht|hin|dhv|dv
        \\                               force an OpenType language system
        \\  --no-bidi-reorder            keep logical glyph order after shaping
        \\  --native-direction-shaping   shape in OpenType native buffer order
        \\  --bot                        treat text as beginning of paragraph
        \\  --eot                        treat text as end of paragraph
        \\  --cluster-level 0|1|2|3      HarfBuzz-compatible cluster merging level
        \\  --script-position normal|superscript|subscript
        \\  --script TAG                 force a 4-byte OpenType script tag, e.g. arab
        \\  --no-caches                  bypass glyph metric and cmap caches
        \\  --shaped-cache               cache complete shaped runs
        \\  --profile                    collect Cangjie stage timings
        \\  --profile-fast-path          collect timings while keeping validated lookup accelerators active
        \\  --line-summary               print per-line glyph counts and checksums for the first measured iteration
        \\  --glyph-summary              include per-line glyph id lists with --line-summary
        \\  --no-positions               skip advance/offset comparison in compare engines
        \\  --expect-glyph-ids CSV       require first line glyph ids to match
        \\  --expect-clusters CSV        require first line clusters to match
        \\  --expect-x-advances CSV      require first line x advances to match
        \\  --expect-y-advances CSV      require first line y advances to match
        \\  --expect-x-offsets CSV       require first line x offsets to match
        \\  --expect-y-offsets CSV       require first line y offsets to match
        \\  --show-flags                 include per-glyph shaping flags with --glyph-summary
        \\  --show-extents               include per-glyph extents with --glyph-summary
        \\  --unsafe-to-concat           produce unsafe-to-concat glyph flags
        \\  --enable-feature TAG         enable one OpenType feature tag for Cangjie
        \\  --disable-feature TAG        disable one OpenType feature tag for Cangjie
        \\  --variation CSV              comma-separated normalized coordinates or tag=value design coordinates
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
