//! Value types emitted by GPOS positioning.

pub const Adjustment = struct {
    index: usize,
    x_advance: i16 = 0,
    x_placement: i16 = 0,
    y_placement: i16 = 0,
    y_advance: i16 = 0,
    /// Parent cross-axis placement captured when a mark lookup applies.
    ///
    /// HarfBuzz resolves this part immediately so lookup order affects stacked
    /// marks, while the main-axis parent placement remains deferred until
    /// final attachment propagation. Keep it wider than OpenType value fields
    /// so a valid cursive chain cannot truncate the accumulated offset.
    attachment_cross_offset: i32 = 0,
    pair_positioned: bool = false,
    attachment_type: AttachmentType = .none,
    attachment_parent_index: ?usize = null,
    x_advance_absolute: bool = false,
    y_advance_absolute: bool = false,

    pub fn markAttachment(self: Adjustment) bool {
        return self.attachment_type == .mark;
    }

    pub fn attachmentParentIndex(self: Adjustment) ?usize {
        return self.attachment_parent_index;
    }
};

pub const AttachmentType = enum {
    none,
    mark,
    cursive,
};
