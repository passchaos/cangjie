//! Apple dfont/resource-fork reconstruction.

const std = @import("std");
const binary = @import("binary.zig");
const types = @import("types.zig");

const DfontResource = struct {
    payload_offset: usize,
    payload_len: usize,
};

/// Reconstruct the `sfnt` resources in an Apple data-fork resource container.
///
/// A one-face dfont returns that standalone SFNT unchanged. Multiple resources
/// become a TTC in resource-map order, which is the face order used by
/// QuickDraw, FreeType, and HarfBuzz. Resource SFNT table offsets are local to
/// each resource; TTC records require absolute offsets from the collection
/// start, so reconstruction rebases every table record after copying.
pub fn decodeAlloc(
    allocator: std.mem.Allocator,
    dfont: []const u8,
    max_decoded_size: usize,
) ![]u8 {
    const resources = try dfontSfntResources(allocator, dfont);
    defer allocator.free(resources);

    if (resources.len == 1) {
        const resource = resources[0];
        if (resource.payload_len > max_decoded_size) return error.OutputTooLarge;
        return try allocator.dupe(
            u8,
            dfont[resource.payload_offset..][0..resource.payload_len],
        );
    }

    const header_unaligned = std.math.add(
        usize,
        12,
        std.math.mul(usize, resources.len, 4) catch
            return error.InvalidContainer,
    ) catch return error.InvalidContainer;
    const header_len = try binary.align4(header_unaligned);
    var total_len = header_len;
    for (resources) |resource| {
        total_len = std.math.add(
            usize,
            total_len,
            try binary.align4(resource.payload_len),
        ) catch return error.InvalidContainer;
        if (total_len > max_decoded_size) return error.OutputTooLarge;
    }

    const out = try allocator.alloc(u8, total_len);
    errdefer allocator.free(out);
    @memset(out, 0);
    @memcpy(out[0..4], "ttcf");
    binary.writeU32(out, 4, 0x00010000);
    if (resources.len > std.math.maxInt(u32)) return error.InvalidContainer;
    binary.writeU32(out, 8, @intCast(resources.len));

    var face_offset = header_len;
    for (resources, 0..) |resource, face_index| {
        if (face_offset > std.math.maxInt(u32)) return error.InvalidContainer;
        binary.writeU32(out, 12 + face_index * 4, @intCast(face_offset));
        const face = dfont[resource.payload_offset..][0..resource.payload_len];
        @memcpy(out[face_offset..][0..face.len], face);
        try rebaseDfontSfntTableOffsets(
            out[face_offset..][0..face.len],
            face_offset,
        );
        face_offset += try binary.align4(face.len);
    }
    return out;
}

fn dfontSfntResources(
    allocator: std.mem.Allocator,
    dfont: []const u8,
) ![]DfontResource {
    if (dfont.len < 16) {
        return error.InvalidContainer;
    }
    const data_start: usize = binary.readU32(dfont, 0);
    const map_start: usize = binary.readU32(dfont, 4);
    const data_len: usize = binary.readU32(dfont, 8);
    const map_len: usize = binary.readU32(dfont, 12);
    const data_end = try binary.checkedEnd(data_start, data_len, dfont.len);
    const map_end = try binary.checkedEnd(map_start, map_len, dfont.len);
    if (data_len == 0 or map_len < 28 or
        binary.rangesOverlap(data_start, data_end, map_start, map_end))
    {
        return error.InvalidContainer;
    }

    // Classic resource forks repeat their header in the map. A dfont uses 16
    // zero bytes instead; accepting either also permits a flattened resource
    // fork with the same safe grammar.
    const map_header = dfont[map_start..][0..16];
    if (!binary.allZero(map_header) and !std.mem.eql(u8, map_header, dfont[0..16])) {
        return error.InvalidContainer;
    }

    const type_list_rel: usize = binary.readU16(dfont, map_start + 24);
    const name_list_rel: usize = binary.readU16(dfont, map_start + 26);
    if (type_list_rel < 28 or type_list_rel >= map_len or
        name_list_rel < 28 or name_list_rel > map_len)
    {
        return error.InvalidContainer;
    }
    const type_list = map_start + type_list_rel;
    const name_list = map_start + name_list_rel;
    if (type_list > map_end - 2 or type_list >= name_list) {
        return error.InvalidContainer;
    }

    const type_count = @as(usize, binary.readU16(dfont, type_list)) + 1;
    if (type_count > 4079) return error.InvalidContainer;
    const type_bytes = std.math.mul(usize, type_count, 8) catch
        return error.InvalidContainer;
    const type_records_end = std.math.add(
        usize,
        type_list + 2,
        type_bytes,
    ) catch return error.InvalidContainer;
    if (type_records_end > name_list) return error.InvalidContainer;

    var sfnt_resources = std.ArrayList(DfontResource).empty;
    defer sfnt_resources.deinit(allocator);
    var found_sfnt_type = false;
    for (0..type_count) |type_index| {
        const type_record = type_list + 2 + type_index * 8;
        const tag = dfont[type_record..][0..4];
        const resource_count = @as(usize, binary.readU16(dfont, type_record + 4)) + 1;
        if (resource_count > 2727) return error.InvalidContainer;
        const references_rel: usize = binary.readU16(dfont, type_record + 6);
        const references = std.math.add(
            usize,
            type_list,
            references_rel,
        ) catch return error.InvalidContainer;
        const reference_bytes = std.math.mul(
            usize,
            resource_count,
            12,
        ) catch return error.InvalidContainer;
        const references_end = std.math.add(
            usize,
            references,
            reference_bytes,
        ) catch return error.InvalidContainer;
        if (references < type_records_end or references_end > name_list) {
            return error.InvalidContainer;
        }

        const is_sfnt = std.mem.eql(u8, tag, "sfnt");
        if (is_sfnt and found_sfnt_type) return error.InvalidContainer;
        found_sfnt_type = found_sfnt_type or is_sfnt;
        for (0..resource_count) |resource_index| {
            const reference = references + resource_index * 12;
            if (binary.readU32(dfont, reference + 8) != 0) {
                return error.InvalidContainer;
            }
            try validateDfontResourceName(
                dfont,
                map_end,
                name_list,
                binary.readU16(dfont, reference + 2),
            );
            const attributes_and_offset = binary.readU32(dfont, reference + 4);
            const data_relative = @as(usize, attributes_and_offset & 0x00ffffff);
            const resource_start = std.math.add(
                usize,
                data_start,
                data_relative,
            ) catch return error.InvalidContainer;
            if (resource_start < data_start or resource_start > data_end - 4) {
                return error.InvalidContainer;
            }
            const payload_len: usize = binary.readU32(dfont, resource_start);
            const payload_offset = resource_start + 4;
            if (payload_len > data_end - payload_offset) {
                return error.InvalidContainer;
            }
            if (is_sfnt) {
                for (sfnt_resources.items) |existing| {
                    if (binary.rangesOverlap(
                        payload_offset,
                        payload_offset + payload_len,
                        existing.payload_offset,
                        existing.payload_offset + existing.payload_len,
                    )) {
                        return error.InvalidContainer;
                    }
                }
                try validateDfontSfnt(
                    dfont[payload_offset..][0..payload_len],
                );
                try sfnt_resources.append(allocator, .{
                    .payload_offset = payload_offset,
                    .payload_len = payload_len,
                });
            }
        }
    }
    if (sfnt_resources.items.len == 0) return error.InvalidContainer;
    return try sfnt_resources.toOwnedSlice(allocator);
}

fn validateDfontResourceName(
    dfont: []const u8,
    map_end: usize,
    name_list: usize,
    name_offset_raw: u16,
) !void {
    if (name_offset_raw == 0xffff) return;
    const name_offset = std.math.add(
        usize,
        name_list,
        name_offset_raw,
    ) catch return error.InvalidContainer;
    if (name_offset >= map_end) return error.InvalidContainer;
    const name_len: usize = dfont[name_offset];
    if (name_len > map_end - name_offset - 1) return error.InvalidContainer;
}

fn validateDfontSfnt(sfnt: []const u8) !void {
    if (sfnt.len < 12 or !types.isSupportedSfntFlavor(binary.readU32(sfnt, 0))) {
        return error.InvalidContainer;
    }
    const table_count = binary.readU16(sfnt, 4);
    if (table_count == 0) return error.InvalidContainer;
    const directory_len = std.math.mul(
        usize,
        table_count,
        16,
    ) catch return error.InvalidContainer;
    if (directory_len > sfnt.len - 12) return error.InvalidContainer;
    for (0..table_count) |table_index| {
        const record = 12 + table_index * 16;
        const offset: usize = binary.readU32(sfnt, record + 8);
        const len: usize = binary.readU32(sfnt, record + 12);
        if ((offset & 3) != 0 or offset > sfnt.len or len > sfnt.len - offset) {
            return error.InvalidContainer;
        }
    }
}

fn rebaseDfontSfntTableOffsets(face: []u8, face_offset: usize) !void {
    try validateDfontSfnt(face);
    const table_count = binary.readU16(face, 4);
    for (0..table_count) |table_index| {
        const record = 12 + table_index * 16;
        const old_offset: usize = binary.readU32(face, record + 8);
        const new_offset = std.math.add(
            usize,
            face_offset,
            old_offset,
        ) catch return error.InvalidContainer;
        if (new_offset > std.math.maxInt(u32)) return error.InvalidContainer;
        binary.writeU32(face, record + 8, @intCast(new_offset));
    }
}
