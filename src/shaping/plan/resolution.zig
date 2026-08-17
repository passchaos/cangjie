//! Resolve public shaping requests into homogeneous lookup properties.

const plan = @import("root.zig");
const pipeline_types = @import("../pipeline/types.zig");
const unicode = @import("../../unicode.zig");

pub fn forText(
    text: []const u8,
    options: plan.ShapeOptions,
) pipeline_types.ResolvedLookupOptions {
    const infer_language = options.language_tag == null;
    const inferred = if (infer_language)
        unicode.inferOpenTypeProperties(text)
    else
        undefined;
    const script = if (infer_language)
        inferred.script
    else
        unicode.inferOpenTypeScript(text);
    return .{
        .lookup = lookup(
            script,
            options,
            options.language_tag orelse inferred.language,
        ),
        .all_ascii = infer_language and inferred.all_ascii,
    };
}

pub fn forScriptRun(
    text: []const u8,
    script: unicode.Script,
    options: plan.ShapeOptions,
) pipeline_types.ResolvedLookupOptions {
    return .{
        .lookup = lookup(
            script,
            options,
            options.language_tag orelse
                unicode.inferOpenTypeLanguageTag(text),
        ),
        // Script itemization does not retain its ASCII proof. Keep this path
        // conservative rather than rescanning solely for one optimization bit.
        .all_ascii = false,
    };
}

fn lookup(
    script: unicode.Script,
    options: plan.ShapeOptions,
    language_tag: unicode.OpenTypeLanguageTag,
) pipeline_types.LookupOptions {
    return .{
        .script = script,
        .script_tag = options.script_tag orelse
            unicode.openTypeScriptTag(script),
        .script_tag_explicit = options.script_tag != null,
        .language_tag = language_tag,
        .direction = options.direction,
        .reorder_bidi = options.reorder_bidi,
        .native_direction_shaping = options.native_direction_shaping,
        .script_position = options.script_position,
        .features = options.features,
        .writing_mode = options.writing_mode,
        .text_orientation = options.text_orientation,
        .normalized_variation_coords = options.normalized_variation_coords,
        .not_found_variation_selector_glyph = options.not_found_variation_selector_glyph,
        .remove_default_ignorables = options.remove_default_ignorables,
        .context_before = options.context_before,
        .context_after = options.context_after,
        .beginning_of_text = options.beginning_of_text,
        .end_of_text = options.end_of_text,
        .cluster_level = options.cluster_level,
    };
}
