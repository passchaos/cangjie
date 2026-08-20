//! Static bindings from nested lookup dispatch to contextual executors.

const std = @import("std");
const contextual = @import("../contextual/root.zig");
const contextual_model = @import("../contextual/model.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;
const positioning = @import("../../../positioning/root.zig");

const Adjustment = contextual_model.Adjustment;
const ApplyNestedFn = contextual_model.ApplyNestedFn;
const ApplyRecordsFn = contextual_model.ApplyRecordsFn;
const Error = contextual_model.Error;
const Options = contextual_model.Options;
const View = contextual_model.View;

pub fn contextCollect(
    view: View,
    subtable: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!void {
    return contextual.context.collect(
        view,
        subtable,
        glyphs,
        adjustments,
        allocator,
        lookup_flag,
        run,
        applyRecords,
    );
}

pub fn contextAt(
    view: View,
    subtable: usize,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
) Error!bool {
    return contextual.context.collectAt(
        view,
        subtable,
        glyphs,
        target_index,
        adjustments,
        allocator,
        lookup_flag,
        run,
        applyRecords,
    );
}

pub fn chainingCollect(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: ApplyNestedFn,
) Error!void {
    switch (try positioning.lookup.contextual.parseChaining(
        view,
        subtable_offset,
    )) {
        .glyph => |subtable| try contextual.chaining.glyph.collect(
            view,
            subtable,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
        .class => |subtable| try contextual.chaining.class.collect(
            view,
            subtable,
            glyphs,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
        .coverage => |parsed| {
            if (parsed.records.input_count == 0) return;
            try contextual.chaining.coverage.execute.collect(
                view,
                contextual.chaining.coverage.execute.fromParsed(parsed),
                glyphs,
                adjustments,
                allocator,
                lookup_flag,
                run,
                applyRecords,
                applyNested,
            );
        },
    }
}

pub fn chainingAt(
    view: View,
    subtable_offset: usize,
    glyphs: []const GlyphId,
    target_index: usize,
    adjustments: *std.ArrayList(Adjustment),
    allocator: std.mem.Allocator,
    lookup_flag: u16,
    run: Options,
    comptime applyRecords: ApplyRecordsFn,
    comptime applyNested: ApplyNestedFn,
) Error!bool {
    if (target_index >= glyphs.len) return false;
    return switch (try positioning.lookup.contextual.parseChaining(
        view,
        subtable_offset,
    )) {
        .glyph => |subtable| contextual.chaining.glyph.collectAt(
            view,
            subtable,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
        .class => |subtable| contextual.chaining.class.collectAt(
            view,
            subtable,
            glyphs,
            target_index,
            adjustments,
            allocator,
            lookup_flag,
            run,
            applyRecords,
        ),
        .coverage => |parsed| if (parsed.records.input_count == 0)
            false
        else
            (try contextual.chaining.coverage.execute.collectAt(
                false,
                view,
                contextual.chaining.coverage.execute.fromParsed(parsed),
                glyphs,
                target_index,
                adjustments,
                allocator,
                lookup_flag,
                run,
                applyRecords,
                applyNested,
            )).matched,
    };
}
