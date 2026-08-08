#!/usr/bin/env python3
"""Compile Unicode's UAX #14 conformance cases into a compact test fixture.

Usage:
    tools/generate_line_break_test_data.py path/to/LineBreakTest.txt \
        src/text/line_break_test_data.bin

The expected input is Unicode's LineBreakTest-15.0.0.txt. As in
unicode-linebreak 0.1.5's own conformance runner, cases marked [30.22] or
[999.0] are omitted because they exercise explicitly tailorable rules rather
than the crate's default pair-table behavior.

Binary format (all multi-byte integers are little-endian):
    magic[4] = "CJLT"
    format_version: u8 = 1
    unicode_version[3]: u8 = {15, 0, 0}
    case_count: u32
    repeated case_count times:
        codepoint_count: u8
        repeated codepoint_count times:
            codepoint: u32
            break_after: u8
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path


SKIPPED_RULES = ("[30.22]", "[999.0]")


def parse_case(line: str, line_number: int) -> list[tuple[int, bool]] | None:
    body, separator, comment = line.partition("# ")
    if not separator:
        raise SystemExit(f"line {line_number}: missing '# ' comment separator")
    if any(rule in comment for rule in SKIPPED_RULES):
        return None

    fields = body.split()
    if not fields or fields.pop(0) != "×":
        raise SystemExit(f"line {line_number}: expected leading no-break marker")
    if len(fields) % 2 != 0:
        raise SystemExit(f"line {line_number}: incomplete codepoint/boundary pair")

    case: list[tuple[int, bool]] = []
    while fields:
        codepoint = int(fields.pop(0), 16)
        marker = fields.pop(0)
        if marker not in ("×", "÷"):
            raise SystemExit(f"line {line_number}: invalid boundary marker {marker!r}")
        if codepoint > 0x10FFFF or 0xD800 <= codepoint <= 0xDFFF:
            raise SystemExit(f"line {line_number}: invalid Unicode scalar U+{codepoint:04X}")
        case.append((codepoint, marker == "÷"))

    if not case or len(case) > 255:
        raise SystemExit(f"line {line_number}: unsupported case size {len(case)}")
    if not case[-1][1]:
        raise SystemExit(f"line {line_number}: case has no end-of-text break")
    return case


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} path/to/LineBreakTest.txt output.bin"
        )

    source_path = Path(sys.argv[1])
    source = source_path.read_text(encoding="utf-8")
    if not source.startswith("# LineBreakTest-15.0.0.txt\n"):
        raise SystemExit("expected Unicode LineBreakTest-15.0.0.txt")

    cases: list[list[tuple[int, bool]]] = []
    for line_number, line in enumerate(source.splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        case = parse_case(line, line_number)
        if case is not None:
            cases.append(case)

    output = bytearray(struct.pack("<4sBBBBI", b"CJLT", 1, 15, 0, 0, len(cases)))
    for case in cases:
        output.append(len(case))
        for codepoint, break_after in case:
            output.extend(struct.pack("<IB", codepoint, break_after))
    Path(sys.argv[2]).write_bytes(output)


if __name__ == "__main__":
    main()
