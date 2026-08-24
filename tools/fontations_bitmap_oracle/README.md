# Fontations bitmap oracle

This tiny binary reads one generated raw EBDT/CBDT fixture through the pinned
local Fontations/Skrifa checkout. It reports Skrifa's selected data kind,
metrics, byte length, and FNV-1a payload hash. Cangjie's integration test uses
the same fixture vectors and contract; maintainers can run the oracle when
updating the pinned Fontations revision without adding Rust to the normal Zig
test dependency graph. The retained formats 1 and 6 both report:

```text
bgra  2  1  2  13  8  9703b39ed959628c
```

Skrifa deliberately returns no high-level glyph for the corresponding 32-bpp
bit-aligned formats 2, 5, and 7. Cangjie retains that same public boundary.

```sh
cargo run --manifest-path tools/fontations_bitmap_oracle/Cargo.toml -- \
  /tmp/cangjie-bgra.ttf bitmap 1 16
```

The same binary also provides a repeated unscaled outline draw boundary for
Skrifa comparisons:

```sh
cargo run --release --manifest-path tools/fontations_bitmap_oracle/Cargo.toml -- \
  /path/to/font.ttf outline GLYPH_ID 10000 31
```

Repeated unscaled glyph metrics and Unicode charmap lookups use the same final
two arguments (`ITERATIONS SAMPLES`). `bounds` compares the complete unscaled
glyph bounding box, including outline-derived CFF and variable-font bounds:

```sh
cargo run --release --manifest-path tools/fontations_bitmap_oracle/Cargo.toml -- \
  /path/to/font.ttf metrics GLYPH_ID 1000000 31
cargo run --release --manifest-path tools/fontations_bitmap_oracle/Cargo.toml -- \
  /path/to/font.ttf bounds GLYPH_ID 1000000 31
cargo run --release --manifest-path tools/fontations_bitmap_oracle/Cargo.toml -- \
  /path/to/font.ttf charmap CODEPOINT 1000000 31
```

Repeated strike selection uses `bitmap-bench GLYPH_ID SIZE ITERATIONS SAMPLES`.
Repeated global font metrics use `global-metrics 0 ITERATIONS SAMPLES`.
Repeated English-or-first family names use `family-name 0 ITERATIONS SAMPLES`.
Resolved post/CFF/synthesized glyph names use
`glyph-name GLYPH_ID ITERATIONS SAMPLES`.
Repeated default-instance classification uses `attributes 0 ITERATIONS SAMPLES`.
Axis and named-instance enumeration uses `variations 0 ITERATIONS SAMPLES`.
Color-palette enumeration uses `palettes 0 ITERATIONS SAMPLES`.
Bitmap-strike enumeration uses `strikes 0 ITERATIONS SAMPLES`.
Preferred color-glyph source lookup uses `color-glyph GLYPH_ID ITERATIONS SAMPLES`.
The matching fixtures can be generated in the current directory with
`zig build glyph-name-fixtures`; it writes `post.ttf`, `cff.otf`, and
`synthesized.ttf`, each with the comparable glyph at id 1, plus complete
`attributes-head.ttf` and `attributes-os2.ttf` wrappers around the exact
Fontations reference tables, plus a complete two-axis/two-instance
`variations.ttf` differential fixture.
The generator also writes `palettes.ttf` for CPAL collection parity.
It writes `strikes.ttf` for embedded bitmap collection parity as well.
`color-glyph-v0.ttf` and `color-glyph-v1.ttf` cover COLR source selection.
