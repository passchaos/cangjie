#!/usr/bin/env python3
"""Compile Unicode 17.0 GraphemeBreakTest.txt into a compact fixture.

Usage:
    tools/unicode/grapheme/generate_conformance.py \
        GraphemeBreakTest.txt src/unicode/grapheme/conformance.bin
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} GraphemeBreakTest.txt output.bin"
        )

    source = Path(sys.argv[1]).read_text(encoding="utf-8")
    if not source.startswith("# GraphemeBreakTest-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17.0 GraphemeBreakTest fixture")

    cases: list[tuple[list[int], list[bool]]] = []
    for line_number, raw in enumerate(source.splitlines(), 1):
        fields = raw.split("#", 1)[0].split()
        if not fields:
            continue
        marker = fields.pop(0)
        if marker != "÷":
            raise SystemExit(f"line {line_number}: missing initial break")

        codepoints: list[int] = []
        boundaries = [True]
        while fields:
            if len(fields) < 2:
                raise SystemExit(f"line {line_number}: incomplete boundary pair")
            codepoint = int(fields.pop(0), 16)
            marker = fields.pop(0)
            if marker not in ("×", "÷"):
                raise SystemExit(f"line {line_number}: invalid marker {marker!r}")
            if codepoint > 0x10FFFF or 0xD800 <= codepoint <= 0xDFFF:
                raise SystemExit(f"line {line_number}: invalid Unicode scalar")
            codepoints.append(codepoint)
            boundaries.append(marker == "÷")
        if len(codepoints) > 0xFF:
            raise SystemExit(f"line {line_number}: case is too long")
        cases.append((codepoints, boundaries))

    output = bytearray(struct.pack("<4sBBBBI", b"CJGT", 1, 17, 0, 0, len(cases)))
    for codepoints, boundaries in cases:
        output.append(len(codepoints))
        output.extend(bytes(boundaries))
        output.extend(struct.pack(f"<{len(codepoints)}I", *codepoints))
    Path(sys.argv[2]).write_bytes(output)


if __name__ == "__main__":
    main()
