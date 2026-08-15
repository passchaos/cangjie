const std = @import("std");
const face_mod = @import("../../font/face/root.zig");
const Font = @import("../../font.zig").Font;
const layout = @import("../../layout.zig");
const paragraph = @import("paragraph.zig");

pub fn ResultType(comptime Attributed: type) type {
    const primary_style = @TypeOf((@as(Attributed, undefined)).primaryTextStyle());
    return paragraph.Result(primary_style);
}

pub fn layoutAttributed(
    font_database: anytype,
    allocator: std.mem.Allocator,
    attributed: anytype,
    default_query: anytype,
    max_width: f32,
) !ResultType(@TypeOf(attributed)) {
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    var resolved = try ResolvedFonts.init(
        font_database,
        allocator,
        attributed.text,
        runs,
        default_query,
    );
    defer resolved.deinit();
    const spans = try paragraph.layoutSpansForResolvedRuns(
        allocator,
        runs,
        resolved.run_fonts,
    );
    defer allocator.free(spans);

    return try paragraph.layoutResolved(
        allocator,
        resolved.paragraphCascade(),
        attributed,
        runs,
        spans,
        max_width,
    );
}

pub fn measureAttributed(
    font_database: anytype,
    allocator: std.mem.Allocator,
    attributed: anytype,
    default_query: anytype,
    max_width: f32,
) !layout.TextMetrics {
    const runs = try attributed.runs(allocator);
    defer allocator.free(runs);
    var resolved = try ResolvedFonts.init(
        font_database,
        allocator,
        attributed.text,
        runs,
        default_query,
    );
    defer resolved.deinit();
    const spans = try paragraph.layoutSpansForResolvedRuns(
        allocator,
        runs,
        resolved.run_fonts,
    );
    defer allocator.free(spans);
    var buffer = layout.LayoutBuffer.init(allocator);
    defer buffer.deinit();
    return try paragraph.measureResolved(
        resolved.paragraphCascade(),
        &buffer,
        attributed,
        spans,
        max_width,
    );
}

const ResolvedFonts = struct {
    allocator: std.mem.Allocator,
    all_fonts: std.ArrayList(*const Font) = .empty,
    run_fonts: [][]const *const Font,

    fn init(
        font_database: anytype,
        allocator: std.mem.Allocator,
        text: []const u8,
        runs: anytype,
        default_query: anytype,
    ) !ResolvedFonts {
        const run_fonts = try allocator.alloc([]const *const Font, runs.len);
        @memset(run_fonts, &.{});
        var result = ResolvedFonts{
            .allocator = allocator,
            .run_fonts = run_fonts,
        };
        var initialized_runs: usize = 0;
        errdefer {
            for (result.run_fonts[0..initialized_runs]) |fonts| {
                allocator.free(fonts);
            }
            allocator.free(result.run_fonts);
            result.all_fonts.deinit(allocator);
        }

        for (runs, 0..) |run, index| {
            const query = queryForStyle(run.style, default_query);
            // Fallback is allowed to cross families only after the requested
            // primary face has been resolved. Silently treating an unknown
            // family as "pick any font covering this scalar" would make style
            // typos render unpredictably and bypass the caller's default.
            if (font_database.match(query) == null) {
                return error.FontFamilyNotFound;
            }
            const run_text = text[run.byte_range.start..run.byte_range.end()];
            const fonts = try font_database.buildCascadeForText(
                allocator,
                query,
                run_text,
            );
            if (fonts.len == 0) {
                allocator.free(fonts);
                return error.FontFamilyNotFound;
            }
            result.run_fonts[index] = fonts;
            initialized_runs += 1;
            for (fonts) |font| try appendUniqueFont(allocator, &result.all_fonts, font);
        }
        if (result.all_fonts.items.len == 0) {
            const default_face = font_database.match(default_query) orelse
                return error.FontFamilyNotFound;
            try result.all_fonts.append(
                allocator,
                face_mod.backend.font(default_face.face),
            );
        }
        return result;
    }

    fn deinit(self: *ResolvedFonts) void {
        for (self.run_fonts) |fonts| self.allocator.free(fonts);
        self.allocator.free(self.run_fonts);
        self.all_fonts.deinit(self.allocator);
        self.* = undefined;
    }

    fn paragraphCascade(self: *const ResolvedFonts) layout.FontCascade {
        return layout.FontCascade.init(self.all_fonts.items);
    }
};

fn queryForStyle(style: anytype, default_query: anytype) @TypeOf(default_query) {
    return .{
        .family = style.font_family orelse default_query.family,
        .postscript_name = if (style.font_family == null)
            default_query.postscript_name
        else
            null,
        .weight = @intFromEnum(style.font_weight),
        .stretch = style.font_stretch,
        .style = switch (style.font_style) {
            .normal => .normal,
            .italic => .italic,
            .oblique => .oblique,
        },
    };
}

fn appendUniqueFont(
    allocator: std.mem.Allocator,
    fonts: *std.ArrayList(*const Font),
    font: *const Font,
) !void {
    for (fonts.items) |existing| {
        if (existing == font) return;
    }
    try fonts.append(allocator, font);
}
