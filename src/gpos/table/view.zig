//! Bounds-checked view over one GPOS table range.

const bin = @import("../../binary.zig");

pub const Error = error{ BadGpos, EndOfStream };

pub const View = struct {
    data: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool = false,
    /// True only while font loading exhaustively validates the LookupList.
    ///
    /// Runtime contextual positioning must instead preflight nested lookups
    /// before it appends adjustments, because no outer validation walk exists.
    validating_full_lookup_list: bool = false,
    /// Optional maxp.numGlyphs proof used only by font-load validation.
    glyph_count: ?u16 = null,

    /// Return the declared table bytes after proving the range is representable
    /// inside the backing font data. Reads use this slice so a hostile absolute
    /// offset cannot overflow before the backing range is checked.
    pub fn bytes(self: View) Error![]const u8 {
        if (self.offset > self.data.len or
            self.length > self.data.len - self.offset)
        {
            return error.EndOfStream;
        }
        return self.data[self.offset .. self.offset + self.length];
    }

    /// Prove that a structural child range lies inside the declared GPOS table.
    ///
    /// Structural validation reports `BadGpos`; scalar reads retain
    /// `EndOfStream` so detached callers can distinguish truncated input.
    pub fn ensure(self: View, relative: usize, length: usize) Error!void {
        if (relative > self.length or length > self.length - relative) {
            return error.BadGpos;
        }
        _ = try self.bytes();
    }

    pub fn readU16(self: View, relative: usize) Error!u16 {
        const table = try self.bytes();
        if (relative > table.len or table.len - relative < 2) return error.EndOfStream;
        return bin.readU16At(table, relative) catch error.EndOfStream;
    }

    pub fn readI16(self: View, relative: usize) Error!i16 {
        const table = try self.bytes();
        if (relative > table.len or table.len - relative < 2) return error.EndOfStream;
        return bin.readI16At(table, relative) catch error.EndOfStream;
    }

    pub fn readU32(self: View, relative: usize) Error!u32 {
        const table = try self.bytes();
        if (relative > table.len or table.len - relative < 4) return error.EndOfStream;
        return bin.readU32At(table, relative) catch error.EndOfStream;
    }
};
