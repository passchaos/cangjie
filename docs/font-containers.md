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

`cangjie.font.Face.parse` and `parseIndex` are zero-copy APIs: a `Face` borrows
the caller's SFNT bytes. Both return a concrete parsed-face value; use
`properties()`, `glyphs()`, `metrics()`, `names()`, `variations()`, and
`color()` rather than depending on parser table records. Compressed containers
and DFONT resources require
newly reconstructed bytes, so `cangjie.font.container.OwnedFace` owns both the
decoded allocation and the `Face` borrowing it. Destroying `OwnedFace`
deinitializes the parser before releasing those bytes.

`Face.glyphs().outline` is the defensive one-shot outline API: it revalidates
borrowed table checksums so post-parse source mutation fails explicitly. For
trusted immutable bytes and repeated atlas/path construction,
`Face.glyphs().session()` returns a lightweight borrowed `GlyphSession` that
reuses the whole-face grammar/checksum proof established by `Face.parse`. The
face and its source bytes must outlive the session and must remain unchanged;
returned outlines remain allocator-owned exactly like one-shot output.

`cangjie.font.container.decodeAlloc` always returns owned bytes, including a
copy for plain SFNT/TTC input. Its size limit applies to the decoded output and
therefore bounds WOFF expansion and DFONT-to-SFNT/TTC reconstruction.
Convenience database loaders use a conservative 64 MiB default; callers
loading a trusted larger collection can use the explicit `*WithLimit` APIs.

The implementation is organized under `src/font/container/`:

- `root.zig` owns format detection, the unified decode contract, and the
  internal decoded-face owner.
- `dfont.zig`, `woff1.zig`, and `woff2.zig` isolate format-specific validation
  and reconstruction.
- `binary.zig` centralizes checked ranges, alignment, and big-endian access.
- `test_support.zig` and `tests.zig` keep fixture construction and malformed
  input coverage outside production decoders.

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
remains meaningful. The normal face parser then validates reconstructed table
maps, checksums, and supported OpenType table grammars.

Tests cover single/multi-face DFONT reconstruction, malformed resource maps,
compressed and uncompressed WOFF1 tables, malformed ranges, physical-order
reconstruction, decoded-size limits, ownership, database scanning/manifests, a
fixed transformed-glyf WOFF2 fixture, and optional installed real fonts.
Current real-font probes include HarfBuzz's retained `DFONT.dfont`, MathJax
WOFF1, Annapurna SIL WOFF1/WOFF2, and a variable General Sans WOFF2.

Embedded bitmap coverage includes sbix PNG, CBDT PNG formats 17/18/19, and
raw EBDT/CBDT formats 1/2/5/6/7. Compound formats 8/9 recursively flatten
same-strike components under a FreeType-compatible depth guard. Raw strikes
expose borrowed 1/2/4/8-bpp mask payloads with row-alignment metadata and
bounded 8-bit coverage decoding.
All raw 32-bpp formats expose premultiplied sRGB BGRA payloads without a
conversion allocation. Formats 1/6 match Skrifa; formats 2/5/7 additionally
match FreeType's BGRA output and exceed Skrifa's current high-level boundary.
The CPU renderer and draw-list
atlas surface consume masks as alpha and PNG/BGRA content as color.
CBLC/EBLC inspection retains distinct horizontal/vertical ppem values, strike
orientation flags, and both horizontal and vertical `BigGlyphMetrics`
bearings/advances instead of collapsing them into one horizontal record.
`tools/freetype_bitmap_oracle.c` reads the retained format-8 fixture through
FreeType and confirms parent metrics `4x2`, bearing `(0,2)`, and rows `1000` /
`0010`; the Cangjie materializer and CPU-render tests retain the same pixels.

## Performance Scope

Container decoding is a load-time cost, not a shaping hot path. Representative
local probes measured roughly 0.31 ms for a 34 KiB MathJax WOFF1 and 1.2--1.3
ms for a 38 KiB variable General Sans WOFF2, including reconstruction and
parse. Already-decoded SFNT copy-and-parse was substantially cheaper. These
figures establish practical startup cost only; they are not a claim of
load-time superiority over FreeType or Fontations.

## Fontations Coverage Gate

The Fontations/Skrifa oracle now also exposes a repeated unscaled outline draw
boundary. On fixed CPU 30, 31-sample medians for Roboto `A` measured Cangjie's
parsed `GlyphSession` at `1007/1024 ns` versus Skrifa at `1025/1196 ns`; Noto
Serif `g` measured `4717/4623 ns` versus `6815/6868 ns`. The initial Noto Kufi
Arabic `س` row exposed a Cangjie deficit at about `6000 ns` versus
`5766/5798 ns`. Profiling found repeated CFF Private DICT and Local Subrs INDEX
decoding on every glyph. Parse-time CFF state now owns decoded per-FD private
records and local subroutine indexes; the post-fix Cangjie row measured
`3585/3751 ns` versus Skrifa's fresh `5641/5782 ns`, about a `1.55x`
geometric-mean Cangjie lead. Command-stream checksums are stable within each
engine, and the existing CFF/FreeType correctness gates remain authoritative
for geometry parity. These are three unscaled outline workloads, not an
overall Fontations performance claim.

The oracle also covers repeated unscaled glyph metrics and nominal charmap
lookups. On the same CPU, Roboto glyph metrics measured `8.88 ns` for Cangjie
versus `26.62 ns` for Skrifa. Public `Face` views now explicitly reuse their
documented immutable-byte parse proof for horizontal metrics and cmap reads;
the mutation-aware low-level `Font` methods retain checksum revalidation.
Caching the selected cmap at parse time and dispatching the proven format
reduced Roboto U+0041 from `107.42/106.52 ns` to `70.48/60.56 ns`. Skrifa
measured `35.96/35.95 ns`, so charmap remains a measured Fontations deficit
despite the roughly `1.7x` Cangjie improvement. A supplementary-plane format-12
control likewise measured Cangjie at `53.49/57.44 ns` versus Skrifa at
`31.58/29.47 ns`. Cangjie now also decodes the selected immutable format
8/12/13 group array once at face parse time; the same supplementary-plane row
fell further to `44.01/44.05 ns`, preserving exact format-12/13 mapping tests.
Parse-time 4 KiB scalar buckets then bound each immutable group search to the
small subset intersecting one Unicode page. That reduced the same format-12 row
to `27.25/27.28 ns` versus Skrifa's fresh `44.57/44.63 ns`; Roboto U+0041
also measured `36.48 ns` with metrics/outline controls unchanged. These rows
now favor Cangjie, but they remain narrow repeated-lookup evidence rather than
an overall Fontations performance claim.

The immutable face also retains the selected cmap's complete ASCII mapping,
which is only 256 bytes per face and avoids even format dispatch for common UI
text. Roboto U+0041 fell from `271.29/270.28 ns` on the pre-sidecar binary to
`17.67/17.45 ns`; a fresh cross-engine run measured Cangjie at `17.61/11.84
ns` versus Skrifa at `36.29/36.38 ns`. Supplementary format-12, metrics, and
outline controls remain on their separate proven paths.

Repeated bitmap strike selection is covered as well. On the generated 2x1
premultiplied-BGRA CBDT fixture, Skrifa measured `170.96/260.50 ns`; Cangjie
initially measured `370.15/278.11 ns` because its public color view repeated
whole-table checksums and CBLC/CBDT structural validation. The immutable Face
view now reuses the parse proof while the low-level mutation-aware methods keep
their defensive checks. Post-fix Cangjie measured `106.51/134.83 ns`, with the
same 8-byte `9703b39ed959628c` payload contract and existing bitmap tests.

Skrifa's high-level global `Metrics` boundary is now covered independently of
the table-family manifest. On Roboto, both engines return UPEM 2048, 3359
glyphs, `1900/-500/0` ascent/descent/leading, cap height 1456, x-height 1082,
average/max width `1161/4368`, and bounds `-1825,-555,4188,2163`; the complete
field checksum is `00000005bc61651f`. Repeated immutable-Face reads initially
measured Cangjie at `785.86/670.00 ns` versus Skrifa at `437.30/364.89 ns`
because Cangjie revalidated head, hhea, OS/2, and post on every view call. The
Face view now reuses its parse proof while mutation-aware `Font` APIs retain
defensive validation. Post-fix Cangjie measured `142.18/130.17 ns`, preserving
the same complete-field result.

`docs/fontations-coverage.json` maps every public top-level table family in
Fontations `read-fonts` 0.42.2, plus eight grouped Skrifa 0.45.2 capability
families covering `MetadataProvider` and embedded TrueType hinting, to a
concrete Cangjie implementation file and a live test artifact.
`zig build fontations-coverage` verifies that every pinned upstream module and
API is mapped exactly once, the referenced files remain live, and every test
artifact still declares Zig tests. This is an inventory and evidence-maintenance
gate, not proof of per-table semantic parity or superiority; those stronger
claims require reference differential tests and same-host performance
measurements.

CFF1 and variable CFF2 outlines now expose reusable PPEM-specific Type2
hinting instances. The charstring executor retains horizontal/vertical stems,
hint masks, and counter masks; Private DICT parsing supplies variation-aware
blue zones, family zones, BlueScale/Shift/Fuzz, and LanguageGroup. The native
hint map uses FreeType-compatible 16.16 arithmetic, blue-zone capture, initial
mapping, overlap rejection, pair adjustment, cross-mask stem locking, and
26.6 output truncation. `zig build hinting-freetype-test` compares complete
point/tag/contour/advance output for deployed STIX CFF1 glyphs at several
sizes and Cantarell variable CFF2 glyphs at non-default locations. This closes
the previously missing Skrifa `HintingInstance` CFF boundary; it is correctness
evidence, not a CFF outline-performance superiority claim.

The incremental-font surface also applies table-keyed `iftk` patches: it
validates compatibility IDs and sorted offsets, supports shared-dictionary
Brotli diffs plus replace/drop flags, ignores duplicate tags after the first
entry like Fontations, and rebuilds a tag-sorted SFNT with fresh table
checksums and `head.checkSumAdjustment`. The decoder loads the system Brotli C
runtime dynamically; unavailable platforms report
`error.BrotliRuntimeUnavailable` rather than accepting compressed bytes.

Glyph-keyed `ifgk` patch groups are applied atomically as well. Cangjie
authenticates every selected `IFT `/`IFTX` compatibility id, decodes and
validates every `GlyphPatches` directory before reconstruction, merges
duplicate table/glyph keys with first-patch priority, and rebuilds the coupled
`glyf`/`loca`, `gvar`, CFF, and CFF2 CharStrings data defined by the IFT
specification. Unknown table tags are ignored. Application-bitmap bits are
committed only after every supported table succeeds, and the operation returns
a separately owned canonical SFNT without modifying the borrowed source face.

Skrifa's localized-string selection is covered separately too. On the
multilingual system Noto Sans, both engines choose the English-or-first family
name `Noto Sans` with per-read checksum `76daabed9807bcc7`. Cangjie's original
Face path allocated and materialized every matching localized record and
revalidated the complete name table, measuring `3961.86/2881.41 ns` per read.
The immutable Face now selects directly from the parse-proven table without an
intermediate allocation; mutation-aware `Font.localizedNames` keeps its
defensive checksum/validation contract. Post-fix Cangjie measured `62.10/52.30
ns` versus Skrifa at `299.07/174.54 ns`, with the selected UTF-8 value unchanged.

The Face glyph view also matches Skrifa's resolved glyph-name policy: a
name-bearing `post` table has first priority, non-CID CFF1 charsets resolve
standard and custom SIDs through the CFF String INDEX, and absent, invalid, or
empty names synthesize `gidNNN`. The existing nullable `name`/`Font.glyphName`
API remains the raw mutation-aware `post` contract; `resolvedName` is the
explicit total lookup. The local Skrifa oracle exposes the same `glyph-name`
boundary for post, CFF, and synthesized differential/performance checks.
On the retained gid-1 fixtures, Skrifa and Cangjie resolve identical values and
single-lookup hashes: `A1`/`0000410000006e42`,
`customGlyph`/`b6cad728a83bbe01`, and
`gid1`/`7d8ee301fa817891`. Fixed-CPU A/B/B/A runs (one million lookups, 31
samples) measured Cangjie at `45.19/45.59 ns` versus Skrifa at
`153.49/151.47 ns` for post; `117.32/117.32 ns` versus
`161.07/149.64 ns` for CFF; and `49.43/34.27 ns` versus
`107.31/107.34 ns` for synthesis. These are narrow repeated-name lookup
results, not an overall Fontations performance claim.

Skrifa's default-instance `attributes()` boundary is covered independently as
well. Complete wrappers around its own cmap12 head-fallback and cmap14
OS/2+post fixtures produce identical classification fields and per-read sums:
normal/italic/700 with `0000000083af0001`, and
0.875/oblique(-14)/800 with `0000000145080002`. The original mutation-aware
Face path measured `141.24/142.49 ns` for head fallback and
`250.30/188.00 ns` for OS/2 versus Skrifa at `65.83` and `67.48 ns`. Reusing
the immutable Face parse proof and decoding only the required style fields
reduces Cangjie to `8.57/11.80 ns` and `20.69/18.52 ns`, respectively, versus
fresh Skrifa controls at `67.78` and `104.61 ns`. Low-level attribute reads still detect
post-parse checksum mutations. These are narrow repeated classification
lookups, not an overall Fontations performance claim.

Variation axes and named instances now have a combined, non-allocating Face
summary boundary as well. The retained two-axis/two-instance fixture yields
the same complete field checksum `000000038fe9e2f0` in Cangjie and Skrifa,
including tags, indexes, NameIDs, flags, design-space ranges, optional
PostScript NameIDs, and instance coordinates. Fixed-CPU-30
Cangjie/Skrifa/Skrifa/Cangjie medians over one million reads were
`127.34/318.91/438.69/127.07 ns`. The ordinary `axes` and `instances` Face
methods also reuse parse-time fvar proof, while their low-level `Font`
counterparts retain checksum/name-reference revalidation. This is narrow
variation-metadata evidence, not an overall Fontations performance claim.

Skrifa's `ColorPalettes` boundary is now represented directly in the Face
color view: callers can enumerate palette metadata and colors, or take a
non-allocating complete summary. On the retained one-palette/two-entry CPAL
fixture, both engines produce checksum `00000001feff0102` over collection
length, palette index/count/type/label, and RGBA records. Fixed-CPU-30
Cangjie/Skrifa/Skrifa/Cangjie medians over one million reads were
`37.62/46.99/71.41/60.73 ns`; checksums were stable. Low-level scalar and
owned CPAL APIs retain post-parse checksum/name-reference validation, while
the immutable Face view reuses structural parse proof. This is narrow CPAL
metadata evidence, not an overall Fontations performance claim.

The Face color view also exposes Skrifa's preferred color-glyph source lookup:
COLRv1 is selected first and COLRv0 is the fallback. Retained v0-only and
v1-only fixtures match Skrifa's source-presence checksums `2` and `1`.
Fixed-CPU-30 Cangjie/Skrifa/Skrifa/Cangjie medians were
`53.63/111.87/112.04/47.86 ns` for v0 and
`40.40/141.13/131.81/37.38 ns` for v1. The summary also retains layer/paint
content for Cangjie diagnostics; low-level COLR graph methods remain
mutation-aware. This is narrow source-selection evidence, not an overall
Fontations performance claim.

The Face color view now exposes Skrifa-equivalent embedded bitmap strike
collections as well, using the same `sbix → CBDT → EBDT` source priority. A
non-allocating summary covers format, strike count, and each strike's ppem; on
the retained CBDT fixture both engines produce `0000000041800002`. Fixed-CPU-30
Cangjie/Skrifa/Skrifa/Cangjie medians over one million reads were
`13.60/270.89/229.46/26.60 ns`. Owned strike enumeration is also available;
low-level bitmap APIs retain complete post-parse location/data validation,
while immutable Face reads reuse the parse proof. This is narrow strike
metadata evidence, not an overall Fontations performance claim.

Preserve-GID TrueType subsetting now handles variable fonts explicitly. The
default keeps the complete fvar/avar/gvar/HVAR/VVAR/MVAR/STAT/cvar family: GIDs
and glyph-count domains remain stable, so retained glyph outlines and metrics
continue to vary while cmap hides unretained glyphs. Callers that need a static
default-instance program can set `preserve_variations=false`; the entire
coupled variation family is then removed together rather than emitting a
partially variable font. A focused gvar fixture proves both the retained
non-default outline and the stripped zero-axis/default-outline result.

The subset cmap builder also retains Unicode variation sequences by default.
It reconstructs sorted platform-0/encoding-5 format-14 records beside the
selected format-12 cmap, preserves both default UVS ranges and explicit
non-default glyph mappings whose resulting GID remains in the closure, and
drops records that target removed glyphs.
`preserve_unicode_variation_sequences=false` emits a format-12-only cmap. The
combined fixture verifies U+0041+FE0F non-default glyph 3 and U+0042+FE0F
default semantics after reparsing the emitted subset.

COLRv0/CPAL is now an optional preserve-GID subset profile too. When enabled,
the subset retains only color base records selected by the requested glyph
set, copies their palette-indexed layer records, and keeps CPAL unchanged;
unselected color bases disappear while layer GIDs remain stable. Setting
`preserve_color_layers=false` drops COLR and CPAL together for a monochrome
program. COLRv1, bitmap strikes, SVG, and VARC remain rejected because their
recursive paint/image/component closures require separate serializers rather
than pretending a copied table is a valid subset.

Validated SVG glyph documents can be retained independently as well. The
subset resolves each document covering a retained GID, emits one sorted
single-glyph SVG record, and writes resolved gzip content as ordinary validated
XML. This avoids keeping a source record range that still advertises removed
glyphs. `preserve_svg_documents=false` drops the table; bitmap strikes and
VARC remain explicitly unsupported pending their own closure/rewrite logic.

Outline-backed sbix PNG strikes now have a preserve-GID subset path as well.
Every authored strike is rebuilt with the original ppem/ppi, a complete
glyph-count offset array, and direct PNG records only for retained glyphs;
resolved `dupe` records become self-contained images, so removed target GIDs
cannot leave dangling strike references. `preserve_sbix_strikes=false` drops
the table. CBDT PNG image formats 17 and 18 now have a bounded preserve-GID
path as well: every strike is rebuilt with a complete dense format-1 offset
array, retained image records are copied verbatim, and removed GIDs receive
empty offsets. `preserve_cbdt_png_strikes=false` drops CBDT/CBLC together.
Shared-metrics format 19, raw/compound CBDT records, and EBDT remain
unsupported until their index-2/5 and component serializers are equally
strict.
