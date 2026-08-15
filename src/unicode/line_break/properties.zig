//! Generated Unicode 17 properties used by the UAX #14 rule engine.
//!
//! Keeping the packed-data decoder separate from iteration makes the runtime
//! boundary explicit: generators own the binary format, while the rule engine
//! consumes typed properties and does not depend on page-table details.

const std = @import("std");

const data = @embedFile("data.bin");

pub const unicode_version = std.SemanticVersion{
    .major = 17,
    .minor = 0,
    .patch = 0,
};

pub const BreakClass = enum(u6) {
    mandatory,
    carriage_return,
    line_feed,
    combining_mark,
    next_line,
    surrogate,
    word_joiner,
    zero_width_space,
    non_breaking_glue,
    space,
    zero_width_joiner,
    before_and_after,
    after,
    before,
    hyphen,
    contingent,
    close_punctuation,
    close_parenthesis,
    exclamation,
    inseparable,
    nonstarter,
    open_punctuation,
    quotation,
    infix_separator,
    numeric,
    postfix,
    prefix,
    symbol,
    ambiguous,
    alphabetic,
    conditional_japanese_starter,
    emoji_base,
    emoji_modifier,
    hangul_lv_syllable,
    hangul_lvt_syllable,
    hebrew_letter,
    ideographic,
    hangul_l_jamo,
    hangul_v_jamo,
    hangul_t_jamo,
    regional_indicator,
    complex_context,
    aksara,
    aksara_prebase,
    aksara_start,
    unambiguous_hyphen,
    virama_final,
    virama,
    unknown,
};

pub const GeneralCategory = enum(u3) {
    other,
    nonspacing_mark,
    spacing_mark,
    initial_punctuation,
    final_punctuation,
    unassigned,
};

pub const Properties = packed struct(u16) {
    class: BreakClass,
    category: GeneralCategory,
    east_asian: bool,
    extended_pictographic: bool,
    reserved: u5,
};

const Header = struct {
    index_count: usize,
    page_count: usize,
    index_offset: usize,
    pages_offset: usize,
};

const header = parseHeader();
const ascii_properties = buildAsciiProperties();

/// Looks up all UAX #14 inputs for one Unicode scalar.
///
/// ASCII is materialized at compile time because prose scanning requests these
/// properties far more often than any individual generated page.
pub inline fn lookup(codepoint: u21) Properties {
    if (codepoint < 0x80) return ascii_properties[codepoint];
    return lookupGenerated(codepoint);
}

pub inline fn lookupTriple(first: u8, second: u8, third: u8) Properties {
    std.debug.assert(first >= 0xe0 and first < 0xf0);
    std.debug.assert(second & 0xc0 == 0x80 and third & 0xc0 == 0x80);
    const codepoint = (@as(u21, first & 0x0f) << 12) |
        (@as(u21, second & 0x3f) << 6) |
        @as(u21, third & 0x3f);
    return lookupGenerated(codepoint);
}

/// Applies LB1 class resolution before context-sensitive rules run.
pub inline fn resolveClass(value: Properties) BreakClass {
    return switch (value.class) {
        .ambiguous, .surrogate, .unknown => .alphabetic,
        .complex_context => if (value.category == .nonspacing_mark or
            value.category == .spacing_mark)
            .combining_mark
        else
            .alphabetic,
        .conditional_japanese_starter => .nonstarter,
        else => |class| class,
    };
}

fn lookupGenerated(codepoint: u21) Properties {
    const page = @as(usize, codepoint) >> 8;
    const slot = readU16(header.index_offset + page * 2);
    const offset = header.pages_offset + @as(usize, slot) * 512 +
        (@as(usize, codepoint) & 0xff) * 2;
    return @bitCast(readU16(offset));
}

fn buildAsciiProperties() [128]Properties {
    var result: [128]Properties = undefined;
    for (&result, 0..) |*entry, codepoint| {
        entry.* = lookupGenerated(@intCast(codepoint));
    }
    return result;
}

fn parseHeader() Header {
    if (data.len < 12 or !std.mem.eql(u8, data[0..4], "CJL2") or
        data[4] != 2 or data[5] != 17 or data[6] != 0 or data[7] != 0)
    {
        @compileError("invalid Unicode line-break data");
    }
    const index_count = readU16(8);
    const page_count = readU16(10);
    const index_offset = 12;
    const pages_offset = index_offset + index_count * 2;
    if (index_count != 0x1100 or
        pages_offset + @as(usize, page_count) * 512 != data.len)
    {
        @compileError("invalid Unicode line-break data lengths");
    }
    return .{
        .index_count = index_count,
        .page_count = page_count,
        .index_offset = index_offset,
        .pages_offset = pages_offset,
    };
}

fn readU16(offset: usize) u16 {
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}
