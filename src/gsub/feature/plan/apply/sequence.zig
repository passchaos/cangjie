//! Ordered Script/LangSys feature application without a retained plan.

const std = @import("std");
const merge = @import("../merge.zig");
const model = @import("../../model.zig");
const metadata = @import("../../../runtime/metadata.zig");
const options = @import("../../../runtime/options.zig");
const prefilter = @import("../../../runtime/prefilter/root.zig");
const selection = @import("../selection.zig");
const shared = @import("shared.zig");
const state = @import("../../../runtime/state.zig");
const table = @import("../../../table/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Error = shared.Error;
pub const Options = options.Options;
pub const View = table.View;

pub fn apply(
    comptime Executor: type,
    view: View,
    applications: []const model.Application,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
) Error!void {
    try metadata.validateApplications(run, glyphs.items.len, applications);
    var storage = state.Storage{};
    const prepared = try state.prepareForTable(
        view,
        run,
        glyphs.items.len,
        &storage,
    );
    if (try isEmpty(view)) return;
    var cache = prefilter.Cache.init();

    // Use stack storage for ordinary LangSys feature lists, preserving
    // arbitrarily large authored arrays through the owned fallback.
    var stack: [64]selection.Item = undefined;
    var stack_len: usize = 0;
    var owned = std.ArrayList(selection.Item).empty;
    defer owned.deinit(allocator);
    const script_list = try table.offset.required16(
        view,
        0,
        try view.readU16(4),
    );
    const script_offset = (try @import("../../selection.zig").script(
        view,
        script_list,
        prepared.script_tag,
    )) orelse 0;
    if (script_offset != 0) {
        if (try @import("../../selection.zig").languageSystem(
            view,
            script_offset,
            prepared.language_tag,
        )) |lang_sys| {
            try @import("../../selection.zig").collectLanguageStackFirst(
                view,
                lang_sys,
                &stack,
                &stack_len,
                &owned,
                allocator,
            );
        }
    }
    const items = if (owned.items.len != 0)
        owned.items
    else
        stack[0..stack_len];
    const context = try selection.context(view);

    for (items) |item| {
        if (!item.required or item.index >= context.feature_count) continue;
        const record =
            context.feature_list + 2 + @as(usize, item.index) * 6;
        const tag = try view.readU32(record);
        if (selection.contains(applications, tag)) continue;
        var required = prepared;
        required.active_source_feature = null;
        try selectedFeature(
            Executor,
            view,
            tag,
            items,
            context,
            glyphs,
            allocator,
            required,
            &cache,
        );
    }

    for (applications) |application| {
        var selected = prepared;
        selected.active_source_feature =
            if (application.source_scoped) application.tag else null;
        selected.match_source_syllable = application.match_source_syllable;
        selected.active_auto_zwnj = application.auto_zwnj;
        selected.active_auto_zwj = application.auto_zwj;
        selected.active_feature_value = application.value;
        selected.active_feature_random = merge.isRandom(application);
        try selectedFeature(
            Executor,
            view,
            application.tag,
            items,
            context,
            glyphs,
            allocator,
            selected,
            &cache,
        );
    }
}

pub fn selectedFeature(
    comptime Executor: type,
    view: View,
    feature_tag: u32,
    items: []const selection.Item,
    context: selection.Context,
    glyphs: *std.ArrayList(GlyphId),
    allocator: std.mem.Allocator,
    run: Options,
    cache: *prefilter.Cache,
) Error!void {
    if (selection.borrowedLookups(
        view,
        feature_tag,
        items,
        context.feature_count,
        run,
    )) |borrowed| {
        return shared.indices(
            Executor,
            view,
            context.lookup_list,
            context.lookup_count,
            borrowed,
            glyphs,
            allocator,
            run,
            cache,
        );
    }
    const selected = try selection.selectedLookupsOwned(
        view,
        feature_tag,
        items,
        context,
        allocator,
        run,
    );
    defer allocator.free(selected);
    return shared.indices(
        Executor,
        view,
        context.lookup_list,
        context.lookup_count,
        selected,
        glyphs,
        allocator,
        run,
        cache,
    );
}

fn isEmpty(view: View) Error!bool {
    return try view.readU16(4) == 0 and
        try view.readU16(6) == 0 and
        try view.readU16(8) == 0;
}
