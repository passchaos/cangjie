//! OpenType JSTF grammar, cross-table validation, and owned inspection.

const std = @import("std");

const bin = @import("../../../../binary.zig");
const gpos = @import("../../../../gpos.zig");
const gpos_table = @import("../../../../gpos/table/root.zig");
const gpos_validation = @import("../../../../gpos/validation/root.zig");
const sfnt = @import("../../../sfnt/root.zig");
const types = @import("types.zig");

pub const Info = types.Info;
pub const Language = types.Language;
pub const LookupList = types.LookupList;
pub const MaxLookup = types.MaxLookup;
pub const Priority = types.Priority;
pub const Script = types.Script;

pub const Error =
    error{ BadSfnt, EndOfStream, UnsupportedGpos } ||
    std.mem.Allocator.Error;

const Context = struct {
    data: []const u8,
    table: sfnt.Record,
    gsub_lookup_count: usize,
    gpos_lookup_count: usize,

    fn tableEnd(self: Context) usize {
        return self.table.offset + self.table.length;
    }
};

pub fn validate(
    data: []const u8,
    table: sfnt.Record,
    gsub: ?sfnt.Record,
    gpos_record: ?sfnt.Record,
    glyph_count: u16,
) Error!void {
    const context = Context{
        .data = data,
        .table = table,
        .gsub_lookup_count = try lookupCount(data, gsub, .gsub),
        .gpos_lookup_count = try lookupCount(data, gpos_record, .gpos),
    };
    try validateContext(context, glyph_count);
}

fn validateContext(context: Context, glyph_count: u16) Error!void {
    try requireRange(context, 0, 6);
    if (try readU32(context, 0) != 0x00010000) return error.BadSfnt;
    const script_count: usize = @intCast(try readU16(context, 4));
    try requireRange(context, 6, script_count * 6);
    var previous_tag: ?[4]u8 = null;
    for (0..script_count) |script_index| {
        const record = 6 + script_index * 6;
        const tag = try readTag(context, record);
        try requireIncreasingTag(previous_tag, tag);
        previous_tag = tag;
        const script = try requiredChild(
            context,
            0,
            try readU16(context, record + 4),
            6,
        );
        try validateScript(context, script, glyph_count);
    }
}

pub fn info(
    allocator: std.mem.Allocator,
    data: []const u8,
    table: sfnt.Record,
    gsub: ?sfnt.Record,
    gpos_record: ?sfnt.Record,
    glyph_count: u16,
) Error!Info {
    const context = Context{
        .data = data,
        .table = table,
        .gsub_lookup_count = try lookupCount(data, gsub, .gsub),
        .gpos_lookup_count = try lookupCount(data, gpos_record, .gpos),
    };
    try validateContext(context, glyph_count);
    const script_count: usize = @intCast(try readU16(context, 4));
    const scripts = try allocator.alloc(Script, script_count);
    errdefer allocator.free(scripts);
    var initialized: usize = 0;
    errdefer for (scripts[0..initialized]) |script| freeScript(allocator, script);
    for (scripts, 0..) |*script, script_index| {
        const record = 6 + script_index * 6;
        const script_offset = try requiredChild(
            context,
            0,
            try readU16(context, record + 4),
            6,
        );
        script.* = try readScript(
            allocator,
            context,
            script_offset,
            try readTag(context, record),
        );
        initialized += 1;
    }
    return .{
        .version = 0x00010000,
        .scripts = scripts,
    };
}

pub fn free(allocator: std.mem.Allocator, value: Info) void {
    for (value.scripts) |script| freeScript(allocator, script);
    allocator.free(value.scripts);
}

fn validateScript(
    context: Context,
    script: usize,
    glyph_count: u16,
) Error!void {
    try requireRange(context, script, 6);
    const extender_relative = try readU16(context, script);
    if (extender_relative != 0) {
        const extender = try requiredChild(
            context,
            script,
            extender_relative,
            2,
        );
        try validateExtenders(context, extender, glyph_count);
    }
    const default_relative = try readU16(context, script + 2);
    if (default_relative != 0) {
        try validateLanguage(context, try requiredChild(
            context,
            script,
            default_relative,
            2,
        ));
    }
    const language_count: usize = @intCast(try readU16(context, script + 4));
    try requireRange(context, script + 6, language_count * 6);
    var previous_tag: ?[4]u8 = null;
    for (0..language_count) |language_index| {
        const record = script + 6 + language_index * 6;
        const tag = try readTag(context, record);
        try requireIncreasingTag(previous_tag, tag);
        previous_tag = tag;
        try validateLanguage(context, try requiredChild(
            context,
            script,
            try readU16(context, record + 4),
            2,
        ));
    }
}

fn validateExtenders(
    context: Context,
    start: usize,
    glyph_count: u16,
) Error!void {
    const count: usize = @intCast(try readU16(context, start));
    try requireRange(context, start + 2, count * 2);
    var previous: ?u16 = null;
    for (0..count) |index| {
        const glyph = try readU16(context, start + 2 + index * 2);
        if (glyph >= glyph_count) return error.BadSfnt;
        if (previous) |last| if (glyph <= last) return error.BadSfnt;
        previous = glyph;
    }
}

fn validateLanguage(context: Context, language: usize) Error!void {
    const priority_count: usize = @intCast(try readU16(context, language));
    try requireRange(context, language + 2, priority_count * 2);
    for (0..priority_count) |priority_index| {
        try validatePriority(context, try requiredChild(
            context,
            language,
            try readU16(context, language + 2 + priority_index * 2),
            20,
        ));
    }
}

fn validatePriority(context: Context, priority: usize) Error!void {
    try requireRange(context, priority, 20);
    for (0..10) |field_index| {
        const relative = try readU16(context, priority + field_index * 2);
        if (relative == 0) continue;
        const child = try requiredChild(
            context,
            priority,
            relative,
            2,
        );
        switch (field_index) {
            0, 1, 5, 6 => try validateIndexList(
                context,
                child,
                context.gsub_lookup_count,
            ),
            2, 3, 7, 8 => try validateIndexList(
                context,
                child,
                context.gpos_lookup_count,
            ),
            4, 9 => try validateMaxLookups(context, child),
            else => unreachable,
        }
    }
}

fn validateIndexList(
    context: Context,
    start: usize,
    limit: usize,
) Error!void {
    const count: usize = @intCast(try readU16(context, start));
    try requireRange(context, start + 2, count * 2);
    var previous: ?u16 = null;
    for (0..count) |index| {
        const value = try readU16(context, start + 2 + index * 2);
        if (value >= limit) return error.BadSfnt;
        if (previous) |last| if (value <= last) return error.BadSfnt;
        previous = value;
    }
}

fn validateMaxLookups(context: Context, start: usize) Error!void {
    const count: usize = @intCast(try readU16(context, start));
    try requireRange(context, start + 2, count * 2);
    const view = gpos_table.View{
        .data = context.data,
        .offset = context.table.offset,
        .length = context.table.length,
        .validating_full_lookup_list = true,
    };
    for (0..count) |index| {
        const lookup = try requiredChild(
            context,
            start,
            try readU16(context, start + 2 + index * 2),
            6,
        );
        gpos_validation.lookup.headerAndExtensions(view, lookup) catch |err|
            return mapGposError(err);
        gpos_validation.lookup.lookupSubtables(
            view,
            lookup,
            try readU16(context, lookup),
            try readU16(context, lookup + 4),
        ) catch |err| return mapGposError(err);
    }
}

fn readScript(
    allocator: std.mem.Allocator,
    context: Context,
    script_offset: usize,
    tag: [4]u8,
) Error!Script {
    const extender_relative = try readU16(context, script_offset);
    const extenders = if (extender_relative == 0)
        try allocator.alloc(@import("../../../../glyph.zig").GlyphId, 0)
    else
        try readExtenders(
            allocator,
            context,
            try requiredChild(context, script_offset, extender_relative, 2),
        );
    errdefer allocator.free(extenders);

    const default_relative = try readU16(context, script_offset + 2);
    var default_language: ?Language = null;
    if (default_relative != 0) {
        default_language = try readLanguage(
            allocator,
            context,
            try requiredChild(context, script_offset, default_relative, 2),
            null,
        );
    }
    errdefer if (default_language) |language| freeLanguage(allocator, language);

    const language_count: usize =
        @intCast(try readU16(context, script_offset + 4));
    const languages = try allocator.alloc(Language, language_count);
    errdefer allocator.free(languages);
    var initialized: usize = 0;
    errdefer for (languages[0..initialized]) |language|
        freeLanguage(allocator, language);
    for (languages, 0..) |*language, language_index| {
        const record = script_offset + 6 + language_index * 6;
        language.* = try readLanguage(
            allocator,
            context,
            try requiredChild(
                context,
                script_offset,
                try readU16(context, record + 4),
                2,
            ),
            try readTag(context, record),
        );
        initialized += 1;
    }
    return .{
        .tag = tag,
        .extender_glyphs = extenders,
        .default_language = default_language,
        .languages = languages,
    };
}

fn readExtenders(
    allocator: std.mem.Allocator,
    context: Context,
    start: usize,
) Error![]@import("../../../../glyph.zig").GlyphId {
    const count: usize = @intCast(try readU16(context, start));
    const result = try allocator.alloc(
        @import("../../../../glyph.zig").GlyphId,
        count,
    );
    for (result, 0..) |*glyph, index| {
        glyph.* = try readU16(context, start + 2 + index * 2);
    }
    return result;
}

fn readLanguage(
    allocator: std.mem.Allocator,
    context: Context,
    start: usize,
    tag: ?[4]u8,
) Error!Language {
    const count: usize = @intCast(try readU16(context, start));
    const priorities = try allocator.alloc(Priority, count);
    errdefer allocator.free(priorities);
    var initialized: usize = 0;
    errdefer for (priorities[0..initialized]) |priority|
        freePriority(allocator, priority);
    for (priorities, 0..) |*priority, index| {
        priority.* = try readPriority(
            allocator,
            context,
            try requiredChild(
                context,
                start,
                try readU16(context, start + 2 + index * 2),
                20,
            ),
        );
        initialized += 1;
    }
    return .{ .tag = tag, .priorities = priorities };
}

fn readPriority(
    allocator: std.mem.Allocator,
    context: Context,
    start: usize,
) Error!Priority {
    var result = Priority{
        .shrinkage_enable_gsub = .{ .indices = &.{} },
        .shrinkage_disable_gsub = .{ .indices = &.{} },
        .shrinkage_enable_gpos = .{ .indices = &.{} },
        .shrinkage_disable_gpos = .{ .indices = &.{} },
        .shrinkage_max = &.{},
        .extension_enable_gsub = .{ .indices = &.{} },
        .extension_disable_gsub = .{ .indices = &.{} },
        .extension_enable_gpos = .{ .indices = &.{} },
        .extension_disable_gpos = .{ .indices = &.{} },
        .extension_max = &.{},
    };
    errdefer freePriority(allocator, result);
    inline for (0..10) |field_index| {
        const relative = try readU16(context, start + field_index * 2);
        if (relative != 0) {
            const child = try requiredChild(context, start, relative, 2);
            switch (field_index) {
                0 => result.shrinkage_enable_gsub =
                    try readIndexList(allocator, context, child),
                1 => result.shrinkage_disable_gsub =
                    try readIndexList(allocator, context, child),
                2 => result.shrinkage_enable_gpos =
                    try readIndexList(allocator, context, child),
                3 => result.shrinkage_disable_gpos =
                    try readIndexList(allocator, context, child),
                4 => result.shrinkage_max =
                    try readMaxLookups(allocator, context, child),
                5 => result.extension_enable_gsub =
                    try readIndexList(allocator, context, child),
                6 => result.extension_disable_gsub =
                    try readIndexList(allocator, context, child),
                7 => result.extension_enable_gpos =
                    try readIndexList(allocator, context, child),
                8 => result.extension_disable_gpos =
                    try readIndexList(allocator, context, child),
                9 => result.extension_max =
                    try readMaxLookups(allocator, context, child),
                else => unreachable,
            }
        }
    }
    return result;
}

fn readIndexList(
    allocator: std.mem.Allocator,
    context: Context,
    start: usize,
) Error!LookupList {
    const count: usize = @intCast(try readU16(context, start));
    const values = try allocator.alloc(u16, count);
    for (values, 0..) |*value, index| {
        value.* = try readU16(context, start + 2 + index * 2);
    }
    return .{ .indices = values };
}

fn readMaxLookups(
    allocator: std.mem.Allocator,
    context: Context,
    start: usize,
) Error![]MaxLookup {
    const count: usize = @intCast(try readU16(context, start));
    const result = try allocator.alloc(MaxLookup, count);
    for (result, 0..) |*lookup, index| {
        const lookup_start = try requiredChild(
            context,
            start,
            try readU16(context, start + 2 + index * 2),
            6,
        );
        lookup.* = .{
            .lookup_type = try readU16(context, lookup_start),
            .lookup_flag = try readU16(context, lookup_start + 2),
            .subtable_count = try readU16(context, lookup_start + 4),
            .offset = lookup_start,
        };
    }
    return result;
}

fn freeScript(allocator: std.mem.Allocator, script: Script) void {
    allocator.free(script.extender_glyphs);
    if (script.default_language) |language| freeLanguage(allocator, language);
    for (script.languages) |language| freeLanguage(allocator, language);
    allocator.free(script.languages);
}

fn freeLanguage(allocator: std.mem.Allocator, language: Language) void {
    for (language.priorities) |priority| freePriority(allocator, priority);
    allocator.free(language.priorities);
}

fn freePriority(allocator: std.mem.Allocator, priority: Priority) void {
    allocator.free(priority.shrinkage_enable_gsub.indices);
    allocator.free(priority.shrinkage_disable_gsub.indices);
    allocator.free(priority.shrinkage_enable_gpos.indices);
    allocator.free(priority.shrinkage_disable_gpos.indices);
    allocator.free(priority.shrinkage_max);
    allocator.free(priority.extension_enable_gsub.indices);
    allocator.free(priority.extension_disable_gsub.indices);
    allocator.free(priority.extension_enable_gpos.indices);
    allocator.free(priority.extension_disable_gpos.indices);
    allocator.free(priority.extension_max);
}

const LookupKind = enum { gsub, gpos };

fn lookupCount(
    data: []const u8,
    record: ?sfnt.Record,
    kind: LookupKind,
) Error!usize {
    const table = record orelse return 0;
    if (table.length < 10) return error.BadSfnt;
    const top_level_relative = try bin.readU16At(data, table.offset + 8);
    if (top_level_relative == 0 or
        top_level_relative > table.length or
        table.length - top_level_relative < 2)
    {
        return error.BadSfnt;
    }
    _ = kind;
    return @intCast(try bin.readU16At(
        data,
        table.offset + top_level_relative,
    ));
}

fn requiredChild(
    context: Context,
    base: usize,
    relative: u16,
    minimum: usize,
) Error!usize {
    if (relative == 0) return error.BadSfnt;
    const amount: usize = @intCast(relative);
    if (base > context.table.length or
        amount > context.table.length - base)
    {
        return error.BadSfnt;
    }
    const result = base + amount;
    try requireRange(context, result, minimum);
    return result;
}

fn requireRange(
    context: Context,
    relative: usize,
    length: usize,
) Error!void {
    if (relative > context.table.length or
        length > context.table.length - relative)
    {
        return error.BadSfnt;
    }
    if (context.table.offset > context.data.len or
        context.table.length > context.data.len - context.table.offset)
    {
        return error.BadSfnt;
    }
}

fn readU16(context: Context, relative: usize) Error!u16 {
    try requireRange(context, relative, 2);
    return try bin.readU16At(context.data, context.table.offset + relative);
}

fn readU32(context: Context, relative: usize) Error!u32 {
    try requireRange(context, relative, 4);
    return try bin.readU32At(context.data, context.table.offset + relative);
}

fn readTag(context: Context, relative: usize) Error![4]u8 {
    try requireRange(context, relative, 4);
    return try bin.readTagAt(context.data, context.table.offset + relative);
}

fn requireIncreasingTag(previous: ?[4]u8, current: [4]u8) Error!void {
    if (previous) |last| {
        if (std.mem.order(u8, &last, &current) != .lt) {
            return error.BadSfnt;
        }
    }
}

fn mapGposError(err: anytype) Error {
    return switch (err) {
        error.UnsupportedGpos => error.UnsupportedGpos,
        else => error.BadSfnt,
    };
}
