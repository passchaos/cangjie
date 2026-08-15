#!/usr/bin/env python3
"""Compile the full Unicode 17 UAX #9 conformance suites.

Usage:
    tools/unicode/bidi/generate_conformance.py \
        BidiTest.txt BidiCharacterTest.txt src/unicode/bidi/conformance.bin

The fixture stores unique BidiTest expectations once and references them from
each generated paragraph-level variant. BidiCharacterTest rows already carry
their own scalar input and are encoded directly.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

CLASSES = (
    "L", "R", "AL", "EN", "ES", "ET", "AN", "CS", "NSM", "BN", "B", "S",
    "WS", "ON", "LRE", "LRO", "RLE", "RLO", "PDF", "LRI", "RLI", "FSI", "PDI",
)
CLASS = {name: index for index, name in enumerate(CLASSES)}
REMOVED = 0xFF


def parse_levels(fields):
    return bytes(REMOVED if field == "x" else int(field) for field in fields)


def parse_order(fields):
    return bytes(int(field) for field in fields)


def load_bidi_test(path):
    text = Path(path).read_text(encoding="utf-8")
    if not text.startswith("# BidiTest-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17 BidiTest")
    current_levels = b""
    current_order = b""
    expectations = []
    expectation_slots = {}
    cases = []
    source_rows = 0
    for line_no, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("@Levels:"):
            current_levels = parse_levels(stripped.split(":", 1)[1].split())
            continue
        if stripped.startswith("@Reorder:"):
            current_order = parse_order(stripped.split(":", 1)[1].split())
            continue
        if not stripped or stripped.startswith(("#", "@")):
            continue
        source_rows += 1
        fields = stripped.split(";")
        if len(fields) < 2:
            raise SystemExit(f"{path}:{line_no}: malformed data row")
        types = bytes(CLASS[name] for name in fields[0].split())
        if len(types) != len(current_levels):
            raise SystemExit(f"{path}:{line_no}: level length mismatch")
        expectation = (current_levels, current_order)
        slot = expectation_slots.get(expectation)
        if slot is None:
            slot = len(expectations)
            expectation_slots[expectation] = slot
            expectations.append(expectation)
        bitset = int(fields[1].strip(), 16)
        for bit, mode in ((1, 2), (2, 0), (4, 1)):
            if bitset & bit:
                cases.append((mode, slot, types))
    if source_rows != 490846 or len(cases) != 770241:
        raise SystemExit(
            f"unexpected BidiTest counts: rows={source_rows} variants={len(cases)}"
        )
    return expectations, cases


def load_character_test(path):
    text = Path(path).read_text(encoding="utf-8")
    if not text.startswith("# BidiCharacterTest-17.0.0.txt\n"):
        raise SystemExit("expected Unicode 17 BidiCharacterTest")
    cases = []
    for line_no, line in enumerate(text.splitlines(), 1):
        stripped = line.split("#", 1)[0].strip()
        if not stripped:
            continue
        fields = [field.strip() for field in stripped.split(";")]
        if len(fields) != 5:
            raise SystemExit(f"{path}:{line_no}: malformed data row")
        codepoints = [int(value, 16) for value in fields[0].split()]
        mode = int(fields[1])
        resolved = int(fields[2])
        levels = parse_levels(fields[3].split())
        order = parse_order(fields[4].split())
        if len(codepoints) != len(levels) or mode not in (0, 1, 2):
            raise SystemExit(f"{path}:{line_no}: invalid row")
        cases.append((mode, resolved, codepoints, levels, order))
    if len(cases) != 91707:
        raise SystemExit(f"expected 91707 BidiCharacterTest rows, found {len(cases)}")
    return cases


def main():
    if len(sys.argv) != 4:
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} "
            "BidiTest.txt BidiCharacterTest.txt output.bin"
        )
    expectations, type_cases = load_bidi_test(sys.argv[1])
    character_cases = load_character_test(sys.argv[2])
    output = bytearray(
        struct.pack(
            "<4sBBBBIII",
            b"CJBT",
            1,
            17,
            0,
            0,
            len(expectations),
            len(type_cases),
            len(character_cases),
        )
    )
    for levels, order in expectations:
        output.extend(struct.pack("<BB", len(levels), len(order)))
        output.extend(levels)
        output.extend(order)
    for mode, expectation, types in type_cases:
        output.extend(struct.pack("<BHB", mode, expectation, len(types)))
        output.extend(types)
    for mode, resolved, codepoints, levels, order in character_cases:
        output.extend(struct.pack("<BBBB", mode, resolved, len(codepoints), len(order)))
        output.extend(levels)
        output.extend(struct.pack(f"<{len(codepoints)}I", *codepoints))
        output.extend(order)
    Path(sys.argv[3]).write_bytes(output)


if __name__ == "__main__":
    main()
