//! Internal source-grapheme state shared by geometry construction stages.

const types = @import("types.zig");

pub const SourceOwner = struct {
    byte_start: usize,
    byte_end: usize,
    run_index: usize,
};

pub const Grapheme = struct {
    byte_start: usize,
    byte_len: usize,
    direction: types.Direction,
    run_index: ?usize,
    style_index: ?u32,
    inline_position: f32 = 0,
    inline_size: f32 = 0,
    positioned: bool = false,
    fontless: bool = false,
    authored_ligature_caret: bool = false,

    pub fn byteEnd(self: Grapheme) usize {
        return self.byte_start + self.byte_len;
    }
};

pub const IndexRange = struct {
    start: usize,
    end: usize,
};
