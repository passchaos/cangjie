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

pub fn apply(
    buffer: anytype,
    text: []const u8,
    options: anytype,
    recipe: anytype,
    needs_bidi_reorder: bool,
) !void {
    if (options.writing_mode.isVertical()) {
        // The admitted vertical subset has no bidi permutation, optical
        // punctuation, inline objects, or justification. Run pens still need
        // refreshing because paragraph letter/word spacing changed y advances
        // after the retained shaping snapshot was restored.
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
