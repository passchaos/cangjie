//! Bounds-checked view over one GSUB table range.

const bin = @import("../../binary.zig");

pub const Error = error{ BadGsub, EndOfStream };

pub const View = struct {
    data: []const u8,
    offset: usize,
    length: usize,
    assume_validated: bool = false,
    /// Optional maxp.numGlyphs proof used only by font-load validation.
    glyph_count: ?u16 = null,
    /// Shaping can permit transient SingleSubst delta outputs which a later
    /// lookup maps back into the renderable maxp range.
    allow_transient_single_delta: bool = false,

    pub fn bytes(self: View) Error![]const u8 {
        if (self.offset > self.data.len or
            self.length > self.data.len - self.offset)
        {
            return error.EndOfStream;
        }
        return self.data[self.offset .. self.offset + self.length];
    }

    pub fn ensure(self: View, relative: usize, length: usize) Error!void {
        if (relative > self.length or length > self.length - relative) {
            return error.BadGsub;
        }
    }

    pub fn readU16(self: View, relative: usize) Error!u16 {
        const table = try self.bytes();
        if (relative > table.len or table.len - relative < 2) return error.EndOfStream;
        return bin.readU16At(
            table,
            relative,
        ) catch error.EndOfStream;
    }

    pub fn readI16(self: View, relative: usize) Error!i16 {
        const table = try self.bytes();
        if (relative > table.len or table.len - relative < 2) return error.EndOfStream;
        return bin.readI16At(
            table,
            relative,
        ) catch error.EndOfStream;
    }

    pub fn readU32(self: View, relative: usize) Error!u32 {
        const table = try self.bytes();
        if (relative > table.len or table.len - relative < 4) return error.EndOfStream;
        return bin.readU32At(
            table,
            relative,
        ) catch error.EndOfStream;
    }

    pub fn readF2Dot14(self: View, relative: usize) Error!f32 {
        return @as(f32, @floatFromInt(try self.readI16(relative))) / 16384.0;
    }
};
