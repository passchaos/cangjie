//! LigatureSubst matcher surface and accelerator lookup helpers.

const accelerator = @import("../../../accelerator/root.zig");
const accelerated = @import("matching/accelerated.zig");
const direct = @import("matching/direct.zig");
const GlyphId = @import("../../../../glyph.zig").GlyphId;

const Ligature = accelerator.model.LigatureSubstitution;
const LigatureSet = accelerator.model.LigatureSet;

pub const directMatch = direct.find;
pub const acceleratedMatch = accelerated.find;
pub const acceleratedPrefilteredMatch = accelerated.findPrefiltered;

pub fn setForGlyph(
    ligature: Ligature,
    glyph: GlyphId,
) ?LigatureSet {
    return accelerator.build.ligature.index.find(
        ligature.sets,
        ligature.set_slots,
        glyph,
    );
}

pub fn requiredSecondComponents(ligature: Ligature) []const GlyphId {
    return accelerator.build.ligature.requiredSecondComponents(ligature);
}
