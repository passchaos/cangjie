const std = @import("std");

const options_mod = @import("options.zig");
const runner = @import("runner.zig");

pub fn print(options: options_mod.Options, result: runner.BenchResult) void {
    const ns_per_iter = divFloat(result.elapsed_ns, options.iterations);
    const ns_per_glyph = if (result.glyph_count == 0) 0 else divFloat(result.elapsed_ns, result.glyph_count);
    const stats = sampleStats(result.samples);
    std.debug.print(
        \\engine={s}
        \\font={s}
        \\text={s}
        \\text_bytes={d}
        \\iterations={d}
        \\warmup={d}
        \\samples={d}
        \\feature_overrides={d}
        \\variation_coords={d}
        \\use_caches={any}
        \\use_shaped_cache={any}
        \\profile={any}
        \\elapsed_ns={d}
        \\glyphs={d}
        \\ns_per_iter={d:.3}
        \\ns_per_glyph={d:.3}
        \\sample_min_ns_per_glyph={d:.3}
        \\sample_median_ns_per_glyph={d:.3}
        \\sample_max_ns_per_glyph={d:.3}
        \\checksum={x}
        \\
    , .{
        options.engine.label(),
        options.fontLabel(),
        options.textLabel(),
        options.text.len,
        options.iterations,
        options.warmup,
        options.samples,
        options.featureOverrideCount(),
        options.normalizedVariationCoords().len,
        options.use_caches,
        options.use_shaped_cache,
        options.profile,
        result.elapsed_ns,
        result.glyph_count,
        ns_per_iter,
        ns_per_glyph,
        stats.min,
        stats.median,
        stats.max,
        result.checksum,
    });
    std.debug.print(
        \\glyph_index_cache_hits={d}
        \\glyph_index_cache_misses={d}
        \\glyph_metrics_cache_hits={d}
        \\glyph_metrics_cache_misses={d}
        \\gdef_cache_hits={d}
        \\gdef_cache_misses={d}
        \\gsub_proof_cache_hits={d}
        \\gsub_proof_cache_misses={d}
        \\gpos_proof_cache_hits={d}
        \\gpos_proof_cache_misses={d}
        \\lookup_selection_cache_hits={d}
        \\lookup_selection_cache_misses={d}
        \\shaped_cache_hits={d}
        \\shaped_cache_misses={d}
        \\
    , .{
        result.glyph_index_cache_hits,
        result.glyph_index_cache_misses,
        result.glyph_metrics_cache_hits,
        result.glyph_metrics_cache_misses,
        result.gdef_cache_hits,
        result.gdef_cache_misses,
        result.gsub_proof_cache_hits,
        result.gsub_proof_cache_misses,
        result.gpos_proof_cache_hits,
        result.gpos_proof_cache_misses,
        result.lookup_selection_cache_hits,
        result.lookup_selection_cache_misses,
        result.shaped_cache_hits,
        result.shaped_cache_misses,
    });
    for (options.featureOverrides(), 0..) |feature, index| {
        var tag_buf: [4]u8 = undefined;
        options_mod.writeFeatureTag(&tag_buf, feature.tag);
        std.debug.print(
            \\feature_override index={d} tag={s} enabled={any}
            \\
        , .{
            index,
            tag_buf[0..],
            feature.enabled,
        });
    }
    std.debug.print(
        \\
        \\profile_total_ns={d}
        \\profile_validate_ns={d}
        \\profile_options_ns={d}
        \\profile_cmap_ns={d}
        \\profile_gdef_ns={d}
        \\profile_gsub_ns={d}
        \\profile_gsub_select_ns={d}
        \\profile_gsub_apply_ns={d}
        \\profile_gpos_ns={d}
        \\profile_gpos_select_ns={d}
        \\profile_gpos_apply_ns={d}
        \\profile_position_ns={d}
        \\profile_bidi_ns={d}
        \\profile_glyphs={d}
        \\profile_gsub_lookups={d}
        \\profile_gsub_single_lookups={d}
        \\profile_gsub_multiple_lookups={d}
        \\profile_gsub_alternate_lookups={d}
        \\profile_gsub_ligature_lookups={d}
        \\profile_gsub_context_lookups={d}
        \\profile_gsub_extension_lookups={d}
        \\profile_gpos_lookups={d}
        \\profile_gpos_single_lookups={d}
        \\profile_gpos_pair_lookups={d}
        \\profile_gpos_mark_lookups={d}
        \\profile_gpos_context_lookups={d}
        \\profile_gpos_extension_lookups={d}
        \\
    , .{
        result.profile.total_ns,
        result.profile.validate_ns,
        result.profile.options_ns,
        result.profile.cmap_ns,
        result.profile.gdef_ns,
        result.profile.gsub_ns,
        result.profile.gsub_select_ns,
        result.profile.gsub_apply_ns,
        result.profile.gpos_ns,
        result.profile.gpos_select_ns,
        result.profile.gpos_apply_ns,
        result.profile.position_ns,
        result.profile.bidi_ns,
        result.profile.glyph_count,
        result.profile.gsub_lookup_count,
        result.profile.gsub_single_lookup_count,
        result.profile.gsub_multiple_lookup_count,
        result.profile.gsub_alternate_lookup_count,
        result.profile.gsub_ligature_lookup_count,
        result.profile.gsub_context_lookup_count,
        result.profile.gsub_extension_lookup_count,
        result.profile.gpos_lookup_count,
        result.profile.gpos_single_lookup_count,
        result.profile.gpos_pair_lookup_count,
        result.profile.gpos_mark_lookup_count,
        result.profile.gpos_context_lookup_count,
        result.profile.gpos_extension_lookup_count,
    });
    for (0..result.profile.arabic_stage_count) |stage_index| {
        std.debug.print(
            \\profile_arabic_stage index={d} ns={d} lookups={d}
            \\
        , .{
            stage_index,
            result.profile.arabic_stage_ns[stage_index],
            result.profile.arabic_stage_lookup_count[stage_index],
        });
    }
    for (result.profile.gsub_lookup_entries[0..result.profile.gsub_lookup_entry_count]) |entry| {
        std.debug.print(
            \\profile_gsub_lookup index={d} ns={d} count={d} glyphs_before={d} glyphs_after={d} last_delta={d} hash_before={x} hash_after={x} first_diff={d}
            \\
        , .{
            entry.lookup_index,
            entry.elapsed_ns,
            entry.count,
            entry.glyphs_before_sum,
            entry.glyphs_after_sum,
            entry.last_glyph_delta,
            entry.last_hash_before,
            entry.last_hash_after,
            entry.last_first_diff,
        });
        if (entry.last_hash_before != entry.last_hash_after and entry.window_len != 0) {
            std.debug.print(
                \\profile_gsub_lookup_window index={d} start={d} before=
            , .{ entry.lookup_index, entry.window_start });
            printU16Array(entry.glyphs_before_window[0..entry.window_len]);
            std.debug.print(" after=", .{});
            printU16Array(entry.glyphs_after_window[0..entry.window_len]);
            std.debug.print("\n", .{});
        }
    }
    for (result.profile.gpos_lookup_entries[0..result.profile.gpos_lookup_entry_count]) |entry| {
        std.debug.print(
            \\profile_gpos_lookup index={d} ns={d} count={d}
            \\
        , .{
            entry.lookup_index,
            entry.elapsed_ns,
            entry.count,
        });
    }
    for (result.samples) |sample| {
        const sample_ns_per_glyph = if (sample.glyph_count == 0) 0 else divFloat(sample.elapsed_ns, sample.glyph_count);
        std.debug.print(
            \\sample index={d} elapsed_ns={d} glyphs={d} ns_per_glyph={d:.3} checksum={x}
            \\
        , .{
            sample.index,
            sample.elapsed_ns,
            sample.glyph_count,
            sample_ns_per_glyph,
            sample.checksum,
        });
    }
    for (result.line_summaries) |summary| {
        std.debug.print(
            \\line_summary index={d} text_bytes={d} glyphs={d} checksum={x}
        , .{
            summary.index,
            summary.text_bytes,
            summary.glyph_count,
            summary.checksum,
        });
        if (summary.glyph_ids.len != 0) {
            std.debug.print(" glyph_ids=", .{});
            for (summary.glyph_ids, 0..) |glyph_id, index| {
                if (index != 0) std.debug.print(",", .{});
                std.debug.print("{d}", .{glyph_id});
            }
        }
        if (summary.clusters.len != 0) {
            std.debug.print(" clusters=", .{});
            for (summary.clusters, 0..) |cluster, index| {
                if (index != 0) std.debug.print(",", .{});
                std.debug.print("{d}", .{cluster});
            }
        }
        printI32Array(" x_advances", summary.x_advances);
        printI32Array(" y_advances", summary.y_advances);
        printI32Array(" x_offsets", summary.x_offsets);
        printI32Array(" y_offsets", summary.y_offsets);
        std.debug.print("\n", .{});
    }
}

fn printI32Array(label: []const u8, values: []const i32) void {
    if (values.len == 0) return;
    std.debug.print("{s}=", .{label});
    for (values, 0..) |value, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{value});
    }
}

fn printU16Array(values: []const u16) void {
    for (values, 0..) |value, index| {
        if (index != 0) std.debug.print(",", .{});
        std.debug.print("{d}", .{value});
    }
}

fn divFloat(numerator: i128, denominator: usize) f64 {
    if (denominator == 0) return 0;
    return @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}

const SampleStats = struct {
    min: f64 = 0,
    median: f64 = 0,
    max: f64 = 0,
};

fn sampleStats(samples: []const runner.BenchResult.Sample) SampleStats {
    if (samples.len == 0) return .{};
    var values_buf: [64]f64 = undefined;
    const count = @min(samples.len, values_buf.len);
    for (samples[0..count], values_buf[0..count]) |sample, *value| {
        value.* = if (sample.glyph_count == 0) 0 else divFloat(sample.elapsed_ns, sample.glyph_count);
    }
    std.sort.heap(f64, values_buf[0..count], {}, floatLessThan);
    return .{
        .min = values_buf[0],
        .median = values_buf[count / 2],
        .max = values_buf[count - 1],
    };
}

fn floatLessThan(_: void, lhs: f64, rhs: f64) bool {
    return lhs < rhs;
}
