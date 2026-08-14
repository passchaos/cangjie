const builtin = @import("builtin");

/// Dedicated executable section for narrow shaping helpers whose code-size
/// changes must not perturb the layout of unrelated hot functions in the main
/// text section. The names retain the original Indic-scanner spelling so
/// extending its use does not introduce another platform section or shift
/// existing Linux performance baselines.
pub const isolated_hotpaths = switch (builtin.object_format) {
    .elf => ".cangjie_indic_scanner",
    .macho => "__TEXT,__cangjie_indic",
    .coff => ".text$cangjie_indic",
    else => ".text",
};
