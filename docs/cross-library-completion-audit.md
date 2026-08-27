# Cross-library completion audit

The project goal is an evidence-backed claim that Cangjie exceeds FreeType,
HarfBuzz, Fontations/Skrifa, and Parley in both relevant functionality and
performance. This is intentionally stronger than passing unit tests or winning
one benchmark. The claim remains **open** until every row below is closed.

## Required evidence

| Reference | Concrete completion criterion | Current artifact/evidence | Status |
| --- | --- | --- | --- |
| HarfBuzz | Exact glyph IDs, clusters, advances, offsets, and relevant flags across retained upstream and production-font corpora | `shaping-parity-smoke`, `shaping-corpus-parity-smoke`, `tests/data/`, `docs/shaping-parity.md` | Strong retained coverage, not exhaustive |
| HarfBuzz/HarfRust | Faster than the faster reference on every representative shaping workload, with independent binaries, pinned CPU, symmetric order, and repeatable margin | `shaping-performance-matrix` | Open: `react-dom.txt` is now covered and leads by more than `1.50x`, while Amiri words remains a near tie and therefore does not establish superiority |
| Fontations/Skrifa | Every pinned public table/API family mapped to a live test; shared high-level operations semantically equivalent and faster at matched lifecycle boundaries | `docs/fontations-coverage.json`, `fontations-coverage`, `fontations-matrix` | Inventory complete; all 25 maintained rows, including variable-CFF2 default/axis-endpoint owning and reuse outlines, lead; broader semantic differentials remain open |
| FreeType | Correct outline/hinting/bitmap behavior plus faster matched cold, owning, reused, and prepared raster lifecycles across glyf/CFF/CFF2, bitmap/color, representative scripts, and sizes | `hinting-freetype-test`, `glyph-bench`, `freetype-matrix`, raster evidence in `docs/shaping-parity.md` | Open: all 75 maintained grayscale glyf/CFF1/CFF2 lifecycle rows now lead, while bitmap/color, hinting-target, cold parse, broader glyph coverage, and additional platforms remain incomplete |
| Parley | Equivalent paragraph layout results—not only counts—and faster default/styled/reflow paths for Latin, Arabic, CJK, bidi, vertical, fallback, and inline-object workloads | `parley-matrix`, paragraph/reflow tests, `docs/text-pipeline.md` | Open: the 18-row matrix covers three scripts, three construction styles, retained reflow, and matched in-flow inline objects; logical-line normalization proves 9/18 geometry rows equivalent; retained paragraph state and a narrowly proved simple-reflow path raise the corrected timing matrix to 9/18 performance rows ahead, while inline-object reflow and several styled construction rows remain gaps; vertical, fallback, and out-of-flow modes are not comparable |
| Robustness | Malformed supported inputs fail atomically under safety checks and sustained coverage-guided fuzzing | `font-fuzz-smoke`, `font-fuzz`, regression fixtures | Open: the retained 100K campaign is useful evidence, not exhaustive format coverage |
| Platform scope | Results reproduced on each supported target or the performance claim explicitly scoped to named hardware/OS/toolchain versions | benchmark documentation | Open: current performance evidence is primarily one Linux x86-64 host |

## Reproducible audit snapshot

The following checks were rerun for the audited state described below on Linux
x86-64, pinned to CPU 30 where the harness supports it:

- `zig build test -j1 -Doptimize=ReleaseFast --summary failures`: pass.
- `zig build shaping-parity-smoke ... --summary none`: pass against the local
  HarfBuzz 14.3 and HarfRust references.
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
  Cangjie leads 9/18 rows. Default Latin, Arabic, and Japanese retained reflow
  now lead by `1.375x`, `1.036x`, and `1.489x`; inline-object reflow and
  Arabic/Japanese styled construction remain performance gaps. Logical-line geometry agrees
  on 9/18 rows after preserving source ranges, advances, and relative cluster
  placement while discarding only a per-line translation and sub-1/1024 px
  accumulation noise.
- `zig build font-fuzz-smoke -Doptimize=ReleaseSafe -- ...`: six retained
  seeds and 2,946 deterministic mutations passed.
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

The latest strict shaping run at `077cb97e` measured speedups of `1.213x`
(Roboto), `1.042x` (Source Serif), `0.994x` (Amiri words), `1.083x` (Amiri
long), and `1.001x` (Devanagari). An empty cached merged-stage optimization
then reduced Amiri-word retired instructions/branches/cycles by about
`1.23%`/`1.26%`/`1.43%`; a subsequent strict run measured `1.006x`, but this
remains inside the audit's noise margin rather than a proven stable lead.
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
9/18 rows, including all three default retained-reflow rows, but the remaining
nine rows still make Parley an explicit performance blocker. This
evidence is substantial but does not satisfy the stronger overall claim. In particular,
the latest shaping runs still place Amiri words near parity; Devanagari now
leads the retained row by about `1.03x`, but that is only one font/corpus. The
broader FreeType bitmap/color/hinting/cold-parse coverage and Parley semantic
matrices remain incomplete.
