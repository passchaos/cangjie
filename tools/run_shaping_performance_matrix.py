#!/usr/bin/env python3
"""Run an interleaved Cangjie/HarfBuzz/HarfRust shaping matrix."""

from __future__ import annotations

import argparse
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Case:
    name: str
    font: str
    text: str
    direction: str


CORE_CASES = (
    Case("roboto-words", "Roboto-Regular.ttf", "en-words.txt", "ltr"),
    Case("source-serif-words", "SourceSerifVariable-Roman.ttf", "en-words.txt", "ltr"),
    Case("amiri-words", "Amiri-Regular.ttf", "fa-words.txt", "rtl"),
    Case("amiri-long", "Amiri-Regular.ttf", "fa-thelittleprince.txt", "rtl"),
    Case("devanagari-words", "NotoSansDevanagari-Regular.ttf", "hi-words.txt", "ltr"),
)

# The mixed source-code corpus is deliberately a separate suite. A single pass
# shapes about one million glyphs, so silently adding it to the core matrix
# would make the commonly used 5-iteration/11-sample command prohibitively
# expensive and could encourage users to reduce the core suite's rigor.
REACT_DOM_CASES = (
    Case("roboto-react-dom", "Roboto-Regular.ttf", "react-dom.txt", "ltr"),
    Case(
        "source-serif-react-dom",
        "SourceSerifVariable-Roman.ttf",
        "react-dom.txt",
        "ltr",
    ),
)


def cases_for_suite(suite: str) -> tuple[Case, ...]:
    if suite == "core":
        return CORE_CASES
    if suite == "react-dom":
        return REACT_DOM_CASES
    if suite == "all":
        return CORE_CASES + REACT_DOM_CASES
    raise ValueError(f"unknown suite: {suite}")


def run(command: list[str], cpu: int | None) -> dict[str, str]:
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    completed = subprocess.run(
        command, check=False, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True,
    )
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr, end="")
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}"
        )
    fields: dict[str, str] = {}
    for token in re.split(r"[\t\n ]", completed.stdout):
        if "=" in token:
            key, value = token.split("=", 1)
            # shape-bench prints aggregate fields before per-sample records,
            # whose repeated glyph/checksum keys must not replace the totals.
            fields.setdefault(key, value)
    return fields


def cangjie_command(
    executable: Path, font: Path, text: Path, case: Case,
    iterations: int, samples: int, engine: str = "cangjie",
) -> list[str]:
    return [
        str(executable), "--engine", engine, "--font", str(font),
        "--text-file", str(text), "--direction", case.direction,
        "--iterations", str(iterations), "--warmup", "2",
        "--samples", str(samples), "--timing-consumer", "summary",
    ]


def median(record: dict[str, str]) -> float:
    if "sample_median_ns_per_glyph" in record:
        return float(record["sample_median_ns_per_glyph"])
    return float(record["median_ns_per_glyph"])


def glyphs_per_iteration(
    record: dict[str, str], iterations: int, samples: int, aggregate: bool
) -> int:
    glyphs = int(record["glyphs"])
    if not aggregate:
        return glyphs
    measured_runs = iterations * samples
    if glyphs % measured_runs != 0:
        raise RuntimeError(
            f"aggregate glyph count {glyphs} is not divisible by "
            f"iterations*samples ({measured_runs})"
        )
    return glyphs // measured_runs


def test_glyph_count_normalization() -> None:
    assert glyphs_per_iteration({"glyphs": "120"}, 3, 4, True) == 10
    assert glyphs_per_iteration({"glyphs": "10"}, 3, 4, False) == 10
    try:
        glyphs_per_iteration({"glyphs": "121"}, 3, 4, True)
    except RuntimeError:
        pass
    else:
        raise AssertionError("non-integral aggregate must be rejected")


def test_case_selection() -> None:
    assert cases_for_suite("core") == CORE_CASES
    assert cases_for_suite("react-dom") == REACT_DOM_CASES
    assert cases_for_suite("all") == CORE_CASES + REACT_DOM_CASES
    try:
        cases_for_suite("unknown")
    except ValueError:
        pass
    else:
        raise AssertionError("unknown suites must be rejected")


def main() -> int:
    test_glyph_count_normalization()
    test_case_selection()
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--harfbuzz", required=True, type=Path)
    parser.add_argument("--harfrust-manifest", required=True, type=Path)
    parser.add_argument("--corpus-root", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--cpu", type=int)
    parser.add_argument(
        "--suite", choices=("core", "react-dom", "all"), default="core",
        help=(
            "corpus suite to run; react-dom is separate because each pass "
            "shapes about one million glyphs"
        ),
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.harfrust_manifest)],
        check=True,
    )
    harfrust = args.harfrust_manifest.parent / "target/release/harfrust-shape-oracle"
    cases = cases_for_suite(args.suite)
    for case in cases:
        font = args.corpus_root / "fonts" / case.font
        text = args.corpus_root / "texts" / case.text
        cangjie_cmd = cangjie_command(
            args.cangjie, font, text, case, args.iterations, args.samples
        )
        harfbuzz_cmd = cangjie_command(
            args.harfbuzz, font, text, case, args.iterations, args.samples,
            "harfbuzz",
        )
        harfrust_cmd = [
            str(harfrust), str(font), str(text), str(args.iterations),
            str(args.samples), case.direction,
        ]
        # Symmetric process ordering limits temperature/frequency bias without
        # conflating the libraries' intentionally independent hash functions.
        cangjie_a = run(cangjie_cmd, args.cpu)
        harfbuzz_a = run(harfbuzz_cmd, args.cpu)
        harfrust_a = run(harfrust_cmd, args.cpu)
        harfrust_b = run(harfrust_cmd, args.cpu)
        harfbuzz_b = run(harfbuzz_cmd, args.cpu)
        cangjie_b = run(cangjie_cmd, args.cpu)
        records = (cangjie_a, harfbuzz_a, harfrust_a, harfrust_b, harfbuzz_b, cangjie_b)
        # shape-bench reports the aggregate over every measured iteration and
        # sample, while the library-level HarfRust oracle reports one complete
        # corpus pass. Normalize both contracts before comparing semantics.
        glyph_counts = {
            glyphs_per_iteration(
                record, args.iterations, args.samples, index != 2 and index != 3
            )
            for index, record in enumerate(records)
        }
        if len(glyph_counts) != 1:
            raise RuntimeError(
                f"{case.name}: unstable/cross-engine glyph counts {glyph_counts}"
            )
        values = (
            (median(cangjie_a), median(cangjie_b)),
            (median(harfbuzz_a), median(harfbuzz_b)),
            (median(harfrust_a), median(harfrust_b)),
        )
        means = tuple(math.sqrt(a * b) for a, b in values)
        strongest = min(means[1:])
        print(
            f"{case.name}: cangjie={values[0][0]:.3f}/{values[0][1]:.3f} "
            f"harfbuzz={values[1][0]:.3f}/{values[1][1]:.3f} "
            f"harfrust={values[2][0]:.3f}/{values[2][1]:.3f} "
            f"speedup_vs_best={strongest / means[0]:.3f}x "
            f"glyphs={glyphs_per_iteration(cangjie_a, args.iterations, args.samples, True)}"
        )
    print(
        f"Cangjie/HarfBuzz/HarfRust shaping matrix completed: {len(cases)} corpora"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
