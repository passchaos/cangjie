//! GSUB ScriptList and LangSys feature selection.
//!
//! This module resolves table-relative offsets and produces compact feature
//! indexes. It deliberately does not decide whether an optional feature is
//! enabled; required/default policy remains with the shaping executor.

const std = @import("std");
const table = @import("../table/root.zig");
const unicode = @import("../../unicode.zig");

pub const Error = table.view.Error;
pub const View = table.View;

pub const Item = struct {
    index: u16,
    required: bool = false,
};

/// Resolve the requested Script, falling back to DFLT when it is absent.
///
/// Duplicate Script tags occur in production fonts. The list must remain
/// nondecreasing, and the first authored matching record is authoritative.
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
///
/// Unlike Script records, duplicate language tags are rejected because the
/// second branch would be unreachable under deterministic first-match lookup.
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

/// Collect into fixed storage when possible, falling back to caller-owned
/// allocation without truncating large LangSys feature arrays.
pub fn collectLanguageStackFirst(
    view: View,
    language_offset: usize,
    stack: []Item,
    stack_len: *usize,
    owned: *std.ArrayList(Item),
    allocator: std.mem.Allocator,
) (Error || std.mem.Allocator.Error)!void {
    try view.ensure(language_offset, 6);
    const required_index = try view.readU16(language_offset + 2);
    const feature_count = try view.readU16(language_offset + 4);
    try view.ensure(language_offset + 6, @as(usize, feature_count) * 2);
    const max_item_count =
        @as(usize, feature_count) + @intFromBool(required_index != 0xffff);
    if (max_item_count > stack.len) {
        return collectLanguage(view, language_offset, owned, allocator);
    }
    if (required_index != 0xffff) {
        appendToBuffer(stack, stack_len, required_index, true);
    }
    for (0..feature_count) |feature_index| {
        appendToBuffer(
            stack,
            stack_len,
            try view.readU16(language_offset + 6 + feature_index * 2),
            false,
        );
    }
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

pub fn validateFeatureRecords(
    view: View,
    feature_list_offset: usize,
    feature_count: u16,
) Error!void {
    return validateTagRecords(
        view,
        feature_list_offset + 2,
        feature_count,
        true,
    );
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

fn appendToBuffer(
    items: []Item,
    length: *usize,
    index: u16,
    required: bool,
) void {
    for (items[0..length.*]) |*item| {
        if (item.index != index) continue;
        item.required = item.required or required;
        return;
    }
    std.debug.assert(length.* < items.len);
    items[length.*] = .{ .index = index, .required = required };
    length.* += 1;
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
                return error.BadGsub;
            }
        }
        previous = tag;
    }
}
