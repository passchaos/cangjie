#!/usr/bin/env python3
"""Run an interleaved Cangjie/HarfBuzz/HarfRust shaping matrix."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence


TOOL_NAME = "run_shaping_performance_matrix.py"
TOOL_VERSION = "1.0"
REPORT_SCHEMA_VERSION = 1
WARMUP_ITERATIONS = 2
EXECUTION_ORDER = (
    "cangjie_a",
    "harfbuzz_a",
    "harfrust_a",
    "harfrust_b",
    "harfbuzz_b",
    "cangjie_b",
)


@dataclass(frozen=True)
class Case:
    name: str
    font: str
    text: str
    direction: str
    common_args: tuple[str, ...] = ()


@dataclass(frozen=True)
class EngineMeasurement:
    """The two symmetric timing endpoints and their combined estimate."""

    a_median_ns_per_glyph: float
    b_median_ns_per_glyph: float
    geometric_mean_ns_per_glyph: float
    a_normalized_glyph_count: int
    b_normalized_glyph_count: int


@dataclass(frozen=True)
class CaseResult:
    """A fully validated row, independent of text or JSON rendering."""

    case: Case
    cangjie: EngineMeasurement
    harfbuzz: EngineMeasurement
    harfrust: EngineMeasurement
    fastest_reference: str
    fastest_reference_geometric_mean_ns_per_glyph: float
    speedup_vs_fastest_reference: float
    threshold_status: str
    normalized_glyph_count: int
    semantic_count_agreement: bool


@dataclass(frozen=True)
class RunConfiguration:
    """Inputs that affect the identity or interpretation of a matrix run."""

    cangjie: Path
    harfbuzz: Path
    harfrust_manifest: Path
    harfrust_executable: Path
    corpus_root: Path
    suite: str
    iterations: int
    samples: int
    cpu: int | None
    fail_on_slower: bool
    minimum_speedup: float


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
        "--iterations", str(iterations), "--warmup", str(WARMUP_ITERATIONS),
        "--samples", str(samples), "--timing-consumer", "summary",
        *case.common_args,
    ]


def median(record: Mapping[str, str]) -> float:
    if "sample_median_ns_per_glyph" in record:
        return float(record["sample_median_ns_per_glyph"])
    return float(record["median_ns_per_glyph"])


def glyphs_per_iteration(
    record: Mapping[str, str], iterations: int, samples: int, aggregate: bool
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


def evaluate_case(
    case: Case,
    records: Sequence[Mapping[str, str]],
    iterations: int,
    samples: int,
    minimum_speedup: float,
) -> CaseResult:
    """Validate six symmetric endpoints and calculate one matrix row.

    ``records`` follows :data:`EXECUTION_ORDER`. Keeping this work pure makes
    the evidence calculations unit-testable without running either benchmark.
    """
    if len(records) != len(EXECUTION_ORDER):
        raise ValueError(
            f"{case.name}: expected {len(EXECUTION_ORDER)} endpoint records, "
            f"got {len(records)}"
        )
    if iterations <= 0 or samples <= 0:
        raise ValueError("iterations and samples must be positive")

    normalized_counts = tuple(
        glyphs_per_iteration(
            record, iterations, samples, index not in (2, 3)
        )
        for index, record in enumerate(records)
    )
    semantic_count_agreement = len(set(normalized_counts)) == 1
    if not semantic_count_agreement:
        raise RuntimeError(
            f"{case.name}: unstable/cross-engine glyph counts "
            f"{set(normalized_counts)}"
        )

    endpoint_values = (
        (median(records[0]), median(records[5])),
        (median(records[1]), median(records[4])),
        (median(records[2]), median(records[3])),
    )
    means = tuple(math.sqrt(a * b) for a, b in endpoint_values)
    # Keep tie handling deterministic so the artifact is stable even if both
    # references report identical rounded medians.
    fastest_reference = (
        "harfbuzz" if means[1] <= means[2] else "harfrust"
    )
    fastest_reference_mean = min(means[1:])
    speedup = fastest_reference_mean / means[0]

    measurements = tuple(
        EngineMeasurement(
            a_median_ns_per_glyph=values[0],
            b_median_ns_per_glyph=values[1],
            geometric_mean_ns_per_glyph=mean,
            a_normalized_glyph_count=normalized_counts[a_index],
            b_normalized_glyph_count=normalized_counts[b_index],
        )
        for values, mean, (a_index, b_index) in zip(
            endpoint_values, means, ((0, 5), (1, 4), (2, 3))
        )
    )
    return CaseResult(
        case=case,
        cangjie=measurements[0],
        harfbuzz=measurements[1],
        harfrust=measurements[2],
        fastest_reference=fastest_reference,
        fastest_reference_geometric_mean_ns_per_glyph=fastest_reference_mean,
        speedup_vs_fastest_reference=speedup,
        threshold_status=(
            "met"
            if meets_speedup_gate(speedup, minimum_speedup)
            else "below-minimum"
        ),
        normalized_glyph_count=normalized_counts[0],
        semantic_count_agreement=semantic_count_agreement,
    )


def _measurement_json(measurement: EngineMeasurement) -> dict[str, Any]:
    return {
        "endpoint_medians_ns_per_glyph": {
            "a": measurement.a_median_ns_per_glyph,
            "b": measurement.b_median_ns_per_glyph,
        },
        "geometric_mean_ns_per_glyph": (
            measurement.geometric_mean_ns_per_glyph
        ),
        "normalized_glyph_counts": {
            "a": measurement.a_normalized_glyph_count,
            "b": measurement.b_normalized_glyph_count,
        },
    }


def case_result_json(result: CaseResult) -> dict[str, Any]:
    """Return the stable machine-readable representation of one row."""
    return {
        "name": result.case.name,
        "font": result.case.font,
        "text": result.case.text,
        "direction": result.case.direction,
        "common_args": list(result.case.common_args),
        "engines": {
            "cangjie": _measurement_json(result.cangjie),
            "harfbuzz": _measurement_json(result.harfbuzz),
            "harfrust": _measurement_json(result.harfrust),
        },
        "fastest_reference": {
            "engine": result.fastest_reference,
            "geometric_mean_ns_per_glyph": (
                result.fastest_reference_geometric_mean_ns_per_glyph
            ),
        },
        "speedup_vs_fastest_reference": (
            result.speedup_vs_fastest_reference
        ),
        "threshold_status": result.threshold_status,
        "normalized_glyph_count": result.normalized_glyph_count,
        "semantic_count_agreement": result.semantic_count_agreement,
    }


def build_json_report(
    configuration: RunConfiguration,
    selected_cases: Sequence[Case],
    results: Sequence[CaseResult],
) -> dict[str, Any]:
    """Build an artifact only from a complete set of validated rows."""
    if len(results) != len(selected_cases):
        raise ValueError(
            "cannot build a completed report from a partial matrix: "
            f"expected {len(selected_cases)} rows, got {len(results)}"
        )
    expected_names = [case.name for case in selected_cases]
    result_names = [result.case.name for result in results]
    if result_names != expected_names:
        raise ValueError(
            "cannot build report from reordered or mismatched cases: "
            f"expected {expected_names}, got {result_names}"
        )
    if not all(result.semantic_count_agreement for result in results):
        raise ValueError(
            "cannot build a completed report with semantic-count disagreement"
        )
    below_minimum = [
        result.case.name
        for result in results
        if result.threshold_status != "met"
    ]
    gate_mode = "enforced" if configuration.fail_on_slower else "report-only"
    gate_passed = not below_minimum
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "tool": {"name": TOOL_NAME, "version": TOOL_VERSION},
        "run": {
            "suite": configuration.suite,
            "iterations": configuration.iterations,
            "samples": configuration.samples,
            "warmup_iterations": WARMUP_ITERATIONS,
            "cpu": configuration.cpu,
            "execution_order": list(EXECUTION_ORDER),
            "cangjie_executable": str(configuration.cangjie),
            "harfbuzz_executable": str(configuration.harfbuzz),
            "harfrust_manifest": str(configuration.harfrust_manifest),
            "harfrust_executable": str(configuration.harfrust_executable),
            "corpus_root": str(configuration.corpus_root),
            "fail_on_slower": configuration.fail_on_slower,
            "minimum_speedup": configuration.minimum_speedup,
        },
        "gate": {
            "mode": gate_mode,
            "minimum_speedup": configuration.minimum_speedup,
            "thresholds_met": gate_passed,
            "command_succeeded": gate_passed or not configuration.fail_on_slower,
        },
        "suite": {
            "name": configuration.suite,
            "cases": expected_names,
        },
        "cases": [case_result_json(result) for result in results],
        "summary": {
            "case_count": len(results),
            "thresholds_met_count": len(results) - len(below_minimum),
            "below_minimum_count": len(below_minimum),
            "below_minimum_cases": below_minimum,
            "semantic_count_agreement": all(
                result.semantic_count_agreement for result in results
            ),
        },
    }


@dataclass(frozen=True)
class MatrixOutcome:
    """Completed matrix data plus the gate diagnostics used by the CLI."""

    cases: tuple[Case, ...]
    results: tuple[CaseResult, ...]
    failures: tuple[str, ...]


def write_json_atomic(path: Path, report: Mapping[str, Any]) -> None:
    """Durably replace ``path`` without exposing a partial JSON document."""
    parent = path.parent
    # The destination directory must already exist: a typo should fail rather
    # than silently create an unexpected directory hierarchy.
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            dir=parent, prefix=f".{path.name}.", suffix=".tmp", text=True
        )
    except OSError as error:
        raise RuntimeError(
            f"cannot create JSON output for {path}: {error}"
        ) from error
    descriptor_open = True
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            descriptor_open = False
            json.dump(report, output, indent=2, sort_keys=True, allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        if descriptor_open:
            os.close(descriptor)
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def emit_json_report(
    path: Path | None,
    configuration: RunConfiguration,
    outcome: MatrixOutcome,
) -> None:
    """Write evidence for a completed outcome, if the caller requested it."""
    if path is None:
        return
    write_json_atomic(
        path,
        build_json_report(configuration, outcome.cases, outcome.results),
    )


def run_matrix(args: argparse.Namespace, harfrust: Path) -> MatrixOutcome:
    """Execute all selected rows and preserve their historic text output."""
    cases = cases_for_suite(args.suite)
    gate_mode = "enforced" if args.fail_on_slower else "report-only"
    failures: list[str] = []
    results: list[CaseResult] = []
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
        records = (
            run(cangjie_cmd, args.cpu),
            run(harfbuzz_cmd, args.cpu),
            run(harfrust_cmd, args.cpu),
            run(harfrust_cmd, args.cpu),
            run(harfbuzz_cmd, args.cpu),
            run(cangjie_cmd, args.cpu),
        )
        result = evaluate_case(
            case, records, args.iterations, args.samples, args.minimum_speedup
        )
        results.append(result)
        if gate_failed(
            result.speedup_vs_fastest_reference,
            args.minimum_speedup,
            args.fail_on_slower,
        ):
            failures.append(
                f"{case.name}: speedup "
                f"{result.speedup_vs_fastest_reference:.6f}x is below the "
                f"{args.minimum_speedup:.6f}x minimum"
            )
        print(
            f"{case.name}: "
            f"cangjie={result.cangjie.a_median_ns_per_glyph:.3f}/"
            f"{result.cangjie.b_median_ns_per_glyph:.3f} "
            f"harfbuzz={result.harfbuzz.a_median_ns_per_glyph:.3f}/"
            f"{result.harfbuzz.b_median_ns_per_glyph:.3f} "
            f"harfrust={result.harfrust.a_median_ns_per_glyph:.3f}/"
            f"{result.harfrust.b_median_ns_per_glyph:.3f} "
            f"speedup_vs_best={result.speedup_vs_fastest_reference:.6f}x "
            f"minimum_speedup={args.minimum_speedup:.6f}x "
            f"threshold={result.threshold_status} gate_mode={gate_mode} "
            f"glyphs={result.normalized_glyph_count}"
        )
    return MatrixOutcome(cases, tuple(results), tuple(failures))


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


def main(argv: Sequence[str] | None = None) -> int:
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
        "--json-output",
        type=Path,
        help=(
            "atomically write a versioned JSON artifact after every "
            "successful matrix, including report-only runs with rows below "
            "the threshold"
        ),
    )
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
    args = parser.parse_args(argv)
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
    outcome = run_matrix(args, harfrust)

    configuration = RunConfiguration(
        cangjie=args.cangjie,
        harfbuzz=args.harfbuzz,
        harfrust_manifest=args.harfrust_manifest,
        harfrust_executable=harfrust,
        corpus_root=args.corpus_root,
        suite=args.suite,
        iterations=args.iterations,
        samples=args.samples,
        cpu=args.cpu,
        fail_on_slower=args.fail_on_slower,
        minimum_speedup=args.minimum_speedup,
    )
    if outcome.failures:
        print(
            "Cangjie shaping performance matrix failed "
            f"(minimum_speedup={args.minimum_speedup:.6f}x):",
            file=sys.stderr,
        )
        for failure in outcome.failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    # Report-only rows below the threshold are successful completed runs.
    # Operational errors and enforced gate failures return before this write.
    emit_json_report(args.json_output, configuration, outcome)
    print(
        f"Cangjie/HarfBuzz/HarfRust shaping matrix completed: "
        f"{len(outcome.cases)} "
        f"corpora gate_mode={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
