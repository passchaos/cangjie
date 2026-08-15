//! `stch` substitution provenance and emitted-glyph sidecar state.

const std = @import("std");

const GlyphPosition = @import("../../../layout/glyph_position.zig").GlyphPosition;
const ligature_provenance = @import("../../../ligature_provenance.zig");
const unicode = @import("../../../unicode.zig");

pub fn recordSubstitutions(
    ligature_components: *ligature_provenance.Store,
) void {
    for (ligature_components.infos.items) |*info| {
        if (!info.flags.multiplied) continue;
        info.flags.stch_action =
            if (info.flags.multiple_component % 2 == 0)
                .fixed
            else
                .repeating;
    }
}

pub fn appendOutput(
    allocator: std.mem.Allocator,
    stch_actions: *std.ArrayList(u8),
    action: ligature_provenance.StchAction,
    output_len: usize,
) std.mem.Allocator.Error!void {
    std.debug.assert(output_len != 0);
    if (stch_actions.items.len == 0 and action == .none) return;
    if (stch_actions.items.len == 0) {
        // Keep the overwhelmingly common no-stretch sidecar empty. Once an
        // actual tile reaches output, backfill emitted slots—not GSUB input
        // slots, because hidden ignorables and one-to-many output differ.
        try stch_actions.resize(allocator, output_len - 1);
        @memset(
            stch_actions.items,
            @intFromEnum(ligature_provenance.StchAction.none),
        );
    }
    std.debug.assert(stch_actions.items.len == output_len - 1);
    try stch_actions.append(allocator, @intFromEnum(action));
}

pub fn markContext(glyphs: []const GlyphPosition, stch_actions: []u8) void {
    if (glyphs.len != stch_actions.len) return;
    for (glyphs, stch_actions) |glyph, *raw_action| {
        if (isContextCodepoint(glyph.codepoint)) raw_action.* |= 0x80;
    }
}

pub fn fromInt(value: u8) ligature_provenance.StchAction {
    return switch (value & 0x03) {
        @intFromEnum(ligature_provenance.StchAction.fixed) => .fixed,
        @intFromEnum(ligature_provenance.StchAction.repeating) => .repeating,
        else => .none,
    };
}

pub fn isContext(value: u8) bool {
    return (value & 0x80) != 0;
}

fn isContextCodepoint(codepoint: u21) bool {
    return codepoint == 0x070f or
        unicode.isDefaultIgnorableForShaping(codepoint) or
        isArabicWordCodepoint(codepoint);
}

fn isArabicWordCodepoint(codepoint: u21) bool {
    if (unicode.isUnicodeMarkCodepoint(codepoint) or
        unicode.isSpacingMarkCodepoint(codepoint) or
        isDecimalNumber(codepoint))
    {
        return true;
    }
    return switch (unicode.joiningTypeForCodepoint(codepoint)) {
        .non_joining, .transparent => false,
        else => true,
    };
}

fn isDecimalNumber(codepoint: u21) bool {
    return (codepoint >= '0' and codepoint <= '9') or
        (codepoint >= 0x0660 and codepoint <= 0x0669) or
        (codepoint >= 0x06f0 and codepoint <= 0x06f9);
}

test "action sidecar stays lazy and backfills emitted output" {
    var action_list = std.ArrayList(u8).empty;
    defer action_list.deinit(std.testing.allocator);

    try appendOutput(std.testing.allocator, &action_list, .none, 1);
    try appendOutput(std.testing.allocator, &action_list, .none, 2);
    try std.testing.expectEqual(@as(usize, 0), action_list.items.len);

    // The output length deliberately jumps over one-to-many emitted glyphs.
    try appendOutput(std.testing.allocator, &action_list, .fixed, 4);
    try std.testing.expectEqualSlices(u8, &.{
        @intFromEnum(ligature_provenance.StchAction.none),
        @intFromEnum(ligature_provenance.StchAction.none),
        @intFromEnum(ligature_provenance.StchAction.none),
        @intFromEnum(ligature_provenance.StchAction.fixed),
    }, action_list.items);
    try appendOutput(std.testing.allocator, &action_list, .none, 5);
    try std.testing.expectEqual(@as(usize, 5), action_list.items.len);
}
