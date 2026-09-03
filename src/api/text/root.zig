//! Unicode analysis, OpenType properties, portable text records, and mutable
//! chunked UTF-8 document storage.
//!
//! Each subnamespace represents one coherent contract. This avoids making
//! unrelated bidi classes, style records, boundary iterators, and OpenType tags
//! compete in a single flat completion list.

pub const bidi = @import("bidi/root.zig");
pub const segmentation = @import("segmentation/root.zig");
pub const script = @import("script/root.zig");
pub const joining = @import("joining.zig");
pub const vertical = @import("vertical.zig");
pub const opentype = @import("opentype/root.zig");
pub const style = @import("style/root.zig");
pub const attributed = @import("attributed/root.zig");
pub const document = @import("document/root.zig");
pub const hyphenation = @import("../../text/hyphenation/root.zig");
