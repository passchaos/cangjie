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
pub const InstanceDescriptor = public.InstanceDescriptor;
pub const DescriptorResolveMode = public.DescriptorResolveMode;
pub const DescriptorResolveStatus = public.DescriptorResolveStatus;
pub const DescriptorResolution = public.DescriptorResolution;
pub const DescriptorCandidate = public.DescriptorCandidate;
pub const DescriptorDigest = public.DescriptorDigest;
pub const DescriptorResolver = public.DescriptorResolver;
pub const InstanceDescriptorCandidate = public.InstanceDescriptorCandidate;
pub const InstanceDescriptorResolver = public.InstanceDescriptorResolver;
pub const descriptor_wire_size = public.descriptor_wire_size;
pub const instance_descriptor_wire_size = public.instance_descriptor_wire_size;
pub const encodeDescriptor = public.encodeDescriptor;
pub const decodeDescriptor = public.decodeDescriptor;
pub const encodeInstanceDescriptor = public.encodeInstanceDescriptor;
pub const decodeInstanceDescriptor = public.decodeInstanceDescriptor;
pub const descriptorSourceDigest = public.descriptorSourceDigest;
pub const resolveDescriptorCandidates = public.resolveDescriptorCandidates;
pub const resolveInstanceDescriptorCandidates =
    public.resolveInstanceDescriptorCandidates;

pub const combinedSystemSourcesForOs = impl.combinedSystemFontSourcesForOs;
pub const defaultSystemSources = impl.defaultSystemFontSources;
pub const defaultSystemSourcesForOs = impl.defaultSystemFontSourcesForOs;
pub const manifestEntryMatchesBytes = impl.manifestEntryMatchesBytes;
pub const parseManifest = impl.parseManifest;
pub const readManifestFile = impl.readManifestFile;
pub const serializeManifest = impl.serializeManifest;
pub const userSourcesForOs = impl.userFontSourcesForOs;
pub const writeManifestFile = impl.writeManifestFile;
