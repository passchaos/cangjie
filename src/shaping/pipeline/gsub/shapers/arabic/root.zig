//! Arabic, Syriac, Adlam, and Mongolian GSUB stage orchestration.

const std = @import("std");
const font_shaping = @import("../../../../../font.zig").shaping;

const Font = @import("../../../../../font.zig").Font;
const GdefLookupMetadata =
    @import("../../../../../font.zig").GdefLookupMetadata;
const GlyphId = @import("../../../../../glyph.zig").GlyphId;
const gsub = @import("../../../../../gsub.zig");
const ligature_provenance =
    @import("../../../../../ligature_provenance.zig");
const ShapeStageProfile =
    @import("../../../../../shape_profile.zig").ShapeStageProfile;
const stch_feature = @import("../../../../features/stch/root.zig");
const unicode = @import("../../../../../unicode.zig");
const executor = @import("../../executor.zig");
const features = @import("../../features.zig");
const pipeline_types = @import("../../../types.zig");
pub const joining = @import("joining.zig");

pub const Input = struct {
    allocator: std.mem.Allocator,
    font: *const Font,
    context: executor.Context,
    table_proved: bool,
    glyph_ids: *std.ArrayList(GlyphId),
    codepoints: []const u21,
    glyph_source_indices: []const usize,
    ligature_components: *ligature_provenance.Store,
    source_features: *std.ArrayList(u32),
    joining_forms: *std.ArrayList(unicode.JoiningForm),
    base_gsub_options: gsub.LookupOptions,
    lookup_options: pipeline_types.LookupOptions,
    gdef_metadata: GdefLookupMetadata,
    shape_in_native_direction: bool,
    profile: ?*ShapeStageProfile,
    profile_io: ?std.Io,
};

pub const Result = struct {
    joining_features: []const u32,
};

pub fn supports(script_tag: unicode.OpenTypeScriptTag) bool {
    return script_tag == .arab or
        script_tag == .syrc or
        script_tag == .adlm or
        script_tag == .mong;
}

pub fn run(input: Input) !Result {
    try input.source_features.resize(
        input.allocator,
        input.codepoints.len,
    );
    if (input.shape_in_native_direction) {
        joining.markNativeOrder(
            input.source_features.items,
            input.codepoints,
            input.glyph_source_indices,
        );
    } else {
        try input.joining_forms.resize(
            input.allocator,
            input.codepoints.len,
        );
        try joining.resolveWithContext(
            input.allocator,
            input.lookup_options.context_before,
            input.codepoints,
            input.lookup_options.context_after,
            input.joining_forms.items,
        );
        for (
            input.joining_forms.items,
            input.source_features.items,
        ) |form, *feature| {
            feature.* = joining.featureTag(form);
        }
    }
    if (input.lookup_options.script_tag == .mong) {
        joining.inheritMongolianVariationSelectors(
            input.source_features.items,
            input.codepoints,
        );
    }
    var joining_options = input.base_gsub_options;
    joining_options.source_features = input.source_features.items;

    const stch_enabled = features.enabled(
        unicode.tag("stch"),
        input.lookup_options.features,
        true,
    );
    var common_features_buf: [2]gsub.feature.Application = undefined;
    var common_feature_count: usize = 0;
    if (features.randomApplication(input.lookup_options.features)) |application| {
        common_features_buf[common_feature_count] = application;
        common_feature_count += 1;
    }
    if (stch_enabled) {
        common_features_buf[common_feature_count] = .{
            .tag = unicode.tag("stch"),
            .auto_zwj = false,
        };
        common_feature_count += 1;
    }
    try executor.applyMerged(
        input.font,
        input.context,
        input.table_proved,
        common_features_buf[0..common_feature_count],
        input.glyph_ids,
        joining_options,
        input.gdef_metadata,
    );
    if (stch_enabled) {
        stch_feature.recordSubstitutions(input.ligature_components);
    }

    var applications_buf: [15]gsub.feature.Application = undefined;
    var application_count: usize = 0;
    const planned_features = [_]gsub.feature.Application{
        .{ .tag = unicode.tag("ccmp"), .auto_zwj = false },
        .{ .tag = unicode.tag("locl"), .auto_zwj = false },
        .{ .tag = unicode.tag("ltrm"), .auto_zwj = false },
        .{ .tag = unicode.tag("rtlm"), .auto_zwj = false },
        .{
            .tag = unicode.tag("isol"),
            .source_scoped = true,
            .auto_zwj = false,
        },
        .{
            .tag = unicode.tag("fina"),
            .source_scoped = true,
            .auto_zwj = false,
        },
        .{
            .tag = unicode.tag("fin2"),
            .source_scoped = true,
            .auto_zwj = false,
        },
        .{
            .tag = unicode.tag("fin3"),
            .source_scoped = true,
            .auto_zwj = false,
        },
        .{
            .tag = unicode.tag("medi"),
            .source_scoped = true,
            .auto_zwj = false,
        },
        .{
            .tag = unicode.tag("med2"),
            .source_scoped = true,
            .auto_zwj = false,
        },
        .{
            .tag = unicode.tag("init"),
            .source_scoped = true,
            .auto_zwj = false,
        },
    };
    for (planned_features) |application| {
        if (input.lookup_options.script_tag != .phag and
            (application.tag == unicode.tag("ltrm") or
                application.tag == unicode.tag("rtlm")))
        {
            continue;
        }
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        applications_buf[application_count] = application;
        application_count += 1;
    }
    if (features.scriptPositionApplication(
        input.lookup_options.script_position,
    )) |application| {
        applications_buf[application_count] = application;
        application_count += 1;
    }
    try applyJoiningStages(
        input,
        applications_buf[0..application_count],
        joining_options,
    );
    try applyMongolianFeatures(input, joining_options);
    try applyArabicRequiredFeatures(input, joining_options);
    try applyFinalFeatures(input);

    return .{ .joining_features = input.source_features.items };
}

fn applyJoiningStages(
    input: Input,
    applications: []const gsub.feature.Application,
    joining_options: gsub.LookupOptions,
) !void {
    if (input.profile) |profile| {
        for (applications, 0..) |application, stage_index| {
            const stage_start = profileNow(input.profile_io);
            const lookup_count_before = profile.gsub_lookup_count;
            if (input.table_proved) {
                try font_shaping.applyGsubFeatureSequenceWithOptionsUsingGdefAfterProof(
                    input.font,
                    &.{application},
                    input.glyph_ids,
                    input.allocator,
                    joining_options,
                    input.gdef_metadata,
                );
            } else {
                try font_shaping.applyGsubFeatureSequenceWithOptionsUsingGdefForShaping(
                    input.font,
                    &.{application},
                    input.glyph_ids,
                    input.allocator,
                    joining_options,
                    input.gdef_metadata,
                );
            }
            if (stage_index < profile.arabic_stage_ns.len) {
                profile.arabic_stage_ns[stage_index] +=
                    profileElapsed(stage_start, input.profile_io);
                profile.arabic_stage_lookup_count[stage_index] +=
                    profile.gsub_lookup_count - lookup_count_before;
                profile.arabic_stage_count =
                    @max(profile.arabic_stage_count, stage_index + 1);
            }
        }
        return;
    }
    return executor.apply(
        input.font,
        input.context,
        input.table_proved,
        applications,
        input.glyph_ids,
        joining_options,
        input.gdef_metadata,
    );
}

fn applyMongolianFeatures(
    input: Input,
    joining_options: gsub.LookupOptions,
) !void {
    if (input.lookup_options.script_tag != .mong) return;
    var applications: [2]gsub.feature.Application = undefined;
    var count: usize = 0;
    for ([_]gsub.feature.Application{
        .{ .tag = unicode.tag("rlig"), .auto_zwj = false },
        .{ .tag = unicode.tag("calt"), .auto_zwj = false },
    }) |application| {
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        applications[count] = application;
        count += 1;
    }
    try executor.applyMergedAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        applications[0..count],
        input.glyph_ids,
        joining_options,
        input.gdef_metadata,
    );
}

fn applyArabicRequiredFeatures(
    input: Input,
    joining_options: gsub.LookupOptions,
) !void {
    if (input.lookup_options.script_tag != .arab) return;
    if (features.enabled(
        unicode.tag("rlig"),
        input.lookup_options.features,
        true,
    )) {
        try executor.applyAfterRunProof(
            input.font,
            input.context,
            input.table_proved,
            &.{.{ .tag = unicode.tag("rlig"), .auto_zwj = false }},
            input.glyph_ids,
            joining_options,
            input.gdef_metadata,
        );
    }
    var applications: [2]gsub.feature.Application = undefined;
    var count: usize = 0;
    for ([_]gsub.feature.Application{
        .{ .tag = unicode.tag("calt"), .auto_zwj = false },
        .{ .tag = unicode.tag("rclt"), .auto_zwj = false },
    }) |application| {
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        applications[count] = application;
        count += 1;
    }
    try executor.applyMergedAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        applications[0..count],
        input.glyph_ids,
        joining_options,
        input.gdef_metadata,
    );
}

fn applyFinalFeatures(input: Input) !void {
    var applications: [24]gsub.feature.Application = undefined;
    var count: usize = 0;
    for ([_]gsub.feature.Application{
        .{ .tag = unicode.tag("rlig"), .auto_zwj = false },
        .{ .tag = unicode.tag("calt"), .auto_zwj = false },
        .{ .tag = unicode.tag("rclt"), .auto_zwj = false },
        .{ .tag = unicode.tag("liga"), .auto_zwj = false },
        .{ .tag = unicode.tag("clig"), .auto_zwj = false },
    }) |application| {
        if (input.lookup_options.script_tag == .arab and
            (application.tag == unicode.tag("rlig") or
                application.tag == unicode.tag("calt") or
                application.tag == unicode.tag("rclt")))
        {
            continue;
        }
        if (input.lookup_options.script_tag == .mong and
            (application.tag == unicode.tag("rlig") or
                application.tag == unicode.tag("calt")))
        {
            continue;
        }
        if (!features.enabled(
            application.tag,
            input.lookup_options.features,
            true,
        )) continue;
        applications[count] = application;
        count += 1;
    }
    count += features.appendExplicitOptional(
        applications[count..],
        input.lookup_options.features,
    );
    try executor.applyMergedAfterRunProof(
        input.font,
        input.context,
        input.table_proved,
        applications[0..count],
        input.glyph_ids,
        input.base_gsub_options,
        input.gdef_metadata,
    );
}

fn profileNow(io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds;
}

fn profileElapsed(start: i128, io: ?std.Io) i128 {
    return std.Io.Clock.now(.awake, io.?).nanoseconds - start;
}
