const std = @import("std");
const cangjie = @import("cangjie");

const options_mod = @import("options.zig");
const runner = @import("runner.zig");

const builtin = @import("builtin");

const CFIndex = c_long;
const CGFloat = f64;
const CGGlyph = u16;

const CFTypeRef = *const anyopaque;
const CFArrayRef = CFTypeRef;
const CFAttributedStringRef = CFTypeRef;
const CFDataRef = CFTypeRef;
const CFDictionaryRef = CFTypeRef;
const CFStringRef = CFTypeRef;
const CGDataProviderRef = CFTypeRef;
const CGFontRef = CFTypeRef;
const CTFontRef = CFTypeRef;
const CTLineRef = CFTypeRef;
const CTRunRef = CFTypeRef;

const CFRange = extern struct {
    location: CFIndex,
    length: CFIndex,
};

const CGSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

extern const kCTFontAttributeName: CFStringRef;

extern "c" fn CFRelease(cf: CFTypeRef) void;
extern "c" fn CFArrayGetCount(theArray: CFArrayRef) CFIndex;
extern "c" fn CFArrayGetValueAtIndex(theArray: CFArrayRef, idx: CFIndex) CFTypeRef;
extern "c" fn CFAttributedStringCreate(alloc: ?CFTypeRef, str: CFStringRef, attributes: CFDictionaryRef) ?CFAttributedStringRef;
extern "c" fn CFDataCreate(allocator: ?CFTypeRef, bytes: [*]const u8, length: CFIndex) ?CFDataRef;
extern "c" fn CFDictionaryCreate(
    allocator: ?CFTypeRef,
    keys: [*]const ?CFTypeRef,
    values: [*]const ?CFTypeRef,
    numValues: CFIndex,
    keyCallBacks: ?CFTypeRef,
    valueCallBacks: ?CFTypeRef,
) ?CFDictionaryRef;
extern "c" fn CFStringCreateWithBytes(alloc: ?CFTypeRef, bytes: [*]const u8, numBytes: CFIndex, encoding: u32, isExternalRepresentation: u8) ?CFStringRef;
extern "c" fn CGDataProviderCreateWithCFData(data: CFDataRef) ?CGDataProviderRef;
extern "c" fn CGFontCreateWithDataProvider(provider: CGDataProviderRef) ?CGFontRef;
extern "c" fn CTFontCreateWithGraphicsFont(graphicsFont: CGFontRef, size: CGFloat, matrix: ?CFTypeRef, attributes: ?CFTypeRef) ?CTFontRef;
extern "c" fn CTLineCreateWithAttributedString(attrString: CFAttributedStringRef) ?CTLineRef;
extern "c" fn CTLineGetGlyphRuns(line: CTLineRef) CFArrayRef;
extern "c" fn CTRunGetAdvances(run: CTRunRef, range: CFRange, buffer: [*]CGSize) void;
extern "c" fn CTRunGetGlyphCount(run: CTRunRef) CFIndex;
extern "c" fn CTRunGetGlyphs(run: CTRunRef, range: CFRange, buffer: [*]CGGlyph) void;

const kCFStringEncodingUTF8: u32 = 0x08000100;

pub fn run(io: std.Io, allocator: std.mem.Allocator, font_bytes: []const u8, options: options_mod.Options) !runner.BenchResult {
    if (builtin.target.os.tag != .macos) return error.UnsupportedCoreText;

    const font = try createFont(font_bytes, options.size);
    defer CFRelease(font);
    const inline_text_lines = [_][]const u8{options.text};
    const text_lines = if (options.text_lines.len != 0) options.text_lines else inline_text_lines[0..];
    var line_summaries = std.ArrayList(runner.BenchResult.LineSummary).empty;
    errdefer line_summaries.deinit(allocator);

    var warmup_index: usize = 0;
    while (warmup_index < options.warmup) : (warmup_index += 1) {
        for (text_lines) |text| {
            const line = try createLine(text, font);
            CFRelease(line);
        }
    }

    var checksum: u64 = 0;
    var glyph_count: usize = 0;
    var samples = std.ArrayList(runner.BenchResult.Sample).empty;
    errdefer samples.deinit(allocator);
    var sample_index: usize = 0;
    while (sample_index < options.samples) : (sample_index += 1) {
        var sample_checksum: u64 = 0;
        var sample_glyph_count: usize = 0;
        const sample_start = std.Io.Clock.now(.awake, io).nanoseconds;
        var i: usize = 0;
        while (i < options.iterations) : (i += 1) {
            for (text_lines, 0..) |text, line_index| {
                const line = try createLine(text, font);
                defer CFRelease(line);
                const glyphs = try readLineGlyphs(allocator, line);
                defer allocator.free(glyphs);
                sample_glyph_count += glyphs.len;
                const line_checksum = glyphsChecksum(glyphs);
                sample_checksum = updateChecksumWithLine(sample_checksum, line_checksum);
                if (options.line_summary and sample_index == 0 and i == 0) {
                    try line_summaries.append(allocator, .{
                        .index = line_index,
                        .text_bytes = text.len,
                        .glyph_count = glyphs.len,
                        .checksum = line_checksum,
                        .glyph_ids = if (options.glyph_summary) try glyphIds(allocator, glyphs) else &.{},
                        .clusters = &.{},
                        .x_advances = &.{},
                        .y_advances = &.{},
                        .x_offsets = &.{},
                        .y_offsets = &.{},
                    });
                }
            }
        }
        const sample_elapsed = std.Io.Clock.now(.awake, io).nanoseconds - sample_start;
        try samples.append(allocator, .{
            .index = sample_index,
            .elapsed_ns = sample_elapsed,
            .glyph_count = sample_glyph_count,
            .checksum = sample_checksum,
        });
        glyph_count += sample_glyph_count;
        checksum = updateChecksumWithLine(checksum, sample_checksum);
    }
    var elapsed: i128 = 0;
    for (samples.items) |sample| elapsed += sample.elapsed_ns;

    return .{
        .elapsed_ns = elapsed,
        .glyph_count = glyph_count,
        .checksum = checksum,
        .profile = cangjie.debug.ShapeProfile{},
        .line_summaries = try line_summaries.toOwnedSlice(allocator),
        .samples = try samples.toOwnedSlice(allocator),
    };
}

fn createFont(font_bytes: []const u8, size: f32) !CTFontRef {
    const data = CFDataCreate(null, font_bytes.ptr, @intCast(font_bytes.len)) orelse return error.CoreTextCreateFailed;
    defer CFRelease(data);

    const provider = CGDataProviderCreateWithCFData(data) orelse return error.CoreTextCreateFailed;
    defer CFRelease(provider);

    const cg_font = CGFontCreateWithDataProvider(provider) orelse return error.CoreTextCreateFailed;
    defer CFRelease(cg_font);

    return CTFontCreateWithGraphicsFont(cg_font, @floatCast(size), null, null) orelse error.CoreTextCreateFailed;
}

fn createLine(text: []const u8, font: CTFontRef) !CTLineRef {
    const string = CFStringCreateWithBytes(null, text.ptr, @intCast(text.len), kCFStringEncodingUTF8, 0) orelse return error.CoreTextCreateFailed;
    defer CFRelease(string);

    var keys = [_]?CFTypeRef{kCTFontAttributeName};
    var values = [_]?CFTypeRef{font};
    const attributes = CFDictionaryCreate(
        null,
        keys[0..].ptr,
        values[0..].ptr,
        keys.len,
        null,
        null,
    ) orelse return error.CoreTextCreateFailed;
    defer CFRelease(attributes);

    const attributed = CFAttributedStringCreate(null, string, attributes) orelse return error.CoreTextCreateFailed;
    defer CFRelease(attributed);

    return CTLineCreateWithAttributedString(attributed) orelse error.CoreTextCreateFailed;
}

fn readLineGlyphs(allocator: std.mem.Allocator, line: CTLineRef) ![]CoreTextGlyph {
    const runs = CTLineGetGlyphRuns(line);
    const run_count: usize = @intCast(CFArrayGetCount(runs));

    var glyphs = std.ArrayList(CoreTextGlyph).empty;
    errdefer glyphs.deinit(allocator);
    for (0..run_count) |run_index| {
        const run_ref: CTRunRef = CFArrayGetValueAtIndex(runs, @intCast(run_index));
        const count: usize = @intCast(CTRunGetGlyphCount(run_ref));
        if (count == 0) continue;

        const run_glyphs = try allocator.alloc(CGGlyph, count);
        defer allocator.free(run_glyphs);
        const advances = try allocator.alloc(CGSize, count);
        defer allocator.free(advances);

        CTRunGetGlyphs(run_ref, .{ .location = 0, .length = @intCast(count) }, run_glyphs.ptr);
        CTRunGetAdvances(run_ref, .{ .location = 0, .length = @intCast(count) }, advances.ptr);

        try glyphs.ensureUnusedCapacity(allocator, count);
        for (run_glyphs, advances) |glyph, advance| {
            glyphs.appendAssumeCapacity(.{
                .glyph_id = glyph,
                .x_advance = @floatCast(advance.width),
                .y_advance = @floatCast(advance.height),
            });
        }
    }
    return try glyphs.toOwnedSlice(allocator);
}

fn glyphIds(allocator: std.mem.Allocator, glyphs: []const CoreTextGlyph) ![]const u32 {
    const ids = try allocator.alloc(u32, glyphs.len);
    for (glyphs, ids) |glyph, *id| id.* = glyph.glyph_id;
    return ids;
}

const CoreTextGlyph = struct {
    glyph_id: CGGlyph,
    x_advance: f32,
    y_advance: f32,
};

fn glyphsChecksum(glyphs: []const CoreTextGlyph) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (glyphs) |glyph| {
        hasher.update(std.mem.asBytes(&glyph.glyph_id));
        hasher.update(std.mem.asBytes(&glyph.x_advance));
        hasher.update(std.mem.asBytes(&glyph.y_advance));
    }
    return hasher.final();
}

fn updateChecksumWithLine(seed: u64, line_checksum: u64) u64 {
    var hasher = std.hash.Wyhash.init(seed);
    hasher.update(std.mem.asBytes(&line_checksum));
    return hasher.final();
}
