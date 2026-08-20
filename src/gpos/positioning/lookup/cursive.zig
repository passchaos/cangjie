//! CursivePos parsing and structural validation.

const accelerator = @import("../../accelerator/root.zig");
const anchor = @import("../anchor.zig");
const table = @import("../../table/root.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;
pub const Parsed = accelerator.model.CursivePositionSubtable;

pub fn parse(view: View, subtable_offset: usize) Error!Parsed {
    const pos_format = try view.readU16(subtable_offset);
    if (pos_format != 1) return error.UnsupportedGpos;
    return .{
        .subtable_offset = subtable_offset,
        .coverage_offset = try table.offset.required16(
            view,
            subtable_offset,
            try view.readU16(subtable_offset + 2),
        ),
        .entry_exit_count = try view.readU16(subtable_offset + 4),
    };
}

pub fn validate(view: View, subtable_offset: usize) Error!void {
    const parsed = try parseForValidation(view, subtable_offset);
    try table.coverage.validate(view, parsed.coverage_offset, .indexed);
    try table.coverage.validateIndices(
        view,
        parsed.coverage_offset,
        parsed.entry_exit_count,
    );
    try view.ensure(
        subtable_offset + 6,
        @as(usize, parsed.entry_exit_count) * 4,
    );
    for (0..parsed.entry_exit_count) |record_index| {
        const record = subtable_offset + 6 + record_index * 4;
        const entry_relative = try readU16ForValidation(view, record);
        const exit_relative = try readU16ForValidation(view, record + 2);
        if (entry_relative != 0) {
            try anchor.validate(
                view,
                try table.offset.required16(
                    view,
                    subtable_offset,
                    entry_relative,
                ),
            );
        }
        if (exit_relative != 0) {
            try anchor.validate(
                view,
                try table.offset.required16(
                    view,
                    subtable_offset,
                    exit_relative,
                ),
            );
        }
    }
}

fn parseForValidation(view: View, subtable_offset: usize) Error!Parsed {
    return parse(view, subtable_offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}

fn readU16ForValidation(view: View, relative: usize) Error!u16 {
    return view.readU16(relative) catch |err| switch (err) {
        error.EndOfStream => error.BadGpos,
        else => err,
    };
}
