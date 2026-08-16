//! SinglePos parsing and structural validation.

const accelerator = @import("../../accelerator/root.zig");
const table = @import("../../table/root.zig");
const value_record = @import("../value_record.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;
pub const Parsed = accelerator.model.SinglePositionSubtable;

pub fn parse(view: View, subtable_offset: usize) Error!Parsed {
    const pos_format = try view.readU16(subtable_offset);
    const coverage_offset = try requiredOffset(
        view,
        subtable_offset,
        try view.readU16(subtable_offset + 2),
    );
    const value_format = try view.readU16(subtable_offset + 4);
    const value_size = try value_record.size(value_format);
    return switch (pos_format) {
        1 => .{
            .subtable_offset = subtable_offset,
            .pos_format = pos_format,
            .coverage_offset = coverage_offset,
            .value_format = value_format,
            .value_size = value_size,
            .values_pos = subtable_offset + 6,
            .value = try value_record.read(
                view,
                subtable_offset + 6,
                value_format,
                subtable_offset,
            ),
        },
        2 => .{
            .subtable_offset = subtable_offset,
            .pos_format = pos_format,
            .coverage_offset = coverage_offset,
            .value_format = value_format,
            .value_count = try view.readU16(subtable_offset + 6),
            .value_size = value_size,
            .values_pos = subtable_offset + 8,
        },
        else => error.UnsupportedGpos,
    };
}

pub fn validate(view: View, subtable_offset: usize) Error!void {
    const pos_format = try readU16ForValidation(view, subtable_offset);
    const coverage_offset = try requiredOffset(
        view,
        subtable_offset,
        try readU16ForValidation(view, subtable_offset + 2),
    );
    try table.coverage.validate(view, coverage_offset, .indexed);
    const value_format =
        try readU16ForValidation(view, subtable_offset + 4);
    const value_size = try value_record.size(value_format);
    switch (pos_format) {
        1 => try value_record.validate(
            view,
            subtable_offset + 6,
            value_format,
            subtable_offset,
        ),
        2 => {
            const value_count =
                try readU16ForValidation(view, subtable_offset + 6);
            // Coverage indexes address the ValueRecord array directly.
            try table.coverage.validateIndices(
                view,
                coverage_offset,
                value_count,
            );
            try view.ensure(
                subtable_offset + 8,
                @as(usize, value_count) * value_size,
            );
            if (value_record.hasDeviceOffsets(value_format)) {
                for (0..value_count) |value_index| {
                    try value_record.validate(
                        view,
                        subtable_offset + 8 + value_index * value_size,
                        value_format,
                        subtable_offset,
                    );
                }
            }
        },
        else => return error.UnsupportedGpos,
    }
}

fn requiredOffset(view: View, base: usize, relative: u16) Error!usize {
    return table.offset.required16(view, base, relative);
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
