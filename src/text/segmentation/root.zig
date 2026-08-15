//! Public, opt-in segmentation tailoring.
//!
//! Default UAX #14 line breaking remains data-driven and language-neutral.
//! Tailorings live under this module so paragraph APIs do not expose their
//! internal trie and dynamic-programming implementation.

pub const WordBreakDictionary =
    @import("dictionary.zig").WordBreakDictionary;
