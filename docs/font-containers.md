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
