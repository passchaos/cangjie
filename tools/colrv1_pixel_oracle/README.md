# Skrifa/tiny-skia COLRv1 pixel oracle

This independent adapter traverses COLRv1 paint graphs with the repository's
pinned Skrifa 0.45.2 checkout and rasterizes them with tiny-skia 0.12.0. It
emits row-major premultiplied RGBA8 and a deterministic FNV-1a checksum. The
normal Zig build does not require Rust; `colrv1-pixel-matrix` builds the oracle
offline only when explicitly requested.

The adapter observes Skrifa's matrix, PaintGlyph, PaintColrGlyph, clip, layer,
gradient, and variation contracts. Notably, tiny-skia names `A * B`
`A.pre_concat(B)`, its sweep shader needs a center-preserving y reflection,
and solid/group SourceOver operations stay in byte-domain sRGB while gradient
interpolation uses full sRGB transfer functions.

Run the maintained ten-case differential with:

```sh
zig build colrv1-pixel-matrix -Doptimize=ReleaseFast
```

The fixture and exact provenance are documented in `THIRD_PARTY_NOTICES.md`.
The two engines use independent scan converters, so the matrix requires a
maximum channel error of one outside a one-pixel edge neighborhood and also
bounds the fringe. It does not use a permissive whole-image tolerance.

Direct invocation is:

```sh
cargo run --release --locked --offline \
  --manifest-path tools/colrv1_pixel_oracle/Cargo.toml -- \
  FONT GID SIZE WIDTH HEIGHT X BASELINE PALETTE COORDS ITERATIONS SAMPLES [OUTPUT]
```

Use `-` for the default location or comma-separated normalized coordinates.
