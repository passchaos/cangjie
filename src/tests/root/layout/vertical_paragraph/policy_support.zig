//! Shared fixtures for vertical wrapping-policy tests.

const support = @import("../../support.zig");

pub const Font = support.Font;
pub const FontCascade = support.FontCascade;
pub const LayoutBuffer = support.LayoutBuffer;
pub const TextShaper = support.TextShaper;

pub fn layout(
    font: *const Font,
    buffer: *LayoutBuffer,
    text: []const u8,
    options: support.ParagraphOptions,
) !support.ParagraphLayout {
    return TextShaper.layoutParagraphUtf8(
        FontCascade.init(&.{font}),
        buffer,
        text,
        20,
        options,
    );
}
