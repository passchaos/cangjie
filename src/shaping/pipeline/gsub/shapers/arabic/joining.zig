//! Arabic-family joining forms and source-feature masks.

const std = @import("std");

const cluster_safety = @import("../../../../cluster_safety.zig");
const gsub = @import("../../../../../gsub.zig");
const unicode = @import("../../../../../unicode.zig");

pub fn markNativeOrder(
    source_features: []u32,
    codepoints: []const u21,
    glyph_source_indices: []const usize,
) void {
    @memset(source_features, 0);
    overlayNativeOrder(
        source_features,
        codepoints,
        glyph_source_indices,
    );
}

pub fn overlayNativeOrder(
    source_features: []u32,
    codepoints: []const u21,
    glyph_source_indices: []const usize,
) void {
    if (codepoints.len == 0 or glyph_source_indices.len == 0) return;

    var ordered_codepoints: [128]u21 = undefined;
    var ordered_sources: [128]usize = undefined;
    if (glyph_source_indices.len > ordered_codepoints.len) {
        markNativeOrderFallback(
            source_features,
            codepoints,
            glyph_source_indices,
        );
        return;
    }

    var ordered_len: usize = 0;
    for (glyph_source_indices) |source| {
        if (source >= codepoints.len) continue;
        ordered_sources[ordered_len] = source;
        ordered_codepoints[ordered_len] = codepoints[source];
        ordered_len += 1;
    }
    if (ordered_len == 0) return;

    var forms: [128]unicode.JoiningForm = undefined;
    unicode.resolveJoiningForms(
        ordered_codepoints[0..ordered_len],
        forms[0..ordered_len],
    ) catch return;
    for (
        forms[0..ordered_len],
        ordered_sources[0..ordered_len],
    ) |form, source| {
        setSourceFeature(source_features, source, form);
    }
}

pub fn resolveWithContext(
    allocator: std.mem.Allocator,
    before: []const u8,
    item_codepoints: []const u21,
    after: []const u8,
    logical_context: ?@import("../../../types.zig").LogicalContext,
    item_forms: []unicode.JoiningForm,
) !void {
    if (logical_context) |context| {
        if (context.joining_before != null or context.joining_after != null) {
            return unicode.resolveJoiningFormsWithNeighbors(
                item_codepoints,
                item_forms,
                context.joiningBefore(),
                context.joiningAfter(),
            );
        }
        // A complete internal item needs no context sidecar. Preserve the
        // allocation-free Arabic fast path when itemization found no cut.
        if (context.active_start == 0 and
            context.active_end == context.text.len and
            context.external_before.len == 0 and
            context.external_after.len == 0)
        {
            return try unicode.resolveJoiningForms(item_codepoints, item_forms);
        }
    }
    if (before.len == 0 and after.len == 0) {
        return try unicode.resolveJoiningForms(item_codepoints, item_forms);
    }

    var context_codepoints = std.ArrayList(u21).empty;
    defer context_codepoints.deinit(allocator);
    try appendUtf8Codepoints(allocator, &context_codepoints, before);
    const item_start = context_codepoints.items.len;
    try context_codepoints.appendSlice(allocator, item_codepoints);
    try appendUtf8Codepoints(allocator, &context_codepoints, after);

    const context_forms = try allocator.alloc(
        unicode.JoiningForm,
        context_codepoints.items.len,
    );
    defer allocator.free(context_forms);
    try unicode.resolveJoiningForms(context_codepoints.items, context_forms);
    @memcpy(
        item_forms,
        context_forms[item_start..][0..item_codepoints.len],
    );
}

pub fn featureTag(form: unicode.JoiningForm) u32 {
    return switch (form) {
        .isolated => unicode.tag("isol"),
        .initial => unicode.tag("init"),
        .medial => unicode.tag("medi"),
        .final => unicode.tag("fina"),
        .none => 0,
    };
}

pub fn inheritMongolianVariationSelectors(
    source_features: []u32,
    codepoints: []const u21,
) void {
    for (codepoints, 0..) |codepoint, index| {
        if (!unicode.isMongolianFreeVariationSelector(codepoint) or index == 0) {
            continue;
        }
        source_features[index] = source_features[index - 1];
    }
}

/// Record HarfBuzz-compatible SAFE_TO_INSERT_TATWEEL candidates.
///
/// A boundary before source N is eligible when source N joins to the previous
/// non-transparent source. This nominates an insertion point only; final output
/// clears it when GSUB/GPOS/kerning marks the same source boundary unsafe.
pub fn markSafeTatweelBoundaries(
    allocator: std.mem.Allocator,
    boundaries: *cluster_safety.SourceBoundaries,
    codepoints: []const u21,
    forms: []const unicode.JoiningForm,
) !void {
    if (codepoints.len != forms.len) return error.InvalidJoiningInput;
    for (codepoints, forms, 0..) |codepoint, form, source_index| {
        if (unicode.joiningTypeForCodepoint(codepoint) == .transparent) {
            continue;
        }
        if (form != .medial and form != .final) continue;
        try boundaries.markSafeTatweelBeforeSource(
            allocator,
            source_index,
        );
    }
}

fn markNativeOrderFallback(
    source_features: []u32,
    codepoints: []const u21,
    glyph_source_indices: []const usize,
) void {
    var previous_source: ?usize = null;
    var previous_form: unicode.JoiningForm = .none;
    for (glyph_source_indices) |source| {
        if (source >= codepoints.len) continue;
        var pair = [_]u21{ codepoints[source], 0 };
        if (previous_source) |previous| {
            pair[0] = codepoints[previous];
            pair[1] = codepoints[source];
            var forms: [2]unicode.JoiningForm = undefined;
            unicode.resolveJoiningForms(&pair, &forms) catch {
                previous_source = source;
                previous_form = .none;
                continue;
            };
            if (previous_form == .none) {
                setSourceFeature(source_features, previous, forms[0]);
            }
            previous_form = forms[1];
            setSourceFeature(source_features, source, forms[1]);
        } else {
            previous_form = .none;
        }
        previous_source = source;
    }
}

fn setSourceFeature(
    source_features: []u32,
    source: usize,
    form: unicode.JoiningForm,
) void {
    if (source >= source_features.len) return;
    const joining_mask =
        (gsub.feature.sourceMaskForTag(unicode.tag("isol")).? |
            gsub.feature.sourceMaskForTag(unicode.tag("init")).? |
            gsub.feature.sourceMaskForTag(unicode.tag("medi")).? |
            gsub.feature.sourceMaskForTag(unicode.tag("fina")).?) &
        ~gsub.feature.source_mask_marker;
    const form_mask = switch (form) {
        .isolated => gsub.feature.sourceMaskForTag(unicode.tag("isol")).?,
        .initial => gsub.feature.sourceMaskForTag(unicode.tag("init")).?,
        .medial => gsub.feature.sourceMaskForTag(unicode.tag("medi")).?,
        .final => gsub.feature.sourceMaskForTag(unicode.tag("fina")).?,
        .none => 0,
    };
    const existing = source_features[source];
    source_features[source] = (existing & ~joining_mask) | form_mask;
}

fn appendUtf8Codepoints(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u21),
    text: []const u8,
) !void {
    var iterator = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iterator.nextCodepoint()) |codepoint| {
        try out.append(allocator, codepoint);
    }
}

test "tatweel candidates follow joining across transparent marks" {
    const codepoints = [_]u21{ 0x0628, 0x064e, 0x0628 };
    var forms: [codepoints.len]unicode.JoiningForm = undefined;
    try unicode.resolveJoiningForms(&codepoints, &forms);
    var boundaries = cluster_safety.SourceBoundaries{};
    defer boundaries.deinit(std.testing.allocator);
    boundaries.reset(0, 6, &.{ 0, 2, 4 });
    try markSafeTatweelBoundaries(
        std.testing.allocator,
        &boundaries,
        &codepoints,
        &forms,
    );
    try std.testing.expect(!boundaries.isSafeTatweelBeforeByte(2));
    try std.testing.expect(boundaries.isSafeTatweelBeforeByte(4));
}
