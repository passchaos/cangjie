# Cross-library completion audit

The project goal is an evidence-backed claim that Cangjie exceeds FreeType,
HarfBuzz, Fontations/Skrifa, and Parley in both relevant functionality and
performance. This is intentionally stronger than passing unit tests or winning
one benchmark. The claim remains **open** until every row below is closed.

## Required evidence

| Reference | Concrete completion criterion | Current artifact/evidence | Status |
| --- | --- | --- | --- |
| HarfBuzz | Exact glyph IDs, clusters, advances, offsets, and relevant flags across retained upstream and production-font corpora | `shaping-parity-smoke`, `shaping-corpus-parity-smoke`, `tests/data/`, `docs/shaping-parity.md` | Strong retained coverage, not exhaustive |
| HarfBuzz/HarfRust | Faster than the faster reference on every representative shaping workload, with independent binaries, pinned CPU, symmetric order, and repeatable margin | `shaping-performance-matrix` | Open: all five maintained core rows now lead (`1.014x--1.216x`) and `react-dom.txt` leads by more than `1.50x`; Amiri words and Devanagari still have narrow margins, and broader font/script coverage remains incomplete |
| Fontations/Skrifa | Every pinned public table/API family mapped to a live test; shared high-level operations semantically equivalent and faster at matched lifecycle boundaries | `docs/fontations-coverage.json`, `fontations-coverage`, `fontations-matrix` | Inventory complete; all 25 maintained rows, including variable-CFF2 default/axis-endpoint owning and reuse outlines, lead; broader semantic differentials remain open |
| FreeType | Correct outline/hinting/bitmap behavior plus faster matched cold, owning, reused, and prepared raster lifecycles across glyf/CFF/CFF2, bitmap/color, representative scripts, and sizes | `hinting-freetype-test`, `glyph-bench`, `freetype-matrix`, raster evidence in `docs/shaping-parity.md` | Open: all 75 maintained grayscale glyf/CFF1/CFF2 raster rows and all 10 native-strike CBDT/sbix decoded-pixel rows lead; the five-font cold in-memory face rows expose large parsing deficits, and COLR/SVG, broader hinting-target/glyph coverage, plus additional platforms remain incomplete |
| Parley | Equivalent paragraph layout results—not only counts—and faster default/styled/reflow paths for Latin, Arabic, CJK, bidi, vertical, fallback, and inline-object workloads | `parley-matrix`, paragraph/reflow tests, `docs/text-pipeline.md` | Open: the maintained 18-row matrix covers three scripts, three construction styles, retained reflow, and matched in-flow inline objects and now leads every performance row; logical-line normalization proves 9/18 geometry rows equivalent, while vertical, fallback, out-of-flow, and the remaining structural geometry differences are not comparable |
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
  --samples 7 --cpu 30`: 25/25 semantic rows passed; every measured row
  favored Cangjie (`1.252x--13.865x` in the latest run). The real
  variable-CFF2 rows require identical normalized FNV command streams and
  cover default owning output (`1.252x`), retained caller storage (`13.814x`),
  and owning output at normalized `wght` endpoints `+1`/`-1`
  (`1.317x`/`1.336x`). Caller-owned reuse at those endpoints leads by
  `13.865x`/`13.763x`.
- `zig build parley-matrix -Doptimize=ReleaseFast -- --iterations 1000 --samples
  7 --cpu 30`: 18/18 count/stability rows passed. After removing Parley's
  timed O(n) semantic-summary walk to match Cangjie's O(1) timed consumer,
  Cangjie leads all 18 rows. Default Latin, Arabic, and Japanese retained reflow
  lead by `1.524x`, `1.231x`, and `1.561x`; their inline-object counterparts
  lead by `1.325x`, `1.029x`, and `1.358x`. Arabic default, spacing,
  alternating, and inline-object construction lead by `1.191x`, `1.169x`,
  `1.238x`, and `1.214x`; Japanese spacing leads by `1.801x`. Retaining exact
  text-only UAX #29/#14 analysis moves Japanese alternating construction to a
  reproducible `1.112x` lead. Logical-line geometry agrees
  on 9/18 rows after preserving source ranges, advances, and relative cluster
  placement while discarding only a per-line translation and sub-1/1024 px
  accumulation noise.
- `zig build font-fuzz-smoke -Doptimize=ReleaseSafe -- ...`: six retained
  bitmap/color/container seeds and 3,084 deterministic mutations passed in the
  latest bitmap-audit rerun.
- `zig build font-fuzz -Doptimize=ReleaseSafe --fuzz=100K`: the selected
  parser/render target completed 269,563 executions, 2,467 unique runs, and
  4,331/32,005 instrumented edges (13.53%) without a reported failure.
- `font-fuzz-smoke` over six external HarfBuzz fuzz seeds covering CFF2+COLR
  v1, CBDT, sbix, SVG, variable CFF2, and malformed CBDT PNG completed 3,084
  deterministic ReleaseSafe cases without a failure.
- `zig build freetype-matrix -Doptimize=ReleaseFast -- --iterations 100
  --samples 5 --sizes 8,16,32,64,128 --cpu 30`: completed 40 symmetric
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

The latest strict `10 * 21` shaping run measured speedups of `1.216x`
(Roboto), `1.084x` (Source Serif), `1.046x` (Amiri words), `1.112x` (Amiri
long), and `1.014x` (Devanagari). The Arabic improvement comes from routing a
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
FreeType cold parsing remains a concrete performance blocker; COLR/SVG, broader
hinting targets, and more glyphs remain uncovered. Parley semantic matrices
also remain incomplete.
