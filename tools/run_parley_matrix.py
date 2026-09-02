#!/usr/bin/env python3
"""Run a cross-script Cangjie/Parley layout and reflow matrix."""

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


TOOL_NAME = "run_parley_matrix.py"
TOOL_VERSION = "1.0"
REPORT_SCHEMA_VERSION = 1
EXECUTION_ORDER = (
    "cangjie_a",
    "parley_a",
    "parley_b",
    "cangjie_b",
)


@dataclass(frozen=True)
class Case:
    name: str
    font: Path
    text: Path
    family: str
    width: str
    fallback_font: Path | None = None


@dataclass(frozen=True)
class MatrixRow:
    """One concrete row in the fixed 38-row execution manifest."""

    case: Case
    phase: str
    style: str
    requires_semantic_equality: bool
    requires_object_geometry: bool

    @property
    def identifier(self) -> str:
        return f"{self.case.name}/{self.phase}/{self.style}"


@dataclass(frozen=True)
class RowResult:
    """A fully evaluated row with auditable timing and checksum evidence."""

    row: MatrixRow
    text_bytes: int
    glyphs: int
    lines: int
    objects: int
    geometry_checksums: tuple[str | None, ...]
    placement_checksums: tuple[str | None, ...]
    object_checksums: tuple[str | None, ...]
    cangjie_checksums: tuple[str | None, str | None]
    parley_checksums: tuple[str | None, str | None]
    geometry_equal: bool
    placement_equal: bool
    object_geometry_equal: bool
    cangjie_checksum_stable: bool
    parley_checksum_stable: bool
    cangjie_a_median_ns_per_iter: float
    cangjie_b_median_ns_per_iter: float
    parley_a_median_ns_per_iter: float
    parley_b_median_ns_per_iter: float
    cangjie_geometric_mean_ns_per_iter: float
    parley_geometric_mean_ns_per_iter: float
    speedup: float
    threshold_status: str


@dataclass(frozen=True)
class RunConfiguration:
    """Inputs that define the machine-readable identity of a run."""

    cangjie: Path
    parley_manifest: Path
    parley_executable: Path
    parley_root: Path
    roboto: Path
    arabic_font: Path
    japanese_font: Path
    bidi_font: Path
    bidi_family: str
    fallback_font: Path
    iterations: int
    samples: int
    cpu: int | None
    fail_on_slower: bool
    minimum_speedup: float
    parley_vertical_api: bool


@dataclass(frozen=True)
class MatrixOutcome:
    """Completed matrix data plus the failure diagnostics used by the CLI."""

    rows: tuple[MatrixRow, ...]
    results: tuple[RowResult, ...]
    failures: tuple[str, ...]


# These rows have byte-addressable geometry and placement parity. Object rows
# intentionally use their separate object-geometry contract, while the other
# Japanese styles retain known line-breaking differences. Keeping this list
# explicit prevents a newly added coverage row from silently becoming a false
# semantic-equivalence claim.
SEMANTIC_EQUALITY_ROWS = frozenset(
    {
        ("latin", "layout", "default"),
        ("latin", "layout", "center"),
        ("latin", "reflow", "center"),
        ("latin", "layout", "spacing"),
        ("latin", "layout", "alternating"),
        ("latin", "reflow", "default"),
        ("arabic", "layout", "default"),
        ("arabic", "layout", "spacing"),
        ("arabic", "layout", "alternating"),
        ("arabic", "reflow", "default"),
        ("mixed-bidi-ltr", "layout", "default"),
        ("mixed-bidi-ltr", "reflow", "default"),
        ("mixed-bidi-rtl", "layout", "default"),
        ("mixed-bidi-rtl", "reflow", "default"),
        ("japanese", "layout", "alternating"),
        ("fallback", "layout", "fallback"),
        ("fallback", "reflow", "fallback"),
    }
)

DEFAULT_MINIMUM_SPEEDUP = 1.01


def valid_minimum_speedup(minimum_speedup: float) -> bool:
    """A benchmark margin must be finite and strictly better than parity."""
    return math.isfinite(minimum_speedup) and minimum_speedup > 1.0


def meets_speedup_gate(speedup: float, minimum_speedup: float) -> bool:
    """Return whether a measured ratio reaches the declared gate boundary."""
    return not math.isnan(speedup) and speedup >= minimum_speedup


def gate_failed(
    speedup: float, minimum_speedup: float, fail_on_slower: bool
) -> bool:
    """Keep threshold reporting independent from opt-in enforcement."""
    return fail_on_slower and not meets_speedup_gate(speedup, minimum_speedup)


def test_speedup_gate_boundary() -> None:
    minimum = DEFAULT_MINIMUM_SPEEDUP
    assert valid_minimum_speedup(minimum)
    assert not valid_minimum_speedup(1.0)
    assert not valid_minimum_speedup(math.inf)
    assert not valid_minimum_speedup(math.nan)
    # An exact minimum is a pass. Testing the adjacent lower float guards
    # against accidentally restoring the old parity-only comparison.
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


def run(command: list[str], cpu: int | None) -> dict[str, str]:
    if cpu is not None:
        command = ["taskset", "-c", str(cpu), *command]
    completed = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
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
            fields[key] = value
    return fields


def cangjie_command(
    executable: Path,
    case: Case,
    style: str,
    phase: str,
    iterations: int,
    samples: int,
) -> list[str]:
    command = [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.width, phase, "auto", style,
    ]
    if case.fallback_font is not None:
        command.append(str(case.fallback_font))
    return command


def parley_command(
    executable: Path,
    case: Case,
    style: str,
    phase: str,
    iterations: int,
    samples: int,
) -> list[str]:
    command = [
        str(executable), str(case.font), str(case.text), str(iterations),
        str(samples), case.family, case.width, "auto", style, phase,
    ]
    if case.fallback_font is not None:
        command.append(str(case.fallback_font))
    return command


def build_matrix_rows(args: argparse.Namespace) -> tuple[MatrixRow, ...]:
    """Return the fixed 38-row manifest in the exact execution order."""
    samples_root = args.parley_root / "parley_dev/assets/text_samples"
    cases = (
        Case("latin", args.roboto, samples_root / "latin.txt", "Roboto", "200"),
        Case(
            "arabic",
            args.arabic_font,
            samples_root / "arabic.txt",
            "Noto Kufi Arabic",
            "180",
        ),
        Case(
            "japanese",
            args.japanese_font,
            samples_root / "japanese.txt",
            "Noto Sans CJK JP",
            "200",
        ),
        Case(
            "mixed-bidi-ltr",
            args.bidi_font,
            Path("tests/data/parley-mixed-bidi-ltr.txt"),
            args.bidi_family,
            "220",
        ),
        Case(
            "mixed-bidi-rtl",
            args.bidi_font,
            Path("tests/data/parley-mixed-bidi-rtl.txt"),
            args.bidi_family,
            "220",
        ),
        Case(
            "fallback",
            args.roboto,
            Path("tests/data/parley-fallback.txt"),
            "Roboto",
            "200",
            args.fallback_font,
        ),
    )
    center_case = Case(
        "latin",
        args.roboto,
        Path("tests/data/parley-center-latin.txt"),
        "Roboto",
        "200",
    )
    rows: list[MatrixRow] = []
    for case in cases:
        if case.name == "fallback":
            phase_style_pairs = (("layout", "fallback"), ("reflow", "fallback"))
        elif case.name.startswith("mixed-bidi-"):
            # Keep this differential focused on the base-direction resolver and
            # visual ordering. Styling and inline-object coverage use fixtures
            # whose source-order contracts are independent of mixed bidi.
            phase_style_pairs = (("layout", "default"), ("reflow", "default"))
        else:
            mutable_pairs = [
                ("layout", "default"),
                ("layout", "spacing"),
                ("layout", "alternating"),
                ("reflow", "default"),
                ("layout", "inline-object"),
                ("reflow", "inline-object"),
                ("layout", "out-of-flow-object"),
                ("reflow", "out-of-flow-object"),
                ("layout", "custom-out-of-flow-object"),
                ("reflow", "custom-out-of-flow-object"),
            ]
            if case.name == "latin":
                mutable_pairs.insert(1, ("layout", "center"))
                mutable_pairs.insert(2, ("reflow", "center"))
            phase_style_pairs = tuple(mutable_pairs)
        for phase, style in phase_style_pairs:
            row_case = center_case if style == "center" else case
            rows.append(
                MatrixRow(
                    case=row_case,
                    phase=phase,
                    style=style,
                    requires_semantic_equality=(
                        (case.name, phase, style) in SEMANTIC_EQUALITY_ROWS
                    ),
                    requires_object_geometry=style in (
                        "inline-object",
                        "out-of-flow-object",
                        "custom-out-of-flow-object",
                    ),
                )
            )
    return tuple(rows)


def _shared_shape(
    records: Sequence[Mapping[str, str]],
) -> tuple[int, int, int, int] | None:
    shapes = {
        (
            item.get("text_bytes"),
            item.get("glyphs"),
            item.get("lines"),
            item.get("objects"),
        )
        for item in records
    }
    if len(shapes) != 1:
        return None
    text_bytes, glyphs, lines, objects = next(iter(shapes))
    if None in (text_bytes, glyphs, lines, objects):
        return None
    return (int(text_bytes), int(glyphs), int(lines), int(objects))


def _raw_shapes(
    records: Sequence[Mapping[str, str]],
) -> tuple[tuple[str | None, str | None, str | None, str | None], ...]:
    return tuple(
        (
            item.get("text_bytes"),
            item.get("glyphs"),
            item.get("lines"),
            item.get("objects"),
        )
        for item in records
    )


def _checksum_equivalent(checksums: tuple[str | None, ...]) -> bool:
    return len(set(checksums)) == 1 and None not in checksums


def _native_checksum_stable(
    first: str | None, second: str | None
) -> bool:
    return (
        first is not None
        and second is not None
        and first != "0000000000000000"
        and first == second
    )


def evaluate_row(
    row: MatrixRow,
    records: Sequence[Mapping[str, str]],
    minimum_speedup: float,
) -> tuple[RowResult, tuple[str, ...]]:
    """Evaluate one row without performing any subprocess work."""
    if len(records) != len(EXECUTION_ORDER):
        raise ValueError(
            f"{row.identifier}: expected {len(EXECUTION_ORDER)} endpoint "
            f"records, got {len(records)}"
        )

    cangjie_first, parley_first, parley_second, cangjie_second = records
    shared_shape = _shared_shape(records)
    raw_shapes = _raw_shapes(records)
    if shared_shape is None:
        text_bytes = int(cangjie_first.get("text_bytes", "0"))
        glyphs = int(cangjie_first.get("glyphs", "0"))
        lines = int(cangjie_first.get("lines", "0"))
        objects = int(cangjie_first.get("objects", "0"))
    else:
        text_bytes, glyphs, lines, objects = shared_shape

    geometry_checksums = tuple(
        record.get("geometry_checksum") for record in records
    )
    placement_checksums = tuple(
        record.get("placement_checksum") for record in records
    )
    object_checksums = tuple(
        record.get("object_checksum") for record in records
    )
    cangjie_checksums = (
        cangjie_first.get("checksum"),
        cangjie_second.get("checksum"),
    )
    parley_checksums = (
        parley_first.get("checksum"),
        parley_second.get("checksum"),
    )
    geometry_equal = _checksum_equivalent(geometry_checksums)
    placement_equal = _checksum_equivalent(placement_checksums)
    object_geometry_equal = _checksum_equivalent(object_checksums)
    cangjie_checksum_stable = _native_checksum_stable(*cangjie_checksums)
    parley_checksum_stable = _native_checksum_stable(*parley_checksums)

    cangjie_a = float(cangjie_first["median_ns_per_iter"])
    cangjie_b = float(cangjie_second["median_ns_per_iter"])
    parley_a = float(parley_first["median_ns_per_iter"])
    parley_b = float(parley_second["median_ns_per_iter"])
    cangjie_ns = math.sqrt(cangjie_a * cangjie_b)
    parley_ns = math.sqrt(parley_a * parley_b)
    speedup = math.inf if cangjie_ns == 0 else parley_ns / cangjie_ns
    threshold_status = (
        "met"
        if meets_speedup_gate(speedup, minimum_speedup)
        else "below-minimum"
    )

    failures: list[str] = []
    if shared_shape is None:
        failures.append(
            f"{row.identifier}: output counts="
            f"{sorted(raw_shapes)}"
        )
    expected_objects = "1" if row.requires_object_geometry else "0"
    if any(record.get("objects") != expected_objects for record in records):
        failures.append(
            f"{row.identifier}: expected objects={expected_objects}, "
            f"got {[record.get('objects') for record in records]}"
        )
    if row.requires_semantic_equality and not geometry_equal:
        failures.append(
            f"{row.identifier}: geometry checksums="
            f"{[record.get('geometry_checksum') for record in records]}"
        )
    if row.requires_semantic_equality and not placement_equal:
        failures.append(
            f"{row.identifier}: placement checksums="
            f"{[record.get('placement_checksum') for record in records]}"
        )
    if row.requires_object_geometry and not object_geometry_equal:
        failures.append(
            f"{row.identifier}: object checksums="
            f"{[record.get('object_checksum') for record in records]}"
        )
    if not cangjie_checksum_stable:
        failures.append(
            f"{row.identifier}: cangjie checksum="
            f"{cangjie_checksums[0]!r}/{cangjie_checksums[1]!r}"
        )
    if not parley_checksum_stable:
        failures.append(
            f"{row.identifier}: parley checksum="
            f"{parley_checksums[0]!r}/{parley_checksums[1]!r}"
        )

    result = RowResult(
        row=row,
        text_bytes=text_bytes,
        glyphs=glyphs,
        lines=lines,
        objects=objects,
        geometry_checksums=geometry_checksums,
        placement_checksums=placement_checksums,
        object_checksums=object_checksums,
        cangjie_checksums=cangjie_checksums,
        parley_checksums=parley_checksums,
        geometry_equal=geometry_equal,
        placement_equal=placement_equal,
        object_geometry_equal=object_geometry_equal,
        cangjie_checksum_stable=cangjie_checksum_stable,
        parley_checksum_stable=parley_checksum_stable,
        cangjie_a_median_ns_per_iter=cangjie_a,
        cangjie_b_median_ns_per_iter=cangjie_b,
        parley_a_median_ns_per_iter=parley_a,
        parley_b_median_ns_per_iter=parley_b,
        cangjie_geometric_mean_ns_per_iter=cangjie_ns,
        parley_geometric_mean_ns_per_iter=parley_ns,
        speedup=speedup,
        threshold_status=threshold_status,
    )
    return result, tuple(failures)


def _row_manifest_json(row: MatrixRow) -> dict[str, Any]:
    return {
        "id": row.identifier,
        "name": row.case.name,
        "phase": row.phase,
        "style": row.style,
        "font": str(row.case.font),
        "text": str(row.case.text),
        "family": row.case.family,
        "width": row.case.width,
        "fallback_font": (
            None if row.case.fallback_font is None else str(row.case.fallback_font)
        ),
        "requires_semantic_equality": row.requires_semantic_equality,
        "requires_object_geometry": row.requires_object_geometry,
    }


def _row_result_json(result: RowResult) -> dict[str, Any]:
    return {
        **_row_manifest_json(result.row),
        "counts": {
            "text_bytes": result.text_bytes,
            "glyphs": result.glyphs,
            "lines": result.lines,
            "objects": result.objects,
        },
        "timings_ns_per_iter": {
            "execution_order": list(EXECUTION_ORDER),
            "endpoint_medians": {
                "cangjie": {
                    "a": result.cangjie_a_median_ns_per_iter,
                    "b": result.cangjie_b_median_ns_per_iter,
                },
                "parley": {
                    "a": result.parley_a_median_ns_per_iter,
                    "b": result.parley_b_median_ns_per_iter,
                },
            },
            "geometric_means": {
                "cangjie": result.cangjie_geometric_mean_ns_per_iter,
                "parley": result.parley_geometric_mean_ns_per_iter,
            },
        },
        "checksums": {
            "geometry": list(result.geometry_checksums),
            "placement": list(result.placement_checksums),
            "object": list(result.object_checksums),
            "native": {
                "cangjie": list(result.cangjie_checksums),
                "parley": list(result.parley_checksums),
            },
        },
        "equalities": {
            "geometry": result.geometry_equal,
            "placement": result.placement_equal,
            "object_geometry": result.object_geometry_equal,
            "cangjie_native_stable": result.cangjie_checksum_stable,
            "parley_native_stable": result.parley_checksum_stable,
        },
        "speedup": result.speedup,
        "threshold_status": result.threshold_status,
    }


def build_json_report(
    configuration: RunConfiguration,
    selected_rows: Sequence[MatrixRow],
    results: Sequence[RowResult],
    failures: Sequence[str],
) -> dict[str, Any]:
    """Build an artifact only from a complete set of validated rows."""
    if len(results) != len(selected_rows):
        raise ValueError(
            "cannot build a completed report from a partial matrix: "
            f"expected {len(selected_rows)} rows, got {len(results)}"
        )
    expected_ids = [row.identifier for row in selected_rows]
    result_ids = [result.row.identifier for result in results]
    if result_ids != expected_ids:
        raise ValueError(
            "cannot build report from reordered or mismatched rows: "
            f"expected {expected_ids}, got {result_ids}"
        )
    gate_mode = "enforced" if configuration.fail_on_slower else "report-only"
    below_minimum = [
        result.row.identifier
        for result in results
        if result.threshold_status != "met"
    ]
    thresholds_met = not below_minimum
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "tool": {"name": TOOL_NAME, "version": TOOL_VERSION},
        "config": {
            "cangjie_executable": str(configuration.cangjie),
            "parley_manifest": str(configuration.parley_manifest),
            "parley_executable": str(configuration.parley_executable),
            "parley_root": str(configuration.parley_root),
            "roboto": str(configuration.roboto),
            "arabic_font": str(configuration.arabic_font),
            "japanese_font": str(configuration.japanese_font),
            "bidi_font": str(configuration.bidi_font),
            "bidi_family": configuration.bidi_family,
            "fallback_font": str(configuration.fallback_font),
            "iterations": configuration.iterations,
            "samples": configuration.samples,
            "cpu": configuration.cpu,
            "execution_order": list(EXECUTION_ORDER),
            "fail_on_slower": configuration.fail_on_slower,
            "minimum_speedup": configuration.minimum_speedup,
            "parley_vertical_api": configuration.parley_vertical_api,
        },
        "gate": {
            "mode": gate_mode,
            "minimum_speedup": configuration.minimum_speedup,
            "thresholds_met": thresholds_met,
            "command_succeeded": (
                thresholds_met or not configuration.fail_on_slower
            ),
        },
        "manifest": {
            "row_count": len(selected_rows),
            "rows": [_row_manifest_json(row) for row in selected_rows],
        },
        "rows": [_row_result_json(result) for result in results],
        "summary": {
            "row_count": len(results),
            "thresholds_met_count": len(results) - len(below_minimum),
            "below_minimum_count": len(below_minimum),
            "below_minimum_rows": below_minimum,
            "failure_count": len(failures),
            "failures": list(failures),
        },
    }


def write_json_atomic(path: Path, report: Mapping[str, Any]) -> None:
    """Durably replace ``path`` without exposing a partial JSON document."""
    parent = path.parent
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
        build_json_report(
            configuration, outcome.rows, outcome.results, outcome.failures
        ),
    )


def run_matrix(args: argparse.Namespace, parley: Path) -> MatrixOutcome:
    """Execute all rows while preserving the historical text output."""
    rows = build_matrix_rows(args)
    gate_mode = "enforced" if args.fail_on_slower else "report-only"
    failures: list[str] = []
    results: list[RowResult] = []
    for row in rows:
        records = (
            run(
                cangjie_command(
                    args.cangjie,
                    row.case,
                    row.style,
                    row.phase,
                    args.iterations,
                    args.samples,
                ),
                args.cpu,
            ),
            run(
                parley_command(
                    parley,
                    row.case,
                    row.style,
                    row.phase,
                    args.iterations,
                    args.samples,
                ),
                args.cpu,
            ),
            run(
                parley_command(
                    parley,
                    row.case,
                    row.style,
                    row.phase,
                    args.iterations,
                    args.samples,
                ),
                args.cpu,
            ),
            run(
                cangjie_command(
                    args.cangjie,
                    row.case,
                    row.style,
                    row.phase,
                    args.iterations,
                    args.samples,
                ),
                args.cpu,
            ),
        )
        result, row_failures = evaluate_row(row, records, args.minimum_speedup)
        results.append(result)
        failures.extend(row_failures)
        if gate_failed(result.speedup, args.minimum_speedup, args.fail_on_slower):
            failures.append(
                f"{row.identifier}: speedup {result.speedup:.6f}x "
                f"is below the {args.minimum_speedup:.6f}x minimum"
            )
        print(
            f"{row.identifier}: "
            f"cangjie_ns={result.cangjie_a_median_ns_per_iter:.3f}/"
            f"{result.cangjie_b_median_ns_per_iter:.3f} "
            f"parley_ns={result.parley_a_median_ns_per_iter:.3f}/"
            f"{result.parley_b_median_ns_per_iter:.3f} "
            f"speedup={result.speedup:.6f}x "
            f"minimum_speedup={args.minimum_speedup:.6f}x "
            f"threshold={result.threshold_status} gate_mode={gate_mode} "
            f"glyphs={result.glyphs} "
            f"lines={result.lines} "
            f"objects={result.objects} "
            f"geometry_equal={str(result.geometry_equal).lower()} "
            f"placement_equal="
            f"{str(result.placement_equal).lower() if row.requires_semantic_equality else 'n/a'} "
            f"object_geometry_equal="
            f"{str(result.object_geometry_equal).lower() if row.requires_object_geometry else 'n/a'}"
        )
    return MatrixOutcome(tuple(rows), tuple(results), tuple(failures))


def main(argv: Sequence[str] | None = None) -> int:
    test_speedup_gate_boundary()
    parser = argparse.ArgumentParser()
    parser.add_argument("--cangjie", required=True, type=Path)
    parser.add_argument("--parley-manifest", required=True, type=Path)
    parser.add_argument("--parley-root", required=True, type=Path)
    parser.add_argument("--roboto", required=True, type=Path)
    parser.add_argument("--arabic-font", required=True, type=Path)
    parser.add_argument("--japanese-font", required=True, type=Path)
    parser.add_argument(
        "--bidi-font",
        type=Path,
        default=Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
        help="font covering the Latin, Arabic, and Hebrew mixed-bidi fixture",
    )
    parser.add_argument(
        "--bidi-family",
        default="DejaVu Sans",
        help="family name registered by --bidi-font in the Parley oracle",
    )
    parser.add_argument(
        "--fallback-font",
        type=Path,
        default=Path(
            "/usr/share/fonts/truetype/noto/"
            "NotoSansDevanagari-Regular.ttf"
        ),
    )
    parser.add_argument("--iterations", type=int, default=1)
    parser.add_argument("--samples", type=int, default=1)
    parser.add_argument("--cpu", type=int)
    parser.add_argument(
        "--json-output",
        type=Path,
        help=(
            "atomically write a versioned JSON artifact after every "
            "successful completed matrix, including report-only runs with "
            "rows below the threshold"
        ),
    )
    parser.add_argument(
        "--fail-on-slower",
        action="store_true",
        help=(
            "fail when Cangjie does not meet --minimum-speedup in any "
            "matrix row"
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
    for label, path in (
        ("--roboto", args.roboto),
        ("--arabic-font", args.arabic_font),
        ("--japanese-font", args.japanese_font),
        ("--bidi-font", args.bidi_font),
        ("--fallback-font", args.fallback_font),
    ):
        if not path.is_file():
            parser.error(f"{label} does not name a readable font file: {path}")

    gate_mode = "enforced" if args.fail_on_slower else "report-only"
    print(
        f"parley_performance_gate={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )
    # Parley 0.7's public Layout/Builder surface is horizontal-only: it has no
    # writing-mode or vertical-flow input. Keep vertical Cangjie evidence in
    # its conformance suite rather than fabricating a rotated horizontal row.
    parley_vertical_api = False

    subprocess.run(
        ["cargo", "build", "--release", "--quiet",
         "--manifest-path", str(args.parley_manifest)],
        check=True,
    )
    parley = args.parley_manifest.parent / "target/release/parley-layout-oracle"
    outcome = run_matrix(args, parley)

    configuration = RunConfiguration(
        cangjie=args.cangjie,
        parley_manifest=args.parley_manifest,
        parley_executable=parley,
        parley_root=args.parley_root,
        roboto=args.roboto,
        arabic_font=args.arabic_font,
        japanese_font=args.japanese_font,
        bidi_font=args.bidi_font,
        bidi_family=args.bidi_family,
        fallback_font=args.fallback_font,
        iterations=args.iterations,
        samples=args.samples,
        cpu=args.cpu,
        fail_on_slower=args.fail_on_slower,
        minimum_speedup=args.minimum_speedup,
        parley_vertical_api=parley_vertical_api,
    )
    if outcome.failures:
        print(
            "Cangjie/Parley matrix failed "
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
        "Cangjie/Parley output-count, proven text-semantics, and object-geometry "
        f"matrix passed: {len(outcome.rows)} cases gate_mode={gate_mode} "
        f"minimum_speedup={args.minimum_speedup:.6f}x"
    )
    print(f"parley_vertical_api={str(parley_vertical_api).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
