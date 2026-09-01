# Cross-library completion audit

The project goal is an evidence-backed claim that Cangjie exceeds FreeType,
HarfBuzz, Fontations/Skrifa, and Parley in both relevant functionality and
performance. This is intentionally stronger than passing unit tests or winning
one benchmark. The claim remains **open** until every row below is closed.

## Required evidence

| Reference | Concrete completion criterion | Current artifact/evidence | Status |
| --- | --- | --- | --- |
| HarfBuzz | Exact glyph IDs, clusters, advances, offsets, and relevant flags across retained upstream and production-font corpora | `shaping-parity-smoke`, `shaping-corpus-parity-smoke`, `tests/data/`, `docs/shaping-parity.md` | Strong retained coverage, not exhaustive |
| HarfBuzz/HarfRust | Faster than the faster reference on every representative shaping workload, with independent binaries, pinned CPU, symmetric order, and repeatable margin | `shaping-performance-matrix` and its optional versioned `--json-output` artifact | Open: the current fixed-CPU-30 `5 * 31` core run clears the explicit `1.01x` gate for Roboto, Source Serif, and both Amiri rows (`1.441x`/`1.013x`/`1.143x`/`1.501x`) but Devanagari remains red (`0.965x`). The current `3 * 31` broad run leads both Latin rows (`1.143x`/`1.080x`) but Noto Nastaliq remains red (`0.782x` words, `0.614x` long). Some endpoints were visibly contention-affected, so the large red rows—not inflated winning ratios—are the actionable evidence; broader shaping performance remains open |
| Fontations/Skrifa | Every pinned public table/API family mapped to a live test; shared high-level operations semantically equivalent and faster at matched lifecycle boundaries | `docs/fontations-coverage.json`, `fontations-coverage`, `fontations-matrix` | Inventory complete; all 33 maintained rows are semantically exact, now including real VARC GID 1 at default, conditional-boundary, and endpoint locations in owning and reuse lifecycles. The focused strict VARC matrix now leads all eight new rows after parsed-gvar decoding was accelerated; broader semantic coverage remains open |
| FreeType | Correct outline/hinting/bitmap behavior plus faster matched cold, owning, reused, and prepared raster lifecycles across glyf/CFF/CFF2, bitmap/color, representative scripts, and sizes | `hinting-freetype-test`, `hinted-outline-matrix`, `glyph-bench`, `freetype-matrix`, raster evidence in `docs/shaping-parity.md` | Open: all 75 maintained grayscale raster rows, all 10 native-strike bitmap rows, the shared COLRv0 layer/CPAL row, and all five matched face-open rows lead. The expanded 120-row hinted-outline matrix is semantically exact; the earlier 100 rows led in one strict run and the 20 new U+00C3 rows lead in focused repeats, but a combined strict run remains noise-sensitive. Complete eager validation is separately reported and remains slower, COLRv1/SVG have no FreeType built-in renderer for direct performance comparison, and broader glyph/platform coverage remains incomplete |
| Parley | Equivalent paragraph layout results—not only counts—and faster default/styled/reflow paths for Latin, Arabic, CJK, bidi, vertical, fallback, and inline-object workloads | `parley-matrix`, paragraph/reflow tests, `docs/text-pipeline.md` | Open: the maintained 38-row matrix covers three scripts, centered placement and reflow, three construction styles, retained reflow, matched in-flow/ordinary/custom out-of-flow objects, mixed Roboto→Noto Sans Devanagari fallback, and mixed Latin/Hebrew/Arabic construction and reflow with both LTR and RTL base directions. Seventeen text rows enforce exact normalized geometry, resolved cluster direction, and visible-left placement, while all 18 object rows enforce exact object geometry. The explicit performance gate defaults to `1.01x`; the latest strict run is red on twenty rows after applying it to every maintained row. Japanese default/spacing line boundaries differ because Cangjie honors shaping-derived unsafe-to-break boundaries that pinned Parley does not consume; vertical comparison remains unavailable because the pinned Parley API has no writing-mode input |
| Robustness | Malformed supported inputs fail atomically under safety checks and sustained coverage-guided fuzzing | `font-fuzz-smoke`, `font-fuzz`, regression fixtures | Open: the retained 100K campaign is useful evidence, not exhaustive format coverage |
| Platform scope | Results reproduced on each supported target or the performance claim explicitly scoped to named hardware/OS/toolchain versions | benchmark documentation | Open: current performance evidence is primarily one Linux x86-64 host |

Parley 0.7's public builder/layout API has no writing-mode or vertical-flow
input. The matrix emits `parley_vertical_api=false` to make that capability
boundary machine-visible; rotating horizontal coordinates would not constitute
a vertical-layout differential. Cangjie's vertical conformance remains covered
independently, but no cross-library vertical performance claim is made.

## Reproducible audit snapshot

The following checks were rerun for the audited state described below on Linux
x86-64, pinned to CPU 30 where the harness supports it:

- `zig build test -j1 -Doptimize=ReleaseFast --summary failures`: pass.
- `zig build shaping-parity-smoke ... --summary none`: pass against the local
  HarfBuzz 14.3 and HarfRust references. The same gate was rerun after the
  bitmap-differential additions and passed.
- `zig build shaping-corpus-parity-smoke ... --summary none`: pass.
- `zig build fontations-coverage -Doptimize=ReleaseFast`: 41 table families,
  48 public modules, and eight high-level capability groups mapped.
- `zig build fontations-matrix -Doptimize=ReleaseFast -- --iterations 100000
  --samples 7 --cpu 30 --fail-on-slower`: 25/25 semantic rows passed and the
  runner now enforces rather than merely reports the performance requirement.
  Every measured row favored Cangjie (`1.271x--13.947x` in the latest strict
  run). The real
  variable-CFF2 rows require identical normalized FNV command streams and
  cover default owning output (`1.252x`), retained caller storage (`13.814x`),
  and owning output at normalized `wght` endpoints `+1`/`-1`
  (`1.317x`/`1.336x`). Caller-owned reuse at those endpoints leads by
  `13.865x`/`13.763x`.
- Variable outline reuse now decodes directly into the caller-owned command
  buffer rather than replacing its allocation before publishing the coordinate
  cache key. A post-change strict `100000 * 7` run kept all 25 maintained rows
  green; CFF2 default/`+1`/`-1` reuse measured `13.835x`/`13.552x`/`13.531x`.
- The owning Fontations outline oracle now materializes Skrifa output into its
  public owned `Vec<PathElement>` before hashing, matching Cangjie's owned
  command-array lifecycle rather than comparing an owning result with an
  allocation-free callback pen. The maintained strict matrix remains green;
  the final corrected `100000 * 7` CFF2 owning/reuse rows led by
  `1.713x`/`18.144x` at default coordinates and `1.701x--1.753x`/
  `18.146x--18.253x` at the two endpoints. Debug command tracing is resolved
  once outside the measured loop, so an unset diagnostic environment variable
  does not distort these results. A later fixed-CPU-30
  `1000 * 11 --extended --fail-on-slower` run passed all 125 semantic and
  performance rows.
- The maintained matrix now retains Fontations' real
  `varc-ac01-conditional.ttf` and adds eight GID-1 rows: owning and
  caller-storage draws at the default location, immediately below/at the
  normalized `wght=0.5` conditional boundary (`0.49,0` and `0.5,0`), and the
  `1,0` endpoint. Direct one-iteration checks and the 33-row quick matrix
  produced identical command-stream checksums for both engines: `249fc6df523c4439`,
  `5a6e6f5198f5f187`, `42fd47d8cbf0b95c`, and `2bc32c6dbad5615e`
  respectively. A fixed-CPU-30 `10000 * 7` focused probe was deliberately run
  without `--fail-on-slower`: reuse led by `9.712x--12.340x`, while owning
  default narrowly led (`1.054x`) and the three varied owning rows initially
  trailed (`0.862x`, `0.916x`, and `0.909x`). Parsed simple-glyph variation
  now reuses `gvar` metadata retained by `Font.parse`, fuses dense all-point
  delta decoding with accumulation, and allocates sparse interpolation scratch
  only when required. A fixed-CPU-30 `10000 * 7` rerun then led all owning
  rows at `1.431x`, `1.478x`, `1.492x`, and `1.476x`, with reuse at
  `9.542x--11.987x`; a later strict `1000 * 3` verification also passed all
  eight rows. Symmetric 200,000-iteration counters reduced owning retired
  instructions by `27.36%--40.62%` and branches by `29.49%--41.76%`.
- Ranged shaping now propagates the reusable engine's detailed profiling
  configuration through its independent GSUB boundary. The ReleaseFast-only
  `cached GSUB plans retain detailed lookup profiling` failure is closed; its
  regression also verifies the actual ranged substitution result `[2,2,2]`.
- The optional Fontations `--extended` outline corpus now includes all ten
  selected semantically identical glyphs from the larger two-axis
  `AdobeVFPrototype.otf`, in both owning and caller-storage modes. The original
  fixed-CPU-30 `1000 * 7` run led all ten initial CFF2 rows
  (`1.065x--1127x`). Cangjie's Type2 path builder now canonicalizes a final
  explicit line back to the contour origin into the following close operation,
  matching Skrifa and admitting glyphs 20, 64, 128, and 192 to the matrix.
  Raising the CFF2 operand stack to the format's 513-entry limit also admits
  glyph 2's large blend program. A `1000 * 7` semantic/performance run of the
  resulting 125-row extended matrix confirmed every checksum. Under the
  corrected owned and reusable lifecycles, a fixed-CPU-30 `1000 * 11` rerun
  measured glyph 20 at `1.008x` and glyph 128 at `1.052x`; a subsequent rerun
  measured them at `1.128x` and `1.321x`. All ten selected Adobe owning/reuse
  pairs now lead. In the final strict 125-row rerun the production-glyf owning
  rows that had previously trailed led by `2.194x--4.508x`, and their reuse
  rows led by `3.126x--28.240x`.
- Parsed-face static `glyf` decoding now uses the grammar proof established by
  `Face.parse` instead of repeating the per-expanded-flag predicate for every
  owning outline. Fixed-CPU-30 A/B/B/A probes kept checksums unchanged and
  improved the representative owning rows by roughly 1--2% (Roboto gid10/128,
  DejaVu gid133, and Noto Arabic compound gid20/200). The later matched-lifecycle
  strict run closes every currently retained extended production-glyf row.
- `zig build parley-matrix -Doptimize=ReleaseFast -- --iterations 1000 --samples
  7 --cpu 30 --fail-on-slower`: the 26-row matrix passed before custom
  placement was added. The current 34-row semantic matrix passes. Thirteen
  text rows enforce exact normalized geometry and visible-left placement, and
  all 18 object rows enforce exact normalized object geometry. The added ordinary
  out-of-flow six rows use the
  same 24x20 object as the in-flow cases but select Parley's `OutOfFlow` and
  Cangjie's `.out_of_flow` semantics for both construction and retained
  reflow. After reserving the single retained object output before the timed
  loop, an earlier run led all six new rows (`1.089x--1.801x`) and all 24 rows.
  Repeating the matched A/B/B/A run after adding the geometry oracle found two
  narrow open regressions: Arabic in-flow and out-of-flow retained reflow.
  Deriving both the logical and final visual marker indices from retained run
  and line ranges removed two whole-paragraph scans; the latest run led those
  rows at `1.014x` and `1.002x` in the latest expanded strict run and every
  enforced row overall. The
  margin remains near noise and needs continued monitoring. After removing Parley's
  timed O(n) semantic-summary walk to match Cangjie's O(1) timed consumer,
  Cangjie had led the preceding 18-row run. Default Latin, Arabic, and Japanese retained reflow
  lead by `1.524x`, `1.231x`, and `1.561x`; their inline-object counterparts
  lead by `1.325x`, `1.029x`, and `1.358x`. Arabic default, spacing,
  alternating, and inline-object construction lead by `1.191x`, `1.169x`,
  `1.238x`, and `1.214x`; Japanese spacing leads by `1.801x`. Retaining exact
  text-only UAX #29/#14 analysis moves Japanese alternating construction to a
  reproducible `1.112x` lead. Logical-line geometry agrees on 9/24 rows after
  preserving source ranges, advances, and relative cluster placement while
  discarding only a per-line translation and sub-1/1024 px accumulation noise.
  Object geometry is compared independently at the fractional-coordinate
  boundary (Parley pixel quantization disabled), including stable id, source
  byte, owning line, x/y, width/height, and baseline.
  The six custom-object rows model a pre-resolved absolute 24x20 placement and
  explicitly drive Parley's resumable custom-box breaker. Construction leads
  in Latin/Arabic/Japanese. Retained single-object positioning now narrows its
  search to the source-containing line, and out-of-flow line metrics skip an
  inapplicable object scan. A fixed-CPU-30 `10000 * 11` run measured custom
  reflow at `1.420x`/`1.048x`/`1.406x`; ordinary out-of-flow reflow measured
  `1.413x`/`1.013x`/`1.381x`. A later full strict run remained red only on the
  noise-sensitive Arabic in-flow row (`0.978x`); the other two Arabic object
  modes narrowly led (`1.013x` and `1.048x`).
  The retained simple line builder now derives a single validated in-flow
  object's metric contribution from its already-known source range instead of
  scanning each line for the marker, and run-offset recomputation stops after
  establishing the final run origin because no later run can consume its
  trailing prefix sum. The resulting fixed-CPU-30 `10000 * 11` strict matrix
  passes all 32 rows; Arabic default/in-flow/ordinary/custom retained reflow
  leads by `1.048x`/`1.022x`/`1.007x`/`1.013x`. These margins are still close
  enough to require continued monitoring.
  The mixed Roboto→Noto Sans Devanagari fallback rows also have identical
  normalized geometry. Extending the retained simple-path proof to adjacent
  multi-glyph clusters moved fallback construction/reflow to `1.664x`/`1.718x`
  in the latest run.
- The maintained Parley matrix now contains 38 rows. Four new default-style
  rows cover mixed Latin/Hebrew/Arabic paragraphs with resolved LTR and RTL
  bases in both construction and retained reflow. Their common digest includes
  source ranges, visible positions and advances, and resolved cluster
  direction while collapsing discarded wrapping-space advance. Both engines
  agree exactly: the LTR fixture has 73 glyphs and three lines; the RTL fixture
  has 76 glyphs and three lines. This raises the explicitly enforced text
  geometry/direction/placement set from 13 to 17 rows; all 18 object-geometry
  rows remain exact.
- `parley-matrix` now declares a finite minimum speedup greater than parity,
  defaults it to `1.01x`, accepts the exact boundary, reports it on every row,
  and makes `--fail-on-slower` reject any row below it. A fixed-CPU-30
  `1000 * 7` strict audit passed the semantic checks but correctly failed nine
  performance rows: Latin centered reflow `0.434357x`; Arabic default, spacing,
  and alternating construction `0.690567x`/`0.696919x`/`0.718518x`; Japanese
  alternating construction `0.879623x`; and mixed-bidi LTR construction/reflow
  `0.274357x`/`0.477241x` plus RTL construction/reflow
  `0.272972x`/`0.469446x`. These are open deficits, not passing evidence. The
  mixed-bidi reflow path subsequently stopped revalidating the complete cmap
  for each mirrored scalar and uses the parsed immutable-face lookup; focused
  repeats fell from tens of microseconds to roughly 2--3 microseconds with
  identical checksums, but a fresh full strict matrix is still required before
  claiming those four rows closed.
- A later profile found another, much larger mixed-bidi construction tax:
  every logical shaping run reacquired the legacy `kern` handle through the
  mutation-aware API and checksummed DejaVu Sans's 16,380-byte table. That scan
  consumed about 60.8% of sampled cycles. The Engine now proves and caches the
  handle once under its existing immutable face-byte contract; one-shot uniform
  layout also reuses its buffer-owned UAX #9 storage. Fixed-CPU-30 symmetric
  `5000 * 7` probes reduced LTR construction from `145.159/146.028 us` to
  `52.918/53.426 us` and RTL from `107.478/107.068 us` to
  `42.123/41.529 us`, with all output digests unchanged. A fresh strict
  `1000 * 7` full matrix improves the corresponding Parley ratios to
  `0.749865x` and `0.763963x`, but they remain below `1.01x`; the matrix is
  still red on twenty rows overall. This is a material retained improvement,
  not closure of the Parley gate.
- `zig build font-fuzz-smoke -Doptimize=ReleaseSafe -- ...`: six retained
  repository seeds and 2,946 deterministic cases passed in the latest
  shaping-expanded rerun.
- `zig build font-fuzz -Doptimize=ReleaseSafe --fuzz=100K`: the selected
  parser/render target completed 269,563 executions, 2,467 unique runs, and
  4,331/32,005 instrumented edges (13.53%) without a reported failure.
- A later 100K campaign exposed an undersized legacy `kern` subtable that
  reached a reversed slice before its declared length was rejected. The parser
  now validates the recovered format-0 length before slicing, has a focused
  regression test, and the replay completed 206,868 executions with 931 unique
  runs and 5,448/32,252 edges (16.89%) without another failure.
- The malformed-font driver now additionally exercises caller-owned reusable
  outline storage, owning and reusable non-default variable outlines, color
  palettes, and bitmap strikes. A fresh ReleaseSafe 100K campaign completed
  208,224 executions with 762 unique runs and 5,624/32,884 edges (17.10%)
  without a failure. Letting bitmap-only and color-only faces continue through
  metadata access after an absent conventional outline raised the final replay
  to 233,293 executions, 686 unique runs, and 5,741/32,892 edges (17.45%), also
  without a reported failure.
- Successfully parsed fuzz inputs now also run a bounded Latin/Arabic/Indic
  shaping corpus, including one UTF-8 byte-ranged GSUB feature request, through
  one reusable engine. The driver retries a valid request after malformed UTF-8
  and propagates allocator failures while tolerating ordinary malformed-table
  and shaping errors. Generated GSUB, GPOS, and mixed OpenType/AAT fonts extend
  the structured corpus beyond the existing `morx`/`mort`/`kerx`/`trak` seeds.
- An earlier, separate `font-fuzz-smoke` run over six external HarfBuzz fuzz
  seeds covering CFF2+COLR v1, CBDT, sbix, SVG, variable CFF2, and malformed
  CBDT PNG completed 3,084 deterministic ReleaseSafe cases without a failure.
  Its different case count reflects the external seeds' sizes: prefix coverage
  is capped at byte 256, then each seed receives 256 mutations.
- `zig build freetype-matrix -Doptimize=ReleaseFast -- --iterations 100
  --samples 5 --sizes 8,16,32,64,128 --cpu 30 --fail-on-slower`: completed 40 symmetric
  A/B/B/A raster rows across Latin glyf, Latin CFF1, Arabic glyf, and CJK CFF.
  It found real remaining deficits before enlarging the bounded repeated-
  geometry cache: Arabic reused-outline raster ranged from `0.599x` to
  `0.886x`, while CJK reused-outline raster ranged from `0.425x` to `0.734x`
  versus FreeType. The retained cache enlargement removed the dominant CJK
  deficit, and retained coverage/emboldening then closed every row. A strict
  post-change `500 * 11` run measured all 40 rows ahead (`1.177x--4.522x`).
  CFF2 now retains its parsed top-level and per-FD Private DICT execution
  metadata. The latest expanded 75-row run including CFF2 and fresh owning
  outlines completed with every row ahead (`1.174x--17.073x`); after the
  CFF2 charstring improvements described below, the former owning 8 px blocker
  moved from `0.989x` to `1.698x`.
- `glyph-bench --mode bitmap-render` now compares decoded native embedded-
  bitmap output with FreeType. It hashes the selected ppem, dimensions,
  authored horizontal placement, and normalized mask8 or premultiplied BGRA8
  pixels while excluding row padding. `bench-smoke` proves identical output
  for synthetic CBDT PNG, raw BGRA, EBDT mask, and compound format 8; real
  HarfBuzz CBDT and sbix PNG fixtures also produce identical checksums. A
  fixed-CPU-30 symmetric `1000 * 7` probe found explicit performance deficits:
  Cangjie/FreeType were `131756.841/66794.454` and
  `129480.187/66687.966 ns` for NotoColorEmoji CBDT at 109 ppem
  (`0.511x` endpoint geometric ratio). The complete fixed-CPU-30 `500 * 11`
  matrix added five CBDT and five sbix rows (90 total). CBDT remained behind
  at `0.442x--0.514x`; sbix 8/16 ppem were ties at `0.983x`/`0.987x`, while
  32/64/128 ppem led by `1.171x`/`1.153x`/`1.038x`. This closes
  the missing common-output instrumentation, not the performance requirement.
  Profiling the CBDT row showed that per-pixel Wyhash updates, rather than PNG
  inflation, dominated the Cangjie benchmark adapter. Canonicalizing its
  private decoded RGBA allocation to premultiplied BGRA in place and hashing
  once reduced a fixed-CPU-30 A/B/B/A `1000 * 11` run from
  `130423.622/131862.929` to `59242.994/59744.398 ns` with identical output.
  Three-repeat counters fell from about `1.857B` to `632--636M` instructions,
  `263.8M` to `104.2--104.8M` branches, and `585.6M` to `266.9--269.0M`
  cycles. A same-binary seven-sample check then measured CBDT at
  `59033.811/66747.079 ns` (`1.131x`) and sbix at `1.101x`, `1.465x`, and
  `2.046x` for 20/32/128 ppem. The final fixed-CPU-30 `500 * 11` 90-row
  matrix passed all semantic checks: all ten bitmap rows led, with CBDT at
  `1.189x--1.215x` and sbix at `1.118x--2.011x`; all 75 grayscale rows also
  remained ahead. This closes the maintained embedded-bitmap matrix, but not
  cold parsing or broader COLR/SVG and hinting coverage.
  The lifecycle runner now enforces these performance wins instead of only
  reporting the ratios; a smaller post-change strict smoke also passed all 40
  rows at 8/16 ppem.
- The matrix now also includes the common COLRv0 layer/CPAL boundary exposed by
  both libraries. Cangjie retains parse-proved compact COLR/CPAL layouts and
  provides allocation-free ordered layer iteration; low-level mutation-aware
  APIs retain checksum and whole-table validation. Synthetic and real Bungee
  fixtures match FreeType's layer glyph IDs, palette indices, and RGBA entries.
  A fixed-CPU-30 B/A/A/B `1,000,000 * 21` real-font run measured
  `65.979/63.882 ns` for FreeType and `49.916/51.649 ns` for Cangjie, a
  `1.273x` endpoint geometric Cangjie lead. The final `500 * 11` lifecycle
  matrix completed 91 rows and measured the same real row at `1.287x`. FreeType
  upstream explicitly documents that COLRv1 needs a separate graphics library,
  so COLRv1 and SVG remain Cangjie functionality evidence rather than a fair
  FreeType renderer-performance row.
- `OpenFace.open/openIndex` now provides the missing allocation-free face-open
  lifecycle: it validates collection offsets, the sorted bounded directory,
  mandatory core tables, outline topology, and horizontal metrics, then
  exposes core properties. `OpenFace.validate` explicitly promotes it to the
  existing fully validated `Face`; `face-validate` preserves that stricter
  benchmark, and legacy `face-parse` maps to it. A fixed-CPU-30 A/B/B/A
  `100000 * 11` run measured matched face-open speedups of about `33.1x`
  Roboto, `224.0x` STIX CFF1, `41.9x` Cantarell CFF2, `16.8x` Noto Kufi
  Arabic, and `1315.6x` Noto CJK, with identical UPEM/glyph-count checksums.
  Full eager validation still costs roughly `0.807 ms`, `0.177 ms`, `0.007
  ms`, `0.221 ms`, and `10.433 ms` respectively and is not misreported as the
  FreeType-equivalent boundary.
- `glyph-bench --mode hinted-outline` now exposes the same 26.6 point, on-curve,
  contour, and advance summary used by the FreeType hinting differential, with
  explicit v35/v40 and normal/light/LCD/LCD_V/mono controls. The existing
  `hinting-freetype-test` already covers seven TrueType fixtures (Latin,
  compound, Arabic, Devanagari, and variable glyf) across those modes, plus five
  CFF1/CFF2 Type2 cases. Moving public `Face` hint transactions onto the
  immutable parse-proof path removed repeated whole-glyf validation: against
  the independent `926b941d` binary, DejaVu Sans `A` at 9 ppem improved from
  about `1.355 ms` to `4.8--5.4 us`, while the normalized checksum remained
  exact. The row still trails FreeType's roughly `1.44 us`, so hinted-outline
  performance remains an explicit blocker.
- The hint VM now borrows its bounded `Cursor` instead of copying its 32-entry
  call stack per executed opcode, batches already-bounds-checked push operands,
  keeps scalar state opcodes out of the point-zone adapter, and gives dominant
  MDRP/MIRP instructions a focused dispatcher. Point contexts borrow the VM's
  zone descriptors rather than copying twelve slices per geometry opcode, and
  compound transactions retain parse-proved child data/metrics so execution
  does not resolve each child twice. A separate public in-place execution API
  makes the non-atomic renderer contract explicit while the original method
  again guarantees rollback on malformed caller-edited bytecode. Against the
  independent `d4d890d6` binary, fixed-CPU-30 A/B/B/A 11-sample rows improved
  DejaVu `A`/`X`, compound U+00C2, Devanagari U+0915, and Arabic U+0627 by
  `2.81x`, `2.56x`, `6.07x`, `6.46x`, and `6.90x`, respectively, without a
  checksum change. A matched candidate/FreeType run measured about `1.78/1.63
  us` (`0.92x`) for `A`, `1.32/1.19 us` (`0.90x`) for `X`, `4.58/2.75 us`
  (`0.60x`) for U+00C2, `24.24/27.48 us` (`1.13x`) for Devanagari, and
  `5.51/6.57 us` (`1.19x`) for Arabic. The retained `hinted-outline-matrix`
  exercises five glyphs, two sizes, v35/v40, and five targets in symmetric
  A/B/B/A order; its one-size smoke passed all 50 semantic rows. Latin and
  especially compound execution remain explicit performance blockers.
- Simple hinted-glyph transactions now allocate one aligned backing block for
  current/original/unscaled points, flags, and contour ends instead of five
  independent owners. This preserves the public slice API and atomic cleanup
  contract while reducing allocator traffic. A fixed-CPU-30 100,000-iteration,
  11-sample direct comparison reduced DejaVu `A`, `X`, and U+00C2 from about
  `1.76`, `1.32`, and `4.57 us` to `1.71`, `1.24`, and `4.24 us`; checksums
  remained exact. The same rows are still behind FreeType, so this improvement
  narrows rather than closes the retained Latin blocker.
- Simple glyf decoding now keeps its already-expanded raw flag byte beside each
  semantic point flag until both coordinate streams have been consumed. It no
  longer rescans the compressed flag run solely to recover Y delta bits. A
  fixed-CPU-30 100,000-iteration, 11-sample check improved `A`, `X`, and
  U+00C2 from about `1.68`, `1.24`, and `4.19 us` to `1.67`, `1.23`, and
  `4.15 us`, with exact FreeType checksums. A fixed-CPU-30 11-sample rerun of
  the final retained path measured `1.74/1.63 us` (`0.94x`), `1.30/1.18 us`
  (`0.91x`), and `4.54/2.76 us` (`0.61x`), respectively.
- Hinting instances now retain the parse-proved maxp point, contour, component,
  and depth limits consumed by glyph transactions. The immutable hot path no
  longer reparses maxp once per glyph merely to recover the same four values.
  Seven-repeat fixed-CPU counters reduced `A` by about `0.66%` instructions
  and `0.81%` branches, Arabic by `0.22%`/`0.18%`, and Devanagari by about
  `1.55%` cycles; the 50-row v35/v40 target matrix retained exact checksums.
- Immutable-face simple-glyph decoding no longer repeats the per-flag grammar
  predicate already established by whole-face glyf validation. The checked
  public transaction path retains that validation. Fixed-CPU-30 medians kept
  `A` and U+00C2 neutral and improved `X`, Devanagari, and Arabic by about
  `1.4%`, `2.5%`, and `2.7%`; full tests and the FreeType differential pass.
- Point-derived line vectors now use a four-entry direct-mapped cache local to
  one VM run. DejaVu's `A` repeatedly alternates only a few diagonal stem
  directions, so this avoids repeated normalization without carrying state
  across glyphs. Seven-repeat fixed-CPU counters reduced `A` instructions by
  `0.47%`, branches by `0.75%`, and cycles by `3.5%`; U+00C2 instructions,
  branches, and cycles fell `0.40%`, `1.12%`, and `1.58%`. Other controls were
  neutral within the observed cycle noise and the full differential passes.
- The benchmark's in-place rendering mode now retains transaction scratch
  capacity between glyph loads, matching FreeType's retained `FT_GlyphLoader`
  lifecycle instead of charging a fresh general-purpose allocation set on
  every iteration. Fixed-CPU-30 11-sample medians remained neutral for `A`,
  improved `X` from about `1.25` to `1.24 us`, compound U+00C2 from `4.22` to
  `4.18 us`, Devanagari from `24.23` to `23.97 us`, and Arabic from `5.51` to
  `5.40 us`, with unchanged checksums. The separately selectable atomic mode
  continues to measure its rollback-copy contract.
- `HintingPointTransactionBuffer` now makes that retained loader lifecycle a
  public, caller-owned contract rather than an arena benchmark artifact. Simple
  glyphs decode directly into reusable packed point/flag/contour storage. For
  repeated compound loads, the buffer retains the expanded transaction plus a
  pristine point/flag snapshot and restores it before bytecode execution, so
  pre-execution compound expansion is not repeated. The owning transaction and atomic execution
  APIs remain unchanged. Against the independent `a69336fa` binary, fixed-CPU-
  30 A/B/B/A counters reduced DejaVu `A` instructions/branches/cycles by
  `0.59%`/`0.40%`/`3.19%`, `X` by `0.77%`/`0.49%`/`2.88%`, and U+00C2 by
  `17.87%`/`18.25%`/`22.98%`; Devanagari retired work was neutral and Arabic
  instructions/branches fell `0.19%`/`0.11%` (cycles were within `0.5%`
  noise). Eleven-sample wall runs
  kept exact checksums and improved the compound row from about `4.18 us` to
  `3.20 us`. This substantially narrows, but does not close, the remaining
  FreeType compound-Latin gap.
- Compound point transforms now recognize the identity matrix and diagonal-
  only scale before entering the general four-multiply F2Dot14 path. Identity
  is the common case for accent composites such as DejaVu U+00C2. Against the
  independently built `5cab5664` binary, fixed-CPU-30 A/B/B/A counters reduced
  that row's instructions, branches, and cycles by `5.06%`, `5.79%`, and
  `6.03%`; the simple `A`/`X` controls kept retired work neutral.
- Component placement now handles identity transforms as three bulk copies
  rather than repeating the per-point identity predicate for current, original,
  and unscaled coordinates. A second fixed-CPU-30 A/B/B/A run against the
  independent `108776c5` binary reduced U+00C2 instructions by `2.85%`,
  branches by `2.52%`, and cycles by `4.28%`; `A`/`X` retired work remained
  neutral and the FreeType differential stayed exact.
- IUP now specializes its contour interpolation loop for X and Y at compile
  time, eliminating repeated runtime axis selection from the point loop. Against
  the independent `9d3f39af` binary, fixed-CPU-30 A/B/B/A counters reduced
  instructions by `0.88%` for `A`, `1.92%` for `X`, and `1.30%` for U+00C2;
  Devanagari also fell `0.16%`, while Arabic retired work stayed neutral.
- Top-level compound construction now retains pristine point/original/
  unscaled/flag/contour state for direct simple children. Compound execution
  borrows that state instead of parsing and scaling the same child `glyf` a
  second time; nested compound children retain the established recursive
  fallback. Fixed-CPU-30 A/B/B/A counters versus `37ba6d1c` reduced U+00C2
  instructions by `8.51%`, branches by `7.77%`, and cycles by `11.11%`;
  simple `A`/`X` retired work remained neutral.
- A final fixed-CPU-30, 11-sample Cangjie/FreeType A/B/B/A check at 9 ppem
  measured `A` at `1.626/1.642 us` (`1.010x`), `X` at `1.195/1.175 us`
  (`0.983x`), U+00C2 at `2.908/2.747 us` (`0.945x`), Devanagari at
  `23.767/29.363 us` (`1.235x`), and Arabic at `5.437/6.558 us` (`1.206x`).
  The simple `A` row has reached a narrow lead and compound Latin has moved
  close to parity, but `X`, U+00C2, and the broader matrix still prevent an
  overall hinting-performance claim.
- After retained child state and axis-specialized IUP, another fixed-CPU-30
  11-sample A/B/B/A run measured `A` at `1.664/1.662 us` (tie), `X` at
  `1.181/1.188 us` (`1.005x`), U+00C2 at `2.596/2.773 us` (`1.068x`),
  Devanagari at `24.177/29.624 us` (`1.225x`), and Arabic at
  `5.469/6.721 us` (`1.229x`). A subsequent two-size, two-interpreter, five-
  target matrix passed all 100 semantic rows; 92 rows led and the other eight
  were all DejaVu `X` near-ties between `0.988x` and `1.000x`. This is not yet
  a strict every-row performance win, and wider glyph/platform coverage remains
  open.
- IUP's internal interpolation ranges now consume the bounds proof established
  once by their enclosing contour walk instead of rebuilding an impossible
  error path for every touched-point pair. Against `e1343082`, fixed-CPU-30
  A/B/B/A retired instructions/branches fell `0.78%`/`0.79%` for `A`,
  `1.49%`/`1.00%` for `X`, and `1.17%`/`0.94%` for U+00C2; Devanagari and
  Arabic controls remained neutral or improved.
- The VM now materializes its point-zone runtime adapter once per program, not
  once per point opcode. Its members are pointers into VM state, so scalar
  opcodes remain immediately visible without reconstruction. Against
  `9a43a387`, fixed-CPU-30 A/B/B/A instructions/branches/cycles fell
  `3.65%`/`0.79%`/`1.79%` for `A`, `4.60%`/`0.97%`/`3.86%` for `X`, and
  `3.85%`/`0.93%`/`2.89%` for U+00C2. Devanagari and Arabic also improved.
- Parsed-face simple decoding now specializes its already-validated byte reader:
  it reads the final contour endpoint directly, omits repeated contour-order
  checks, and uses debug assertions instead of release-mode bounds branches for
  coordinate bytes. The mutation-aware owning decoder retains all checks.
  Against `d7edc2ef`, fixed-CPU-30 A/B/B/A instructions/branches/cycles fell
  `1.51%`/`2.01%`/`1.57%` for `A` and `2.15%`/`3.52%`/`2.09%` for `X`;
  Arabic also improved, while compound and Devanagari controls were neutral
  within cycle noise.
- The post-change fixed-CPU-30 `30000 * 7` two-size, two-interpreter, five-
  target matrix passed all 100 semantic rows and led every timing row. The
  narrowest row was DejaVu `A` at 9 ppem, v40 LCD: `1663.486/1682.563 ns`
  (`1.011x`); every `X` row now led by at least `1.045x`. This closes the
  maintained hinted-outline matrix, but broader glyph/platform evidence is
  still required for the overall FreeType claim.
- The FreeType differential now also covers a 499-byte DejaVu Serif Cyrillic
  program, a separate FreeSans Latin instruction style, and Annapurna SIL
  Devanagari across the retained interpreter/target gates. A first wider probe
  exposed unresolved Bengali/Tamil and Liberation Sans v40-mono mismatches;
  those are recorded as new open compatibility work rather than hidden behind
  the maintained matrix.
- The differential additionally walks all 94 printable ASCII characters in
  DejaVu Sans at 9 ppem under v35 normal, v40 normal, and v40 mono semantics
  (282 exact outline comparisons). An independent FreeType 2.14.3 run of the
  extended ten-font-case matrix across 8, 9, 12, 16, and 20 ppem also passed
  all 500 semantic rows. This broadens the Linux oracle evidence, but does not
  substitute for other operating systems or arbitrary installed fonts.
- The maintained `--extended` hinted-outline matrix now also covers ten Noto
  script fonts (Bengali, Tamil, Telugu, Kannada, Malayalam, Gujarati, Gurmukhi,
  Hebrew, Thai, and Khmer). At 9 and 16 ppem across both interpreters and all
  five targets, 396 system-FreeType semantic rows pass. Two v40 monochrome
  compound rows whose output changed in FreeType 2.14 are excluded from the
  system-2.13 matrix and remain gated by the version-aware differential.
- Probing beyond that retained corpus found further compatibility edges.
  DejaVu U+00B2 uses `SLOOP[0]`; matching FreeType requires accepting zero
  (and clamping oversized values to the 16-bit loop counter) rather than
  rejecting it. That behavior is now fixed and gated. DejaVu U+00C3 exposed a
  separate signed-rounding bug in its parent compound program: `ROUND[00]`
  incorrectly rounded `-96` to `-64`, so function 7's two `MSIRP` operations
  moved point 35 instead of point 20 before `IUP[X]`. Grid, half-grid, and
  double-grid modes now round a negative magnitude and restore its sign, as
  FreeType does. U+00C3 is retained in both the direct differential and the
  maintained performance matrix. A fixed-CPU-2 `1000 * 3` semantic smoke
  matched all ten 9 ppem v35/v40 target checksums; that sample count is not
  used as performance evidence. A full fixed-CPU-2 `30000 * 7` strict run
  matched all 120 maintained checksums, but two U+00C3 v40 rows were perturbed
  by host noise and failed the timing gate. Dedicated fixed-CPU-30 A/B/B/A
  `30000 * 11` reruns then led reproducibly: `1.138x--1.151x` for normal and
  `1.130x--1.146x` for light. Broader multilingual coverage remains open.
- Parsed `gvar` header and glyph-offset metadata is now retained by `Font` and
  threaded into immutable simple-glyph hint loads. This removes a whole-table
  offset scan per glyph. Against the independent pre-change binary, fixed-CPU-
  30 A/B/B/A counters for default-instance Cascadia `X` fell `69.67%` in
  instructions, `76.19%` in branches, and `65.18%` in cycles; non-variable
  DejaVu controls also improved through the later glyph-move work.
- The same immutable path now returns before allocating or decoding tuple
  payloads when every normalized coordinate is zero: OpenType tuple support is
  necessarily zero at the default location, and `Font.parse` has already
  validated the inactive payload grammar. Three fixed-CPU-30 A/B/B/A rounds
  against the retained-metadata binary reduced Cascadia `X` instructions,
  branches, and cycles by a further `6.85%`, `4.17%`, and `8.24%`; DejaVu
  Latin, Noto Devanagari, and Noto Arabic controls kept retired work flat.
- FreeType-style sign-symmetric RDTG/RUTG rounding fixes the newly exposed
  Bengali/Tamil mismatches: negative values round their magnitudes down/up and
  restore the sign, rather than using mathematical floor/ceil. Both scripts
  now remain in every v35/v40 target differential fixture. Liberation Sans
  v40 matches normal/light/LCD/LCD_V against FreeType 2.13 and mono against
  FreeType 2.14. FreeType 2.14 deliberately changed compound
  `ROUND_XY_TO_GRID` from an interpreter-version test to the actual v40
  compatibility state; Cangjie's rounded mono result matches the current
  behavior rather than 2.13's obsolete unrounded component X offset.
- Glyph-zone MDRP/MIRP now share one bounds/zone resolution and operate
  directly on glyph arrays when zp0/zp1 are both zone 1. Against the pre-change
  binary, fixed-CPU-30 A/B/B/A instructions/branches/cycles fell
  `5.86%`/`5.73%`/`3.23%` for `A`, `6.30%`/`7.15%`/`2.59%` for `X`, and
  `4.69%`/`4.59%`/`3.79%` for U+00C2; control scripts also improved.

An earlier strict `5 * 11` shaping run, using the runner's new
`--fail-on-slower` gate, measured speedups of `1.145x` (Roboto), `1.055x`
(Source Serif), `1.052x` (Amiri words), `1.109x` (Amiri long), and `1.054x`
(Devanagari). The Arabic improvement comes from routing a
cached merged plan directly through its already-proved accelerator sidecars;
against an independent baseline, Amiri-word retired instructions fell about
`2.68%`, branches `6.19%`, and cycles about `2.1%`, with unchanged output.
The smallest margins still warrant more corpus and platform evidence rather
than a universal shaping-performance claim. After borrowing chaining-group
records, using direct plan-cache slots, indexing larger production Arabic pair
sets, compacting short-context scratch, and isolating general matchers from the
hot frame, three consecutive latest strict runs pass all five rows. Amiri words
leads by `1.004x--1.008x`, and Devanagari by `1.010x--1.013x`; both remain
noise-sensitive rather than broad universal evidence.
The separate long mixed-code suite now measures both retained `react-dom.txt`
font rows. Consecutive fixed-CPU-30 symmetric `1 * 7` and `1 * 11` runs
measured `1.500x`/`1.522x` for Roboto and `1.525x`/`1.531x` for Source Serif
against the faster of HarfBuzz and HarfRust. This closes the missing-workload
instrumentation gap, but does not change the near-tie status of Amiri words.
The latest gated `1 * 11` rerun measured `1.526x` and `1.536x`;
`--fail-on-slower` now makes any non-winning row fail instead of remaining a
report-only result.
The performance runner's `broad` suite now adds the full English Little Prince
corpus for both Roboto and Source Serif. A fixed-CPU-30 symmetric `3 * 7`
strict run matched glyph counts and led the faster reference by `1.182x` and
`1.103x`. The same suite now retains Noto Nastaliq at an explicit `dflt`
language boundary, matching the unset DefaultLangSys policy used by both
references. This produces the same 83,486-glyph words corpus in all three
engines; Cangjie's default content-inferred `ara` policy intentionally produces
83,663 instead. The fair `dflt` performance rows expose a major remaining gap:
`0.495x` for words and `0.387x` for the long Persian corpus.

The Noto Nastaliq accelerator series through `c063dc63` adds complete
multi-record chaining-class actions, direct extension-wrapped contextual and
cardinality dispatch, nested sidecar reuse, contextual/chaining hash indexes,
and dense cached class definitions. The words workload still produces 83,486
glyphs with summary checksum `8a676da08b39950c`. A proposed adjacent-rule
hash path (`94d221f1`) was not retained: an independent fixed-CPU-30,
31-sample A/B/B/A comparison measured the candidate at
`3357.769/3338.305 ns/glyph` versus `3215.562/3293.985 ns/glyph` for the
pre-change binary. Commit `251df279` reverts that regression after the full
ReleaseFast test suite passed.

The post-revert fixed-CPU-30 strict reruns used the committed matrix harness
without weakening `--fail-on-slower`. The `broad` `3 * 7` run reported Noto
Nastaliq words at `0.544x` (`3369.452/3444.211 ns/glyph` for Cangjie versus
`1863.869/1841.613` HarfBuzz and `2876.697/2479.565` HarfRust), Noto long at
`0.502x` (`2159.815/2265.356` versus `1141.918/1077.753` and
`1439.479/1446.942`), Roboto long at `1.102x`, and Source Serif long at
`1.067x`. The strict `core` `5 * 11` run reported Roboto `1.175x`, Source
Serif `1.062x`, Amiri words `0.675x`, Amiri long `0.793x`, and Devanagari
`0.819x`. Both strict commands correctly failed. Host contention made these
absolute timings slower than several earlier snapshots, but the failures are
too large to claim overall shaping superiority and supersede the earlier
narrow all-core-win statement until a clean repeat proves otherwise.
Subsequent retained work makes the chaining hash decision from the largest
same-shape candidate bucket rather than the total class-set size
(`57936e3e`), adds a physical-adjacency ContextSubst path for proven runs
without default ignorables (`08d56288`), and builds bounded direct
glyph-to-glyph maps for compact SingleSubst tables (`197dc1ba`, compacted in
`671d5e17`). Independent fixed-CPU-30 A/B/B/A checks kept the Noto words
glyph count and checksum unchanged. The shape-density change measured
`3215.562/3293.985` versus `3140.760/3104.604 ns/glyph`; the compact single
map measured `3214.239/3210.327` versus `3104.134/3199.442 ns/glyph` and
also improved the Amiri words endpoints from `2392.762/2434.036` to
`2280.893/2310.760 ns/glyph`. These targeted gains do not supersede the
strict red rows above; a later broad run remained red on both Noto cases.

The next retained pair of changes records each ContextSubst group's shortest
input window and decodes class/hash prefixes only when the corresponding rule
length is probed (`44ac458b`), then adds an owned two-glyph ContextPos format-2
sidecar for direct and ExtensionPos lookups (`35d64472`). The latter avoids
reparsing the rule set, coverage, record, and nested-lookup index for Noto's
15-rule positioning lookup. A fixed-CPU-30, 31-sample A/B/B/A run kept
2,588,066 glyphs and checksum `512f7015bb79a7ef`; the pre-change medians were
`3135.072/3221.161 ns/glyph` and the candidate medians were
`3136.721/2999.310 ns/glyph`. Counter checks reduced retired instructions by
about 8.3% and branches by about 9.8%. A proposed direct second-class map for
one-lookahead chaining rules was not retained because its 31-sample result was
mixed (`3012.137/3066.766` baseline versus `3049.971/2953.314` candidate).

The next retained contextual-filtering change reuses the source decoder's
whole-run proof that no default-ignorable scalar exists. LookupFlag/GDEF
filtering still runs first; ordinary contextual glyphs then avoid repeated
source-index, Unicode-property, variation-selector, joiner, and substitution
checks. On Noto Nastaliq words, two fixed-CPU-30 symmetric 31-sample matrices
reduced the candidate median geometric mean by `3.02%` and `2.57%`
(`2.80%` across all eight endpoints), with identical 2,588,066-glyph output
and checksum `364f7db2b1d87607`. The long Persian corpus improved by `3.69%`
in A/B/B/A order and was within noise (`-0.78%`) in the reverse order, for a
`1.48%` aggregate reduction. A five-repeat counter run reduced retired
instructions by `1.46%` and branches by `2.71%`; branch misses and cycles were
noisy on the heavily loaded host. Full ReleaseFast tests and the retained
HarfBuzz/HarfRust corpus parity gate passed, including Noto words and long at
the explicit `dflt` language boundary. Two broader matcher experiments were
not retained: a homogeneous chaining-triplet matrix changed retired work by
less than one percent and was neutral on the long corpus, while a dedicated
two-input ContextSubst branch left retired work effectively unchanged and
regressed the symmetric wall-time aggregate.

The current post-`35d64472` strict fixed-CPU-30 matrices still fail without
weakening `--fail-on-slower`. Broad `3 * 7` reports Noto Nastaliq words at
`0.603x` and long text at `0.504x`; Roboto long (`1.127x`) and Source Serif
long (`1.064x`) pass. Core `5 * 11` reports Roboto at `1.302x`, but Source
Serif words at `0.979x`, Amiri words at `0.731x`, Amiri long at `0.872x`, and
Devanagari words at `0.918x`. These current red rows continue to rule out an
overall shaping-performance claim.

A subsequent group-local second-input class digest rejects impossible nested
ChainContextSubst format-2 candidates before entering the large noinline
matcher. The one-byte digest occupies existing `RuleGroup` padding, is disabled
for groups with any one-input alternative, and resolves logical inputs through
the same LookupFlag/default-ignorable/syllable traversal as exact matching.
Two fixed-CPU-30, 31-sample A/B/B/A plus reverse-order comparisons against the
independent `61ed9e2f` binary kept identical aggregate glyph counts and
checksums. Across all eight endpoints, Noto Nastaliq words improved by about
`1.99%` and the long Persian corpus by about `2.53%`; one forward words order
regressed by `1.49%`, so the aggregate and counter evidence—not that noisy
single ordering—justify retention. A ten-pass A/B/B/A counter run reduced
retired instructions by `0.59%`, branches by `0.66%`, branch misses by `0.52%`,
and cycles by `4.18%`. Full ReleaseFast tests and the complete retained
HarfBuzz/HarfRust corpus parity gate passed, including the Noto words and long
rows at `83,486`/`110,143` glyphs and checksums `fc28919889b8942b`/
`9e460d90b9034d46`. The post-change broad matrix still trails the faster
reference on Noto (`0.638x` words, `0.521x` long), so this is a measured
incremental gain rather than closure of the shaping-performance requirement.

Cached staged and merged plans now apply the already-built ligature and
coverage-only chaining first-input digests before crossing the unprofiled
lookup-executor boundary. The proof uses one unfiltered run-wide superset and
invalidates it with the shared glyph-mutation generation; class-based,
incomplete, unproved, and profiled paths remain unchanged. Production tables
now provision that generation even for one digest-capable ligature, while a
detached caller without an epoch conservatively bypasses the early rejection.
Fixed-CPU-30, 31-sample A/B/B/A comparisons against `188acf6a` retained
identical aggregate glyph counts and checksums and improved Amiri words by
`6.76%`, Amiri long by `2.28%`, Roboto words by `6.29%`, and Devanagari words
by `2.80%`. An earlier A/B/B/A plus reverse-order series before this final
generation guard likewise improved all four workloads in aggregate. A ten-pass
Amiri words counter run reduced retired instructions by `10.76%`, branches by
`2.72%`, branch misses by `0.19%`, and cycles by `12.56%`; Devanagari
instructions and branch misses also fell by `0.92%` and `0.98%` while branches
were effectively flat. Full ReleaseFast tests and the complete
HarfBuzz/HarfRust corpus parity gate passed. The subsequent strict core matrix
improved the observed rows but remained red for Amiri words/long
(`0.830x`/`0.870x`) and Devanagari (`0.955x`), so the cross-library
shaping-performance claim is still open.

A bounded ChainContextSubst format-1 sidecar now covers the common exact
two-input, optional-one-lookahead, one-record shape without reparsing the
Coverage/RuleSet/rule graph at every glyph. The accelerator is generic rather
than script-specific, preserves position-major authored subtable order, uses
the shared filtered traversal and safety marking, and falls back for the whole
lookup unless every subtable is supported. Its builder also scans complete
unsupported structures before falling back, so malformed tails cannot escape
atomic preflight. This activates for the HarfRust benchmark corpus's 136-rule
Noto Sans Devanagari lookup 41. Fixed-P-core-8 A/B/B/A plus reverse-order
31-sample comparisons improved the Devanagari aggregate by about `3.00%`;
retired instructions and branches fell `2.08%` and `1.69%` in the final
ten-pass A/B/B/A counter run. Branch misses rose by about `10.9%`, while cycles
improved `1.41%`; unrelated Amiri/Roboto retired work moved by less than one
percent. Full ReleaseFast tests and the complete HarfBuzz/HarfRust corpus
parity gate passed. A noisy concurrent core matrix is retained only as a
diagnostic—not superiority evidence—and still left Devanagari below the faster
reference, so further optimization remains necessary.

The current `f579e37f` snapshot was rerun on the same Linux x86-64 host and
fixed CPU 30 with the matrix's symmetric process order and its new enforced
`1.01x` minimum. Core `5 * 31` reported Roboto `1.440842x`, Source Serif
`1.013227x`, Amiri words `1.142873x`, Amiri long `1.501133x`, and Devanagari
`0.965414x`. Broad `3 * 31` reported Noto Nastaliq words `0.782152x`, Noto
Nastaliq long `0.614364x`, Roboto long `1.143029x`, and Source Serif long
`1.079957x`. All six process endpoints in each row agreed on normalized glyph
count. Several individual reference endpoints were visibly delayed by host
contention, so this run does not use the enlarged winning ratios as a stronger
claim; the stable, material Devanagari and Nastaliq deficits remain decisive.
The retained GPOS second-lookahead index nevertheless moved both Amiri rows
from the prior red snapshot to clear wins. Three later generic experiments
were rejected rather than retained: a four-input compact path was neutral on
retired work and `0.56%` slower on its Devanagari target, a first-lookahead
class digest improved Noto retired work but regressed the Devanagari control,
and predecoded CursivePos anchors reduced Noto retired work by less than half a
percent while leaving target wall time flat and regressing the Roboto control.

A later bounded GPOS completion now prepares MarkLigPos mark/ligature Coverage
indexes for direct and homogeneous ExtensionPos lookups, including exact nested
dispatch. It remains whole-corpus neutral, as expected for Noto lookup 13's
small share. ContextSubst's hash matcher also now starts at each group's
already-proven minimum input length rather than binary-searching impossible
shorter prefix hashes. Fixed-CPU-30 five-pass counters fell by about
`0.72%` instructions/`1.00%` branches on Noto words and `0.97%`/`1.26%` on
long prose; 31-sample timing was noise-scale (`1.0030x`/`1.0016x`). The latest
post-change broad report-only sample remains red at `0.825879x` and `0.667667x`
for Noto words/long, while Roboto and Source Serif long remain wins. A separate
attempt to reuse the chaining second-input digest in the top-level loop was
rejected after Noto regressed about `0.24--0.44%` and Roboto showed a material
code-layout regression. An exact dense ContextSubst second-class index was also
rejected: it reduced branch counts but did not reduce Noto words instructions
and regressed controls. These experiments are not superiority evidence; the
Noto gap remains open.

The subsequent fixed-CPU-30 strict broad gate (`3 * 31`, explicit `1.01x`
minimum) confirms that conclusion on the committed minimum-length optimization:
Noto Nastaliq words and long remain below the fastest reference at `0.834112x`
and `0.670056x`; Roboto long and Source Serif long pass at `1.151490x` and
`1.075064x`. All six endpoints in every row retain identical normalized glyph
counts. The strict command therefore fails exactly the two Noto rows rather
than being treated as a completed shaping-performance claim.

A follow-up LigatureSubst audit found that the large required-second digest
prefilter assumed physical adjacency even when LookupFlag filtering or
default-ignorable traversal could make two logical components nonadjacent. The
prefilter now uses physical pairs only under the flag-free/no-default-ignorable
proof and otherwise performs a conservative whole-run digest test; malformed
optional digest/range metadata falls back to the canonical decoded matcher. A
129-definition IgnoreMarks regression covers the digest threshold and retains
the intervening mark. A separate exact two-glyph pair-index prototype was
rejected: its final defensive implementation regressed fixed-CPU-30 symmetric
Noto words and long runs by roughly 14--16%, despite identical glyph counts and
checksums. It was fully removed rather than treated as progress.

## Audit rules

1. A semantic manifest proves inventory only; it is not a differential test.
2. Stable self-checksums prove determinism only; cross-library layout claims
   require normalized comparable outputs.
3. Performance rows must compare the same work and lifecycle. Cache/prepared
   paths cannot replace cold or owning rows.
4. A row is a win only when repeated symmetric runs clear a declared noise
   margin; a `0.997x` or `1.001x` observation is a tie, not superiority. The
   shaping matrix makes that margin reproducible with `--minimum-speedup`
   (default `1.01x`): `--fail-on-slower` rejects every row below the declared
   threshold, while an exact-boundary result passes. Without the fail flag,
   the same threshold result remains visible but report-only.
5. Every retained optimization must preserve the full ReleaseFast suite and
   all applicable reference-parity gates.
6. The overall claim may be made only after every open row above has concrete,
   reproducible evidence.

## Current conclusion

Cangjie has exact semantic agreement across the maintained 33-case
Fontations/Skrifa matrix, and every retained row currently leads its matched
reference lifecycle, including the eight real VARC rows. Broader semantic
coverage is still open, so no overall Fontations claim is made. Cangjie is ahead
in the complete maintained 75-row FreeType grayscale lifecycle matrix. The
latest strict Parley performance run covers all 38 maintained rows under the
explicit `1.01x` gate and remains red on the twenty rows recorded above. Its
semantic side passes all 17 required text geometry/direction/placement rows and
all 18 object-geometry rows, including both phases of both mixed-bidi fixtures.
This evidence is
substantial but does not satisfy the stronger overall claim. In particular,
the latest shaping runs still trail the faster reference on Noto Nastaliq and
Devanagari; both Amiri rows now clear the declared margin. The
FreeType-equivalent face opening now
leads, while complete eager validation is reported separately. Broader hinting
targets and more glyphs remain uncovered. SVG still needs a separate renderer
reference, and COLRv1 coverage is represented by the bounded matrix below
rather than a broad renderer claim. Parley's maintained semantic gate passes,
but broader semantic/platform coverage and the twenty strict performance deficits
remain open.

### COLRv1 pixel differential

`zig build colrv1-pixel-matrix -Doptimize=ReleaseFast` compares ten retained
COLRv1 scenes against an independent Skrifa 0.45.2 plus tiny-skia 0.12.0
adapter. The corpus covers pad and repeat linear gradients, radial and sweep
gradients, nested transforms, isolated compositing, clip-box compositing,
PaintColrGlyph recursion, layers, and variable alpha at default and non-default
locations. Both sides emit premultiplied RGBA8 on the same 128x128 canvas.

The runner enforces byte-exact full-image equality for the linear-pad and
composite cases. Away from reference geometry-coverage boundaries every other
case differs by at most one byte per channel. Because the rasterizers use
independent scan conversion, the Skrifa adapter emits a sidecar mask built from
path and clip coverage before brush shading. The runner bounds that fringe per
pixel (`max <= 160`, mean L-infinity channel error `<= 30`); it also rejects
masks covering over half the canvas. The 30-byte mean ceiling is just above the
worst retained coverage disagreement (linear-repeat at `29.094`) rather than a
whole-image tolerance. Gradient color slopes never create fringe pixels, and
candidate output cannot expand the reference mask. Synthetic negative tests
prove that a one-pixel geometry shift, reversed steep gradient, broad color
error, and candidate-created hard edges all fail the strict interior gate.

The oracle's adapter follows Skrifa's documented painter protocol rather than
Cangjie's paint implementation: matrix concatenation is `current * child`;
PaintGlyph's optional brush transform is not applied twice; PaintColrGlyph is
left to Skrifa's cycle-checked recursive traversal; composite callbacks use
the emitted outer isolation layer plus inner authored mode; and the sweep
shader receives a center-preserving y reflection to reconcile tiny-skia's
unit-angle coordinate convention with the y-up font transform.

### GPOS contextual recursion bound

Runtime GPOS execution now caps every `PosLookupRecord` call stack at sixteen
edges, matching the structural-validation boundary. The generic nested
dispatcher and the accelerated ChainContextPos-to-SinglePos path share one
checked entry helper, so a hostile caller-supplied depth cannot overflow and
the seventeenth edge is rejected with the existing `UnsupportedGpos` contract
before lookup parsing or adjustment mutation. Direct and ExtensionPos-wrapped
self cycles, the exact sixteenth-edge boundary, the accelerated bypass, and
recursive validation all have focused regression coverage.
The post-change `zig test src/gpos.zig -OReleaseFast` run passed all 378 tests;
the full ReleaseFast project suite and the 2,946-case ReleaseSafe malformed-font
smoke harness passed as well. The retained HarfBuzz 14.3/HarfRust shaping
parity matrix also passed with the pinned HarfBuzz prefix.
