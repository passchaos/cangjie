//! Font discovery, matching, manifests, and fallback-cascade construction.

const public = @import("../../font/database/api.zig");
const impl = @import("../../font/database/root.zig");

pub const Database = public.Database;
pub const FaceInfo = public.FaceInfo;
pub const ManifestEntry = impl.FontManifestEntry;
pub const Query = impl.FontQuery;
pub const Source = impl.FontSource;
pub const Style = impl.FontStyle;
pub const Descriptor = public.Descriptor;
pub const DescriptorResolveMode = public.DescriptorResolveMode;
pub const DescriptorResolveStatus = public.DescriptorResolveStatus;
pub const DescriptorResolution = public.DescriptorResolution;
pub const DescriptorCandidate = public.DescriptorCandidate;
pub const DescriptorDigest = public.DescriptorDigest;
pub const descriptor_wire_size = public.descriptor_wire_size;
pub const encodeDescriptor = public.encodeDescriptor;
pub const decodeDescriptor = public.decodeDescriptor;
pub const descriptorSourceDigest = public.descriptorSourceDigest;
pub const resolveDescriptorCandidates = public.resolveDescriptorCandidates;

pub const combinedSystemSourcesForOs = impl.combinedSystemFontSourcesForOs;
pub const defaultSystemSources = impl.defaultSystemFontSources;
pub const defaultSystemSourcesForOs = impl.defaultSystemFontSourcesForOs;
pub const manifestEntryMatchesBytes = impl.manifestEntryMatchesBytes;
pub const parseManifest = impl.parseManifest;
pub const readManifestFile = impl.readManifestFile;
pub const serializeManifest = impl.serializeManifest;
pub const userSourcesForOs = impl.userFontSourcesForOs;
pub const writeManifestFile = impl.writeManifestFile;
