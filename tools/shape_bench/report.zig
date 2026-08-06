const std = @import("std");

const options_mod = @import("options.zig");
const runner = @import("runner.zig");

pub fn print(options: options_mod.Options, result: runner.BenchResult) void {
    const ns_per_iter = divFloat(result.elapsed_ns, options.iterations);
    const ns_per_glyph = if (result.glyph_count == 0) 0 else divFloat(result.elapsed_ns, result.glyph_count);
    std.debug.print(
        \\engine={s}
        \\font={s}
        \\text_bytes={d}
        \\iterations={d}
        \\warmup={d}
        \\use_caches={any}
        \\profile={any}
        \\elapsed_ns={d}
        \\glyphs={d}
        \\ns_per_iter={d:.3}
        \\ns_per_glyph={d:.3}
        \\checksum={x}
        \\profile_cmap_ns={d}
        \\profile_gdef_ns={d}
        \\profile_gsub_ns={d}
        \\profile_gsub_select_ns={d}
        \\profile_gsub_apply_ns={d}
        \\profile_gpos_ns={d}
        \\profile_gpos_select_ns={d}
        \\profile_gpos_apply_ns={d}
        \\profile_position_ns={d}
        \\profile_glyphs={d}
        \\profile_gpos_lookups={d}
        \\profile_gpos_single_lookups={d}
        \\profile_gpos_pair_lookups={d}
        \\profile_gpos_mark_lookups={d}
        \\profile_gpos_context_lookups={d}
        \\profile_gpos_extension_lookups={d}
        \\
    , .{
        options.engine.label(),
        options.fontLabel(),
        options.text.len,
        options.iterations,
        options.warmup,
        options.use_caches,
        options.profile,
        result.elapsed_ns,
        result.glyph_count,
        ns_per_iter,
        ns_per_glyph,
        result.checksum,
        result.profile.cmap_ns,
        result.profile.gdef_ns,
        result.profile.gsub_ns,
        result.profile.gsub_select_ns,
        result.profile.gsub_apply_ns,
        result.profile.gpos_ns,
        result.profile.gpos_select_ns,
        result.profile.gpos_apply_ns,
        result.profile.position_ns,
        result.profile.glyph_count,
        result.profile.gpos_lookup_count,
        result.profile.gpos_single_lookup_count,
        result.profile.gpos_pair_lookup_count,
        result.profile.gpos_mark_lookup_count,
        result.profile.gpos_context_lookup_count,
        result.profile.gpos_extension_lookup_count,
    });
}

fn divFloat(numerator: i128, denominator: usize) f64 {
    if (denominator == 0) return 0;
    return @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}
