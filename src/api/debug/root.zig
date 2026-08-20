//! Optional diagnostic dumps and paragraph overlay construction.

const std = @import("std");

const impl = @import("../../debug/root.zig");
const face_mod = @import("../../font/face/root.zig");
const shape_profile = @import("../../shape_profile.zig");

pub const OverlayKind = impl.OverlayKind;
pub const Overlay = impl.DebugOverlay;
pub const OverlayList = impl.DebugOverlayList;
pub const OverlayOptions = impl.OverlayOptions;
pub const ShapeProfile = shape_profile.ShapeStageProfile;

pub const buildOverlays = impl.buildDebugOverlays;
pub const dumpBidiMap = impl.dumpBidiMap;
pub const dumpBidiRuns = impl.dumpBidiRuns;
pub const dumpOverlays = impl.dumpDebugOverlays;
pub const dumpGlyphClusters = impl.dumpGlyphClusters;
pub const dumpHitTest = impl.dumpHitTest;
pub const dumpLineBreaks = impl.dumpLineBreaks;
pub const dumpParagraphLayout = impl.dumpParagraphLayout;
pub const dumpSelectionRects = impl.dumpSelectionRects;
pub const dumpShapeRuns = impl.dumpShapeRuns;
pub const dumpUnicodeSegmentation = impl.dumpUnicodeSegmentation;

pub fn dumpFontCoverage(
    writer: *std.Io.Writer,
    face: *const face_mod.Face,
    text: []const u8,
) !void {
    return impl.dumpFontCoverage(
        writer,
        face_mod.backend.font(face),
        text,
    );
}

pub fn dumpFontFallback(
    writer: *std.Io.Writer,
    cascade: face_mod.Cascade,
    text: []const u8,
) !void {
    return impl.dumpFontFallback(
        writer,
        .init(face_mod.backend.fonts(cascade.faces)),
        text,
    );
}

pub fn dumpMissingGlyphs(
    writer: *std.Io.Writer,
    cascade: face_mod.Cascade,
    text: []const u8,
) !void {
    return impl.dumpMissingGlyphs(
        writer,
        .init(face_mod.backend.fonts(cascade.faces)),
        text,
    );
}
