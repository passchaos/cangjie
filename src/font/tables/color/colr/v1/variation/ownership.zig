//! Ownership separation between COLR variation tables and Paint payloads.

const bin = @import("../../../../../../binary.zig");
const bases = @import("../bases.zig");
const clip = @import("../clip.zig");
const directories = @import("../directories.zig");
const paint = @import("../paint/root.zig");
const types = @import("../types.zig");

pub fn validate(
    data: []const u8,
    table: types.Table,
    variation_range: types.Range,
) types.Error!void {
    if (try bases.read(data, table)) |base_list| {
        if (directories.overlaps(
            variation_range,
            bases.range(table, base_list),
        )) {
            return error.BadSfnt;
        }
    }

    const layer_list_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 18));
    if (layer_list_offset != 0) {
        const structural_range = try directories.layerListRange(
            data,
            table,
            layer_list_offset,
        );
        if (directories.overlaps(variation_range, structural_range)) {
            return error.BadSfnt;
        }
    }

    const clip_list_offset: usize =
        @intCast(try bin.readU32At(data, table.offset + 22));
    if (clip_list_offset != 0) {
        const structural_range = try directories.clipListRange(
            data,
            table,
            clip_list_offset,
        );
        if (directories.overlaps(variation_range, structural_range)) {
            return error.BadSfnt;
        }
    }

    try validateClipBoxes(data, table, variation_range);
    try validatePaintPayloads(data, table, variation_range);
}

fn validateClipBoxes(
    data: []const u8,
    table: types.Table,
    variation_range: types.Range,
) types.Error!void {
    const list = (try clip.directory(data, table)) orelse return;
    for (0..list.count) |index| {
        const clip_box_range =
            (try clip.boxAtIndex(data, table, list, index)).range;
        if (directories.overlaps(variation_range, clip_box_range)) {
            return error.BadSfnt;
        }
    }
}

fn validatePaintPayloads(
    data: []const u8,
    table: types.Table,
    variation_range: types.Range,
) types.Error!void {
    const forbidden = paint.Range{
        .start = table.offset + variation_range.start,
        .end = table.offset + variation_range.end,
    };
    var visitor = Visitor{};
    try paint.walkAllWithForbiddenRange(
        data,
        table,
        forbidden,
        &visitor,
    );
}

const Visitor = struct {
    pub fn visit(
        _: *const Visitor,
        _: []const u8,
        _: types.Table,
        _: usize,
        _: paint.FormatInfo,
    ) types.Error!void {
        // The shared walker claims every structural Paint payload. The
        // forbidden range seeded above is therefore the complete ownership
        // policy for this pass; no format-specific semantics are needed.
    }
};
