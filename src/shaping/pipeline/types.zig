//! Shared run properties passed between shaping pipeline stages.
//!
//! These types deliberately live below paragraph orchestration: source mapping, GSUB,
//! GPOS, and final output all consume the same resolved properties, and none
//! of those stages should need to import the paragraph/layout orchestrator.

const shaping_metadata = @import("../../shaping_metadata.zig");
const unicode = @import("../../unicode.zig");

pub const ClusterLevel = shaping_metadata.ClusterLevel;

pub const TextDirection = enum {
    ltr,
    rtl,
};

pub const WritingMode = enum {
    horizontal_tb,
    vertical_rl,
    vertical_lr,

    pub fn isVertical(self: WritingMode) bool {
        return self != .horizontal_tb;
    }
};

pub const TextOrientation = enum {
    mixed,
    upright,
    sideways,
};

pub const ScriptPosition = enum {
    normal,
    superscript,
    subscript,
};

/// Optional OpenType JSTF suggestion applied during one isolated line reshape.
pub const JstfMax = struct {
    /// Lookup offsets relative to the owning JSTF table.
    lookup_offsets: []const usize,
};

pub const JstfModifications = struct {
    /// Sorted LookupList indexes added to the active GSUB/GPOS plans.
    gsub_enable: []const u16 = &.{},
    /// Sorted LookupList indexes suppressed at top-level and nested dispatch.
    gsub_disable: []const u16 = &.{},
    gpos_enable: []const u16 = &.{},
    gpos_disable: []const u16 = &.{},
};

/// Fully resolved properties for one homogeneous shaping run.
///
/// Public `ShapeOptions` still carries optional script/language requests.
/// Itemization resolves those requests once into this record before any table
/// stage runs. The two run-content flags are populated by source decoding and
/// prevent native-direction reversal of numeric-only RTL-script runs.
pub const LookupOptions = struct {
    script: unicode.Script = .common,
    script_tag: unicode.OpenTypeScriptTag = .dflt,
    script_tag_explicit: bool = false,
    language_tag: unicode.OpenTypeLanguageTag = .dflt,
    direction: TextDirection = .ltr,
    reorder_bidi: bool = true,
    native_direction_shaping: bool = false,
    script_position: ScriptPosition = .normal,
    features: []const unicode.FeatureOverride = &.{},
    feature_ranges: []const unicode.GsubFeatureRange = &.{},
    writing_mode: WritingMode = .horizontal_tb,
    text_orientation: TextOrientation = .mixed,
    normalized_variation_coords: []const f32 = &.{},
    jstf_max: ?JstfMax = null,
    jstf_modifications: ?JstfModifications = null,
    not_found_variation_selector_glyph: ?u32 = null,
    remove_default_ignorables: bool = false,
    context_before: []const u8 = &.{},
    context_after: []const u8 = &.{},
    beginning_of_text: bool = false,
    end_of_text: bool = false,
    cluster_level: ?ClusterLevel = null,
    run_has_decimal_number: bool = false,
    run_has_letter: bool = false,

    /// Whether native-direction resolution needs source number/letter traits.
    /// Only LTR requests for an RTL script use the HarfBuzz-compatible rule
    /// that keeps number-only runs in logical order.
    pub fn needsRtlNumericDirectionGuard(self: LookupOptions) bool {
        if (!self.reorder_bidi and !self.native_direction_shaping) return false;
        if (self.writing_mode.isVertical() or self.direction != .ltr) {
            return false;
        }
        return self.nativeHorizontalDirection() == .rtl;
    }

    pub fn shouldShapeInNativeDirection(self: LookupOptions) bool {
        if (!self.reorder_bidi and !self.native_direction_shaping) return false;
        if (self.writing_mode.isVertical()) return false;
        const native_direction = textDirectionFromBidiClass(
            self.nativeHorizontalDirection() orelse return false,
        );
        if (self.direction == .ltr and
            native_direction == .rtl and
            self.run_has_decimal_number and
            !self.run_has_letter)
        {
            return false;
        }
        return self.direction != native_direction;
    }

    pub fn nativeHorizontalDirection(
        self: LookupOptions,
    ) ?unicode.BidiClass {
        // ScriptList negotiation may select DFLT/latn or a generation-specific
        // OpenType tag. Text direction remains a Unicode-script property, not
        // a property of whichever font table entry supplied lookups. An
        // explicit caller override is authoritative.
        const direction_tag = if (self.script_tag_explicit)
            self.script_tag
        else if (self.script != .common and
            self.script != .inherited and
            self.script != .unknown)
            unicode.openTypeScriptTag(self.script)
        else
            self.script_tag;
        return unicode.openTypeScriptHorizontalDirection(direction_tag);
    }

    /// Effective buffer direction seen by GPOS and output attachment logic.
    pub fn shapingDirection(self: LookupOptions) TextDirection {
        if (self.shouldShapeInNativeDirection()) {
            const native =
                self.nativeHorizontalDirection() orelse return self.direction;
            return textDirectionFromBidiClass(native);
        }
        return self.direction;
    }
};

pub const ResolvedLookupOptions = struct {
    lookup: LookupOptions,
    all_ascii: bool,
};

fn textDirectionFromBidiClass(direction: unicode.BidiClass) TextDirection {
    return if (direction == .rtl) .rtl else .ltr;
}

test "only LTR requests for RTL scripts need numeric direction traits" {
    try @import("std").testing.expect((LookupOptions{
        .script = .arabic,
    }).needsRtlNumericDirectionGuard());
    try @import("std").testing.expect(!(LookupOptions{
        .script = .devanagari,
    }).needsRtlNumericDirectionGuard());
    try @import("std").testing.expect(!(LookupOptions{
        .script = .arabic,
        .direction = .rtl,
    }).needsRtlNumericDirectionGuard());
}
