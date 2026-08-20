//! Font discovery, matching, manifests, and fallback-cascade construction.

const public = @import("../../font/database/api.zig");
const impl = @import("../../font/database/root.zig");

pub const Database = public.Database;
pub const FaceInfo = public.FaceInfo;
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
