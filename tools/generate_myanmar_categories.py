#!/usr/bin/env python3
"""Translate HarfBuzz's Unicode Indic table into Myanmar category ranges.

Usage:
    tools/generate_myanmar_categories.py \
        path/to/hb-ot-shaper-indic-table.cc \
        src/myanmar/category_data.zig

HarfBuzz's Myanmar syllable machine consumes the low-byte Indic category
generated from Unicode IndicSyllabicCategory/IndicPositionalCategory data and
the Myanmar-specific overrides in gen-indic-table.py. This translator decodes
HarfBuzz's generated table and emits compact, searchable ranges so Cangjie's
hand-written grammar and HarfBuzz use the same Unicode 17 vocabulary.

The decoder is deliberately pinned to the current default-size packing
topology. A future HarfBuzz generator change must update this script rather
than silently producing incorrect category data.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


VERSION_RE = re.compile(r"# IndicSyllabicCategory-([0-9.]+)\.txt")
VALUES_RE = re.compile(
    r"static const uint16_t _hb_indic_values\[(\d+)\]\s*=\s*"
    r"\{(.*?)\};",
    re.DOTALL,
)
DATA_RE = re.compile(
    r"static const uint8_t _hb_indic_u8\[(\d+)\]\s*=\s*"
    r"\{(.*?)\};",
    re.DOTALL,
)

EXPECTED_VALUE_COUNT = 42
EXPECTED_DATA_LENGTH = 1220
TABLE_LIMIT = 71_396

# These are the low-byte category values exported by HarfBuzz's Indic,
# Khmer, and Myanmar machines. Positional categories in the second macro
# argument do not affect Myanmar syllable recognition.
CATEGORY_VALUES = {
    "A": 9,
    "As": 32,
    "C": 1,
    "CM": 16,
    "CS": 18,
    "DC": 11,
    "GB": 10,
    "H": 4,
    "M": 7,
    "MH": 35,
    "ML": 41,
    "MP": 13,
    "MR": 36,
    "MW": 37,
    "MY": 38,
    "N": 3,
    "PT": 39,
    "R": 15,
    "Rf": 14,
    "Rt": 25,
    "S": 17,
    "SM": 8,
    "SP": 57,
    "V": 2,
    "VA": 20,
    "VB": 21,
    "VL": 22,
    "VR": 23,
    "VS": 40,
    "X": 0,
    "Xg": 26,
    "Yg": 27,
    "ZWJ": 6,
    "ZWNJ": 5,
}


def parse_header(path: Path) -> tuple[str, list[int], list[int]]:
    text = path.read_text(encoding="utf-8")
    version_match = VERSION_RE.search(text)
    values_match = VALUES_RE.search(text)
    data_match = DATA_RE.search(text)
    if version_match is None:
        raise ValueError("missing IndicSyllabicCategory Unicode version")
    if values_match is None or data_match is None:
        raise ValueError("missing generated HarfBuzz Indic category arrays")

    declared_value_count = int(values_match.group(1))
    value_tokens = re.findall(
        r"_\(\s*([A-Za-z]+)\s*,\s*([A-Za-z]+)\s*\)",
        values_match.group(2),
    )
    if declared_value_count != EXPECTED_VALUE_COUNT or len(value_tokens) != EXPECTED_VALUE_COUNT:
        raise ValueError(
            "unsupported HarfBuzz Indic value table: "
            f"declared {declared_value_count}, parsed {len(value_tokens)}, "
            f"expected {EXPECTED_VALUE_COUNT}"
        )
    try:
        values = [CATEGORY_VALUES[category] for category, _position in value_tokens]
    except KeyError as error:
        raise ValueError(f"unknown generated Indic category {error.args[0]!r}") from error

    declared_data_length = int(data_match.group(1))
    data = [int(token) for token in re.findall(r"\d+", data_match.group(2))]
    if declared_data_length != EXPECTED_DATA_LENGTH or len(data) != EXPECTED_DATA_LENGTH:
        raise ValueError(
            "unsupported HarfBuzz Indic packing: "
            f"declared {declared_data_length}, parsed {len(data)}, "
            f"expected {EXPECTED_DATA_LENGTH}"
        )
    if any(value > 0xFF for value in data):
        raise ValueError("generated Indic byte table contains a value above u8")

    topology = "return u<71396u ? (uint8_t)(_hb_indic_u8[996u+"
    if topology not in text:
        raise ValueError("unsupported HarfBuzz Indic packing topology")
    return version_match.group(1), values, data


def category_for_codepoint(codepoint: int, values: list[int], data: list[int]) -> int:
    if codepoint >= TABLE_LIMIT:
        return 0

    def nibble(index: int) -> int:
        return (data[index >> 1] >> ((index & 1) << 2)) & 15

    level_1 = data[70 + nibble(codepoint >> 9) * 8 + ((codepoint >> 6) & 7)]
    level_2 = data[186 + level_1 * 8 + ((codepoint >> 3) & 7)]
    level_3 = data[488 + level_2 * 4 + ((codepoint >> 1) & 3)]
    return values[data[996 + level_3 + (codepoint & 1)]]


def build_ranges(values: list[int], data: list[int]) -> list[tuple[int, int, int]]:
    ranges: list[tuple[int, int, int]] = []
    start: int | None = None
    last = 0
    active_category = 0

    for codepoint in range(TABLE_LIMIT):
        # Common and Inherited characters can be absorbed into a Myanmar
        # script run. Retain every non-default upstream category rather than
        # assuming only scalars from the Myanmar blocks can reach the machine.
        category = category_for_codepoint(codepoint, values, data)
        if category == 0:
            if start is not None:
                ranges.append((start, last, active_category))
                start = None
            continue
        if start is not None and category == active_category and codepoint == last + 1:
            last = codepoint
            continue
        if start is not None:
            ranges.append((start, last, active_category))
        start = last = codepoint
        active_category = category

    if start is not None:
        ranges.append((start, last, active_category))
    return ranges


def render(version: str, ranges: list[tuple[int, int, int]]) -> str:
    lines = [
        f"// Generated by tools/generate_myanmar_categories.py from HarfBuzz Unicode {version}.",
        "// Values are low-byte Indic categories consumed by the Myanmar grammar.",
        "",
        "const Range = struct {",
        "    first: u21,",
        "    last: u21,",
        "    category: u8,",
        "};",
        "",
        "const ranges = [_]Range{",
    ]
    for first, last, category in ranges:
        lines.append(
            f"    .{{ .first = 0x{first:x}, .last = 0x{last:x}, .category = {category} }},"
        )
    lines.extend(
        [
            "};",
            "",
            "pub fn forCodepoint(codepoint: u21) u8 {",
            "    var low: usize = 0;",
            "    var high: usize = ranges.len;",
            "    while (low < high) {",
            "        const mid = low + (high - low) / 2;",
            "        if (ranges[mid].last < codepoint) {",
            "            low = mid + 1;",
            "        } else {",
            "            high = mid;",
            "        }",
            "    }",
            "    if (low >= ranges.len or codepoint < ranges[low].first) return 0;",
            "    return ranges[low].category;",
            "}",
            "",
            'test "Unicode 17 Myanmar categories retain machine overrides" {',
            '    const testing = @import("std").testing;',
            "    try testing.expectEqual(@as(u8, 15), forCodepoint(0x1004));",
            "    try testing.expectEqual(@as(u8, 22), forCodepoint(0x1031));",
            "    try testing.expectEqual(@as(u8, 32), forCodepoint(0x103a));",
            "    try testing.expectEqual(@as(u8, 40), forCodepoint(0xfe00));",
            "    try testing.expectEqual(@as(u8, 0), forCodepoint(0x0020));",
            "}",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    version, values, data = parse_header(Path(sys.argv[1]))
    ranges = build_ranges(values, data)
    Path(sys.argv[2]).write_text(render(version, ranges), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
