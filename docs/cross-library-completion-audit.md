# Cross-library completion audit

The project goal is an evidence-backed claim that Cangjie exceeds FreeType,
HarfBuzz, Fontations/Skrifa, and Parley in both relevant functionality and
performance. This is intentionally stronger than passing unit tests or winning
one benchmark. The claim remains **open** until every row below is closed.

## Required evidence

| Reference | Concrete completion criterion | Current artifact/evidence | Status |
| --- | --- | --- | --- |
| HarfBuzz | Exact glyph IDs, clusters, advances, offsets, and relevant flags across retained upstream and production-font corpora | `shaping-parity-smoke`, `shaping-corpus-parity-smoke`, `tests/data/`, `docs/shaping-parity.md` | Strong retained coverage, not exhaustive |
| HarfBuzz/HarfRust | Faster than the faster reference on every representative shaping workload, with independent binaries, pinned CPU, symmetric order, and repeatable margin | `shaping-performance-matrix` | Open: all five maintained core rows now lead (`1.052x--1.145x` in the latest strict run) and `react-dom.txt` leads by more than `1.50x`; broader font/script coverage remains incomplete |
| Fontations/Skrifa | Every pinned public table/API family mapped to a live test; shared high-level operations semantically equivalent and faster at matched lifecycle boundaries | `docs/fontations-coverage.json`, `fontations-coverage`, `fontations-matrix` | Inventory complete; all 25 maintained rows, including variable-CFF2 default/axis-endpoint owning and reuse outlines, lead; broader semantic differentials remain open |
| FreeType | Correct outline/hinting/bitmap behavior plus faster matched cold, owning, reused, and prepared raster lifecycles across glyf/CFF/CFF2, bitmap/color, representative scripts, and sizes | `hinting-freetype-test`, `hinted-outline-matrix`, `glyph-bench`, `freetype-matrix`, raster evidence in `docs/shaping-parity.md` | Open: all 75 maintained grayscale raster rows, all 10 native-strike bitmap rows, the shared COLRv0 layer/CPAL row, all five matched face-open rows, and the expanded 100-row hinted-outline matrix lead. Complete eager validation is separately reported and remains slower, COLRv1/SVG have no FreeType built-in renderer for direct performance comparison, and broader glyph/platform coverage remains incomplete |
| Parley | Equivalent paragraph layout results—not only counts—and faster default/styled/reflow paths for Latin, Arabic, CJK, bidi, vertical, fallback, and inline-object workloads | `parley-matrix`, paragraph/reflow tests, `docs/text-pipeline.md` | Open: the maintained 32-row matrix covers three scripts, three construction styles, retained reflow, matched in-flow/ordinary/custom out-of-flow objects, and mixed Roboto→Noto Sans Devanagari fallback. All 18 object rows prove identical id/source/line/position/size/baseline geometry at fractional coordinates. Custom construction leads, but retained custom placement still trails on Latin/Arabic and is near noise on Japanese; vertical and remaining structural differences are open |
| Robustness | Malformed supported inputs fail atomically under safety checks and sustained coverage-guided fuzzing | `font-fuzz-smoke`, `font-fuzz`, regression fixtures | Open: the retained 100K campaign is useful evidence, not exhaustive format coverage |
| Platform scope | Results reproduced on each supported target or the performance claim explicitly scoped to named hardware/OS/toolchain versions | benchmark documentation | Open: current performance evidence is primarily one Linux x86-64 host |

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
- The optional Fontations `--extended` outline corpus now includes all ten
  selected semantically identical glyphs from the larger two-axis
  `AdobeVFPrototype.otf`, in both owning and caller-storage modes. The original
  fixed-CPU-30 `1000 * 7` run led all ten initial CFF2 rows
  (`1.065x--1127x`). Cangjie's Type2 path builder now canonicalizes a final
  explicit line back to the contour origin into the following close operation,
  matching Skrifa and admitting glyphs 20, 64, 128, and 192 to the matrix.
  Raising the CFF2 operand stack to the format's 513-entry limit also admits
  glyph 2's large blend program. A `1000 * 7` semantic/performance run of the
  resulting 125-row extended matrix confirmed every checksum. All CFF2 reuse
  rows led; owning glyphs 20 and 128 remained slower, alongside existing glyf
  owning deficits, so this extended corpus is not yet a strict performance
  pass.
- `zig build parley-matrix -Doptimize=ReleaseFast -- --iterations 1000 --samples
  7 --cpu 30 --fail-on-slower`: the 26-row matrix passed before custom
  placement was added. The current 32-row semantic matrix passes, including
  exact normalized object geometry in all 18 object rows. The added ordinary
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
  `1.413x`/`1.013x`/`1.381x`. The in-flow Arabic object row remains just behind
  at `0.978x`, so the strict gate is still red.
  The mixed Roboto→Noto Sans Devanagari fallback rows also have identical
  normalized geometry. Extending the retained simple-path proof to adjacent
  multi-glyph clusters moved fallback construction/reflow to `1.664x`/`1.718x`
  in the latest run.
- `zig build font-fuzz-smoke -Doptimize=ReleaseSafe -- ...`: six retained
  bitmap/color/container seeds and 3,084 deterministic mutations passed in the
  latest bitmap-audit rerun.
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
- `font-fuzz-smoke` over six external HarfBuzz fuzz seeds covering CFF2+COLR
  v1, CBDT, sbix, SVG, variable CFF2, and malformed CBDT PNG completed 3,084
  deterministic ReleaseSafe cases through the expanded driver without a
  failure.
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
- Probing beyond that retained corpus found two further compatibility edges.
  DejaVu U+00B2 uses `SLOOP[0]`; matching FreeType requires accepting zero
  (and clamping oversized values to the 16-bit loop counter) rather than
  rejecting it. That behavior is now fixed and gated. A separate experimental
  U+00C3 sweep was not retained because it mixed parent compound-IUP coordinate
  domains and regressed existing cases; broader multilingual coverage remains
  open.
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

The latest strict `5 * 11` shaping run, using the runner's new
`--fail-on-slower` gate, measured speedups of `1.145x` (Roboto), `1.055x`
(Source Serif), `1.052x` (Amiri words), `1.109x` (Amiri long), and `1.054x`
(Devanagari). The Arabic improvement comes from routing a
cached merged plan directly through its already-proved accelerator sidecars;
against an independent baseline, Amiri-word retired instructions fell about
`2.68%`, branches `6.19%`, and cycles about `2.1%`, with unchanged output.
The smallest margins still warrant more corpus and platform evidence rather
than a universal shaping-performance claim.
The separate long mixed-code suite now measures both retained `react-dom.txt`
font rows. Consecutive fixed-CPU-30 symmetric `1 * 7` and `1 * 11` runs
measured `1.500x`/`1.522x` for Roboto and `1.525x`/`1.531x` for Source Serif
against the faster of HarfBuzz and HarfRust. This closes the missing-workload
instrumentation gap, but does not change the near-tie status of Amiri words.
The latest gated `1 * 11` rerun measured `1.526x` and `1.536x`;
`--fail-on-slower` now makes any non-winning row fail instead of remaining a
report-only result.

## Audit rules

1. A semantic manifest proves inventory only; it is not a differential test.
2. Stable self-checksums prove determinism only; cross-library layout claims
   require normalized comparable outputs.
3. Performance rows must compare the same work and lifecycle. Cache/prepared
   paths cannot replace cold or owning rows.
4. A row is a win only when repeated symmetric runs clear a declared noise
   margin; a `0.997x` or `1.001x` observation is a tie, not superiority.
5. Every retained optimization must preserve the full ReleaseFast suite and
   all applicable reference-parity gates.
6. The overall claim may be made only after every open row above has concrete,
   reproducible evidence.

## Current conclusion

Cangjie is already ahead in the maintained 25-case Fontations/Skrifa matrix
and complete maintained 75-row FreeType grayscale lifecycle matrix, plus most
of the five-corpus shaping matrix. The corrected Parley timing matrix now leads
all 18 rows, including all six retained-reflow rows. This evidence is
substantial but does not satisfy the stronger overall claim. In particular,
the latest shaping runs lead all five maintained rows, but Amiri words and
Devanagari remain narrow single-font/corpus results. The
FreeType-equivalent face opening now leads, while complete eager validation is
reported separately. Broader hinting targets and more glyphs remain uncovered,
and COLRv1/SVG need a separate renderer reference. Parley semantic matrices
also remain incomplete.
