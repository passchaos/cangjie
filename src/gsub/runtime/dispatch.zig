//! GSUB lookup header dispatch and accelerator capability selection.
//!
//! Cached fields are trusted only for an exact validated table and lookup
//! identity. Concrete capability helpers operate on an already-proved sidecar
//! so lower executors cannot accidentally reselect foreign cached state.

const accelerator = @import("../accelerator/root.zig");
const options = @import("options.zig");
const table = @import("../table/root.zig");

pub const Error = table.view.Error;
pub const Lookup = accelerator.Lookup;
pub const MultipleSubstitution = accelerator.model.MultipleSubstitution;
pub const LigatureSubstitution = accelerator.model.LigatureSubstitution;
pub const Options = options.Options;
pub const SingleEntry = accelerator.model.SingleEntry;
pub const View = table.View;

pub const Header = struct {
    lookup_type: u16,
    lookup_flag: u16,
    subtable_count: u16,
    mark_filtering_set: ?u16,
};

/// Resolve one Lookup header after its fixed storage has been validated.
pub fn header(
    view: View,
    lookup_offset: usize,
    exact_sidecar: ?*const Lookup,
) Error!Header {
    if (exact_sidecar) |cached| {
        return .{
            .lookup_type = cached.lookup_type,
            .lookup_flag = cached.lookup_flag,
            .subtable_count = cached.subtable_count,
            .mark_filtering_set = cached.mark_filtering_set,
        };
    }

    const lookup_flag = try view.readU16(lookup_offset + 2);
    const subtable_count = try view.readU16(lookup_offset + 4);
    return .{
        .lookup_type = try view.readU16(lookup_offset),
        .lookup_flag = lookup_flag,
        .subtable_count = subtable_count,
        .mark_filtering_set = if ((lookup_flag & 0x0010) != 0)
            try view.readU16(
                lookup_offset + 6 + @as(usize, subtable_count) * 2,
            )
        else
            null,
    };
}

/// Return the complete accelerator slice only when it belongs to this exact
/// validated table range and still occupies its original allocation. This
/// proof is deliberately not represented by a caller-settable boolean.
pub inline fn exactSidecars(view: View, run: Options) ?[]const Lookup {
    if (!view.assume_validated) return null;
    const accelerators = run.lookup_accelerators orelse return null;
    _ = accelerator.feature_index.exact(
        view.data,
        view.offset,
        view.length,
        accelerators,
    ) orelse return null;
    return accelerators;
}

/// Index an accelerator slice whose table identity was proved at the caller's
/// boundary. This is intentionally distinct from `Options`: a copied public
/// option value cannot manufacture the proof represented by `accelerators`.
pub inline fn lookupInExactSidecars(
    accelerators: []const Lookup,
    lookup_offset: usize,
    lookup_index: ?u16,
) ?*const Lookup {
    const index = lookup_index orelse return null;
    if (index >= accelerators.len) return null;
    const cached = &accelerators[index];
    if (cached.lookup_offset != lookup_offset or cached.lookup_type == 0) {
        return null;
    }
    return cached;
}

/// Return one lookup only after proving both the table-wide sidecar identity
/// and its exact LookupList position.
pub inline fn exact(
    view: View,
    lookup_offset: usize,
    lookup_index: ?u16,
    run: Options,
) ?*const Lookup {
    const accelerators = exactSidecars(view, run) orelse return null;
    return lookupInExactSidecars(
        accelerators,
        lookup_offset,
        lookup_index,
    );
}

pub inline fn chainingCoverage(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (!lookup.chaining_coverage_only) return null;
    return lookup;
}

pub inline fn reverseChaining(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (lookup.reverse_chaining_subtables.len == 0 or
        lookup.reverse_chaining_groups.len == 0)
    {
        return null;
    }
    return lookup;
}

pub inline fn multiple(cached: ?*const Lookup) ?*const MultipleSubstitution {
    const lookup = cached orelse return null;
    if (lookup.multiple_subst.entries.len == 0) return null;
    return &lookup.multiple_subst;
}

pub inline fn singleEntries(cached: ?*const Lookup) ?[]const SingleEntry {
    const lookup = cached orelse return null;
    if (lookup.single_subst_entries.len == 0) return null;
    return lookup.single_subst_entries;
}

pub inline fn single(
    cached: ?*const Lookup,
) ?*const accelerator.model.SingleSubstitution {
    const lookup = cached orelse return null;
    if (!lookup.single_subst.enabled) return null;
    return &lookup.single_subst;
}

pub inline fn ligature(cached: ?*const Lookup) ?*const LigatureSubstitution {
    const lookup = cached orelse return null;
    if (lookup.ligature_subst.sets.len == 0) return null;
    return &lookup.ligature_subst;
}

pub inline fn contextClass(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (lookup.context_class_subtables.len == 0) return null;
    return lookup;
}

pub inline fn contextCoverage(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (lookup.context_coverage_subtables.len == 0) return null;
    return lookup;
}

pub inline fn chainingClass(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (lookup.chaining_class_subtables.len == 0) return null;
    return lookup;
}

pub inline fn chainingGlyph(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (lookup.chaining_glyph_subtables.len == 0 or
        lookup.chaining_glyph_subtables.len !=
            @as(usize, lookup.subtable_count))
    {
        return null;
    }
    return lookup;
}

pub inline fn extensionType(cached: ?*const Lookup) ?*const Lookup {
    const lookup = cached orelse return null;
    if (lookup.extension_lookup_type == null) return null;
    return lookup;
}

pub fn tableUsesRunDigestCache(lookups: ?[]const Lookup) bool {
    const items = lookups orelse return false;
    return items.len != 0 and items[0].table_uses_run_digest_cache;
}

pub fn matchesSourceSyllable(
    lookup_index: ?u16,
    run: Options,
) bool {
    if (run.match_source_syllable) return true;
    const lookups = run.match_source_syllable_lookups orelse return false;
    const index = lookup_index orelse return false;
    for (lookups) |candidate| {
        if (candidate == index) return true;
    }
    return false;
}

pub fn needsCustomizedOptions(
    lookup_flag: u16,
    scoped_syllable: bool,
    run: Options,
) bool {
    return (lookup_flag & 0x0010) != 0 or
        scoped_syllable != run.match_source_syllable;
}
