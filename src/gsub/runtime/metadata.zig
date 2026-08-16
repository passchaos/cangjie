//! GSUB run metadata cardinality and source-domain validation.

const feature = @import("../feature/root.zig");
const options = @import("options.zig");

pub const Error = error{InvalidShapingInput};
pub const Options = options.Options;

pub fn validate(run: Options, glyph_count: usize) Error!void {
    return validateRequirements(
        run,
        glyph_count,
        run.active_source_feature != null or
            run.active_source_feature_mask != 0,
        run.match_source_syllable or
            run.match_source_syllable_lookups != null,
    );
}

pub fn validateApplications(
    run: Options,
    glyph_count: usize,
    applications: []const feature.Application,
) Error!void {
    var require_source_features =
        run.active_source_feature != null or
        run.active_source_feature_mask != 0;
    var require_source_syllables =
        run.match_source_syllable or
        run.match_source_syllable_lookups != null;
    for (applications) |application| {
        require_source_features =
            require_source_features or application.source_scoped;
        require_source_syllables =
            require_source_syllables or application.match_source_syllable;
    }
    return validateRequirements(
        run,
        glyph_count,
        require_source_features,
        require_source_syllables,
    );
}

pub fn validateLookupPlan(
    run: Options,
    glyph_count: usize,
    plan: feature.LookupPlan,
) Error!void {
    var require_source_features =
        run.active_source_feature != null or
        run.active_source_feature_mask != 0;
    var require_source_syllables =
        run.match_source_syllable or
        run.match_source_syllable_lookups != null;
    for (plan.entries) |entry| {
        require_source_features =
            require_source_features or entry.application.source_scoped;
        require_source_syllables =
            require_source_syllables or
            entry.application.match_source_syllable;
    }
    return validateRequirements(
        run,
        glyph_count,
        require_source_features,
        require_source_syllables,
    );
}

pub fn validateMergedLookupPlan(
    run: Options,
    glyph_count: usize,
    plan: feature.MergedLookupPlan,
) Error!void {
    var require_source_features =
        run.active_source_feature != null or
        run.active_source_feature_mask != 0;
    var require_source_syllables =
        run.match_source_syllable or
        run.match_source_syllable_lookups != null;
    for (plan.lookups) |lookup| {
        require_source_features =
            require_source_features or lookup.source_mask != 0;
        require_source_syllables =
            require_source_syllables or lookup.match_source_syllable;
    }
    return validateRequirements(
        run,
        glyph_count,
        require_source_features,
        require_source_syllables,
    );
}

/// Prove the maximal source metadata contract for a multi-stage script shaper.
///
/// Every supported substitution preserves these cardinalities atomically, so
/// later stages can use after-proof entry points without rescanning the run.
pub fn validateScriptShaper(run: Options, glyph_count: usize) Error!void {
    return validateRequirements(
        run,
        glyph_count,
        run.source_features != null,
        run.source_syllables != null,
    );
}

fn validateRequirements(
    run: Options,
    glyph_count: usize,
    require_source_features: bool,
    require_source_syllables: bool,
) Error!void {
    if (run.glyph_source_indices) |sources| {
        if (sources.items.len != glyph_count) {
            return error.InvalidShapingInput;
        }
    }
    if (run.glyph_cluster_indices) |clusters| {
        if (clusters.items.len != glyph_count) {
            return error.InvalidShapingInput;
        }
    }
    if (run.glyph_substituted) |substituted| {
        if (substituted.items.len != glyph_count) {
            return error.InvalidShapingInput;
        }
    }
    if (run.glyph_stage_substituted) |substituted| {
        if (substituted.items.len != glyph_count) {
            return error.InvalidShapingInput;
        }
    }
    if (run.ligature_components) |store| {
        if (store.infos.items.len != glyph_count or !store.isValid()) {
            return error.InvalidShapingInput;
        }
    }
    if (!require_source_features and
        !require_source_syllables and
        run.source_codepoints == null)
    {
        return;
    }

    const sources =
        run.glyph_source_indices orelse return error.InvalidShapingInput;
    const features = if (require_source_features)
        run.source_features orelse return error.InvalidShapingInput
    else
        &.{};
    const syllables = if (require_source_syllables)
        run.source_syllables orelse return error.InvalidShapingInput
    else
        &.{};
    for (sources.items) |source| {
        if (require_source_features and source >= features.len) {
            return error.InvalidShapingInput;
        }
        if (require_source_syllables and source >= syllables.len) {
            return error.InvalidShapingInput;
        }
        if (run.source_codepoints) |codepoints| {
            if (source >= codepoints.len) return error.InvalidShapingInput;
        }
    }
}
