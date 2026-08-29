//! Final presentation over completely selected retained paragraph lines.
//!
//! The greedy breaker intentionally commits logical source-order lines. These
//! transformations run only after every line is known because justification
//! can reshape glyph ranges and bidi permutes the shared glyph/run arrays.
//! Keeping the sequence here gives one-shot retained layout and incremental
//! breaking an identical completion boundary.

const bidi_reorder = @import("../../bidi/reorder/root.zig");
const inline_object = @import("../../inline_object/root.zig");
const font_expansion = @import("../../justification/font_expansion.zig");
const jstf_justification = @import("../../justification/jstf.zig");
const jstf_extender = @import("../../justification/jstf/extender.zig");
const kashida_justification = @import("../../justification/kashida.zig");
const paragraph_reflow = @import("../../line_break/reflow/root.zig");
const punctuation_compression = @import("../../punctuation/compression.zig");
const punctuation_hanging = @import("../../punctuation/hanging.zig");
const vertical_hanging = @import("../vertical_hanging.zig");
const vertical_justification = @import("../vertical_justification.zig");
const unicode = @import("../../../unicode.zig");

/// Finish the subset of presentation reachable from the simple retained
/// reflow proof. All disabled features were checked before line construction,
/// so this avoids repeatedly entering no-op justification, punctuation, and
/// object-placement passes.
pub fn applySimpleRetained(
    buffer: anytype,
    options: anytype,
    needs_bidi_reorder: bool,
    pure_rtl_lines: bool,
    pure_rtl_may_have_mirroring: bool,
    bidi_paragraph: ?unicode.BidiParagraph,
) !void {
    if (needs_bidi_reorder) {
        if (pure_rtl_lines and !pure_rtl_may_have_mirroring and
            (bidi_reorder.applyPureRtlLinesWithoutMirroringAfterProof(buffer) or
                try bidi_reorder.applyPureRtlLinesWithObjectWithoutMirroringAfterProof(buffer)))
        {} else if (pure_rtl_lines and
            (bidi_reorder.applyPureRtlLinesAfterProof(buffer) or
                try bidi_reorder.applyPureRtlLinesWithObjectAfterProof(buffer)))
        {} else if (bidi_paragraph) |paragraph|
            try bidi_reorder.applyLinesResolved(buffer, paragraph)
        else
            unreachable;
        // Visual permutation changes which glyph ranges each retained run
        // owns. Rebuild their absolute pens only in that case; the LTR simple
        // path restored already-correct immutable run offsets and changed no
        // advances, spacing, tabs, justification, or punctuation.
        bidi_reorder.recomputeRunOffsets(buffer);
    }
    // The strict builder already accumulated RTL widths in final visual order.
    // Hanging is excluded by its option proof, so no post-permutation line
    // scan is needed here.
    // The proof keeps run ownership fixed. Only absolute pens change after
    // line-local permutation; no run rebuilding is needed.
    if (options.inline_objects.len == 1 and
        (options.inline_objects[0].kind != .custom_out_of_flow or
            options.out_of_flow_placements.len == 1))
    {
        if (options.inline_objects[0].kind == .custom_out_of_flow)
            inline_object.positionSingleResolvedRetained(
                buffer,
                options.inline_objects[0],
                options.out_of_flow_placements[0],
                options.writing_mode,
            )
        else
            inline_object.positionSingleRetained(
                buffer,
                options.inline_objects[0],
                options.writing_mode,
            );
    } else {
        try inline_object.position(
            buffer,
            options.inline_objects,
            options.out_of_flow_placements,
            options.writing_mode,
        );
    }
}

pub fn apply(
    buffer: anytype,
    text: []const u8,
    options: anytype,
    recipe: anytype,
    needs_bidi_reorder: bool,
    pure_rtl_lines: bool,
    bidi_paragraph: ?unicode.BidiParagraph,
) !void {
    if (options.writing_mode.isVertical()) {
        // Vertical column construction has already applied line limits,
        // ellipsis, alignment, tabs, and object block metrics. Apply UAX #9 to
        // each final column before rebuilding run pens and positioned objects;
        // Generic inline-axis justification and punctuation compression are
        // applied in logical order before bidi, exactly like horizontal lines.
        vertical_justification.apply(buffer, options);
        try punctuation_compression.apply(buffer, options);
        if (needs_bidi_reorder) {
            if (pure_rtl_lines and
                bidi_reorder.applyPureRtlLinesAfterProof(buffer))
            {} else if (bidi_paragraph) |paragraph|
                try bidi_reorder.applyLinesResolved(buffer, paragraph)
            else
                try bidi_reorder.applyLines(
                    buffer,
                    text,
                    options.direction == .rtl,
                );
        }
        vertical_hanging.apply(buffer, options);
        bidi_reorder.recomputeRunOffsets(buffer);
        try inline_object.position(
            buffer,
            options.inline_objects,
            options.out_of_flow_placements,
            options.writing_mode,
        );
        return;
    }
    try jstf_justification.apply(buffer, options, recipe);
    try jstf_extender.apply(buffer, text, options, recipe);
    try font_expansion.apply(buffer, options, recipe);
    try kashida_justification.apply(buffer, text, options, recipe);
    paragraph_reflow.applyPendingJustification(buffer);
    try punctuation_compression.apply(buffer, options);
    if (needs_bidi_reorder) {
        if (pure_rtl_lines and
            bidi_reorder.applyPureRtlLinesAfterProof(buffer))
        {} else if (bidi_paragraph) |paragraph|
            try bidi_reorder.applyLinesResolved(buffer, paragraph)
        else
            try bidi_reorder.applyLines(
                buffer,
                text,
                options.direction == .rtl,
            );
    }
    punctuation_hanging.apply(buffer, options);
    bidi_reorder.recomputeRunOffsets(buffer);
    try inline_object.position(
        buffer,
        options.inline_objects,
        options.out_of_flow_placements,
        options.writing_mode,
    );
}
