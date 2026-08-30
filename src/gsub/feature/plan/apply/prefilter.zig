//! Necessary-condition rejection for trusted cached-plan sidecars.
//!
//! This layer is intentionally narrower than lookup dispatch. A `false`
//! result is permitted only when the sidecar completely describes the
//! lookup's possible first inputs; every incomplete or unsupported sidecar
//! remains generic executor work.

const accelerator = @import("../../../accelerator/root.zig");
const GlyphDigest = @import("../../../../glyph_digest.zig").GlyphDigest;
const options = @import("../../../runtime/options.zig");
const runtime_prefilter = @import("../../../runtime/prefilter/root.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

pub const Cache = runtime_prefilter.Cache;
pub const Lookup = accelerator.Lookup;
pub const Options = options.Options;

/// Return whether a lookup whose plan/sidecar identity is already proved can
/// possibly have a first-input candidate in the current glyph stream.
pub inline fn mayMatch(
    sidecar: *const Lookup,
    glyphs: []const GlyphId,
    run: Options,
    cache: *Cache,
) bool {
    const candidate_digest = candidateDigest(sidecar) orelse return true;
    // Reusing a run digest across plan entries is sound only when every glyph
    // mutation advances the shared epoch. Production table construction
    // provisions that pointer for every digest-capable lookup; incomplete or
    // hand-built callers conservatively retain ordinary dispatch.
    if (run.glyph_mutation_generation == null) return true;
    const run_digest = cache.digestForRun(
        glyphs,
        sidecar.lookup_flag,
        run,
    );
    return !run_digest.isEmpty() and
        candidate_digest.mayIntersect(run_digest);
}

fn candidateDigest(
    sidecar: *const Lookup,
) ?GlyphDigest {
    const payload_type = if (sidecar.lookup_type == 7)
        sidecar.extension_lookup_type orelse return null
    else
        sidecar.lookup_type;

    switch (payload_type) {
        4 => {
            // The builder only records a complete LigatureSubst payload for a
            // single subtable. Requiring both payload data and a nonempty
            // digest distinguishes a proven empty candidate set from an
            // accelerator capability miss.
            if (sidecar.subtable_count != 1 or
                sidecar.ligature_subst.sets.len == 0 or
                sidecar.ligature_subst.first_component_digest.isEmpty())
            {
                return null;
            }
            return sidecar.ligature_subst.first_component_digest;
        },
        6 => {
            // Coverage-only direct and homogeneous extension lookups share
            // the same union of all first-input coverages. Class and mixed
            // contextual formats deliberately lack this completeness proof.
            if (!sidecar.chaining_coverage_only or
                sidecar.chaining_input_digest.isEmpty())
            {
                return null;
            }
            return sidecar.chaining_input_digest;
        },
        else => return null,
    }
}
