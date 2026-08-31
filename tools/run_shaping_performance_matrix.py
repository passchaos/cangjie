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
    common_args: tuple[str, ...] = ()


CORE_CASES = (
    Case("roboto-words", "Roboto-Regular.ttf", "en-words.txt", "ltr"),
    Case("source-serif-words", "SourceSerifVariable-Roman.ttf", "en-words.txt", "ltr"),
    Case("amiri-words", "Amiri-Regular.ttf", "fa-words.txt", "rtl"),
    Case("amiri-long", "Amiri-Regular.ttf", "fa-thelittleprince.txt", "rtl"),
    Case("devanagari-words", "NotoSansDevanagari-Regular.ttf", "hi-words.txt", "ltr"),
)

# Long prose and mixed source-code corpora are separate suites. Silently adding
# them to the core matrix would make the commonly used 5-iteration/11-sample
# command prohibitively expensive and could encourage reducing core rigor.
REACT_DOM_CASES = (
    Case("roboto-react-dom", "Roboto-Regular.ttf", "react-dom.txt", "ltr"),
    Case(
        "source-serif-react-dom",
        "SourceSerifVariable-Roman.ttf",
        "react-dom.txt",
        "ltr",
    ),
)

BROAD_CASES = (
    # HarfBuzz and the in-process HarfRust oracle leave language unset, which
    # selects DefaultLangSys. Cangjie's public API deliberately performs
    # content-based language inference, so pin `dflt` here to compare the same
    # lookup selection rather than Urdu/Persian policy against a default one.
    Case(
        "noto-nastaliq-words",
        "NotoNastaliqUrdu-Regular.ttf",
        "fa-words.txt",
        "rtl",
        ("--language", "dflt"),
    ),
    Case(
        "noto-nastaliq-long",
        "NotoNastaliqUrdu-Regular.ttf",
        "fa-thelittleprince.txt",
        "rtl",
        ("--language", "dflt"),
    ),
    Case(
        "roboto-long",
        "Roboto-Regular.ttf",
        "en-thelittleprince.txt",
        "ltr",
    ),
    Case(
        "source-serif-long",
        "SourceSerifVariable-Roman.ttf",
        "en-thelittleprince.txt",
        "ltr",
    ),
)

DEFAULT_MINIMUM_SPEEDUP = 1.01


def cases_for_suite(suite: str) -> tuple[Case, ...]:
    if suite == "core":
        return CORE_CASES
    if suite == "react-dom":
        return REACT_DOM_CASES
    if suite == "broad":
        return BROAD_CASES
    if suite == "all":
        return CORE_CASES + BROAD_CASES + REACT_DOM_CASES
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
        *case.common_args,
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


def valid_minimum_speedup(minimum_speedup: float) -> bool:
    """A gate margin must be finite and strictly better than parity."""
    return math.isfinite(minimum_speedup) and minimum_speedup > 1.0


def meets_speedup_gate(speedup: float, minimum_speedup: float) -> bool:
    """Return whether a measured ratio reaches the declared gate boundary."""
    return not math.isnan(speedup) and speedup >= minimum_speedup


def gate_failed(
    speedup: float, minimum_speedup: float, fail_on_slower: bool
) -> bool:
    """Keep threshold reporting independent from opt-in gate enforcement."""
    return fail_on_slower and not meets_speedup_gate(speedup, minimum_speedup)


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
    assert cases_for_suite("broad") == BROAD_CASES
    assert cases_for_suite("all") == CORE_CASES + BROAD_CASES + REACT_DOM_CASES
    try:
        cases_for_suite("unknown")
    except ValueError:
        pass
    else:
        raise AssertionError("unknown suites must be rejected")


def test_speedup_gate_boundary() -> None:
    minimum = DEFAULT_MINIMUM_SPEEDUP
    assert valid_minimum_speedup(minimum)
    assert not valid_minimum_speedup(1.0)
    assert not valid_minimum_speedup(math.inf)
    assert not valid_minimum_speedup(math.nan)
    # The option names a minimum, so its exact boundary passes while the next
    # representable lower ratio does not. This keeps the gate deterministic.
    assert meets_speedup_gate(minimum, minimum)
    assert not meets_speedup_gate(math.nextafter(minimum, -math.inf), minimum)
    assert meets_speedup_gate(math.inf, minimum)
    assert not meets_speedup_gate(math.nan, minimum)
    assert not gate_failed(1.0, minimum, False)
    assert not gate_failed(math.nan, minimum, False)
    assert gate_failed(1.0, minimum, True)
    assert gate_failed(math.nan, minimum, True)
    assert not gate_failed(minimum, minimum, True)
    custom_minimum = 1.125
    assert meets_speedup_gate(custom_minimum, custom_minimum)
    assert not meets_speedup_gate(
        math.nextafter(custom_minimum, -math.inf), custom_minimum
    )


def main() -> int:
    test_glyph_count_normalization()
    test_case_selection()
    test_speedup_gate_boundary()
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--harfbuzz", required=True, type=Path)
    parser.add_argument("--harfrust-manifest", required=True, type=Path)
    parser.add_argument("--corpus-root", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--cpu", type=int)
    parser.add_argument(
        "--suite", choices=("core", "broad", "react-dom", "all"), default="core",
        help=(
            "corpus suite to run; broad adds Nastaliq and long prose, while "
            "react-dom stays separate because each pass shapes about one "
            "million glyphs"
        ),
    )
    parser.add_argument(
        "--fail-on-slower",
        action="store_true",
        help=(
            "fail when Cangjie does not meet --minimum-speedup against "
            "the best reference"
        ),
    )
    parser.add_argument(
        "--minimum-speedup",
        type=float,
        default=DEFAULT_MINIMUM_SPEEDUP,
        help=(
            "minimum ratio required by --fail-on-slower "
            f"(default: {DEFAULT_MINIMUM_SPEEDUP:g}); also reported when "
            "the gate is disabled"
        ),
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.samples <= 0:
        parser.error("iterations and samples must be positive")
    if not valid_minimum_speedup(args.minimum_speedup):
        parser.error("--minimum-speedup must be finite and greater than 1")

    gate_mode = "enforced" if args.fail_on_slower else "report-only"
    print(
        f"shaping_performance_gate={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.harfrust_manifest)],
        check=True,
    )
    harfrust = args.harfrust_manifest.parent / "target/release/harfrust-shape-oracle"
    cases = cases_for_suite(args.suite)
    failures: list[str] = []
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
        speedup = strongest / means[0]
        threshold_result = (
            "met"
            if meets_speedup_gate(speedup, args.minimum_speedup)
            else "below-minimum"
        )
        if gate_failed(speedup, args.minimum_speedup, args.fail_on_slower):
            failures.append(
                f"{case.name}: speedup {speedup:.6f}x is below the "
                f"{args.minimum_speedup:.6f}x minimum"
            )
        print(
            f"{case.name}: cangjie={values[0][0]:.3f}/{values[0][1]:.3f} "
            f"harfbuzz={values[1][0]:.3f}/{values[1][1]:.3f} "
            f"harfrust={values[2][0]:.3f}/{values[2][1]:.3f} "
            f"speedup_vs_best={speedup:.6f}x "
            f"minimum_speedup={args.minimum_speedup:.6f}x "
            f"threshold={threshold_result} gate_mode={gate_mode} "
            f"glyphs={glyphs_per_iteration(cangjie_a, args.iterations, args.samples, True)}"
        )
    if failures:
        print(
            "Cangjie shaping performance matrix failed "
            f"(minimum_speedup={args.minimum_speedup:.6f}x):",
            file=sys.stderr,
        )
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(
        f"Cangjie/HarfBuzz/HarfRust shaping matrix completed: {len(cases)} "
        f"corpora gate_mode={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
