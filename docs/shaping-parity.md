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

Current HarfRust glyph-id, UTF-8 cluster, advance, and offset parity evidence:

- Amiri `"آیت‌الله"` passes `compare-harfrust`.
- Amiri `"اللَّهِ"` passes `compare-harfrust`.
- Amiri `"تثبیت"` passes default `compare-harfrust`; it also passes with
  `--language ara`.
- Amiri `fa-words.txt` passes default `compare-harfrust` for 10,000 lines.
- Roboto `en-words.txt` passes `compare-harfrust` for 12,391 lines.
- Amiri `fa-thelittleprince.txt` passes default `compare-harfrust` for 771
  lines.
- NotoSansDevanagari parses and focused words `के`, `कि`, `की`, `का`, and
  `श्रेणी` pass `compare-harfrust`; broader `hi-words.txt` parity is now
  blocked later at another Indic conjunct/half-form case, `वार्ता`.

Conclusion: Arabic long text still trails CoreText substantially. The broad
goal is active, not complete.

## Near-Term Gaps

- Add a library-level HarfBuzz or HarfRust comparison runner so CoreText is not
  the only external timing baseline. The current `harfrust` `shape-bench`
  engine is a batch external-process baseline, not a fully fair in-process
  performance baseline.
- Expand the benchmark matrix beyond Amiri and Roboto:
  `NotoSansDevanagari-Regular.ttf`, `NotoNastaliqUrdu-Regular.ttf`,
  `SourceSerifVariable-Roman.ttf`, and the harfrust text corpus.
- Track output parity, not only timing. `compare-harfrust` now compares glyph
  ids, clusters, advances, and offsets in HarfBuzz-style buffer order; feature
  override and broader font/script matrices still need expansion.
- Expand the new Indic shaper slice from simple vowel-sign words to consonant
  clusters, half forms, and conjuncts before treating `hi-words.txt` as a
  parity corpus.
- Continue Arabic hot-path work from measured profile evidence:
  GSUB `calt` context lookups and GPOS lookups `37`, `57`, and `74`.
- Avoid retaining optimizations that only improve a single noisy run or regress
  Roboto/word-list smoke cases.
