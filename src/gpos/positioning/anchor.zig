//! GPOS Anchor parsing and VariationIndex resolution.

const std = @import("std");
const device = @import("device.zig");
const table = @import("../table/root.zig");
const metric_variation = @import("../../opentype/metric_variation.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub const Value = struct {
    x: i16,
    y: i16,
};

pub const VariationStore = struct {
    data: []const u8,
    table_offset: usize,
    table_length: usize,
    store_offset: usize,
};

pub const Options = struct {
    normalized_coords: []const f32 = &.{},
    variation_store: ?VariationStore = null,
};

pub fn read(view: View, anchor_offset: usize, options: Options) Error!Value {
    const format = try view.readU16(anchor_offset);
    const required_length: usize = switch (format) {
        1 => 6,
        2 => 8,
        3 => 10,
        else => return error.UnsupportedGpos,
    };
    if (anchor_offset > view.length or
        required_length > view.length - anchor_offset)
    {
        return error.EndOfStream;
    }

    var x: i32 = try view.readI16(anchor_offset + 2);
    var y: i32 = try view.readI16(anchor_offset + 4);
    if (format == 3) {
        x += try variationDelta(
            view,
            anchor_offset,
            try view.readU16(anchor_offset + 6),
            options,
        );
        y += try variationDelta(
            view,
            anchor_offset,
            try view.readU16(anchor_offset + 8),
            options,
        );
    }
    return .{
        .x = std.math.cast(i16, x) orelse return error.BadGpos,
        .y = std.math.cast(i16, y) orelse return error.BadGpos,
    };
}

pub fn validate(view: View, anchor_offset: usize) Error!void {
    const format = try readU16ForValidation(view, anchor_offset);
    switch (format) {
        1 => try view.ensure(anchor_offset, 6),
        2 => try view.ensure(anchor_offset, 8),
        3 => {
            try view.ensure(anchor_offset, 10);
            const x_relative =
                try readU16ForValidation(view, anchor_offset + 6);
            const y_relative =
                try readU16ForValidation(view, anchor_offset + 8);
            if (x_relative != 0) {
                try device.validate(
                    view,
                    try table.offset.required16(
                        view,
                        anchor_offset,
                        x_relative,
                    ),
                );
            }
            if (y_relative != 0) {
                try device.validate(
                    view,
                    try table.offset.required16(
                        view,
                        anchor_offset,
                        y_relative,
                    ),
                );
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn variationDelta(
    view: View,
    anchor_offset: usize,
    relative: u16,
    options: Options,
) Error!i32 {
    if (relative == 0 or options.normalized_coords.len == 0) return 0;
    const variation_index = try table.offset.required16(
        view,
        anchor_offset,
        relative,
    );
    const delta_format = try view.readU16(variation_index + 4);
    // Ordinary Device tables are PPEM-dependent and remain zero in this
    // font-unit API. DeltaFormat 0x8000 is the variation-common record.
    if (delta_format != 0x8000) return 0;
    const store = options.variation_store orelse return 0;
    return metric_variation.itemVariationDelta(
        store.data,
        store.table_offset,
        store.table_length,
        store.store_offset,
        .{
            .outer = try view.readU16(variation_index),
            .inner = try view.readU16(variation_index + 2),
        },
        options.normalized_coords,
    ) catch |err| switch (err) {
        error.BadSfnt, error.EndOfStream => error.BadGpos,
        error.OutOfMemory => unreachable,
    };
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
