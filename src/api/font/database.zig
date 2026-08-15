//! Font discovery, matching, manifests, and fallback-cascade construction.

const impl = @import("../../database.zig");

pub const Database = impl.FontDatabase;
pub const FaceInfo = impl.FontFaceInfo;
pub const ManifestEntry = impl.FontManifestEntry;
pub const Query = impl.FontQuery;
pub const Source = impl.FontSource;
pub const Style = impl.FontStyle;

pub const combinedSystemSourcesForOs = impl.combinedSystemFontSourcesForOs;
pub const defaultSystemSources = impl.defaultSystemFontSources;
pub const defaultSystemSourcesForOs = impl.defaultSystemFontSourcesForOs;
pub const manifestEntryMatchesBytes = impl.manifestEntryMatchesBytes;
pub const parseManifest = impl.parseManifest;
pub const readManifestFile = impl.readManifestFile;
pub const serializeManifest = impl.serializeManifest;
pub const userSourcesForOs = impl.userFontSourcesForOs;
pub const writeManifestFile = impl.writeManifestFile;
