const std = @import("std");
const bin = @import("../binary.zig");

pub const Error = error{BadSfnt} || std.mem.Allocator.Error || error{EndOfStream};

pub const ComponentFlags = struct {
    pub const reset_unspecified_axes: u32 = 1 << 0;
    pub const have_axes: u32 = 1 << 1;
    pub const axis_values_have_variation: u32 = 1 << 2;
    pub const transform_has_variation: u32 = 1 << 3;
    pub const have_translate_x: u32 = 1 << 4;
    pub const have_translate_y: u32 = 1 << 5;
    pub const have_rotation: u32 = 1 << 6;
    pub const have_condition: u32 = 1 << 7;
    pub const have_scale_x: u32 = 1 << 8;
    pub const have_scale_y: u32 = 1 << 9;
    pub const have_center_x: u32 = 1 << 10;
    pub const have_center_y: u32 = 1 << 11;
    pub const gid_is_24bit: u32 = 1 << 12;
    pub const have_skew_x: u32 = 1 << 13;
    pub const have_skew_y: u32 = 1 << 14;
    pub const known_mask: u32 = (1 << 15) - 1;
};

pub const StaticTransform = struct {
    xx: f32 = 1,
    yx: f32 = 0,
    xy: f32 = 0,
    yy: f32 = 1,
    dx: f32 = 0,
    dy: f32 = 0,
};

pub const DecomposedTransform = struct {
    translate_x: f32 = 0,
    translate_y: f32 = 0,
    rotation: f32 = 0,
    scale_x: f32 = 1,
    scale_y: f32 = 1,
    skew_x: f32 = 0,
    skew_y: f32 = 0,
    center_x: f32 = 0,
    center_y: f32 = 0,
};

pub const Component = struct {
    flags: u32,
    glyph_id: u32,
    condition_index: ?u32,
    axis_indices: []const u8 = &.{},
    axis_values: []const u8 = &.{},
    axis_count: usize = 0,
    axis_values_var_index: ?u32 = null,
    transform_var_index: ?u32 = null,
    decomposed_transform: DecomposedTransform,
};

pub fn staticTransform(transform: DecomposedTransform) StaticTransform {
    var result = StaticTransform{
        .dx = transform.translate_x + transform.center_x,
        .dy = transform.translate_y + transform.center_y,
    };
    if (transform.rotation != 0) {
        const radians = transform.rotation * std.math.pi;
        result = mulTransform(result, .{
            .xx = @cos(radians),
            .yx = @sin(radians),
            .xy = -@sin(radians),
            .yy = @cos(radians),
        });
    }
    result = mulTransform(result, .{ .xx = transform.scale_x, .yy = transform.scale_y });
    if (transform.skew_x != 0 or transform.skew_y != 0) {
        result = mulTransform(result, .{
            .xx = 1,
            .yx = @tan(transform.skew_y * std.math.pi),
            .xy = @tan(-transform.skew_x * std.math.pi),
            .yy = 1,
        });
    }
    if (transform.center_x != 0 or transform.center_y != 0) {
        result = mulTransform(result, .{ .dx = -transform.center_x, .dy = -transform.center_y });
    }
    return result;
}

fn mulTransform(a: StaticTransform, b: StaticTransform) StaticTransform {
    return .{
        .xx = a.xx * b.xx + a.xy * b.yx,
        .yx = a.yx * b.xx + a.yy * b.yx,
        .xy = a.xx * b.xy + a.xy * b.yy,
        .yy = a.yx * b.xy + a.yy * b.yy,
        .dx = a.xx * b.dx + a.xy * b.dy + a.dx,
        .dy = a.yx * b.dx + a.yy * b.dy + a.dy,
    };
}

pub const Info = struct {
    version: u32,
    coverage_offset: usize,
    multi_var_store_offset: ?usize,
    condition_list_offset: ?usize,
    axis_indices_list_offset: ?usize,
    var_composite_glyphs_offset: usize,
    glyphs: []u16,
};

const Header = struct {
    version: u32,
    coverage_offset: usize,
    multi_var_store_offset: ?usize,
    condition_list_offset: ?usize,
    axis_indices_list_offset: ?usize,
    var_composite_glyphs_offset: usize,
};

pub fn validate(data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!void {
    const h = try header(data, offset, length);
    const coverage_count = try coverageGlyphCount(data, offset, length, h.coverage_offset, glyph_count);
    if (h.multi_var_store_offset) |store| try validateMultiItemVariationStoreHeader(data, offset, length, store);
    if (h.condition_list_offset) |conditions| try validateConditionListHeader(data, offset, length, conditions);
    if (h.axis_indices_list_offset) |axis_indices| try validateIndex2Header(data, offset, length, axis_indices);
    const glyph_index = try index2Info(data, offset, length, h.var_composite_glyphs_offset);
    if (glyph_index.count != coverage_count) return error.BadSfnt;
    for (0..glyph_index.count) |glyph_index_value| {
        const component_data = try index2Item(data, offset, length, h.var_composite_glyphs_offset, glyph_index_value);
        try validateComponentStream(data, offset, length, h, component_data, glyph_count);
    }
}

pub fn info(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize) Error!Info {
    const h = try header(data, offset, length);
    try validate(data, offset, length, glyph_count);
    const glyphs = try coverageGlyphs(allocator, data, offset, length, h.coverage_offset, glyph_count);
    errdefer allocator.free(glyphs);
    return .{
        .version = h.version,
        .coverage_offset = h.coverage_offset,
        .multi_var_store_offset = h.multi_var_store_offset,
        .condition_list_offset = h.condition_list_offset,
        .axis_indices_list_offset = h.axis_indices_list_offset,
        .var_composite_glyphs_offset = h.var_composite_glyphs_offset,
        .glyphs = glyphs,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    allocator.free(value.glyphs);
}

pub fn glyphCoverageIndex(data: []const u8, offset: usize, length: usize, glyph_count: usize, glyph_id: u16) Error!?usize {
    const h = try header(data, offset, length);
    _ = glyph_count;
    return try coverageIndex(data, offset, length, h.coverage_offset, glyph_id);
}

pub fn glyphComponents(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, glyph_count: usize, coverage_index: usize) Error![]Component {
    var iterator = try componentIterator(data, offset, length, glyph_count, coverage_index);
    var components = std.ArrayList(Component).empty;
    errdefer components.deinit(allocator);
    while (try iterator.next()) |component| try components.append(allocator, component);
    return try components.toOwnedSlice(allocator);
}

pub const ComponentIterator = struct {
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    glyph_count: usize,
    h: Header,
    reader: SliceReader,

    pub fn next(self: *ComponentIterator) Error!?Component {
        if (self.reader.remaining() == 0) return null;
        return try readComponent(
            self.data,
            self.table_offset,
            self.table_length,
            self.h,
            &self.reader,
            self.glyph_count,
        );
    }
};

pub fn componentIterator(data: []const u8, offset: usize, length: usize, glyph_count: usize, coverage_index: usize) Error!ComponentIterator {
    const h = try header(data, offset, length);
    const component_data = try index2Item(data, offset, length, h.var_composite_glyphs_offset, coverage_index);
    return .{
        .data = data,
        .table_offset = offset,
        .table_length = length,
        .glyph_count = glyph_count,
        .h = h,
        .reader = .{ .data = component_data },
    };
}

pub fn conditionMatches(data: []const u8, offset: usize, length: usize, condition_index: u32, normalized_coords: []const f32) Error!bool {
    return try conditionMatchesWithAllocator(std.heap.page_allocator, data, offset, length, condition_index, normalized_coords);
}

pub fn conditionMatchesWithAllocator(allocator: std.mem.Allocator, data: []const u8, offset: usize, length: usize, condition_index: u32, normalized_coords: []const f32) Error!bool {
    const h = try header(data, offset, length);
    const list_offset = h.condition_list_offset orelse return error.BadSfnt;
    const count = try bin.readU32At(data, offset + list_offset);
    if (condition_index >= count) return error.BadSfnt;
    const relative: usize = @intCast(try bin.readU32At(data, offset + list_offset + 4 + @as(usize, condition_index) * 4));
    if (relative == 0 or relative > length - list_offset) return error.BadSfnt;
    return try conditionAtMatches(allocator, data, offset, length, list_offset + relative, normalized_coords, 0);
}

pub fn componentCoordinates(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    component: Component,
    current_coords: []const f32,
    font_coords: []const f32,
    font_axis_count: usize,
) Error![]f32 {
    const coord_count = componentCoordinateCount(current_coords, font_coords, font_axis_count);
    const coords = try allocator.alloc(f32, coord_count);
    errdefer allocator.free(coords);
    try componentCoordinatesInto(
        allocator,
        data,
        offset,
        length,
        component,
        current_coords,
        font_coords,
        font_axis_count,
        coords,
    );
    return coords;
}

pub fn componentCoordinateCount(current_coords: []const f32, font_coords: []const f32, font_axis_count: usize) usize {
    return @max(font_axis_count, @max(current_coords.len, font_coords.len));
}

pub fn componentCoordinatesInto(
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize,
    length: usize,
    component: Component,
    current_coords: []const f32,
    font_coords: []const f32,
    font_axis_count: usize,
    coords: []f32,
) Error!void {
    const required = componentCoordinateCount(current_coords, font_coords, font_axis_count);
    if (coords.len < required) return error.BadSfnt;
    @memset(coords, 0);
    const source = if ((component.flags & ComponentFlags.reset_unspecified_axes) != 0)
        font_coords
    else
        current_coords;
    @memcpy(coords[0..@min(coords.len, source.len)], source[0..@min(coords.len, source.len)]);

    if ((component.flags & ComponentFlags.have_axes) == 0) return;
    if (component.axis_count == 0) return;
    var inline_indices: [32]i32 = undefined;
    const indices = if (component.axis_count <= inline_indices.len)
        inline_indices[0..component.axis_count]
    else
        try allocator.alloc(i32, component.axis_count);
    defer if (component.axis_count > inline_indices.len) allocator.free(indices);
    var inline_values: [32]i32 = undefined;
    const values = if (component.axis_count <= inline_values.len)
        inline_values[0..component.axis_count]
    else
        try allocator.alloc(i32, component.axis_count);
    defer if (component.axis_count > inline_values.len) allocator.free(values);
    try decodePackedDeltas(component.axis_indices, indices);
    try decodePackedDeltas(component.axis_values, values);
    if (component.axis_values_var_index) |var_index| {
        var inline_deltas: [32]f32 = undefined;
        const deltas = if (component.axis_count <= inline_deltas.len)
            inline_deltas[0..component.axis_count]
        else
            try allocator.alloc(f32, component.axis_count);
        defer if (component.axis_count > inline_deltas.len) allocator.free(deltas);
        try variationDeltasInto(
            data,
            offset,
            length,
            var_index,
            current_coords,
            deltas,
        );
        // Tuple deltas are floating-point because multiple active regions can
        // contribute fractional values. Round only after adding a delta to its
        // static TupleValues base; rounding the delta first changes negative
        // half-way cases by one F2Dot14 bit and compounds through nested VARC
        // components.
        for (values, deltas) |*value, delta| {
            value.* = @intFromFloat(@round(@as(f32, @floatFromInt(value.*)) + delta));
        }
    }
    for (indices, values) |axis_index, raw_value| {
        if (axis_index < 0 or axis_index >= coords.len) return error.BadSfnt;
        const clamped = std.math.clamp(raw_value, @as(i32, std.math.minInt(i16)), @as(i32, std.math.maxInt(i16)));
        coords[@intCast(axis_index)] = @as(f32, @floatFromInt(clamped)) / 16384.0;
    }
}

pub fn componentTransform(
    data: []const u8,
    offset: usize,
    length: usize,
    component: Component,
    normalized_coords: []const f32,
) Error!StaticTransform {
    var transform = component.decomposed_transform;
    if (component.transform_var_index) |var_index| {
        const transform_mask = ComponentFlags.have_translate_x |
            ComponentFlags.have_translate_y |
            ComponentFlags.have_rotation |
            ComponentFlags.have_scale_x |
            ComponentFlags.have_scale_y |
            ComponentFlags.have_skew_x |
            ComponentFlags.have_skew_y |
            ComponentFlags.have_center_x |
            ComponentFlags.have_center_y;
        const field_count: usize = @popCount(component.flags & transform_mask);
        var delta_storage: [9]f32 = undefined;
        const deltas = delta_storage[0..field_count];
        try variationDeltasInto(data, offset, length, var_index, normalized_coords, deltas);
        var delta_index: usize = 0;
        if ((component.flags & ComponentFlags.have_translate_x) != 0) {
            transform.translate_x += deltas[delta_index];
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_translate_y) != 0) {
            transform.translate_y += deltas[delta_index];
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_rotation) != 0) {
            transform.rotation += deltas[delta_index] / 4096.0;
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_scale_x) != 0) {
            transform.scale_x += deltas[delta_index] / 1024.0;
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_scale_y) != 0) {
            transform.scale_y += deltas[delta_index] / 1024.0;
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_skew_x) != 0) {
            transform.skew_x += deltas[delta_index] / 4096.0;
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_skew_y) != 0) {
            transform.skew_y += deltas[delta_index] / 4096.0;
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_center_x) != 0) {
            transform.center_x += deltas[delta_index];
            delta_index += 1;
        }
        if ((component.flags & ComponentFlags.have_center_y) != 0) {
            transform.center_y += deltas[delta_index];
        }
        if ((component.flags & ComponentFlags.have_scale_y) == 0) transform.scale_y = transform.scale_x;
    }
    return staticTransform(transform);
}

fn header(data: []const u8, offset: usize, length: usize) Error!Header {
    if (offset > data.len or length > data.len - offset or length < 24) return error.BadSfnt;
    const major = try bin.readU16At(data, offset);
    const minor = try bin.readU16At(data, offset + 2);
    if (major != 1 or minor != 0) return error.BadSfnt;
    const coverage_offset: usize = @intCast(try bin.readU32At(data, offset + 4));
    const multi_var_store_offset = nullableOffset(try bin.readU32At(data, offset + 8));
    const condition_list_offset = nullableOffset(try bin.readU32At(data, offset + 12));
    const axis_indices_list_offset = nullableOffset(try bin.readU32At(data, offset + 16));
    const var_composite_glyphs_offset: usize = @intCast(try bin.readU32At(data, offset + 20));
    try validateRequiredOffset(coverage_offset, length, 24, 4);
    try validateRequiredOffset(var_composite_glyphs_offset, length, 24, 4);
    if (multi_var_store_offset) |value| try validateOptionalOffset(value, length, 24, 2);
    if (condition_list_offset) |value| try validateOptionalOffset(value, length, 24, 4);
    if (axis_indices_list_offset) |value| try validateOptionalOffset(value, length, 24, 4);
    return .{
        .version = (@as(u32, major) << 16) | minor,
        .coverage_offset = coverage_offset,
        .multi_var_store_offset = multi_var_store_offset,
        .condition_list_offset = condition_list_offset,
        .axis_indices_list_offset = axis_indices_list_offset,
        .var_composite_glyphs_offset = var_composite_glyphs_offset,
    };
}

fn nullableOffset(value: u32) ?usize {
    return if (value == 0) null else @intCast(value);
}

fn validateRequiredOffset(value: usize, length: usize, minimum: usize, min_len: usize) Error!void {
    if (value == 0) return error.BadSfnt;
    try validateOptionalOffset(value, length, minimum, min_len);
}

fn validateOptionalOffset(value: usize, length: usize, minimum: usize, min_len: usize) Error!void {
    if (value < minimum or value > length or min_len > length - value) return error.BadSfnt;
}

fn coverageGlyphCount(data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize, glyph_count: usize) Error!usize {
    const start = table_offset + coverage_offset;
    const format = try bin.readU16At(data, start);
    return switch (format) {
        1 => count: {
            if (table_length - coverage_offset < 4) return error.BadSfnt;
            const count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (count > (table_length - coverage_offset - 4) / 2) return error.BadSfnt;
            var previous: ?u16 = null;
            for (0..count) |index| {
                const glyph = try bin.readU16At(data, start + 4 + index * 2);
                if (glyph >= glyph_count) return error.BadSfnt;
                if (previous) |last| if (glyph <= last) return error.BadSfnt;
                previous = glyph;
            }
            break :count count;
        },
        2 => count: {
            if (table_length - coverage_offset < 4) return error.BadSfnt;
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            if (range_count > (table_length - coverage_offset - 4) / 6) return error.BadSfnt;
            var total: usize = 0;
            var previous_end: ?u16 = null;
            for (0..range_count) |index| {
                const record = start + 4 + index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                const start_coverage_index = try bin.readU16At(data, record + 4);
                if (first > last or last >= glyph_count) return error.BadSfnt;
                if (start_coverage_index != total) return error.BadSfnt;
                if (previous_end) |prev| if (first <= prev) return error.BadSfnt;
                previous_end = last;
                total += @as(usize, last - first) + 1;
                if (total > std.math.maxInt(u16)) return error.BadSfnt;
            }
            break :count total;
        },
        else => error.BadSfnt,
    };
}

fn coverageGlyphs(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize, glyph_count: usize) Error![]u16 {
    const count = try coverageGlyphCount(data, table_offset, table_length, coverage_offset, glyph_count);
    const glyphs = try allocator.alloc(u16, count);
    errdefer allocator.free(glyphs);
    const start = table_offset + coverage_offset;
    const format = try bin.readU16At(data, start);
    switch (format) {
        1 => {
            for (glyphs, 0..) |*glyph, index| glyph.* = try bin.readU16At(data, start + 4 + index * 2);
        },
        2 => {
            const range_count: usize = @intCast(try bin.readU16At(data, start + 2));
            var out_index: usize = 0;
            for (0..range_count) |range_index| {
                const record = start + 4 + range_index * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                var glyph = first;
                while (glyph <= last) : (glyph += 1) {
                    glyphs[out_index] = glyph;
                    out_index += 1;
                }
            }
        },
        else => return error.BadSfnt,
    }
    return glyphs;
}

fn coverageIndex(data: []const u8, table_offset: usize, table_length: usize, coverage_offset: usize, glyph_id: u16) Error!?usize {
    _ = table_length;
    const start = table_offset + coverage_offset;
    return switch (try bin.readU16At(data, start)) {
        1 => result: {
            const count = try bin.readU16At(data, start + 2);
            var low: usize = 0;
            var high: usize = count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const candidate = try bin.readU16At(data, start + 4 + mid * 2);
                if (glyph_id < candidate) high = mid else if (glyph_id > candidate) low = mid + 1 else break :result mid;
            }
            break :result null;
        },
        2 => result: {
            const range_count = try bin.readU16At(data, start + 2);
            var low: usize = 0;
            var high: usize = range_count;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const record = start + 4 + mid * 6;
                const first = try bin.readU16At(data, record);
                const last = try bin.readU16At(data, record + 2);
                if (glyph_id < first) {
                    high = mid;
                } else if (glyph_id > last) {
                    low = mid + 1;
                } else {
                    const base = try bin.readU16At(data, record + 4);
                    break :result @as(usize, base) + glyph_id - first;
                }
            }
            break :result null;
        },
        else => error.BadSfnt,
    };
}

const Index2Info = struct {
    count: usize,
    off_size: usize,
    offsets_offset: usize,
    data_offset: usize,
    data_length: usize,
};

fn index2Info(data: []const u8, table_offset: usize, table_length: usize, index_offset: usize) Error!Index2Info {
    if (index_offset > table_length or table_length - index_offset < 4) return error.BadSfnt;
    const start = table_offset + index_offset;
    const count_u32 = try bin.readU32At(data, start);
    const count: usize = @intCast(count_u32);
    // CFF2 INDEX2 encodes an empty index as the four-byte zero count only.
    if (count == 0) return .{ .count = 0, .off_size = 0, .offsets_offset = start + 4, .data_offset = start + 4, .data_length = 0 };
    if (table_length - index_offset < 5) return error.BadSfnt;
    const off_size: usize = data[start + 4];
    if (off_size < 1 or off_size > 4) return error.BadSfnt;
    if (count == std.math.maxInt(usize)) return error.BadSfnt;
    const offset_count = count + 1;
    if (offset_count > (table_length - index_offset - 5) / off_size) return error.BadSfnt;
    const offset_array_bytes = offset_count * off_size;
    const data_length = table_length - index_offset - 5 - offset_array_bytes;
    const offsets_offset = start + 5;
    const data_offset = offsets_offset + offset_array_bytes;
    var previous: usize = 1;
    for (0..offset_count) |index| {
        const value = try readOffset(data, offsets_offset + index * off_size, off_size);
        if (value < previous or value == 0 or value - 1 > data_length) return error.BadSfnt;
        previous = value;
    }
    if (try readOffset(data, offsets_offset, off_size) != 1) return error.BadSfnt;
    return .{ .count = count, .off_size = off_size, .offsets_offset = offsets_offset, .data_offset = data_offset, .data_length = data_length };
}

fn validateIndex2Header(data: []const u8, table_offset: usize, table_length: usize, index_offset: usize) Error!void {
    _ = try index2Info(data, table_offset, table_length, index_offset);
}

fn index2Item(data: []const u8, table_offset: usize, table_length: usize, index_offset: usize, item_index: usize) Error![]const u8 {
    const info_value = try index2Info(data, table_offset, table_length, index_offset);
    if (item_index >= info_value.count) return error.BadSfnt;
    const start = (try readOffset(data, info_value.offsets_offset + item_index * info_value.off_size, info_value.off_size)) - 1;
    const end = (try readOffset(data, info_value.offsets_offset + (item_index + 1) * info_value.off_size, info_value.off_size)) - 1;
    if (end < start or end > info_value.data_length) return error.BadSfnt;
    return data[info_value.data_offset + start .. info_value.data_offset + end];
}

fn readOffset(data: []const u8, offset: usize, size: usize) Error!usize {
    var value: usize = 0;
    for (0..size) |index| value = (value << 8) | data[offset + index];
    return value;
}

const SliceReader = struct {
    data: []const u8,
    offset: usize = 0,

    fn remaining(self: SliceReader) usize {
        return self.data.len - self.offset;
    }

    fn readU8(self: *SliceReader) Error!u8 {
        if (self.offset >= self.data.len) return error.BadSfnt;
        defer self.offset += 1;
        return self.data[self.offset];
    }

    fn readU16(self: *SliceReader) Error!u16 {
        if (self.remaining() < 2) return error.BadSfnt;
        defer self.offset += 2;
        return std.mem.readInt(u16, self.data[self.offset..][0..2], .big);
    }

    fn readI16(self: *SliceReader) Error!i16 {
        return @bitCast(try self.readU16());
    }

    fn readU24(self: *SliceReader) Error!u32 {
        if (self.remaining() < 3) return error.BadSfnt;
        defer self.offset += 3;
        return (@as(u32, self.data[self.offset]) << 16) |
            (@as(u32, self.data[self.offset + 1]) << 8) |
            self.data[self.offset + 2];
    }

    fn readU32Var(self: *SliceReader) Error!u32 {
        const first = try self.readU8();
        return if (first < 0x80)
            first
        else if (first < 0xc0)
            (@as(u32, first - 0x80) << 8) | try self.readU8()
        else if (first < 0xe0)
            (@as(u32, first - 0xc0) << 16) | (@as(u32, try self.readU8()) << 8) | try self.readU8()
        else if (first < 0xf0)
            (@as(u32, first - 0xe0) << 24) | (@as(u32, try self.readU8()) << 16) |
                (@as(u32, try self.readU8()) << 8) | try self.readU8()
        else
            (@as(u32, try self.readU8()) << 24) | (@as(u32, try self.readU8()) << 16) |
                (@as(u32, try self.readU8()) << 8) | try self.readU8();
    }
};

fn validateComponentStream(data: []const u8, table_offset: usize, table_length: usize, h: Header, component_data: []const u8, glyph_count: usize) Error!void {
    var reader = SliceReader{ .data = component_data };
    while (reader.remaining() != 0) {
        _ = try readComponent(data, table_offset, table_length, h, &reader, glyph_count);
    }
}

fn readComponent(data: []const u8, table_offset: usize, table_length: usize, h: Header, reader: *SliceReader, glyph_count: usize) Error!Component {
    const flags = try reader.readU32Var();
    const glyph_id = if ((flags & ComponentFlags.gid_is_24bit) != 0) try reader.readU24() else try reader.readU16();
    if (glyph_id >= glyph_count) return error.BadSfnt;
    const condition_index = if ((flags & ComponentFlags.have_condition) != 0) try reader.readU32Var() else null;
    if (condition_index) |index| {
        const condition_list = h.condition_list_offset orelse return error.BadSfnt;
        try validateConditionIndex(data, table_offset, table_length, condition_list, index);
    }

    var axis_indices: []const u8 = &.{};
    var axis_values: []const u8 = &.{};
    var axis_count: usize = 0;
    if ((flags & ComponentFlags.have_axes) != 0) {
        const axis_indices_index = try reader.readU32Var();
        const axis_indices_list = h.axis_indices_list_offset orelse return error.BadSfnt;
        axis_indices = try index2Item(data, table_offset, table_length, axis_indices_list, axis_indices_index);
        axis_count = try packedDeltaCount(axis_indices);
        // Packed axis values use TupleValues encoding. Full axis remapping is
        // deliberately deferred, but validation must still consume exactly the
        // declared number of values so following transform fields stay aligned.
        const values_start = reader.offset;
        try consumePackedDeltas(reader, axis_count);
        axis_values = reader.data[values_start..reader.offset];
    }
    const axis_values_var_index = if ((flags & ComponentFlags.axis_values_have_variation) != 0) try reader.readU32Var() else null;
    const transform_var_index = if ((flags & ComponentFlags.transform_has_variation) != 0) try reader.readU32Var() else null;

    var translate_x: f32 = 0;
    var translate_y: f32 = 0;
    var rotation: f32 = 0;
    var scale_x: f32 = 1;
    var scale_y: f32 = 1;
    var skew_x: f32 = 0;
    var skew_y: f32 = 0;
    var center_x: f32 = 0;
    var center_y: f32 = 0;
    if ((flags & ComponentFlags.have_translate_x) != 0) translate_x = @floatFromInt(try reader.readI16());
    if ((flags & ComponentFlags.have_translate_y) != 0) translate_y = @floatFromInt(try reader.readI16());
    if ((flags & ComponentFlags.have_rotation) != 0) rotation = @as(f32, @floatFromInt(try reader.readI16())) / 4096.0;
    if ((flags & ComponentFlags.have_scale_x) != 0) scale_x = @as(f32, @floatFromInt(try reader.readI16())) / 1024.0;
    if ((flags & ComponentFlags.have_scale_y) != 0) scale_y = @as(f32, @floatFromInt(try reader.readI16())) / 1024.0 else scale_y = scale_x;
    if ((flags & ComponentFlags.have_skew_x) != 0) skew_x = @as(f32, @floatFromInt(try reader.readI16())) / 4096.0;
    if ((flags & ComponentFlags.have_skew_y) != 0) skew_y = @as(f32, @floatFromInt(try reader.readI16())) / 4096.0;
    if ((flags & ComponentFlags.have_center_x) != 0) center_x = @floatFromInt(try reader.readI16());
    if ((flags & ComponentFlags.have_center_y) != 0) center_y = @floatFromInt(try reader.readI16());

    var reserved = flags & ~ComponentFlags.known_mask;
    while (reserved != 0) : (reserved &= reserved - 1) _ = try reader.readU32Var();
    return .{
        .flags = flags,
        .glyph_id = glyph_id,
        .condition_index = condition_index,
        .axis_indices = axis_indices,
        .axis_values = axis_values,
        .axis_count = axis_count,
        .axis_values_var_index = axis_values_var_index,
        .transform_var_index = transform_var_index,
        .decomposed_transform = .{
            .translate_x = translate_x,
            .translate_y = translate_y,
            .rotation = rotation,
            .scale_x = scale_x,
            .scale_y = scale_y,
            .skew_x = skew_x,
            .skew_y = skew_y,
            .center_x = center_x,
            .center_y = center_y,
        },
    };
}

fn consumePackedDeltas(reader: *SliceReader, value_count: usize) Error!void {
    var consumed: usize = 0;
    while (consumed < value_count) {
        const control = try reader.readU8();
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > value_count - consumed) return error.BadSfnt;
        const zero = (control & 0x80) != 0;
        const words = (control & 0x40) != 0;
        const bytes_per_value: usize = if (zero and !words) 0 else if (zero and words) 4 else if (words) 2 else 1;
        if (bytes_per_value != 0) {
            if (run_count > reader.remaining() / bytes_per_value) return error.BadSfnt;
            reader.offset += run_count * bytes_per_value;
        }
        consumed += run_count;
    }
}

fn packedDeltaCount(data: []const u8) Error!usize {
    var reader = SliceReader{ .data = data };
    var count: usize = 0;
    while (reader.remaining() != 0) {
        const control = try reader.readU8();
        const run_count = @as(usize, control & 0x3f) + 1;
        const zero = (control & 0x80) != 0;
        const words = (control & 0x40) != 0;
        const bytes_per_value: usize = if (zero and !words) 0 else if (zero and words) 4 else if (words) 2 else 1;
        if (bytes_per_value != 0) {
            if (run_count > reader.remaining() / bytes_per_value) return error.BadSfnt;
            reader.offset += run_count * bytes_per_value;
        }
        if (run_count > std.math.maxInt(usize) - count) return error.BadSfnt;
        count += run_count;
    }
    return count;
}

fn decodePackedDeltas(data: []const u8, out: []i32) Error!void {
    var reader = SliceReader{ .data = data };
    var output_index: usize = 0;
    while (output_index < out.len) {
        const control = try reader.readU8();
        const run_count = @as(usize, control & 0x3f) + 1;
        if (run_count > out.len - output_index) return error.BadSfnt;
        const zero = (control & 0x80) != 0;
        const words = (control & 0x40) != 0;
        for (0..run_count) |_| {
            out[output_index] = if (zero and !words)
                0
            else if (zero and words)
                @bitCast(try readU32FromSlice(&reader))
            else if (words)
                try reader.readI16()
            else
                @as(i8, @bitCast(try reader.readU8()));
            output_index += 1;
        }
    }
    if (reader.remaining() != 0) return error.BadSfnt;
}

fn readU32FromSlice(reader: *SliceReader) Error!u32 {
    if (reader.remaining() < 4) return error.BadSfnt;
    const value = std.mem.readInt(u32, reader.data[reader.offset..][0..4], .big);
    reader.offset += 4;
    return value;
}

fn validateConditionListHeader(data: []const u8, table_offset: usize, table_length: usize, list_offset: usize) Error!void {
    if (table_length - list_offset < 4) return error.BadSfnt;
    const start = table_offset + list_offset;
    const count: usize = @intCast(try bin.readU32At(data, start));
    if (count > (table_length - list_offset - 4) / 4) return error.BadSfnt;
    for (0..count) |index| {
        const cond_offset: usize = @intCast(try bin.readU32At(data, start + 4 + index * 4));
        if (cond_offset == 0 or cond_offset > table_length - list_offset or table_length - list_offset - cond_offset < 2) return error.BadSfnt;
        try validateConditionAt(data, table_offset, table_length, list_offset + cond_offset, 0);
    }
}

fn validateConditionIndex(data: []const u8, table_offset: usize, table_length: usize, list_offset: usize, index: u32) Error!void {
    if (table_length - list_offset < 4) return error.BadSfnt;
    const count = try bin.readU32At(data, table_offset + list_offset);
    if (index >= count) return error.BadSfnt;
    const condition_offset: usize = @intCast(try bin.readU32At(data, table_offset + list_offset + 4 + @as(usize, index) * 4));
    if (condition_offset == 0 or condition_offset > table_length - list_offset) return error.BadSfnt;
    try validateConditionAt(data, table_offset, table_length, list_offset + condition_offset, 0);
}

fn validateConditionAt(data: []const u8, table_offset: usize, table_length: usize, condition_offset: usize, depth: u8) Error!void {
    if (depth >= 64 or condition_offset > table_length or table_length - condition_offset < 2) return error.BadSfnt;
    const absolute = table_offset + condition_offset;
    switch (try bin.readU16At(data, absolute)) {
        1 => {
            if (table_length - condition_offset < 8) return error.BadSfnt;
            const minimum = try bin.readI16At(data, absolute + 4);
            const maximum = try bin.readI16At(data, absolute + 6);
            if (minimum > maximum) return error.BadSfnt;
        },
        2 => {
            if (table_length - condition_offset < 8) return error.BadSfnt;
        },
        3, 4 => {
            if (table_length - condition_offset < 3) return error.BadSfnt;
            const count: usize = data[absolute + 2];
            if (count > (table_length - condition_offset - 3) / 3) return error.BadSfnt;
            for (0..count) |child_index| {
                const child_offset = try readU24At(data, absolute + 3 + child_index * 3);
                if (child_offset == 0 or child_offset > table_length - condition_offset) return error.BadSfnt;
                try validateConditionAt(data, table_offset, table_length, condition_offset + child_offset, depth + 1);
            }
        },
        5 => {
            if (table_length - condition_offset < 5) return error.BadSfnt;
            const child_offset = try readU24At(data, absolute + 2);
            if (child_offset == 0 or child_offset > table_length - condition_offset) return error.BadSfnt;
            try validateConditionAt(data, table_offset, table_length, condition_offset + child_offset, depth + 1);
        },
        else => return error.BadSfnt,
    }
}

fn conditionAtMatches(allocator: std.mem.Allocator, data: []const u8, table_offset: usize, table_length: usize, condition_offset: usize, normalized_coords: []const f32, depth: u8) Error!bool {
    if (depth >= 64 or condition_offset > table_length or table_length - condition_offset < 2) return error.BadSfnt;
    const absolute = table_offset + condition_offset;
    return switch (try bin.readU16At(data, absolute)) {
        1 => result: {
            if (table_length - condition_offset < 8) return error.BadSfnt;
            const axis_index = try bin.readU16At(data, absolute + 2);
            const minimum = f2dot14(try bin.readI16At(data, absolute + 4));
            const maximum = f2dot14(try bin.readI16At(data, absolute + 6));
            const coord = if (axis_index < normalized_coords.len) normalized_coords[axis_index] else 0;
            break :result coord >= minimum and coord <= maximum;
        },
        2 => result: {
            if (table_length - condition_offset < 8) return error.BadSfnt;
            const default_value: f32 = @floatFromInt(try bin.readI16At(data, absolute + 2));
            const var_index = try bin.readU32At(data, absolute + 4);
            var deltas: [1]f32 = undefined;
            try variationDeltasInto(data, table_offset, table_length, var_index, normalized_coords, &deltas);
            break :result default_value + deltas[0] > 0;
        },
        3 => result: {
            const count = data[absolute + 2];
            for (0..count) |child_index| {
                const child = try readU24At(data, absolute + 3 + child_index * 3);
                if (!try conditionAtMatches(allocator, data, table_offset, table_length, condition_offset + child, normalized_coords, depth + 1)) break :result false;
            }
            break :result true;
        },
        4 => result: {
            const count = data[absolute + 2];
            for (0..count) |child_index| {
                const child = try readU24At(data, absolute + 3 + child_index * 3);
                if (try conditionAtMatches(allocator, data, table_offset, table_length, condition_offset + child, normalized_coords, depth + 1)) break :result true;
            }
            break :result false;
        },
        5 => !try conditionAtMatches(allocator, data, table_offset, table_length, condition_offset + try readU24At(data, absolute + 2), normalized_coords, depth + 1),
        else => error.BadSfnt,
    };
}

fn f2dot14(value: i16) f32 {
    return @as(f32, @floatFromInt(value)) / 16384.0;
}

fn readU24At(data: []const u8, offset: usize) Error!usize {
    if (offset > data.len or data.len - offset < 3) return error.BadSfnt;
    return (@as(usize, data[offset]) << 16) | (@as(usize, data[offset + 1]) << 8) | data[offset + 2];
}

fn variationDeltasInto(
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    var_index: u32,
    normalized_coords: []const f32,
    output: []f32,
) Error!void {
    @memset(output, 0);
    if (output.len == 0 or var_index == 0xffff_ffff) return;

    const h = try header(data, table_offset, table_length);
    const store_offset = h.multi_var_store_offset orelse return error.BadSfnt;
    const store = table_offset + store_offset;
    if (table_length - store_offset < 8 or try bin.readU16At(data, store) != 1) return error.BadSfnt;
    const region_list_relative: usize = @intCast(try bin.readU32At(data, store + 2));
    const data_count: usize = @intCast(try bin.readU16At(data, store + 6));
    const outer: usize = @intCast(var_index >> 16);
    const inner: usize = @intCast(var_index & 0xffff);
    if (outer >= data_count) return error.BadSfnt;
    const offsets_end = 8 + data_count * 4;
    if (offsets_end > table_length - store_offset) return error.BadSfnt;
    const data_relative: usize = @intCast(try bin.readU32At(data, store + 8 + outer * 4));
    if (data_relative < offsets_end or data_relative > table_length - store_offset or table_length - store_offset - data_relative < 3) return error.BadSfnt;
    const item_data_offset = store_offset + data_relative;
    const item_data = table_offset + item_data_offset;
    if (data[item_data] != 1) return error.BadSfnt;
    const region_index_count: usize = @intCast(try bin.readU16At(data, item_data + 1));
    if (region_index_count > (table_length - item_data_offset - 3) / 2) return error.BadSfnt;
    const delta_sets_offset = item_data_offset + 3 + region_index_count * 2;
    const delta_sets_index = try index2Info(data, table_offset, table_length, delta_sets_offset);
    if (inner >= delta_sets_index.count) return error.BadSfnt;
    const packed_deltas = try index2Item(data, table_offset, table_length, delta_sets_offset, inner);
    if (region_index_count != 0 and output.len > std.math.maxInt(usize) / region_index_count) return error.BadSfnt;
    const expected_values = region_index_count * output.len;
    var delta_fetcher = PackedDeltaFetcher{ .reader = .{ .data = packed_deltas }, .remaining = expected_values };

    const region_list_offset = store_offset + region_list_relative;
    if (region_list_relative < offsets_end or region_list_offset > table_length or table_length - region_list_offset < 2) return error.BadSfnt;
    const region_count: usize = @intCast(try bin.readU16At(data, table_offset + region_list_offset));
    if (region_count > (table_length - region_list_offset - 2) / 4) return error.BadSfnt;
    for (0..region_index_count) |region_delta_index| {
        const region_index = try bin.readU16At(data, item_data + 3 + region_delta_index * 2);
        if (region_index >= region_count) return error.BadSfnt;
        const region_relative: usize = @intCast(try bin.readU32At(data, table_offset + region_list_offset + 2 + @as(usize, region_index) * 4));
        if (region_relative == 0 or region_relative > table_length - region_list_offset) return error.BadSfnt;
        const scalar = try sparseRegionScalar(data, table_offset, table_length, region_list_offset + region_relative, normalized_coords);
        if (scalar == 0)
            try delta_fetcher.skip(output.len)
        else
            try delta_fetcher.addScaled(output, scalar);
    }
    try delta_fetcher.finish();
}

const PackedDeltaFetcher = struct {
    reader: SliceReader,
    remaining: usize,
    run_remaining: usize = 0,
    bytes_per_value: usize = 1,

    fn ensureRun(self: *PackedDeltaFetcher) Error!void {
        if (self.run_remaining != 0) return;
        if (self.remaining == 0) return error.BadSfnt;
        const control = try self.reader.readU8();
        self.run_remaining = @as(usize, control & 0x3f) + 1;
        const zero = (control & 0x80) != 0;
        const words = (control & 0x40) != 0;
        self.bytes_per_value = if (zero and !words) 0 else if (zero and words) 4 else if (words) 2 else 1;
        if (self.run_remaining > self.remaining) return error.BadSfnt;
        if (self.bytes_per_value != 0 and self.run_remaining > self.reader.remaining() / self.bytes_per_value) return error.BadSfnt;
    }

    fn skip(self: *PackedDeltaFetcher, requested: usize) Error!void {
        if (requested > self.remaining) return error.BadSfnt;
        var count = requested;
        while (count != 0) {
            try self.ensureRun();
            const take = @min(count, self.run_remaining);
            self.reader.offset += take * self.bytes_per_value;
            self.run_remaining -= take;
            self.remaining -= take;
            count -= take;
        }
    }

    fn addScaled(self: *PackedDeltaFetcher, output: []f32, scalar: f32) Error!void {
        if (output.len > self.remaining) return error.BadSfnt;
        var output_index: usize = 0;
        while (output_index < output.len) {
            try self.ensureRun();
            const take = @min(output.len - output_index, self.run_remaining);
            switch (self.bytes_per_value) {
                0 => {},
                1 => {
                    const bytes = self.reader.data[self.reader.offset..][0..take];
                    for (bytes, output[output_index..][0..take]) |byte, *value| {
                        value.* += @as(f32, @floatFromInt(@as(i8, @bitCast(byte)))) * scalar;
                    }
                },
                2 => {
                    for (output[output_index..][0..take], 0..) |*value, index| {
                        const start = self.reader.offset + index * 2;
                        const delta = std.mem.readInt(i16, self.reader.data[start..][0..2], .big);
                        value.* += @as(f32, @floatFromInt(delta)) * scalar;
                    }
                },
                4 => {
                    for (output[output_index..][0..take], 0..) |*value, index| {
                        const start = self.reader.offset + index * 4;
                        const delta = std.mem.readInt(i32, self.reader.data[start..][0..4], .big);
                        value.* += @as(f32, @floatFromInt(delta)) * scalar;
                    }
                },
                else => unreachable,
            }
            self.reader.offset += take * self.bytes_per_value;
            self.run_remaining -= take;
            self.remaining -= take;
            output_index += take;
        }
    }

    fn finish(self: PackedDeltaFetcher) Error!void {
        if (self.remaining != 0 or self.run_remaining != 0 or self.reader.remaining() != 0) return error.BadSfnt;
    }
};

fn sparseRegionScalar(data: []const u8, table_offset: usize, table_length: usize, region_offset: usize, normalized_coords: []const f32) Error!f32 {
    if (region_offset > table_length or table_length - region_offset < 2) return error.BadSfnt;
    const absolute = table_offset + region_offset;
    const axis_count: usize = @intCast(try bin.readU16At(data, absolute));
    if (axis_count > (table_length - region_offset - 2) / 8) return error.BadSfnt;
    var scalar: f32 = 1;
    for (0..axis_count) |axis_record| {
        const record = absolute + 2 + axis_record * 8;
        const axis_index = try bin.readU16At(data, record);
        const start = try bin.readI16At(data, record + 2);
        const peak = try bin.readI16At(data, record + 4);
        const end = try bin.readI16At(data, record + 6);
        if (peak == 0) continue;

        // Region coordinates and normalized locations are defined in the same
        // F2Dot14 domain. Quantize the public f32 input before comparisons so
        // coordinates near a support boundary cannot cross it merely because
        // the API carries more precision than the OpenType representation.
        const coord = normalizedF2Dot14Bits(if (axis_index < normalized_coords.len) normalized_coords[axis_index] else 0);
        if (coord == peak) continue;
        if (coord == 0) return 0;
        if (start > peak or peak > end or (start < 0 and end > 0)) continue;
        if (coord < start or coord > end) return 0;
        if (coord < peak) {
            const numerator = @as(i32, coord) - start;
            if (numerator == 0) return 0;
            scalar *= @as(f32, @floatFromInt(numerator)) /
                @as(f32, @floatFromInt(@as(i32, peak) - start));
        } else {
            const numerator = @as(i32, end) - coord;
            if (numerator == 0) return 0;
            scalar *= @as(f32, @floatFromInt(numerator)) /
                @as(f32, @floatFromInt(@as(i32, end) - peak));
        }
    }
    return scalar;
}

fn normalizedF2Dot14Bits(value: f32) i16 {
    const clamped = std.math.clamp(value, -1, 1);
    // font-types' F2Dot14::from_f32 uses half-away-from-zero conversion.
    const bias: f32 = if (std.math.signbit(clamped)) -0.5 else 0.5;
    const scaled = clamped * 16384.0 + bias;
    return @intFromFloat(std.math.clamp(
        scaled,
        @as(f32, @floatFromInt(std.math.minInt(i16))),
        @as(f32, @floatFromInt(std.math.maxInt(i16))),
    ));
}

fn validateMultiItemVariationStoreHeader(data: []const u8, table_offset: usize, table_length: usize, store_offset: usize) Error!void {
    if (table_length - store_offset < 8) return error.BadSfnt;
    const start = table_offset + store_offset;
    if (try bin.readU16At(data, start) != 1) return error.BadSfnt;
    const region_list_offset: usize = @intCast(try bin.readU32At(data, start + 2));
    const data_count: usize = @intCast(try bin.readU16At(data, start + 6));
    const offsets_end = 8 + data_count * 4;
    if (offsets_end > table_length - store_offset) return error.BadSfnt;
    if (region_list_offset < offsets_end or region_list_offset > table_length - store_offset or table_length - store_offset - region_list_offset < 2) return error.BadSfnt;
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .big);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .big);
}

fn writeSingleRegionVarcFixture(bytes: []u8, packed_deltas: []const u8) void {
    std.debug.assert(bytes.len == 76 and packed_deltas.len <= 4);
    @memset(bytes, 0);
    writeU16(bytes, 0, 1);
    writeU32(bytes, 4, 68); // Empty coverage required by the VARC header.
    writeU32(bytes, 8, 24); // MultiItemVariationStore.
    writeU32(bytes, 20, 72); // Empty VarCompositeGlyphs INDEX2.

    // One variation-data subtable referencing one sparse region whose support
    // ramps from zero to one over normalized axis 0.
    writeU16(bytes, 24, 1);
    writeU32(bytes, 26, 12);
    writeU16(bytes, 30, 1);
    writeU32(bytes, 32, 28);
    writeU16(bytes, 36, 1);
    writeU32(bytes, 38, 6);
    writeU16(bytes, 42, 1);
    writeU16(bytes, 44, 0);
    writeU16(bytes, 46, 0);
    writeU16(bytes, 48, 0x4000);
    writeU16(bytes, 50, 0x4000);

    bytes[52] = 1;
    writeU16(bytes, 53, 1);
    writeU16(bytes, 55, 0);
    writeU32(bytes, 57, 1);
    bytes[61] = 1;
    bytes[62] = 1;
    bytes[63] = @intCast(packed_deltas.len + 1);
    @memcpy(bytes[64..][0..packed_deltas.len], packed_deltas);

    writeU16(bytes, 68, 1);
    writeU16(bytes, 70, 0);
    writeU32(bytes, 72, 0);
}

test "VARC exposes top-level offsets and coverage glyphs" {
    var bytes: [46]u8 = .{0} ** 46;
    writeU16(&bytes, 0, 1);
    writeU16(&bytes, 2, 0);
    writeU32(&bytes, 4, 24);
    writeU32(&bytes, 20, 32);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 1);
    writeU16(&bytes, 30, 3);
    writeU32(&bytes, 32, 2); // INDEX2 count matches coverage.
    bytes[36] = 1; // offSize.
    bytes[37] = 1;
    bytes[38] = 4;
    bytes[39] = 7;
    bytes[40] = 0;
    writeU16(&bytes, 41, 1);
    bytes[43] = 0;
    writeU16(&bytes, 44, 3);

    try validate(&bytes, 0, bytes.len, 4);
    const parsed = try info(std.testing.allocator, &bytes, 0, bytes.len, 4);
    defer free(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u32, 0x00010000), parsed.version);
    try std.testing.expectEqual(@as(usize, 24), parsed.coverage_offset);
    try std.testing.expectEqual(@as(?usize, null), parsed.multi_var_store_offset);
    try std.testing.expectEqual(@as(usize, 32), parsed.var_composite_glyphs_offset);
    try std.testing.expectEqualSlices(u16, &.{ 1, 3 }, parsed.glyphs);
}

test "VARC component iterator streams the same records as the collecting API" {
    var bytes: [46]u8 = .{0} ** 46;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 4, 24);
    writeU32(&bytes, 20, 32);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 1);
    writeU16(&bytes, 30, 3);
    writeU32(&bytes, 32, 2);
    bytes[36] = 1;
    bytes[37] = 1;
    bytes[38] = 4;
    bytes[39] = 7;
    bytes[40] = 0;
    writeU16(&bytes, 41, 1);
    bytes[43] = 0;
    writeU16(&bytes, 44, 3);

    const collected = try glyphComponents(std.testing.allocator, &bytes, 0, bytes.len, 4, 0);
    defer std.testing.allocator.free(collected);
    var iterator = try componentIterator(&bytes, 0, bytes.len, 4, 0);
    const first = (try iterator.next()).?;
    try std.testing.expectEqual(@as(u32, 1), first.glyph_id);
    try std.testing.expectEqual(collected[0].glyph_id, first.glyph_id);
    try std.testing.expect((try iterator.next()) == null);
}

test "VARC coverage glyphs must stay sorted and in maxp bounds" {
    var bytes: [36]u8 = .{0} ** 36;
    writeU16(&bytes, 0, 1);
    writeU32(&bytes, 4, 24);
    writeU32(&bytes, 20, 32);
    writeU16(&bytes, 24, 1);
    writeU16(&bytes, 26, 2);
    writeU16(&bytes, 28, 3);
    writeU16(&bytes, 30, 1);
    writeU32(&bytes, 32, 0); // Empty INDEX2.

    try std.testing.expectError(error.BadSfnt, validate(&bytes, 0, bytes.len, 4));
}

test "VARC uint32var and static component transform decode" {
    // flags=HAVE_TRANSLATE_X|HAVE_SCALE_X|HAVE_SCALE_Y (0x310), encoded
    // as a two-byte UInt32Var, followed by a 16-bit glyph id.
    var bytes = [_]u8{
        0x83, 0x10,
        0x00, 0x03,
        0x00, 0x0a, // translateX = 10
        0x08, 0x00, // scaleX = 2.0 in F6Dot10
        0x02, 0x00, // scaleY = 0.5 in F6Dot10
    };
    var reader = SliceReader{ .data = &bytes };
    const component = try readComponent(&bytes, 0, bytes.len, .{
        .version = 0x00010000,
        .coverage_offset = 0,
        .multi_var_store_offset = null,
        .condition_list_offset = null,
        .axis_indices_list_offset = null,
        .var_composite_glyphs_offset = 0,
    }, &reader, 4);

    try std.testing.expectEqual(@as(u32, 3), component.glyph_id);
    try std.testing.expectEqual(bytes.len, reader.offset);
    const transform = staticTransform(component.decomposed_transform);
    try std.testing.expectApproxEqAbs(@as(f32, 2), transform.xx, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), transform.yy, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), transform.dx, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), transform.dy, 0.0001);
}

test "VARC decomposed transform applies center rotation and skew order" {
    const transform = staticTransform(.{
        .translate_x = 10,
        .translate_y = 20,
        .rotation = 0.5, // 90 degrees.
        .scale_x = 2,
        .scale_y = 3,
        .center_x = 4,
        .center_y = 5,
    });
    // T(translate+center) * R(90deg) * S(2,3) * T(-center).
    try std.testing.expectApproxEqAbs(@as(f32, 0), transform.xx, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), transform.yx, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -3), transform.xy, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), transform.yy, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 29), transform.dx, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 17), transform.dy, 0.0001);

    const skew = staticTransform(.{ .skew_x = 0.25, .skew_y = 0.25 });
    try std.testing.expectApproxEqAbs(@as(f32, -1), skew.xy, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), skew.yx, 0.0001);
}

test "VARC INDEX2 uses 32-bit count and one-based offsets" {
    var bytes: [12]u8 = .{0} ** 12;
    writeU32(&bytes, 0, 2);
    bytes[4] = 1;
    bytes[5] = 1;
    bytes[6] = 3;
    bytes[7] = 5;
    bytes[8] = 0xaa;
    bytes[9] = 0xbb;
    bytes[10] = 0xcc;
    bytes[11] = 0xdd;

    const first = try index2Item(&bytes, 0, bytes.len, 0, 0);
    const second = try index2Item(&bytes, 0, bytes.len, 0, 1);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb }, first);
    try std.testing.expectEqualSlices(u8, &.{ 0xcc, 0xdd }, second);
}

test "VARC multi-item variation store evaluates region-major tuples" {
    var bytes: [76]u8 = .{0} ** 76;
    writeSingleRegionVarcFixture(&bytes, &.{ 1, 10, @bitCast(@as(i8, -20)) });

    var deltas: [2]f32 = undefined;
    try variationDeltasInto(&bytes, 0, bytes.len, 0, &.{0.5}, &deltas);
    try std.testing.expectApproxEqAbs(@as(f32, 5), deltas[0], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -10), deltas[1], 0.0001);
}

test "VARC packed delta fetcher streams mixed runs" {
    const packed_bytes = [_]u8{
        0x80, // One zero.
        0x40, 0x01, 0x00, // One i16: 256.
        0xc0, 0xff, 0xff, 0xff, 0xfe, // One i32: -2.
    };
    var fetcher = PackedDeltaFetcher{
        .reader = .{ .data = &packed_bytes },
        .remaining = 3,
    };
    var output = [_]f32{ 0, 0, 0 };
    try fetcher.addScaled(&output, 0.5);
    try fetcher.finish();
    try std.testing.expectEqualSlices(f32, &.{ 0, 128, -1 }, &output);

    const bytes = [_]u8{ 0x02, 1, 2, 3 };
    var split = PackedDeltaFetcher{
        .reader = .{ .data = &bytes },
        .remaining = 3,
    };
    try split.skip(2);
    var tail = [_]f32{0};
    try split.addScaled(&tail, 1);
    try split.finish();
    try std.testing.expectEqual(@as(f32, 3), tail[0]);
}

test "VARC packed delta fetcher rejects count and byte mismatches" {
    const extra = [_]u8{ 0, 1, 0, 2 };
    var extra_fetcher = PackedDeltaFetcher{
        .reader = .{ .data = &extra },
        .remaining = 1,
    };
    var output = [_]f32{0};
    try extra_fetcher.addScaled(&output, 1);
    try std.testing.expectError(error.BadSfnt, extra_fetcher.finish());

    const truncated = [_]u8{ 0x40, 0 };
    var truncated_fetcher = PackedDeltaFetcher{
        .reader = .{ .data = &truncated },
        .remaining = 1,
    };
    try std.testing.expectError(error.BadSfnt, truncated_fetcher.addScaled(&output, 1));
}

test "VARC axis variation rounds after adding the static axis value" {
    var bytes: [76]u8 = .{0} ** 76;
    writeSingleRegionVarcFixture(&bytes, &.{ 0, @bitCast(@as(i8, -1)) });

    const component = Component{
        .flags = ComponentFlags.have_axes | ComponentFlags.axis_values_have_variation,
        .glyph_id = 0,
        .condition_index = null,
        .axis_indices = &.{ 0, 0 },
        .axis_values = &.{ 0, 10 },
        .axis_count = 1,
        .axis_values_var_index = 0,
        .decomposed_transform = .{},
    };
    const coords = try componentCoordinates(
        std.testing.allocator,
        &bytes,
        0,
        bytes.len,
        component,
        &.{0.5},
        &.{0.5},
        1,
    );
    defer std.testing.allocator.free(coords);

    // 10 + (-1 * 0.5) = 9.5, which rounds to 10. Rounding the variation
    // delta separately would incorrectly produce 9.
    try std.testing.expectEqual(@as(f32, 10.0 / 16384.0), coords[0]);

    var inline_coords: [1]f32 = undefined;
    try componentCoordinatesInto(
        std.testing.allocator,
        &bytes,
        0,
        bytes.len,
        component,
        &.{0.5},
        &.{0.5},
        1,
        &inline_coords,
    );
    try std.testing.expectEqualSlices(f32, coords, &inline_coords);

    var too_short: [0]f32 = .{};
    try std.testing.expectError(
        error.BadSfnt,
        componentCoordinatesInto(
            std.testing.allocator,
            &bytes,
            0,
            bytes.len,
            component,
            &.{0.5},
            &.{0.5},
            1,
            &too_short,
        ),
    );
}

test "VARC component validation rejects truncation and coverage count mismatch" {
    var truncated: [39]u8 = .{0} ** 39;
    writeU16(&truncated, 0, 1);
    writeU32(&truncated, 4, 24);
    writeU32(&truncated, 20, 30);
    writeU16(&truncated, 24, 1);
    writeU16(&truncated, 26, 1);
    writeU16(&truncated, 28, 0);
    writeU32(&truncated, 30, 1);
    truncated[34] = 1;
    truncated[35] = 1;
    truncated[36] = 3;
    truncated[37] = ComponentFlags.have_translate_x; // Missing GID/payload bytes.
    truncated[38] = 0;
    try std.testing.expectError(error.BadSfnt, validate(&truncated, 0, truncated.len, 2));

    var count_mismatch: [38]u8 = .{0} ** 38;
    writeU16(&count_mismatch, 0, 1);
    writeU32(&count_mismatch, 4, 24);
    writeU32(&count_mismatch, 20, 30);
    writeU16(&count_mismatch, 24, 1);
    writeU16(&count_mismatch, 26, 1);
    writeU16(&count_mismatch, 28, 0);
    writeU32(&count_mismatch, 30, 0); // Coverage has one glyph, INDEX2 has none.
    try std.testing.expectError(error.BadSfnt, validate(&count_mismatch, 0, count_mismatch.len, 2));
}
