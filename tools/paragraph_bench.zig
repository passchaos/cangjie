//! End-to-end paragraph construction benchmark comparable to Parley's
//! `RangedBuilder::build + break_all_lines + align` default benchmark.

const std = @import("std");
const cangjie = @import("cangjie");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const font_path = args.next() orelse return usage();
    const text_path = args.next() orelse return usage();
    const iterations = try parsePositive(args.next() orelse return usage());
    const sample_count = try parsePositive(args.next() orelse return usage());
    const width = if (args.next()) |value| try parseFinitePositiveFloat(value) else 200.0;
    const phase = if (args.next()) |value| try parsePhase(value) else Phase.layout;
    const direction = if (args.next()) |value| try parseDirection(value) else Direction.auto;
    const style = if (args.next()) |value| try parseStyle(value) else Style.default;
    const fallback_font_path = args.next();
    if (args.next() != null) return usage();
    if ((style == .fallback) != (fallback_font_path != null))
        return error.InvalidArguments;
    if (phase == .reflow and
        style != .default and
        style != .center and
        style != .inline_object and
        style != .out_of_flow_object and
        style != .custom_out_of_flow_object and
        style != .fallback)
    {
        return error.InvalidArguments;
    }

    const font_bytes: []u8 = if (std.mem.eql(u8, font_path, "builtin:minimal"))
        try cangjie.testing.test_font.buildMinimalTtf(allocator)
    else
        try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            font_path,
            allocator,
            .limited(256 * 1024 * 1024),
        );
    defer allocator.free(font_bytes);
    var face = try cangjie.font.Face.parse(allocator, font_bytes);
    defer face.deinit();

    const text_bytes = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        text_path,
        allocator,
        .limited(64 * 1024 * 1024),
    );
    defer allocator.free(text_bytes);
    const source_text = firstLine(text_bytes);
    const object_marker = cangjie.paragraph.object_replacement_utf8;
    const inline_object_index = utf8BoundaryAtOrAfter(
        source_text,
        source_text.len / 2,
    );
    const text = if (style.hasInlineObject())
        try std.mem.concat(
            allocator,
            u8,
            &.{ source_text[0..inline_object_index], object_marker, source_text[inline_object_index..] },
        )
    else
        source_text;
    defer if (style.hasInlineObject()) allocator.free(text);
    if (!std.unicode.utf8ValidateSlice(text)) return error.InvalidUtf8;
    const fallback_bytes: ?[]u8 = if (fallback_font_path) |path|
        try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            path,
            allocator,
            .limited(256 * 1024 * 1024),
        )
    else
        null;
    defer if (fallback_bytes) |bytes_value| allocator.free(bytes_value);
    var fallback_face: ?cangjie.font.Face = if (fallback_bytes) |bytes_value|
        try cangjie.font.Face.parse(allocator, bytes_value)
    else
        null;
    defer if (fallback_face) |*face_value| face_value.deinit();
    const single_faces = [_]*const cangjie.font.Face{&face};
    const fallback_faces = if (fallback_face) |*face_value|
        [_]*const cangjie.font.Face{ &face, face_value }
    else
        undefined;
    const cascade = cangjie.font.Cascade.init(
        if (fallback_face != null) &fallback_faces else &single_faces,
    );
    var engine = cangjie.shaping.Engine.init(allocator, .{});
    defer engine.deinit();
    const paragraph_direction = try resolvedDirection(direction, text);
    const inline_objects = if (style.hasInlineObject())
        &[_]cangjie.paragraph.InlineObject{.{
            .id = 1,
            .byte_index = inline_object_index,
            .width = 24,
            .height = 20,
            .baseline = 15,
            .kind = switch (style) {
                .inline_object => .in_flow,
                .out_of_flow_object => .out_of_flow,
                .custom_out_of_flow_object => .custom_out_of_flow,
                else => unreachable,
            },
        }}
    else
        &.{};
    const object_placements = if (style == .custom_out_of_flow_object)
        &[_]cangjie.paragraph.OutOfFlowPlacement{.{
            .byte_index = inline_object_index,
            .geometry = .{
                .x = 11,
                .y = 13,
                .width = 24,
                .height = 20,
                .baseline = 15,
            },
        }}
    else
        &.{};
    // Center reflow uses the same retained content as start alignment; only
    // line placement changes at the reflow boundary.
    var retained = if (phase == .reflow)
        try engine.prepareParagraph(cascade, .{
            .text = text,
            .font_size = 16,
            .options = .{
                .max_width = width,
                .direction = paragraph_direction,
                .alignment = alignmentForStyle(style),
                .inline_objects = inline_objects,
                .out_of_flow_placements = object_placements,
            },
        })
    else
        null;
    defer if (retained) |*paragraph| paragraph.deinit();
    var reflow = cangjie.paragraph.ReflowBuffer.init(allocator);
    defer reflow.deinit();

    const samples = try allocator.alloc(i128, sample_count);
    defer allocator.free(samples);
    var checksum: u64 = 0;
    var geometry_checksum: u64 = 0;
    var placement_checksum: u64 = 0;
    var object_checksum: u64 = 0;
    var glyph_count: usize = 0;
    var line_count: usize = 0;
    var object_count: usize = 0;
    for (samples) |*sample| {
        for (0..3) |_| {
            const layout = try benchmarkOnce(
                phase,
                &engine,
                cascade,
                text,
                width,
                paragraph_direction,
                style,
                inline_objects,
                object_placements,
                if (retained) |*paragraph| paragraph else null,
                &reflow,
            );
            const current_checksum = layoutChecksum(layout);
            if (checksum != 0 and checksum != current_checksum) return error.UnstableOutput;
            checksum = current_checksum;
            geometry_checksum = try normalizedGeometryChecksum(
                allocator,
                text,
                layout,
                paragraph_direction,
            );
            placement_checksum = placementChecksum(layout);
            object_checksum = normalizedObjectGeometryChecksum(layout);
            glyph_count = layout.glyphs.len;
            line_count = layout.lines.len;
            object_count = layout.inline_objects.len;
        }
        var batch_checksum = std.hash.Wyhash.init(0);
        const start = std.Io.Clock.now(.awake, init.io).nanoseconds;
        for (0..iterations) |_| {
            const layout = try benchmarkOnce(
                phase,
                &engine,
                cascade,
                text,
                width,
                paragraph_direction,
                style,
                inline_objects,
                object_placements,
                if (retained) |*paragraph| paragraph else null,
                &reflow,
            );
            if (layout.glyphs.len != glyph_count or
                layout.lines.len != line_count or
                layout.inline_objects.len != object_count)
            {
                return error.UnstableOutput;
            }
            batch_checksum.update(std.mem.asBytes(&layout.width));
            batch_checksum.update(std.mem.asBytes(&layout.height));
            std.mem.doNotOptimizeAway(layout.glyphs.ptr);
        }
        sample.* = std.Io.Clock.now(.awake, init.io).nanoseconds - start;
        std.mem.doNotOptimizeAway(batch_checksum.final());
    }
    std.mem.sort(i128, samples, {}, std.sort.asc(i128));
    const median = @as(f64, @floatFromInt(samples[samples.len / 2])) /
        @as(f64, @floatFromInt(iterations));
    std.debug.print(
        "engine=cangjie\tphase={s}\tdirection={s}\tstyle={s}\ttext_bytes={d}\twidth={d:.3}\titerations={d}\tsamples={d}\t" ++
            "median_ns_per_iter={d:.3}\tglyphs={d}\tlines={d}\tobjects={d}\tchecksum={x:0>16}\tgeometry_checksum={x:0>16}\tplacement_checksum={x:0>16}\tobject_checksum={x:0>16}\n",
        .{ @tagName(phase), @tagName(direction), @tagName(style), text.len, width, iterations, sample_count, median, glyph_count, line_count, object_count, checksum, geometry_checksum, placement_checksum, object_checksum },
    );
}

const Phase = enum { layout, reflow };
const Direction = enum { auto, ltr, rtl };
const Style = enum {
    default,
    center,
    spacing,
    alternating,
    inline_object,
    out_of_flow_object,
    custom_out_of_flow_object,
    fallback,

    fn hasInlineObject(self: Style) bool {
        return self == .inline_object or
            self == .out_of_flow_object or
            self == .custom_out_of_flow_object;
    }
};

fn benchmarkOnce(
    phase: Phase,
    engine: *cangjie.shaping.Engine,
    cascade: cangjie.font.Cascade,
    text: []const u8,
    width: f32,
    paragraph_direction: cangjie.shaping.Direction,
    style: Style,
    inline_objects: []const cangjie.paragraph.InlineObject,
    object_placements: []const cangjie.paragraph.OutOfFlowPlacement,
    retained: ?*const cangjie.paragraph.Shaped,
    reflow: *cangjie.paragraph.ReflowBuffer,
) !cangjie.paragraph.Layout {
    return switch (phase) {
        .layout => layoutOnce(
            engine,
            cascade,
            text,
            width,
            paragraph_direction,
            style,
            inline_objects,
            object_placements,
        ),
        .reflow => retained.?.layout(reflow, .{
            .max_width = width,
            .direction = paragraph_direction,
            .alignment = alignmentForStyle(style),
            .inline_objects = inline_objects,
            .out_of_flow_placements = object_placements,
        }),
    };
}

fn layoutOnce(
    engine: *cangjie.shaping.Engine,
    cascade: cangjie.font.Cascade,
    text: []const u8,
    width: f32,
    direction: cangjie.shaping.Direction,
    style: Style,
    inline_objects: []const cangjie.paragraph.InlineObject,
    object_placements: []const cangjie.paragraph.OutOfFlowPlacement,
) !cangjie.paragraph.Layout {
    const alignment = alignmentForStyle(style);
    if (style == .spacing) {
        const spans = [_]cangjie.paragraph.StyledSpan{.{
            .byte_start = 0,
            .byte_len = text.len,
            .style_index = 1,
            .font_size = 16,
            .letter_spacing = 0.75,
            .word_spacing = 2.0,
        }};
        return (try engine.layoutStyledWithoutContentWidths(cascade, .{
            .text = text,
            .default_font_size = 16,
            .spans = &spans,
            .options = .{ .max_width = width, .direction = direction, .alignment = alignment },
        })).layout;
    }
    if (style == .alternating) {
        const split = utf8BoundaryAtOrAfter(text, text.len / 2);
        if (split == 0 or split == text.len) {
            const spans = [_]cangjie.paragraph.StyledSpan{.{
                .byte_start = 0,
                .byte_len = text.len,
                .style_index = 2,
                .font_size = 18,
                .letter_spacing = 0.75,
                .word_spacing = 2.0,
            }};
            return (try engine.layoutStyledWithoutContentWidths(cascade, .{
                .text = text,
                .default_font_size = 16,
                .spans = &spans,
                .options = .{ .max_width = width, .direction = direction, .alignment = alignment },
            })).layout;
        }
        const spans = [_]cangjie.paragraph.StyledSpan{
            .{
                .byte_start = 0,
                .byte_len = split,
                .style_index = 1,
                .font_size = 16,
            },
            .{
                .byte_start = split,
                .byte_len = text.len - split,
                .style_index = 2,
                .font_size = 18,
                .letter_spacing = 0.75,
                .word_spacing = 2.0,
            },
        };
        return (try engine.layoutStyledWithoutContentWidths(cascade, .{
            .text = text,
            .default_font_size = 16,
            .spans = &spans,
            .options = .{ .max_width = width, .direction = direction, .alignment = alignment },
        })).layout;
    }
    return engine.layout(cascade, .{
        .text = text,
        .font_size = 16,
        .options = .{
            .max_width = width,
            .direction = direction,
            .alignment = alignment,
            .inline_objects = inline_objects,
            .out_of_flow_placements = object_placements,
        },
    });
}

fn alignmentForStyle(style: Style) cangjie.paragraph.Align {
    return if (style == .center) .center else .start;
}

fn layoutChecksum(layout: cangjie.paragraph.Layout) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (layout.lines) |line| {
        hash = bytes(hash, std.mem.asBytes(&line.byte_start));
        hash = bytes(hash, std.mem.asBytes(&line.byte_len));
        hash = bytes(hash, std.mem.asBytes(&line.width));
    }
    for (layout.glyphs) |glyph| {
        hash = bytes(hash, std.mem.asBytes(&glyph.glyph_id));
        hash = bytes(hash, std.mem.asBytes(&glyph.cluster));
        hash = bytes(hash, std.mem.asBytes(&glyph.x_advance));
        hash = bytes(hash, std.mem.asBytes(&glyph.x_offset));
        hash = bytes(hash, std.mem.asBytes(&glyph.y_offset));
    }
    return hash;
}

/// Hash source-addressable inline geometry shared by both public layout APIs.
/// Baseline/line-height policy and visually retained trailing spaces differ, so
/// those are normalized away rather than pretending native record equality.
fn normalizedGeometryChecksum(
    allocator: std.mem.Allocator,
    text: []const u8,
    layout: cangjie.paragraph.Layout,
    direction: cangjie.shaping.Direction,
) !u64 {
    var geometry = try cangjie.paragraph.buildGeometry(
        allocator,
        text,
        layout,
        .{ .direction = if (direction == .rtl) .rtl else .ltr },
    );
    defer geometry.deinit();
    const Record = struct {
        byte_start: usize,
        byte_len: usize,
        inline_position: f32,
        inline_size: f32,
    };
    var records = std.ArrayList(Record).empty;
    defer records.deinit(allocator);
    var hash: u64 = 0xcbf29ce484222325;
    for (geometry.lines) |line| {
        records.clearRetainingCapacity();
        hash = hashU64(hash, line.byte_start);
        hash = hashU64(hash, line.byte_start + line.byte_len);
        for (line.spans(geometry.spans)) |span| {
            for (span.graphemes(geometry.graphemes)) |grapheme| {
                const trailing = trailingAsciiWhitespace(
                    text,
                    grapheme.byte_start,
                    line.byte_start + line.byte_len,
                );
                try records.append(allocator, .{
                    .byte_start = grapheme.byte_start,
                    .byte_len = grapheme.byte_len,
                    .inline_position = span.bounds.x - line.bounds.x +
                        grapheme.inline_position,
                    .inline_size = if (trailing) 0 else grapheme.inline_size,
                });
            }
        }
        std.mem.sort(Record, records.items, {}, struct {
            fn lessThan(_: void, a: Record, b: Record) bool {
                return a.byte_start < b.byte_start;
            }
        }.lessThan);
        const origin = for (records.items) |record| {
            if (record.inline_size != 0) break record.inline_position;
        } else 0;
        for (records.items) |record| {
            hash = hashU64(hash, record.byte_start);
            hash = hashU64(hash, record.byte_len);
            // Logical geometry is translation invariant. Quantizing relative
            // positions to 1/1024 px removes only floating accumulation noise
            // while preserving every visible local displacement and raw size.
            hash = hashI32(
                hash,
                if (record.inline_size == 0)
                    0
                else
                    canonicalInlinePosition(record.inline_position - origin),
            );
            hash = hashF32(hash, record.inline_size);
        }
    }
    return hash;
}

/// Hash the physical visible-left placement that the logical geometry checksum
/// intentionally removes. Source ranges make the record order addressable,
/// while 1/256-pixel canonicalization tolerates only float accumulation noise.
fn placementChecksum(layout: cangjie.paragraph.Layout) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (layout.lines) |line| {
        hash = hashU64(hash, line.byte_start);
        hash = hashU64(hash, line.byte_start + line.byte_len);
        hash = hashI32(hash, canonicalPlacementPosition(line.x));
    }
    return hash;
}

fn normalizedObjectGeometryChecksum(layout: cangjie.paragraph.Layout) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    hash = hashU64(hash, layout.inline_objects.len);
    for (layout.inline_objects) |object| {
        hash = hashU64Value(hash, object.id);
        hash = hashU64(hash, object.byte_index);
        hash = hashU64(hash, object.line_index);
        hash = hashI32(hash, canonicalInlinePosition(object.x));
        hash = hashI32(hash, canonicalInlinePosition(object.y));
        hash = hashI32(hash, canonicalInlinePosition(object.width));
        hash = hashI32(hash, canonicalInlinePosition(object.height));
        hash = hashI32(hash, canonicalInlinePosition(object.baseline));
    }
    return hash;
}

fn canonicalInlinePosition(value: f32) i32 {
    // 1/1024 px remains four orders of magnitude below the matrix's smallest
    // glyph advance while absorbing the <1.6e-5 px accumulation drift seen
    // when equivalent RTL positions are summed from opposite physical edges.
    const scaled = @round(@as(f64, value) * 1024.0);
    if (scaled <= @as(f64, @floatFromInt(std.math.minInt(i32)))) {
        return std.math.minInt(i32);
    }
    if (scaled >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) {
        return std.math.maxInt(i32);
    }
    return @intFromFloat(scaled);
}

fn canonicalPlacementPosition(value: f32) i32 {
    // Absolute origins combine full-line advances in different physical orders
    // in the two engines. Keep subpixel sensitivity while absorbing their
    // observed one-ULP drift at a 1/1024-pixel rounding boundary.
    const scaled = @round(@as(f64, value) * 256.0);
    if (scaled <= @as(f64, @floatFromInt(std.math.minInt(i32)))) {
        return std.math.minInt(i32);
    }
    if (scaled >= @as(f64, @floatFromInt(std.math.maxInt(i32)))) {
        return std.math.maxInt(i32);
    }
    return @intFromFloat(scaled);
}

fn trailingAsciiWhitespace(text: []const u8, start: usize, end: usize) bool {
    if (start >= end or end > text.len) return false;
    for (text[start..end]) |byte| {
        if (byte != ' ' and byte != '\t') return false;
    }
    return true;
}

fn hashU64(initial: u64, value: usize) u64 {
    const normalized: u64 = @intCast(value);
    return hashU64Value(initial, normalized);
}

fn hashU64Value(initial: u64, value: u64) u64 {
    var encoded: [8]u8 = undefined;
    std.mem.writeInt(u64, &encoded, value, .little);
    return bytes(initial, &encoded);
}

fn hashF32(initial: u64, value: f32) u64 {
    const bits: u32 = @bitCast(value);
    return bytes(initial, std.mem.asBytes(&bits));
}

fn hashI32(initial: u64, value: i32) u64 {
    var encoded: [4]u8 = undefined;
    std.mem.writeInt(i32, &encoded, value, .little);
    return bytes(initial, &encoded);
}

fn bytes(initial: u64, value: []const u8) u64 {
    var hash = initial;
    for (value) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3;
    }
    return hash;
}

fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, text, "\r\n") orelse text.len;
    return text[0..end];
}

fn parsePositive(value: []const u8) !usize {
    const parsed = try std.fmt.parseInt(usize, value, 10);
    if (parsed == 0) return error.InvalidArguments;
    return parsed;
}

fn parseFinitePositiveFloat(value: []const u8) !f32 {
    const parsed = try std.fmt.parseFloat(f32, value);
    if (!std.math.isFinite(parsed) or parsed <= 0) return error.InvalidArguments;
    return parsed;
}

fn parsePhase(value: []const u8) !Phase {
    if (std.mem.eql(u8, value, "layout")) return .layout;
    if (std.mem.eql(u8, value, "reflow")) return .reflow;
    return error.InvalidArguments;
}

fn parseDirection(value: []const u8) !Direction {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "ltr")) return .ltr;
    if (std.mem.eql(u8, value, "rtl")) return .rtl;
    return error.InvalidArguments;
}

fn parseStyle(value: []const u8) !Style {
    if (std.mem.eql(u8, value, "default")) return .default;
    if (std.mem.eql(u8, value, "center")) return .center;
    if (std.mem.eql(u8, value, "spacing")) return .spacing;
    if (std.mem.eql(u8, value, "alternating")) return .alternating;
    if (std.mem.eql(u8, value, "inline-object")) return .inline_object;
    if (std.mem.eql(u8, value, "out-of-flow-object")) return .out_of_flow_object;
    if (std.mem.eql(u8, value, "custom-out-of-flow-object"))
        return .custom_out_of_flow_object;
    if (std.mem.eql(u8, value, "fallback")) return .fallback;
    return error.InvalidArguments;
}

fn utf8BoundaryAtOrAfter(text: []const u8, start: usize) usize {
    var boundary = @min(start, text.len);
    while (boundary < text.len and (text[boundary] & 0xc0) == 0x80) {
        boundary += 1;
    }
    return boundary;
}

fn resolvedDirection(
    direction: Direction,
    text: []const u8,
) !cangjie.shaping.Direction {
    return switch (direction) {
        .auto => switch (try cangjie.text.bidi.direction(text)) {
            .rtl => .rtl,
            else => .ltr,
        },
        .ltr => .ltr,
        .rtl => .rtl,
    };
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        "usage: paragraph-bench FONT TEXT ITERATIONS SAMPLES [WIDTH] [layout|reflow] [auto|ltr|rtl] [default|center|spacing|alternating|inline-object|out-of-flow-object|custom-out-of-flow-object|fallback] [FALLBACK_FONT]\n",
        .{},
    );
    return error.InvalidArguments;
}

test "placement checksum encodes absolute visible-left line origins" {
    const lines = [_]cangjie.paragraph.Line{
        .{
            .glyph_start = 0,
            .glyph_len = 0,
            .run_start = 0,
            .run_len = 0,
            .byte_start = 2,
            .byte_len = 5,
            .x = 12.25,
            .y = 0,
            .width = 20,
            .height = 10,
            .baseline = 8,
            .ascent = 8,
            .descent = 2,
            .leading = 0,
        },
    };
    const layout: cangjie.paragraph.Layout = .{
        .glyphs = &.{},
        .runs = &.{},
        .lines = &lines,
        .width = 20,
        .height = 10,
    };
    try std.testing.expectEqual(
        @as(u64, 0xa677645ffa7e2cbb),
        placementChecksum(layout),
    );

    var translated_lines = lines;
    translated_lines[0].x += 1.0 / 256.0;
    var translated = layout;
    translated.lines = &translated_lines;
    try std.testing.expect(
        placementChecksum(layout) != placementChecksum(translated),
    );
}
