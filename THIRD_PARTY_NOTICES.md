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
