# Third-Party Notices

## Unicode Character Database

Generated property tables and boundary blobs under `src/unicode/` contain
derived Unicode data, including UAX #50 vertical orientation. Their
conformance fixtures are compact encodings of the official Unicode 17
segmentation and line-breaking test files.

- Project: <https://www.unicode.org/>
- Copyright: Unicode, Inc.
- License: Unicode License v3; see `licenses/Unicode-3.0.txt`

The generation inputs, checksums, excluded tailorable cases, and reproducible
commands are recorded in `docs/text-pipeline.md`.

## Fontations VORG Test Font

`tests/data/fontations/vorg.ttf` is copied verbatim from Fontations
`font-test-data` at commit `6b3029b7a5ff2174346efa5b3833a22faa6fce60`.
Its SHA-256 is
`b6f28d136848a9b94638c8a199dcbf0cccb83593912d8f4d7bb12a8ecc0e31dc`.
It is used only to keep the VORG differential test reproducible without a
separate Fontations checkout.

- Project: <https://github.com/googlefonts/fontations>
- Copyright: 2019 Fontations Developers
- License: Apache License 2.0; see `licenses/Apache-2.0.txt`

## Fontations Name Test Font

`src/tests/data/fontations_names_only.ttf` is copied verbatim from Fontations
`font-test-data` at commit `bb6f87166aa8bac93ff9df5ea67d58b7091b3e2a`.
Its SHA-256 is
`5b6607d13ec365ca5d706c7032bde1e80727fa219a51bc49fa6c9a0e80634a24`.
It provides the authoritative multilingual records for the Skrifa localized
string differential test. The legacy numeric-language mapping in
`src/font/tables/metadata/name_languages.zig` is likewise derived from
Skrifa's Apache-licensed `src/string.rs` at that commit.

- Project: <https://github.com/googlefonts/fontations>
- Copyright: 2019 Fontations Developers
- License: Apache License 2.0; see `licenses/Apache-2.0.txt`

## Fontations Attribute Test Fonts

`src/tests/data/fontations_cmap12_font1.ttf` and
`src/tests/data/fontations_cmap14_font1.ttf` are copied verbatim from
Fontations `font-test-data` at commit
`bb6f87166aa8bac93ff9df5ea67d58b7091b3e2a`. Their SHA-256 values are,
respectively,
`1134860fcfa1ab18ac0f4020c30b40aa8caf6bf0287dbc3854cceb97b169a34d` and
`9e3f0ff71bf961702f81f485030095ad78794654c9d6b3b1e1167469b9f8c30b`.
They provide the authoritative head fallback and OS/2/post oblique records for
the Skrifa `MetadataProvider::attributes` differential test.

- Project: <https://github.com/googlefonts/fontations>
- Copyright: 2019 Fontations Developers
- License: Apache License 2.0; see `licenses/Apache-2.0.txt`
