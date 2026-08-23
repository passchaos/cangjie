# HarfRust library oracle

This standalone executable links the checked-out local HarfRust source directly.
It exists because `shape-bench --engine harfrust` must execute `hr-shape` to
capture serialized reference output, so that mode includes process startup and
text serialization and is not a strict shaping-performance comparison.

The oracle loads a font and a UTF-8 corpus once, retains `ShaperData`, shape
plans, and one reusable `UnicodeBuffer`, and times only repeated library shaping
plus a constant-size result consumer. Complete glyph IDs, clusters, advances,
and offsets are hashed before and after measurement to reject unstable output.

```sh
cargo run --release --manifest-path tools/harfrust_shape_oracle/Cargo.toml -- \
  /path/to/font.ttf /path/to/text.txt 5 11 ltr

zig build shape-bench -Doptimize=ReleaseFast -- \
  --font /path/to/font.ttf --text-file /path/to/text.txt \
  --iterations 5 --warmup 2 --samples 11 --direction ltr \
  --timing-consumer summary
```

The two tools intentionally keep independent deterministic checksums; exact
cross-engine glyph and position parity remains the responsibility of
`shape-bench --engine compare-harfrust`.
