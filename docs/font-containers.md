# Modern Font Container Support

Cangjie deliberately targets the containers used by current desktop, mobile,
and web fonts rather than FreeType's complete historical format matrix.

## Supported Input

- Standalone TrueType and OpenType SFNT (`.ttf`, `.otf`), including TrueType,
  CFF1, and CFF2 outlines.
- TrueType/OpenType collections (`.ttc`, `.otc`).
- Apple data-fork resource containers (`.dfont`) carrying one or more `sfnt`
  resources. Multiple resources are exposed in resource-map/QuickDraw order.
- WOFF 1.0 (`.woff`) through the built-in bounded zlib decoder.
- WOFF 2.0 (`.woff2`) through a runtime `libwoff2dec` backend. Platforms
  without a compatible backend return `error.Woff2RuntimeUnavailable` rather
  than treating compressed bytes as an SFNT.

Type 1 PFA/PFB, legacy standalone CID containers, BDF/PCF, PFR, Windows FNT,
and similarly uncommon historical formats are intentionally out of scope.
That exclusion does **not** include CID-keyed CFF1 inside modern OpenType,
TTC/OTC, web fonts, or current color-font formats.

## Ownership And Limits

`cangjie.font.Font.parse` and `parseFace` are zero-copy APIs: a `Font` borrows
the caller's SFNT bytes. Compressed containers and DFONT resources require
newly reconstructed bytes, so `cangjie.font.container.LoadedFont` owns both the
decoded allocation and the `Font` borrowing it. Destroying `LoadedFont`
deinitializes the parser before releasing those bytes.

`cangjie.font.container.decodeAlloc` always returns owned bytes, including a
copy for plain SFNT/TTC input. Its size limit applies to the decoded output and
therefore bounds WOFF expansion and DFONT-to-SFNT/TTC reconstruction.
Convenience database loaders use a conservative 64 MiB default; callers
loading a trusted larger collection can use the explicit `*WithLimit` APIs.

`cangjie.font.database.Database` decodes containers before parsing and fallback
discovery. It:

- scans `.woff`, `.woff2`, and `.dfont` beside `.ttf`, `.otf`, `.ttc`, and
  `.otc`;
- discovers every face in WOFF2 and DFONT collections;
- deduplicates decoded SFNT bytes with hash prefiltering plus exact comparison;
- retains the original container hash and byte length in manifests, so a cache
  detects replacement of a WOFF source rather than only its decoded form.

## Validation

The DFONT decoder validates disjoint resource data/map ranges, map-header
identity, bounded type/reference/name lists, 24-bit data offsets, resource
length prefixes, and every embedded SFNT table range. One resource is copied as
a standalone SFNT; multiple resources are rebuilt as a TTC with absolute table
offsets.

The WOFF1 decoder enforces the format's structural `MUST` conditions: a
strictly tag-sorted directory, printable tags, bounded and aligned payloads,
non-overlapping tightly packed tables, correctly placed metadata/private
blocks, exact reconstructed size, and exact zlib consumption. Reconstruction
preserves physical table order so the SFNT-wide `head.checkSumAdjustment`
remains meaningful. The normal `Font` parser then validates reconstructed table
maps, checksums, and supported OpenType table grammars.

Tests cover single/multi-face DFONT reconstruction, malformed resource maps,
compressed and uncompressed WOFF1 tables, malformed ranges, physical-order
reconstruction, decoded-size limits, ownership, database scanning/manifests, a
fixed transformed-glyf WOFF2 fixture, and optional installed real fonts.
Current real-font probes include HarfBuzz's retained `DFONT.dfont`, MathJax
WOFF1, Annapurna SIL WOFF1/WOFF2, and a variable General Sans WOFF2.

## Performance Scope

Container decoding is a load-time cost, not a shaping hot path. Representative
local probes measured roughly 0.31 ms for a 34 KiB MathJax WOFF1 and 1.2--1.3
ms for a 38 KiB variable General Sans WOFF2, including reconstruction and
parse. Already-decoded SFNT copy-and-parse was substantially cheaper. These
figures establish practical startup cost only; they are not a claim of
load-time superiority over FreeType or Fontations.
