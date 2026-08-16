//! Shared primitives for contextual GSUB grammar validation.

const records = @import("../../execution/contextual/records/root.zig");
const table = @import("../../table/root.zig");

pub const Error = table.coverage.Error ||
    error{ InvalidShapingInput, ShapingLimitExceeded };
pub const View = table.View;

pub fn read(view: View, offset: usize) Error!u16 {
    return view.readU16(offset) catch |err| switch (err) {
        error.EndOfStream => error.BadGsub,
        else => err,
    };
}

pub fn required(
    view: View,
    base: usize,
    relative: u16,
) Error!usize {
    return table.offset.required16(view, base, relative);
}

pub fn optionalClassDef(
    view: View,
    base: usize,
    relative: u16,
) Error!usize {
    return (try table.offset.optional16(
        view,
        base,
        relative,
    )) orelse table.class_def.empty_offset;
}

pub fn validateCoverage(view: View, offset: usize) Error!void {
    return table.coverage.validate(view, offset, .indexed);
}

pub fn validateClassDef(view: View, offset: usize) Error!void {
    return table.class_def.validate(view, offset);
}

pub fn validateOptionalClassDef(view: View, offset: usize) Error!void {
    if (offset == table.class_def.empty_offset) return;
    return table.class_def.validate(view, offset);
}

pub fn ensureGlyphWithinMaxp(view: View, glyph: usize) Error!void {
    if (view.glyph_count) |glyph_count| {
        if (glyph >= glyph_count) return error.BadGsub;
    }
}

pub fn validateRecords(
    comptime Executor: type,
    view: View,
    offset: usize,
    count: usize,
) Error!void {
    return records.validateReferences(Executor, view, offset, count);
}
