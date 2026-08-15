//! Compile-time contract for the intentionally small supported facade.

const std = @import("std");
const cangjie = @import("../../root.zig");

test "public facade uses domain names without legacy aliases" {
    try std.testing.expect(@hasDecl(cangjie, "Engine"));
    try std.testing.expect(@hasDecl(cangjie.font, "Face"));
    try std.testing.expect(@hasDecl(cangjie.font, "Cascade"));
    try std.testing.expect(@hasDecl(cangjie.font.container, "OwnedFace"));
    try std.testing.expect(@hasDecl(cangjie.shaping, "Glyph"));
    try std.testing.expect(@hasDecl(cangjie.text, "segmentation"));
    try std.testing.expect(@hasDecl(cangjie.font.metadata, "variations"));

    // The redesign deliberately carries no compatibility layer. These checks
    // make accidental reintroduction of redundant names a test failure instead
    // of allowing the facade to grow flat again.
    try std.testing.expect(!@hasDecl(cangjie.shaping, "Context"));
    try std.testing.expect(!@hasDecl(cangjie.font, "Font"));
    try std.testing.expect(!@hasDecl(cangjie.font.container, "LoadedFont"));
    try std.testing.expect(!@hasDecl(cangjie.shaping, "FontCascade"));
    try std.testing.expect(!@hasDecl(cangjie.shaping, "GlyphPosition"));
    try std.testing.expect(!@hasDecl(cangjie.text, "OpenTypeScript"));
    try std.testing.expect(
        !@hasDecl(cangjie.font.metadata, "VariationCoordinate"),
    );

    const Face = cangjie.font.Face;
    try std.testing.expect(!@hasDecl(Face, "applyGsub"));
    try std.testing.expect(!@hasDecl(Face, "collectGposAdjustments"));
    try std.testing.expect(!@hasDecl(Face, "LayoutScriptSelection"));
    try std.testing.expect(!@hasDecl(Face, "proveGsubTableForShaping"));
    try std.testing.expect(!@hasDecl(Face, "selectGsubLookupsForShaping"));
    try std.testing.expect(!@hasDecl(Face, "gdefLookupMetadataForShaping"));
    try std.testing.expect(!@hasDecl(Face, "glyphOutlineForRaster"));
    try std.testing.expect(
        !@hasDecl(Face, "resolvedSvgGlyphDocumentForRaster"),
    );
}
