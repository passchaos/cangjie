//! GPOS ScriptList, LangSys, and enabled-feature selection.
//!
//! This module resolves the OpenType activation graph but deliberately does not
//! inspect lookup payloads. Runtime-only filtering, such as skipping mark
//! attachment lookups for a proven mark-free run, remains with the executor.

const std = @import("std");
const table = @import("../table/root.zig");
const unicode = @import("../../unicode.zig");

pub const Error = table.view.Error || error{UnsupportedGpos};
pub const View = table.View;

pub const Item = struct {
    index: u16,
    required: bool = false,
};

pub const Options = struct {
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    overrides: []const unicode.FeatureOverride = &.{},
};

/// Collect enabled lookup indexes in authored feature order.
///
/// The executor may filter individual indexes before sorting/deduplicating the
/// final list. Keeping this result unsorted preserves the activation graph as a
/// reusable parser contract rather than coupling it to one execution strategy.
pub fn lookupIndices(
    view: View,
    allocator: std.mem.Allocator,
    options: Options,
) (Error || std.mem.Allocator.Error)!std.ArrayList(u16) {
    var feature_items = std.ArrayList(Item).empty;
    defer feature_items.deinit(allocator);
    var lookups = std.ArrayList(u16).empty;
    errdefer lookups.deinit(allocator);

    const script_list_offset = try requiredTopLevelOffset(view, 4);
    const feature_list_offset = try requiredTopLevelOffset(view, 6);
    if (try script(view, script_list_offset, options.script_tag)) |script_offset| {
        try collect(
            view,
            script_offset,
            options.language_tag,
            &feature_items,
            allocator,
        );
    }

    const feature_count = try view.readU16(feature_list_offset);
    try view.ensure(feature_list_offset + 2, @as(usize, feature_count) * 6);
    for (feature_items.items) |item| {
        if (item.index >= feature_count) continue;
        const feature_record =
            feature_list_offset + 2 + @as(usize, item.index) * 6;
        const feature_tag = try view.readU32(feature_record);
        // ReqFeatureIndex names mandatory LangSys behavior. User overrides only
        // control optional/default features and cannot suppress this edge.
        if (!item.required and !enabled(feature_tag, options.overrides)) continue;
        const feature_offset = try table.offset.required16(
            view,
            feature_list_offset,
            try view.readU16(feature_record + 4),
        );
        try view.ensure(feature_offset, 4);
        const lookup_count = try view.readU16(feature_offset + 2);
        try view.ensure(feature_offset + 4, @as(usize, lookup_count) * 2);
        for (0..lookup_count) |lookup_index| {
            try lookups.append(
                allocator,
                try view.readU16(feature_offset + 4 + lookup_index * 2),
            );
        }
    }
    return lookups;
}

/// Resolve the requested Script, falling back to DFLT when absent.
///
/// Duplicate Script tags occur in production fonts. The first matching record
/// is authoritative, while validation still walks every authored child.
pub fn script(
    view: View,
    script_list_offset: usize,
    requested: unicode.OpenTypeScriptTag,
) Error!?usize {
    const script_count = try view.readU16(script_list_offset);
    if (!view.assume_validated) {
        try validateScriptRecords(view, script_list_offset, script_count);
    }
    return try findScript(
        view,
        script_list_offset,
        script_count,
        @intFromEnum(requested),
    ) orelse if (requested != .dflt)
        try findScript(
            view,
            script_list_offset,
            script_count,
            @intFromEnum(unicode.OpenTypeScriptTag.dflt),
        )
    else
        null;
}

/// Resolve the requested LangSys, falling back to DefaultLangSys.
pub fn languageSystem(
    view: View,
    script_offset: usize,
    requested: unicode.OpenTypeLanguageTag,
) Error!?usize {
    try view.ensure(script_offset, 4);
    const default_relative = try view.readU16(script_offset);
    const language_count = try view.readU16(script_offset + 2);
    try validateLanguageRecords(view, script_offset, language_count);
    if (requested != .dflt) {
        if (try findLanguage(
            view,
            script_offset,
            language_count,
            @intFromEnum(requested),
        )) |language_offset| {
            return language_offset;
        }
    }
    return try table.offset.optional16(
        view,
        script_offset,
        default_relative,
    );
}

pub fn collect(
    view: View,
    script_offset: usize,
    requested_language: unicode.OpenTypeLanguageTag,
    items: *std.ArrayList(Item),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    const language_offset = try languageSystem(
        view,
        script_offset,
        requested_language,
    ) orelse return;
    return collectLanguage(view, language_offset, items, allocator);
}

pub fn collectLanguage(
    view: View,
    language_offset: usize,
    items: *std.ArrayList(Item),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    try view.ensure(language_offset, 6);
    const required_index = try view.readU16(language_offset + 2);
    const feature_count = try view.readU16(language_offset + 4);
    try view.ensure(language_offset + 6, @as(usize, feature_count) * 2);
    if (required_index != 0xffff) {
        try append(items, allocator, required_index, true);
    }
    for (0..feature_count) |feature_index| {
        try append(
            items,
            allocator,
            try view.readU16(language_offset + 6 + feature_index * 2),
            false,
        );
    }
}

pub fn enabled(
    feature_tag: u32,
    overrides: []const unicode.FeatureOverride,
) bool {
    for (overrides) |override| {
        if (override.tag == feature_tag) return override.enabled;
    }
    return defaultEnabled(feature_tag);
}

pub fn validateScriptRecords(
    view: View,
    script_list_offset: usize,
    script_count: u16,
) Error!void {
    return validateTagRecords(
        view,
        script_list_offset + 2,
        script_count,
        true,
    );
}

pub fn validateLanguageRecords(
    view: View,
    script_offset: usize,
    language_count: u16,
) Error!void {
    return validateTagRecords(
        view,
        script_offset + 4,
        language_count,
        false,
    );
}

fn defaultEnabled(feature_tag: u32) bool {
    return feature_tag == unicode.tag("abvm") or
        feature_tag == unicode.tag("blwm") or
        feature_tag == unicode.tag("ccmp") or
        feature_tag == unicode.tag("locl") or
        feature_tag == unicode.tag("mark") or
        feature_tag == unicode.tag("mkmk") or
        feature_tag == unicode.tag("rlig") or
        feature_tag == unicode.tag("calt") or
        feature_tag == unicode.tag("clig") or
        feature_tag == unicode.tag("curs") or
        feature_tag == unicode.tag("dist") or
        feature_tag == unicode.tag("kern") or
        feature_tag == unicode.tag("liga") or
        feature_tag == unicode.tag("rclt");
}

fn findScript(
    view: View,
    script_list_offset: usize,
    script_count: u16,
    script_tag: u32,
) Error!?usize {
    for (0..script_count) |script_index| {
        const record = script_list_offset + 2 + script_index * 6;
        if (try view.readU32(record) != script_tag) continue;
        return try table.offset.required16(
            view,
            script_list_offset,
            try view.readU16(record + 4),
        );
    }
    return null;
}

fn findLanguage(
    view: View,
    script_offset: usize,
    language_count: u16,
    language_tag: u32,
) Error!?usize {
    for (0..language_count) |language_index| {
        const record = script_offset + 4 + language_index * 6;
        if (try view.readU32(record) != language_tag) continue;
        return try table.offset.required16(
            view,
            script_offset,
            try view.readU16(record + 4),
        );
    }
    return null;
}

fn append(
    items: *std.ArrayList(Item),
    allocator: std.mem.Allocator,
    index: u16,
    required: bool,
) std.mem.Allocator.Error!void {
    for (items.items) |*item| {
        if (item.index != index) continue;
        item.required = item.required or required;
        return;
    }
    try items.append(allocator, .{ .index = index, .required = required });
}

fn validateTagRecords(
    view: View,
    records_offset: usize,
    record_count: u16,
    allow_equal: bool,
) Error!void {
    try view.ensure(records_offset, @as(usize, record_count) * 6);
    var previous: ?u32 = null;
    for (0..record_count) |record_index| {
        const tag = try view.readU32(records_offset + record_index * 6);
        if (previous) |last| {
            if (if (allow_equal) tag < last else tag <= last) {
                return error.BadGpos;
            }
        }
        previous = tag;
    }
}

fn requiredTopLevelOffset(view: View, field_offset: usize) Error!usize {
    return table.offset.required16(
        view,
        0,
        try view.readU16(field_offset),
    );
}
