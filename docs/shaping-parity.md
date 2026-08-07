# Shaping Parity And Performance Targets

Cangjie should not be described as exceeding industry implementations until the
claim is backed by both correctness and performance evidence. This document is
the working checklist for that bar.

## Reference Implementations

Local references to inspect before non-trivial shaping changes:

- `/Users/bytedance/Work/harfbuzz`
- `/Users/bytedance/Work/harfrust`
- `/Users/bytedance/Work/fontations`
- `/Users/bytedance/Work/freetype`

Use HarfBuzz as the primary shaping semantics reference. Use fontations for
modern table parsing structure, harfrust for the benchmark corpus and Rust
porting choices, and FreeType for font loading, legacy `kern`, and raster/font
infrastructure boundaries.

## Completion Bar

The goal is not complete until all of these are true:

- Correctness: Cangjie matches the reference output, or every intentional
  difference is documented, for the benchmark corpus and a broader script/font
  fixture set.
- Performance: Cangjie is faster than the strongest local reference on the
  same host for representative long text and word-list workloads, not only for
  isolated micro-cases.
- Coverage: GSUB, GPOS, GDEF, cmap, variation selector, feature override,
  script/language selection, legacy `kern`, and relevant variable-font behavior
  have explicit test or corpus coverage.
- Robustness: malformed supported tables are rejected before partial shaping
  results leak, and fuzz/corpus failures have stable regression tests.
- Structure: hot-path optimizations keep parsing, caching, layout, and
  benchmark/reporting concerns separated enough that large files do not keep
  absorbing unrelated logic.

## Current Required Benchmarks

Run these after shaping hot-path changes:

```sh
zig build test
zig build shape-bench -Doptimize=ReleaseFast -- --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file /Users/bytedance/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file /Users/bytedance/Work/harfrust/harfrust/benches/texts/fa-words.txt --direction rtl --iterations 1 --warmup 2 --samples 5
zig build shape-bench -Doptimize=ReleaseFast -- --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf --text-file /Users/bytedance/Work/harfrust/harfrust/benches/texts/en-words.txt --direction ltr --iterations 1 --warmup 1 --samples 2
zig build shape-bench -Doptimize=ReleaseFast -- --engine coretext --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text-file /Users/bytedance/Work/harfrust/harfrust/benches/texts/fa-thelittleprince.txt --direction rtl --iterations 1 --warmup 2 --samples 5
```

Use `--profile` for targeting only. Profile mode applies Arabic GSUB feature
stages separately, so it is not the final performance number for the cached
feature-plan hot path.

For output parity against HarfRust, build the local CLI once:

```sh
(cd /Users/bytedance/Work/harfrust && cargo build --release -p hr-shape)
zig build shape-bench -Doptimize=ReleaseFast -- --engine harfrust --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام" --direction rtl --iterations 1 --warmup 0 --samples 1 --line-summary --glyph-summary
zig build shape-bench -Doptimize=ReleaseFast -- --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام" --direction rtl --iterations 1 --warmup 0 --samples 1 --line-summary --glyph-summary
zig build shape-bench -Doptimize=ReleaseFast -- --engine compare-harfrust --font /Users/bytedance/Work/harfrust/harfrust/benches/fonts/Amiri-Regular.ttf --text "سلام" --direction rtl
```

The `harfrust` engine shells out to `hr-shape` once per sample and uses
`hr-shape -n` for measured iterations. It is useful for batch output parity and
rough timing against HarfRust, but still includes external process startup and
serialization/parsing overhead. A library runner is still needed for strict
HarfRust/HarfBuzz timing.

`compare-harfrust` runs Cangjie and HarfRust in the same invocation and compares
per-line glyph-id, UTF-8 cluster, font-unit x/y advance, and x/y offset
sequences in HarfBuzz-style buffer order. When `--language` is not specified,
compare mode forces Cangjie to `dflt` because the current `hr-shape` runner
guesses script and direction but does not guess language. Pass `--language ara`,
`--language zhs`, etc. to compare an explicit LangSys on both engines.

## Current Evidence Snapshot

Latest retained optimization commit before this parity work:

- `266a5ec Fast path accelerated GSUB context records`

Representative performance state near that commit:

- Amiri `fa-thelittleprince`, Cangjie: about `1705 ns/glyph` median.
- Amiri `fa-words`, Cangjie: about `1970 ns/glyph` median.
- Roboto `en-words`, Cangjie: about `1118 ns/glyph` median.
- Amiri `fa-thelittleprince`, CoreText: about `1233 ns/glyph` median.

Current local snapshot after the Nastaliq parity work:

- Amiri `fa-thelittleprince`, Cangjie default visual-order path: about
  `2084 ns/glyph` median after reusing GPOS range-search helpers and skipping
  repeated first-input coverage checks in accelerated GSUB chaining format 3
  subtables.
- Amiri `fa-thelittleprince`, Cangjie with `--no-bidi-reorder`: about
  `1585 ns/glyph` median.
- Amiri `fa-thelittleprince`, CoreText: about `1263 ns/glyph` median.
- HarfRust Criterion in-process reference for Amiri `fa-thelittleprince`:
  about `48.2 ms` per full text for HarfRust and `54.9 ms` for HarfBuzz
  through `harfbuzz_rs`; Cangjie remains multiple times slower on the same
  workload, so the performance goal is not close to complete.
- A profile run after the GPOS range-search change reduced Amiri
  `fa-thelittleprince` GPOS time from about `155 ms` to about `111 ms`; lookup
  `74` fell from about `24.4 ms` to `5.7 ms`, and lookup `57` from about
  `21.0 ms` to `6.1 ms`. The host was not fully idle, so use this as hotspot
  direction rather than a final headline benchmark.
- A later profile run after the accelerated GSUB chaining format 3 fast path
  reduced Amiri `fa-thelittleprince` GSUB profile time from about `308 ms` to
  about `257 ms`; the Arabic `calt` stage fell from about `207 ms` to
  `172 ms`.

Current HarfRust glyph-id, UTF-8 cluster, advance, and offset parity evidence:

- Amiri `"آیت‌الله"` passes `compare-harfrust`.
- Amiri `"اللَّهِ"` passes `compare-harfrust`.
- Amiri `"تثبیت"` passes default `compare-harfrust`; it also passes with
  `--language ara`.
- Amiri `fa-words.txt` passes default `compare-harfrust` for 10,000 lines.
- Roboto `en-words.txt` passes `compare-harfrust` for 12,391 lines.
- SourceSerifVariable `en-words.txt` passes `compare-harfrust` for 12,391
  lines.
- SourceSerifVariable `en-thelittleprince.txt` passes `compare-harfrust` for
  1,172 lines.
- Amiri `fa-thelittleprince.txt` passes default `compare-harfrust` for 771
  lines.
- NotoNastaliqUrdu `fa-words.txt` passes `compare-harfrust` for 10,000 lines,
  and `fa-thelittleprince.txt` passes for 771 lines; focused blockers `"سلام"`,
  `"به"`, `"ویکی‌پدیا"`, `"هجری"`, `"جزء"`, `"اللَّهِ"`, and `"اللَّهُ"` pass
  individually.
- NotoSansDevanagari parses and focused words `के`, `कि`, `की`, `का`,
  `श्रेणी`, `वार्ता`, `वर्षों`, `उत्तराखण्ड`, `हिन्दी`, `द्वारा`, `रूप`,
  `फ़िल्म`, `क्षेत्र`, `स्थित`, `एक्स्प्रेस`, `सन्`, `व्यक्ति`, `ा`,
  `अंग्रेज़ी`, `सिद्धांत`, `पुनः`, `ज़्यादा`, `सन्‌`, `ि`, `अवार्ड्स`,
  `वर्ल्ड`, `चार्ल्स`, `्य`, `स्‍थान`, `ब्रिटिश`, `स्वागत`, `द्वितीय`, and
  `ट्विटर`, `वैश्विक`, `श्वि`, `क्वि`, and `ट्वि` pass `compare-harfrust`.
- NotoSansDevanagari `hi-words.txt` passes `compare-harfrust` for 10,000
  lines.

Conclusion: Arabic long text still trails CoreText substantially. The broad
goal is active, not complete.

## Near-Term Gaps

- Add a library-level HarfBuzz or HarfRust comparison runner so CoreText is not
  the only external timing baseline. The current `harfrust` `shape-bench`
  engine is a batch external-process baseline, not a fully fair in-process
  performance baseline.
- Expand the benchmark matrix beyond Amiri, Roboto, SourceSerifVariable,
  NotoNastaliqUrdu, and the active Devanagari gate; broader Arabic, Urdu,
  Nastaliq, and mixed-script texts still need retained parity coverage.
- Track output parity, not only timing. `compare-harfrust` now compares glyph
  ids, clusters, advances, and offsets in HarfBuzz-style buffer order; feature
  override and broader font/script matrices still need expansion.
- Expand the new Indic shaper slice beyond the current Devanagari `nukt`,
  `akhn`, `rphf`, `rkrf`, `half`, `cjct`, `pres`, `abvs`, `blws`, and `psts`
  stages; the current `hi-words.txt` gate only covers the active Devanagari
  word corpus, not full HarfBuzz Indic script parity.
- Continue Arabic hot-path work from measured profile evidence:
  GSUB `calt` context lookups, GPOS lookup `37`, and the remaining mark/cursive
  paths after the shared range-search cleanup.
- Avoid retaining optimizations that only improve a single noisy run or regress
  Roboto/word-list smoke cases.
