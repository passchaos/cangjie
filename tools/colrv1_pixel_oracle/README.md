# Skrifa/tiny-skia COLRv1 pixel oracle

This independent adapter traverses COLRv1 paint graphs with Skrifa 0.45.2 at
the exact Fontations revision `bb6f87166aa8bac93ff9df5ea67d58b7091b3e2a`
and rasterizes them with tiny-skia 0.12.0. (`0.45.2` was not published on
crates.io, so Cargo pins the upstream Git revision and lockfile source.) It
emits row-major premultiplied RGBA8, a deterministic FNV-1a checksum, and a
one-byte-per-pixel geometry-edge sidecar. The normal Zig build does not require
Rust; `colrv1-pixel-matrix` builds the locked oracle offline only when
explicitly requested and the pinned dependencies are present in Cargo's cache.

The adapter observes Skrifa's matrix, PaintGlyph, PaintColrGlyph, clip, layer,
gradient, and variation contracts. Notably, tiny-skia names `A * B`
`A.pre_concat(B)`, its sweep shader needs a center-preserving y reflection,
and solid/group SourceOver operations stay in byte-domain sRGB while gradient
interpolation uses full sRGB transfer functions.

Run the maintained ten-case differential with:

```sh
zig build colrv1-pixel-matrix -Doptimize=ReleaseFast
```

The fixture and dependency provenance are documented in
`THIRD_PARTY_NOTICES.md`. The two engines use independent scan converters, so
the matrix requires a maximum channel error of one outside the reference
oracle's coverage-edge neighborhoods and bounds the fringe per pixel. Edges
come from path/clip coverage before brush shading; color gradients cannot be
misclassified as edges or expand their own tolerance. `linear-pad` and
`composite` additionally require byte-exact full-image agreement. The runner's
synthetic self-tests exercise shifted geometry, reversed gradients, broad color
errors, and candidate-created edges before every maintained matrix run (they
may be skipped explicitly with `--no-self-test` for local diagnostics only).

Direct invocation is:

```sh
cargo run --release --locked --offline \
  --manifest-path tools/colrv1_pixel_oracle/Cargo.toml -- \
  FONT GID SIZE WIDTH HEIGHT X BASELINE PALETTE COORDS ITERATIONS SAMPLES \
  [OUTPUT] [GEOMETRY_EDGES_OUTPUT]
```

Use `-` for the default location or comma-separated normalized coordinates.
